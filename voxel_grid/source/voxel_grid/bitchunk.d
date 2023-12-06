module voxel_grid.bitchunk;

import voxel_grid.chunk : isChunk;
import std.typecons     : Nullable, nullable;
import core.bitop       : bt, btr, bts;

@safe @nogc nothrow pure
static size_t to_index_(uint x, uint y, uint z, ubyte magnitude)
    => x + (y << magnitude) + (z << (magnitude << 1));
 
@trusted @nogc nothrow pure
static bool get_bit(const(ubyte[]) data, size_t index)
in(index < (data.length << 3))
    => cast(bool)bt(cast(size_t*)data.ptr, index);

@trusted @nogc nothrow
static bool set_bit(ubyte[] data, size_t index, bool value)
in(index < (data.length << 3))
    => cast(bool)(
        value
            ? bts(cast(size_t*)data.ptr, index)
            : btr(cast(size_t*)data.ptr, index)
    );
// If using statically magnitude must be less than 8
// 1 Bit chunk
struct VoxelBitChunk(VoxelT, uint chunk_magnitude=4)
{
    alias VoxelType = VoxelT;
    enum size_t DIM = 1L << chunk_magnitude;
    enum size_t magnitude = chunk_magnitude;
    enum size_t voxel_count = 1L << (magnitude * 3);

    /*
       So Here I got 2 choices.

       1) I can have a ubyte reprenset 8 voxels in the x dimension
            - I guess this might allow me to copy from x dimension
       2) I can have a ubyte represent 2x2x2 voxels
            - I guess this might allow me to copy volume of voxels
    */
    ubyte[voxel_count >> 3] data;
    /* ubyte[] data; */

    this(uint dim)
    {
        /* this.data = new ubyte[voxel_count >> 3]; */
    }

    bool in_bounds(int x, int y, int z)
        => (x >= 0 && y >= 0 && z >= 0 &&
            x < DIM && y < DIM && z < DIM);

    size_t to_index(uint x, uint y, uint z) => to_index_(x, y, z, magnitude);

    // TODO: I could probably put `in_bounds` check this into an `in` contract
    // Since getting a voxel outside of range should either just be an error
    // or return an empty voxel
    Nullable!VoxelType get_voxel(uint cx, uint cy, uint cz)
    {
        if (!this.in_bounds(cx, cy, cz))
            return Nullable!VoxelType();

        // This one is different
        return VoxelType(data.get_bit(to_index(cx, cy, cz))).nullable();
    }

    void set_voxel(uint cx, uint cy, uint cz, VoxelType voxel)
    {
        import std.stdio;
        if (this.in_bounds(cx, cy, cz))
            data.set_bit(to_index(cx, cy, cz), cast(bool)voxel);
    }

    size_t size() const pure => voxel_count >> 3;
}

struct BitVoxel
{
    bool data = false;

    this(bool data)
    {
        this.data = data;
    }

    bool is_empty() const pure => !this.data;

    bool opCast(T : bool)() const pure => this.data;
}

/* static assert(isChunk!(VoxelBitChunk!BitVoxel)); */

unittest
{
    import std.stdio;
    alias BitChunk(uint magnitude=4) = VoxelBitChunk!(BitVoxel, magnitude);
    enum size_t MAG = 7;
    enum size_t DIM = 1 << MAG;

    alias Chunk = BitChunk!MAG;
    Chunk chunk = Chunk(MAG);

    chunk.set_voxel(3, 0, 0, BitVoxel(true));
    chunk.set_voxel(0, 3, 0, BitVoxel(true));
    chunk.set_voxel(0, 0, 3, BitVoxel(true));

    chunk.set_voxel(1, 1, 1, BitVoxel(true));
    chunk.set_voxel(1, 2, 3, BitVoxel(true));
    chunk.set_voxel(3, 3, 3, BitVoxel(true));

    assert(chunk.get_voxel(0, 0, 0).get.is_empty());
    assert(chunk.get_voxel(3, 1, 3).get.is_empty());
    assert(chunk.get_voxel(0, 1, 0).get.is_empty());

    assert(!chunk.get_voxel(3, 0, 0).get.is_empty());
    assert(!chunk.get_voxel(0, 3, 0).get.is_empty());
    assert(!chunk.get_voxel(0, 0, 3).get.is_empty());

    assert(!chunk.get_voxel(1, 1, 1).get.is_empty());
    assert(!chunk.get_voxel(1, 2, 3).get.is_empty());
    assert(!chunk.get_voxel(3, 3, 3).get.is_empty());

    if (chunk.size > 0x400) {
        if (chunk.size > 0x100000)
            writeln("BitChunk!", MAG, ".sizeof = ", chunk.size / 0x100000, " MB");
        else
            writeln("BitChunk!", MAG, ".sizeof = ", chunk.size / 0x400, " KB");
    }
    else writeln("BitChunk!", MAG, ".sizeof = ", chunk.size, " B");
    writeln("Chunk(", DIM, "x", DIM, "x", DIM, ") Voxel count = ", Chunk.voxel_count);
}
