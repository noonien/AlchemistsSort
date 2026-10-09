/* Ogg Vorbis, for the music (assets/music/*.ogg): Sean Barrett's stb_vorbis
   (public domain or MIT, see the end of stb_vorbis.c, which is kept here
   unchanged) and a few calls Goose makes of it, to decode a track a little
   at a time rather than all at once.

   The C that Goose writes includes this file (`--include src/c/ogg.h`; the
   game includes it through stream.h). It comes after Goose's own type
   declarations, so it can use the program's types: a slice is sl_u8 or
   sl_f32. */

#ifndef ALCH_OGG_H
#define ALCH_OGG_H

#define STB_VORBIS_NO_PUSHDATA_API
#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_MAX_CHANNELS 2
#include "stb_vorbis.c"

#define ALCH_DECODERS 8

/* A track being decoded, from its own copy of the file's bytes. */
typedef struct {
    stb_vorbis *v;
    uint8_t *bytes;
    int channels, rate;
    int64_t frames;
} alch_decoder;

static alch_decoder alch_decoders[ALCH_DECODERS];

static alch_decoder *alch_dec(int64_t d) {
    return d >= 0 && d < ALCH_DECODERS && alch_decoders[d].v ? &alch_decoders[d] : NULL;
}

/* Starts decoding the Ogg Vorbis file in `data` (copied: the caller's bytes
   may go). Returns its decoder, or -1 if it isn't one or none is free. */
int64_t alch_dec_open(sl_u8 data) {
    int64_t d = 0;
    while (d < ALCH_DECODERS && alch_decoders[d].v) d++;
    if (d == ALCH_DECODERS || data.len <= 0 || data.len > 0x7fffffff) return -1;
    uint8_t *copy = (uint8_t *)malloc((size_t)data.len);
    if (!copy) return -1;
    memcpy(copy, data.data, (size_t)data.len);
    int error = 0;
    stb_vorbis *v = stb_vorbis_open_memory(copy, (int)data.len, &error, NULL);
    if (!v) { free(copy); return -1; }
    stb_vorbis_info i = stb_vorbis_get_info(v);
    alch_decoders[d] = (alch_decoder){ v, copy, i.channels, (int)i.sample_rate,
                                      (int64_t)stb_vorbis_stream_length_in_samples(v) };
    return d;
}

int64_t alch_dec_rate(int64_t d) { alch_decoder *a = alch_dec(d); return a ? a->rate : 0; }
int64_t alch_dec_channels(int64_t d) { alch_decoder *a = alch_dec(d); return a ? a->channels : 0; }
int64_t alch_dec_frames(int64_t d) { alch_decoder *a = alch_dec(d); return a ? a->frames : 0; }

/* Decodes the next frames into `out` as left and right in turn (a mono
   track on both), as many as fit; returns how many, 0 at the end. */
int64_t alch_dec_read(int64_t d, sl_f32 out) {
    alch_decoder *a = alch_dec(d);
    if (!a) return 0;
    int64_t want = out.len / 2, at = 0;
    while (at < want) {
        int64_t n = want - at;
        if (n > 4096) n = 4096;
        int got = stb_vorbis_get_samples_float_interleaved(a->v, 2, out.data + 2 * at, (int)(2 * n));
        if (got <= 0) break;
        at += got;
    }
    return at;
}

void alch_dec_rewind(int64_t d) {
    alch_decoder *a = alch_dec(d);
    if (a) stb_vorbis_seek_start(a->v);
}

void alch_dec_close(int64_t d) {
    alch_decoder *a = alch_dec(d);
    if (!a) return;
    stb_vorbis_close(a->v);
    free(a->bytes);
    a->v = NULL;
    a->bytes = NULL;
}

#endif
