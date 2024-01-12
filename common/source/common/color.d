/+
 Simple 4 byte color type.

 TODO:
 - Add unittests here
+/
module common.color;

struct Color4b
{
    // ALL here is safe
    @safe @nogc nothrow:

    enum : Color4b
    {
        WHITE  =  Color4b(255, 255, 255),
        RED    =  Color4b(255, 0, 0),
        GREEN  =  Color4b(0, 255, 0),
        BLUE   =  Color4b(0, 0, 255),
        BLACK  =  Color4b(0, 0, 0),
        EMPTY  =  Color4b(0, 0, 0, 0)
    }

    ubyte[4] rgba;

    // I Could do some cast magic here to convert `rgba` to uint
    // but I doubt the performance difference would matter
    uint to_hex() const pure
    {
        return ((rgba[3] << 0)    |
                (rgba[2] << 8)    |
                (rgba[1] << 16)   |
                (rgba[0] << 24));
    }

    // constructor seems to work with any qualifier
    this(uint hex_color)
    {
        this.a = (hex_color >> 0)  & 0xff;
        this.b = (hex_color >> 8)  & 0xff;
        this.g = (hex_color >> 16) & 0xff;
        this.r = (hex_color >> 24) & 0xff;
    }

    this(ubyte r, ubyte g, ubyte b, ubyte a)
    {
        this.r = r;
        this.g = g;
        this.b = b;
        this.a = a;
    }

    this(ubyte r, ubyte g, ubyte b)
    {
        this(r, g, b, 255);
    }

    Color4b opBinary(string op)(float x)
    {
        Color4b res = Color4b(this.r, this.g, this.b, this.a);
        mixin("res.r = cast(ubyte)(this.r " ~ op ~ " x);");
        mixin("res.g = cast(ubyte)(this.g " ~ op ~ " x);");
        mixin("res.b = cast(ubyte)(this.b " ~ op ~ " x);");
        /* res.a = cast(ubyte)(this.a * x); */
        return res;
    }

    uint toHash() const => this.to_hex();
    bool opEquals(const Color4b col) const => (this.to_hex() == col.to_hex());

    @property pure {
        ref inout(ubyte) r() inout return => rgba[0]; 
        ref inout(ubyte) g() inout return => rgba[1]; 
        ref inout(ubyte) b() inout return => rgba[2]; 
        ref inout(ubyte) a() inout return => rgba[3]; 
    }
}

@safe @nogc nothrow
unittest
{
    assert(Color4b(0xff_ff_ff_ff) == Color4b.WHITE);
    assert(Color4b(0xff_00_00_ff) == Color4b.RED);
    assert(Color4b(0x00_ff_00_ff) == Color4b.GREEN);
    assert(Color4b(0x00_00_ff_ff) == Color4b.BLUE);
    assert(Color4b(0x00_00_00_ff) == Color4b.BLACK);
    assert(Color4b(0x00_00_00_00) == Color4b.EMPTY);

}
