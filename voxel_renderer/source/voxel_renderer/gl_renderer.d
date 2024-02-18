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

import voxel_grid.chunk;
import voxel_grid.bitchunk;

import common   : ivec3, vec3, Color4b;


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
        this.mesh_buffer = MeshContainer(1, chunk_size);
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

    void commit_tmp_chunk(ref const ChunkT chunk, ivec3 cpos)
    {
        create_chunk_mesh(chunk, cpos);
        mesh_buffer.push_tmp_chunk(cpos);
    }


    void allocate_buffers()
    {
        device.allocate_main_buffer(mesh_buffer.vertex_buffer_size());
    }

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

    void render() => device.render(cast(int)this.mesh_buffer.face_meshes.length);

    /* void render(uint start, uint count) => device.render(start, count); */

    void render_cached_chunk(ChunkInfo info) // should be private
    {
        this.device.set_chunk_pos(ivec3(info.coords));
        this.device.set_chunk_size(ChunkT.size);
        this.device.render(info.index, info.size);
    }

    /++
        Render chunk in `cpos`. Requires passing `chunk` in case mesh is not
        cached
    +/
    void render_chunk(ivec3 cpos, ref ChunkT chunk)
    {
        int id = this.mesh_buffer.chunks_header.find(cpos.array);

        ChunkInfo info;
        if (id == ChunksHeader.NULL_ID) {
            id = this.mesh_buffer.tmp_chunks_header.find(cpos.array);

            // TODO: Flush buffer
            if (id == ChunksHeader.NULL_ID) { // Create & upload mesh
                this.mesh_buffer.clear_tmp();
                this.commit_tmp_chunk(chunk, cpos);
                this.send_tmp_to_device();

                id = this.mesh_buffer.tmp_chunks_header.find(cpos.array);
            }

            assert(id != ChunksHeader.NULL_ID);

            info = this.mesh_buffer.tmp_chunks_header[id].info;
        }
        else {
            info = this.mesh_buffer.chunks_header[id].info;
        }
        render_cached_chunk(info);
    }

    // Render multiple chunks
    void render_chunks(ivec3[] chunk_positions) { }
}
