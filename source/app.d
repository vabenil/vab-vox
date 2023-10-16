import std.stdio;

import bindbc.sdl;
import bindbc.opengl;

import window;
import sdl_ehandler;

struct GState
{
    enum int WINDOW_WIDTH = 600;
    enum int WINDOW_HEIGHT = 400;

    bool quit = false;
    Window win;
}

// TODO: perhaps pass this as an argument instead of global
GState gstate;

void on_key_down(SDL_Event* e)
{
    const ubyte *keyboard_state = SDL_GetKeyboardState(null);
    if (keyboard_state[SDL_SCANCODE_Q])
        gstate.quit = true;
}

void init_graphics()
{
    gstate.win = Window("Voxel engine", GState.WINDOW_WIDTH, GState.WINDOW_HEIGHT);
    glClearColor(0, 0, 0, 1); // wrap this in vadgl
}

void main_loop()
{
    SDL_EHandler ehandler;
    ehandler.add_handler("quit", (void *) { gstate.quit = true; });
    ehandler.add_handler("key_down", &on_key_down);
    while (!gstate.quit) {
        ehandler.handle_sdl_events(cast(void*)null);
        gstate.win.swap_buffer();
    }
}

void create_class_diagram()
{
    import duml_class_gen;
    import voxel_grid                   : Voxel, VoxelGrid;
    import voxel_grid.voxel_grid_array  : ChunkArray, VoxelGridArray;

    alias Chunk = ChunkArray!Voxel;
    alias Grid = VoxelGridArray!Chunk;

    static immutable string res =
        create_uml_diagram!(Grid);

    File diagram_f = File("diagram.dot", "w");
    diagram_f.write(res);
}

void main()
{
    import common.types : Vector;
    import voxel_grid;

    init_graphics();
    main_loop();
}
