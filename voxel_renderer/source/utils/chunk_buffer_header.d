module utils.chunk_buffer_header;

import utils.chunksheader;
import utils.memheader;

import std.range    : isRandomAccessRange;

enum Buffer : int
{
    CPU_BACK_FACE = 0,
    CPU_FRONT_FACE = 1,
    GPU_BACK_FACE = 2,
    GPU_FRONT_FACE = 3
}

enum Device
{
    CPU,
    GPU,
}


private enum int BC = Buffer.max + 1; // Buff count

public enum Buffer[] CPU_BUFFERS = [ Buffer.CPU_BACK_FACE, Buffer.CPU_FRONT_FACE ];
public enum Buffer[] GPU_BUFFERS = [ Buffer.GPU_BACK_FACE, Buffer.GPU_FRONT_FACE ];

private enum bool isMemRange(T) = is(typeof(T.start) : int) && is(typeof(T.end) : int);

auto calc_size(T)(T mem_range) if (isMemRange!T) => mem_range.end - mem_range.start;

import std.format;
Device device(Buffer buff) in (buff >= Buffer.min && buff <= Buffer.max, format!"buff is %d"(buff))
{
    // Could make a static switch
    final switch (buff)
    {
        case Buffer.CPU_FRONT_FACE, Buffer.CPU_BACK_FACE:
            return Device.CPU;

        case Buffer.GPU_BACK_FACE, Buffer.GPU_FRONT_FACE:
            return Device.GPU;
    }
}

Device device(int buff) => device(cast(Buffer)buff);

Buffer parallel_buffer(Buffer buff) in (buff >= Buffer.min && buff <= Buffer.max)
{
    final switch (buff)
    {
        case Buffer.CPU_FRONT_FACE:
            return Buffer.GPU_FRONT_FACE;

        case Buffer.CPU_BACK_FACE:
            return Buffer.GPU_BACK_FACE;

        case Buffer.GPU_FRONT_FACE:
            return Buffer.CPU_FRONT_FACE;

        case Buffer.GPU_BACK_FACE:
            return Buffer.CPU_BACK_FACE;
    }
}

Buffer to_cpu(int buff) => to_cpu(cast(Buffer)buff);

/++
    Manages storage of chunk meshes in the GPU/CPU

    NOTE:
        It may be better to call this `MeshHeader` or `MeshAllocator`
 +/
struct ChunkBufferHeader
{
    import std.container.array;
    import std.range            : chain;

    private alias MChunkHeader = ChunkHeader!BC;
    private alias MChunksHeader = ChunksHeader!BC;
    /++
        Stores stores metadata about a chunk and also where on memory that chunk
        buffers are stored
    ++/
    private MChunksHeader chunks_header;

    /++
        Manages blocks of memory.

        Basically it tells me where to get a chunk of memory of size `s` or
        whether or not there's enough space left for such a block.
    ++/
    private MemHeader[BC] mem_headers;

    this(int[BC] buffer_sizes)
    {
        // Set mem_headers to track memory in header
        static foreach (buff_id; 0..BC) {
            this.mem_headers[buff_id] = MemHeader(buffer_sizes[buff_id]);
        }
    }

    /++
        Returns an iterator to all ChunkMemoryBlocks
     +/
    /* MemHeader.Range get_memory_blocks(); */

    /++
        Returns an iterator to all `ChunkHeader`s in the MeshContainer
     +/
    MChunksHeader.Range get_chunk_headers() => chunks_header.range();
    MChunksHeader.IndexedRange get_indexed_chunk_headers() => chunks_header.indexed_range();

    MChunkHeader* chunk_get_header(int chunk_header_id)
    {
        if (chunk_header_id == -1) {
            return null;
        }

        MChunkHeader* chunk_header = &this.chunks_header[chunk_header_id];
        return chunk_header;
    }

    MChunkHeader* chunk_get_header(ivec3 cpos) => chunk_get_header(this.chunks_header.find(cpos));

    ChunkMemBlock* chunk_get_buffer_mem_block(int chunk_header_id, int buffer_id)
    {
        if (chunk_header_id == -1) {
            return null;
        }

        MChunkHeader* chunk_header = &this.chunks_header[chunk_header_id];

        return &chunk_header.mem_blocks[buffer_id];
    }

    /// Get buffer `buffer_id` from chunk in `cpos`. or null if it doesn't exist
    ChunkMemBlock* chunk_get_buffer_mem_block(ivec3 cpos, int buffer_id)
        => this.chunk_get_buffer_mem_block(this.chunks_header.find(cpos), buffer_id);

    /++
        Creates a chunk mesh with `capacity` capacity for each buffer

        NOTE: this currently assumes that chunk is not already in header
     +/
    /* void chunk_allocate_buffer(ivec3 cpos, int capacity); */


    /++
        Creates a chunk mesh with `capacity` capacity of in buffer `buffer_id`.
        In case buffer is already allocated, this reallocates buffer with
        `capacity` capacity

        NOTE:
            This essentially sets all meshes to "ON_DEVICE" as long as the chunk
            mesh has memory allocated to it, it's considered "ON_DEVICE"
     +/
    int chunk_allocate_buffer(int chunk_header_id, int buffer_id, int capacity)
     in (chunk_header_id != -1)
    {
        MChunkHeader* chunk_header = &this.chunks_header[chunk_header_id];

        ChunkMemBlock* mem_block = &chunk_header.mem_blocks[buffer_id];

        int mem_start = mem_block.start;
        // There's is already something allocated
        if (mem_block.state & MeshState.ON_DEVICE) {
            // Gotta realloc here
            if (calc_size(*mem_block) < capacity) {
                // Free chunk buffer memory
                this.mem_headers[buffer_id].free(mem_block.start);
                mem_start = this.mem_headers[buffer_id].allocate(capacity);
            }
            // If we are resizing down then there's no need for another allocation
            else {
                this.mem_headers[buffer_id].resize(mem_start, capacity);
            }
        }
        else { // MemBlock is not valid and memory hasn't be allocated
            // Just allocate the damn memory
            mem_start = this.mem_headers[buffer_id].allocate(capacity);
        }
        assert(mem_start != -1);

        mem_block.start = mem_start;
        mem_block.end = mem_start + capacity;
        mem_block.state = MeshState.SYNCHED; // We assume the thing is synched
        mem_block.buff_id = buffer_id;

        return chunk_header_id;
    }

    /++
        Creates a chunk mesh with `capacity` capacity of in buffer `buffer_id`.
        In case buffer is already allocated, this reallocates buffer with
        `capacity` capacity

        NOTE:
            This essentially sets all meshes to "ON_DEVICE" as long as the chunk
            mesh has memory allocated to it, it's considered "ON_DEVICE"
     +/
    int chunk_allocate_buffer(ivec3 cpos, int buffer_id, int capacity)
    {
        int chunk_header_id = this.chunks_header.find(cpos);
        if (chunk_header_id == -1) {
            chunk_header_id = this.chunks_header.push(MChunkHeader(cpos));
        }
        return chunk_allocate_buffer(chunk_header_id, buffer_id, capacity);
    }

    /++
        Allocate enough space in `buffer_dst` to fit data from `buffer_src`.

        Also update the `MeshState` of `buffer_dst` to "ON_DEVICE"
     +/
    void chunk_buffer_transfer(int header_id, int buffer_dst, int buffer_src)
    {
        MChunkHeader* chunk_header = &this.chunks_header[header_id];

        ChunkMemBlock src_block = chunk_header.mem_blocks[buffer_src];
        ChunkMemBlock* dst_block = &chunk_header.mem_blocks[buffer_src];

        if (!(src_block.state & MeshState.ON_DEVICE)) // No data to be copied
            return;

        assert(src_block.start != -1 && src_block.end != -1);

        // This reallocates if necessary
        chunk_allocate_buffer(header_id, buffer_dst, src_block.calc_size());

        dst_block.state |= src_block.state;
    }

    /// ditto
    alias chunk_reallocate_buffer = chunk_allocate_buffer;

    /++
        Creates a chunk mesh with `capacities` capacities of in all buffers.

        NOTE:
            This essentially sets all meshes to "ON_DEVICE" as long as the chunk
            mesh has memory allocated to it, it's considered "ON_DEVICE"
     +/
    void chunk_init_buffers(ivec3 cpos, int[BC] capacities)
    {
        MChunkHeader chunk_header = MChunkHeader(cpos);

        int mem_start, cap;
        static foreach (buffer_id; 0..BC)
        {
            cap = capacities[buffer_id];
            mem_start = mem_headers[buffer_id].allocate(cap);
            assert(mem_start != -1);

            chunk_header.mem_blocks[buffer_id].start = mem_start;
            chunk_header.mem_blocks[buffer_id].end = mem_start + cap;
            chunk_header.mem_blocks[buffer_id].state = MeshState.ON_DEVICE;
        }

        this.chunks_header.push(chunk_header);
    }

    // TODO: I don't really like this. I probably wanna make a mesh class which actually
    // takes care of mesh data
    void chunk_set_buffer_data(T)(ivec3 cpos, int buffer_id, T buffer, T faces)
    if (isRandomAccessRange!T)
    {
        import std.stdio;
        import std.algorithm    : copy;

        int chunk_header_id = chunk_allocate_buffer(cpos, buffer_id, cast(int)faces.length);

        MChunkHeader chunk_header = this.chunks_header[chunk_header_id];
        ChunkMemBlock mem_block = chunk_header.mem_blocks[buffer_id];

        // I don't know time complexity of this shit. But since my thing is an
        // array I should be able to do it in a more efficient way
        // This works the exact opposite way I would expect
        faces[].copy(buffer[mem_block.start..mem_block.end]);
    }

    T chunk_get_buffer_data(T)(ivec3 cpos, int buffer_id, T buffer) if (isRandomAccessRange!T)
    {
        int chunk_header_id = this.chunks_header.find(cpos);
        if (chunk_header_id == -1)
            return buffer[0..0]; // return empty range in case of error

        MChunkHeader chunk_header = this.chunks_header[chunk_header_id];
        ChunkMemBlock mem_block = chunk_header.mem_blocks[buffer_id];

        return buffer[mem_block.start..mem_block.end];
    }

    /++
        Stops tracking mesh memory in CPU
    ++/
    void chunk_buffer_free(int header_id, int buffer_id)
    {
        if (header_id == -1)
            return;

        MChunkHeader* chunk_header = &this.chunks_header[header_id];
        ChunkMemBlock* mem_block = &chunk_header.mem_blocks[buffer_id];

        if (mem_block.state == MeshState.NONE)
            return;

        // Update in mem_headers
        this.mem_headers[buffer_id].free(mem_block.start);

        // Update memblock in chunk_header
        *mem_block = ChunkMemBlock(buff_id: buffer_id, start: -1, end: -1, MeshState.NONE);
    }

    /// ditto
    void chunk_buffer_free(ivec3 cpos, int buffer_id)
        => chunk_buffer_free(this.chunks_header.find(cpos), buffer_id);

    /// Free chunk
    void chunk_free(int header_id)
    {
        static foreach (buff_id; 0..BC) {
            chunk_buffer_free(header_id, buff_id);
        }
        this.chunks_header.remove(header_id);
    }

    // ditto
    void chunk_free(ivec3 cpos)
        => chunk_free(this.chunks_header.find(cpos));

    /++
        NOTE: This function seems to make no sense as mesh_container actually
        has no idea on how to create meshes. Make a mesher or mesh_gen function
        that will create meshes.

        The mesh container only manages the memory of meshes on a physical and
        maybe a virtual device


        Tries to add a face mesh to the chunk `buffer_id` buffer.

        If there's not enough space in `buffer_id` buffer try to reallocate.
        If reallocation fails return 1, 0 otherwise.
     +/
    /* int chunk_buffer_push_face(ivec3 cpos, VoxelVertex vertex, int buffer_id = 0) */
    /* { */
    /*     // If there's no chunk_header, create one */
    /*     int header_id = this.chunks_header.find(cpos); */
    /*     // We are assuming here there is always enough space for more chunk_headers */
    /*     if (header_id == -1) */ 
    /*         header_id = this.chunks_header.push(MChunkHeader(cpos)); */

    /*     return -1; */
    /* } */

    int get_gpu_face_count()
    {
        int face_count = 0;
        static foreach (buff_id; [Buffer.GPU_BACK_FACE, Buffer.GPU_FRONT_FACE]) {
            face_count += this.mem_headers[buff_id].used;
        }
        return face_count;
    }

    int get_buffer_capacity(int buffer_id) => this.mem_headers[buffer_id].capacity;
}


// Shitty test, but proves things at least kinda work how I expect
unittest
{
    import std.stdio;
    import vertex;

    VoxelVertex[] buffer;
    buffer.length = 8;

    auto back_buffer = buffer[0..4];
    /* auto front_buffer = buffer[4..$]; */

    // Create 3 backfaces for a cube
    VoxelVertex[] back_faces = [
        VoxelVertex(0xffffffff, 0),
        VoxelVertex(0xff0000ff, 1),
        VoxelVertex(0x00ff00ff, 2),
    ];

    ChunkBufferHeader mesh_container = ChunkBufferHeader([4, 4, 8, 8]);
    // Nothing has been allocated face count should be 0
    assert(mesh_container.get_gpu_face_count() == 0);

    mesh_container.chunk_set_buffer_data([0, 0, 0], Buffer.CPU_BACK_FACE, back_buffer, back_faces[]);

    writeln(mesh_container.chunk_get_buffer_data([0, 0, 0], Buffer.CPU_BACK_FACE, back_buffer));

    // Simulation storing data in the gpu
    mesh_container.chunk_allocate_buffer([0, 0, 0], Buffer.GPU_BACK_FACE, 3);

    assert(mesh_container.get_gpu_face_count() == 3);
}
