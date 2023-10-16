module vadgl.error;

import std.traits       : EnumMembers;
import std.format       : format;

import vadgl.types;
import result;

// TODO: Use strings for error. It will be eaiser
// TODO: use Result!(GLError, void) instead of just GLError
// TOOD: Instead of putting all errors in a single enum.
/// I should make different enums/struct to represent different kind of errors
// and store the actual error into an union or sumType
struct GLError
{
    enum Flag
    {
        // 1 to 1 mappings to general OpenGL errros
        NO_ERROR = 0,
        INVALID_ENUM,
        INVALID_VALUE,
        INVALID_OPERATION,

        STACK_OVERFLOW,
        STACK_UNDERFLOW,

        // Custom errors
        // For glBind<Buffer|VertexArray>
        INVALID_TARGET,
        INVALID_BUFFER,

        // shader errors
        INVALID_SHADER,
        INVALID_SHADER_TYPE,
        SHADER_SOURCE_NOT_SET,
        SHADER_COMPILATION_ERROR,

        // program errors
        INVALID_PROGRAM,
        SHADER_ALREADY_ATTACHED,
        PROGRAM_LINK_ERROR,
        PROGRAM_VALIDATION_ERROR,

        INVALID_PARAMETER,
        UNKNOWN_ERROR = int.max
    }

    mixin injectEnum!Flag;

    Flag error_flag;
    string msg;

    this(Flag error_flag, string msg = "") @safe nothrow
    {
        this.error_flag = error_flag;
        this.msg = msg;
    }

    this(string func, Flag error_flag, string msg = "") @safe
    {
        this.error_flag = error_flag;
        this.msg = format!"[GLError]: %s: %s\n"(func, error_flag);
        if (msg)
            this.msg ~= msg~"\n";
    }

    bool is_error() @safe const => this.error_flag != Flag.NO_ERROR;

    GLError with_msg(string msg) @safe => GLError(this.error_flag, msg);
    GLError append(string msg) @safe => GLError(this.error_flag, this.msg ~ msg);

    /* GLError push_func(string fname, string msg = "") */
    /*         => GLError( */
    /*                 this.error_flag, */
    /*                 this.msg~"[From]: "~fname~(msg ? msg)); */

    // TODO: maybe use toString instead
    string to_error_msg() @safe const
            => (msg == "") ? format!"[GL_ERROR]: %s"(error_flag) : msg;

    bool opCast(T: bool)() @safe const => is_error();

    static GLError no_error() @safe nothrow => GLError.NO_ERROR;
    static GLError default_msg(GLError.Flag flag, string func)
            => GLError(flag, format!"[GL_ERROR: %s: %s]"(func, flag));
}

struct InternalError
{
    mixin injectEnum!GLInternalError;

    GLInternalError error_flag;

    this(GLInternalError error_flag) @safe nothrow { this.error_flag = error_flag; }

    bool is_error() @safe const => (this.error_flag != GLInternalError.NO_ERROR);
    string to_error_msg() @safe => format!"got gl error: %s"(error_flag);

    bool opCast(T: bool)() @safe const => is_error();
    static InternalError no_error() @safe nothrow => InternalError.NO_ERROR;
}

public alias GLResult = ResultPartial!GLError;

// ditto
GLResult!T glresult(T)(auto ref T val) @safe => GLResult!T(val);
GLResult!void glresult(GLError err) @safe => GLResult!void(err);

GLError.Flag to_glerror_flag(GLInternalError internal) // ditto
{
    final switch (internal)
    {
        static foreach (flag; EnumMembers!GLInternalError)
            mixin(q{
                case GLInternalError.%1$s:
                    return GLError.Flag.%1$s;
            }.format(flag.stringof));
    }
}

GLError to_glerror(GLInternalError internal) => GLError(internal.to_glerror_flag());

GLError to_glerror(InternalError internal) => GLError(internal.error_flag.to_glerror_flag());

GLError.Flag to_glerror_flag(InternalError internal) => internal.to_glerror().error_flag;

GLResult!T to_glresult(T)(Result!(InternalError, T) result) if (!is(T == void))
            => GLResult!T(result.error.to_glerror(), result.value);

GLResult!T to_glresult(T)(Result!(InternalError, T) result) if (is(T == void))
            => GLResult!T(result.error.to_glerror());
