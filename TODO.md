## TODO:
- [PRIORITY]: Organize this damned code base, it's a mess.
- [PRIORITY]: Set up pipeline
- [PRIORITY]: ~~Add temporal buffer for chunk rendering~~
- [PRIORITY]: ~~Allow arbitrary number of chunks in header~~
- [IMPORTANT]: Do batch rendering for chunks
- [IMPORTANT]: Do backface culling
- [IMPORTANT]: Fix windows bug where on some machines games don't work
- [IMPORTANT]: Actually start using multiple threads
- [IMPORTANT]: Make a GUI to make stuff easier
- [IMPORTANT]: stop requiring OpenGL for renderer and just use vadgl
- [IMPORTANT]: On windows there's problems handling input, likely related to
    how grabbing the mouse and focus works differently on windows, FIX pls
- Add `vadg` it as a external repo **[in_progress]**
- Add proper logging
- Create a visualization utility for Quad trees to help myself
- ~~Make a way to render chunks~~
- **[VADGL]** Add abstractions for working with textures with `vadgl`
- **[VADGL]** Add paranoid mode
- [LOW IMPORTANCE] Maybe use sdl2 wrapper in the future

## NOTES:
- For now re-meshing even when on small changes feels like to much work. I wanna
    make it so instead there's a way to remove and add faces into the chunk_mesh
    directly. This should be much faster. Additionally it would be great if the
    `source/world.d` can also store many `VoxelWorld`s. It be great if I can
    also store a `BinaryVoxelWorld` were visible (non-trasnparent) voxels are 1
    and everything else is 0. It would likely speed-up pretty much anything
    allowing me to easily iterate past non-visible voxels.
- Figuring out LOD would also be cool, for this I guess I will need to store
    multiple `ChunkHeaders` perhaps multiple `ChunkBufferHeader`. One for each
    LOD level I want. Perhaps I would also need some sort of time-stamp to know
    what is most up-to-date, since some of this buffers may be more up-to-date
    than others
- Read about brokering servers (the better peer-to-peer)

## Old TODO
- Creating fucking client
- ~~Write basic code for the world~~
- Make the fucking the database (May use something else)
- ~~Write the fucking OpenGL rasterizer renderer~~
- Create fucking server **[not_important]**
- Be happy
- Improve fucking shaders so that stuff doesn't look like shit

### Extra
- Make particle engine if there's time
- Write fucking physics
- Remember that there's `__vector`
