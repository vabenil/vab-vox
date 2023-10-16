/+
 Simple 4 byte color type.

 TODO:
 - Add unittests here
+/
module common.color;

// ALL here is safe
@safe @nogc nothrow:

struct Color4b
{
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

    uint to_hex() pure
    {
        return ((rgba[0] << 0)    |
                (rgba[1] << 8)    |
                (rgba[2] << 16)   |
                (rgba[3] << 24));
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

    @property pure {
        ref inout(ubyte) r() inout return => rgba[0]; 
        ref inout(ubyte) g() inout return => rgba[1]; 
        ref inout(ubyte) b() inout return => rgba[2]; 
        ref inout(ubyte) a() inout return => rgba[3]; 
    }
}
