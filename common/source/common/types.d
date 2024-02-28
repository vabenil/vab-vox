module common.types;

private import std.traits       : isNumeric, isFloatingPoint;
private import std.format       : format;
private import std.algorithm    : among;
private import std.math         : floor;

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

struct Vector(BT, ulong N) if (isNumeric!BT && N <= 4)
{
    alias This = Vector!(BT, N);
    alias BaseType = BT;
    enum ulong dimensions = N;

    enum string[] symbols = ["x", "y", "z", "w"];

    enum bool validateArgs(Args...) =
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

    bool opEquals(This b) const pure
    {
        bool is_equal = true;

        static foreach (i; 0..N)
            is_equal = is_equal && (this[i] == b[i]);

        return is_equal;
    }

    ref inout(BT) opIndex(long i) inout return pure => this.array[i];

    // TODO: It may be better to use this.array[] += v.array[]
    This opBinary(string op)(const This v) const pure if (op.among("+", "-"))
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

Vector!(T, N) floor(T, ulong N)(Vector!(T, N) v) if (isFloatingPoint!T)
    => Vector!(T, N)(floor(v.x), floor(v.y), floor(v.z));

// Convenience function to convert to vector
Vector!(T, N) vec(T, ulong N)(T[N] arr) pure => Vector!(T, N)(arr);

unittest
{
    ivec3 v0 = ivec3(1, 2, 3);

    assert(v0.x == 1);
    assert(v0.y == 2);
    assert(v0.z == 3);
}
