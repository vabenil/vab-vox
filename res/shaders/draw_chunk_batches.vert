#version 460 core

layout(location=0) in ivec2 model_pos;
layout(location=1) in ivec3 pos;
layout(location=2) in vec4 color;
layout(location=3) in uint packed_size;

// The amount of voxels a chunk has in every dimension
uniform int u_chunk_size;

// TODO: Probably add LOD later here
uniform ivec3 u_chunk_count;
uniform int u_face_count;
uniform int u_middle_chunk;
layout(std140, binding = 1) uniform ChunkCoords
{
    ivec4 u_chunk_coords[256];
    int indices[256];
    int sizes[256];
};

/*
   Ok so u_chunk_coords is an ordered array, and in all honesty I don't
   expect it to be that big. For the time being since I know the amount
   of chunks being rendered, the index of the current instance via
   `gl_InstanceID` and lowest & highest I can do a binary search for

   log(n) searching performance.

   |       |       |
   |   |   |       | 
   | | |   |       |
 */

uniform mat4 u_trans_mat;

out vec4 v_color;
out vec3 v_pos;

uvec3[3] identity = uvec3[3](
    uvec3(1u, 0u, 0u),
    uvec3(0u, 1u, 0u),
    uvec3(0u, 0u, 1u)
);


ivec3 unpack_pos(uint packed_pos)
{
    return ivec3(
            packed_pos & 0x3ffu,
            (packed_pos << 10) & 0x3ffu,
            (packed_pos << 20) & 0x3ffu);
}

vec3 get_world_pos()
{
    uint face_id, dim, sbit;
    // get dimension and sign bit from packed data
    face_id = uint(packed_size & 0x7u);
    dim = face_id % 3u;
    sbit = uint(face_id > 2u);

    ivec3 u_chunk_pos = u_chunk_coords[gl_DrawID].xyz;

    vec3 delta = vec3(uvec3(identity[dim]) & sbit);
    /* vec3 face_pos = vec3( pos) + delta; */
    vec3 face_pos = vec3(u_chunk_pos * u_chunk_size + pos) + delta;

    // Model position to 3d
    vec3 m_pos = vec3(0);
    m_pos[(dim + 1u) % 3u] = float(model_pos[0]);
    m_pos[(dim + 2u) % 3u] = float(model_pos[1]);

    return face_pos + m_pos;
}

void main()
{
    /* vec3 world_pos = vec3(model_pos, 0.0f) + pos; */
    vec3 w_pos = get_world_pos();

    v_color = color;
    v_pos = w_pos;
    /* gl_Position =  vec4(w_pos, 1) * u_trans_mat; */
    gl_Position =  u_trans_mat * vec4(w_pos, 1);
}
