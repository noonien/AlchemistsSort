/* Goose's gfx layer for the browser: the C API of src/gfx/gfx_api.h in the
   Goose source, on SDL3's Emscripten port for the window and input and on
   WebGL 2 (OpenGL ES 3.0) for drawing, in place of SDL_GPU, which has no
   web backend.

   The window and input half follows src/gfx/gfx_device.c closely, so key
   names, mouse coordinates in pixels and the per-frame edges behave as on
   the desktop. The drawing half covers what 2D programs use: buffers, 2D
   textures and samplers, pipelines from embed_shader blobs, render passes
   into the screen or a texture, uniforms, scissor and instanced draws.
   Shaders come from the table web/shaders.py builds (GLSL ES from each
   blob's SPIR-V); compute, 3D and array textures, multisampling and
   loading image files report that the web does not have them.

   Like SDL_GPU, the program draws into a screen texture that frame() shows;
   frame() then waits for the browser's next animation frame, which needs
   the program built with Asyncify. */

#include <SDL3/SDL.h>
#include <GLES3/gl3.h>
#include <emscripten.h>

#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gfx_api.h"
#include "gfx_blob.h"
#include "shaders_web.h"

/* --- handles --------------------------------------------------------------- */
/* As in gfx_device.c: (generation << 20) | index, so a stale handle is caught. */

#define GFX_INDEX_BITS 20
#define GFX_INDEX_MASK ((1u << GFX_INDEX_BITS) - 1)

typedef struct {
    const char *what;
    unsigned char *items;
    uint16_t *gens;
    uint8_t *live;
    uint32_t *freelist;
    uint32_t count, cap, nfree, item_size;
} gfx_table;

/* --- resources ------------------------------------------------------------- */

typedef struct {
    GLuint buf;
    GLenum target;              /* GL_ARRAY_BUFFER, or GL_ELEMENT_ARRAY_BUFFER for indices */
    uint32_t size, usage;
} gfx_buffer_slot;

typedef struct {
    GLuint tex;                 /* 0 for a depth target, which is a renderbuffer */
    GLuint rbo;
    GLuint fbo;                 /* made when first drawn into */
    GLenum internal, format, type;
    int bytes_per_pixel;
    gs_gfx_texture_desc desc;
    bool screen;
} gfx_texture_slot;

typedef struct {
    GLuint smp;
} gfx_sampler_slot;

typedef struct {
    uint8_t stage;
    uint16_t num_samplers, num_uniform_buffers;
    uint32_t uniform_sizes[4];
    int num_inputs;
    gs_gfx_blob_input inputs[16];
    const gs_web_shader *web;
} gfx_shader_info;

typedef struct {
    GLuint location;
    int slot;                   /* vertex buffer 0, or 1 per instance */
    int format;                 /* VERTEX_* */
    uint32_t offset;
} gfx_attr;

typedef struct {
    GLuint program;
    gfx_shader_info vs, fs;
    gs_gfx_pipeline_desc desc;
    gfx_attr attrs[16];
    int nattrs;
    uint32_t stride[2];
    uint32_t vbuf_mask;
} gfx_pipeline_slot;

/* --- the one state --------------------------------------------------------- */

enum { GFX_STAGES = 2, GFX_UNITS_PER_STAGE = 4 };

typedef struct {
    bool open;
    SDL_Window *window;
    SDL_GLContext gl;
    bool video_inited;
    int64_t flags;

    gs_gfx_texture screen, screen_depth;
    int width, height;
    bool drawn;                 /* into the screen since the last frame() */

    /* The pass being recorded. */
    bool pass;
    int target_w, target_h;
    gfx_pipeline_slot *pipeline;
    struct { GLuint buf; int64_t offset; bool bound; } vbufs[2];
    struct { GLuint buf; int64_t offset; int size; bool bound; } ibuf;
    uint32_t samplers_bound[GFX_STAGES];
    uint32_t uniforms_pushed[GFX_STAGES];
    GLuint ubos[GFX_STAGES][4];
    GLuint vao;
    uint32_t enabled_attrs;

    /* Input, as gfx_device.c keeps it. */
    bool quit;
    uint8_t keys[SDL_SCANCODE_COUNT];
    uint8_t pressed_keys[SDL_SCANCODE_COUNT], released_keys[SDL_SCANCODE_COUNT];
    uint32_t buttons, pressed_buttons, released_buttons;
    float mouse_x, mouse_y, mouse_dx, mouse_dy, wheel;
    bool mouse_in, focused, mouse_relative, cursor_visible;
    uint8_t button_clicks[32];
    int window_w, window_h, window_pw, window_ph;
    gs_gfx_event *events;
    int64_t nevents, events_cap;
    char *clipboard;

    uint64_t start_ns, last_ns;
    double delta;
    int64_t frames;

    char error[1024];
    int64_t misuse;

    gfx_table buffers, textures, samplers, pipelines;
} gfx_state;

static gfx_state gfx;
static int64_t gfx_opens;

/* --- errors ---------------------------------------------------------------- */

static bool gfx_fail(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vsnprintf(gfx.error, sizeof gfx.error, fmt, args);
    va_end(args);
    return false;
}

static bool gfx_misuse(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vsnprintf(gfx.error, sizeof gfx.error, fmt, args);
    va_end(args);
    if (++gfx.misuse <= 8) fprintf(stderr, "gfx: %s\n", gfx.error);
    return false;
}

/* What a desktop program may do that a browser cannot. */
static bool gfx_unsupported(const char *what) {
    return gfx_fail("%s: not available in the browser", what);
}

static bool gfx_need_device(const char *what) {
    if (gfx.open) return true;
    return gfx_misuse("%s: gfx is not open (call gfx::open first)", what);
}

int64_t gs_gfx_error(gs_gfx_bytes out) {
    int64_t n = (int64_t)strlen(gfx.error);
    int64_t k = n < out.len ? n : out.len;
    if (k > 0) memcpy(out.data, gfx.error, (size_t)k);
    return n;
}

int64_t gs_gfx_misuse_count(void) { return gfx.misuse; }

/* --- handle tables --------------------------------------------------------- */

static void *gfx_table_add(gfx_table *t, uint32_t *id) {
    uint32_t i;
    if (t->nfree) {
        i = t->freelist[--t->nfree];
    } else {
        if (t->count == t->cap) {
            uint32_t cap = t->cap ? t->cap * 2 : 64;
            if (cap > GFX_INDEX_MASK) {
                gfx_fail("too many %ss", t->what);
                return NULL;
            }
            t->items = (unsigned char *)realloc(t->items, (size_t)cap * t->item_size);
            t->gens = (uint16_t *)realloc(t->gens, cap * sizeof(uint16_t));
            t->live = (uint8_t *)realloc(t->live, cap);
            t->freelist = (uint32_t *)realloc(t->freelist, cap * sizeof(uint32_t));
            t->cap = cap;
        }
        i = t->count++;
        t->gens[i] = 0;
    }
    t->gens[i] = (uint16_t)(t->gens[i] % 4095 + 1);
    t->live[i] = 1;
    void *item = t->items + (size_t)i * t->item_size;
    memset(item, 0, t->item_size);
    *id = ((uint32_t)t->gens[i] << GFX_INDEX_BITS) | i;
    return item;
}

static void *gfx_table_find(gfx_table *t, uint32_t id) {
    uint32_t i = id & GFX_INDEX_MASK;
    if (!id || i >= t->count || !t->live[i] || t->gens[i] != id >> GFX_INDEX_BITS) return NULL;
    return t->items + (size_t)i * t->item_size;
}

static void *gfx_table_get(gfx_table *t, uint32_t id) {
    void *item = gfx_table_find(t, id);
    if (!item) {
        if (!id) gfx_misuse("a null %s handle", t->what);
        else gfx_misuse("a %s handle that was released, or never created", t->what);
    }
    return item;
}

static void gfx_table_remove(gfx_table *t, uint32_t id) {
    if (!gfx_table_find(t, id)) return;
    uint32_t i = id & GFX_INDEX_MASK;
    t->live[i] = 0;
    t->freelist[t->nfree++] = i;
}

static void gfx_table_each(gfx_table *t, void (*f)(void *item)) {
    for (uint32_t i = 0; i < t->count; i++)
        if (t->live[i]) f(t->items + (size_t)i * t->item_size);
}

static void gfx_table_clear(gfx_table *t) {
    free(t->items);
    free(t->gens);
    free(t->live);
    free(t->freelist);
    const char *what = t->what;
    uint32_t size = t->item_size;
    memset(t, 0, sizeof *t);
    t->what = what;
    t->item_size = size;
}

static void gfx_init_tables(void) {
    gfx.buffers.what = "buffer";
    gfx.buffers.item_size = sizeof(gfx_buffer_slot);
    gfx.textures.what = "texture";
    gfx.textures.item_size = sizeof(gfx_texture_slot);
    gfx.samplers.what = "sampler";
    gfx.samplers.item_size = sizeof(gfx_sampler_slot);
    gfx.pipelines.what = "pipeline";
    gfx.pipelines.item_size = sizeof(gfx_pipeline_slot);
}

/* --- textures -------------------------------------------------------------- */

/* A Goose texture format as GL's internal format, format and type. */
static bool gfx_gl_format(int32_t f, gfx_texture_slot *s) {
    switch (f) {
        case GS_GFX_RGBA8: case GS_GFX_BGRA8:
            s->internal = GL_RGBA8; s->format = GL_RGBA; s->type = GL_UNSIGNED_BYTE;
            s->bytes_per_pixel = 4; return true;
        case GS_GFX_RGBA8_SRGB:
            s->internal = GL_SRGB8_ALPHA8; s->format = GL_RGBA; s->type = GL_UNSIGNED_BYTE;
            s->bytes_per_pixel = 4; return true;
        case GS_GFX_R8:
            s->internal = GL_R8; s->format = GL_RED; s->type = GL_UNSIGNED_BYTE;
            s->bytes_per_pixel = 1; return true;
        case GS_GFX_RG8:
            s->internal = GL_RG8; s->format = GL_RG; s->type = GL_UNSIGNED_BYTE;
            s->bytes_per_pixel = 2; return true;
        case GS_GFX_RGBA16F:
            s->internal = GL_RGBA16F; s->format = GL_RGBA; s->type = GL_HALF_FLOAT;
            s->bytes_per_pixel = 8; return true;
        case GS_GFX_RGBA32F:
            s->internal = GL_RGBA32F; s->format = GL_RGBA; s->type = GL_FLOAT;
            s->bytes_per_pixel = 16; return true;
        case GS_GFX_R32F:
            s->internal = GL_R32F; s->format = GL_RED; s->type = GL_FLOAT;
            s->bytes_per_pixel = 4; return true;
        case GS_GFX_DEPTH: case GS_GFX_DEPTH24: case GS_GFX_DEPTH24_STENCIL8:
            s->internal = GL_DEPTH24_STENCIL8; s->format = GL_DEPTH_STENCIL;
            s->type = GL_UNSIGNED_INT_24_8; s->bytes_per_pixel = 4; return true;
        case GS_GFX_DEPTH32F:
            s->internal = GL_DEPTH_COMPONENT32F; s->format = GL_DEPTH_COMPONENT;
            s->type = GL_FLOAT; s->bytes_per_pixel = 4; return true;
        case GS_GFX_DEPTH16:
            s->internal = GL_DEPTH_COMPONENT16; s->format = GL_DEPTH_COMPONENT;
            s->type = GL_UNSIGNED_SHORT; s->bytes_per_pixel = 2; return true;
        default:
            return false;
    }
}

static bool gfx_is_depth(int32_t f) {
    return f == GS_GFX_DEPTH || f == GS_GFX_DEPTH16 || f == GS_GFX_DEPTH24 ||
           f == GS_GFX_DEPTH32F || f == GS_GFX_DEPTH24_STENCIL8;
}

static int gfx_mip_count(int w, int h) {
    int n = 1;
    while ((w > 1 || h > 1) && n < 16) {
        w = w > 1 ? w / 2 : 1;
        h = h > 1 ? h / 2 : 1;
        n++;
    }
    return n;
}

/* Storage for a 2D texture slot as its desc says. */
static bool gfx_texture_storage(gfx_texture_slot *s) {
    const gs_gfx_texture_desc *d = &s->desc;
    if (!gfx_gl_format(d->format, s)) return gfx_unsupported("that texture format");
    if (gfx_is_depth(d->format) && !(d->usage & GS_GFX_SAMPLED)) {
        glGenRenderbuffers(1, &s->rbo);
        glBindRenderbuffer(GL_RENDERBUFFER, s->rbo);
        glRenderbufferStorage(GL_RENDERBUFFER, s->internal, d->width, d->height);
        return true;
    }
    glGenTextures(1, &s->tex);
    glBindTexture(GL_TEXTURE_2D, s->tex);
    glTexStorage2D(GL_TEXTURE_2D, d->mips, s->internal, d->width, d->height);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, d->mips - 1);
    return glGetError() == GL_NO_ERROR || gfx_fail("creating a texture");
}

static void gfx_free_texture(void *item) {
    gfx_texture_slot *s = (gfx_texture_slot *)item;
    if (s->fbo) glDeleteFramebuffers(1, &s->fbo);
    if (s->tex) glDeleteTextures(1, &s->tex);
    if (s->rbo) glDeleteRenderbuffers(1, &s->rbo);
    s->fbo = s->tex = s->rbo = 0;
}

static gfx_texture_slot *gfx_texture_slot_of(gs_gfx_texture t) {
    return (gfx_texture_slot *)gfx_table_get(&gfx.textures, t.id);
}

/* The screen: a texture with a depth buffer beside it, drawn to the canvas by
   frame(). Its handles stay the same when a resize replaces them. */
static bool gfx_create_screen(int w, int h) {
    if (w < 1) w = 1;
    if (h < 1) h = 1;
    gs_gfx_texture *handles[2] = { &gfx.screen, &gfx.screen_depth };
    int32_t formats[2] = { GS_GFX_RGBA8, GS_GFX_DEPTH };
    int32_t usages[2] = { GS_GFX_COLOR_TARGET | GS_GFX_SAMPLED, GS_GFX_DEPTH_TARGET };
    for (int i = 0; i < 2; i++) {
        gfx_texture_slot *s = (gfx_texture_slot *)gfx_table_find(&gfx.textures, handles[i]->id);
        if (s) gfx_free_texture(s);
        else s = (gfx_texture_slot *)gfx_table_add(&gfx.textures, &handles[i]->id);
        if (!s) return false;
        memset(s, 0, sizeof *s);
        s->screen = true;
        s->desc.kind = GS_GFX_TEXTURE_2D;
        s->desc.format = formats[i];
        s->desc.usage = usages[i];
        s->desc.width = w;
        s->desc.height = h;
        s->desc.depth = 1;
        s->desc.mips = 1;
        s->desc.samples = 1;
        if (!gfx_texture_storage(s)) return false;
    }
    gfx.width = w;
    gfx.height = h;
    return true;
}

/* The framebuffer that draws into color texture `c`, with depth `d` (or none). */
static GLuint gfx_framebuffer(gfx_texture_slot *c, gfx_texture_slot *d) {
    gfx_texture_slot *owner = c ? c : d;
    if (!owner->fbo) {
        glGenFramebuffers(1, &owner->fbo);
        glBindFramebuffer(GL_FRAMEBUFFER, owner->fbo);
        if (c) glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, c->tex, 0);
    }
    glBindFramebuffer(GL_FRAMEBUFFER, owner->fbo);
    if (c) {
        GLenum att = d ? (d->format == GL_DEPTH_STENCIL ? GL_DEPTH_STENCIL_ATTACHMENT
                                                        : GL_DEPTH_ATTACHMENT)
                       : GL_DEPTH_STENCIL_ATTACHMENT;
        if (d && d->rbo) glFramebufferRenderbuffer(GL_FRAMEBUFFER, att, GL_RENDERBUFFER, d->rbo);
        else if (d) glFramebufferTexture2D(GL_FRAMEBUFFER, att, GL_TEXTURE_2D, d->tex, 0);
        else glFramebufferRenderbuffer(GL_FRAMEBUFFER, att, GL_RENDERBUFFER, 0);
    } else if (d->rbo) {
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, d->rbo);
    } else {
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, d->tex, 0);
    }
    return owner->fbo;
}

gs_gfx_texture gs_gfx_screen(void) {
    gfx_need_device("screen");
    return gfx.screen;
}

gs_gfx_texture gs_gfx_screen_depth(void) {
    gfx_need_device("screen_depth");
    return gfx.screen_depth;
}

void gs_gfx_screen_size(gs_gfx_int2 *out) {
    out->x = gfx.width;
    out->y = gfx.height;
}

/* --- open and close -------------------------------------------------------- */

uint8_t gs_gfx_available(void) { return 1; }

static const char *gfx_cstr(gs_gfx_bytes s, char *buf, size_t cap) {
    size_t n = s.len < 0 ? 0 : (size_t)s.len;
    if (n >= cap) n = cap - 1;
    if (n) memcpy(buf, s.data, n);
    buf[n] = 0;
    return buf;
}

static void gfx_update_input_scale(void) {
    int w = 0, h = 0, pw = 0, ph = 0;
    if (!gfx.window || !SDL_GetWindowSize(gfx.window, &w, &h) ||
        !SDL_GetWindowSizeInPixels(gfx.window, &pw, &ph) || w <= 0 || h <= 0 || pw <= 0 ||
        ph <= 0)
        return;
    gfx.window_w = w;
    gfx.window_h = h;
    gfx.window_pw = pw;
    gfx.window_ph = ph;
}

static float gfx_to_pixels(float v, int pixels, int size) {
    return (float)((double)v * pixels / size);
}

uint8_t gs_gfx_open(gs_gfx_bytes title, int64_t width, int64_t height, int64_t flags) {
    if (gfx.open) return gfx_misuse("gfx is already open: close() it first");
    if (width < 1 || height < 1 || width > 16384 || height > 16384)
        return gfx_misuse("a screen of %lld x %lld pixels", (long long)width, (long long)height);
    gfx.error[0] = 0;
    gfx.flags = flags;
    gfx_init_tables();
    /* frame() waits for the browser itself; SDL must not yield on its own. */
    SDL_SetHint(SDL_HINT_EMSCRIPTEN_ASYNCIFY, "0");
    if (!SDL_InitSubSystem(SDL_INIT_VIDEO)) return gfx_fail("initializing SDL video: %s", SDL_GetError());
    gfx.video_inited = true;
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
    SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 0);
    SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 0);
    char buf[512];
    /* A web page's canvas fills the page, whatever size the program asks
       for: the program lays itself out by screen_size, as on a resize. */
    SDL_WindowFlags wf = SDL_WINDOW_OPENGL | SDL_WINDOW_HIGH_PIXEL_DENSITY |
                         SDL_WINDOW_RESIZABLE | SDL_WINDOW_FILL_DOCUMENT;
    gfx.window = SDL_CreateWindow(gfx_cstr(title, buf, sizeof buf), (int)width, (int)height, wf);
    if (!gfx.window) {
        gfx_fail("creating the window: %s", SDL_GetError());
        gs_gfx_close();
        return false;
    }
    gfx.gl = SDL_GL_CreateContext(gfx.window);
    if (!gfx.gl) {
        gfx_fail("no WebGL 2: %s", SDL_GetError());
        gs_gfx_close();
        return false;
    }
    gfx.open = true;
    glGenVertexArrays(1, &gfx.vao);
    glBindVertexArray(gfx.vao);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    int pw = 1, ph = 1;
    SDL_GetWindowSizeInPixels(gfx.window, &pw, &ph);
    gfx_update_input_scale();
    gfx.focused = true;
    gfx.mouse_in = true;
    gfx.cursor_visible = true;
    if (!gfx_create_screen(pw, ph)) {
        char why[sizeof gfx.error];
        memcpy(why, gfx.error, sizeof why);
        gs_gfx_close();
        memcpy(gfx.error, why, sizeof why);
        return false;
    }
    gfx.start_ns = gfx.last_ns = SDL_GetTicksNS();
    gfx_opens++;
    return true;
}

uint8_t gs_gfx_open_headless(int64_t width, int64_t height, int64_t flags) {
    (void)width, (void)height, (void)flags;
    return gfx_unsupported("open_headless");
}

static void gfx_free_buffer(void *item) {
    gfx_buffer_slot *s = (gfx_buffer_slot *)item;
    if (s->buf) glDeleteBuffers(1, &s->buf);
}

static void gfx_free_sampler(void *item) {
    gfx_sampler_slot *s = (gfx_sampler_slot *)item;
    if (s->smp) glDeleteSamplers(1, &s->smp);
}

static void gfx_free_pipeline(void *item) {
    gfx_pipeline_slot *s = (gfx_pipeline_slot *)item;
    if (s->program) glDeleteProgram(s->program);
}

void gs_gfx_close(void) {
    if (gfx.open) {
        gfx_table_each(&gfx.buffers, gfx_free_buffer);
        gfx_table_each(&gfx.textures, gfx_free_texture);
        gfx_table_each(&gfx.samplers, gfx_free_sampler);
        gfx_table_each(&gfx.pipelines, gfx_free_pipeline);
        for (int st = 0; st < GFX_STAGES; st++)
            for (int i = 0; i < 4; i++)
                if (gfx.ubos[st][i]) glDeleteBuffers(1, &gfx.ubos[st][i]);
        if (gfx.vao) glDeleteVertexArrays(1, &gfx.vao);
    }
    gfx_table_clear(&gfx.buffers);
    gfx_table_clear(&gfx.textures);
    gfx_table_clear(&gfx.samplers);
    gfx_table_clear(&gfx.pipelines);
    free(gfx.events);
    SDL_free(gfx.clipboard);
    if (gfx.gl) SDL_GL_DestroyContext(gfx.gl);
    if (gfx.window) SDL_DestroyWindow(gfx.window);
    if (gfx.video_inited) SDL_QuitSubSystem(SDL_INIT_VIDEO);
    char error[sizeof gfx.error];
    memcpy(error, gfx.error, sizeof error);
    int64_t misuse = gfx.misuse;
    memset(&gfx, 0, sizeof gfx);
    memcpy(gfx.error, error, sizeof error);
    gfx.misuse = misuse;
}

int64_t gs_gfx_driver(gs_gfx_bytes out) {
    const char *name = gfx.open ? "webgl2" : "";
    int64_t n = (int64_t)strlen(name);
    int64_t k = n < out.len ? n : out.len;
    if (k > 0) memcpy(out.data, name, (size_t)k);
    return n;
}

void gs_gfx_set_title(gs_gfx_bytes title) {
    char buf[512];
    if (gfx.window) SDL_SetWindowTitle(gfx.window, gfx_cstr(title, buf, sizeof buf));
}

void gs_gfx_quit(void) { gfx.quit = true; }

void gs_gfx_flush(void) {
    if (!gfx_need_device("flush")) return;
    glFinish();
}

/* --- frames ---------------------------------------------------------------- */

/* Hands control back to the browser until its next animation frame, which
   is when it shows the canvas and delivers input. */
EM_ASYNC_JS(void, gfx_wait_for_browser, (void), {
    await new Promise(resolve => requestAnimationFrame(resolve));
});

/* The screen onto the canvas. */
static void gfx_present(void) {
    gfx_texture_slot *s = gfx_texture_slot_of(gfx.screen);
    if (!s) return;
    int pw = gfx.width, ph = gfx.height;
    SDL_GetWindowSizeInPixels(gfx.window, &pw, &ph);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, gfx_framebuffer(s, NULL));
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
    glDisable(GL_SCISSOR_TEST);
    glBlitFramebuffer(0, 0, gfx.width, gfx.height, 0, 0, pw, ph, GL_COLOR_BUFFER_BIT,
                      pw == gfx.width && ph == gfx.height ? GL_NEAREST : GL_LINEAR);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

static gs_gfx_event *gfx_event(int32_t kind) {
    if (gfx.nevents == gfx.events_cap) {
        gfx.events_cap = gfx.events_cap ? gfx.events_cap * 2 : 64;
        gfx.events = (gs_gfx_event *)realloc(gfx.events,
                                             sizeof(gs_gfx_event) * (size_t)gfx.events_cap);
    }
    gs_gfx_event *e = &gfx.events[gfx.nevents++];
    memset(e, 0, sizeof *e);
    e->kind = kind;
    return e;
}

static int32_t gfx_mods(void) {
    int32_t m = 0;
    if (gfx.keys[SDL_SCANCODE_LSHIFT] || gfx.keys[SDL_SCANCODE_RSHIFT]) m |= GS_GFX_MOD_SHIFT;
    if (gfx.keys[SDL_SCANCODE_LCTRL] || gfx.keys[SDL_SCANCODE_RCTRL]) m |= GS_GFX_MOD_CTRL;
    if (gfx.keys[SDL_SCANCODE_LALT] || gfx.keys[SDL_SCANCODE_RALT]) m |= GS_GFX_MOD_ALT;
    if (gfx.keys[SDL_SCANCODE_LGUI] || gfx.keys[SDL_SCANCODE_RGUI]) m |= GS_GFX_MOD_GUI;
    return m;
}

static void gfx_text_events(const char *text) {
    if (!text) return;
    Uint32 cp;
    while ((cp = SDL_StepUTF8(&text, NULL)) != 0)
        gfx_event(GS_GFX_EVENT_TEXT)->codepoint = cp;
}

static void gfx_key_event(SDL_Scancode sc, SDL_Keycode key, bool down, bool repeat) {
    if (sc > SDL_SCANCODE_UNKNOWN && sc < SDL_SCANCODE_COUNT) {
        if (down && !gfx.keys[sc]) gfx.pressed_keys[sc] = 1;
        if (!down && gfx.keys[sc]) gfx.released_keys[sc] = 1;
        gfx.keys[sc] = down;
    }
    gs_gfx_event *ev = gfx_event(GS_GFX_EVENT_KEY);
    ev->scancode = (int32_t)sc;
    ev->keycode = (int32_t)key;
    ev->mods = gfx_mods();
    ev->down = down;
    ev->repeat = repeat;
}

static void gfx_button_event(int button, bool down, int clicks) {
    if (button > 0 && button < 32) {
        uint32_t bit = 1u << button;
        if (down && !(gfx.buttons & bit)) gfx.pressed_buttons |= bit;
        if (!down && (gfx.buttons & bit)) gfx.released_buttons |= bit;
        gfx.buttons = down ? gfx.buttons | bit : gfx.buttons & ~bit;
        if (down) gfx.button_clicks[button] = (uint8_t)clicks;
    }
    gs_gfx_event *ev = gfx_event(GS_GFX_EVENT_MOUSE_BUTTON);
    ev->button = button;
    ev->clicks = clicks;
    ev->down = down;
    ev->x = gfx.mouse_x;
    ev->y = gfx.mouse_y;
}

/* A page losing focus lets go of every key and button, as a window does. */
static void gfx_focus(bool focused) {
    if (gfx.focused == focused) return;
    gfx.focused = focused;
    if (!focused) {
        for (int sc = 1; sc < SDL_SCANCODE_COUNT; sc++)
            if (gfx.keys[sc])
                gfx_key_event((SDL_Scancode)sc,
                              SDL_GetKeyFromScancode((SDL_Scancode)sc, SDL_KMOD_NONE, false),
                              false, false);
        for (int b = 1; b < 32; b++)
            if (gfx.buttons & (1u << b)) gfx_button_event(b, false, gfx.button_clicks[b]);
        gfx.mouse_dx = gfx.mouse_dy = gfx.wheel = 0;
    }
    gfx_event(focused ? GS_GFX_EVENT_FOCUS_GAINED : GS_GFX_EVENT_FOCUS_LOST);
}

uint8_t gs_gfx_frame(void) {
    if (!gfx_need_device("frame")) return 0;
    if (gfx.pass) {
        gfx_misuse("frame() inside a render pass: end the pass first");
        return 0;
    }
    /* The first call starts the first frame; every later one ends one. */
    if (gfx.frames > 0) {
        if (gfx.drawn) gfx_present();
        gfx.drawn = false;
        gfx_wait_for_browser();
    }
    memset(gfx.pressed_keys, 0, sizeof gfx.pressed_keys);
    memset(gfx.released_keys, 0, sizeof gfx.released_keys);
    gfx.pressed_buttons = gfx.released_buttons = 0;
    gfx.mouse_dx = gfx.mouse_dy = gfx.wheel = 0;
    gfx.nevents = 0;
    bool resized = false;
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        switch (e.type) {
            case SDL_EVENT_QUIT:
            case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
                gfx.quit = true;
                break;
            case SDL_EVENT_KEY_DOWN:
            case SDL_EVENT_KEY_UP:
                if (gfx.focused) gfx_key_event(e.key.scancode, e.key.key, e.key.down, e.key.repeat);
                break;
            case SDL_EVENT_TEXT_INPUT:
                if (gfx.focused) gfx_text_events(e.text.text);
                break;
            case SDL_EVENT_MOUSE_MOTION: {
                if (!gfx.focused) break;
                gfx.mouse_x = gfx_to_pixels(e.motion.x, gfx.window_pw, gfx.window_w);
                gfx.mouse_y = gfx_to_pixels(e.motion.y, gfx.window_ph, gfx.window_h);
                gfx.mouse_dx += gfx_to_pixels(e.motion.xrel, gfx.window_pw, gfx.window_w);
                gfx.mouse_dy += gfx_to_pixels(e.motion.yrel, gfx.window_ph, gfx.window_h);
                gs_gfx_event *ev = gfx_event(GS_GFX_EVENT_MOUSE_MOTION);
                ev->x = gfx.mouse_x;
                ev->y = gfx.mouse_y;
            } break;
            case SDL_EVENT_MOUSE_BUTTON_DOWN:
            case SDL_EVENT_MOUSE_BUTTON_UP:
                if (!gfx.focused) break;
                gfx.mouse_x = gfx_to_pixels(e.button.x, gfx.window_pw, gfx.window_w);
                gfx.mouse_y = gfx_to_pixels(e.button.y, gfx.window_ph, gfx.window_h);
                gfx_button_event(e.button.button, e.button.down, e.button.clicks);
                break;
            case SDL_EVENT_MOUSE_WHEEL: {
                if (!gfx.focused) break;
                gfx.wheel += e.wheel.y;
                gs_gfx_event *ev = gfx_event(GS_GFX_EVENT_MOUSE_WHEEL);
                ev->x = e.wheel.x;
                ev->y = e.wheel.y;
            } break;
            case SDL_EVENT_WINDOW_MOUSE_ENTER:
            case SDL_EVENT_WINDOW_MOUSE_LEAVE:
                gfx.mouse_in = e.type == SDL_EVENT_WINDOW_MOUSE_ENTER;
                break;
            case SDL_EVENT_WINDOW_FOCUS_GAINED:
            case SDL_EVENT_WINDOW_FOCUS_LOST:
                gfx_focus(e.type == SDL_EVENT_WINDOW_FOCUS_GAINED);
                break;
            case SDL_EVENT_WINDOW_RESIZED:
                gfx_update_input_scale();
                break;
            case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
                gfx_update_input_scale();
                resized = true;
                break;
            default:
                break;
        }
    }
    if (resized) {
        int w = 0, h = 0;
        SDL_GetWindowSizeInPixels(gfx.window, &w, &h);
        if (w > 0 && h > 0 && (w != gfx.width || h != gfx.height)) gfx_create_screen(w, h);
    }
    uint64_t now = SDL_GetTicksNS();
    gfx.delta = (double)(now - gfx.last_ns) / 1e9;
    gfx.last_ns = now;
    gfx.frames++;
    return !gfx.quit;
}

double gs_gfx_time(void) {
    return gfx.open ? (double)(SDL_GetTicksNS() - gfx.start_ns) / 1e9 : 0.0;
}

double gs_gfx_delta_time(void) { return gfx.delta; }

int64_t gs_gfx_frame_count(void) { return gfx.frames; }

int64_t gs_gfx_open_count(void) { return gfx_opens; }

/* --- input ----------------------------------------------------------------- */

static const struct {
    SDL_Scancode scancode;
    const char *name;
} gfx_key_aliases[] = {
    { SDL_SCANCODE_LALT, "Left Alt" },     { SDL_SCANCODE_LALT, "Left Option" },
    { SDL_SCANCODE_RALT, "Right Alt" },    { SDL_SCANCODE_RALT, "Right Option" },
    { SDL_SCANCODE_LGUI, "Left GUI" },     { SDL_SCANCODE_LGUI, "Left Command" },
    { SDL_SCANCODE_LGUI, "Left Windows" }, { SDL_SCANCODE_RGUI, "Right GUI" },
    { SDL_SCANCODE_RGUI, "Right Command" }, { SDL_SCANCODE_RGUI, "Right Windows" },
    { SDL_SCANCODE_APPLICATION, "Application" },
};

static SDL_Scancode gfx_find_scancode(const char *name) {
    SDL_Scancode sc = SDL_GetScancodeFromName(name);
    for (size_t i = 0; sc == SDL_SCANCODE_UNKNOWN && i < SDL_arraysize(gfx_key_aliases); i++)
        if (SDL_strcasecmp(name, gfx_key_aliases[i].name) == 0) sc = gfx_key_aliases[i].scancode;
    return sc;
}

static SDL_Scancode gfx_scancode(gs_gfx_bytes name) {
    char buf[64];
    SDL_Scancode sc = gfx_find_scancode(gfx_cstr(name, buf, sizeof buf));
    if (sc == SDL_SCANCODE_UNKNOWN) gfx_misuse("no key is called '%s'", buf);
    return sc;
}

uint8_t gs_gfx_key_down(gs_gfx_bytes name) {
    SDL_Scancode sc = gfx_scancode(name);
    return sc != SDL_SCANCODE_UNKNOWN && gfx.keys[sc];
}

uint8_t gs_gfx_key_pressed(gs_gfx_bytes name) {
    SDL_Scancode sc = gfx_scancode(name);
    return sc != SDL_SCANCODE_UNKNOWN && gfx.pressed_keys[sc];
}

uint8_t gs_gfx_key_released(gs_gfx_bytes name) {
    SDL_Scancode sc = gfx_scancode(name);
    return sc != SDL_SCANCODE_UNKNOWN && gfx.released_keys[sc];
}

static uint32_t gfx_button(int64_t button) {
    if (button < 1 || button > 31) {
        gfx_misuse("no mouse button %lld", (long long)button);
        return 0;
    }
    return 1u << button;
}

uint8_t gs_gfx_mouse_down(int64_t button) { return (gfx.buttons & gfx_button(button)) != 0; }
uint8_t gs_gfx_mouse_pressed(int64_t button) { return (gfx.pressed_buttons & gfx_button(button)) != 0; }
uint8_t gs_gfx_mouse_released(int64_t button) { return (gfx.released_buttons & gfx_button(button)) != 0; }

void gs_gfx_mouse_pos(gs_gfx_float2 *out) {
    out->x = gfx.mouse_x;
    out->y = gfx.mouse_y;
}

void gs_gfx_mouse_delta(gs_gfx_float2 *out) {
    out->x = gfx.mouse_dx;
    out->y = gfx.mouse_dy;
}

float gs_gfx_mouse_wheel(void) { return gfx.wheel; }
uint8_t gs_gfx_mouse_in_window(void) { return gfx.mouse_in; }
uint8_t gs_gfx_focused(void) { return gfx.focused; }
uint8_t gs_gfx_mouse_relative(void) { return gfx.mouse_relative; }
uint8_t gs_gfx_cursor_visible(void) { return gfx.cursor_visible && !gfx.mouse_relative; }

uint8_t gs_gfx_set_mouse_relative(uint8_t on) {
    if (!gfx_need_device("set_mouse_relative")) return 0;
    bool enabled = on != 0;
    if (gfx.mouse_relative == enabled) return 1;
    if (!SDL_SetWindowRelativeMouseMode(gfx.window, enabled))
        return gfx_fail("set_mouse_relative: %s", SDL_GetError());
    gfx.mouse_relative = enabled;
    gfx.mouse_dx = gfx.mouse_dy = 0;
    return 1;
}

uint8_t gs_gfx_set_cursor_visible(uint8_t visible) {
    if (!gfx_need_device("set_cursor_visible")) return 0;
    bool show = visible != 0;
    if (!gfx.mouse_relative) {
        if (!(show ? SDL_ShowCursor() : SDL_HideCursor()))
            return gfx_fail("set_cursor_visible: %s", SDL_GetError());
    }
    gfx.cursor_visible = show;
    return 1;
}

/* Injected input is for tests, which run headless on the desktop. */
uint8_t gs_gfx_inject_focus(uint8_t focused) {
    (void)focused;
    return gfx_unsupported("inject_focus");
}

uint8_t gs_gfx_inject_key(gs_gfx_bytes name, uint8_t down) {
    (void)name, (void)down;
    return gfx_unsupported("inject_key");
}

void gs_gfx_inject_mouse(float x, float y, int64_t button, uint8_t down) {
    (void)x, (void)y, (void)button, (void)down;
    gfx_unsupported("inject_mouse");
}

uint8_t gs_gfx_inject_text(gs_gfx_bytes text) {
    (void)text;
    return gfx_unsupported("inject_text");
}

int64_t gs_gfx_events(gs_gfx_event_slice out) {
    int64_t k = gfx.nevents < out.len ? gfx.nevents : out.len;
    if (k > 0) memcpy(out.data, gfx.events, sizeof(gs_gfx_event) * (size_t)k);
    return gfx.nevents;
}

void gs_gfx_text_input(uint8_t on) {
    if (!gfx_need_device("text_input")) return;
    if (on) SDL_StartTextInput(gfx.window);
    else SDL_StopTextInput(gfx.window);
}

int64_t gs_gfx_scancode(gs_gfx_bytes name) {
    char buf[64];
    return gfx_find_scancode(gfx_cstr(name, buf, sizeof buf));
}

int64_t gs_gfx_key_name(int64_t scancode, gs_gfx_bytes out) {
    if (scancode < 0 || scancode >= SDL_SCANCODE_COUNT) {
        gfx_misuse("key_name: no scancode %lld", (long long)scancode);
        return 0;
    }
    const char *name = SDL_GetScancodeName((SDL_Scancode)scancode);
    int64_t n = (int64_t)strlen(name);
    int64_t k = n < out.len ? n : out.len;
    if (k > 0) memcpy(out.data, name, (size_t)k);
    return n;
}

/* The page keeps a clipboard of its own: the browser's needs a permission
   prompt and an async call. */
int64_t gs_gfx_clipboard(gs_gfx_bytes out) {
    int64_t n = gfx.clipboard ? (int64_t)strlen(gfx.clipboard) : 0;
    int64_t k = n < out.len ? n : out.len;
    if (k > 0) memcpy(out.data, gfx.clipboard, (size_t)k);
    return n;
}

uint8_t gs_gfx_set_clipboard(gs_gfx_bytes text) {
    size_t n = text.len > 0 ? (size_t)text.len : 0;
    char *copy = (char *)SDL_malloc(n + 1);
    if (!copy) return gfx_fail("out of memory for the clipboard");
    if (n) memcpy(copy, text.data, n);
    copy[n] = 0;
    SDL_free(gfx.clipboard);
    gfx.clipboard = copy;
    return 1;
}

/* --- buffers --------------------------------------------------------------- */

static gfx_buffer_slot *gfx_buffer_slot_of(gs_gfx_buffer b) {
    return (gfx_buffer_slot *)gfx_table_get(&gfx.buffers, b.id);
}

gs_gfx_buffer gs_gfx_create_buffer(int64_t usage, int64_t size, gs_gfx_bytes data) {
    gs_gfx_buffer h = { 0 };
    if (!gfx_need_device("buffer")) return h;
    if (size < data.len) size = data.len;
    if (size <= 0 || size > 0x7fffffff) {
        gfx_misuse("a buffer of %lld bytes", (long long)size);
        return h;
    }
    if (!usage || (usage & ~(int64_t)63)) {
        gfx_misuse("buffer usage %lld is not a combination of the BUFFER_ flags", (long long)usage);
        return h;
    }
    if (usage & (GS_GFX_BUFFER_STORAGE | GS_GFX_BUFFER_COMPUTE_READ | GS_GFX_BUFFER_COMPUTE_WRITE |
                 GS_GFX_BUFFER_INDIRECT)) {
        gfx_unsupported("storage, compute and indirect buffers");
        return h;
    }
    gfx_buffer_slot *s = (gfx_buffer_slot *)gfx_table_add(&gfx.buffers, &h.id);
    if (!s) return h;
    /* WebGL never lets an index buffer be bound as anything else. */
    s->target = (usage & GS_GFX_BUFFER_INDEX) ? GL_ELEMENT_ARRAY_BUFFER : GL_ARRAY_BUFFER;
    s->size = (uint32_t)size;
    s->usage = (uint32_t)usage;
    glGenBuffers(1, &s->buf);
    glBindBuffer(s->target, s->buf);
    /* Zeroed past the data, as on the desktop. */
    void *zero = calloc(1, (size_t)size);
    if (data.len > 0) memcpy(zero, data.data, (size_t)data.len);
    glBufferData(s->target, size, zero, GL_DYNAMIC_DRAW);
    free(zero);
    return h;
}

uint8_t gs_gfx_update_buffer(gs_gfx_buffer b, int64_t offset, gs_gfx_bytes data) {
    if (!gfx_need_device("update_buffer")) return 0;
    gfx_buffer_slot *s = gfx_buffer_slot_of(b);
    if (!s) return 0;
    if (offset < 0 || data.len < 0 || offset + data.len > (int64_t)s->size)
        return gfx_misuse("update_buffer: %lld bytes at %lld do not fit a buffer of %u",
                          (long long)data.len, (long long)offset, s->size);
    if (data.len == 0) return 1;
    glBindBuffer(s->target, s->buf);
    glBufferSubData(s->target, offset, data.len, data.data);
    return 1;
}

uint8_t gs_gfx_read_buffer(gs_gfx_buffer b, int64_t offset, gs_gfx_bytes out) {
    (void)b, (void)offset, (void)out;
    return gfx_unsupported("read_buffer");
}

int64_t gs_gfx_buffer_size(gs_gfx_buffer b) {
    gfx_buffer_slot *s = gfx_buffer_slot_of(b);
    return s ? s->size : 0;
}

void gs_gfx_release_buffer(gs_gfx_buffer b) {
    if (!gfx_need_device("release_buffer")) return;
    gfx_buffer_slot *s = gfx_buffer_slot_of(b);
    if (!s) return;
    gfx_free_buffer(s);
    gfx_table_remove(&gfx.buffers, b.id);
}

/* --- textures and samplers ------------------------------------------------- */

gs_gfx_texture gs_gfx_create_texture(const gs_gfx_texture_desc *desc) {
    gs_gfx_texture h = { 0 };
    if (!gfx_need_device("texture")) return h;
    gs_gfx_texture_desc d = *desc;
    if (d.kind != GS_GFX_TEXTURE_2D) {
        gfx_unsupported("3D, array and cube textures");
        return h;
    }
    if (d.width < 1 || d.height < 1 || d.width > 16384 || d.height > 16384) {
        gfx_misuse("a texture of %d x %d", d.width, d.height);
        return h;
    }
    if (d.samples > 1) {
        gfx_unsupported("multisampled textures");
        return h;
    }
    if (d.usage & (GS_GFX_STORAGE_READ | GS_GFX_COMPUTE_READ | GS_GFX_COMPUTE_WRITE |
                   GS_GFX_COMPUTE_READ_WRITE)) {
        gfx_unsupported("storage and compute textures");
        return h;
    }
    if (!d.usage) d.usage = GS_GFX_SAMPLED;
    int full = gfx_mip_count(d.width, d.height);
    if (d.mips <= 0 || d.mips > full) d.mips = full;
    d.depth = 1;
    d.samples = 1;
    gfx_texture_slot *s = (gfx_texture_slot *)gfx_table_add(&gfx.textures, &h.id);
    if (!s) return h;
    s->desc = d;
    if (!gfx_texture_storage(s)) {
        gfx_free_texture(s);
        gfx_table_remove(&gfx.textures, h.id);
        h.id = 0;
    }
    return h;
}

gs_gfx_texture gs_gfx_load_texture(gs_gfx_bytes path, int64_t flags) {
    (void)path, (void)flags;
    gs_gfx_texture h = { 0 };
    gfx_unsupported("load_texture");
    return h;
}

/* Region `r` of texture `s`, whole mip when r->w is 0, checked against it. */
static bool gfx_region(gfx_texture_slot *s, const gs_gfx_region *r, int *x, int *y, int *w,
                       int *h, const char *what) {
    if (r->mip < 0 || r->mip >= s->desc.mips || r->layer != 0)
        return gfx_misuse("%s: no mip %d, layer %d", what, r->mip, r->layer);
    int mw = s->desc.width >> r->mip, mh = s->desc.height >> r->mip;
    mw = mw ? mw : 1;
    mh = mh ? mh : 1;
    *x = r->w ? r->x : 0;
    *y = r->w ? r->y : 0;
    *w = r->w ? r->w : mw;
    *h = r->w ? r->h : mh;
    if (*x < 0 || *y < 0 || *w < 1 || *h < 1 || *x + *w > mw || *y + *h > mh)
        return gfx_misuse("%s: a region outside the %d x %d mip", what, mw, mh);
    return true;
}

uint8_t gs_gfx_update_texture(gs_gfx_texture t, const gs_gfx_region *region, gs_gfx_bytes data) {
    if (!gfx_need_device("update_texture")) return 0;
    gfx_texture_slot *s = gfx_texture_slot_of(t);
    if (!s) return 0;
    if (!s->tex) return gfx_misuse("update_texture: a depth target");
    int x, y, w, h;
    if (!gfx_region(s, region, &x, &y, &w, &h, "update_texture")) return 0;
    int64_t need = (int64_t)w * h * s->bytes_per_pixel;
    if (data.len != need)
        return gfx_misuse("update_texture: %lld bytes for a %d x %d region of %d-byte pixels",
                          (long long)data.len, w, h, s->bytes_per_pixel);
    glBindTexture(GL_TEXTURE_2D, s->tex);
    glTexSubImage2D(GL_TEXTURE_2D, region->mip, x, y, w, h, s->format, s->type, data.data);
    return 1;
}

uint8_t gs_gfx_read_texture(gs_gfx_texture t, const gs_gfx_region *region, gs_gfx_bytes out) {
    if (!gfx_need_device("read_texture")) return 0;
    gfx_texture_slot *s = gfx_texture_slot_of(t);
    if (!s) return 0;
    if (!s->tex || s->bytes_per_pixel != 4 || s->type != GL_UNSIGNED_BYTE)
        return gfx_unsupported("reading back that texture format");
    int x, y, w, h;
    if (!gfx_region(s, region, &x, &y, &w, &h, "read_texture")) return 0;
    if (region->mip != 0) return gfx_unsupported("reading back a mip");
    int64_t need = (int64_t)w * h * 4;
    if (out.len < need) return gfx_misuse("read_texture: %lld bytes for %lld", (long long)out.len,
                                          (long long)need);
    glBindFramebuffer(GL_FRAMEBUFFER, gfx_framebuffer(s, NULL));
    /* GL's rows run bottom up; gfx's top down. */
    glReadPixels(x, s->desc.height - y - h, w, h, GL_RGBA, GL_UNSIGNED_BYTE, out.data);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    uint8_t *row = (uint8_t *)malloc((size_t)w * 4);
    for (int i = 0; i < h / 2; i++) {
        uint8_t *a = out.data + (size_t)i * w * 4, *b = out.data + (size_t)(h - 1 - i) * w * 4;
        memcpy(row, a, (size_t)w * 4);
        memcpy(a, b, (size_t)w * 4);
        memcpy(b, row, (size_t)w * 4);
    }
    free(row);
    return 1;
}

uint8_t gs_gfx_save_png(gs_gfx_texture t, gs_gfx_bytes path) {
    (void)t, (void)path;
    return gfx_unsupported("save_png");
}

void gs_gfx_generate_mips(gs_gfx_texture t) {
    if (!gfx_need_device("generate_mips")) return;
    gfx_texture_slot *s = gfx_texture_slot_of(t);
    if (!s || !s->tex) return;
    glBindTexture(GL_TEXTURE_2D, s->tex);
    glGenerateMipmap(GL_TEXTURE_2D);
}

uint8_t gs_gfx_texture_info(gs_gfx_texture t, gs_gfx_texture_desc *out) {
    gfx_texture_slot *s = gfx_texture_slot_of(t);
    if (!s) return 0;
    *out = s->desc;
    return 1;
}

void gs_gfx_release_texture(gs_gfx_texture t) {
    if (!gfx_need_device("release_texture")) return;
    gfx_texture_slot *s = gfx_texture_slot_of(t);
    if (!s) return;
    if (s->screen) {
        gfx_misuse("release_texture: the screen is gfx's own");
        return;
    }
    gfx_free_texture(s);
    gfx_table_remove(&gfx.textures, t.id);
}

static GLenum gfx_wrap(int32_t w) {
    return w == GS_GFX_MIRROR ? GL_MIRRORED_REPEAT : w == GS_GFX_CLAMP ? GL_CLAMP_TO_EDGE : GL_REPEAT;
}

gs_gfx_sampler gs_gfx_create_sampler(const gs_gfx_sampler_desc *d) {
    gs_gfx_sampler h = { 0 };
    if (!gfx_need_device("sampler")) return h;
    gfx_sampler_slot *s = (gfx_sampler_slot *)gfx_table_add(&gfx.samplers, &h.id);
    if (!s) return h;
    glGenSamplers(1, &s->smp);
    bool lin = d->min_filter == GS_GFX_LINEAR, mip_lin = d->mip_filter == GS_GFX_LINEAR;
    GLenum min = lin ? (mip_lin ? GL_LINEAR_MIPMAP_LINEAR : GL_LINEAR_MIPMAP_NEAREST)
                     : (mip_lin ? GL_NEAREST_MIPMAP_LINEAR : GL_NEAREST_MIPMAP_NEAREST);
    glSamplerParameteri(s->smp, GL_TEXTURE_MIN_FILTER, (GLint)min);
    glSamplerParameteri(s->smp, GL_TEXTURE_MAG_FILTER,
                        d->mag_filter == GS_GFX_LINEAR ? GL_LINEAR : GL_NEAREST);
    glSamplerParameteri(s->smp, GL_TEXTURE_WRAP_S, (GLint)gfx_wrap(d->wrap_u));
    glSamplerParameteri(s->smp, GL_TEXTURE_WRAP_T, (GLint)gfx_wrap(d->wrap_v));
    glSamplerParameteri(s->smp, GL_TEXTURE_WRAP_R, (GLint)gfx_wrap(d->wrap_w));
    if (d->compare) {
        static const GLenum ops[] = { 0, GL_NEVER, GL_LESS, GL_EQUAL, GL_LEQUAL, GL_GREATER,
                                      GL_NOTEQUAL, GL_GEQUAL, GL_ALWAYS };
        glSamplerParameteri(s->smp, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE);
        glSamplerParameteri(s->smp, GL_TEXTURE_COMPARE_FUNC,
                            (GLint)ops[d->compare >= 1 && d->compare <= 8 ? d->compare : 4]);
    }
    return h;
}

void gs_gfx_release_sampler(gs_gfx_sampler smp) {
    if (!gfx_need_device("release_sampler")) return;
    gfx_sampler_slot *s = (gfx_sampler_slot *)gfx_table_get(&gfx.samplers, smp.id);
    if (!s) return;
    gfx_free_sampler(s);
    gfx_table_remove(&gfx.samplers, smp.id);
}

/* --- shaders and pipelines ------------------------------------------------- */

static uint64_t gfx_hash(const uint8_t *p, int64_t n) {
    uint64_t hash = 14695981039346656037ull;
    for (int64_t i = 0; i < n; i++) hash = (hash ^ p[i]) * 1099511628211ull;
    return hash;
}

/* A blob's reflection, and its GLSL ES from the generated table. */
static bool gfx_read_blob(gs_gfx_bytes blob, int stage, gfx_shader_info *info) {
    gs_gfx_blob_header h;
    if (blob.len >= (int64_t)sizeof h) memcpy(&h, blob.data, sizeof h);
    if (blob.len < (int64_t)sizeof h || memcmp(h.magic, GS_GFX_BLOB_MAGIC, 4) != 0)
        return gfx_misuse("not a shader: pass what embed_shader returns");
    if (h.version != GS_GFX_BLOB_VERSION)
        return gfx_misuse("a shader blob of version %d, where this gfx reads version %d", h.version,
                          GS_GFX_BLOB_VERSION);
    if (h.stage != stage)
        return gfx_misuse("a %s shader where a %s shader goes", h.stage ? "fragment" : "vertex",
                          stage ? "fragment" : "vertex");
    if (h.num_uniform_buffers > 4 || h.num_inputs > 16 || h.num_samplers > 4)
        return gfx_unsupported("a shader with more than 4 uniform blocks or samplers");
    if (h.num_storage_buffers_ro || h.num_storage_textures_ro)
        return gfx_unsupported("storage buffers and textures in a shader");
    memset(info, 0, sizeof *info);
    info->stage = h.stage;
    info->num_samplers = h.num_samplers;
    info->num_uniform_buffers = h.num_uniform_buffers;
    const uint8_t *p = blob.data + sizeof h;
    for (int i = 0; i < h.num_uniform_buffers; i++, p += 4) memcpy(&info->uniform_sizes[i], p, 4);
    info->num_inputs = h.num_inputs;
    for (int i = 0; i < h.num_inputs; i++, p += sizeof(gs_gfx_blob_input))
        memcpy(&info->inputs[i], p, sizeof(gs_gfx_blob_input));
    uint64_t hash = gfx_hash(blob.data, blob.len);
    for (int i = 0; i < gs_web_shader_count; i++)
        if (gs_web_shaders[i].hash == hash && gs_web_shaders[i].size == (uint32_t)blob.len)
            info->web = &gs_web_shaders[i];
    if (!info->web)
        return gfx_misuse("a shader the web build has no GLSL ES for: rerun web/shaders.py on "
                          "the program's C");
    return true;
}

static GLuint gfx_compile(GLenum kind, const char *src) {
    GLuint s = glCreateShader(kind);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[1024] = "";
        glGetShaderInfoLog(s, sizeof log, NULL, log);
        gfx_misuse("compiling a %s shader: %s", kind == GL_VERTEX_SHADER ? "vertex" : "fragment",
                   log);
        glDeleteShader(s);
        return 0;
    }
    return s;
}

/* Bytes and GL layout of each VERTEX_* format. */
static const struct {
    uint32_t size;
    GLint n;
    GLenum type;
    char kind;                  /* 'f' float, 'n' normalized, 'i' integer */
} gfx_vertex_formats[] = {
    { 0, 0, 0, 0 },
    { 4, 1, GL_FLOAT, 'f' }, { 8, 2, GL_FLOAT, 'f' }, { 12, 3, GL_FLOAT, 'f' },
    { 16, 4, GL_FLOAT, 'f' },
    { 4, 1, GL_INT, 'i' }, { 8, 2, GL_INT, 'i' }, { 12, 3, GL_INT, 'i' }, { 16, 4, GL_INT, 'i' },
    { 4, 1, GL_UNSIGNED_INT, 'i' }, { 8, 2, GL_UNSIGNED_INT, 'i' },
    { 12, 3, GL_UNSIGNED_INT, 'i' }, { 16, 4, GL_UNSIGNED_INT, 'i' },
    { 4, 4, GL_UNSIGNED_BYTE, 'n' }, { 4, 4, GL_BYTE, 'n' }, { 4, 4, GL_UNSIGNED_BYTE, 'i' },
    { 4, 2, GL_SHORT, 'i' }, { 8, 4, GL_SHORT, 'i' },
    { 4, 2, GL_UNSIGNED_SHORT, 'n' }, { 8, 4, GL_UNSIGNED_SHORT, 'n' },
    { 4, 2, GL_HALF_FLOAT, 'f' }, { 8, 4, GL_HALF_FLOAT, 'f' },
};

static int gfx_input_format(uint8_t type) {
    switch (type) {
        case GS_GFX_INPUT_FLOAT: return GS_GFX_VERTEX_FLOAT;
        case GS_GFX_INPUT_FLOAT2: return GS_GFX_VERTEX_FLOAT2;
        case GS_GFX_INPUT_FLOAT3: return GS_GFX_VERTEX_FLOAT3;
        case GS_GFX_INPUT_FLOAT4: case GS_GFX_INPUT_MAT4: return GS_GFX_VERTEX_FLOAT4;
        case GS_GFX_INPUT_INT: return GS_GFX_VERTEX_INT;
        case GS_GFX_INPUT_INT2: return GS_GFX_VERTEX_INT2;
        case GS_GFX_INPUT_INT3: return GS_GFX_VERTEX_INT3;
        case GS_GFX_INPUT_INT4: return GS_GFX_VERTEX_INT4;
        case GS_GFX_INPUT_UINT: return GS_GFX_VERTEX_UINT;
        case GS_GFX_INPUT_UINT2: return GS_GFX_VERTEX_UINT2;
        case GS_GFX_INPUT_UINT3: return GS_GFX_VERTEX_UINT3;
        case GS_GFX_INPUT_UINT4: return GS_GFX_VERTEX_UINT4;
        default: return 0;
    }
}

/* Inputs in location order, packed as a Goose struct lays out its fields:
   buffer 0 per vertex, or buffer 1 per instance from instance_location on. */
static bool gfx_vertex_layout(gfx_pipeline_slot *p) {
    gs_gfx_blob_input in[16];
    int n = p->vs.num_inputs;
    memcpy(in, p->vs.inputs, sizeof(in[0]) * (size_t)n);
    for (int i = 1; i < n; i++)
        for (int j = i; j > 0 && in[j - 1].location > in[j].location; j--) {
            gs_gfx_blob_input t = in[j];
            in[j] = in[j - 1];
            in[j - 1] = t;
        }
    for (int i = 0; i < n; i++) {
        int loc = in[i].location;
        int slot = p->desc.instance_location >= 0 && loc >= p->desc.instance_location ? 1 : 0;
        int columns = in[i].type == GS_GFX_INPUT_MAT4 ? 4 : 1;
        int fmt = gfx_input_format(in[i].type);
        int override = p->desc.formats[loc];
        if (override) {
            if (columns == 4 || override > GS_GFX_VERTEX_HALF4)
                return gfx_misuse("PipelineDesc.formats[%d]: format %d cannot feed the vertex "
                                  "shader's input at location %d", loc, override, loc);
            fmt = override;
        }
        for (int c = 0; c < columns; c++) {
            gfx_attr *a = &p->attrs[p->nattrs++];
            a->location = (GLuint)(loc + c);
            a->slot = slot;
            a->format = fmt;
            a->offset = p->stride[slot];
            p->stride[slot] += gfx_vertex_formats[fmt].size;
        }
    }
    for (int slot = 0; slot < 2; slot++)
        if (p->stride[slot]) p->vbuf_mask |= 1u << slot;
    return true;
}

gs_gfx_pipeline gs_gfx_create_pipeline(gs_gfx_bytes vs, gs_gfx_bytes fs,
                                       const gs_gfx_pipeline_desc *desc) {
    gs_gfx_pipeline h = { 0 };
    if (!gfx_need_device("pipeline")) return h;
    const gs_gfx_pipeline_desc *d = desc;
    if ((uint32_t)d->primitive > 4 || (uint32_t)d->cull > 2 || (uint32_t)d->blend > 4 ||
        (uint32_t)d->depth_compare > 8 || d->instance_location > 15) {
        gfx_misuse("a PipelineDesc with a primitive, cull, blend or compare that is not one of "
                   "gfx's constants");
        return h;
    }
    gfx_pipeline_slot tmp;
    memset(&tmp, 0, sizeof tmp);
    if (!gfx_read_blob(vs, GS_GFX_STAGE_VERTEX, &tmp.vs) ||
        !gfx_read_blob(fs, GS_GFX_STAGE_FRAGMENT, &tmp.fs))
        return h;
    tmp.desc = *d;
    if (!gfx_vertex_layout(&tmp)) return h;
    GLuint v = gfx_compile(GL_VERTEX_SHADER, tmp.vs.web->glsl);
    GLuint f = v ? gfx_compile(GL_FRAGMENT_SHADER, tmp.fs.web->glsl) : 0;
    if (!f) {
        if (v) glDeleteShader(v);
        return h;
    }
    GLuint prog = glCreateProgram();
    glAttachShader(prog, v);
    glAttachShader(prog, f);
    glLinkProgram(prog);
    glDeleteShader(v);
    glDeleteShader(f);
    GLint ok = 0;
    glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[1024] = "";
        glGetProgramInfoLog(prog, sizeof log, NULL, log);
        gfx_misuse("linking a pipeline: %s", log);
        glDeleteProgram(prog);
        return h;
    }
    /* GLSL ES 3.00 has no binding qualifiers: blocks and samplers go to the
       binding gfx gives each stage's slot, stage * 4 + slot. */
    glUseProgram(prog);
    const gfx_shader_info *stages[2] = { &tmp.vs, &tmp.fs };
    for (int st = 0; st < 2; st++) {
        for (int i = 0; i < stages[st]->num_uniform_buffers; i++) {
            GLuint idx = glGetUniformBlockIndex(prog, stages[st]->web->ubos[i]);
            if (idx != GL_INVALID_INDEX) glUniformBlockBinding(prog, idx, (GLuint)(st * 4 + i));
        }
        for (int i = 0; i < stages[st]->num_samplers; i++) {
            GLint loc = glGetUniformLocation(prog, stages[st]->web->samplers[i]);
            if (loc >= 0) glUniform1i(loc, st * GFX_UNITS_PER_STAGE + i);
        }
    }
    gfx_pipeline_slot *p = (gfx_pipeline_slot *)gfx_table_add(&gfx.pipelines, &h.id);
    if (!p) {
        glDeleteProgram(prog);
        return h;
    }
    *p = tmp;
    p->program = prog;
    return h;
}

void gs_gfx_release_pipeline(gs_gfx_pipeline p) {
    if (!gfx_need_device("release_pipeline")) return;
    gfx_pipeline_slot *s = (gfx_pipeline_slot *)gfx_table_get(&gfx.pipelines, p.id);
    if (!s) return;
    if (gfx.pipeline == s) gfx.pipeline = NULL;
    gfx_free_pipeline(s);
    gfx_table_remove(&gfx.pipelines, p.id);
}

gs_gfx_compute_pipeline gs_gfx_create_compute_pipeline(gs_gfx_bytes cs) {
    (void)cs;
    gs_gfx_compute_pipeline h = { 0 };
    gfx_unsupported("compute pipelines");
    return h;
}

void gs_gfx_release_compute_pipeline(gs_gfx_compute_pipeline p) { (void)p; }

/* --- render passes and drawing --------------------------------------------- */

static void gfx_reset_bindings(void) {
    memset(gfx.samplers_bound, 0, sizeof gfx.samplers_bound);
    memset(gfx.vbufs, 0, sizeof gfx.vbufs);
    memset(&gfx.ibuf, 0, sizeof gfx.ibuf);
}

uint8_t gs_gfx_begin_pass(const gs_gfx_pass_desc *d) {
    if (!gfx_need_device("begin_pass")) return 0;
    if (gfx.pass) return gfx_misuse("begin_pass inside a render pass: end it first");
    if (d->color[1].id) return gfx_unsupported("more than one color target");
    if (d->resolve[0].id) return gfx_unsupported("multisampled targets");
    gfx_texture_slot *c = NULL, *z = NULL;
    if (d->color[0].id) {
        c = gfx_texture_slot_of(d->color[0]);
        if (!c) return 0;
        if (!(c->desc.usage & GS_GFX_COLOR_TARGET))
            return gfx_misuse("begin_pass: color target 0 was not created with COLOR_TARGET");
        if (d->mip != 0 || d->layer != 0) return gfx_unsupported("drawing into a mip or layer");
    }
    if (d->depth.id) {
        z = gfx_texture_slot_of(d->depth);
        if (!z) return 0;
        if (!(z->desc.usage & GS_GFX_DEPTH_TARGET))
            return gfx_misuse("begin_pass: the depth target was not created with DEPTH_TARGET");
        if (c && (z->desc.width != c->desc.width || z->desc.height != c->desc.height))
            return gfx_misuse("begin_pass: the depth target and color target differ in size");
    }
    if (!c && !z) return gfx_misuse("begin_pass with no targets");
    gfx_texture_slot *size = c ? c : z;
    gfx.target_w = size->desc.width;
    gfx.target_h = size->desc.height;
    gfx_framebuffer(c, z);
    if (c) {
        GLenum att = GL_COLOR_ATTACHMENT0;
        glDrawBuffers(1, &att);
    }
    if (c && c->screen) gfx.drawn = true;
    glViewport(0, 0, gfx.target_w, gfx.target_h);
    glDisable(GL_SCISSOR_TEST);
    GLbitfield clear = 0;
    if (c && d->clear_color) {
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        glClearColor(d->color_value.x, d->color_value.y, d->color_value.z, d->color_value.w);
        clear |= GL_COLOR_BUFFER_BIT;
    }
    if (z && d->clear_depth) {
        glDepthMask(GL_TRUE);
        glClearDepthf(d->depth_value);
        clear |= GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT;
    }
    if (clear) glClear(clear);
    glEnable(GL_SCISSOR_TEST);
    glScissor(0, 0, gfx.target_w, gfx.target_h);
    gfx.pass = true;
    gfx.pipeline = NULL;
    gfx_reset_bindings();
    return 1;
}

void gs_gfx_end_pass(void) {
    if (!gfx.pass) {
        gfx_misuse("end_pass with no render pass begun");
        return;
    }
    gfx.pass = false;
    gfx.pipeline = NULL;
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

static void gfx_blend(int32_t mode) {
    if (mode == GS_GFX_BLEND_NONE) {
        glDisable(GL_BLEND);
        return;
    }
    glEnable(GL_BLEND);
    glBlendEquation(GL_FUNC_ADD);
    switch (mode) {
        case GS_GFX_BLEND_ALPHA:
            glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
            break;
        case GS_GFX_BLEND_ADD:
            glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE, GL_ZERO, GL_ONE);
            break;
        case GS_GFX_BLEND_PREMULTIPLIED:
            glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
            break;
        case GS_GFX_BLEND_MULTIPLY:
            glBlendFuncSeparate(GL_DST_COLOR, GL_ZERO, GL_ZERO, GL_ONE);
            break;
        default:
            break;
    }
}

void gs_gfx_bind_pipeline(gs_gfx_pipeline p) {
    if (!gfx.pass) {
        gfx_misuse("bind_pipeline outside a render pass");
        return;
    }
    gfx_pipeline_slot *s = (gfx_pipeline_slot *)gfx_table_get(&gfx.pipelines, p.id);
    if (!s) return;
    const gs_gfx_pipeline_desc *d = &s->desc;
    if (d->wireframe) {
        gfx_unsupported("wireframe drawing");
        return;
    }
    glUseProgram(s->program);
    gfx_blend(d->blend);
    if (d->cull == GS_GFX_CULL_NONE) {
        glDisable(GL_CULL_FACE);
    } else {
        glEnable(GL_CULL_FACE);
        glCullFace(d->cull == GS_GFX_CULL_FRONT ? GL_FRONT : GL_BACK);
    }
    glFrontFace(d->clockwise ? GL_CW : GL_CCW);
    if (d->depth_test || d->depth_write) {
        static const GLenum ops[] = { GL_LESS, GL_NEVER, GL_LESS, GL_EQUAL, GL_LEQUAL, GL_GREATER,
                                      GL_NOTEQUAL, GL_GEQUAL, GL_ALWAYS };
        glEnable(GL_DEPTH_TEST);
        glDepthFunc(d->depth_test ? ops[d->depth_compare] : GL_ALWAYS);
        glDepthMask(d->depth_write ? GL_TRUE : GL_FALSE);
    } else {
        glDisable(GL_DEPTH_TEST);
    }
    if (d->depth_bias != 0.0f || d->depth_bias_slope != 0.0f) {
        glEnable(GL_POLYGON_OFFSET_FILL);
        glPolygonOffset(d->depth_bias_slope, d->depth_bias);
    } else {
        glDisable(GL_POLYGON_OFFSET_FILL);
    }
    gfx.pipeline = s;
}

void gs_gfx_bind_vertex_buffer(int64_t slot, gs_gfx_buffer b, int64_t offset) {
    if (!gfx.pass) {
        gfx_misuse("bind_vertex_buffer outside a render pass");
        return;
    }
    gfx_buffer_slot *s = gfx_buffer_slot_of(b);
    if (!s) return;
    if (slot < 0 || slot > 1 || offset < 0 || offset >= s->size ||
        !(s->usage & GS_GFX_BUFFER_VERTEX)) {
        gfx_misuse("bind_vertex_buffer: slot %lld (0, or 1 for instances), offset %lld, of a "
                   "BUFFER_VERTEX buffer", (long long)slot, (long long)offset);
        return;
    }
    gfx.vbufs[slot].buf = s->buf;
    gfx.vbufs[slot].offset = offset;
    gfx.vbufs[slot].bound = true;
}

void gs_gfx_bind_index_buffer(gs_gfx_buffer b, int64_t index_size, int64_t offset) {
    if (!gfx.pass) {
        gfx_misuse("bind_index_buffer outside a render pass");
        return;
    }
    gfx_buffer_slot *s = gfx_buffer_slot_of(b);
    if (!s) return;
    if ((index_size != 2 && index_size != 4) || offset < 0 || offset >= s->size ||
        !(s->usage & GS_GFX_BUFFER_INDEX)) {
        gfx_misuse("bind_index_buffer: indices of 2 or 4 bytes, not %lld, from a BUFFER_INDEX "
                   "buffer", (long long)index_size);
        return;
    }
    gfx.ibuf.buf = s->buf;
    gfx.ibuf.offset = offset;
    gfx.ibuf.size = (int)index_size;
    gfx.ibuf.bound = true;
}

void gs_gfx_bind_texture(int64_t stage, int64_t slot, gs_gfx_texture t, gs_gfx_sampler smp) {
    if (!gfx.pass) {
        gfx_misuse("bind_texture outside a render pass");
        return;
    }
    if (stage < GS_GFX_VERTEX || stage > GS_GFX_FRAGMENT || slot < 0 || slot >= GFX_UNITS_PER_STAGE) {
        gfx_misuse("bind_texture: stage %lld, slot %lld", (long long)stage, (long long)slot);
        return;
    }
    gfx_texture_slot *s = gfx_texture_slot_of(t);
    gfx_sampler_slot *ss = (gfx_sampler_slot *)gfx_table_get(&gfx.samplers, smp.id);
    if (!s || !ss) return;
    if (!(s->desc.usage & GS_GFX_SAMPLED) || !s->tex) {
        gfx_misuse("bind_texture: the texture was not created SAMPLED");
        return;
    }
    GLuint unit = (GLuint)(stage * GFX_UNITS_PER_STAGE + slot);
    glActiveTexture(GL_TEXTURE0 + unit);
    glBindTexture(GL_TEXTURE_2D, s->tex);
    glBindSampler(unit, ss->smp);
    gfx.samplers_bound[stage] |= 1u << slot;
}

void gs_gfx_bind_storage_texture(int64_t stage, int64_t slot, gs_gfx_texture t) {
    (void)stage, (void)slot, (void)t;
    gfx_unsupported("storage textures");
}

void gs_gfx_bind_storage_buffer(int64_t stage, int64_t slot, gs_gfx_buffer b) {
    (void)stage, (void)slot, (void)b;
    gfx_unsupported("storage buffers");
}

void gs_gfx_push_uniforms(int64_t stage, int64_t slot, gs_gfx_bytes data) {
    if (!gfx_need_device("push_uniforms")) return;
    if (stage < GS_GFX_VERTEX || stage > GS_GFX_FRAGMENT || slot < 0 || slot > 3) {
        gfx_misuse("push_uniforms: stage %lld, slot %lld (0 to 3)", (long long)stage,
                   (long long)slot);
        return;
    }
    if (data.len <= 0 || data.len > 16384) {
        gfx_misuse("push_uniforms: %lld bytes (1 to 16384)", (long long)data.len);
        return;
    }
    const gfx_shader_info *info = gfx.pipeline ? (stage == GS_GFX_VERTEX ? &gfx.pipeline->vs
                                                                         : &gfx.pipeline->fs)
                                               : NULL;
    if (info && slot < info->num_uniform_buffers && info->uniform_sizes[slot] != data.len) {
        gfx_misuse("push_uniforms: the %s shader's uniform block %lld is %u bytes by std140, "
                   "and %lld were pushed", stage ? "fragment" : "vertex", (long long)slot,
                   info->uniform_sizes[slot], (long long)data.len);
        return;
    }
    GLuint *ubo = &gfx.ubos[stage][slot];
    if (!*ubo) glGenBuffers(1, ubo);
    glBindBuffer(GL_UNIFORM_BUFFER, *ubo);
    glBufferData(GL_UNIFORM_BUFFER, data.len, data.data, GL_DYNAMIC_DRAW);
    glBindBufferBase(GL_UNIFORM_BUFFER, (GLuint)(stage * 4 + slot), *ubo);
    gfx.uniforms_pushed[stage] |= 1u << slot;
}

/* gfx's rectangles are top down, GL's bottom up. */
void gs_gfx_viewport(float x, float y, float w, float h) {
    if (!gfx.pass) {
        gfx_misuse("viewport outside a render pass");
        return;
    }
    glViewport((GLint)x, (GLint)((float)gfx.target_h - y - h), (GLsizei)w, (GLsizei)h);
}

void gs_gfx_scissor(int64_t x, int64_t y, int64_t w, int64_t h) {
    if (!gfx.pass) {
        gfx_misuse("scissor outside a render pass");
        return;
    }
    if (w == 0) {
        x = y = 0;
        w = gfx.target_w;
        h = gfx.target_h;
    }
    glScissor((GLint)x, (GLint)(gfx.target_h - y - h), (GLsizei)(w < 0 ? 0 : w),
              (GLsizei)(h < 0 ? 0 : h));
}

static bool gfx_ready_to_draw(const char *what) {
    if (!gfx.pass) return gfx_misuse("%s outside a render pass", what);
    gfx_pipeline_slot *p = gfx.pipeline;
    if (!p) return gfx_misuse("%s with no pipeline bound", what);
    for (int slot = 0; slot < 2; slot++)
        if ((p->vbuf_mask & (1u << slot)) && !gfx.vbufs[slot].bound)
            return gfx_misuse("%s: the pipeline reads vertex buffer %d, which is not bound", what,
                              slot);
    const gfx_shader_info *stages[2] = { &p->vs, &p->fs };
    for (int st = 0; st < 2; st++) {
        for (int i = 0; i < stages[st]->num_samplers; i++)
            if (!(gfx.samplers_bound[st] & (1u << i)))
                return gfx_misuse("%s: the %s shader reads sampler %d, which no bind_texture "
                                  "gave it", what, st ? "fragment" : "vertex", i);
        for (int i = 0; i < stages[st]->num_uniform_buffers; i++)
            if (!(gfx.uniforms_pushed[st] & (1u << i)))
                return gfx_misuse("%s: the %s shader reads uniform block %d, which no "
                                  "push_uniforms gave it", what, st ? "fragment" : "vertex", i);
    }
    return true;
}

/* Points the pipeline's attributes at the bound vertex buffers, `first[slot]`
   elements in: WebGL 2 has no base vertex or base instance to do it. */
static void gfx_attributes(int64_t first_vertex, int64_t first_instance) {
    gfx_pipeline_slot *p = gfx.pipeline;
    uint32_t want = 0;
    for (int i = 0; i < p->nattrs; i++) {
        const gfx_attr *a = &p->attrs[i];
        int64_t first = a->slot ? first_instance : first_vertex;
        intptr_t off = (intptr_t)(gfx.vbufs[a->slot].offset + a->offset +
                                  first * (int64_t)p->stride[a->slot]);
        glBindBuffer(GL_ARRAY_BUFFER, gfx.vbufs[a->slot].buf);
        const GLint n = gfx_vertex_formats[a->format].n;
        const GLenum type = gfx_vertex_formats[a->format].type;
        const GLsizei stride = (GLsizei)p->stride[a->slot];
        if (gfx_vertex_formats[a->format].kind == 'i')
            glVertexAttribIPointer(a->location, n, type, stride, (const void *)off);
        else
            glVertexAttribPointer(a->location, n, type,
                                  gfx_vertex_formats[a->format].kind == 'n' ? GL_TRUE : GL_FALSE,
                                  stride, (const void *)off);
        glVertexAttribDivisor(a->location, a->slot ? 1 : 0);
        want |= 1u << a->location;
    }
    for (GLuint loc = 0; loc < 16; loc++) {
        bool on = (want >> loc) & 1, was = (gfx.enabled_attrs >> loc) & 1;
        if (on && !was) glEnableVertexAttribArray(loc);
        if (!on && was) glDisableVertexAttribArray(loc);
    }
    gfx.enabled_attrs = want;
}

static GLenum gfx_mode(int32_t primitive) {
    static const GLenum modes[] = { GL_TRIANGLES, GL_TRIANGLE_STRIP, GL_LINES, GL_LINE_STRIP,
                                    GL_POINTS };
    return modes[primitive];
}

void gs_gfx_draw(int64_t vertices, int64_t instances, int64_t first_vertex,
                 int64_t first_instance) {
    if (!gfx_ready_to_draw("draw")) return;
    if (vertices < 0 || instances < 0 || first_vertex < 0 || first_instance < 0) {
        gfx_misuse("draw: a negative count");
        return;
    }
    if (!vertices || !instances) return;
    gfx_attributes(0, first_instance);
    glDrawArraysInstanced(gfx_mode(gfx.pipeline->desc.primitive), (GLint)first_vertex,
                          (GLsizei)vertices, (GLsizei)instances);
}

void gs_gfx_draw_indexed(int64_t indices, int64_t instances, int64_t first_index,
                         int64_t vertex_offset, int64_t first_instance) {
    if (!gfx_ready_to_draw("draw_indexed")) return;
    if (!gfx.ibuf.bound) {
        gfx_misuse("draw_indexed with no index buffer bound");
        return;
    }
    if (indices < 0 || instances < 0 || first_index < 0 || first_instance < 0) {
        gfx_misuse("draw_indexed: a negative count");
        return;
    }
    if (!indices || !instances) return;
    gfx_attributes(vertex_offset, first_instance);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, gfx.ibuf.buf);
    glDrawElementsInstanced(gfx_mode(gfx.pipeline->desc.primitive), (GLsizei)indices,
                            gfx.ibuf.size == 2 ? GL_UNSIGNED_SHORT : GL_UNSIGNED_INT,
                            (const void *)(intptr_t)(gfx.ibuf.offset + first_index * gfx.ibuf.size),
                            (GLsizei)instances);
}

/* --- compute: none in WebGL 2 ---------------------------------------------- */

uint8_t gs_gfx_begin_compute(gs_gfx_buffer_slice rw_buffers, gs_gfx_texture_slice rw_textures) {
    (void)rw_buffers, (void)rw_textures;
    return gfx_unsupported("compute passes");
}

void gs_gfx_end_compute(void) {}

void gs_gfx_bind_compute_pipeline(gs_gfx_compute_pipeline p) { (void)p; }

void gs_gfx_dispatch(int64_t x, int64_t y, int64_t z) { (void)x, (void)y, (void)z; }
