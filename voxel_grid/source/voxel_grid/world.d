module voxel_grid.world;

import voxel_grid.voxel;
import std.typecons         : Optional = Nullable;

interface VoxelWorld(ChunkT)
{
    alias VoxelType = ChunkT.VoxelType;

    VoxelType set_voxel(int[3] pos, Voxel voxel);
    Optional!VoxelType get_voxel(int[3] pos) const;

    int opApply(Callback : int delegate(int[3] cpos, ref ChunkT chunk))(Callback ops);

    VoxelType opIndex(int[3] pos) const;

    VoxelType opIndex(int x, int y, int z) const;

    VoxelType opIndexAssign(VoxelType voxel, int[3] pos);

    VoxelType opIndexAssign(VoxelType voxel, int x, int y, int z);
}
