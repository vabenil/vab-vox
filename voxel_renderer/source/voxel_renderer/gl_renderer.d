/+
    NOTE: Since anyway, currently I'm planning on re-creating chunk meshes whenever a chunk changes,
    I might as well only store the header with the information about the meshes and delete the meshes from the
    GPU.
    Though I guess for the temporary meshes, I gotta keep those on the GPU
+/
module voxel_renderer.gl_renderer;

public import voxel_renderer.renderer;

/* I call this gl_renderer, but honestly
   this renderer is kinda independant from opengl

   I could just call it voxel_renderer and it would still work
*/
import core.bitop       : bt, btr, bts;
import std.bitmanip;
import std.typecons     : Tuple, tuple;

import voxel_renderer.gl_device;

import voxel_grid.world;
import voxel_grid.chunk;
import voxel_grid.bitchunk;

import common           : ivec3, vec3, Color4b;
import std.typecons     : Optional = Nullable, optional = nullable;


private enum int[3][3] mat3_identity = [
    [1, 0, 0],
    [0, 1, 0],
    [0, 0, 1],
];

enum ulong MAG  = 5;
alias BitChunk = VoxelBitChunk!(BitVoxel, MAG);

// SIZE of the chunk header / maximum count of chunks to hold in gpu for perm
// storage
private enum int CHUNK_HEADER_CAP = 0x1000;

// safe as long as data can store enough bits to fit index
@nogc nothrow
static ubyte set_bit(ubyte* data, ulong index, bool value)
/* in(index < (data.length << 3)) */
    => cast(ubyte)(
            value
                ? bts(cast(ulong*)data, index)
                : btr(cast(ulong*)data, index)
        );

private alias MemRange = Tuple!(int, "start", int, "end");

int mem_size(MemRange range) pure => range.end - range.start;

import utils.chunksheader;
// A vertex is the same as a face mesh
// Contains all vertex data
struct MeshContainer
{
    import utils.memheader;
    import std.typecons : Tuple, tuple;
    /*
       IDEA: Maybe use two vbos. One for far away things

       Rar away chunks close to 0:
        - Since this will be swapped more often and won't require extra allocations
       Close chunks close to $;
   */

    /*
        TODO: Right now the header contains information about the state in memory of the CPU,
        not GPU
    */
    // I guess I will need a simpler header for the second vbo, perhaps only the size
    ChunksHeader chunks_header; // contains info on what arrays are bound to what places
    ChunksHeader tmp_chunks_header;

    MemHeader cpu_header;
    MemHeader tmp_header; // NOTE: might be unnecessary

    /*
       `face_meshes` is a buffer of faces for voxels inside multiple chunks.

       chunks_header - Keeps track of memory of the main buffer
       chunks_header - Keeps track of memory of the tmp buffer

       main buffer contains chunks that will stay cached in memory
       tmp buffer contains chunks that will be streamed to be rendered

       This both buffers data will be stored inside `face_meshes`
    */
    VoxelVertex[] face_meshes; // tracked by cpu_header

    // Add a queue of chunks to send to the GPU
    // Add gpu header here

    int max_face_count = 0;
    int max_tmp_face_count = 0;
    int reserved_chunks = 0; // chunks reserved for tmp

    int buff_size = 0; // 1 unit = `VoxelVertex`
    VoxelVertex[] tmp_chunk_buffer;

    @disable this();

    // Count, is the count of chunks for which it's chunk buffer will be stored
    this(uint count, uint max_chunk_face_count) in (count > 0)
    {
        this.max_face_count = (count - 1) * max_chunk_face_count;
        this.max_tmp_face_count = 1 * max_chunk_face_count;

        this.face_meshes.length = count * max_chunk_face_count;

        this.cpu_header = MemHeader(this.max_face_count);
        this.tmp_header = MemHeader(this.max_tmp_face_count);

        this.chunks_header = ChunksHeader(CHUNK_HEADER_CAP);
        this.tmp_chunks_header = ChunksHeader(CHUNK_HEADER_CAP);

        if (tmp_chunk_buffer.length == 0) {
            // TODO: Use `tmp_header` here instead
            this.tmp_chunk_buffer = new VoxelVertex[](max_chunk_face_count);
        }
    }

    // NOTE: It's better to push chunks at the end when they are far away,
    // because it's easier to remove chunks at the end of the buffer

    // Append to tmp chunk
    void push_face(VoxelVertex face)
    {
        if (buff_size < tmp_chunk_buffer.length)
            tmp_chunk_buffer[buff_size++] = face;
    }

    void clean_tmp() { tmp_chunk_buffer.length = 0; }

    // Adds a chunk to the header and return index of header
    // Also add chunk to vertex buffer
    // IMPORTANT: This function doesn't check whether is already in header
    int push_chunk(ivec3 chunk_pos)
    {
        import std.stdio;
        // out of memory
        if (this.chunks_header.is_full()) {
            debug {
                writeln("[WARNING]: Out of memory");
            }
            return ChunksHeader.NULL_ID;
        }

        // TODO: Create a ChunkInfo first and append later
        int mem_start = this.cpu_header.allocate(this.buff_size);

        // Not enough space on main buffer try allocate in tmp
        if (mem_start == -1)
            return this.push_tmp_chunk(chunk_pos);

        int header_id = this.chunks_header.append(
            ChunkInfo(
                coords: chunk_pos.array,
                index: mem_start,
                size: this.buff_size,
                modified: true
            )
        );

        face_meshes[mem_start..mem_start+this.buff_size] = tmp_chunk_buffer[0..buff_size];

        this.buff_size = 0; // Reset tmp buffer

        return header_id;
    }

    // NOTE: Not READY FOR USAGE
    int push_tmp_chunk(ivec3 chunk_pos)
    {
        import std.stdio;
        // tmp part of the buffer starts at the end
        int offset = this.tmp_header.quick_allocate(this.buff_size);

        // Not enough space in tmp buffer
        if (offset == -1) {
            return ChunksHeader.NULL_ID;
        }

        offset += this.cpu_header.capacity;

        int header_id = this.tmp_chunks_header.append(
            ChunkInfo(
                coords: chunk_pos.array,
                index: offset,
                size: this.buff_size,
                modified: true
            )
        );
        face_meshes[offset..offset+this.buff_size] = tmp_chunk_buffer[0..buff_size];
        this.buff_size = 0;

        return header_id;
    }

    void clear_tmp()
    {
        this.tmp_chunks_header.clear();
        this.tmp_header.clear();
    }

    Optional!ChunkRef get_chunk_header(ivec3 cpos)
    {
        int id = this.chunks_header.find(cpos.array);

        if (id == ChunksHeader.NULL_ID) {
            id = this.tmp_chunks_header.find(cpos.array);
            if (id == ChunksHeader.NULL_ID)
                return Optional!ChunkRef();
            return this.tmp_chunks_header[id].optional;
        }
        return this.chunks_header[id].optional;
    }

    /* void free_chunk(ivec3 chunk_pos) */
    /* { */
    /*     for (int i = 0; i < this.header.count; i++) { */
    /*         if (this.header.coords[i] == chunk_pos) { */

    /*         } */
    /*     } */
    /* } */

    ulong vertex_buffer_size() const pure => face_meshes.length * VoxelVertex.sizeof;

    void[] get_buffer() const => cast(void[])this.face_meshes;

    void[] get_chunk_buffer(ChunkInfo info)
        => cast(void[])this.face_meshes[info.index..info.end];

    void[] get_chunk_buffer(int index)
        => get_chunk_buffer(this.chunks_header[index].info);
}

class VoxelRenderer(ChunkT)
{
    alias VoxelT = ChunkT.VoxelType;

    /* NOTES:

       For this I have a 2 choices:
        - Static
        - Dynamic

        **Static**: I allocate a buffer with a static ammount of space per chunk
            - Cons:
                + A lot of extra space will be allocated per chunk
                + very parallel friendly
            - Pros:
                + Simple, and will require only 1 allocation in the GPU(Provided all the data fits)

        **Dynamic**: I allocate a buffer with a dynamamic amount of space per chunk
            - Pros:
                + Will use significanly less memory
            + Cons:
                + Anytime a new chunk is modified it *may* require an additional allocation
                + Requires me to keep track of all chunk meshes
                + Not as parallel friendly

        **Solution**: Use a hybrid of dynamic and static
   */
    MeshContainer mesh_buffer;
    /* private MeshContainer mesh_buffer; */
    private GLDevice device;

    this(GLDevice device)
    {
        enum int chunk_size = ChunkT.voxel_count * 6 / 2;
        this.device = device;
        this.mesh_buffer = MeshContainer(4, chunk_size);
    }

    GLDevice get_device() => device;

    void set_camera(vec3 pos, vec3 dir, vec3 up) {}

    // NOTE: This has no effect if `commit_chunk` is not used
    void create_face_mesh(Color4b color, int face_id, ivec3 pos)
    {
        mesh_buffer.push_face(VoxelVertex(pos, color, face_id));
    }

    // For the time being we don't cache the chunk, so we 
    // must recalculate all chunk meshes
    // TODO: Use Bit chunk here
    void create_voxel_mesh(ref const ChunkT chunk, ivec3 pos)
    {
        VoxelT voxel = chunk[pos.array];
        if (voxel.data == 0)
            return; // voxel is empty

        int face_id = 0;
        ivec3 adj_pos;

        static foreach (s_bit; 0..2)
        static foreach (i; 0..3)
        {
            adj_pos = ivec3(mat3_identity[i]);
            adj_pos = adj_pos * (s_bit * 2 - 1); // by sign
            adj_pos = adj_pos + pos;

            if (!chunk.in_bounds(adj_pos.array) || chunk[adj_pos.array].is_empty()) {
                create_face_mesh(Color4b(voxel.data), face_id, pos);
            }
            face_id++;
        }
    }

    void create_chunk_mesh(ref const ChunkT chunk, ivec3 cpos)
    {
        for (int k = 0; k < ChunkT.size; k++)
        for (int j = 0; j < ChunkT.size; j++)
        for (int i = 0; i < ChunkT.size; i++)
            create_voxel_mesh(chunk, ivec3(i, j, k));
    }

    // Will try to create meshes, if mesh can't be created
    // it will be stored for creating later & rendering later
    void commit_chunk(ref const ChunkT chunk, ivec3 cpos)
    {
        create_chunk_mesh(chunk, cpos);
        mesh_buffer.push_chunk(cpos);
    }

    int commit_tmp_chunk(ref const ChunkT chunk, ivec3 cpos)
    {
        create_chunk_mesh(chunk, cpos);
        return mesh_buffer.push_tmp_chunk(cpos);
    }


    void allocate_buffers()
    {
        device.allocate_main_buffer(mesh_buffer.vertex_buffer_size());
    }

    // NOTE: I could call this shit "sync". That sounds better
    void send_tmp_to_device()
    {
        import std.stdio;
        debug writeln("### Sending chunks to tmp buffer...");
        // render tmp if exists
        foreach (ChunkRef chunk_ref; mesh_buffer.tmp_chunks_header) {
            debug writeln("send ", chunk_ref.info, " to device"); 

            void[] buffer_slice = mesh_buffer.get_chunk_buffer(chunk_ref.info);
            if (chunk_ref.modified) {
                device.send_to_main_buffer(chunk_ref.index * VoxelVertex.sizeof, buffer_slice);
                chunk_ref.modified = false;
            }
        }

        debug writeln("### ALL tmp chunks sent");
    }

    void send_to_device()
    {
        foreach (ChunkRef chunk_ref; mesh_buffer.chunks_header) {
            void[] buffer_slice = mesh_buffer.get_chunk_buffer(chunk_ref.info);
            if (chunk_ref.modified) {
                device.send_to_main_buffer(chunk_ref.index * VoxelVertex.sizeof, buffer_slice);
                chunk_ref.modified = false;
            }
        }

        send_tmp_to_device();
    }

    /* void commit_chunk(ref const BitChunk bit_chunk, ref const ChunkT chunk, ivec3 cpos) {} */

    void commit_voxel(VoxelT voxel, ivec3 pos)
    {
        static foreach (s_bit; 0..2)
        static foreach (i; 0..3) {
            create_face_mesh(Color4b(voxel.data), 3 * !(s_bit) + i, pos);
        }
    }

    void render_header(ref ChunksHeader header)
    {
        // TODO: Stop using magic numbers!!!
        // TODO: We have to swap and do a bunch of bs
        foreach (ChunkRef chunk_ref; header) {
            if (chunk_ref.queued) {
                // Add this chunk to a batch
                render_cached_chunk(chunk_ref.info);
                chunk_ref.queued = false;
            }
        }
    }

    void render_indirect_header()
    {
        import std.array        : array;
        import std.range        : chain;
        import std.algorithm    : filter, map;

        auto draw_commands = create_indirect_draw_commands();
        int[4][] chunk_coords =
            chain(this.mesh_buffer.chunks_header[], this.mesh_buffer.tmp_chunks_header[])
                .filter!(info => info.queued)
                .map!(info => ivec4(info.coords[0], info.coords[1], info.coords[2], 0).array).array();

        this.device.send_chunk_coords(chunk_coords);
        this.device.set_chunk_count(cast(int)chunk_coords.length);
        this.device.set_chunk_size(ChunkT.size);
        this.device.multi_render_indirect(draw_commands);
    }

    // TODO: No way to render chunks in batches yet, Fix that
    /// Render everything in tmp buffer and clear it
    void flush()
    {
        /* import std.stdio; */
        /* writeln("chunk headers free: ", mesh_buffer.tmp_chunks_header.unused); */
        send_tmp_to_device(); // make sure tmp buffers are on device

        // TODO: This function could be called render_cached
        render_header(this.mesh_buffer.tmp_chunks_header);
        this.mesh_buffer.clear_tmp();
    }

    void render_cached_chunk(ChunkInfo info) // should be private
    {
        this.device.set_chunk_pos(ivec3(info.coords));
        this.device.set_chunk_size(ChunkT.size);
        this.device.render(info.index, info.size);
    }

    // TODO: Make a proper render queue, with rendering commands,
    // for rendering chunks in batches
    // TODO: Searching for a chunk_header is kinda of a pain. Make that easier
    /// Queue chunk for rendering may
    void queue_chunk(ivec3 cpos, ref ChunkT chunk)
    {
        Optional!ChunkRef cached = this.mesh_buffer.get_chunk_header(cpos);

        if (!cached.isNull) {
            cached.get.queued = true;
        }
        else { // Chunk is not cached
            int id = this.commit_tmp_chunk(chunk, cpos);

            if (id == ChunksHeader.NULL_ID) { // not enough space
                this.flush();
                // the mesh is already created, just try to alllocate it on header
                id = this.mesh_buffer.push_tmp_chunk(cpos);
                assert(id != ChunksHeader.NULL_ID);
            }

            this.send_tmp_to_device();
            this.mesh_buffer.tmp_chunks_header[id].queued = true;
        }
    }

    void render()
    {
        render_indirect_header();
        // Render main buffer
        /* render_header(this.mesh_buffer.chunks_header); */
        // Render tmp
        /* render_header(this.mesh_buffer.tmp_chunks_header); */
    }

    // TODO: Perhaps put rendering commands in different places
    auto create_indirect_draw_commands()
    {
        import std.range            : chain;
        import utils.capedarray;
        // TODO: Maybe preallocate this shit on class init or smth
        // Can't batch render more than 256 render commands

        // NOTE: GC
        static DrawElementsIndirectCommand[] draw_commands;
        draw_commands.length = 0; // set length to 0, since it's static

        // We gotta render the shit in temporal chunk
        // And in non-temp
        // TODO: To avoid unnessary extra calculation in chunk and shit I should
        // just make a draw rendering list. Which contains which chunks
        // need to be rendered. It Could contain ChunkRef, or just something
        // that points at the fucking chunk headers

        auto chunks_headers = chain(this.mesh_buffer.chunks_header[], this.mesh_buffer.tmp_chunks_header[]);
        // Use chain or something
        foreach (ChunkRef chunk_ref; chunks_headers) {
            if (chunk_ref.queued) {
                draw_commands ~= DrawElementsIndirectCommand(
                    count: 6,
                    instance_count: chunk_ref.size,
                    index: 0,
                    base_vertex: 0, base_instance: chunk_ref.index
                );
            }
        }

        // Send commands to the GL_DRAW_INDIRECT_BUFFER buffer

        return draw_commands[];
    }

    /* void render(uint start, uint count) => device.render(start, count); */

    /++
        Render chunk in `cpos`. Requires passing `chunk` in case mesh is not
        cached
    +/
    void render_chunk(ivec3 cpos, ref ChunkT chunk)
    {
        ChunkRef chunk_ref = void;
        Optional!ChunkRef cached = this.mesh_buffer.get_chunk_header(cpos);

        if (!cached.isNull) {
            chunk_ref = cached.get;
        }
        else { // Chunk is not cached
            this.flush();

            int id = this.commit_tmp_chunk(chunk, cpos);
            this.send_tmp_to_device();

            chunk_ref = this.mesh_buffer.tmp_chunks_header[id];
        }
        render_cached_chunk(chunk_ref.info);

        chunk_ref.queued = false;
    }

    // Render multiple chunks
    void render_chunks(ivec3[] chunk_positions, VoxelWorld!ChunkT world) { }
}
