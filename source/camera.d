module camera;

import inmath;
import inmath.math;

/* enum vec3 UP = vec3(0, 1.0f, 0.0f).normalized; */
enum vec3 UP = vec3(0, 1.0f, 0.0f);

@safe @nogc nothrow:

static float to_rad(float degrees) pure => degrees * (PI / 180.0);

static float to_deg(float radians) pure => radians * (180.0f / PI);

mat4 glm_perspective_rh_no(float fovy, float aspect, float nearZ, float farZ) pure
{
  float f, fn;

  mat4 dest = mat4(0.0f);

  f  = 1.0f / tan(fovy * 0.5f);
  fn = 1.0f / (nearZ - farZ);

  dest[0][0] = f / aspect;
  dest[1][1] = f;
  dest[2][2] = (nearZ + farZ) * fn;
  dest[2][3] =-1.0f;
  dest[3][2] = 2.0f * nearZ * farZ * fn;

  return dest;
}


static vec3 direction_from_euler_angles(float pitch, float yaw) pure
{
    vec3 dir;
    float yaw_rad = to_rad(yaw),
          pitch_rad = to_rad(pitch);

    float cos_pitch = cos(pitch_rad);

    dir.x = cos(yaw_rad) * cos_pitch;
    dir.y = sin(pitch_rad);
    dir.z = sin(yaw_rad) * cos_pitch;
    return dir;
}

struct Camera
{
    int width;
    int height;

    vec3 pos;

    mat4 model;
    mat4 view;
    mat4 proj;

    mat4 proj_view;

    float pitch = 0;
    float yaw = 0;
    float roll = 0;
    float fov = 0;

    float sensitivity = 0.15f;

    @safe @nogc nothrow:
    /* vec3 direction() pure const => vec3( */
    /*     quat.eulerRotation(roll.to_rad(), pitch.to_rad(), yaw.to_rad()).quaternion.xyz */
    /* ); */
    vec3 direction() pure const => direction_from_euler_angles(this.pitch, this.yaw);

    vec3 izpos() pure const => this.pos * vec3(1, 1, -1);

    this(vec3 pos, float fov, int width, int height, float near=0.1f, float far=256.0f)
    {
        const float vox_size = 8;
        this.model = mat4(
            1.0f, 0.0f, 0.0f, 0.0f,
            0.0f, 1.0f, 0.0f, 0.0f,
            0.0f, 0.0f, -1.0f, 0.0f,
            0.0f, 0.0f, 0.0f, 1.0f
        ) * vox_size;
        this.pos = pos;
        this.fov = fov;
        this.set_dimensions(width, height, near, far);
    }

    void set_direction(vec3 forward)
    {
        import std.stdio;
        // I honestly don't know if this uses degrees or radians
        /* quat d = quat.lookRotation(forward, UP); */

        this.pitch = asin(forward.y).to_deg();
        this.yaw = -atan2(forward.z, forward.x).to_deg();
    }

    void look_at() { this.look_at(this.izpos + this.direction()); }

    void look_at(vec3 front)
    {
        this.view = mat4.lookAt(this.izpos, front, UP);
    }

    // Create projection matrix
    void set_dimensions(int w, int h, float near=0.1f, float far=256.0f)
    {
        this.width = w;
        this.height = h;
        this.proj = mat4.perspective(width, height, fov, near, far);
        /* this.proj = glm_perspective_rh_no(fov.to_rad(), cast(float)width/cast(float)height, near, far); */
    }

    mat4 mpv() pure const => proj * view * model;
    /* mat4 mpv() pure const => proj * model * view; */
    /* mat4 mpv() pure const => view * model * proj; */
    /* mat4 mpv() pure const => model * proj * view; */
    /* mat4 mpv() pure const => proj * (view * model); */
    /* mat4 mpv() pure const => (proj * view) * model; */
}
