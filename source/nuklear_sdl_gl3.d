/*
 * Nuklear - 1.32.0 - public domain
 * no warrenty implied; use at your own risk.
 * authored from 2015-2016 by Micha Mettke
 */
/*
 * ==============================================================
 *
 *                              API
 *
 * ===============================================================
 */
module nuklear_sdl_gl3;

public import nuklear;
import bindbc.opengl;
import bindbc.sdl;

import core.stdc.stdlib;
import core.stdc.string;

private
bool my_nk_init(nk_context* ctx, const(nk_user_font*) font)
{
    nk_allocator allocator;
    allocator.userdata.ptr = null;
    allocator.alloc = (handle, old, size) => malloc(size);
    allocator.free = (handle, ptr) => cast(void)free(ptr);
    return nk_init(ctx, &allocator, font);
}

struct nk_sdl_device {
    nk_buffer cmds;
    nk_draw_null_texture null_tex;
    GLuint vbo, vao, ebo;
    GLuint prog;
    GLuint vert_shdr;
    GLuint frag_shdr;
    GLint attrib_pos;
    GLint attrib_uv;
    GLint attrib_col;
    GLint uniform_tex;
    GLint uniform_proj;
    GLuint font_tex;
}

struct nk_sdl_vertex {
    float[2] position;
    float[2] uv;
    nk_byte[4] col;
}

struct nk_sdl {
    SDL_Window *win;
    nk_sdl_device ogl;
    nk_context ctx;
    nk_font_atlas atlas;
}

static nk_sdl sdl;

enum string NK_SHADER_VERSION = "#version 300 es\n";

void nk_sdl_device_create()
{
    GLint status;
    static const GLchar *vertex_shader = q{
        #version 300 es
        uniform mat4 ProjMtx;
        in vec2 Position;
        in vec2 TexCoord;
        in vec4 Color;
        out vec2 Frag_UV;
        out vec4 Frag_Color;
        void main() {
           Frag_UV = TexCoord;
           Frag_Color = Color;
           gl_Position = ProjMtx * vec4(Position.xy, 0, 1);
        }
    };
    static const GLchar *fragment_shader = q{
        #version 300 es
        precision mediump float;
        uniform sampler2D Texture;
        in vec2 Frag_UV;
        in vec4 Frag_Color;
        out vec4 Out_Color;
        void main(){
           Out_Color = Frag_Color * texture(Texture, Frag_UV.st);
        }
    };

    nk_sdl_device *dev = &sdl.ogl;
    nk_buffer_init_default(&dev.cmds);
    dev.prog = glCreateProgram();
    dev.vert_shdr = glCreateShader(GL_VERTEX_SHADER);
    dev.frag_shdr = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(dev.vert_shdr, 1, &vertex_shader, cast(int *)0);
    glShaderSource(dev.frag_shdr, 1, &fragment_shader, cast(int *)0);
    glCompileShader(dev.vert_shdr);
    glCompileShader(dev.frag_shdr);
    glGetShaderiv(dev.vert_shdr, GL_COMPILE_STATUS, &status);
    assert(status == GL_TRUE);
    glGetShaderiv(dev.frag_shdr, GL_COMPILE_STATUS, &status);
    assert(status == GL_TRUE);
    glAttachShader(dev.prog, dev.vert_shdr);
    glAttachShader(dev.prog, dev.frag_shdr);
    glLinkProgram(dev.prog);
    glGetProgramiv(dev.prog, GL_LINK_STATUS, &status);
    assert(status == GL_TRUE);

    dev.uniform_tex = glGetUniformLocation(dev.prog, "Texture");
    dev.uniform_proj = glGetUniformLocation(dev.prog, "ProjMtx");
    dev.attrib_pos = glGetAttribLocation(dev.prog, "Position");
    dev.attrib_uv = glGetAttribLocation(dev.prog, "TexCoord");
    dev.attrib_col = glGetAttribLocation(dev.prog, "Color");

    {
        /* buffer setup */
        GLsizei vs = nk_sdl_vertex.sizeof;
        size_t vp = nk_sdl_vertex.position.offsetof;
        size_t vt = nk_sdl_vertex.uv.offsetof;
        size_t vc = nk_sdl_vertex.col.offsetof;

        glGenBuffers(1, &dev.vbo);
        glGenBuffers(1, &dev.ebo);
        glGenVertexArrays(1, &dev.vao);

        glBindVertexArray(dev.vao);
        glBindBuffer(GL_ARRAY_BUFFER, dev.vbo);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, dev.ebo);

        glEnableVertexAttribArray(cast(GLuint)dev.attrib_pos);
        glEnableVertexAttribArray(cast(GLuint)dev.attrib_uv);
        glEnableVertexAttribArray(cast(GLuint)dev.attrib_col);

        glVertexAttribPointer(cast(GLuint)dev.attrib_pos, 2, GL_FLOAT, GL_FALSE, vs, cast(void*)vp);
        glVertexAttribPointer(cast(GLuint)dev.attrib_uv, 2, GL_FLOAT, GL_FALSE, vs, cast(void*)vt);
        glVertexAttribPointer(cast(GLuint)dev.attrib_col, 4, GL_UNSIGNED_BYTE, GL_TRUE, vs, cast(void*)vc);
    }

    glBindTexture(GL_TEXTURE_2D, 0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    glBindVertexArray(0);
}

void nk_sdl_device_upload_atlas(const void *image, int width, int height)
{
    nk_sdl_device *dev = &sdl.ogl;
    glGenTextures(1, &dev.font_tex);
    glBindTexture(GL_TEXTURE_2D, dev.font_tex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexImage2D(
        GL_TEXTURE_2D, 0, GL_RGBA,
        cast(GLsizei)width, cast(GLsizei)height, 0,
        GL_RGBA, GL_UNSIGNED_BYTE, image);
}

void nk_sdl_device_destroy()
{
    nk_sdl_device *dev = &sdl.ogl;
    glDetachShader(dev.prog, dev.vert_shdr);
    glDetachShader(dev.prog, dev.frag_shdr);
    glDeleteShader(dev.vert_shdr);
    glDeleteShader(dev.frag_shdr);
    glDeleteProgram(dev.prog);
    glDeleteTextures(1, &dev.font_tex);
    glDeleteBuffers(1, &dev.vbo);
    glDeleteBuffers(1, &dev.ebo);
    nk_buffer_free(&dev.cmds);
}

void nk_sdl_render(nk_anti_aliasing AA, int max_vertex_buffer, int max_element_buffer)
{
    nk_sdl_device *dev = &sdl.ogl;
    int width, height;
    int display_width, display_height;
    nk_vec2 scale;
    GLfloat[4][4] ortho = [
        [2.0f, 0.0f, 0.0f, 0.0f],
        [0.0f,-2.0f, 0.0f, 0.0f],
        [0.0f, 0.0f,-1.0f, 0.0f],
        [-1.0f,1.0f, 0.0f, 1.0f],
    ];
    SDL_GetWindowSize(sdl.win, &width, &height);
    SDL_GL_GetDrawableSize(sdl.win, &display_width, &display_height);
    ortho[0][0] /= cast(GLfloat)width;
    ortho[1][1] /= cast(GLfloat)height;

    scale.x = cast(float)display_width/cast(float)width;
    scale.y = cast(float)display_height/cast(float)height;

    /* setup global state */
    glViewport(0,0,display_width,display_height);
    glEnable(GL_BLEND);
    glBlendEquation(GL_FUNC_ADD);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glDisable(GL_CULL_FACE);
    glDisable(GL_DEPTH_TEST);
    glEnable(GL_SCISSOR_TEST);
    glActiveTexture(GL_TEXTURE0);

    /* setup program */
    glUseProgram(dev.prog);
    glUniform1i(dev.uniform_tex, 0);
    glUniformMatrix4fv(dev.uniform_proj, 1, GL_FALSE, &ortho[0][0]);
    {
        /* convert from command queue into draw list and draw to screen */
        const nk_draw_command *cmd;
        void *vertices, elements;
        const(nk_draw_index) *offset = null;
        nk_buffer vbuf, ebuf;

        /* allocate vertex and element buffer */
        glBindVertexArray(dev.vao);
        glBindBuffer(GL_ARRAY_BUFFER, dev.vbo);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, dev.ebo);

        glBufferData(GL_ARRAY_BUFFER, max_vertex_buffer, null, GL_STREAM_DRAW);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, max_element_buffer, null, GL_STREAM_DRAW);

        /* load vertices/elements directly into vertex/element buffer */
        vertices = glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY);
        elements = glMapBuffer(GL_ELEMENT_ARRAY_BUFFER, GL_WRITE_ONLY);
        {
            /* fill convert configuration */
            nk_convert_config config;
            static const(nk_draw_vertex_layout_element)[4] vertex_layout = [
                {
                    nk_draw_vertex_layout_attribute.NK_VERTEX_POSITION,
                    nk_draw_vertex_layout_format.NK_FORMAT_FLOAT,
                    nk_sdl_vertex.position.offsetof
                },
                {
                    nk_draw_vertex_layout_attribute.NK_VERTEX_TEXCOORD,
                    nk_draw_vertex_layout_format.NK_FORMAT_FLOAT,
                    nk_sdl_vertex.uv.offsetof
                },
                {
                    nk_draw_vertex_layout_attribute.NK_VERTEX_COLOR,
                    nk_draw_vertex_layout_format.NK_FORMAT_R8G8B8A8,
                    nk_sdl_vertex.col.offsetof
                },
                NK_VERTEX_LAYOUT_END
            ];

            memset(&config, 0, config.sizeof);
            config.vertex_layout = vertex_layout.ptr;
            config.vertex_size = nk_sdl_vertex.sizeof;
            config.vertex_alignment = nk_sdl_vertex.alignof;
            config.tex_null = dev.null_tex;
            config.circle_segment_count = 22;
            config.curve_segment_count = 22;
            config.arc_segment_count = 22;
            config.global_alpha = 1.0f;
            config.shape_AA = AA;
            config.line_AA = AA;

            /* setup buffers to load vertices and elements */
            nk_buffer_init_fixed(&vbuf, vertices, cast(nk_size)max_vertex_buffer);
            nk_buffer_init_fixed(&ebuf, elements, cast(nk_size)max_element_buffer);
            nk_convert(&sdl.ctx, &dev.cmds, &vbuf, &ebuf, &config);
        }
        glUnmapBuffer(GL_ARRAY_BUFFER);
        glUnmapBuffer(GL_ELEMENT_ARRAY_BUFFER);

        /* iterate over and execute each draw command */
        nk_draw_foreach(&sdl.ctx, &dev.cmds, (cmd) {
            if (!cmd.elem_count) return;
            glBindTexture(GL_TEXTURE_2D, cast(GLuint)cmd.texture.id);
            glScissor(cast(GLint)(cmd.clip_rect.x * scale.x),
                cast(GLint)((height - cast(GLint)(cmd.clip_rect.y + cmd.clip_rect.h)) * scale.y),
                cast(GLint)(cmd.clip_rect.w * scale.x),
                cast(GLint)(cmd.clip_rect.h * scale.y));

            uint gl_type =
                (nk_draw_index.sizeof == 4)
                    ? GL_UNSIGNED_INT
                    : GL_UNSIGNED_SHORT;
            glDrawElements(GL_TRIANGLES, cast(GLsizei)cmd.elem_count, gl_type, offset);
            offset += cmd.elem_count;
        });
        nk_clear(&sdl.ctx);
        nk_buffer_clear(&dev.cmds);
    }

    glUseProgram(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    glBindVertexArray(0);
    glDisable(GL_BLEND);
    glDisable(GL_SCISSOR_TEST);
}

static void
nk_sdl_clipboard_paste(nk_handle usr, nk_text_edit *edit)
{
    const char *text = SDL_GetClipboardText();
    if (text) nk_textedit_paste(edit, text, nk_strlen(text));
    cast(void)usr;
}

static void
nk_sdl_clipboard_copy(nk_handle usr, const char *text, int len)
{
    char *str = null;
    cast(void)usr;
    if (!len) return;
    str = cast(char*)malloc(cast(size_t)len+1);
    if (!str) return;
    memcpy(str, text, cast(size_t)len);
    str[len] = '\0';
    SDL_SetClipboardText(str);
    free(str);
}

nk_context* nk_sdl_init(SDL_Window *win)
{
    sdl.win = win;
    my_nk_init(&sdl.ctx, null);
    sdl.ctx.clip.copy = cast(nk_plugin_copy)&nk_sdl_clipboard_copy;
    sdl.ctx.clip.paste = cast(nk_plugin_paste)&nk_sdl_clipboard_paste;
    sdl.ctx.clip.userdata = nk_handle_ptr(null);
    nk_sdl_device_create();
    return &sdl.ctx;
}

void nk_sdl_font_stash_begin(nk_font_atlas **atlas)
{
    nk_font_atlas_init_default(&sdl.atlas);
    nk_font_atlas_begin(&sdl.atlas);
    *atlas = &sdl.atlas;
}

void nk_sdl_font_stash_end()
{
    const(void) *image; int w, h;
    image = nk_font_atlas_bake(&sdl.atlas, &w, &h, NK_FONT_ATLAS_RGBA32);
    nk_sdl_device_upload_atlas(image, w, h);
    nk_font_atlas_end(&sdl.atlas, nk_handle_id(cast(int)sdl.ogl.font_tex), &sdl.ogl.null_tex);
    if (sdl.atlas.default_font)
        nk_style_set_font(&sdl.ctx, &sdl.atlas.default_font.handle);

}

int nk_sdl_handle_event(SDL_Event *evt)
{
    nk_context *ctx = &sdl.ctx;
    if (evt.type == SDL_KEYUP || evt.type == SDL_KEYDOWN) {
        /* key events */
        bool down = evt.type == SDL_KEYDOWN;
        const ubyte* state = SDL_GetKeyboardState(null);
        SDL_Keycode sym = evt.key.keysym.sym;
        if (sym == SDLK_RSHIFT || sym == SDLK_LSHIFT)
            nk_input_key(ctx, NK_KEY_SHIFT, down);
        else if (sym == SDLK_DELETE)
            nk_input_key(ctx, NK_KEY_DEL, down);
        else if (sym == SDLK_RETURN)
            nk_input_key(ctx, NK_KEY_ENTER, down);
        else if (sym == SDLK_TAB)
            nk_input_key(ctx, NK_KEY_TAB, down);
        else if (sym == SDLK_BACKSPACE)
            nk_input_key(ctx, NK_KEY_BACKSPACE, down);
        else if (sym == SDLK_HOME) {
            nk_input_key(ctx, NK_KEY_TEXT_START, down);
            nk_input_key(ctx, NK_KEY_SCROLL_START, down);
        } else if (sym == SDLK_END) {
            nk_input_key(ctx, NK_KEY_TEXT_END, down);
            nk_input_key(ctx, NK_KEY_SCROLL_END, down);
        } else if (sym == SDLK_PAGEDOWN) {
            nk_input_key(ctx, NK_KEY_SCROLL_DOWN, down);
        } else if (sym == SDLK_PAGEUP) {
            nk_input_key(ctx, NK_KEY_SCROLL_UP, down);
        } else if (sym == SDLK_z)
            nk_input_key(ctx, NK_KEY_TEXT_UNDO, down && state[SDL_SCANCODE_LCTRL]);
        else if (sym == SDLK_r)
            nk_input_key(ctx, NK_KEY_TEXT_REDO, down && state[SDL_SCANCODE_LCTRL]);
        else if (sym == SDLK_c)
            nk_input_key(ctx, NK_KEY_COPY, down && state[SDL_SCANCODE_LCTRL]);
        else if (sym == SDLK_v)
            nk_input_key(ctx, NK_KEY_PASTE, down && state[SDL_SCANCODE_LCTRL]);
        else if (sym == SDLK_x)
            nk_input_key(ctx, NK_KEY_CUT, down && state[SDL_SCANCODE_LCTRL]);
        else if (sym == SDLK_b)
            nk_input_key(ctx, NK_KEY_TEXT_LINE_START, down && state[SDL_SCANCODE_LCTRL]);
        else if (sym == SDLK_e)
            nk_input_key(ctx, NK_KEY_TEXT_LINE_END, down && state[SDL_SCANCODE_LCTRL]);
        else if (sym == SDLK_UP)
            nk_input_key(ctx, NK_KEY_UP, down);
        else if (sym == SDLK_DOWN)
            nk_input_key(ctx, NK_KEY_DOWN, down);
        else if (sym == SDLK_LEFT) {
            if (state[SDL_SCANCODE_LCTRL])
                nk_input_key(ctx, NK_KEY_TEXT_WORD_LEFT, down);
            else nk_input_key(ctx, NK_KEY_LEFT, down);
        } else if (sym == SDLK_RIGHT) {
            if (state[SDL_SCANCODE_LCTRL])
                nk_input_key(ctx, NK_KEY_TEXT_WORD_RIGHT, down);
            else nk_input_key(ctx, NK_KEY_RIGHT, down);
        } else return 0;
        return 1;
    } else if (evt.type == SDL_MOUSEBUTTONDOWN || evt.type == SDL_MOUSEBUTTONUP) {
        /* mouse button */
        bool down = evt.type == SDL_MOUSEBUTTONDOWN;
        const int x = evt.button.x, y = evt.button.y;
        if (evt.button.button == SDL_BUTTON_LEFT) {
            if (evt.button.clicks > 1)
                nk_input_button(ctx, NK_BUTTON_DOUBLE, x, y, down);
            nk_input_button(ctx, NK_BUTTON_LEFT, x, y, down);
        } else if (evt.button.button == SDL_BUTTON_MIDDLE)
            nk_input_button(ctx, NK_BUTTON_MIDDLE, x, y, down);
        else if (evt.button.button == SDL_BUTTON_RIGHT)
            nk_input_button(ctx, NK_BUTTON_RIGHT, x, y, down);
        return 1;
    } else if (evt.type == SDL_MOUSEMOTION) {
        /* mouse motion */
        if (ctx.input.mouse.grabbed) {
            int x = cast(int)ctx.input.mouse.prev.x, y = cast(int)ctx.input.mouse.prev.y;
            nk_input_motion(ctx, x + evt.motion.xrel, y + evt.motion.yrel);
        } else nk_input_motion(ctx, evt.motion.x, evt.motion.y);
        return 1;
    } else if (evt.type == SDL_TEXTINPUT) {
        /* text input */
        nk_glyph glyph;
        memcpy(glyph.ptr, evt.text.text.ptr, NK_UTF_SIZE);
        nk_input_glyph(ctx, glyph.ptr);
        return 1;
    } else if (evt.type == SDL_MOUSEWHEEL) {
        /* mouse wheel */
        nk_input_scroll(ctx, nk_vec2(cast(float)evt.wheel.x, cast(float)evt.wheel.y));
        return 1;
    }
    return 0;
}

void nk_sdl_shutdown()
{
    nk_font_atlas_clear(&sdl.atlas);
    nk_free(&sdl.ctx);
    nk_sdl_device_destroy();
    memset(&sdl, 0, sdl.sizeof);
}
