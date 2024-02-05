/+
    TODO:
        - Unittest this shit
        - Make this work with more than 255 elements
+/
module utils.chunk_header;

private import utils.capedarray;

struct ChunkInfo
{
    int[3] pos;
    int index;
    int size;

    int end() const pure => this.index + this.size;
}

// Likely faster to copy than reference
bool pos_equals(int[3] v0, int[3] v1)
{
    static foreach (i; 0..3) {
        if (v0[i] != v1[i])
            return false;
    }
    return true;
}

struct Header
{
    enum ubyte NULL_ID = 255;

    // ~~I don't expect more than 128 chunks~~ I should keep track of even more chunks honestly
    // store information of all chunks
    ubyte count = 0;
    // Chunk coordinates
    int[3][255] coords = void;
    // Units in voxel faces
    int[255] indices = 0;
    int[255] sizes = 0;

    // Free positions in header (chunks that can be overriden)
    CapedArray!(ubyte, 255) free_headers; // use as a list

    // Implement this later
    // Sort by proximity to camera
    /* void sort(ivec3 cam_pos) */
    /* { */
    /*     // ordered array containing indices to header */
    /*     CapedArray!(byte, 128) order_array; */
    /*     // for this gotta assume whole thing is unsorted */
    /* } */

    int find(int[3] pos)
    {
        for (int i = 0; i < this.count; i++) {
            // Linear but it's fine since we don't expect many chunks freed
            if (this.free_headers.find(cast(ubyte)i) != -1)
                continue; // if this value is freed it doesn't count

            if (pos_equals(this.coords[i], pos))
                return i; // found
        }
        return NULL_ID;
    }

    void swap(int chunk0_i, int chunk1_i)
    {
        ChunkInfo tmp = this[chunk0_i];

        this[chunk0_i] = this[chunk1_i];
        this[chunk1_i] = tmp;
    }

    bool full() const pure => (count == ubyte.max-1) && (free_headers.length == 0);

    // Returns index to empty space and remove empty space
    ubyte take_empty() in (!this.full())
    {
        if (free_headers.length) {
            // pop!
            ubyte index = free_headers[$-1];
            free_headers._length--;
            return index;
        }
        // push
        return cast(ubyte)(count++);
    }

    // Can fail
    int append(ChunkInfo info) in(!this.full())
    {
        int index = this.take_empty();
        this[index] = info;
        return index;
    }

    void remove(int index) in(index > 0 && index < this.count)
    {
        if (index+1 == this.count) { // Removing last
            this.count--;
            return ;
        }

        // Add to free spaces, we are assuming index wasn't already removed
        this.free_headers.append(cast(ubyte)index);
    }
    // Convinience function
    ChunkInfo opIndex(int i) const pure => ChunkInfo(coords[i], indices[i], sizes[i]);

    ChunkInfo opIndexAssign(ChunkInfo value, int i)
    {
        this.coords[i] = value.pos;
        this.indices[i] = value.index;
        this.sizes[i] = value.size;

        return value;
    }

    int opDollar(ulong _) const pure => this.count;
}
