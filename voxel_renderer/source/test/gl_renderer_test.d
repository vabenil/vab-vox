module test.gl_renderer_test;


unittest
{
    import common   : Vec3 = vec3, IVec3 = ivec3, Color4b;
    import bindbc.opengl;
    import bindbc.sdl;
    import vadgl;
    import inmath;

    import test.window;
    import test.sdl_ehandler;
    import test.camera;

    import voxel_renderer.gl_renderer;
    import voxel_renderer.gl_device;

    import voxel_grid.voxel_grid;
    import voxel_grid.chunk;
    import voxel_grid.voxel;

    import std.stdio;
    import std.format;

    import std.typecons     : Tuple, tuple;

    writeln("Starting gl_device test!");

    enum uint WIDTH = 600;
    enum uint HEIGHT = 400;

    Window win = Window("Voxel Renderer test", WIDTH, HEIGHT);

    SDL_SetRelativeMouseMode(true);

    bool quit = false;
    vec3 pos = vec3(15.0f, 4.0f, 0.0f);
    vec3 target = vec3(0.0f, 0.0f, 0.0f);

    // set camera
    Camera camera = Camera(pos, 60.0f, WIDTH, HEIGHT);
    camera.set_direction((target - camera.pos).normalized);
    camera.look_at(); // calculate view matrix

    writeln(camera.pitch, ", ", camera.yaw);
    writefln("[%(%(%s, %),\n%)]", camera.view.matrix);

    void on_mouse_move(SDL_Event *e)
    {
        camera.yaw += e.motion.xrel * camera.sensitivity;
        camera.pitch -= e.motion.yrel * camera.sensitivity;
        // Roll changes the up vector

        if (camera.pitch > 89.9f) camera.pitch = 89.9f;
        if (camera.pitch < -89.9f) camera.pitch = -89.9f;
    }

    void on_key_press(SDL_Event *e)
    {
        import std.stdio;
        SDL_Keysym keysym = e.key.keysym;
        auto mod = keysym.mod;

        vec3 dir = camera.direction;
        vec2 dir_2d = vec2(dir.x, dir.z).normalized;

        const float speed = 0.5;
        float x_increase = dir_2d.x * speed;
        float z_increase = dir_2d.y * speed;

        const ubyte* keyboard_state = SDL_GetKeyboardState(null);

        vec3 delta = vec3(0.0f);
        if (keyboard_state[SDL_SCANCODE_Q]) {
            quit = true; // quit game
        }

        if (keyboard_state[SDL_SCANCODE_A]) {
            delta.x += z_increase;
            delta.z += x_increase;
        }

        if (keyboard_state[SDL_SCANCODE_D]) {
            delta.x += -z_increase;
            delta.z += -x_increase;
        }

        if (keyboard_state[SDL_SCANCODE_W]) {
            delta.x += x_increase;
            delta.z += -z_increase;
        }
        if (keyboard_state[SDL_SCANCODE_SPACE] && !(mod & KMOD_SHIFT)) {
            delta.y += speed;
        }

        if (keyboard_state[SDL_SCANCODE_SPACE] && (mod & KMOD_SHIFT)) {
            delta.y += -speed;
        }

        if (keyboard_state[SDL_SCANCODE_S]) {
            delta.x += -x_increase;
            delta.z += z_increase;
        }

        // TODO: This could update multiple times a fram which is BAD
        camera.pos += delta;
    }

    alias MChunk = VoxelChunk!(Voxel, 5);

    GLDevice device = new GLDevice();
    device.device_init();

    auto renderer = new VoxelRenderer!MChunk(device);

    MChunk chunk;
    foreach (j; 0..MChunk.size) {
        foreach (i; 0..MChunk.size) {
            auto color = Color4b(cast(ubyte)((i+1) * 8), cast(ubyte)((j+1) * 8), 0);
            chunk[i, 0, j] = Voxel(color.to_hex);
        }
    }

    renderer.commit_chunk(chunk, IVec3(0, 0, 0));
    renderer.send_to_device();

    SDL_EHandler event_handler;
    event_handler.add_handler("quit", delegate(e) { quit = true; });
    event_handler.add_handler("mouse_move", &on_mouse_move);
    event_handler.add_handler("key_down", &on_key_press);
    while (!quit) {
        event_handler.handle_sdl_events(cast(void*)null);

        gl_clear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT).trust;
        /* writeln(camera.pitch, ", ", camera.yaw); */
        /* writeln(camera.pos); */

        /* camera.set_direction(); */
        camera.look_at();

        /* writeln(camera.proj); */
        device.set_mpv_matrix(camera.mpv(), true);
        renderer.render();
        /* renderer.get_device().render(); */
        win.swap_buffer();
    }
}
