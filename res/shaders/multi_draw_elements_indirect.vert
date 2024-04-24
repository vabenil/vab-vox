#version 460 core

layout(location=0) in ivec2 model_pos;
layout(location=1) in ivec3 pos;
layout(location=2) in vec4 color;
layout(location=3) in uint packed_size;

uniform int u_chunk_size;

// So the idea I guess would be to send chunk info here,
// And from the chunk info and InstanceID I should be able to figure out
// NOTE: It would be much better to either use a uniform buffer, or just
// and average old buffer for this shit
// u_chunk_pos for rendering
// TODO: Probably add LOD later here

/* uniform ivec3 u_chunk_pos; */

uniform ivec3 u_chunk_count;

layout(std140, binding = 1) uniform ChunkCoords
{
    ivec4 u_chunk_coords[256];
};

uniform mat4 u_trans_mat;

out vec4 v_color;
out vec3 v_pos;
out vec3 surf_norm;

uint face_id;

uvec3[3] identity = uvec3[3](
    uvec3(1u, 0u, 0u),
    uvec3(0u, 1u, 0u),
    uvec3(0u, 0u, 1u)
);

vec4[6] colors = vec4[6](
    vec4(1, 1, 1, 1),
    vec4(1, 0, 0, 1),
    vec4(0, 1, 0, 1),
    vec4(0, 0, 1, 1),
    vec4(0.5, 0.4, 0.1, 1),
    vec4(0.0, 0.0, 0.0, 1)
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
    uint  dim, sbit;
    // get dimension and sign bit from packed data
    face_id = uint(packed_size & 0x7u);
    dim = face_id % 3u;
    sbit = uint(face_id > 2u);

    // MODIFY
    surf_norm = identity[dim] * (float(sbit) * 2 - 1);

    ivec3 u_chunk_pos = u_chunk_coords[int(gl_DrawID/2)].xyz;

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
    vec4 binary_color[2] = vec4[2](vec4(1.0, 0, 0, 1.0),  vec4(0, 0, 1, 1));
    /* vec3 world_pos = vec3(model_pos, 0.0f) + pos; */
    vec3 w_pos = get_world_pos();

    v_color = color;
    /* v_color = colors[face_id]; */
    /* v_color = binary_color[face_id / 3]; */
    v_pos = w_pos;
    /* gl_Position =  vec4(w_pos, 1) * u_trans_mat; */
    gl_Position =  u_trans_mat * vec4(w_pos, 1);
}
