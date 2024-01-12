module test.gl_device_test;

// NOTE: This test doesn't work with the newest device.
// Create a device for 2d rendering if needed or use Nuklear
/* unittest */
/* { */
/*     import common   : IVec3 = ivec3, Color4b; */
/*     import bindbc.opengl; */
/*     import bindbc.sdl; */
/*     import vadgl; */
/*     import inmath; */

/*     import test.window; */
/*     import test.sdl_ehandler; */

/*     import voxel_renderer.device; */
/*     import voxel_renderer.gl_device; */

/*     import std.stdio; */

/*     writeln("Starting gl_device test!"); */

/*     enum uint WIDTH = 600; */
/*     enum uint HEIGHT = 400; */

/*     Window win = Window("Voxel Renderer test", WIDTH, HEIGHT); */
/*     auto ortho_m = mat4.orthographic(0, WIDTH, 0, HEIGHT, -1, 100.0f); */

/*     GLint size; */
/*     glGetIntegerv(GL_MAX_TEXTURE_BUFFER_SIZE, &size); */
/*     writeln(size); */
/*     VoxelDevice device = new GLDevice(); */
/*     device.device_init(); */
/*     device.set_mpv_matrix(ortho_m.matrix); */

/*     device.commit_cube(IVec3(0, 0, 0), Color4b.WHITE, 0); */
/*     device.commit_cube(IVec3(1, 1, 0), Color4b.BLUE, 0); */
/*     device.commit_cube(IVec3(1, 0, 0), Color4b.GREEN, 0); */
/*     device.commit_cube(IVec3(0, 1, 0), Color4b.RED, 0); */


/*     bool quit = false; */
/*     SDL_EHandler event_handler; */
/*     event_handler.add_handler("quit", delegate(e) { quit = true; }); */
/*     while (!quit) { */
/*         event_handler.handle_sdl_events(cast(void*)null); */

/*         gl_clear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT).trust; */
/*         device.render(); */
/*         win.swap_buffer(); */
/*     } */
/* } */
