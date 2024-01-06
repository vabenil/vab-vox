import std.stdio;

import bindbc.sdl;
import bindbc.opengl;

import camera;
import window;
import sdl_ehandler;

import common.color;
import common.types     : IVec3 = ivec3;

import inmath;


import voxel_grid.chunk;
import voxel_grid.voxel;

import voxel_renderer.gl_renderer;
import voxel_renderer.gl_device;

alias MChunk = VoxelChunk!(Voxel, 5);

struct GState
{
    enum int WINDOW_WIDTH = 600;
    enum int WINDOW_HEIGHT = 400;

    bool quit = false;
    Camera camera;
    Window win;
    VoxelRenderer!MChunk renderer;
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

    const float speed = 0.5;
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

void init_graphics()
{
    gstate.win = Window("Voxel engine", GState.WINDOW_WIDTH, GState.WINDOW_HEIGHT);

    SDL_SetRelativeMouseMode(true); // wrap this in Window
    glClearColor(0, 0, 0, 1); // wrap this in vadgl

    GLDevice device = new GLDevice();
    device.device_init();

    gstate.renderer = new VoxelRenderer!MChunk(device);

    MChunk chunk;
    MChunk chunk2;
    foreach (j; 0..MChunk.size) {
        foreach (i; 0..MChunk.size) {
            /* auto color = Color4b(cast(ubyte)((i+1) * 8), cast(ubyte)((j+1) * 8), 0); */
            chunk[i, 0, j] = Voxel(Color4b.GREEN.to_hex);
            chunk2[i, 0, j] = Voxel(Color4b.BLUE.to_hex);
        }
    }

    gstate.renderer.commit_chunk(chunk, IVec3(0, 0, 0));
    gstate.renderer.commit_chunk(chunk2, IVec3(1, 0, 0));
    gstate.renderer.send_to_device();

    writeln("face count - ", gstate.renderer.mesh_buffer.face_meshes.length);
}

void main_loop()
{
    import vadgl;

    SDL_EHandler event_handler;
    event_handler.add_handler("quit", delegate(e) { gstate.quit = true; });
    event_handler.add_handler("mouse_move", &on_mouse_move);
    event_handler.add_handler("key_down", &on_key_down);
    while (!gstate.quit) {
        event_handler.handle_sdl_events(&gstate);

        gl_clear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT).trust;
        /* writeln(camera.pitch, ", ", camera.yaw); */
        /* writeln(camera.pos); */

        /* camera.set_direction(); */
        gstate.camera.look_at();

        gstate.renderer.get_device().set_mpv_matrix(gstate.camera.mpv(), true);
        gstate.renderer.render_chunk(IVec3(0, 0, 0));
        gstate.renderer.render_chunk(IVec3(1, 0, 0));
        /* renderer.get_device().render(); */
        gstate.win.swap_buffer();
    }
}

/* void create_class_diagram() */
/* { */
/*     import duml_class_gen; */
/*     import voxel_grid.voxel_grid_array  : VoxelGridArray; */

/*     alias Grid = VoxelGridArray!Chunk; */

/*     static immutable string res = */
/*         create_uml_diagram!(Grid); */

/*     File diagram_f = File("diagram.dot", "w"); */
/*     diagram_f.write(res); */
/* } */

void main()
{
    vec3 pos = vec3(15.0f, 4.0f, 0.0f);
    vec3 target = vec3(1.0f * MChunk.size, 0.0f, 0.0f); // look at second chunk

    // set camera
    gstate.camera = Camera(pos, 60.0f, gstate.WINDOW_WIDTH, gstate.WINDOW_HEIGHT);
    gstate.camera.set_direction((target - gstate.camera.pos).normalized);
    gstate.camera.look_at(); // calculate view matrix

    writeln(gstate.camera.pitch, ", ", gstate.camera.yaw);
    writefln("[%(%(%s, %),\n%)]", gstate.camera.view.matrix);

    init_graphics();
    main_loop();
}
