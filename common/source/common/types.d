module common.types;

private import std.traits   : isNumeric;
private import std.format   : format;

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

struct Vector(T, size_t N) if (isNumeric!T && N > 0)
{
    alias Type = T;
    enum size_t dimensions = N;

    enum string[] symbols = ["x", "y", "z", "w"];

    enum bool validateArgs(Args...) =
        Args.length == N &&
        is(Args[0] : T) && // can be explicitly converted to T
        isSameType!Args;

    T[N] array;

    this(Args...)(Args args) if (validateArgs!Args)
    {
        this.array = [args];
    }

    pure
    {
        // generate x, y, z, w getter and setter functions
        static foreach (i, symbol; symbols[0..min(N, $)]) {
            mixin(format!(q{
                ref inout(Type) %s() inout return => array[%d];
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
