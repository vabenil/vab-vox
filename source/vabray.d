module vabray;

import std.math         : modf;

import std.math;
import std.math         : sign = sgn;
import std.algorithm    : minIndex;

import std.typecons     : Tuple, tuple;

import common.types;
/* import inmath; */

/* float step(T1, T2)(T1 edge, T2 x) => x < edge ? 0.0f : 1.0f; */

vec3 fractional(vec3 v)
{
    real _;
    vec3 result;
    static foreach (i; 0..3) {
        result.array[i] = cast(float)modf(cast(real)v.array[i], _);
    }
    return result;
}

struct Ray
{
    vec3 o;
    vec3 d;

    RayRange raymarch() => RayRange(this);
}

// For now this shit is a forward range and an inifite range
// I suppose I could make it an indexed (?) range, maybe
struct RayRange
{
    Ray ray;

    int i = 0;
    float dist = 0;

    vec3 T;
    vec3 step;
    vec3 tdelta;

    ivec3 block;
    ivec3 face = ivec3(0, 0, 0);

    @property @safe @nogc nothrow pure {
        float distance() => this.dist;
    }

    this(Ray ray)
    {
        // fractional part of origin
        vec3 fract_o = ray.o.fractional();

        this.ray = ray;
        this.step = ray.d.convert!sign();
        this.block = ivec3(ray.o);
        /* this.T = (step(vec3(0, 0, 0), ray.d) - fract_o) / ray.d; */
        this.T = (vec3(0.0f, 0.0f, 0.0f).step(ray.d) - fract_o) / ray.d;

        static foreach (i; 0..3) // for each dimension
            this.tdelta[i] = (ray.d[i] == 0) ? 0 : this.step[i] / ray.d[i];

        this.i = cast(int)this.T.array[].minIndex;
        this.face[this.i] = cast(int)-step[this.i];
    }

    Tuple!(float, ivec3, ivec3) front() => tuple(this.distance(), this.block, this.face);

    void popFront() {
        this.dist = T[i];

        this.block[i] += cast(int)this.step[i];
        this.T[i] += this.tdelta[i];

        this.face = ivec3(0, 0, 0);
        this.face[i] = cast(int)-step[i];
        this.i = cast(int)this.T.array[].minIndex;
    }

    enum bool empty = false; // Infinite range
}


// Ok how the fuck do I test this shit?
unittest
{
    import std.stdio;

    ivec3 origin = ivec3(0, 0, 0);
    ivec3 target = ivec3(3, 1, 1);

    float dist_to_target = (target - origin).length;

    writeln("target: ", target, "; distance: ", dist_to_target);

    vec3 direction = vec3(target - origin) / dist_to_target;

    Ray r = Ray(vec3(origin), direction);

    ivec3 destination;
    foreach (float dist, ivec3 pos, ivec3 face; r.raymarch()) {
        writeln("block: ", pos, "; dist: ", dist);
        destination = pos;

        if (dist > dist_to_target)
            break;
    }

    writeln("reached: ", destination);
    assert(destination == target);
}
