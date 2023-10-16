import bindbc.sdl;
import bindbc.opengl;

import std.string       : toStringz;
import std.format       : format;
import std.exception    : enforce;


struct Window
{
    enum Flag : uint
    {
        NONE                = 0,
        FULLSCREEN          = SDL_WINDOW_FULLSCREEN,
        FULLSCREEN_DESKTOP  = SDL_WINDOW_FULLSCREEN_DESKTOP,
        OPENGL              = SDL_WINDOW_OPENGL,
        SHOWN               = SDL_WINDOW_SHOWN, 
        HIDDEN              = SDL_WINDOW_HIDDEN, 
        BORDERLESS          = SDL_WINDOW_BORDERLESS, 
        RESIZABLE           = SDL_WINDOW_RESIZABLE, 
        MINIMIZED           = SDL_WINDOW_MINIMIZED, 
        MAXIMIZED           = SDL_WINDOW_MAXIMIZED, 

        INPUT_GRABBED       = SDL_WINDOW_INPUT_GRABBED,
        INPUT_FOCUS         = SDL_WINDOW_INPUT_FOCUS,
        MOUSE_FOCUS         = SDL_WINDOW_MOUSE_FOCUS,
        FOREIGN             = SDL_WINDOW_FOREIGN,
    }

    alias Flag this;

    @trusted
    static void set_opengl_attributes(int mayor_v, int minor_v)
    {
        // Use OpenGL 3.2
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, mayor_v);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, minor_v);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);

        SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
        SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
        SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
        SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 8);
        SDL_GL_SetAttribute(SDL_GL_BUFFER_SIZE, 32);

        // double buffered window
        SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    }

    static if (!bindbc.sdl.staticBinding)
    static void load_sdl()
    {
        SDLSupport ret = loadSDL();
        if (ret != sdlSupport)
            throw new Exception("BindBC_SDL: shared library failed to load");

        static if (bindSDLTTF)
            if (loadSDLTTF() < sdlTTFSupport)
                throw new Exception("Couldn't load SDL ttf");

        static if (bindSDLImage)
            if (loadSDLImage() < sdlImageSupport)
                throw new Exception("Couldn't load SDL Image");
    }

    static void load_opengl()
    {
        // TODO: stop using hard-coded opengl version
        GLSupport ret = loadOpenGL();
        if (ret < GLSupport.gl32) {
            throw new Exception("OpenGL version 3.2 or greater required");
        }

        set_opengl_attributes(3, 2);
    }

    // set to true if sdl and opengl where already manually loaded
    static bool sdl_loaded = false;
    static bool opengl_loaded = false;

    private {
        SDL_Window* sdl = null;
        SDL_GLContext ctx = null;
        bool success = false; // window created successfully
    }

    @safe
    this(SDL_Window* sdl, SDL_GLContext ctx, bool success)
    {
        this.sdl = sdl;
        this.ctx = ctx;
        this.success = success;
    }

    @trusted
    this(string title, uint width, uint height, Flag flags = Flag.NONE)
    {
        static if (!bindbc.sdl.staticBinding)
            if (!sdl_loaded)
                load_sdl();

        this.sdl = SDL_CreateWindow(
                title.toStringz(),
                SDL_WINDOWPOS_CENTERED,
                SDL_WINDOWPOS_CENTERED,
                width, height, Flag.OPENGL | flags
            );

        if (!this.sdl)
            throw new Exception("Couldn't create window");

        this.ctx = SDL_GL_CreateContext(this.sdl);
        if (!this.ctx)
            throw new Exception(
                "Failed to create window with SDL error: %s"
                .format(SDL_GetError())
            );

        if (SDL_Init(SDL_INIT_VIDEO) < 0)
            throw new Exception(
                "Failed to initialize SDL with SDL error: %s"
                .format(SDL_GetError())
            );

        if (!opengl_loaded)
            load_opengl();
    }

    ~this() @trusted
    {
        if (this.ctx)
            SDL_GL_DeleteContext(this.ctx);

        if (this.sdl) {
            SDL_DestroyWindow(this.sdl);
            SDL_Quit();
        }
    }

    @safe
    SDL_GLContext get_context() => this.ctx;

    @safe
    SDL_Window *get_sdl_win() => this.sdl;

    @trusted
    void get_position(out int w, out int h) => SDL_GetWindowPosition(this.sdl, &w, &h);

    @trusted
    void set_position(in int w, in int h) => SDL_SetWindowPosition(this.sdl, w, h);

    @trusted
    void get_size(out int w, out int h) => SDL_GetWindowSize(this.sdl, &w, &h);

    @trusted
    bool set_vsync(bool vsync) => (SDL_GL_SetSwapInterval(vsync) == 0);

    @trusted
    void swap_buffer() => SDL_GL_SwapWindow(this.sdl);

    @safe
    int width()
    {
        enforce(this.sdl);

        int w, _;
        this.get_size(w, _);
        return w;
    }

    @safe
    int height()
    {
        enforce(this.sdl);

        int _, h;
        this.get_size(_, h);
        return h;
    }
}
