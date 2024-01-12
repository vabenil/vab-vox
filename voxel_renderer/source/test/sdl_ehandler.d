module test.sdl_ehandler;

public import test.event_handler;

import bindbc.sdl;


struct SDL_EHandler
{
    enum Event
    {
        ON_QUIT          =  "quit",
        ON_MOUSE_MOVE    =  "mouse_move",
        ON_MOUSE_CLICK   =  "mouse_click",
        ON_MOUSE_WHEEL   =  "mouse_wheel",
        ON_KEY_DOWN      =  "key_down",
        ON_TEXTINPUT     =  "text_input",
        ON_WINDOW_FOCUS  =  "window_focus",
        ON_ANY           =  "any",
    }

    private EHandler ehandler;

    alias cb_fn_t = EHandler.cb_fn_t;
    alias cb_al_t = EHandler.cb_alter_t;

    @safe pure
    string sdl_event_to_str(int event)
    {
        switch (event) {
            case SDL_QUIT:
                return Event.ON_QUIT;
            case SDL_MOUSEMOTION:
                return Event.ON_MOUSE_MOVE;
            case SDL_MOUSEWHEEL:
                return Event.ON_MOUSE_WHEEL;
            case SDL_MOUSEBUTTONDOWN:
                return Event.ON_MOUSE_CLICK;
            case SDL_KEYDOWN: 
                return Event.ON_KEY_DOWN;
            case SDL_TEXTINPUT: 
                return Event.ON_TEXTINPUT;
            case SDL_WINDOWEVENT:
                return Event.ON_WINDOW_FOCUS;
            default:
                return "INVALID_SDL_EVENT";
        }
    }

    @system
    private void add_handler_(T)(string event, T func)
    {
        import std.traits : EnumMembers;

        final switch (event) {
            case Event.ON_QUIT,
                 Event.ON_MOUSE_MOVE,
                 Event.ON_MOUSE_WHEEL,
                 Event.ON_MOUSE_CLICK,
                 Event.ON_KEY_DOWN,
                 Event.ON_TEXTINPUT,
                 Event.ON_WINDOW_FOCUS,
                 Event.ON_ANY:

                ehandler.add_handler(event, func);
                break;
        }
    }

    // TODO: A must be type SDL_Event so just use that
    @trusted
    void add_handler(B)(string event, void delegate(SDL_Event*, B*) func)
    {
        add_handler_(event, func);
    }

    @trusted
    void add_handler(B)(string event, void function(SDL_Event*, B*) func)
    {
        add_handler_(event, func);
    }

    @trusted
    void add_handler(string event, void function(SDL_Event*) func)
    {
        add_handler!(void)(event, (SDL_Event* e, void *) => func(e));
    }

    @trusted
    void add_handler(string event, void delegate(SDL_Event*) func)
    {
        add_handler!(void)(event, (SDL_Event* e, void *) => func(e));
    }

    @safe
    void remove_listener(string event)
    {
        ehandler.remove_listener(event);
    }

    @system
    void handle_sdl_events(T)(T* user_data)
    {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            ehandler.trigger_handlers("any", &e, user_data); // always trigger
            // TODO: Check if event is valid and throw if not
            ehandler.trigger_handlers(sdl_event_to_str(e.type), &e, user_data);
        }
    }
}
