### Plan:
- Ok so plan is simple. For the time being render 1 chunk at a time.
this allows for a lot of compressions and allows me to reduce the amount data
sent to the gpu.
In this pass don't include any lighting. Just the color and *whether or not this
block is emitting any light*(this might not be necessary).\
**TODO:**
Using indirect rendering calls stuff can be optimized by a lot. So for OpenGL
versions higher than 4 use indirect rendering calls, for lower just render 1
chunk at a time.

- Then in the next pass use the screen space data together with a bit
representation of the voxels. For now this bit representation will include all
voxels in the world.
