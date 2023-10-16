struct EHandler
{
    struct Callback
    {
        private static uint num = 0;

        uint id;
        cb_fn_t func;

        @safe
        this(cb_fn_t func)
        {
            this.id = num++;
            this.func = func;
        }
    }

    alias cb_alter_t = void function(void *e_data, void *user_data);
    alias cb_fn_t = void delegate(void *event_data, void *user_data);
    alias listener_t  = Callback[uint];

    listener_t[string] listeners;

    @trusted
    uint add_handler(A1, A2)(string event, void delegate(A1*, A2*) func)
    {
        Callback cb = Callback(cast(cb_fn_t)func);
        listener_t *listener = event in listeners;
        if (listener) {
            (*listener)[cb.id] = cb;
        }
        else {
            listeners[event] = [
                cb.id: cb
            ];
        }
        return cb.id;
    }

    @trusted
    uint add_handler(A1, A2)(string event, void function(A1*, A2*) alter_func)
    {
        import std.functional : toDelegate;
        return this.add_handler(event, toDelegate(alter_func));
    }

    @safe
    void remove_listener(string event)
    {
        this.listeners.remove(event);
    }

    @safe
    void remove_callback(string event, uint cb_id)
    {
        listener_t *listener = event in this.listeners;
        if (listener) {
            (*listener).remove(cb_id);
        }
    }

    // Not safe
    void trigger_handlers(A, B)(string event, A* event_data, B* user_data)
    {
        listener_t *listener = event in this.listeners;

        if (listener)
            foreach (callback; *listener) {
                callback.func(cast(void*)event_data, cast(void*)user_data);
            }
    }
}
