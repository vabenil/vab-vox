module utils.capedarray;

// Basically an array with a costant capacity and dynamic length
struct CapedArray(ElementType, uint capacity)
{
    // All of this is @safe and @nogc as long
    // as `ElementType` copy constructor is @safe and @nogc

    alias E = ElementType;
    // Makes no sense to make an array with that's more than 4 gb
    // for that just use a dynamic array

    // Not private but shouldn't be modified unless you know what you are doing
    uint _length = 0;

    E[capacity] array = void;

    @property @safe @nogc nothrow {
        int length() const pure => this._length;

        // Safely modify length
        void length(uint new_length) in(new_length <= capacity )
        {
            this._length = new_length;
        }

        uint opDollar(size_t dim : 0)() const pure => this.length;
    }

    @safe @nogc nothrow
    ref inout(E) opIndex(int index) return inout => array[index];

    @safe @nogc nothrow
    this(E[] array_)
    in (array.length <= capacity)
    {
        this._length = cast(uint)array_.length;
        this.array[0..array_.length] = array_;
    }

    @safe @nogc nothrow
    void clear() { this._length = 0; }

    int find(E value)
    {
        foreach (int i, const(E) val; this)
            if (val == value)
                return i;
        return -1;
    }

    // Will return false if operation failed
    @safe @nogc nothrow
    bool append(E value)
    {
        if (_length == capacity)
            return false;

        this.array[_length++] = value;
        return true;
    }

    // GC because of idup
    @safe @nogc nothrow
    bool insert(E value, int index) in (index >= 0)
    {
        if (_length == capacity)
            return false;

        // Shift values after index 1 to the right
        for (int j = _length; j > index; j--)
            this.array[j] = this.array[j-1];

        this.array[index] = value;
        this._length++;
        return true;
    }

    @safe @nogc nothrow
    bool opOpAssign(string op : "~")(E value) => append(value);

    // Overrides for iterators
    // Can't know whether this will be safe, nothrow or anything really
    // I guess I will need a template for this
    int opApply(int delegate(int index, ref E value) ops)
    {
        int result = 0;
        for (int i = 0; i < this.length; i++) {
            result = ops(i, this.array[i]);
            if (result)
                break;
        }
        return result;
    }

    int opApply(int delegate(int index, const E value) ops)
    {
        int result = 0;
        for (int i = 0; i < this.length; i++) {
            result = ops(i, this.array[i]);
            if (result)
                break;
        }
        return result;
    }

    int opApply(int delegate(const E value) ops)
        => this.opApply((int _, const E v) => ops(v));

    int opApply(int delegate(ref E value) ops)
        => this.opApply((int _, ref E v) => ops(v));
}

// Create an array-like interface for a "pointer" + length pair
struct CapedArrayView(T, uint capacity)
{
    uint* length = null;
    T[] mem = void;

    @disable this();

    this(T[] mem_slice, uint* length) in (mem.length == capacity)
    {
        this.mem = mem_slice;
        this.length = length;
    }
}
