import std.stdio;

import bindbc.sdl;
import bindbc.opengl;

import inmath;

import camera;
import window;
import sdl_ehandler;
import world;

import common.color;
import common.types     : IVec3 = ivec3, vec;
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
    /* enum int WINDOW_WIDTH = 960; */
    /* enum int WINDOW_HEIGHT = 540; */
    enum int WINDOW_WIDTH = 1152;
    enum int WINDOW_HEIGHT = 648;
    /* enum int WINDOW_WIDTH = 1920; */
    /* enum int WINDOW_HEIGHT = 1080; */

    bool grab_mouse = true;
    bool quit = false;
    Camera camera;
    Window win;
    VoxelRenderer!MChunk renderer;
    World!MChunk world;
}

// TODO: perhaps pass this as an argument instead of global
__gshared GState gstate;

void on_mouse_move(SDL_Event *e)
{
    gstate.camera.yaw += e.motion.xrel * gstate.camera.sensitivity;
    gstate.camera.pitch -= e.motion.yrel * gstate.camera.sensitivity;
    // Roll changes the up vector

    if (gstate.camera.pitch > 89.9f) gstate.camera.pitch = 89.9f;
    if (gstate.camera.pitch < -89.9f) gstate.camera.pitch = -89.9f;
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

    const ubyte *keyboard_state = SDL_GetKeyboardState(null);
    if (keyboard_state[SDL_SCANCODE_Q])
        gstate.quit = true;

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
        gstate.grab_mouse = !gstate.grab_mouse;
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

void init_globals()
{
    vec3 pos = vec3(15.0f, 8.0f, -15.0f);
    vec3 target = vec3(15, 8.0f, 15); // look at second chunk

    // set camera
    gstate.camera = Camera(pos, 60.0f, gstate.WINDOW_WIDTH, gstate.WINDOW_HEIGHT, 0.1f, 512);
    gstate.camera.set_direction((target - gstate.camera.pos).normalized);
    gstate.camera.look_at(); // calculate view matrix

    gstate.world = new World!MChunk();
    /* gstate.world.load_from_vox_file("./assets/SmallBuilding01.vox"); */

    // By Chupsmovil at https://opengameart.org/content/voxel-skeleton-set-v1
    // No modifications to the original asset where made
    gstate.world.load_from_vox_file("./assets/11_SKELLINGTON_CHAMPION.vox");

    /* gstate.world.load_from_vox_file("./assets/realistic_terrain.vox"); */
    /* gstate.world.load_from_vox_file("./assets/Plane04.vox"); */
    /* gstate.world.load_from_vox_file("./assets/11.vox"); */

}

void init_graphics()
{
    gstate.win = Window("Voxel engine", GState.WINDOW_WIDTH, GState.WINDOW_HEIGHT, GLVersion.GL46);
    gstate.win.set_vsync(false);

    /* SDL_SetRelativeMouseMode(gstate.grab_mouse); // wrap this in Window */
    glClearColor(0.3, 0.3, 0.3, 1); // wrap this in vadgl

    GLDevice device = new GLDevice();
    device.device_init();

    gstate.renderer = new VoxelRenderer!MChunk(device);
    gstate.renderer.allocate_buffers();

    foreach (pos, chunk; gstate.world) {
        gstate.renderer.commit_chunk(chunk, pos.vec());
    }

    gstate.renderer.send_to_device();

    writeln("face count - ",
            gstate.renderer.mesh_buffer.cpu_header.used +
            gstate.renderer.mesh_buffer.tmp_header.used);
}

void main_loop()
{
    import vadgl;
    import std.datetime.stopwatch;

    int ticks = 1;
    double duration_sum = 1;

    SDL_EHandler event_handler;
    event_handler.add_handler("quit", delegate(e) { gstate.quit = true; });
    event_handler.add_handler("mouse_move", &on_mouse_move);
    event_handler.add_handler("key_down", &on_key_down);
    while (!gstate.quit) {
        event_handler.handle_sdl_events(&gstate);

        SDL_SetRelativeMouseMode(gstate.grab_mouse); // wrap this in Window

        StopWatch watch = StopWatch(AutoStart.no);
        watch.start();
        gl_clear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT).trust;

        /* camera.set_direction(); */
        gstate.camera.look_at();

        gstate.renderer.get_device().set_mpv_matrix(gstate.camera.mpv(), true);

        foreach (pos, chunk; gstate.world) {
            gstate.renderer.queue_chunk(pos.vec(), chunk);
        }
        gstate.renderer.render();

        gstate.win.swap_buffer();

        watch.stop();
        double avg_dur = duration_sum / ticks;
        double fps = 1_000_000 / avg_dur; // don't count writeln

        if (ticks % 10 == 0)
            writeln(cast(int)fps);

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
