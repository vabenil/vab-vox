module common.types;

private import std.traits       : isNumeric;
private import std.format       : format;
private import std.algorithm    : among;

// all here is SAFE and no heap ALLOCATIONS will happen in this module
@safe @nogc:

alias vec3 = Vector!(float, 3);
alias ivec3 = Vector!(int, 3);

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

struct Vector(BT, size_t N) if (isNumeric!BT && N <= 4)
{
    alias This = Vector!(BT, N);
    alias BaseType = BT;
    enum size_t dimensions = N;

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

    BT opIndex(long i) const pure => this.array[i];

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

    // TODO: Implement mathematical operations
}

unittest
{
    ivec3 v0 = ivec3(1, 2, 3);

    assert(v0.x == 1);
    assert(v0.y == 2);
    assert(v0.z == 3);
}
