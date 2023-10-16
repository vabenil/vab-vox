/+
    Implementation of a world usinga simple array.
    No real chunks for this version of the world array
+/
module voxel_grid.voxel_grid_array;

import voxel_grid.voxel_chunk;
import voxel_grid.voxel_grid;

import std.exception    : enforce;
import std.typecons     : Nullable, nullable;

/* // Fear not for this place is safe */
@safe:

// TODO: Maybe add this to utility functions
@nogc pure nothrow
size_t to_index_(uint x, uint y, uint z, ubyte magnitude)
    => x + (y << magnitude) + (z << (magnitude << 1));

/* /+ */
/* Suggestion: Alias this to SVGridArray */
/* +/ */
class VoxelGridArray(ChunkType) : VoxelGridTmp!ChunkType
{
    alias VoxelType = ChunkType.VoxelType;

    ubyte magnitude;
    uint size;
    VoxelType[] data;

    this(uint magnitude)
    {
        enforce(magnitude < 12, "magnitude's larger than 12 are too big");

        this.magnitude = cast(ubyte)magnitude;
        this.size = 1 << magnitude;
        this.data = new VoxelType[1 << (magnitude * 3)];
    }

    @nogc pure nothrow
    bool in_bounds(int x, int y, int z)
        => (x >= 0 && y >= 0 && z >= 0 &&
            x < size && y < size && z < size);

    // TODO: unittest this
    // Equivalent to "x + y * size + z * (size ^ 2)
    @nogc nothrow pure 
    size_t to_index(int x, int y, int z) => to_index_(x, y, z, this.magnitude);

    /+
        Taking any block in the range of 0-size for x, y, z should not result in
        null. Null is only returned (x, y, z) is outside of bounds.
    +/
    @nogc
    Nullable!VoxelType get_voxel(uint x, uint y, uint z)
    {
        if (!this.in_bounds(x, y, z))
            return Nullable!VoxelType();

        return data[to_index(x, y, z)].nullable();
    }

    void set_voxel(uint x, uint y, uint z, VoxelType voxel)
    {
        if (this.in_bounds(x, y, z))
            data[to_index(x, y, z)] = voxel;
    }

    ChunkType get_chunk(uint cx, uint cy, uint cz)
    {
        immutable uint cs = 1 << ChunkType.magnitude;
        Chunk chunk;

        // NOTE: this could be optimized by caching z and by using sums instead of multiply
        for (int k = 0; k < cs; k++)
        for (int j = 0; j < cs; j++) {
            size_t row_index = to_index_(0, j, k, ChunkType.magnitude);
            size_t world_row_index = to_index_(cx * cs, j+cy, k+cz, this.magnitude);

            chunk.data[row_index..row_index+cs] = data[world_row_index..world_row_index+cs];
        }
        return chunk;
    }
}

/* // Since interface is not typed as safe I can't call this as safe */
@system
unittest
{
    import voxel_grid.voxel;

    VoxelGrid grid = new VoxelGridArray!Chunk(5);

    grid.set_voxel(4, 7, 0, Voxel(1));
    grid.set_voxel(1, 2, 7, Voxel(1));
    grid.set_voxel(1, 1, 1, Voxel(1));

    // Voxel set
    assert(grid.get_voxel(4, 7, 0).get);
    assert(grid.get_voxel(1, 2, 7).get);
    assert(grid.get_voxel(1, 1, 1).get);

    // Empty voxel
    assert(grid.get_voxel(0, 0, 0) == Voxel().nullable());
    assert(grid.get_voxel(1, 2, 3) == Voxel().nullable());
    assert(grid.get_voxel(2, 2, 2) == Voxel().nullable());

    // Voxel outside bounds
    assert(grid.get_voxel(128, 128, 128).isNull);
}
