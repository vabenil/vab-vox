// Meant to be used with gl_renderere
module voxel_renderer.gl_device;

import common   : vec3, ivec3, ivec4, Color4b;

import bindbc.opengl;
import vadgl;

public import voxel_renderer.device;

// Shader for indirect instance rendering
// Or just rendering chunk by chunk
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

/++
    TODO: use this.
    Basically idea is to send chunks to device and store rendering commands
    as DrawChunkCommand
 +/
struct DrawChunkCommand
{
    int[3] chunk_pos;
    int index;
    int size;
}

struct DrawChunkBatchCommand
{

}

struct DrawElementsIndirectCommand
{
    uint count;
    uint instance_count;
    uint index;
    int base_vertex;
    uint base_instance;
}

private void default_create_program(GLDevice device)
{
    import std.stdio;

    enum string vert_shader_path = "./res/shaders/multi_draw_elements_indirect.vert";
    enum string frag_shader_path = "./res/shaders/simple.frag";

    Shader vert_sh, frag_sh;
    vert_sh = Shader.from_file("vertex", Shader.Type.VERTEX, vert_shader_path).throw_on_error();
    frag_sh = Shader.from_file("frag", Shader.Type.FRAGMENT, frag_shader_path).throw_on_error();

    device.program = Program.create_program("program").throw_on_error();
    foreach (shader; [&vert_sh, &frag_sh]) {
        if (auto res = shader.compile()) {
            stderr.writeln(res.error.to_error_msg());
            stderr.writeln(get_info_log(*shader).throw_on_error());
            assert(0);
        }
    }

    device.program.attach(vert_sh, frag_sh).throw_on_error();
    device.program.link().throw_on_error;
    device.program.validate().throw_on_error;
    // Compile, attach and link shaders, then validate
    device.program.use().throw_on_error();
}

private void default_initialize_buffers(GLDevice dev)
{
    static immutable int[8] QUAD_MODEL = [
        0, 0,
        0, 1,
        1, 1,
        1, 0
    ];

    // Could make it ubyte but honestly it doesn't make a difference
    static immutable uint[6] QUAD_INDICES = [0, 1, 2, 2, 3, 0];

    // Create buffers
    dev.vao = VArrayObject.create().throw_on_error();
    dev.vbo = VBufferObject.create().throw_on_error();
    dev.ubo = VBufferObject.create(GL_UNIFORM_BUFFER).throw_on_error();
    dev.ibo = VBufferObject.create(GL_DRAW_INDIRECT_BUFFER).throw_on_error();
    dev.ebo = VBufferObject.create(GL_ELEMENT_ARRAY_BUFFER).throw_on_error();
    dev.model_vbo = VBufferObject.create().throw_on_error();

    dev.ubo.bind().throw_on_error();
    // Remember to realloc buffer if necessary
    dev.ubo.set_data((int[4]).sizeof * 256, null, GL_STREAM_DRAW).throw_on_error();
    gl_wrap!glBindBufferBase(GL_UNIFORM_BUFFER, 1, dev.ubo.id).throw_on_error();

    // Allocate enough for rendering 256 chunks
    dev.ibo.bind().throw_on_error();
    dev.ibo.set_data(DrawElementsIndirectCommand.sizeof * 256, null, GL_STREAM_DRAW).throw_on_error;

    // Send ebo data
    dev.ebo.bind().throw_on_error(); // Set target for model
    dev.ebo.set_data(QUAD_INDICES[], GL_STATIC_DRAW).throw_on_error();

    // Send model data
    dev.model_vbo.bind().throw_on_error();
    dev.model_vbo.set_data(QUAD_MODEL[], GL_STATIC_DRAW).throw_on_error();

    VBufferObject.disable(GL_ARRAY_BUFFER);
    VBufferObject.disable(GL_ELEMENT_ARRAY_BUFFER);
    VBufferObject.disable(GL_UNIFORM_BUFFER);
    VBufferObject.disable(GL_DRAW_INDIRECT_BUFFER);
}

private void default_initialize_uniforms(GLDevice dev)
{
    int prog = dev.program.id;

    dev.uniforms["u_trans_mat"] = GLUniform.from_name("u_trans_mat", prog).throw_on_error();
    dev.uniforms["u_chunk_size"] = GLUniform.from_name("u_chunk_size", prog).throw_on_error();
    dev.uniforms["u_camera_pos"] = GLUniform.from_name("u_camera_pos", prog).throw_on_error();
    dev.uniforms["u_chunk_pos"] = GLUniform.from_name("u_chunk_pos", prog).throw_on_error();
    dev.uniforms["u_chunk_count"] = GLUniform.from_name("u_chunk_count", prog).throw_on_error();

}

private void default_initialize_attributes(GLDevice dev)
{
    import bindbc.opengl;

    enum
    {
        MODEL_POS = 0,
        POS,
        COLOR,
        MATERIAL,
    }

    enum uint vertex_size = 20;

    dev.attributes = [
        "model_pos":    glattribute!gl_ivec2(loc: MODEL_POS, offset_: 0),
        "pos":          glattribute!gl_ivec3(loc: POS, offset_: 0),
        "color":        glattribute!gl_ubvec4(loc: COLOR, offset_: 12, normalized: true),
        "packed_size":  glattribute!uint(loc: MATERIAL, offset_: 16),
    ];

    // TODO: set mpv matrix uniform here
    dev.vao.bind().throw_on_error();
    dev.ibo.bind().throw_on_error();
    dev.ubo.bind().throw_on_error();
    dev.ebo.bind().throw_on_error();

    dev.model_vbo.bind().throw_on_error();
    // set the `model_vbo` attribute
    dev.attributes["model_pos"].enable().throw_on_error();
    dev.attributes["model_pos"].setI((int[2]).sizeof).throw_on_error();
    dev.attributes["model_pos"].set_divisor(0).throw_on_error();

    dev.vbo.bind().throw_on_error();

    // set `vbo` attributes
    dev.attributes["pos"].setI(vertex_size).throw_on_error();
    dev.attributes["color"].set(vertex_size).throw_on_error();
    dev.attributes["packed_size"].setI(vertex_size).throw_on_error();

    dev.attributes["pos"].enable().throw_on_error();
    dev.attributes["color"].enable().throw_on_error();
    dev.attributes["packed_size"].enable().throw_on_error();

    dev.attributes["pos"].set_divisor(1).throw_on_error();
    dev.attributes["color"].set_divisor(1).throw_on_error();
    dev.attributes["packed_size"].set_divisor(1).throw_on_error();

    dev.vao.disable(); // ALWAYS unbind vao first
    dev.vbo.disable();
    dev.ebo.disable();
    dev.ibo.disable();
    dev.ubo.disable();
    dev.model_vbo.disable();
}

/+
    NOTE: I'm still figuring out the general interface for this thing.
    I will learn a bunch of stuff if I ever rewrite this on another framework.

    Though the only real thing I would use asides from OpenGL is Vulkan since I'm
    not touching Metal or DirectX.

    NOTE: Yeah, so I'm having a lot of trouble on the difference between "device" and
    "renderer" in my case. For now the only difference is that the "device" doesn't
    depend on the "world" (though it's meant to be used to render said world).

    For the time being I guess the device can just hold the state of the OpenGL stuff
    and have "convenience" functions

    TODO:
        - ~Maybe serialize cubes or faces into "rendering commands" that will
             send vertex data into multiple vbos~.
             Note: `VoxelVertex` can be considered a rendering command. I should
            instead add `DrawChunkCommand`s. Also multiple vbos seem unnecessary
            to me at the moment

        - Then make `multi_render(ivec3[] chunk_coords)` which will render all
         those vertices.
+/
// Device for instance rendering
class GLDevice : VoxelDevice
{
    // This uses GC. Dont use GC
    void[] buffer;
    private {
        ulong face_count = 0;

        VArrayObject vao;
        // TODO: We might need another vbo for far objects;
        VBufferObject vbo;
        /++
            Contains ChunksHeader data so:

            // Realization. I don't need the indices
            {
                int[3] chunk_pos;
                int chunk_index; // offset in the buffer (in faces/instances)
                int chunk_size; // the amount of faces this chunk has
            }
         +/
        VBufferObject ubo; /// uniform buffer object
        VBufferObject ibo; /// indirect buffer object
        VBufferObject ebo;
        VBufferObject model_vbo;

        // TODO: Use a template to automate this
        GLUniform[string] uniforms;
        GLAttributeInfo[string] attributes;

        Program program;

        void function(GLDevice) create_program = &default_create_program;
        void function(GLDevice) initialize_buffers = &default_initialize_buffers;
        void function(GLDevice) initialize_uniforms = &default_initialize_uniforms;
        void function(GLDevice) initialize_attributes = &default_initialize_attributes;
    }

    // TODO: I Prob got to normalize it
    void set_mpv_matrix(const(float[16]) mat, bool normalize=false)
        => uniforms["u_trans_mat"].set_mat4(mat, normalize).throw_on_error();

    void set_mpv_matrix(const(float[4][4]) mat, bool normalize=false)
        => set_mpv_matrix(cast(const(float[16]))mat, normalize);

    void set_chunk_pos(ivec3 chunk_pos)
    {
        int[4][1] pos = [[chunk_pos.x, chunk_pos.y, chunk_pos.z, 0]];
        send_chunk_coords(pos[]);
    }

    void set_camera_pos(vec3 cam_pos)
        => uniforms["u_chunk_count"].set_v(cam_pos.array).throw_on_error();

    void set_chunk_count(int chunk_count)
        => uniforms["u_chunk_count"].set(chunk_count).throw_on_error();

    void set_chunk_size(int size)
        => uniforms["u_chunk_size"].set(size).throw_on_error();

    void set_camera(vec3 pos, vec3 dir, vec3 up) {}

    void enable_gl_settings() {
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
        writeln("device_init()");

        create_program(this);

        initialize_buffers(this);

        initialize_uniforms(this);

        initialize_attributes(this);

        /* gl_clear_color(1.0, 1.0, 1.0f, 1.0f); */
        int result;
        glGetIntegerv(GL_MAX_UNIFORM_LOCATIONS, &result);
        writeln("GL_MAX_UNIFORM_LOCATIONS: ", result);

        glGetIntegerv(GL_MAX_UNIFORM_BLOCK_SIZE, &result);
        writeln("GL_MAX_UNIFORM_BLOCK_SIZE: ", result);
    }

    void allocate_main_buffer(long size)
    {
        vbo.bind().throw_on_error();
        vbo.set_data(size, null, GL_STATIC_DRAW).throw_on_error();
        vbo.disable();
    }

    // This would be system because data may not have enough space
    void send_to_main_buffer(long offset, long size, const(void*) data)
    {
        import std.stdio;
        import std.algorithm    : map;
        vbo.bind().throw_on_error();
        vbo.set_sub_data(offset, size, data).throw_on_error();

        /* // For some reason second buffer is empty */
        /* VoxelVertex[] vertices = new VoxelVertex[](size / VoxelVertex.sizeof); */

        /* gl_wrap!glGetBufferSubData( */
        /*     GL_ARRAY_BUFFER, */
        /*     offset, */
        /*     size, */
        /*     cast(void*)vertices).throw_on_error(); */

        /* writeln("send: ", vertices, "; to buffer offset: ", offset); */

        vbo.disable();
    }

    // This is safe
    void send_to_main_buffer(long offset, const(void[]) data)
        => send_to_main_buffer(offset, data.length, data.ptr);

    void send_to_tmp_buffer(long size)
    {
        vbo.bind().throw_on_error();
        vbo.set_data(size, null, GL_STATIC_DRAW).throw_on_error();
        vbo.disable();
    }

    void send_to_device(void[] buff) // Send and allocate shit
    {
        vbo.bind().throw_on_error();
        vbo.set_data(buff, GL_STATIC_DRAW).throw_on_error();
        vbo.disable();
    }

    void send_indirect_commands(DrawElementsIndirectCommand[] draw_commands)
    {
        void[] command_buffer = draw_commands;

        ibo.bind().throw_on_error();
        ibo.set_sub_data(0, command_buffer).throw_on_error();
        /* ibo.disable(); */
    }

    /*
        TODO: Probably best idea is to make a big buffer to store
        meshes for multiple buffers and then draw slices of the buffer
   */
    void send_to_device() => this.send_to_device(this.buffer);

    void clear_buffer() { this.buffer.length = 0; }
    // TODO: Perhaps add a way to clear the buffer

    /* NOTE: This coule be used to render multiple chunks more efficiently
       I don't know the difference between this 2 functions
        - glMultiDrawElementsIndirect
        - glDrawElementsIndirect
    */
    void multi_render(ivec3[] chunk_coords, int[] indices)
    {
        assert(0, "Not implmeented yet");
    }

    void send_chunk_coords(int[3][] chunk_coords) {}

    void send_chunk_coords(int[4][] chunk_coords)
    {
        /* import std.stdio; */
        /* writeln(chunk_coords); */
        ubo.bind().throw_on_error();
        ubo.set_sub_data(0, chunk_coords).throw_on_error();
        ubo.disable();
    }

    void multi_render_indirect(DrawElementsIndirectCommand[] draw_commands)
    {
        import std.stdio;
        import std.algorithm    : map;
        enable_gl_settings();
        program.use().throw_on_error();
        vbo.bind().throw_on_error();

        send_indirect_commands(draw_commands);

/*         foreach (draw_command; draw_commands) { */
/*             // For some reason second buffer is empty */
/*             VoxelVertex[] vertices = new VoxelVertex[](draw_command.instance_count); */

/*             auto start = draw_command.base_instance * VoxelVertex.sizeof; */
/*             gl_wrap!glGetBufferSubData( */
/*                 GL_ARRAY_BUFFER, */
/*                 start, */
/*                 draw_command.instance_count * VoxelVertex.sizeof, */
/*                 cast(void*)vertices).throw_on_error(); */

/*             writeln("buffer ", start, ": ", vertices.map!(vertex => vertex.packed_data)); */
/*         } */

        vao.bind().throw_on_error();
        gl_wrap!glMultiDrawElementsIndirect(
            GL_TRIANGLES, GL_UNSIGNED_INT, null,
            cast(int)draw_commands.length, 0
        ).throw_on_error;

        vao.disable();
        vbo.disable();
    }

    void render(uint start, uint count)
    {
        enable_gl_settings();
        program.use().throw_on_error();

        vao.bind().throw_on_error();

        // I don't really need to change representation of shit because anyway
        // I gotta love to get freaking rendering commands
        // Ok so here multi draw would kinda fit
        // Use this function
        gl_wrap!glDrawElementsInstancedBaseInstance(
            GL_TRIANGLES, 6, GLType.UINT, null, count, start,
        ).throw_on_error();
        /* gl_draw_elements_instanced(GL_TRIANGLES, 6, GLType.UINT, null, count) .throw_on_error(); */

        vao.disable();
    }

    void render(uint count) => render(0u, count);

    void render() { this.render(cast(int)this.face_count); }
}
