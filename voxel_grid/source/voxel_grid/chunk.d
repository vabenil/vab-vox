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
static ulong to_index_(uint x, uint y, uint z, ubyte magnitude)
    => x + (y << magnitude) + (z << (magnitude << 1));

// TODO: Honestly just use a class
struct VoxelChunk(VoxelT, uint chunk_magnitude=4) if (isVoxel!VoxelT)
{
    @safe nothrow:
    static assert(chunk_magnitude > 0 && chunk_magnitude <= 10);

    alias VoxelType = VoxelT;
    alias This = VoxelChunk!(VoxelType, chunk_magnitude);

    enum uint size = 1 << chunk_magnitude;
    enum uint magnitude = chunk_magnitude;
    enum uint voxel_count = 1 << (magnitude * 3);

    static if (chunk_magnitude <= 5)
        VoxelType[voxel_count] data;
    else
        VoxelType[] data;

    // IMPORTANT: ALWAYS use Chunk() for initializing a chunk
    // Work around for default constructor
    static This opCall()
    {
        This self = This.init; // init an empty chunk
        static if (chunk_magnitude > 5)
            self.data = new VoxelType[](voxel_count);

        return self;
    }

    bool in_bounds(int x, int y, int z) const pure
        => (x >= 0 && y >= 0 && z >= 0 &&
            x < size && y < size && z < size);

    bool in_bounds(const int[3] p) const pure => in_bounds(p[0], p[1], p[2]);

    ulong to_index(uint x, uint y, uint z) const pure => to_index_(x, y, z, magnitude);

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

    VoxelType opIndex(uint x, uint y, uint z) const
    in (this.in_bounds(x, y, z))
    {
        return data[to_index(x, y, z)];
    }

    VoxelType opIndexAssign(VoxelType vox, uint x, uint y, uint z)
    in (this.in_bounds(x, y, z))
    {
        return (data[to_index(x, y, z)] = vox);
    }
    VoxelType opIndex(int[3] p) const => this[p[0], p[1], p[2]];
    VoxelType opIndex(uint index) const => data[index];

    VoxelType opIndexAssign(VoxelType vox, int[3] p) => (this[p[0], p[1], p[2]] = vox);
    VoxelType opIndexAssign(VoxelType vox, uint index) => (data[index] = vox);
}

alias Chunk = VoxelChunk!Voxel;

unittest
{
    import std.stdio;

    Chunk chunk = Chunk();

    chunk.set_voxel(3, 0, 0, Voxel(true));
    chunk.set_voxel(0, 3, 0, Voxel(true));
    chunk.set_voxel(0, 0, 3, Voxel(true));

    chunk.set_voxel(1, 1, 1, Voxel(true));
    chunk.set_voxel(1, 2, 3, Voxel(true));
    chunk.set_voxel(3, 3, 3, Voxel(true));

    assert(chunk.get_voxel(0, 0, 0).get.is_empty());
    assert(chunk.get_voxel(3, 1, 3).get.is_empty());
    assert(chunk.get_voxel(0, 1, 0).get.is_empty());

    assert(!chunk.get_voxel(3, 0, 0).get.is_empty());
    assert(!chunk.get_voxel(0, 3, 0).get.is_empty());
    assert(!chunk.get_voxel(0, 0, 3).get.is_empty());

    assert(!chunk.get_voxel(1, 1, 1).get.is_empty());
    assert(!chunk.get_voxel(1, 2, 3).get.is_empty());
    assert(!chunk.get_voxel(3, 3, 3).get.is_empty());

    /* if (chunk.size > 0x400) { */
    /*     if (chunk.size > 0x100000) */
    /*         writeln("BitChunk!", MAG, ".sizeof = ", chunk.size / 0x100000, " MB"); */
    /*     else */
    /*         writeln("BitChunk!", MAG, ".sizeof = ", chunk.size / 0x400, " KB"); */
    /* } */
    /* else writeln("BitChunk!", MAG, ".sizeof = ", chunk.size, " B"); */
    /* writeln("BitChunk(", DIM, "x", DIM, "x", DIM, ") Voxel count = ", BitChunk.voxel_count); */
}
