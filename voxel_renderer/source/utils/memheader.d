/+
    TODO: Make a `MemSliceHeader` that will be a slice of the MemHeader
+/
module utils.memheader;

import std.typecons     : Tuple;
import std.meta         : allSatisfy, ApplyRight;

alias MemRange = Tuple!(int, "start", int, "end");

@safe @nogc nothrow
private static int size(MemRange range) pure => range.end - range.start;

private enum isSameType(T1, T2) = is(T1 == T2);

/++
    Contains information about a memory buffer. Meant to be used along side an
    allocated block of memory.
    Example:
    ---
    int[] buff0 = new int[](32);
    MemHeader buff0_header = MemHeader(32);

    // Get index to space with 8 elements
    int ptr_i = buff0_header.allocate(8);

    // do whatever you want with that memory
    buff0[ptr_i..ptr_i+8] = 11;
    writeln(buff0[ptr_i..ptr_i+8);

    // Free the memory after you stoped using it
    buff0_header.free(ptr_i);
    ---
 +/
struct MemHeader
{
    struct Range
    {
        int index = 0;
        MemHeader* mem_header;

        MemRange front() => mem_header.mem_blocks[index]; 
        void popFront() { index++; }
        bool empty() => index >= mem_header.mem_blocks.length;
    }

    //  TODO: Make a public getter and make the field itself private
    /// Amount of memory used
    int used = 0;
    /// Total capacity of the buffer
    int capacity = 0;
    /+
        Storage for allocated ranges of memory, ordered in ascending order by `start`.

        If this is empty that means the buffer is empty
    +/
    /*
       TODO: If I want this shit to be `@nogc` I need to use `std.container.array`
       or use my own implementation
   */
    private MemRange[] mem_blocks;

    this(int cap, int mem_block_init_cap = 32)
    {
        this.capacity = cap;
        // Reserve space for mem_blocks. If we now the maximum size it will
        // take we can save up on allocations
        this.mem_blocks.reserve(mem_block_init_cap);
    }

    @property @safe @nogc nothrow
    int unused() const pure => this.capacity - this.used;

    int allocate(int size)
    in (this.unused >= size, "Not enough space")
    {
        import std.array    : insertInPlace;
        int mem_block_i = this.find_free_mem(size);

        if (mem_block_i == -1)
            return -1;

        // new block starts at end of previous block
        int start = (mem_block_i) ? this.mem_blocks[mem_block_i-1].end : 0;
        // Add new `MemRange` to allocate spaces
        this.mem_blocks.insertInPlace(mem_block_i, [MemRange(start, start+size)]);
        // Update `used` 
        this.used += size;
        // Return start of `MemRange`
        return start;
    }

    // TODO: Make @nogc
    // Allocate at the end of the buffer
    int quick_allocate(int size)
    /* in (this.unused >= size, "Not enough space") */
    {
        import std.stdio;

        int start = (this.mem_blocks.length) ? this.mem_blocks[$-1].end : 0;
        if (this.capacity - start >= size) {
            // Update `used` 
            this.used += size;
            this.mem_blocks ~= MemRange(start, start+size);
            return start;
        }
        return -1; // not enough space
    }

    /++
        Does the same as `allocate(int size)` but returns a slice to `buff`
     +/
    T[] allocate(T)(T[] buff, int size) in (buff.length >= this.capacity)
    {
        int start = this.allocate(size);
        return buff[start..start+size];
    }

    // TODO: Implement resizing up, and call it realloc
    // I only want to resize down for now
    void resize(int start, int new_size)
    {
        import std.algorithm            : countUntil;
        long index = this.mem_blocks.countUntil!(block => block.start == start);
        assert(index != -1);
        MemRange* block = &this.mem_blocks[index];
        assert(new_size <= (*block).size());

        int diff = (*block).size() - new_size;
        // #### Update block end and used memory.
        // #### This is literally the only thing this function does
        block.end = block.start + new_size;
        this.used -= diff;
    }

    void clear()
    {
        this.mem_blocks.length = 0;
        this.used = 0;
    }

    /// Free block of memory starting from `start`
    void free(int start)
    {
        import std.algorithm            : countUntil, remove;
        // linear search
        // assert that a memory block starting from `start` exists
        long index = this.mem_blocks.countUntil!(block => block.start == start);
        assert(index != -1);

        MemRange block = this.mem_blocks[index]; // get block to free
        this.mem_blocks.remove(index);
        this.mem_blocks.length--; // std.algorithm.remove doesn't update length

        this.used -= block.size();
    }

    bool is_full() const pure => (this.used < this.capacity);

    // TODO: Store free spaces in a list. It will make shit faster and
    // the memory cost is negliable
    /++
        Return index where new memblock of size `size` should be inserted to or
        -1 if there's no spot big enough to fit memblock.
     +/
    int find_free_mem(int size) const
    {
        immutable(int) block_count = cast(int)this.mem_blocks.length;

        /// Optimization: Put checks elsewhere, so that they are run only
        // when absolutely necessary
        if (size > this.capacity)
            return -1;

        // No memory blocks so the whole buffer is free real state
        if (block_count == 0)
            return 0;

        // Check if there's space at the start of buffer
        if (this.mem_blocks[0].start >= size)
            return 0;

        // Check if there's space at the end of buffer
        if (this.capacity - this.mem_blocks[$-1].end >= size)
            return block_count;

        // Search free space between blocks
        for (int i = 1; i < block_count; i++) {
            // Check if there's enough space between mem_blocks
            MemRange mem_block = this.mem_blocks[i-1];

            int free_start = mem_block.end;
            int free_end = mem_blocks[i].start;

            int free_space = free_end - free_start;

            if (free_space >= size)
                return i;
        }
        return -1;
    }

    // Iterate through every allocated block of memory
    int opApply(int delegate(ref MemRange) operation)
    {
        int result = 0;
        foreach (ref MemRange memblock; mem_blocks) {
            result = operation(memblock);
            if (result)
                return result;
        }
        return result;
    }

    // TODO: Use opSlice, makes more sence
    Range opSlice() => Range(0, &this);
}
