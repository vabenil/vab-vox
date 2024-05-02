#version 330 core

#define EPSILON 1e-5

precision mediump float;

in vec3 v_pos;
in vec4 v_color;
in vec3 surf_norm;

out vec4 color;

uniform vec3 u_camera_pos;

vec3 light = vec3(16.f, 64.f, 0.f);

void main()
{
    vec3 point, light_dir;
    float diff;
    point = surf_norm * EPSILON + v_pos.xyz;
    light_dir = normalize(light - point);
    diff = max(dot(surf_norm, light_dir), 0.20);

    color = vec4(diff * v_color.xyz, v_color.a);
    /* color = 1 * v_color; */
}
