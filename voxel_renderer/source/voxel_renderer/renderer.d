module voxel_renderer.renderer;

import voxel_renderer.device;
import voxel_grid;
import voxel_grid.bitchunk;

static immutable size_t chunk_M = 5;
private alias BitChunk = VoxelBitChunk!(BitVoxel, chunk_M);

interface VoxelRenderer(ChunkT)
{
    alias VoxelT = GridType.VoxelType;

    VoxelDevice get_device();
    // TODO: pass camera
    // TODO: Maybe add config as input argument
    void device_init();

    void set_camera(vec3 pos, vec3 dir, vec3 up);

    void commit_chunk(ref const(ChunkT) chunk, ivec3 chunk_pos);

    void commit_voxel(VoxelT voxel, ivec3 pos);

    // Chunk should already be in device by this point
    void render_chunk(ivec3 chunk_pos);

    void flush();
}
