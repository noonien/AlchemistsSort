// The music's tracks: one for each room and one for the title screen,
// generated for the game and kept as Ogg Vorbis in assets/music (prepare.py
// there makes them from the originals). What plays where, how the volume
// slider maps to a gain, and the decoder's calls (src/c/ogg.h), which read
// a track a little at a time. No audio here, so the tests can read the
// tracks: music.goose plays them.

import std;
import math;

let MUSIC_ROOMS = 6;
let TITLE_TRACK = MUSIC_ROOMS;  // the title screen's, and the map's
let MUSIC_TRACKS = MUSIC_ROOMS + 1;
let TRACK_RATE = 44100;
let MUSIC_DEFAULT = 30;         // the volume slider's first place, percent

extern "alch_dec_open" fn dec_open(data: const u8[:]) -> i64;
extern "alch_dec_rate" fn dec_rate(d: i64) -> i64;
extern "alch_dec_channels" fn dec_channels(d: i64) -> i64;
extern "alch_dec_frames" fn dec_frames(d: i64) -> i64;
extern "alch_dec_read" fn dec_read(d: i64, out: f32[:]) -> i64;
extern "alch_dec_close" fn dec_close(d: i64);

fn track_name(t: i64) -> const u8[:] {
    match t { 1 => "frost_cellar", 2 => "glassworks", 3 => "observatory", 4 => "greenhouse",
              5 => "athanor", 0 => "apothecary", _ => "title_screen" }
}

// The room whose music goes with level n: its chapter's, and in the Great
// Work a different room every 15 levels.
fn music_room(level: i64, chapter_theme: i64, chapter_first: i64) -> i64 {
    if chapter_theme < MUSIC_ROOMS { return chapter_theme; }
    (level - chapter_first) / 15 % MUSIC_ROOMS
}

// The music's gain at `percent` on the slider, even in loudness rather than
// in amplitude: 33 dB a decade, so that, as loudness halves about every
// 10 dB, half way along sounds about half as loud. 100% is the tracks at
// their full level, which sits under the sound effects; 30% is 17 dB below.
fn music_gain(percent: i64) -> f64 {
    if percent <= 0 { return 0.0; }
    pow(min(percent, 100) / 100.0, 1.66)
}
