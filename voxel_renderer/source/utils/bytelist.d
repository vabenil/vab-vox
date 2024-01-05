module utils.bytelist;

import std.typecons : Tuple, tuple;

// List node for a stack
struct ListNode {
    enum byte NULL_ID = -1;

    byte value;
    byte next_id = NULL_ID;
}

struct NodeInfo
{
    byte prev = ListNode.NULL_ID;
    byte current = ListNode.NULL_ID;
    byte next = ListNode.NULL_ID;
    byte index = ListNode.NULL_ID;
}

// This is kinda more of a stack
// Meant to be really small
struct ByteList(ubyte capacity)
{
    alias NULL_ID = ListNode.NULL_ID;

    // All Ids are meant to index this array
    byte free_head = NULL_ID;
    // List with 128 free_node spaces
    byte head_id = NULL_ID;

    ubyte count = 0;
    ubyte buff_size = 0;
    ListNode[capacity] buffer = void;

    this(byte[] v)
    {
        foreach (e; v)
            this.push_front(e);
    }

    byte push_front(byte value)
    {
        ubyte node_id = get_new_id();
        if (node_id == NULL_ID)
            return NULL_ID;

        this.buffer[node_id].value = value;
        this.buffer[node_id].next_id = head_id;
        head_id = node_id;
        // Buff_size get's updated in `get_new_id` if needed
        count++;

        return node_id;
    }

    ListNode head_node() const pure => buffer[head_id];

    inout(ListNode) next(ListNode node) inout => buffer[node.next_id];

    byte head() const pure => this.head_node().value;

    byte pop()
    {
        byte prev_head = this.head_id;
        this.head_id = this.buffer[prev_head].next_id;

        // Value can still be accessed after free_node because, we data is still there
        free_node(prev_head);

        return this.buffer[prev_head].value;
    }

    // Return NULL_ID in case of failure
    ubyte get_new_id()
    {
        byte id = this.free_head;
        // nothing freed, so just take from end of buffer
        if (id == NULL_ID) {
            if (this.buff_size == capacity) {// reached limit
                return NULL_ID;
            }
            return this.buff_size++;
        }

        // Update head_id of free_node list
        this.free_head = this.buffer[id].next_id;
        return id;
    }

    byte get_node_id(byte index) const
    {
        byte i = 0;
        byte node_id = head_id;
        for (; node_id != NULL_ID; node_id = this.buffer[node_id].next_id, i++)
            if (i == index)
                break;

        return (i == index) ? node_id : NULL_ID;
    }

    // Storing a list within a list without allocating any extra space
    // Free ListNode at id
    void free_node(byte node_id)
    {
        // If trying to free from the end just reduce count
        count--;
        if (node_id == buff_size-1) {
            // If the last thing is removed;
            // free_head no longer necessary if list is empty
            free_head = NULL_ID;
            buff_size = cast(byte)(count ? buff_size - 1 : 0);
            return;
        }

        byte* freed_id = &free_head;
        // Get me the next free space to store the index of the node_id of the freed node
        for (; (*freed_id) != NULL_ID; freed_id = &(buffer[*freed_id].next_id)) {}

        *freed_id = node_id;
        this.buffer[node_id].next_id = NULL_ID; // Mark the end of the free_node list
    }

    // Return id of inserted value or NULL_ID if there's not enough space
    byte insert(byte index, byte value)
    {
        byte node_id = get_new_id();

        if (node_id == NULL_ID)
            return NULL_ID;

        this.buffer[node_id].value = value;

        if (index == 0) {
            this.buffer[node_id].next_id = this.head_id;
            this.head_id = node_id;
        }
        else {
            byte prev_node_id = this.get_node_id(cast(byte)(index-1));

            this.buffer[node_id].next_id = this.buffer[prev_node_id].next_id;
            this.buffer[prev_node_id].next_id = node_id;
        }
        count++;
        return node_id;
    }

    void remove(byte index)
    {
        byte node_id = this.get_node_id(index);

        if (index == 0) {
            this.head_id = this.buffer[node_id].next_id;
        }
        else {
            byte prev_node_id = this.get_node_id(cast(byte)(index-1));
            this.buffer[prev_node_id].next_id = this.buffer[node_id].next_id;
        }

        free_node(node_id);
    }

    @property
    int length() const pure => count;

    byte opIndex(byte index) const => this.buffer[this.get_node_id(index)].value;

    bool opEquals()(auto ref ByteList!capacity list)
    {
        if (this.length != list.length)
            return false;

        byte a_id = this.head_id,
             b_id = list.head_id;

        while (a_id != NULL_ID) {
            if (this.buffer[a_id].value != list.buffer[b_id].value) {
                return false;
            }
            a_id = this.buffer[a_id].next_id;
            b_id = list.buffer[b_id].next_id;
        }
        return true;
    }

    // This could be nogc;
    string toString() const
    {
        import std.conv : to;

        string list_str = "[";
        // Don't use pointers, copying 2 bytes is easier than an 8 byte pointer
        byte node_id = this.head_id;
        for (; node_id != NULL_ID; node_id = this.buffer[node_id].next_id) {
            ListNode node = this.buffer[node_id];

            list_str ~= node.value.to!string;
            if (node.next_id != NULL_ID)
                list_str ~= ", ";
        }
        list_str ~= "]";

        return list_str;
    }

    int opApply(int delegate(NodeInfo) ops) const
    {
        int result = 0; // all ok

        NodeInfo info;
        info.index = 0;
        info.prev = NULL_ID;
        info.current = this.head_id;
        info.next = NULL_ID;

        for (; info.current != NULL_ID; info.current = this.buffer[info.current].next_id) {
            info.next = this.buffer[info.current].next_id;
            result = ops(info);
            if (result)
                break; // early exit
            info.prev = info.current;
            info.index++;
        }
        return result;
    }

    int opApply(int delegate(ListNode node, int node_id) ops) const
    {
        int result = 0; // all ok
        foreach (NodeInfo info; this) {
            result = ops(this.buffer[info.current], info.current);
            if (result)
                break;
        }
        return result;
    }

    int opApply(int delegate(ref ListNode node) ops) const
    {
        int result = 0; // all ok
        foreach (ListNode node, int _; this) {
            result = ops(node);
            if (result)
                break; // early exit
        }
        return result;
    }
}

unittest
{
    import std.stdio;

    ByteList!4 list;

    static foreach (i; 1..5) 
        list.push_front(i);

    assert(list == ByteList!4([1, 2, 3, 4]));

    list.remove(1);

    assert(list == ByteList!4([1, 2, 4]));

    list.insert(1, 3);

    assert(list == ByteList!4([1, 2, 3, 4]));

    list.remove(3);
    list.remove(2);

    assert(list == ByteList!4([3, 4]));

    list.remove(1);
    list.remove(0);

    assert(list == ByteList!4([]));

    static foreach (i; 1..5)
        list.push_front(i);

    assert(list == ByteList!4([1, 2, 3, 4]));

    /* foreach (ListNode node; list) */
    /*     writeln(node); */
}
