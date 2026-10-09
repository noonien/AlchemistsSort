/* The music player: a few tracks playing at once, each decoded a little at
   a time (ogg.h), mixed with gains that glide (for crossfades and the
   volume slider, without clicks), each played through, rested, and played
   again from the top. music.goose drives it once a frame.

   Built with ALCH_STREAM_SDL (the native and web builds define it), it
   streams: it opens its own SDL audio stream beside the sound effects'
   and keeps a fifth of a second of the mix queued on it, so no track is
   ever held whole in memory. Without it (running from source, whose
   in-process compiler can't reach SDL), it decodes each track whole, a
   slice a frame, and plays it through the audio module's mixer. */

#ifndef ALCH_STREAM_H
#define ALCH_STREAM_H
#include "ogg.h"

#define ALCH_PLAYERS 4
#define ALCH_RATE 44100             /* the tracks' rate, and the stream's */

typedef struct {
    int on;
    int64_t dec;
    double gain, target, step;      /* its gain, where it glides to, and by how much a frame */
    int stop;                       /* stop once it has glided to silence */
    int64_t pause, rest;            /* frames of silence between plays, and left of this one */
#ifndef ALCH_STREAM_SDL
    float *pcm;                     /* the track, while it is decoded */
    int64_t filled;
    int loaded, voiced;
    audio_Sound_g5 sound;
    audio_Voice_g5 voice;
#endif
} alch_player;

static alch_player alch_players[ALCH_PLAYERS];
static double alch_volume = 0.0, alch_volume_to = 0.0;

static void alch_glide(alch_player *p, int64_t frames) {
    double d = p->target - p->gain, s = p->step * (double)frames;
    p->gain = d > s ? p->gain + s : d < -s ? p->gain - s : p->target;
}

#ifdef ALCH_STREAM_SDL

/* SDL3's, declared here rather than from its headers, which the generated C
   doesn't otherwise need. */
typedef struct SDL_AudioStream SDL_AudioStream;
typedef struct { int format; int channels; int freq; } alch_sdl_spec;
SDL_AudioStream *SDL_OpenAudioDeviceStream(uint32_t devid, const alch_sdl_spec *spec, void *callback, void *userdata);
_Bool SDL_ResumeAudioStreamDevice(SDL_AudioStream *stream);
_Bool SDL_PutAudioStreamData(SDL_AudioStream *stream, const void *buf, int len);
int SDL_GetAudioStreamQueued(SDL_AudioStream *stream);

#define ALCH_AHEAD (ALCH_RATE / 5)  /* frames kept queued */
#define ALCH_CHUNK 1024

static SDL_AudioStream *alch_out;
static float alch_mix[2 * ALCH_CHUNK], alch_track[2 * ALCH_CHUNK];

/* Opens the music's own output; the sound effects' must be open already. */
uint8_t alch_music_open(void) {
    if (alch_out) return 1;
    alch_sdl_spec spec = { 0x8120 /* 32-bit float */, 2, ALCH_RATE };
    alch_out = SDL_OpenAudioDeviceStream(0xFFFFFFFFu /* the default output */, &spec, NULL, NULL);
    if (!alch_out) return 0;
    SDL_ResumeAudioStreamDevice(alch_out);
    return 1;
}

static void alch_close(alch_player *p) {
    alch_dec_close(p->dec);
    p->on = 0;
}

/* The next n frames of player p into alch_track, rests and replays included. */
static void alch_next(alch_player *p, int64_t n) {
    int64_t at = 0;
    while (at < n) {
        if (p->rest > 0) {
            int64_t k = p->rest < n - at ? p->rest : n - at;
            memset(alch_track + 2 * at, 0, (size_t)(2 * k) * sizeof(float));
            p->rest -= k;
            at += k;
            continue;
        }
        sl_f32 out = { alch_track + 2 * at, 2 * (n - at) };
        int64_t got = alch_dec_read(p->dec, out);
        at += got;
        if (got == 0) {
            /* The end: a rest, then the top again. */
            alch_dec_rewind(p->dec);
            p->rest = p->pause > 0 ? p->pause : 1;
        }
    }
}

/* Mixes and queues what the output will want next. */
void alch_music_pump(double dt) {
    (void)dt;
    if (!alch_out) return;
    int64_t want = ALCH_AHEAD - SDL_GetAudioStreamQueued(alch_out) / 8;
    while (want > 0) {
        int64_t n = want < ALCH_CHUNK ? want : ALCH_CHUNK;
        memset(alch_mix, 0, sizeof(alch_mix));
        for (int k = 0; k < ALCH_PLAYERS; k++) {
            alch_player *p = &alch_players[k];
            if (!p->on) continue;
            alch_next(p, n);
            for (int64_t i = 0; i < n; i++) {
                alch_glide(p, 1);
                alch_mix[2 * i] += alch_track[2 * i] * (float)p->gain;
                alch_mix[2 * i + 1] += alch_track[2 * i + 1] * (float)p->gain;
            }
            if (p->stop && p->gain <= 0.0 && p->target <= 0.0) alch_close(p);
        }
        /* The volume glides over a twentieth of a second. */
        double vs = 20.0 / ALCH_RATE;
        for (int64_t i = 0; i < n; i++) {
            double d = alch_volume_to - alch_volume;
            alch_volume += d > vs ? vs : d < -vs ? -vs : d;
            alch_mix[2 * i] *= (float)alch_volume;
            alch_mix[2 * i + 1] *= (float)alch_volume;
        }
        SDL_PutAudioStreamData(alch_out, alch_mix, (int)(n * 8));
        want -= n;
    }
}

#else

uint8_t gs_audio_playing(audio_Voice_g5);
audio_Sound_g5 gs_audio_create_sound(sl_f32, int64_t, int64_t);
audio_Voice_g5 gs_audio_play(audio_Sound_g5, float, float, float, uint8_t);
uint8_t gs_audio_set_voice(audio_Voice_g5, float, float, float);
void gs_audio_stop(audio_Voice_g5);
uint8_t gs_audio_release_sound(audio_Sound_g5);

#define ALCH_SLICE (ALCH_RATE / 4)  /* frames decoded a frame, while a track loads */

uint8_t alch_music_open(void) { return 1; }

static void alch_close(alch_player *p) {
    if (p->voiced) gs_audio_stop(p->voice);
    if (p->loaded) gs_audio_release_sound(p->sound);
    free(p->pcm);
    p->pcm = NULL;
    alch_dec_close(p->dec);
    p->on = 0;
}

void alch_music_pump(double dt) {
    double vs = 20.0 * dt;
    double d = alch_volume_to - alch_volume;
    alch_volume += d > vs ? vs : d < -vs ? -vs : d;
    for (int k = 0; k < ALCH_PLAYERS; k++) {
        alch_player *p = &alch_players[k];
        if (!p->on) continue;
        if (!p->loaded) {
            int64_t frames = alch_dec_frames(p->dec);
            if (!p->pcm) p->pcm = (float *)malloc((size_t)(2 * frames) * sizeof(float));
            if (!p->pcm) { alch_close(p); continue; }
            int64_t n = frames - p->filled < ALCH_SLICE ? frames - p->filled : ALCH_SLICE;
            sl_f32 out = { p->pcm + 2 * p->filled, 2 * n };
            int64_t got = alch_dec_read(p->dec, out);
            p->filled += got;
            if (got > 0 && p->filled < frames) continue;
            sl_f32 all = { p->pcm, 2 * p->filled };
            p->sound = gs_audio_create_sound(all, ALCH_RATE, 2);
            free(p->pcm);
            p->pcm = NULL;
            if (!p->sound.id_g) { alch_close(p); continue; }
            p->loaded = 1;
        }
        alch_glide(p, (int64_t)(dt * ALCH_RATE));
        if (p->stop && p->gain <= 0.0 && p->target <= 0.0) { alch_close(p); continue; }
        if (p->voiced && !gs_audio_playing(p->voice)) {
            /* The end: a rest, then the top again. */
            p->voiced = 0;
            p->rest = p->pause;
        }
        if (!p->voiced) {
            p->rest -= (int64_t)(dt * ALCH_RATE);
            if (p->rest > 0) continue;
            p->voice = gs_audio_play(p->sound, 0.0f, 0.0f, 1.0f, 0);
            p->voiced = 1;
        }
        gs_audio_set_voice(p->voice, (float)(p->gain * alch_volume), 0.0f, 1.0f);
    }
}

#endif

/* Starts the track in `data` (copied) at silence, to rest `pause` seconds
   between plays. Returns its player, or -1. */
int64_t alch_music_start(sl_u8 data, double pause) {
    int k = 0;
    while (k < ALCH_PLAYERS && alch_players[k].on) k++;
    if (k == ALCH_PLAYERS) return -1;
    int64_t dec = alch_dec_open(data);
    if (dec < 0) return -1;
    if (alch_dec_rate(dec) != ALCH_RATE) { alch_dec_close(dec); return -1; }
    alch_players[k] = (alch_player){ 0 };
    alch_player *p = &alch_players[k];
    p->on = 1;
    p->dec = dec;
    p->pause = (int64_t)(pause * ALCH_RATE);
    return k;
}

/* Glides player k's gain to `target` over `seconds`; with `stop`, it stops
   once silent. */
void alch_music_fade(int64_t k, double target, double seconds, uint8_t stop) {
    if (k < 0 || k >= ALCH_PLAYERS || !alch_players[k].on) return;
    alch_player *p = &alch_players[k];
    p->target = target;
    double d = target > p->gain ? target - p->gain : p->gain - target;
    p->step = d / ((seconds > 0.01 ? seconds : 0.01) * ALCH_RATE);
    if (p->step <= 0.0) p->step = 1.0 / ALCH_RATE;
    p->stop = stop;
}

/* The music's level, gliding there: 0 is silence, 1 the loudest. */
void alch_music_volume(double v) { alch_volume_to = v < 0.0 ? 0.0 : v > 1.0 ? 1.0 : v; }

#endif
