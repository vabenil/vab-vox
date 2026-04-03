/++
    Handles coordinate system for both global and local positions.

    Can support with *good* precision any coordinate in the range:
    `CHUNK_SIZE * int.min` - `CHUNK_SIZE * int.max`
++/
module common.coord;
import common.types;

private enum bool isValidCoordType(T) = is(T == int) || is(T == float);

/// Convert float to double and int to long
template ToLong(T)
{
    static assert(isValidCoordType!T);

    static if (is(T == int))
        alias ToLong = long;
    else
        alias ToLong = double;
}

struct Coordinate_(BT, int CHUNK_SIZE)
{
    @safe @nogc nothrow pure:

    static assert(isValidCoordType!BT);

    alias This = Coordinate_!(BT, CHUNK_SIZE);
    alias LongT = ToLong!BT;
    alias Vec = Vector!(BT, 3);
    alias LVec = Vector!(LongT, 3);

    ivec3 chunk_pos = ivec3(0, 0, 0); 
    Vec pos = Vec(0, 0, 0);

    void recalc() pure
    {
        this.chunk_pos += ivec3((Vec(this.pos) / cast(double)CHUNK_SIZE).floor);
        this.pos = ((Vec(this.pos) % CHUNK_SIZE) + CHUNK_SIZE) % CHUNK_SIZE;
    }

    this(ivec3 chunk_pos, Vec pos)
    {
        this.chunk_pos = chunk_pos;
        this.pos = pos;
    }

    this(VT)(VT global_pos) if (is(VT == Vec) || is(VT == LVec))
    {
        this.pos = global_pos;
        this.recalc();
    }

    this(U)(Coordinate_!(U, CHUNK_SIZE) coord) if (isValidCoordType!BT)
    {
        this.chunk_pos = coord.chunk_pos;
        this.pos = coord.pos;

        // recalc(); // I assume this coord is valid
    }

    This opBinary(string op)(BT scalar) const pure
    {
        This result = This(this.chunk_pos, mixin("this.pos "~op~" scalara"));
        result.recalc();
        return result;
    }

    This opBinary(string op, VT)(VT v) if (is(VT == Vec) || is(VT == LVec))
    {
        This result = This(this.chunk_pos, mixin("this.pos "~op~" v"));
        result.recalc();
        return result;
    }

    /// TODO: Add math Operations here
    This opBinary(string op)(const This coord) const pure if (op.among("+", "-", "/"))
    {
        This result = This(
            this.chunk_pos + coord.chunk_pos,
            mixin("this.pos "~op~" coord.pos")
        );
        result.recalc();
        return result;
    }

    This opOpAssign(string op)(BT scalar) => this = mixin("this "~op~" scalar");
    This opOpAssign(string op)(Vec v) => this = mixin("this "~op~" v");
    This opOpAssign(string op)(This coord) => this = mixin("this "~op~" coord");

    /// Vec may not be able to hold position representation
    Vec to_global() => (Vec(chunk_pos) * cast(BT)CHUNK_SIZE) + pos;

    LVec to_long_global() => LVec(chunk_pos) * cast(LongT)CHUNK_SIZE + LVec(pos);
}

alias Coordinate(int CHUNK_SIZE) = Coordinate_!(float, CHUNK_SIZE); 
alias ICoordinate(int CHUNK_SIZE) = Coordinate_!(int, CHUNK_SIZE);

/* void main() */
/* { */
/*     import std.stdio; */
/*     vec3 v = vec3(234, 12, 40); */
/*     writeln(v); */
/*     Coordinate!16 coord = Coordinate!16(v); */
/*     writeln(coord); */
/*     coord = coord + vec3(0, 4, 0); */
/*     writeln(coord); */
/* } */
