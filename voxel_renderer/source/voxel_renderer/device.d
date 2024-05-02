module voxel_renderer.device;

import vadgl;
import common;

interface VoxelDevice
{
    // TODO: Perhaps pass viewport here
    void device_init();

    void set_mpv_matrix(const(float[4][4]) mat, bool normalized=false);
    void set_mpv_matrix(const(float[16]) mat, bool normalized=false);

    // TODO: perhaps pass camera as param to render
    void set_camera(vec3 pos, vec3 dir, vec3 up);

    /* // TODO: add face_index */
    /* void commit_face(ivec3 face, Color4b color, uint face_id, uint material); */

    /* // TODO: Take into consideration chunk */
    /* void commit_cube(ivec3 pos, Color4b color, uint material); */

    void send_to_device();

    /* void send_to_device(Vertex[] buff); */

    void render();
    /* void render(DrawChunkCommand[] commands); */
    /* void commit_chunk(vec3 pos, Color4b color, uint material); */
}
