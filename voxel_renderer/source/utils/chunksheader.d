module utils.chunksheader;

import std.algorithm    : among;


enum MeshState : int
{
    /++ There's no mesh in device ++/
    NONE        = 0,
    /++ Mesh is on device ++/
    ON_DEVICE   = 1,
    /++ Mesh is up to date in device ++/
    SYNCHED     = 3
}

alias ivec3 = int[3];

bool equals(ivec3 a, ivec3 b)
    => a[0] == b[0] && a[1] == b[1] && a[2] == b[2];

/++
    Stores where a memory block starts and ends within a buffer and what state
    the memory block is (NONE means the memory block is not valid)
 +/
struct ChunkMemBlock
{
    int buff_id = -1;
    int start = -1;
    int end = -1;

    MeshState state = MeshState.NONE;

    /++
        Retruns true if `this` memory block is valid
     +/
    bool is_valid() // As long as no field is -1. The  block should be valid
        => !among(-1, this.buff_id, this.start, cast(int)this.state);
}

/++
    Contains information of where the chunk meshes are located in both the
    CPU and GPU. Does not contain any mesh data itself.

    NOTES:
        The chunk may store faces in multiple contigious buffer locations
 +/
struct ChunkHeader(int buffer_count)
{
    /++ The coordinates to the chunk ++/
    ivec3 coords;

    ChunkMemBlock[buffer_count] mem_blocks;

    // Optionally I can add an argument to track whether this chunk
    // Should be rendered later (Although I am not sure if that should be
    // stored in here
}

/++
    Store headers for chunks.

    IDEAS:
        A nice idea here is to sort chunk by dinstance to camera/player.
        closer chunks are closest to array start.

        This way linear search is faster at searching the most common chunks.

        Also it will allow me to do binary search on ChunksHeader. Which to
        be honest is probably all I need. A hashmap may be too much, binary
        search fills just right.
 +/
struct ChunksHeader(int buff_count)
{
    import std.container;
    import std.typecons     : Tuple, tuple;
    import std.algorithm    : map, countUntil, remove;

    alias MChunkHeader = ChunkHeader!buff_count;

    struct Range
    {
        int index = 0;
        Array!MChunkHeader* arr;

        MChunkHeader front() => (*arr)[index];
        bool empty() => index >= arr.length;
        MChunkHeader opIndex(int i) => (*arr)[i];
        void popFront() { index++; }
    }

    struct IndexedRange
    {
        int index = 0;
        Array!MChunkHeader* arr;

        Tuple!(int, MChunkHeader*) front() => tuple(index, &((*arr)[index]));

        bool empty() => index >= arr.length;
        MChunkHeader opIndex(int i) => (*arr)[i];
        void popFront() { index++; }
    }

    /++
        NOTE:
            No need to preserve indexing here. Chunks are accessed mostly by their postion
     +/
    Array!(MChunkHeader) headers;

    /++ It's probably best not to rely on indices ++/
    ref inout(MChunkHeader) opIndex(int i) return inout => headers[i];

    // Doesn't check if a chunk with the same cpos exist already
    // Also maybe is best to just add by cpos. Anything a header
    // is added it is most likely gonna empty any way
    int push(MChunkHeader chunk_header)
    {
        headers.insertBack(chunk_header);
        return cast(int)headers.length-1;
    }

    int find(ivec3 pos)
        => cast(int)headers[].countUntil!(h => h.coords.equals(pos));

    void remove(int index) { headers[].remove(index); }

    // implement is_full
    Range range() => Range(0, &headers);

    IndexedRange indexed_range() => IndexedRange(0, &headers);
}

unittest
{
    import std.algorithm    : canFind;
    import std.stdio;

    alias DBChunkHeader = ChunkHeader!2;
    alias DBChunksHeader = ChunksHeader!2;

    DBChunkHeader[] chunk_headers = [
        DBChunkHeader([0, 0, 0]),
        DBChunkHeader([1, 0, 0]),
        DBChunkHeader([0, 1, 0]),
        DBChunkHeader([0, 0, 1])
    ];

    DBChunksHeader chunks_header;

    foreach (chunk_header; chunk_headers)
        // TODO: Maybe test that returned index is what I expect
        chunks_header.push(chunk_header);

    // test that push & and find works
    foreach (chunk_header; chunk_headers)
        assert(chunks_header.find(chunk_header.coords) >= 0);

    chunks_header.remove(chunks_header.find(chunk_headers[0].coords));

    assert(chunks_header.find(chunk_headers[0].coords) == -1);
}
