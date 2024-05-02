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

import common           : ivec3, ivec4, vec3, Color4b;
import std.typecons     : Optional = Nullable, optional = nullable;
import std.range        : chain;
import std.algorithm    : among;

import std.traits       : EnumMembers;

import std.stdio;

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

private enum int MAX_FACE_COUNT = 3 * (1 << (MAG * 3)) / 2;

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

import utils.chunksheader           :
       ChunksHeader_ = ChunksHeader,
       ChunkHeader_ = ChunkHeader,
       ChunkMemBlock,
       MeshState;

import utils.chunk_buffer_header;

enum int BUFFER_COUNT = 4;
alias ChunkHeader = ChunkHeader_!BUFFER_COUNT;
alias ChunksHeader = ChunksHeader_!BUFFER_COUNT;

/++
Manages vertex data and stores where memory of each chunk is located in
the buffer
+/
struct MeshContainer
{
    import utils.memheader;

    // I guess I will need a simpler header for the second vbo, perhaps only the size
    ChunkBufferHeader buffer_header; // contains info on what arrays are bound to what places

    /*
       `mesh_data` is a buffer of faces for voxels inside multiple chunks.

       chunks_header - Keeps track of memory of the main buffer

       main buffer contains chunks that will stay cached in memory
     */
    VoxelVertex[] mesh_data; // tracked by cpu_header

    // Add a queue of chunks to send to the GPU

    int max_face_count = 0;

    private int cpu_buffer_sizes;

    int[Buffer.max+1] buffer_offsets = 0;

    @disable this();

    // Count, is the count of chunks for which it's chunk buffer will be stored
    this(uint count) in (count > 0)
    {
        import std.conv : text;
        this.max_face_count = count / 2 * MAX_FACE_COUNT;

        // TODO: For now if the cpu buffer size is not the same as gpu
        // there will be problem. Remmeber to implement freeing chunks from the cpu
        cpu_buffer_sizes = 5 * MAX_FACE_COUNT;

        this.buffer_header = ChunkBufferHeader([
                cpu_buffer_sizes, cpu_buffer_sizes, // CPU Back and Front face buffer sizes
                this.max_face_count, this.max_face_count // GPU Back and Front face buffers sizes
        ]);

        buffer_offsets[Buffer.CPU_BACK_FACE] = 0;
        buffer_offsets[Buffer.CPU_FRONT_FACE] = cpu_buffer_sizes;
        buffer_offsets[Buffer.GPU_BACK_FACE] = 0;
        buffer_offsets[Buffer.GPU_FRONT_FACE] = this.max_face_count;

        this.mesh_data.length = cpu_buffer_sizes * 2;

        debug
            writefln("cpu_buffer_size: %d, gpu_buffer_size: %d",
                    2 * this.cpu_buffer_sizes, 2 * this.max_face_count);
    }

    void chunk_buffer_free(int header_id, int buffer_id)
        => this.buffer_header.chunk_buffer_free(header_id, buffer_id);

    void chunk_free(int header_id) => this.buffer_header.chunk_free(header_id);
    void chunk_free(ivec3 cpos) => this.buffer_header.chunk_free(cpos.array);

    VoxelVertex[] chunk_buffer_get(ivec3 cpos, int buffer_id)
    in(buffer_id.device() == Device.CPU)
    {
        int offset = this.buffer_offsets[buffer_id];

        // TODO: Using cpu_buffer_sizes here doesn't feel nice
        auto buffer = this.mesh_data[offset..offset+cpu_buffer_sizes];

        return this.buffer_header.chunk_get_buffer_data(cpos.array, buffer_id, buffer);
    }

    VoxelVertex[] chunk_buffer_get(ChunkMemBlock mem_block)
    in(mem_block.buff_id.device() == Device.CPU)
    {
        int offset = this.buffer_offsets[mem_block.buff_id];

        // TODO: Using cpu_buffer_sizes here doesn't feel nice
        auto buffer = this.mesh_data[offset..offset+cpu_buffer_sizes];

        return buffer[mem_block.start..mem_block.end];
    }

    /++
        Return pointer to an array of `size` size of VoxelVertex

        Arguments:
        $(LIST
                * cpos - The position of the chunk
                * buffer_id - id to buffer. Must be either BufferCPU_BACK_FACE
                or Buffer.CPU_FRONT_FACE
                * size - The size to allocate (1 unit = 1 VoxelVertex)
         )

        Returns:
        A pointer to `size` VoxelVertices. Or null in case of an error
     +/
    VoxelVertex* chunk_buffer_allocate(ivec3 cpos, int buffer_id, int size)
    in (buffer_id.device() == Device.CPU)
    {
        assert(buffer_id != -1);
        int header_id = this.buffer_header.chunk_allocate_buffer(cpos.array, buffer_id, size);

        if (header_id == -1)
            return null;

        ChunkMemBlock* header = this.buffer_header.chunk_get_buffer_mem_block(header_id, buffer_id);
        int offset = this.buffer_offsets[buffer_id];

        /* writeln(*header); */
        /* writeln(i"offset: $(offset), buffer_id: $(buffer_id)"); */

        return &this.mesh_data[offset + header.start];
    }

    /++
        Return of reallocated data. Previous pointer may become invalid

        Arguments:
        $(LIST
                * cpos - The position of the chunk
                * buffer_id - id to buffer. Must be either BufferCPU_BACK_FACE
                or Buffer.CPU_FRONT_FACE
                * size - The size to allocate (1 unit = 1 VoxelVertex)
         )

        Returns:
        A pointer to `size` VoxelVertices. Or null in case of an error
     +/
    alias chunk_buffer_reallocate = chunk_buffer_allocate;

    auto get_all_chunk_headers() => this.buffer_header.get_chunk_headers();

    auto get_all_indexed_chunk_headers() => this.buffer_header.get_indexed_chunk_headers();
}

class GLVoxelRenderer(ChunkT) : VoxelRenderer!ChunkT
{
    alias VoxelT = ChunkT.VoxelType;

    MeshContainer mesh_container;
    private GLDevice device;

    this(GLDevice device)
    {
        this.device = device;
        this.mesh_container = MeshContainer(10);
    }

    public GLDevice get_device() => device;

    void device_init() { allocate_buffers(); }

    void set_camera(vec3 pos, vec3 dir, vec3 up) {}

    void allocate_buffers()
    {
        debug {
            writeln("allocate gpu buffer with ",
                    mesh_container.max_face_count * 2, " vertices");
        }
        device.allocate_main_buffer(mesh_container.max_face_count * 2 * VoxelVertex.sizeof);
    }

    /* void commit_voxel(VoxelT voxel, ivec3 pos); */

    /// Load mesh if mesh is not already loaded (state is ON_DEVICE)
    void load_chunk(ref const ChunkT chunk, ivec3 cpos)
    {
        import std.algorithm    : all;
        ChunkHeader* chunk_header = mesh_container.buffer_header.chunk_get_header(cpos.array);

        if (chunk_header is null)
            return create_chunk_mesh(chunk, cpos); // void

        ChunkMemBlock[] mem_blocks = chunk_header.mem_blocks[];
        /+
            NOTE: In the future I might want to check if only certain buffers
            have mesh data loaded already instead of all of them.
        +/
        static foreach (device_buffers; [GPU_BUFFERS, CPU_BUFFERS]) {
            if (device_buffers[].all!(buffer => mem_blocks[buffer].state & MeshState.ON_DEVICE))
                return ; // Meshes are in device so
        }

        return create_chunk_mesh(chunk, cpos);
    }

    /// Chunk mesh has been modified and has to be remeshed.
    void commit_chunk(ref const ChunkT chunk, ivec3 cpos) { create_chunk_mesh(chunk, cpos); }

    // TODO: Make a proper render queue, with rendering commands,
    // for rendering chunks in batches
    /// Queue chunk for rendering may, or may not create a mesh
    void queue_chunk(ref ChunkT chunk, ivec3 cpos) { }

    void send_to_device()
    {
        // Send all chunks to device no matter what for now
        foreach (header_id, header; mesh_container.get_all_indexed_chunk_headers()) {
            foreach (buff; CPU_BUFFERS) {
                Buffer gpu_buff = buff.parallel_buffer();
                ChunkMemBlock cpu_mem_block = header.mem_blocks[buff]; // [WIP]
                ChunkMemBlock* gpu_mem_block = &header.mem_blocks[gpu_buff];


                if (cpu_mem_block.state == MeshState.NONE || gpu_mem_block.state & MeshState.SYNCHED)
                    continue; // nothing to do

                this.mesh_container.buffer_header.chunk_buffer_transfer(header_id, gpu_buff, buff);

                /* if (gpu_mem_block.state & MeshState.SYNCHED) */
                /*     continue; // Data already on GPU */

                // Get the gpu memblock which should be allocated at this point
                assert(gpu_mem_block.is_valid());

                debug writeln(cpu_mem_block);
                VoxelVertex[] mesh_data = this.mesh_container.chunk_buffer_get(cpu_mem_block);

                int offset = mesh_container.buffer_offsets[buff.parallel_buffer()];
                int start = offset + gpu_mem_block.start;

                /* writeln("header_id: ", header_id, ", buff: ", buff, ", start: ", start); */
                // I should probably check if stuff is synched before sending
                device.send_to_main_buffer(start * VoxelVertex.sizeof, mesh_data);
            }
        }
    }

    void render()
    {
        render_indirect_header();
        // Render main buffer
        /* render_header(this.mesh_container.chunks_header); */
        // Render tmp
        /* render_header(this.mesh_container.tmp_chunks_header); */
    }

    // TODO: Perhaps put rendering commands in different places
    auto create_indirect_draw_commands()
    {
        import std.range            : chain;
        import utils.chunk_buffer_header;
        import utils.capedarray;
        // TODO: Maybe preallocate this shit on class init or smth
        // Can't batch render more than 256 render commands

        // NOTE: GC
        static DrawElementsIndirectCommand[] draw_commands;
        draw_commands.length = 0; // set length to 0, since it's static

        // TODO: To avoid unnessary extra calculation in chunk and shit I should
        // just make a draw rendering list. Which contains which chunks
        // need to be rendered. It Could contain ChunkRef, or just something
        // that points at the fucking chunk headers

        auto chunks_headers = this.mesh_container.get_all_chunk_headers();
        // Use chain or something
        foreach (ChunkHeader header; chunks_headers) {
            foreach (buff; GPU_BUFFERS) {
                ChunkMemBlock mem_block = header.mem_blocks[buff];

                int offset = this.mesh_container.buffer_offsets[buff];
                int start = offset + mem_block.start;

                draw_commands ~= DrawElementsIndirectCommand(
                    count: 6,
                    instance_count: mem_block.calc_size(),
                    index: 0,
                    base_vertex: 0,
                    base_instance: start
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
        /* ChunkRef chunk_ref = void; */
        /* ChunkMemBlock*[2] mem_blocks =  [ */
        /*     this.mesh_container.buffer_header.chunk_get_buffer_mem_block(cpos, Buffer.GPU_BACK_FACE), */
        /*     this.mesh_container.buffer_header.chunk_get_buffer_mem_block(cpos, Buffer.GPU_FRONT_FACE) */
        /* ]; */

        /* foreach (mem_block; mem_blocks) { */
        /*     render_cached_chunk(mem_block); */
        /* } */
        /* else { // Chunk is not cached */
        /*     this.flush(); */

        /*     int id = this.commit_tmp_chunk(chunk, cpos); */
        /*     this.send_tmp_to_device(); */

        /*     chunk_ref = this.mesh_container.tmp_chunks_header[id]; */
        /* } */
    }

    // Render multiple chunks
    void render_chunks(ivec3[] chunk_positions, VoxelWorld!ChunkT world) { }

    /++
        Creates meshes in `CPU_BACK_FACE` and `CPU_FRONT_FACE` buffers,
        allocates the buffers if necessary.

        NOTE: This ignores the buffer MeshState, it assumes that all buffers
        must be re-meshed
     +/
    void create_chunk_mesh(ref const ChunkT chunk, ivec3 cpos)
    {
        import std.range    : zip;
        // Ok, we are remeshing anyway so we might as well free
        // NOTE: This not optimal, as i *MAY* need to only reallocate a single buffer
        // so freeing them al *MAY* be throwing away work

        // Allocate buffers and return ptr, if buffers are already allocated just return ptr
        VoxelVertex* bf_buffer = mesh_container.chunk_buffer_allocate(cpos, Buffer.CPU_BACK_FACE, MAX_FACE_COUNT);
        VoxelVertex* ff_buffer = mesh_container.chunk_buffer_allocate(cpos, Buffer.CPU_FRONT_FACE, MAX_FACE_COUNT);

        assert(bf_buffer != null && ff_buffer != null);

        int face_id = 0; // Index of the face (one of 6 faces a cube can have)

        auto buffers = [bf_buffer, ff_buffer];
        auto buffer_ids = [Buffer.CPU_BACK_FACE, Buffer.CPU_FRONT_FACE];

        foreach (buffer_id, buffer; zip(buffer_ids, buffers)) {
            int face_count = 0;

            debug {
                auto mem_block =
                    mesh_container.buffer_header
                        .chunk_get_buffer_mem_block(cpos.array, buffer_id);
                writeln("allocated cpu mem_block ", *mem_block);
            }

            foreach (i; 0..3) {
                VoxelVertex[] buffer_slice = buffer[face_count..MAX_FACE_COUNT];

                face_count += create_chunk_mesh_faces(chunk, buffer_slice, face_id);
                /* writeln(face_id); */
                face_id++;
            }

            writeln("face_count: ", face_count);
            // Resize down the buffers
            mesh_container.chunk_buffer_reallocate(cpos, buffer_id, face_count);
            // Free from GPU since it's no longer up to date
            mesh_container.buffer_header.chunk_buffer_free(cpos.array, buffer_id.parallel_buffer());
        }
    }

    /++
        Creates all faces of a chunk facing in `face_index` direction where
        `face_index` can be any of the following
        $(LIST
                * 0 - x negative
                * 1 - y negatvie
                * 2 - z negative

                * 3 - x positive
                * 4 - y positive
                * 5 - z positive
         )
        +/
        int create_chunk_mesh_faces(ref const ChunkT chunk, VoxelVertex[] buffer, int face_index)
        {
            debug writeln("create_chunk_mesh_faces");
            ubyte dim = cast(ubyte)(face_index % 3);
            ubyte s_bit = cast(ubyte)(face_index > 2);

            ivec3 delta, pos, adj_pos;
            delta = ivec3(mat3_identity[dim]) * ((s_bit * 2) - 1); // by sign

            int face_count = 0;
            for (int k = 0; k < ChunkT.size; k++)
            for (int j = 0; j < ChunkT.size; j++)
            for (int i = 0; i < ChunkT.size; i++)
            {
                pos = ivec3(i, j, k);
                adj_pos = delta + pos;
                if (!chunk.in_bounds(adj_pos.array) || chunk[adj_pos.array].is_empty()) {
                    if (!chunk[pos.array].is_empty())
                        buffer[face_count++] = VoxelVertex(pos, Color4b(chunk[pos.array].data), face_index);
                }
            }

            return face_count;
        }

    /* void commit_chunk(ref const BitChunk bit_chunk, ref const ChunkT chunk, ivec3 cpos) {} */

    /* void render_header(ref ChunksHeader header) */
    /* { */
    /*     // TODO: Stop using magic numbers!!! */
    /*     // TODO: We have to swap and do a bunch of bs */
    /*     foreach (ChunkRef chunk_ref; header) { */
    /*         if (chunk_ref.queued) { */
    /*             // Add this chunk to a batch */
    /*             render_cached_chunk(chunk_ref.info); */
    /*             chunk_ref.queued = false; */
    /*         } */
    /*     } */
    /* } */

    void render_indirect_header()
    {
        import std.array        : array;
        import std.range        : chain;
        import std.algorithm    : filter, map;

        auto draw_commands = create_indirect_draw_commands();
        int[4][] chunk_coords = this.mesh_container.get_all_chunk_headers()
            .map!(header => ivec4(header.coords[0], header.coords[1], header.coords[2], 0).array).array();

        /* import std.stdio; */
        this.device.send_chunk_coords(chunk_coords);
        this.device.set_chunk_count(cast(int)chunk_coords.length);
        this.device.set_chunk_size(ChunkT.size);
        this.device.multi_render_indirect(draw_commands);
    }

    /* ChunkRef[][] create_chunk_batches() */
    /* { */
    /*     import std.array        : array; */
    /*     import std.algorithm    : sort, filter, map; */

    /*     auto chunk_headers = this.mesh_container.get_all_chunk_headers() */
    /*         .filter!(info => info.queued).array(); */
    /*     chunk_headers.sort!((h0, h1) => h0.index < h1.index); */
    /*     ChunkRef[][] batches = [[chunk_headers[0]]]; */
    /*     for (int i = 1; i < chunk_headers.length; i++) { */
    /*         auto prev = batches[$-1][$-1]; */
    /*         auto curr = chunk_headers[i]; */

    /*         if (prev.is_adjacent(curr)) */
    /*             batches[$-1] ~= curr; */
    /*         else */
    /*             batches ~= [curr]; */
    /*     } */
    /*     return batches; */
    /* } */

    /* void render_chunk_batches() */
    /* { */
    /*     import std.array        : array; */
    /*     import std.range        : chain; */
    /*     import std.algorithm    : filter, sort; */

    /*     auto batches = create_chunk_batches(); */

    /*     // For each batch send position of all chunks in batch */
    /*     // send instances in batch */
    /* } */

    // TODO: No way to render chunks in batches yet, Fix that
    /// Render everything in tmp buffer and clear it
    void flush()
    {
        /* import std.stdio; */
        /* writeln("chunk headers free: ", mesh_container.tmp_chunks_header.unused); */

        // TODO: Fix this function
        /* send_tmp_to_device(); // make sure tmp buffers are on device */

        // TODO: This function could be called render_cached
        /* render_header(this.mesh_container.tmp_chunks_header); */
        /* this.mesh_container.clear_tmp(); */

        /++
            render();
        this.mesh_container.chunks_header.clear();
        this.mesh_container.cpu_header();
        +/
    }

    /* void render_cached_chunk(ChunkHeader chunk_header) // should be private */
    /* { */
    /*     this.device.set_chunk_pos(ivec3(info.coords)); */
    /*     this.device.set_chunk_size(ChunkT.size); */
    /*     this.device.render(info.index, info.size); */
    /* } */
}
