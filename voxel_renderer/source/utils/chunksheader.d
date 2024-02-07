module utils.chunksheader;

// Likely faster to copy than reference
bool pos_equals(int[3] v0, int[3] v1)
{
    bool condition = true;

    static foreach (i; 0..3) {
        condition &= v0[i] == v1[i];
    }

    return condition;
}

// Could call it ChunkHeader
struct ChunkInfo
{
    int[3] coords;
    int index;
    int size;
    bool modified;
}

struct ChunkRef
{
    private {
        ChunksHeader* header;
        int header_id;
    }

    @property
    ref inout(int[3]) coords() return inout => header.coords[header_id];

    @property
    ref inout(int) index() return inout => header.indices[header_id];

    @property
    ref inout(int) size() return inout => header.sizes[header_id];

    @property
    ref inout(bool) modified() return inout => header.modified[header_id];

    ChunkInfo info() => ChunkInfo(this.coords, this.index, this.size, this.modified);
}

int end(T)(T chunk_info) if (is(T == ChunkInfo) || is(T == ChunkRef))
    => chunk_info.index + chunk_info.size;

struct ChunksHeader
{
    enum int NULL_ID = -1;

    int count = 0;
    int cap = 0;

    int[3][] coords;
    int[] indices;
    int[] sizes;
    bool[] modified;

    bool is_full() const pure => this.count >= this.cap;

    @disable this(); // NO DEFAULT CONSTRUCTOR ALLOWED

    this(int size)
    {
        this.cap = size;

        this.coords = new int[3][](size);
        this.indices = new int[](size);
        this.sizes = new int[](size);
        this.modified = new bool[](size);
    }

    int append(ChunkInfo info)
    {
        if (this.count >= cap)
            return -1;

        this.coords[this.count] = info.coords;
        this.indices[this.count] = info.index;
        this.sizes[this.count] = info.size;
        this.modified[this.count] = info.modified;

        return this.count++;
    }

    int find(int[3] pos)
    {
        import std.algorithm    : countUntil;

        return cast(int)this.coords.countUntil(pos);
    }

    void remove(int index) in (index >=0 && index < this.count)
    {
        import std.meta         : AliasSeq;
        import std.algorithm    : remove;

        static foreach (member; AliasSeq!(coords, indices, sizes, modified))
            member.remove(index);

        this.count--;
    }

    ChunkRef opIndex(int index) => ChunkRef(&this, index);

    int opApply(int delegate(ChunkRef) ops)
    {
        int result = 0;
        for (int i = 0; i < this.count; i++) {
            result = ops(this[i]);
            if (result)
                return result;
        }
        return result;
    }
}

// test shit
unittest
{
    // TODO: Include negative asserts
    // Do more tests, this just kinda tests basic functionality, better than
    // Nothing but not good enough
    import std.stdio;

    ChunkInfo[] infos = [
        ChunkInfo([0, 0, 0], 0, 10), ChunkInfo([1, 0, 0], 10, 4),
        ChunkInfo([2, 0, 0], 14, 6), ChunkInfo([3, 0, 0], 20, 5),
        ChunkInfo([4, 0, 0], 25, 5), ChunkInfo([5, 0, 0], 30, 10),
    ];
    ChunksHeader header = ChunksHeader(16);
    foreach (info; infos)
        header.append(info);

    foreach (info; infos)
        assert(header[header.find(info.coords)].index == info.index);

    foreach (info; infos)
        header.remove(header.find(info.coords));

    assert(header.count == 0);
}
