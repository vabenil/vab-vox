/++
    This is simply a demo for the voxel renderer. Mostly to check that everything
    is working well
++/

import std.stdio;

import bindbc.sdl;
import bindbc.opengl;

import inmath;

import camera;
import window;
import sdl_ehandler;
import world;

import common.color;
import common.types     : Vec3 = vec3, IVec3 = ivec3, vec;
import voxel_grid.chunk;
import voxel_grid.voxel;

import voxel_renderer.gl_renderer;
import voxel_renderer.gl_device;

/+ NOTE: smaller chunks mean less chunks, less chunks increases performance
    This is probably mostly because of the number of render calls. Could be
    mitageted by rendering chunks in batches
+/
alias MChunk = VoxelChunk!(Voxel, 6);

struct GState
{
    struct WinState
    {
        bool focused = true;
        bool grab_mouse = true;
        bool quit = false;
    }
    /* enum int WINDOW_WIDTH = 960; */
    /* enum int WINDOW_HEIGHT = 540; */
    enum int WINDOW_WIDTH = 1152;
    enum int WINDOW_HEIGHT = 648;
    /* enum int WINDOW_WIDTH = 1920; */
    /* enum int WINDOW_HEIGHT = 1080; */

    WinState prev_state;
    WinState win_state;

    Camera camera;
    Window win;
    GLVoxelRenderer!MChunk renderer;
    World!MChunk world;
}

// TODO: perhaps pass this as an argument instead of global
__gshared GState gstate;

bool should_grab_window()
{
    static bool has_window_focus_changed()
        => gstate.win_state.focused != gstate.prev_state.focused;

    static bool has_mouse_grab_changed()
        => gstate.win_state.grab_mouse != gstate.prev_state.grab_mouse;

    return has_window_focus_changed() || has_mouse_grab_changed();
}

bool should_grab_mouse()
{
    return gstate.win_state.focused && gstate.win_state.grab_mouse;
}

void on_mouse_move(SDL_Event *e)
{
    if (!gstate.win_state.focused)
        return;

    Camera* camera = &gstate.camera;
    camera.yaw += e.motion.xrel * gstate.camera.sensitivity;
    camera.pitch -= e.motion.yrel * camera.sensitivity;
    // Roll changes the up vector

    camera.pitch = camera.pitch.clamp(-80.0f, 80.0f);
}

void on_mouse_click(SDL_Event *e)
{
    import vabray;

    enum float MAX_DISTANCE = 64.0f;

    Camera* camera = &gstate.camera;
    auto world = gstate.world;
    // I gotta do some raycasting bullshit here

    bool is_left_click = (e.button.button == SDL_BUTTON_LEFT);
    if (is_left_click) {
        Vec3 direction = (cast(Vec3)camera.direction());
        direction[2] *= -1;

        Ray ray = Ray(camera.pos.vector.vec(), direction);

        foreach (float dist, IVec3 pos, IVec3 face; ray.raymarch()) {
            if (!world[pos.array].is_empty()) {
                writeln("Collision at ", pos);

                world[(pos + face).array] = Voxel(Color4b.BLUE.to_hex);
                auto chunk_pos = pos / MChunk.size;
                auto chunk = chunk_pos.array in world.chunk_map ;
                gstate.renderer.commit_chunk(*chunk, chunk_pos);
            }

            if (dist >= MAX_DISTANCE)
                break;
        }
    }
}

void on_key_down(SDL_Event* e)
{
    SDL_Keysym keysym = e.key.keysym;
    auto mod = keysym.mod;

    vec3 dir = gstate.camera.direction;
    vec2 dir_2d = vec2(dir.x, dir.z).normalized;

    static float speed = 0.5;
    float x_increase = dir_2d.x * speed;
    float z_increase = dir_2d.y * speed;

    // Don't do anything if window is not grabbed
    if (!gstate.win_state.focused)
        return;

    const ubyte *keyboard_state = SDL_GetKeyboardState(null);
    if (keyboard_state[SDL_SCANCODE_Q])
        gstate.win_state.quit = true;

    vec3 delta = vec3(0.0f);
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

    if (keyboard_state[SDL_SCANCODE_E]) {
        gstate.win_state.grab_mouse = !gstate.win_state.grab_mouse;
    }

    if (keyboard_state[SDL_SCANCODE_F]) {
        speed += 0.1 * ((mod & KMOD_SHIFT) ? -1 : 1);
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
    gstate.camera.pos += delta;
}

void on_window_focus(SDL_Event* e)
{
    if (e.window.event == SDL_WINDOWEVENT_FOCUS_GAINED) {
        gstate.win_state.focused = true;
    }
    else if (e.window.event == SDL_WINDOWEVENT_FOCUS_LOST) {
        gstate.win_state.focused = false;
    }
}

void init_globals()
{
    vec3 pos = vec3(15.0f, 8.0f, -15.0f);
    vec3 target = vec3(15, 8.0f, 15); // look at second chunk

    // set camera
    gstate.camera = Camera(pos, 60.0f, gstate.WINDOW_WIDTH, gstate.WINDOW_HEIGHT, 0.1f, 512);
    gstate.camera.set_direction((target - gstate.camera.pos).normalized);
    gstate.camera.look_at(); // calculate view matrix

    gstate.world = new World!MChunk();

    for (int j = 0; j < 256; j++)
    for (int i = 0; i < 256; i++)
        gstate.world.set_voxel([j-128, 0, i-128], Voxel(Color4b.WHITE.to_hex));
    /* gstate.world.load_from_vox_file("./res/assets/SmallBuilding01.vox"); */

    // By Chupsmovil at https://opengameart.org/content/voxel-skeleton-set-v1
    // No modifications to the original asset where made
    /* gstate.world.load_from_vox_file("./res/assets/11_SKELLINGTON_CHAMPION.vox", IVec3(-8, 1, -8)); */

    /* gstate.world.load_from_vox_file("./res/assets/realistic_terrain.vox"); */
    /* gstate.world.load_from_vox_file("./res/assets/Plane04.vox", IVec3(28, 64, 48)); */
    /* gstate.world.load_from_vox_file("./res/assets/Plane04.vox", IVec3(-48, 20, 48)); */
    /* gstate.world.load_from_vox_file("./res/assets/Plane04.vox", IVec3(-48, 190, 48)); */

    /* gstate.world.load_from_vox_file("./res/assets/11.vox", IVec3(-2, 0, 1) * 32); */
}

void init_graphics()
{
    gstate.win = Window("Voxel engine", GState.WINDOW_WIDTH, GState.WINDOW_HEIGHT, GLVersion.GL46);
    gstate.win.set_vsync(false);

    // wrap this in Window
    SDL_SetRelativeMouseMode(gstate.win_state.grab_mouse);
    glClearColor(0.3, 0.3, 0.3, 1); // wrap this in vadgl

    GLDevice device = new GLDevice();
    device.device_init();

    gstate.renderer = new GLVoxelRenderer!MChunk(device);
    gstate.renderer.device_init();

    foreach (pos, chunk; gstate.world) {
        gstate.renderer.load_chunk(chunk, pos.vec());
        gstate.renderer.queue_chunk(chunk, pos.vec());
    }

    gstate.renderer.send_to_device();

    // TODO: Maybe add a renderer.log_info();
    /* writeln("face count - ", gstate.renderer.mesh_container.buff_size); */
}

void update_state()
{
    if (should_grab_window())
        SDL_SetRelativeMouseMode(should_grab_mouse());

    gstate.prev_state = gstate.win_state;
}

void main_loop()
{
    import vadgl;
    import std.datetime.stopwatch;

    int ticks = 1;
    double duration_sum = 1;

    writeln("Chunk size: ", MChunk.size);

    SDL_EHandler event_handler;
    event_handler.add_handler("quit", delegate(e) { gstate.win_state.quit = true; });
    event_handler.add_handler("mouse_move", &on_mouse_move);
    event_handler.add_handler("mouse_click", &on_mouse_click);
    event_handler.add_handler("key_down", &on_key_down);
    event_handler.add_handler("window_focus", &on_window_focus);

    while (!gstate.win_state.quit) {
        event_handler.handle_sdl_events(&gstate);

        update_state();

        StopWatch watch = StopWatch(AutoStart.no);
        watch.start();
        gl_clear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT).trust;

        /* camera.set_direction(); */
        gstate.camera.look_at();

        gstate.renderer.get_device().set_camera_pos(gstate.camera.pos.vector.vec());
        gstate.renderer.get_device().set_mpv_matrix(gstate.camera.mpv(), true);

        gstate.renderer.render();

        gstate.win.swap_buffer();

        watch.stop();
        double avg_dur = duration_sum / ticks;
        double fps = 1_000_000 / avg_dur; // don't count writeln

        if (ticks % 10 == 0)
            writeln("pos: ", gstate.camera.pos, ", FPS: ", cast(int)fps);

        duration_sum += watch.peek.total!"usecs";
        ticks++;
    }
}

void main()
{
    init_globals();
    init_graphics();
    main_loop();
}
