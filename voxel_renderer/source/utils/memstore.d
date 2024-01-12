module utils.memstore;

import std.traits   : isNumeric;
import std.typecons : Tuple, tuple;

import utils.bytelist;


private enum ubyte NULL_ID = 255;

private T max(T)(T a, T b) pure if (isNumeric!T) => (a > b) ? a : b;
private alias MemRange = Tuple!(int, "start", int, "end");

int mem_size(MemRange range) pure => range.end - range.start;

struct MemStore
{
    int count = 0;
    // contains free spaces;
    MemRange[254] free_space_buffer = void;
    // TODO: remove value, uncessary memory
    // contains indices to free space
    ByteList!254 free_space_list;


    // Just another alias
    ref inout(ByteList!254) list() return inout => this.free_space_list;

    this(int mem_size)
    {
        this.free_space_list.push_front(0);
        free_space_buffer[this.list.head_id] = MemRange(0, mem_size);
    }

    void push(MemRange mem)
    {
        ubyte id = this.list.push_front(cast(ubyte)count++);
        this.free_space_buffer[id] = mem;
    }

    // returns id (relative to `free_spaces` of the memrange
    NodeInfo find_free_space(int size)
    {
        foreach (NodeInfo info; this.free_space_list) {
            if (free_space_buffer[info.current].mem_size() >= size)
                return info; // can find current and next from prev
        }
        return NodeInfo();
    }

    // Return start index to memory block that fits size
    int take_mem(int size) // all units in voxel_faces
    {
        NodeInfo info = find_free_space(size);
        if (info.index == NULL_ID)
            return NULL_ID; // no free space found

        MemRange* range = &free_space_buffer[info.current];
        int start = range.start;
        // take memory away from free space
        range.start += size;
        if (range.start == range.end) // free empty space
            free_space_list.remove(info.index);

        return start;
    }

    // Insert free memory in 
    ubyte sorted_insert(MemRange range)
    {
        ubyte index = this.list.count;
        foreach (NodeInfo info; this.list) {
            MemRange* free_mem = &this.free_space_buffer[info.current];

            // Head should always have the lowest start
            if (range.start < free_mem.start) {
                index = info.index;
                break;
            }
        }

        ubyte id = this.list.insert(index, 0);
        this.free_space_buffer[id] = range;

        return index;
    }

    // TODO: Unittest this shit
    void free_mem(MemRange range)
    {
        this.sorted_insert(range);
        // TODO: Could make this faster by passing index
        this.optimize();
    }

    void optimize()
    {
        // Search free memory blocks that are close together and fuse them
        // also figure out a way to move memory around
        MemRange* prev = null, current = null, next = null;
        foreach (NodeInfo info; this.list) {
            current = &this.free_space_buffer[info.current];

            if (info.prev != NULL_ID)
                prev = &this.free_space_buffer[info.prev];

            if (info.next != NULL_ID)
                next = &this.free_space_buffer[info.next];

            // First delete next if need then delete prev, so that index
            // doesn't affect the operation
            if (info.next != NULL_ID && current.end >= next.start) {
                current.end = .max(current.end, next.end);
                this.list.remove(cast(ubyte)(info.index+1));
            }
            // Since list is sorted prev is less than current
            if (info.prev != NULL_ID && prev.end >= current.start) { // adjacent to the left
                current.start = prev.start;
                current.end = .max(prev.end, current.end);
                // Deleting prev and next is theoretically safe... I think
                this.list.remove(cast(ubyte)(info.index-1));
            }
        }
    }
}

/* unittest */
/* { */
/*     MemStore */
/* } */


// Maybe test harder
unittest
{
    import std.stdio;

    static void create_rep()(MemStore mem, ref char[] mem_rep)
    {
        mem_rep[] = '0';
        foreach (NodeInfo info; mem.free_space_list) {
            MemRange mem_range = mem.free_space_buffer[info.current];
            // fill this range with Fs
            mem_rep[mem_range.start..mem_range.end] = 'F';
        }
    }

    enum int MEM_SIZE = 64;
    // Let's say we got 32 bytes, and 1 unit is 1 byte
    MemStore mem_store = MemStore(MEM_SIZE);
    int mem1_ptr = mem_store.take_mem(8); // take 4 bytes
    assert(mem1_ptr == 0);

    int mem2_ptr = mem_store.take_mem(2); // take 2 bytes
    assert(mem2_ptr == 8);

    int mem3_ptr = mem_store.take_mem(2); // take 2 bytes
    assert(mem3_ptr == 10);

    mem_store.free_mem(MemRange(4, 8));

    int mem_ptr = mem_store.take_mem(4); // take 4 bytes
    assert(mem_ptr == 4);

    mem_store.free_mem(MemRange(0, MEM_SIZE)); // all is free
    // so now I can take all the memory
    mem_store.take_mem(MEM_SIZE);
    // All memory taken so no free space blocks
    assert(mem_store.free_space_list.length == 0);

    /* char[MEM_SIZE] mem_rep = void; */
    /* create_rep(mem_store, mem_rep[]); */
    /* /1* create_rep(mem_rep); *1/ */
    /* writeln(mem_rep); */

}
