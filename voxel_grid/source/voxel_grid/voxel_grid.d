module voxel_grid.voxel_grid;

import voxel_grid.voxel;
import voxel_grid.chunk;

import std.typecons : Nullable;


interface VoxelGridTmp(ChunkType) if (isChunk!ChunkType) 
{
    alias VoxelType = ChunkType.VoxelType;

    Nullable!VoxelType get_voxel(uint x, uint y, uint z);
    void set_voxel(uint x, uint y, uint z, Voxel voxel);
    ChunkType get_chunk(uint cx, uint cy, uint cz);
}

alias VoxelGrid = VoxelGridTmp!Chunk;

unittest
{
    import std.stdio;
    import std.traits;

    import voxel_grid.voxel;
    import voxel_grid.voxel_chunk;
}
