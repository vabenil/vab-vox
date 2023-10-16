module vadgl.types;

import bindbc.opengl;

// could make this module
enum GLType
{
    // Basic GL types
    BYTE = GL_INT,
    UBYTE = GL_UNSIGNED_BYTE,

    SHORT = GL_SHORT,
    USHORT = GL_UNSIGNED_SHORT,

    INT = GL_INT,
    UINT = GL_UNSIGNED_INT,

    FLOAT = GL_FLOAT,
    DOUBLE = GL_DOUBLE,

    // Vector types
    VEC2 = GL_FLOAT_VEC2,
    VEC3 = GL_FLOAT_VEC3,
    VEC4 = GL_FLOAT_VEC4,

    IVEC2 = GL_INT_VEC2,
    IVEC3 = GL_INT_VEC3,
    IVEC4 = GL_INT_VEC4,

    // Add a bool vectors here

    // Requires gl30
    UVEC2 = GL_UNSIGNED_INT_VEC2,
    UVEC3 = GL_UNSIGNED_INT_VEC3,
    UVEC4 = GL_UNSIGNED_INT_VEC4,

    // TODO: Add matrix types
}

// TODO: maybe make module
enum GLFuncEnum
{
    GENERAL = 0, // General OpenGL error for any function
    ENABLE_VERTEX_ATTRIB_ARRAY,
    ENABLE_DISABLE_ATTRIB_ARRAY,
    SHADER_COMPILE,

    PROGRAM_ATTACH,
    PROGRAM_LINK,
    PROGREM_VALIDATE,

    BIND,
}

// TODO: make this support multiple OpenGL versions
enum GLInternalError
{
    NO_ERROR                       = GL_NO_ERROR,
    INVALID_ENUM                   = GL_INVALID_ENUM,
    INVALID_VALUE                  = GL_INVALID_VALUE,
    INVALID_OPERATION              = GL_INVALID_OPERATION,
    STACK_OVERFLOW                 = GL_STACK_OVERFLOW,
    STACK_UNDERFLOW                = GL_STACK_UNDERFLOW,
}

enum GLParam {
    SHADER_TYPE               =  GL_SHADER_TYPE,
    DELETE_STATUS             =  GL_DELETE_STATUS,
    COMPILE_STATUS            =  GL_COMPILE_STATUS,
    INFO_LOG_LENGTH           =  GL_INFO_LOG_LENGTH,
    SHADER_SOURCE_LENGTH      =  GL_SHADER_SOURCE_LENGTH,

    LINK_STATUS               =  GL_LINK_STATUS,
    VALIDATE_STATUS           =  GL_VALIDATE_STATUS,
    ATTACHED_SHADERS          =  GL_ATTACHED_SHADERS,

    // Only in OpenGL >=  3.2
    GEOMETRY_VERTICES_OUT     =  GL_GEOMETRY_VERTICES_OUT,
    GEOMETRY_INPUT_TYPE       =  GL_GEOMETRY_INPUT_TYPE,
    GEOMETRY_OUTPUT_TYPE      =  GL_GEOMETRY_OUTPUT_TYPE,
}
