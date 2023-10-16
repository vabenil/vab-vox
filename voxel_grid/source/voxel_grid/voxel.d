module voxel_grid.voxel;

@safe @nogc nothrow:

private enum bool isSameFunc(F1, F2) =
    is(Parameters!F1 == Parameters!F2) &&
    is(ReturnType!F1 == ReturnType!F2);

enum bool isVoxel(T) =
    //  Can assign to data
    __traits(compiles, Voxel.init.data = uint.init) &&
    //  Can get data
    __traits(compiles, Voxel.init.data == uint.init) &&
    // is_empty function is defined
    is(typeof(T.init.is_empty()) == bool);

// Default Voxel implmentation
struct Voxel
{
    ubyte[4] data_;

    this(uint init_data)
    {
        this.data = init_data;
    }

    uint data() const pure => (cast(const(uint)[1])data_)[0];

    void data(uint new_data)
    {
        (cast(uint[1])this.data_)[0] = new_data;
    }

    bool is_empty() const pure => (this.data == 0);

    bool opCast(T : bool)() const pure => !this.is_empty();
}

static assert(isVoxel!Voxel);
