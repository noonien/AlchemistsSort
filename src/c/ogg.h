/* Ogg Vorbis, for the instruments' recorded notes (samples/*.ogg): Sean
   Barrett's stb_vorbis (public domain or MIT, see the end of stb_vorbis.c,
   which is kept here unchanged) and the two calls bank.goose makes of it.

   The C that Goose writes includes this file: every build passes
   `--include src/c/ogg.h` to goose, as does running from source. It comes
   after Goose's own type declarations, so it can use the program's types:
   a slice is sl_u8 or sl_f32, and bank.goose's OggInfo is OggInfo_g. */

#define STB_VORBIS_NO_PUSHDATA_API
#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_MAX_CHANNELS 2
#include "stb_vorbis.c"

/* The shape of the stream in `data`: its channels, rate and length in
   frames. False if it isn't Ogg Vorbis. */
uint8_t alch_ogg_info(sl_u8 data, OggInfo_g *info) {
    int error = 0;
    stb_vorbis *v = stb_vorbis_open_memory(data.data, (int)data.len, &error, NULL);
    if (!v) return 0;
    stb_vorbis_info i = stb_vorbis_get_info(v);
    info->channels_g = i.channels;
    info->rate_g = i.sample_rate;
    info->frames_g = stb_vorbis_stream_length_in_samples(v);
    stb_vorbis_close(v);
    return 1;
}

/* Decodes the mono stream in `data` into `out`, as much as fits; returns
   the frames written, or -1 if it isn't mono Ogg Vorbis. */
int64_t alch_ogg_decode(sl_u8 data, sl_f32 out) {
    int error = 0;
    stb_vorbis *v = stb_vorbis_open_memory(data.data, (int)data.len, &error, NULL);
    if (!v) return -1;
    if (stb_vorbis_get_info(v).channels != 1) { stb_vorbis_close(v); return -1; }
    int64_t at = 0;
    while (at < out.len) {
        int64_t want = out.len - at;
        int n = stb_vorbis_get_samples_float_interleaved(v, 1, out.data + at, (int)(want > 65536 ? 65536 : want));
        if (n <= 0) break;
        at += n;
    }
    stb_vorbis_close(v);
    return at;
}
