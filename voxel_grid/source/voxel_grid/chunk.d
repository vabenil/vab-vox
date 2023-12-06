module voxel_grid.chunk;

private import std.meta     : AliasSeq;
private import std.typecons : Nullable, nullable;
private import std.traits   : Parameters, ReturnType, isSafe;

private import voxel_grid.voxel;

alias chunk_get_voxel_t(T) = Nullable!T function(uint, uint, uint);
alias chunk_set_voxel_t(T) = void function(uint, uint, uint, T);

private enum bool isSameFunc(alias F1, alias F2) =
    is(Parameters!F1 == Parameters!F2) &&
    is(ReturnType!F1 == ReturnType!F2);

enum bool isChunk(T) =
    isVoxel!(T.VoxelType) &&
    is(typeof(T.magnitude) == uint) &&
    // validate get_voxel
    isSameFunc!(T.get_voxel, chunk_get_voxel_t!(T.VoxelType)) &&
    isSafe!(T.get_voxel) &&
    // validate get_voxel
    isSameFunc!(T.set_voxel, chunk_set_voxel_t!(T.VoxelType)) &&
    isSafe!(T.set_voxel);


@safe @nogc nothrow pure
static size_t to_index_(uint x, uint y, uint z, ubyte magnitude)
    => x + (y << magnitude) + (z << (magnitude << 1));

struct VoxelChunk(VoxelT, uint chunk_magnitude=4) if (isVoxel!VoxelT)
{
    @safe @nogc nothrow:

    static assert(chunk_magnitude > 0 && chunk_magnitude <= 6);

    alias VoxelType = VoxelT;
    enum uint size = 1 << chunk_magnitude;
    enum uint magnitude = chunk_magnitude;

    VoxelType[1 << (magnitude * 3)] data;

    bool in_bounds(int x, int y, int z)
        => (x >= 0 && y >= 0 && z >= 0 &&
            x < size && y < size && z < size);

    size_t to_index(uint x, uint y, uint z) => to_index_(x, y, z, magnitude);

    Nullable!VoxelType get_voxel(uint cx, uint cy, uint cz)
    {
        if (!this.in_bounds(cx, cy, cz))
            return Nullable!VoxelType();
        return data[to_index(cx, cy, cz)].nullable();
    }

    void set_voxel(uint cx, uint cy, uint cz, VoxelType voxel)
    in(this.in_bounds(cx, cy, cz))
    {
        data[to_index(cx, cy, cz)] = voxel;
    }
}

alias Chunk = VoxelChunk!Voxel;
