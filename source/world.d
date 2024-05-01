module world;

import voxel_grid.voxel;
import voxel_grid.chunk;
import voxel_grid.world     : VoxelWorld;

import common               : IVec3 = ivec3, Vec3 = vec3, vec;
import std.typecons        : Optional = Nullable, optional = nullable;

// Maybe use class here
class World(ChunkT) : VoxelWorld!ChunkT
{
    alias VoxelT = ChunkT.VoxelType;

    ChunkT[int[3]] chunk_map;

    VoxelT set_voxel(int[3] pos, VoxelT voxel)
    {
        IVec3 chunk_pos = IVec3((Vec3(pos.vec()) / cast(float)ChunkT.size).floor);
        /* IVec3 rel_pos = pos.vec() % ChunkT.size; */
        IVec3 rel_pos = ((pos.vec() % ChunkT.size) + ChunkT.size) % ChunkT.size;
        if (ChunkT* chunk = chunk_pos.array in this.chunk_map) {
            (*chunk)[rel_pos.array] = voxel;
        }
        else if (!voxel.is_empty()) {
            chunk_map[chunk_pos.array] = ChunkT();
            chunk_map[chunk_pos.array][rel_pos.array] = voxel;
        }
        return voxel;
    }

    Optional!VoxelT get_voxel(int[3] pos) const
    {
        IVec3 chunk_pos = pos.vec() / ChunkT.size;
        /* IVec3 rel_pos = pos.vec() % ChunkT.size; */
        IVec3 rel_pos = ((pos.vec() % ChunkT.size) + ChunkT.size) % ChunkT.size;

        if (const(ChunkT*) chunk = chunk_pos.array in this.chunk_map) {
            return (*chunk)[rel_pos.array].optional;
        }
        return VoxelT().optional;
    }

    void load_from_vox_file(string vox_path, IVec3 origin = IVec3(0, 0, 0))
    {
        import voxd;
        import common.color;
        import std.range    : iota;
        import std.parallelism;

        import std.stdio;
        import std.datetime.stopwatch;

        StopWatch watch = StopWatch(AutoStart.yes);
        // alternatively: decodeVOXFromMemory(ubyte[] data)
        VOX model = decodeVOXFromFile(vox_path);

        debug {
            writefln(`### Loading model from vox file "%s"...`, vox_path);
            writefln("width = %s", model.width);
            writefln("height = %s", model.height);
            writefln("depth = %s", model.depth);
            writefln("That makes %s voxels total", model.numVoxels());
        }

        for (int k = 0; k < model.depth; k++)
        for (int j = 0; j < model.height; j++)
        for (int i = 0; i < model.width; i++) {
        /* foreach (i; parallel(model.width.iota)) { */
            auto m_vox = model.voxel(i, j, k); // magica voxel
            immutable Color4b color_ = Color4b(m_vox.r, m_vox.g, m_vox.b, m_vox.a);

            IVec3 vox_pos = IVec3(i, k, j) + origin;
            /* Color4b color = Color4b(m_vox.a, m_vox.b, m_vox.r, m_vox.g); */
            if (color_ != Color4b.EMPTY) {
                this[vox_pos.array] = VoxelT(color_.to_hex());
            }
        }

        watch.stop();
        writefln("model loaded in %s milliseconds", watch.peek.total!"msecs");
        debug writeln("### Model loaded!");
    }

    int opApply(int delegate(int[3] cpos, ref ChunkT chunk) ops)
    {
        int result = 0;
        foreach (int[3] cpos, ref ChunkT chunk; this.chunk_map) {
            result = ops(cpos, chunk);
            if (result)
                break;
        }
        return result;
    }

    // TODO: Maybe return Optional, maybe not 
    VoxelT opIndex(int[3] pos) const => get_voxel(pos).get;
    VoxelT opIndex(int x, int y, int z) const => get_voxel([x, y, z]).get;

    VoxelT opIndexAssign(VoxelT voxel, int[3] pos) => this.set_voxel(pos, voxel);
    VoxelT opIndexAssign(VoxelT voxel, int x, int y, int z) => this.set_voxel([x, y, z], voxel);
}
