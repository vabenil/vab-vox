module utils.chunksheader;

import std.meta : AliasSeq, staticMap;

template mirrorMembers(T1, T2)
{
    template mirrorMember(alias member)
    {
        alias mirrorMember = mixin("T1."~member.stringof);
    }

    alias mirrorMembers = staticMap!(mirrorMember, T2.tupleof);
}

// Likely faster to copy than reference
@safe @nogc nothrow
bool pos_equals(int[3] v0, int[3] v1) pure
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
    bool queued;

    bool is_adjacent(ChunkInfo info)
    {
        return (
            this.index == (info.index + info.size) || // adjacent to the right
            (this.index + this.size) == info.index // Adja cent to the left
        );
    }
}

struct ChunkRef
{
    private {
        ChunksHeader* header = null;
        int header_id = -1;
    }

    @disable this();

    @safe @nogc nothrow
    this(ChunksHeader* header, int header_id)
    {
        this.header = header;
        this.header_id = header_id;
    }

    void opAssign(ChunkInfo info)
    {
        static foreach (i, member; mirrorMembers!(ChunkRef, ChunkInfo)) {
            member = info.tupleof[i];
        }
    }

    @property
    ref inout(int[3]) coords() return inout => header.coords[header_id];

    @property
    ref inout(int) index() return inout => header.indices[header_id];

    @property
    ref inout(int) size() return inout => header.sizes[header_id];

    @property
    ref inout(bool) modified() return inout => header.modified[header_id];

    @property
    ref inout(bool) queued() return inout => header.queued[header_id];

    ChunkInfo info() => ChunkInfo(this.coords, this.index, this.size, this.modified, this.queued);
}

int end(T)(T chunk_info) if (is(T == ChunkInfo) || is(T == ChunkRef))
    => chunk_info.index + chunk_info.size;

struct ChunksHeader
{
    //------ ALL HERE IS @safe nothrow

    enum int NULL_ID = -1;

    int count = 0;
    int cap = 0;

    int[3][] coords;
    int[] indices;
    int[] sizes;
    bool[] modified;
    bool[] queued; // queued for rendering

    @property @safe @nogc nothrow
    int length() const pure => this.count;

    @safe nothrow
    bool is_full() const pure => this.count >= this.cap;

    @safe nothrow
    int unused() const pure => this.cap - this.count;

    @disable this(); // NO DEFAULT CONSTRUCTOR ALLOWED

    this(int size)
    {
        this.cap = size;

        this.coords = new int[3][](size);
        this.indices = new int[](size);
        this.sizes = new int[](size);
        this.modified = new bool[](size);
        this.queued = new bool[](size);
    }

    // Shit is not sorted
    @safe nothrow
    int append(ChunkInfo info)
    {
        if (this.count >= cap)
            return -1;

        this.coords[this.count] = info.coords;
        this.indices[this.count] = info.index;
        this.sizes[this.count] = info.size;
        this.modified[this.count] = info.modified;
        this.queued[this.count] = info.queued;

        return this.count++;
    }

    @safe nothrow
    int find(int[3] pos)
    {
        import std.algorithm    : countUntil;

        return cast(int)this.coords[0..count].countUntil(pos);
    }

    @safe nothrow
    void remove(int index) in (index >=0 && index < this.count)
    {
        import std.algorithm    : remove;

        static foreach (member; AliasSeq!(coords, indices, sizes, modified))
            member.remove(index);

        this.count--;
    }

    @safe @nogc nothrow
    void clear() pure { this.count = 0; }

    // NOTE: This probably needs to be `scope` for me to be able to store
    // the result of this function a variable
    @safe nothrow
    ChunkRef opIndex(int index) return => ChunkRef(&this, index);

    int opApply(T)(T ops) if (is(T : int delegate(ref ChunkRef)))
    {
        int result = 0;
        for (int i = 0; i < this.count; i++) {
            ChunkRef chunk_ref = this[i]; // So that I can get a reference
            result = ops(chunk_ref);
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
