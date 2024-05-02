module common.types;

private import std.traits       : isNumeric, isFloatingPoint, CommonType;
private import std.format       : format;
private import std.algorithm    : among;
private import std.math         : floor_ = floor, sqrt;

// all here is SAFE and no heap ALLOCATIONS will happen in this module
@safe @nogc nothrow:

alias vec3 = Vector!(float, 3);
alias ivec3 = Vector!(int, 3);
alias ivec4 = Vector!(int, 4);

private T min(T)(T a, T b) pure => a < b ? a : b;

private template isSameType(Args...)
{
    static if (Args.length <= 1)
        static immutable bool isSameType = true;
    else static if (is(Args[0] == Args[1]))
        static immutable bool isSameType = isSameType!(Args[1..$]);
    else
        static immutable bool isSameType = false;
}

enum isVector(T) = is(T : Vector!(BT, N), BT, ulong N);

static assert(isVector!vec3);

struct Vector(BT, ulong N) if (isNumeric!BT && N <= 4)
{
    alias This = Vector!(BT, N);
    alias BaseType = BT;
    enum ulong dimensions = N;

    enum string[] symbols = ["x", "y", "z", "w"];

    private enum bool validateArgs(Args...) =
        Args.length == N &&
        is(Args[0] : BT) && // can be explicitly converted to BT
        isSameType!Args;

    BT[N] array;

    this(BT[N] arr)
    {
        this.array = arr;
    }

    this(BT[] arr) in (arr.length == N)
    {
        this.array[] = arr;
    }

    this(Args...)(Args args) if (validateArgs!Args)
    {
        this.array = [args];
    }

    // Convert vector of some other type to this type
    this(T)(Vector!(T, N) vector) if (isNumeric!T)
    {
        static foreach (i; 0..N)
            this[i] = cast(BT)vector[i];
    }

    /// Returns the squared magnitude of the vector.
    real lengthSquared() const {
        real temp = 0;

        foreach(index; 0..N) {
            temp += array[index]^^2;
        }

        return temp;
    }

    real length() const => sqrt(lengthSquared);

    /++
        Stores result of `fnc` function ran with each element of `this` vector
        as argument.

        For example:
        ---
        import std.math : sign = sgn;

        // this
        vec3 v = vec3(2, -3, 0, 1).convert!sign;
        // is equivalent to this
        vec3 v_ = vec3(sign(v.x), sign(v.y), sign(v.z));

        assert(v == v_);
        ---
     +/
    This convert(alias fnc)() const
    {
        This vec;
        static foreach (i; 0..N)
            vec[i] = cast(BT)fnc(this[i]);
        return vec;
    }

    // TODO: Perhaps take any pointer of same dimensions as argument
    /* static This from(alias fnc, Args...)(Args args) */
    /* if (Args.lenght == 0 || isVector!(CommonType!Args)) */
    /* { */
    /*     This vec; */

    /*     /1* alias fnc_args = staticMap!; *1/ */

    /*     static foreach (i; 0..N) { */
    /*         vec[i] = cast(BT)fnc(); */
    /*     } */
    /* } */

    static if (isFloatingPoint!BT) // floating point specific func
    {
        This floor() => this.convert!floor_();

        This fractional() => this.convert!(common.types.fractional)();
    }


    bool opEquals(This b) const pure
    {
        bool is_equal = true;

        static foreach (i; 0..N)
            is_equal = is_equal && (this[i] == b[i]); // No branching

        return is_equal;
    }

    ref inout(BT) opIndex(long i) inout return pure => this.array[i];

    // TODO: It may be better to use this.array[] += v.array[]
    // TODO: Think whether it makes sense to define division here
    This opBinary(string op)(const This v) const pure if (op.among("+", "-", "/"))
    {
        This result;
        result.array = mixin("this.array[] "~op~" v.array[]");
        return result;
    }

    This opBinary(string op)(BT scalar) const pure
    {
        This result;
        result.array = mixin("this.array[] "~op~" scalar");
        return result;
    }

    pure
    {
        // generate x, y, z, w getter and setter functions
        static foreach (i, symbol; symbols[0..min(N, $)]) {
            mixin(format!(q{
                ref inout(BT) %s() inout return => array[%d];
            })(symbol, i));
        }
    }

    ulong toHash() const @safe nothrow
    {
        // TODO: I for sure can come up with a better hash function
        return typeid(BT[N]).getHash(&this);
    }
}

private T fractional(T)(T x) if (isFloatingPoint!T)
{
    import std.math     : modf;
    real _;
    return cast(T)modf(x, _);
}

T step(T)(T edge, T x) if (isNumeric!T) => (x < edge) ? 0 : 1;

Vector!(T, N) step(T, ulong N)(Vector!(T, N) edge, Vector!(T, N) x)
{
    Vector!(T, N) result;
    static foreach (i; 0..N) {
        result[i] = step(edge[i], x[i]);
    }
    return result;
}

/* Vector!(T, N) floor(T, ulong N)(Vector!(T, N) v) if (isFloatingPoint!T) */
/*     => Vector!(T, N)(floor(v.x), floor(v.y), floor(v.z)); */

// Convenience function to convert to vector
Vector!(T, N) vec(T, ulong N)(T[N] arr) pure => Vector!(T, N)(arr);


unittest
{
    import std.math;
    ivec3 v0 = ivec3(1, 2, 3);

    assert(v0.x == 1);
    assert(v0.y == 2);
    assert(v0.z == 3);

    vec3 v = vec3(0.1, 1.2, 2.3);

    // Fractional
    vec3 fract_v = v.convert!fractional;
    static foreach (i; 0..3)
        assert(isClose(fract_v[i], (cast(float)i+1) / 10.0f));

    vec3 f_v = v.convert!floor_;
    static foreach (i; 0..3)
        assert((cast(int)(f_v[i])) == i);
}
