/+
- Nothing throws here. All functions which can fail should return a Result!Type
- Do not overcomplicate anything
- Think about OpenGL support fucking later
+/
module vadgl.gl3;

import std.bitmanip             : bitfields;
import std.conv                 : to;
import std.format               : format;
import std.meta                 : AliasSeq;

import std.algorithm            : endsWith;
// OpenGL bindings
import bindbc.opengl;

import vadgl.types;
import vadgl.error;
import result;

enum MAX_GL_VARIABLE_NAME = 256;

auto trust(alias fnc, Args...)(Args args) @trusted => fnc(args);

bool is_integral(GLType type) pure => (type >= GLType.BYTE && type <= GLType.UINT);
bool is_floating(GLType type) pure => (GLType.FLOAT || GLType.DOUBLE);
bool is_base_type(GLType type) pure => (is_integral(type) || is_floating(type));

bool is_vector(GLType type) pure => type.to!string[0..$-1].endsWith("VEC");

GLType to_gl_type(GLenum type) => cast(GLType)type;

// TODO: make this work with matrix types
template to_gl_type(T)
{
    static if (is(T == V[N], V, size_t N)) {
        static immutable string type_name = V.stringof.toUpper;
        enum string dims = N.to!string;
        enum string prefix = (type_name[0] == 'F') ? "" : type_name[0..1];
        mixin("enum GLType to_gl_type = GLType."~prefix~"VEC"~dims~";");
    }
    else
        mixin("enum GLType to_gl_type = GLType.%s;".format(T.stringof.toUpper()));
}

template toDType(GLType type) // make this work with vector and matrix types
{
    mixin("alias toDType = %s;".format(type.to!string().toLower()));
}

@safe nothrow pure
bool is_shader_param(GLParam param)
{
    with(GLParam)
    return (param == SHADER_TYPE || param == DELETE_STATUS ||
           param == COMPILE_STATUS || param == INFO_LOG_LENGTH ||
           param == SHADER_SOURCE_LENGTH
    );
}

@safe nothrow pure
bool is_program_param(GLParam param)
{
    with(GLParam)
    return (param == GL_DELETE_STATUS || param == GL_LINK_STATUS ||
            param == GL_VALIDATE_STATUS || param == GL_INFO_LOG_LENGTH ||
            param == GL_ATTACHED_SHADERS
    );
}

@trusted @nogc nothrow
private static void opengl_clear_errors()
{
    while(glGetError() != GL_NO_ERROR) {}
}

@trusted @nogc nothrow
private GLInternalError opengl_get_error()
{
    while (int my_error = glGetError())
        return cast(GLInternalError)my_error;
    return GLInternalError.NO_ERROR;
}

/+
    Run opengl command and return result of `glGetError()`.

    Returns:
        glError if `fnc`'s return type is void or
        Result!(
+/
template gl_wrap(alias fnc_)
{
    private import std.traits   : isSomeFunction, ReturnType;

    static if (!isSomeFunction!fnc_)
        alias fnc = fnc_!Args;
    else
        alias fnc = fnc_;

    alias T = ReturnType!fnc;
    alias ErrorType = InternalError;
    alias ResultT = Result!(ErrorType, T);

    static if (is(T == void))
    ResultT gl_wrap(Args...)(Args args) nothrow
    {
        opengl_clear_errors();
        fnc(args);
        return ResultT(ErrorType(opengl_get_error()));
    }

    static if (!is(T == void))
    ResultT gl_wrap(Args...)(Args args) nothrow
    {
        opengl_clear_errors();

        T ret = fnc(args);

        if (GLInternalError err = opengl_get_error())
            return ResultT(ErrorType(err));

        return ResultT(ret);
    }
}

struct Shader
{
    enum Type {
        VERTEX           =  GL_VERTEX_SHADER,
        GEOMETRY         =  GL_GEOMETRY_SHADER,
        FRAGMENT         =  GL_FRAGMENT_SHADER,
    }

    private {
        uint id_ = 0;
        string name_ = "";

        Type type_;

        mixin(bitfields!(
            bool, "is_created_", 1,
            bool, "is_source_set_", 1,
            bool, "is_compiled_", 1,
            ubyte, "_padding", 5,
        ));
    }

    @property @safe @nogc nothrow {
        // you can look but not touch ;)
        bool is_created() const => this.is_created_;
        bool is_source_set() const => this.is_source_set_;
        bool is_compiled() const => this.is_compiled_;

        Type type() const => type_;
        uint id() const => this.id_; 
        string name() const => this.name_;
    }

    // Wrapper to glCreateShader
    static
    GLResult!Shader create_shader(string name, Type type)
    {
        auto res = gl_wrap!glCreateShader(cast(uint)type);
        // error handling
        switch(res.error.error_flag)
        {
            case GLInternalError.NO_ERROR:
                if (res.value == 0) goto default;
                break;
            case GLInternalError.INVALID_ENUM:
                return GLResult!Shader(
                        GLError(
                            "glCreateShader",
                            GLError.Flag.INVALID_ENUM,
                            "Type %s is not a valid shader type".format(type)));
            default:
                return GLResult!Shader(GLError("create_shader", GLError.Flag.UNKNOWN_ERROR));
        }
        Shader shader = Shader(name, type, res.value, true);
        return GLResult!Shader(shader);
    }

    //  TODO: Might want to add file and line as template params
    static GLResult!Shader from_src(string name, Type type, string src)
    {
        GLResult!Shader shader_res = Shader.create_shader(name, type);
        if (!shader_res.is_error())
            if (auto res = shader_res.value.set_source(src))
                return GLResult!Shader(res.error);
        return shader_res;
    }

    // TODO:
    // maybe remove this function or put it a version block
    static GLResult!Shader from_file(string name, Type type, string file_name)
    {
        import std.file;

        auto shader_res = Shader.create_shader(name, type);
        if (shader_res.is_error())
            return shader_res;

        Shader shader = shader_res.value;

        if (auto res = shader.set_source(std.file.readText(file_name)))
            return GLResult!Shader(res.error);

        return glresult(shader);
    }

    /+
        Intialize shader with values.

        If you have already successfully called `glCreateShader`,
       `glShaderSource` and `glCompileShader` then you can initialize like so:
        ```d
        auto shader = Shader("my_shader", shader_type, shader_id, all_ok: true);
        ```

        To actually create a shader use `Shader.create_shader`
    +/
    @safe @nogc nothrow 
    this
    (string name, Type type, uint id, bool created=false, bool source_set=false,
     bool compiled=false, bool all_ok=false)
    {
        this.name_ = name;
        this.type_ = type;
        this.id_ = id;
        this.is_created_ = created | all_ok;
        this.is_source_set_ = is_source_set_ | all_ok;
        this.is_compiled_ = is_compiled_ | all_ok;
    }

    /+
        PERHAPS TODO (Althought it might not be necessary):
        - Perhaps put this outside of Shader
        - and overload it
    +/

    // Kind of Wrapper to glShaderSource
    @trusted
    GLResult!void set_source(in string src)
    {
        // TODO: Add a null check for src

        if (!this.is_created)
            return glresult(GLError("set_source", GLError.Flag.INVALID_SHADER));

        immutable(char*) src_ptr = src.ptr;
        int len = cast(int)src.length;

        if (auto err = gl_wrap!glShaderSource(this.id_, 1, &src_ptr, &len).error) {
            return glresult(GLError("glShaderSource", err.to_glerror_flag()));
        }

        this.is_source_set_ = true;
        return glresult(GLError.NO_ERROR);
    }

    /* @safe */
    /+
        Wrapper to glCompileShader.

        This also calls get_param to validte compilation
    +/
    @trusted
    GLResult!void compile()
    {
        if (!is_created)
            return glresult(GLError("compile", GLError.Flag.INVALID_SHADER));

        if (!is_source_set)
            return glresult(GLError("compile", GLError.Flag.SHADER_SOURCE_NOT_SET));

        // Assume source is already set
        // should never happen
        if (auto err = gl_wrap!glCompileShader(this.id).error)
            return glresult(GLError("glCompileShader", err.to_glerror_flag()));

        GLResult!bool compile_res = this.get_param!(GLParam.COMPILE_STATUS);
        if (compile_res)
            return glresult(compile_res.error.append("\t[From]: compile\n"));

        // NOTE: add get_info_log
        if(!compile_res.value) {
            // Ignore retrun value, no error should occur at this point
            return glresult(GLError(
                        "compile", GLError.Flag.SHADER_COMPILATION_ERROR,
                        "\tHINT: Run get_info_log() to get extra information"));
        }

        this.is_compiled_ = true;
        return glresult(GLError.NO_ERROR);
    }

    // Wrap glShaderSource and glCompileShader
    @safe
    GLResult!void compile_src(in string src)
    {
        if (auto res = this.set_source(src))
            return glresult(res.error.append("[From]: compile_src\n"));


        if (auto res = this.compile())
            return glresult(res.error.append("[From]: compile_src\n"));

        return glresult(GLError.NO_ERROR);
    }

    // NOTE: this functions might be redundant, also it throws
    @safe
    GLResult!void compile_f(in string file_name)
    {
        import std.file;
        // TODO: Handle exception
        string shader_src = std.file.readText(file_name);

        return this.compile_src(shader_src);
    }

    string toString() const
        => "Shader(name: %s, type: %s, id: %d, created: %s, source_set: %s, compiled: %s)"
                    .format(this.name, this.type, this.id, this.is_created,
                            this.is_source_set, this.is_compiled);
}

struct Program
{
    private {
        uint id_ = 0;
        string name_ = "";
        // TODO: might add a way to cache uniforms
        mixin(bitfields!(
            bool, "is_created_", 1,
            bool, "is_attached_", 1,
            bool, "is_linked_", 1,
            bool, "is_validated_", 1,
            ubyte, "_padding", 4,
        ));
    }

    @property @safe @nogc nothrow {
        bool is_created() const => this.is_created_;
        bool is_attached() const => this.is_attached_;
        bool is_linked() const => this.is_linked_;
        bool is_validated() const => this.is_validated_;

        uint id() const => this.id_; 
        string name() const => this.name_; 
    }

    this(string program_name, int program_id, bool created = false)
    {
        this.name_ = program_name;
        this.id_ = program_id;
        this.is_created_ = created;
    }

    // Wrapper to glCreateProgram
    static GLResult!Program create_program(string program_name)
    {
        int prog_id = trust!glCreateProgram();

        if (prog_id == 0) { // something went wrong
            return GLResult!Program(GLError.UNKNOWN_ERROR);
        }

        Program program = Program(program_name, prog_id, true);
        return glresult(program);

    }

    // Wrapper to glAttachShader
    // TODO: maybe check GL_ATTACHED_SHADERS to check if number of shaders
    // attached is what we expect
    @trusted
    GLResult!void attach(ref Shader s)
    {
        if (!this.is_created) {
            return glresult(GLError.INVALID_PROGRAM);
        }

        // program.id should be a valid OpenGL program at this point
        switch(gl_wrap!glAttachShader(this.id_, s.id_).error.error_flag) {
            case GLInternalError.NO_ERROR:
                this.is_attached_ = true;
                return glresult(GLError.NO_ERROR);

            case GLInternalError.INVALID_OPERATION:
            {
                if (!s.is_created) {
                    return glresult(GLError("glAttachShader", GLError.Flag.INVALID_SHADER));
                }
                else if (!s.is_compiled) {
                    return glresult(GLError("glAttachShader", GLError.Flag.INVALID_SHADER));
                }
                else { // if shader `s` is compiled this is the only possibility
                    return glresult(GLError("glAttachShader", GLError.Flag.SHADER_ALREADY_ATTACHED));
                }
            }
            default:
                return glresult(GLError.UNKNOWN_ERROR);
        }
    }

    // Wrapper to glLinkProgram
    // TODO: finsih fixing glresult here
    @trusted
    GLResult!void link()
    {
        if (!this.is_attached) { // not a single shader is attached
            return glresult(GLError.INVALID_PROGRAM);
        }

        opengl_clear_errors();
        // TODO: wrap this
        glLinkProgram(this.id_);

        GLInternalError internal_err = opengl_get_error();
        switch(internal_err)
        {
            case GLInternalError.NO_ERROR: break;
            case GLInternalError.INVALID_OPERATION:
                return glresult(GLError.UNKNOWN_ERROR); 
            default:
                return glresult(GLError.UNKNOWN_ERROR);
        }

        int linked = 0;
        if (GLError error = this.get_param(GLParam.LINK_STATUS, linked))
            return glresult(error);

        if (!linked) {
            /* string error_msg; */
            /* auto _ = this.get_info_log(error_msg); */
            return glresult(GLError.PROGRAM_LINK_ERROR);
        }

        this.is_linked_ = true;
        return glresult(GLError.NO_ERROR);
    }

    // Wrapper to glValidateProgram
    // TODO:
    //  - ~~Hmm, maybe I shouldn't throw in here and return bool instead~~ I think I fixed this
    //  - take care of potential geometry shader shenanigans later
    @trusted
    GLResult!void validate()
    {
        if (!this.is_linked) // not a single shader is attached
            return glresult(GLError.INVALID_PROGRAM);

        int validated = 0;
        // Shouldn't raise any errors
        glValidateProgram(this.id);

        if (GLError error = this.get_param(GLParam.VALIDATE_STATUS, validated))
            return glresult(error);

        if (!validated) {
            /* string error_msg; */
            /* auto _ = this.get_info_log(error_msg); */
            return glresult(GLError.PROGRAM_VALIDATION_ERROR);
        }
        this.is_validated_ = true;
        return glresult(GLError.NO_ERROR);
    }

    // Wrapper to glUseProgram
    @trusted
    void use() inout
    {
        // NOTE: in theory if this.id_ is 0 it shouldn't be an error in OpenGL
        // but it really makes no sense to use an invalid program.
        // Make a `Program.stop_using()` or `Program.use_empty()`
        trust!glUseProgram(this.id_);
    }

    // Cool convinience function
    // Might be cool to use a variadic template here with `ref Shader`
    // this solutions is ok thought
    @safe
    GLResult!void prepare_and_attach(Shader*[] shaders ...)
    {
        foreach (Shader *shader; shaders) {
            // TODO: do something with error here
            // if a shader fails compilation exit
            if (auto res = shader.compile()) return res;
            if (auto res = this.attach(*shader)) return res;
        }

        if (auto res = this.link()) return res;
        if (auto res = this.validate()) return res;

        // Everythin ok
        return glresult(GLError.NO_ERROR);
    }

    // Wrapper to glUniformLocation
    @trusted
    int get_uniform_loc(string u_name) inout
    /* out(result; result > 0) */
    {
        import std.stdio;
        import std.string   : toStringz;
        // TODO: add checks and stuff
        int loc = trust!glGetUniformLocation(this.id, u_name.toStringz);
        if (loc < 0) {
            // TODO: use `std.logger` and put this in a version block
            stderr.writeln("[GL_WARNING]: "~u_name~" is not an active uniform name");
        }
        return loc;
    }
}

GLError get_param
(ref inout(Shader) self, GLParam param, out int val,
 string file = __FILE__, size_t line = __LINE__)
{
    if (!self.is_created)
        return GLError.INVALID_SHADER;

    opengl_clear_errors();
    glGetShaderiv(self.id, cast(int)param, &val);

    GLError err = GLError.NO_ERROR;
    GLInternalError internal_err = opengl_get_error();

    with(GLInternalError)
    switch(internal_err)
    {
        case NO_ERROR: break; // do nothing
        case INVALID_ENUM:
        {
            err = GLError.INVALID_PARAMETER;
        } break;
        default:
        {
            err = GLError.UNKNOWN_ERROR;
        }
    }
    return err;
}

// NOTE: I feel like it might make sense to use GLResult here... 
// NOTE: can't make this auto ref for some reason
// Get param for Program
GLError get_param
(ref inout(Program) self, GLParam param, out int val)
{
    if (!self.is_created)
        return GLError.INVALID_PROGRAM;

    opengl_clear_errors();
    glGetProgramiv(self.id, cast(int)param, &val);

    GLError err = GLError.NO_ERROR;
    GLInternalError internal_err = opengl_get_error();

    with(GLInternalError)
    switch(internal_err)
    {
        case NO_ERROR: break; // do nothing
        case INVALID_ENUM: goto case INVALID_OPERATION;
        case INVALID_OPERATION:
            err = GLError.INVALID_PARAMETER;
            break;
        default:
            err = GLError.UNKNOWN_ERROR;
            break;
    }
    return err;
}

alias ParamReturnTypes = AliasSeq!(
    Shader.Type, // SHADER_TYPE
    bool, // DELETE_STATUS
    bool, // COMPILE_STATUS
    int, // INFO_LOG_LENGTH
    int, // SHADER_SOURCE_LENGTH
    bool, // LINK_STATUS
    bool, // VALIDATE_STATUS
);


private template getParamReturnType(GLParam p)
{
    import std.traits   : EnumMembers;

    private template getParamReturnType_(int i, GLParam p)
    {
        static if (i == ParamReturnTypes.length) {
            alias getParamReturnType_ = void;
        }
        else static if (EnumMembers!GLParam[i] == p) // found
        {
            alias getParamReturnType_ = ParamReturnTypes[i];
        }
        else
            alias getParamReturnType_ = getParamReturnType_!(i+1, p);
    }

    alias getParamReturnType = getParamReturnType_!(0, p);
}

private template get_param_(S, T)
{
    GLResult!T get_param_(Param p)(ref inout(S) self)
    {
        int _val;
        GLError err = get_param(self, p, _val);
        return GLResult!T(cast(T)_val, err);
    }
}

private enum isValidTypeForParam(T, GLParam p) =
        (is(T == Shader) && p.is_shader_param()) ||
        (is(T == Program) && p.is_program_param());

private template get_param_(GLParam p)
{
    alias T = getParamReturnType!p;

    static assert(!is(T == void));

    GLResult!T get_param_(S)(ref inout(S) self) if (isValidTypeForParam!(S, p))
    {
        int _val;
        GLError err = get_param(self, p, _val);
        return GLResult!T(err, cast(T)_val);
    }
}

alias get_param(GLParam p) = get_param_!p;
