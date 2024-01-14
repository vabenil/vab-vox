import voxel_grid.voxel;
import voxel_grid.chunk;

import common   : IVec3 = ivec3;


// Maybe use class here
struct World(ChunkT)
{
    alias VoxelT = ChunkT.VoxelType;

    ChunkT[IVec3] chunk_map;

    void set_voxel(IVec3 pos, VoxelT voxel)
    {
        IVec3 chunk_pos = pos / ChunkT.size;
        IVec3 rel_pos = pos % ChunkT.size;

        if (ChunkT* chunk = chunk_pos in this.chunk_map) {
            (*chunk)[rel_pos.array] = voxel;
        }
        else {
            chunk_map[chunk_pos] = ChunkT();
            chunk_map[chunk_pos][rel_pos.array] = voxel;
        }
    }

    VoxelT get_voxel(IVec3 pos) const
    {
        IVec3 chunk_pos = pos / ChunkT.size;
        IVec3 rel_pos = pos % ChunkT.size;

        if (const(ChunkT*) chunk = chunk_pos in this.chunk_map) {
            return (*chunk)[rel_pos.array];
        }
        return VoxelT();
    }

    void load_from_vox_file(string vox_path)
    {
        import voxd;
        import common.color;
        import std.stdio;
        import std.range    : iota;
        import std.parallelism;

        // alternatively: decodeVOXFromMemory(ubyte[] data)
        VOX model = decodeVOXFromFile(vox_path);

        writefln("width = %s", model.width);
        writefln("height = %s", model.height);
        writefln("depth = %s", model.depth);
        writefln("That makes %s voxels total", model.numVoxels());

        for (int k = 0; k < model.depth; k++)
        for (int j = 0; j < model.height; j++)
        for (int i = 0; i < model.width; i++) {
        /* foreach (i; parallel(model.width.iota)) { */
            auto m_vox = model.voxel(i, j, k); // magica voxel
            immutable Color4b color_ = Color4b(m_vox.r, m_vox.g, m_vox.b, m_vox.a);
            /* Color4b color = Color4b(m_vox.a, m_vox.b, m_vox.r, m_vox.g); */
            if (color_ != Color4b.EMPTY) {
                this[IVec3(i, k, j)] = VoxelT(color_.to_hex());
            }
        }
        writeln("Model loaded!");
    }

    int opApply(int delegate(IVec3 cpos, ref ChunkT chunk) ops)
    {
        int result = 0;
        foreach (IVec3 cpos, ref ChunkT chunk; this.chunk_map) {
            result = ops(cpos, chunk);
            if (result)
                break;
        }
        return result;
    }

    VoxelT opIndex(IVec3 pos) const => get_voxel(pos);

    void opIndexAssign(VoxelT voxel, IVec3 pos) => this.set_voxel(pos, voxel);
}
