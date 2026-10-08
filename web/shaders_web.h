/* The table web/shaders.py generates: every shader the program embeds, in
   GLSL ES 3.00, found by the hash gfx_web.c takes of the blob. */

#ifndef GS_SHADERS_WEB_H
#define GS_SHADERS_WEB_H

#include <stdint.h>

typedef struct {
    uint64_t hash;              /* FNV-1a of the whole blob */
    uint32_t size;              /* of the blob */
    int stage;                  /* 0 vertex, 1 fragment */
    const char *ubos[4];        /* uniform block names, by binding */
    const char *samplers[4];    /* sampler names, by binding */
    const char *glsl;
} gs_web_shader;

extern const gs_web_shader gs_web_shaders[];
extern const int gs_web_shader_count;

#endif
