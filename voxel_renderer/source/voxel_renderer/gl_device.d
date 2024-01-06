// Meant to be used with gl_renderere
module voxel_renderer.gl_device;

import common   : vec3, ivec3, Color4b;

import bindbc.opengl;
import vadgl;

public import voxel_renderer.device;

// Instance renderer
static immutable string vertex_source = q{
    #version 330 core

    layout(location=0) in ivec2 model_pos;
    layout(location=1) in ivec3 pos;
    layout(location=2) in vec4 color;
    layout(location=3) in uint packed_size;

    uniform mat4 u_trans_mat;

    out vec4 v_color;
    out vec3 v_pos;

    uvec3[3] identity = uvec3[3](
        uvec3(1u, 0u, 0u),
        uvec3(0u, 1u, 0u),
        uvec3(0u, 0u, 1u)
    );

    vec3 get_world_pos()
    {
        uint face_id, dim, sbit;
        // get dimension and sign bit from packed data
        face_id = uint(packed_size & 0x7u);
        dim = face_id % 3u;
        sbit = uint(face_id > 2u);

        vec3 delta = vec3(uvec3(identity[dim]) & sbit);
        vec3 face_pos = vec3(pos) + delta;

        // Model position to 3d
        vec3 m_pos = vec3(0);
        m_pos[(dim + 1u) % 3u] = float(model_pos[0]);
        m_pos[(dim + 2u) % 3u] = float(model_pos[1]);

        return face_pos + m_pos;
    }

    void main()
    {
        /* vec3 world_pos = vec3(model_pos, 0.0f) + pos; */
        vec3 w_pos = get_world_pos();

        v_color = color;
        /* v_color = vec4(1, 6.0f / (6.0f - float(int(packed_size))), 1, 1); */
        v_pos = w_pos;
        /* gl_Position =  vec4(w_pos, 1) * u_trans_mat; */
        gl_Position =  u_trans_mat * vec4(w_pos, 1);
    }
};

static immutable string _ = q{
    #version 330 core

    layout(location=1) in ivec3 pos;
    layout(location=2) in vec4 color;

    uniform mat4 u_mpv;

    out vec4 v_color;
    out vec3 v_pos;

    void main()
    {
        v_color = color;
        v_pos = pos;
        gl_Position =  vec4(pos, 1) * u_mpv;
    }
};
static immutable string frag_source = q{
    #version 330 core

    in vec3 v_pos;
    in vec4 v_color;

    out vec4 color;

    void main()
    {
        color = v_color;
    }
};

private {
    alias gl_ivec2 = int[2];
    alias gl_ivec3 = int[3];
    alias gl_ivec4 = int[4];

    alias gl_uvec2 = int[2];
    alias gl_uvec3 = int[3];
    alias gl_uvec4 = int[4];

    alias gl_ubvec2 = ubyte[2];
    alias gl_ubvec3 = ubyte[3];
    alias gl_ubvec4 = ubyte[4];

    alias gl_vec2 = float[2];
    alias gl_vec3 = float[3];
    alias gl_vec4 = float[4];
}

// Can be reduced to 12 bytes
// Also if I reaaally tried I could get it down to 8 bytes
struct VoxelVertex
{
    ivec3 pos;
    Color4b color;
    uint packed_data;
}

struct Packed
{
    import std.bitmanip : bitfields;

    mixin(bitfields!(
        ubyte, "face_id", 3,
        uint, "material_id", 29
    ));

    this(uint face_id, uint material)
    {
        this.face_id = cast(ubyte)face_id;
        this.material_id = material;
    }
}

// Device for instance rendering
class GLDevice : VoxelDevice
{
    static immutable int[8] QUAD_MODEL = [
        0, 0,
        0, 1,
        1, 1,
        1, 0
    ];

    // Could make it ubyte but honestly it doesn't make a difference
    static immutable uint[6] QUAD_INDICES = [0, 1, 2, 2, 3, 0];

    enum AttribLoc
    {
        MODEL_POS = 0,
        POS,
        COLOR,
        MATERIAL,
    }

    void[] buffer;
    private {
        size_t face_count = 0;
        // This uses GC. Dont use GC

        VArrayObject vao;
        // TODO: We might need another vbo for far objects;
        VBufferObject vbo;
        VBufferObject ebo;
        VBufferObject model_vbo;

        // TODO: Use a template to automate this
        GLUniform[string] uniforms;
        GLAttributeInfo[string] attributes;

        Program program;
    }

    // TODO: I Prob got to normalize it
    void set_mpv_matrix(const(float[16]) mat, bool normalize=false)
        => uniforms["u_trans_mat"].set_mat4(mat, normalize).throw_on_error();

    void set_mpv_matrix(const(float[4][4]) mat, bool normalize=false)
        => set_mpv_matrix(cast(const(float[16]))mat, normalize);

    void set_camera(vec3 pos, vec3 dir, vec3 up) {}

    void enable_gl_settings()
    {
        import bindbc.opengl;
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        // TODO: add this to vadgl
        glEnable(GL_DEPTH_TEST);
        glEnable(GL_BLEND);
    }

    // This function can throw
    void device_init()
    {
        import std.stdio;
        import bindbc.opengl;
        writeln("device_init()");

        Shader vert_sh, frag_sh;
        vert_sh = Shader.from_src("vertex", Shader.Type.VERTEX, vertex_source).throw_on_error();
        frag_sh = Shader.from_src("frag", Shader.Type.FRAGMENT, frag_source).throw_on_error();

        program = Program.create_program("program").throw_on_error();
        // Compile, attach and link shaders, then validate
        if (auto res = program.prepare_and_attach(&vert_sh, &frag_sh)) {
            stderr.writeln(res.error.to_error_msg());
            stderr.writeln(vert_sh.get_info_log().throw_on_error());
            stderr.writeln(frag_sh.get_info_log().throw_on_error());
            assert(0);
        }
        program.use().throw_on_error();

        // Create buffers
        vao = VArrayObject.create().throw_on_error();
        vbo = VBufferObject.create().throw_on_error();
        ebo = VBufferObject.create(GL_ELEMENT_ARRAY_BUFFER).throw_on_error();
        model_vbo = VBufferObject.create().throw_on_error();

        // Send ebo data
        ebo.bind(GL_ARRAY_BUFFER).throw_on_error(); // Set target for model
        ebo.set_data(QUAD_INDICES[], GL_STATIC_DRAW).throw_on_error();

        // Send model data
        model_vbo.bind().throw_on_error();
        model_vbo.set_data(QUAD_MODEL[], GL_STATIC_DRAW).throw_on_error();

        VBufferObject.disable(GL_ARRAY_BUFFER);

        enum uint vertex_size = 20;

        uniforms["u_trans_mat"] = GLUniform.from_name("u_trans_mat", program.id).throw_on_error();

        attributes = [
            "model_pos": glattribute!gl_ivec2(loc: AttribLoc.MODEL_POS, offset_: 0),
            "pos": glattribute!gl_ivec3(loc: AttribLoc.POS, offset_: 0),
            "color": glattribute!gl_ubvec4(loc: AttribLoc.COLOR, offset_: 12, normalized: true),
            "packed_size": glattribute!uint(loc: AttribLoc.MATERIAL, offset_: 16),
        ];

        // TODO: set mpv matrix uniform here
        vao.bind().throw_on_error();
        ebo.bind().throw_on_error();
        model_vbo.bind().throw_on_error();

        // set the `model_vbo` attribute
        attributes["model_pos"].enable().throw_on_error();
        attributes["model_pos"].setI((int[2]).sizeof).throw_on_error();
        attributes["model_pos"].set_divisor(0).throw_on_error();

        vbo.bind().throw_on_error();

        // set `vbo` attributes
        attributes["pos"].setI(vertex_size).throw_on_error();
        attributes["color"].set(vertex_size).throw_on_error();
        attributes["packed_size"].setI(vertex_size).throw_on_error();

        attributes["pos"].enable().throw_on_error();
        attributes["color"].enable().throw_on_error();
        attributes["packed_size"].enable().throw_on_error();

        attributes["pos"].set_divisor(1).throw_on_error();
        attributes["color"].set_divisor(1).throw_on_error();
        attributes["packed_size"].set_divisor(1).throw_on_error();

        vao.disable(); // ALWAYS unbind vao first

        gl_clear_color(1.0, 1.0, 1.0f, 1.0f);
    }

    void commit_face(ivec3 pos, Color4b color, uint face_id, uint material)
    {
        this.buffer ~= pos.array;
        this.buffer ~= color.rgba;
        this.buffer ~= [Packed(face_id, material)];
        face_count++;
    }

    // NOTE: this function is not optimal
    void commit_cube(ivec3 pos, Color4b color, uint packed_data)
    {
        for (int i = 0; i < 6; i++) {
            this.commit_face(pos, color, i, packed_data);
        }
    }

    /*
        TODO: Probably best idea is to make a big buffer to store
        meshes for multiple buffers and then draw slices of the buffer
   */
    void send_to_device()
    {
        vbo.bind().throw_on_error();
        vbo.set_data(this.buffer, GL_STATIC_DRAW).throw_on_error();
    }

    void send_to_device(void[] buff)
    {
        vbo.bind().throw_on_error();
        vbo.set_data(buff, GL_STATIC_DRAW).throw_on_error();
    }

    void clear_buffer() { this.buffer.length = 0; }
    // TODO: Perhaps add a way to clear the buffer

    void render(int count)
    {
        import std.stdio;

        enable_gl_settings();
        program.use().throw_on_error();

        vao.bind().throw_on_error();

        // NOTE: This is not optimal at all, change this
        /* vbo.set_data(this.buffer, GL_STATIC_DRAW).throw_on_error(); */

        gl_draw_elements_instanced(GL_TRIANGLES, 6, GLType.UINT, null, count)
            .throw_on_error();

        vao.disable();
    }

    void render() { this.render(cast(int)this.face_count); }
}