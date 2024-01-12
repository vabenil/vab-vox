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

enum ubyte NULL_ID = 255;

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

// A vertex is the same as a face mesh
// Contains all vertex data
struct MeshContainer
{
    import utils.capedarray;
    import utils.memstore;
    import std.typecons : Tuple, tuple;

    struct ChunkInfo
    {
        ivec3 pos;
        int index;
        int size;

        int end() const pure => this.index + this.size;
    }

    struct Header
    {
        // I don't expect more than 128 chunks
        // store information of all chunks
        ubyte count = 0;
        // Chunk coordinates
        ivec3[255] coords = void;
        // Units in voxel faces
        int[255] indices = 0;
        int[255] sizes = 0;

        // Free positions in header (chunks that can be overriden)
        CapedArray!(ubyte, 255) free_headers; // use as a list

        // Implement this later
        // Sort by proximity to camera
        /* void sort(ivec3 cam_pos) */
        /* { */
        /*     // ordered array containing indices to header */
        /*     CapedArray!(byte, 128) order_array; */
        /*     // for this gotta assume whole thing is unsorted */
        /* } */

        int find(ivec3 pos)
        {
            for (int i = 0; i < this.count; i++) {
                if (this.free_headers.find(cast(ubyte)i) != -1)
                    continue; // if this value is freed it doesn't count

                if (this.coords[i] == pos)
                    return i; // found
            }
            return NULL_ID;
        }

        void swap(int chunk0_i, int chunk1_i)
        {
            ChunkInfo tmp = this[chunk0_i];

            this[chunk0_i] = this[chunk1_i];
            this[chunk1_i] = tmp;
        }

        bool full() const pure => (count == ubyte.max-1) && (free_headers.length == 0);

        // Returns index to empty space and remove empty space
        ubyte take_empty() in (!this.full())
        {
            if (free_headers.length) {
                // pop!
                ubyte index = free_headers[$-1];
                free_headers._length--;
                return index;
            }
            // push
            return cast(ubyte)(count++);
        }

        // Can fail
        int append(ChunkInfo info) in(!this.full())
        {
            int index = this.take_empty();
            this[index] = info;
            return index;
        }

        // Convinience function
        ChunkInfo opIndex(int i) const pure => ChunkInfo(coords[i], indices[i], sizes[i]);

        ChunkInfo opIndexAssign(ChunkInfo value, int i)
        {
            this.coords[i] = value.pos;
            this.indices[i] = value.index;
            this.sizes[i] = value.size;

            return value;
        }

        int opDollar(ulong _) const pure => this.count;
    }

    /*
       IDEA: Maybe use two vbos. One for far away things

       Rar away chunks close to 0:
        - Since this will be swapped more often and won't require extra allocations
       Close chunks close to $;
   */

    Header header; // contains info on what arrays are bound to what places
    MemStore memstore; // Manages memory
    VoxelVertex[] face_meshes;
    int max_face_count = 0;

    int buff_size = 0; // 1 unit = `VoxelVertex`
    VoxelVertex[] tmp_chunk_buffer;

    // Count, is the count of chunks for which it's chunk buffer will be stored
    this(uint count, uint max_chunk_face_count)
    {
        this.max_face_count = count * max_chunk_face_count;
        this.face_meshes.reserve(max_face_count);
        this.memstore = MemStore(this.max_face_count);

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
    ubyte push_chunk(ivec3 chunk_pos)
    {
        import std.stdio;
        // out of memory
        if (this.header.full()) {
            debug {
                writeln("[WARNING]: Out of memory");
            }
            return NULL_ID;
        }
        /* assert(!this.header.full()); */

        ubyte header_id = this.header.take_empty();
        int mem_start = this.memstore.take_mem(this.buff_size);

        assert(mem_start >= 0);

        this.header.coords[header_id] = chunk_pos;
        this.header.indices[header_id] = mem_start;
        this.header.sizes[header_id] = this.buff_size; // we don't know size until we create mesh

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

    bool append_chunk(int face_count, VoxelVertex[] buffer); // TODO: Implement

    ulong vertex_buffer_size() const pure => face_meshes.length * VoxelVertex.sizeof;

    void[] get_buffer() const => cast(void[])this.face_meshes;

    void[] get_chunk_buffer(int index)
    {
        ChunkInfo info = this.header[index];
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
        this.mesh_buffer = MeshContainer(12, chunk_size);
    }

    VoxelDevice get_device() => device;

    void set_camera(vec3 pos, vec3 dir, vec3 up) {}

    void commit_voxel_face_(int face_id, ivec3 cpos, ivec3 pos)
    {
        /* container.push_face(); */
        device.commit_face(pos, Color4b.WHITE, face_id, 0);
    }

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

    void send_to_device() => device.send_to_device(mesh_buffer.get_buffer());

    void commit_chunk(ref const BitChunk bit_chunk, ref const ChunkT chunk, ivec3 cpos) {}

    void commit_voxel(VoxelT voxel, ivec3 pos)
    {
        static foreach (s_bit; 0..2)
        static foreach (i; 0..3)
        {
            commit_voxel_face(Color4b(voxel.data), 3 * !(s_bit) + i, pos);
        }
    }

    void render() => device.render(cast(int)this.mesh_buffer.face_meshes.length);

    /* void render(uint start, uint count) => device.render(start, count); */

    void render_chunk(ivec3 cpos)
    {
        import std.stdio;
        int id = this.mesh_buffer.header.find(cpos);

        if (id == NULL_ID) {
            return;
        }
        /* assert(id != -1); */

        auto info = this.mesh_buffer.header[id];
        /* import std.stdio; */
        /* writeln(this.mesh_buffer.face_meshes[info.index]); */
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
