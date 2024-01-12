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

    @property {
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

    this(E[] array_)
    in (array.length <= capacity)
    {
        this._length = cast(uint)array_.length;
        this.array[0..array_.length] = array_;
    }

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
    @safe nothrow
    bool insert(E value, int i)
    {
        import std.stdio;
        if (_length == capacity)
            return false;

        this._length++;
        this.array[i+1.._length] = this.array[i.._length-1].idup;
        this.array[i] = value;
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
        => this.opApply((int i, const E v) => ops(v));

    int opApply(int delegate(ref E value) ops)
        => this.opApply((int i, ref E v) => ops(v));
}
