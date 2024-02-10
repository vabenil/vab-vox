## TODO:
- [PRIORITY]: Add temporal buffer for chunk rendering
- [PRIORITY]: ~~Allow arbitrary number of chunks in header~~
- [IMPORTANT]: Fix windows bug where on some machines games don't work
- [IMPORTANT]: Actually start using multiple threads
- [IMPORTANT]: stop requiring OpenGL for renderer and just use vadgl
- [IMPORTANT]: On windows there's problems handling input, likely related to
    how grabbing the mouse and focus works differently on windows, FIX pls
- Add `vadg` it as a external repo **[in_progress]**
- Create a visualization utility for Quad trees to help myself
- Make a way to render chunks
- **[VADGL]** Add abstractions for working with textures with `vadgl`
- **[VADGL]** Add paranoid mode
- [LOW IMPORTANT] Maybe use sdl2 wrapper in the future

## Old TODO
- Creating fucking client
- Write basic code for the world
- Make the fucking the database
- Write the fucking OpenGL rasterizer renderer.
- Create fucking server **[not_important]**

- Be happy

- Improve fucking shaders so that stuff doesn't look like shit

### Extra
- Make particle engine if there's time
- Write fucking physics
- Remember that there's `__vector`

```
Vox
    dub.json
    source
    |   ...
    vadgl
    |   source
    |   |   ...
    |   dub.json
    voxel_grid
    |   source
    |   |   ...
    |   dub.json
    voxel_renderer
    |   source
    |   |   ...
    |   dub.json
