module mui_renderer;

import nuklear_sdl_gl3;
import mrenderer;
import bindbc.sdl;
import bindbc.opengl;

enum size_t MAX_VERTEX_MEM = 20 * 0x4000;
enum size_t MAX_ELEMENT_MEM = short.sizeof * 0x6000;

class MUIRenderer : MRenderer
{
    SDL_Window* win = null;
    nk_context* ctx = null;

    this(SDL_Window* win) { this.win = win; }

    void initialize()
    {
        version(BindNuklear_Static) {}
        else {
            NuklearSupport nuksup = loadNuklear();
            if(nuksup != NuklearSupport.Nuklear4)
            {
                writeln("Error: Nuklear library is not found.");
                return null;
            }
            writeln(nuksup);
        }

        assert(win !is null, "UIRenderer not properly initialized");

        ctx = nk_sdl_init(win);
        nk_font_atlas *atlas;
        nk_font *font;

        nk_sdl_font_stash_begin(&atlas);
        font = nk_font_atlas_add_default(atlas, 13.0f, null);
        nk_sdl_font_stash_end();

        nk_style_set_font(ctx, &font.handle);
        nk_init_default(ctx, &font.handle);
    }

    void render()
    {
        nk_style_item bg;
        bg.type = NK_STYLE_ITEM_COLOR;
        bg.data.color = nk_rgba_f(0, 0, 0, 0.6);
        nk_style_push_style_item(ctx, &ctx.style.window.fixed_background, bg);
        /* writeln(cast(size_t)ctx.style.window.fixed_background.type); */
        /* writeln(ctx.style.window.fixed_background.data.color); */

        nk_rect bounds = nk_rect(0.5 * (600 - 180), 30, 180, 100);
        if (nk_begin(ctx, "nuklear", bounds, NK_WINDOW_NO_SCROLLBAR)) {
            nk_layout_row_dynamic(ctx, 20, 1);
            nk_label(ctx, "This is an example label", NK_TEXT_LEFT);
        }
        nk_end(ctx);
        nk_style_pop_style_item(ctx);

        nk_sdl_render(NK_ANTI_ALIASING_OFF, MAX_VERTEX_MEM, MAX_ELEMENT_MEM);
    }

    void shutdown() { nk_sdl_shutdown(); }
}
