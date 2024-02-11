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

    MemHeader cpu_header;
    // Chunk of buffers
    VoxelVertex[] face_meshes; // tracked by cpu_header

    // Add a queue of chunks to send to the GPU
    // Add gpu header here

    int max_face_count = 0;

    int buff_size = 0; // 1 unit = `VoxelVertex`
    VoxelVertex[] tmp_chunk_buffer;

    // Count, is the count of chunks for which it's chunk buffer will be stored
    this(uint count, uint max_chunk_face_count)
    {
        this.max_face_count = count * max_chunk_face_count;
        this.face_meshes.reserve(max_face_count);
        this.chunks_header = ChunksHeader(CHUNK_HEADER_CAP);
        this.cpu_header = MemHeader(this.max_face_count);

        if (tmp_chunk_buffer.length == 0) {
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
        else {
            // TODO: Here add the chunk to `temporary` memory
        }
        /* assert(!this.header.full()); */

        // TODO: Create a ChunkInfo first and append later
        int mem_start = this.cpu_header.allocate(this.buff_size);

        assert(mem_start >= 0);

        ChunkInfo chunk_info = ChunkInfo(
            coords: chunk_pos.array,
            index: mem_start,
            size: this.buff_size,
            modified: true
        );

        int header_id = this.chunks_header.append(chunk_info);

        face_meshes ~= tmp_chunk_buffer[0..buff_size];

        assert(face_meshes.length <= max_face_count);

        this.buff_size = 0; // Reset tmp buffer

        return header_id;
    }

    /* void free_chunk(ivec3 chunk_pos) */
    /* { */
    /*     for (int i = 0; i < this.header.count; i++) { */
    /*         if (this.header.coords[i] == chunk_pos) { */

    /*         } */
    /*     } */
    /* } */

    ulong vertex_buffer_size() const pure => face_meshes.capacity * VoxelVertex.sizeof;

    void[] get_buffer() const => cast(void[])this.face_meshes;

    void[] get_chunk_buffer(int index)
    {
        ChunkInfo info = this.chunks_header[index].info;
        return cast(void[])this.face_meshes[info.index..info.end];
    }
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
        this.mesh_buffer = MeshContainer(6, chunk_size);
    }

    GLDevice get_device() => device;

    void set_camera(vec3 pos, vec3 dir, vec3 up) {}

    // NOTE: This has no effect if `commit_chunk` is not used
    void commit_voxel_face(Color4b color, int face_id, ivec3 pos)
    {
        mesh_buffer.push_face(VoxelVertex(pos, color, face_id));
    }

    // For the time being we don't cache the chunk, so we 
    // must recalculate all chunk meshes
    // TODO: Use Bit chunk here
    void commit_voxel_faces_(ref const ChunkT chunk, ivec3 pos)
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
                commit_voxel_face(Color4b(voxel.data), face_id, pos);
            }
            face_id++;
        }
    }

    // Create meshes
    void commit_chunk(ref const ChunkT chunk, ivec3 cpos)
    {
        for (int k = 0; k < ChunkT.size; k++)
        for (int j = 0; j < ChunkT.size; j++)
        for (int i = 0; i < ChunkT.size; i++)
            commit_voxel_faces_(chunk, ivec3(i, j, k));

        mesh_buffer.push_chunk(cpos);
    }

    void allocate_buffers()
    {
        device.allocate_main_buffer(mesh_buffer.vertex_buffer_size());
    }

    void send_to_device()
    {
        import std.stdio;
        foreach (ChunkRef chunk_info; mesh_buffer.chunks_header) {
            int index = chunk_info.index,
                size = chunk_info.size;

            void[] buffer_slice = cast(void[])(mesh_buffer.face_meshes[index..index+size]);
            if (chunk_info.modified) {
                device.send_to_main_buffer(index * VoxelVertex.sizeof, buffer_slice);
                chunk_info.modified = false;
            }
        }
    }

    void commit_chunk(ref const BitChunk bit_chunk, ref const ChunkT chunk, ivec3 cpos) {}

    void commit_voxel(VoxelT voxel, ivec3 pos)
    {
        static foreach (s_bit; 0..2)
        static foreach (i; 0..3) {
            commit_voxel_face(Color4b(voxel.data), 3 * !(s_bit) + i, pos);
        }
    }

    void render() => device.render(cast(int)this.mesh_buffer.face_meshes.length);

    /* void render(uint start, uint count) => device.render(start, count); */

    void render_chunk(ivec3 cpos)
    {
        int id = this.mesh_buffer.chunks_header.find(cpos.array);

        if (id == ChunksHeader.NULL_ID) {
            return;
        }

        auto info = this.mesh_buffer.chunks_header[id].info;
        // send uniform
        this.device.set_chunk_pos(cpos);
        this.device.set_chunk_size(ChunkT.size);
        this.device.render(info.index, info.size);
    }

    // Render multiple chunks
    void render_chunks(ivec3[] chunk_positions)
    {
    }

    void flush() {}
}
