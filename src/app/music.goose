// The background music: a track for each room, and the title theme on the
// title screen and the map (tracks.goose). A track plays through, rests a
// few seconds and plays again from the top. A change of room or screen
// crossfades to the new track; the volume slider in Settings sets the level,
// and at 0 the music stops. The player (src/c/stream.h) decodes and mixes a
// little ahead each frame, so no track is ever held whole.

import std;
import math;
import os;
import .sfx;
import .tracks;

let CROSSFADE: f64 = 3.0;       // seconds
let REST: f64 = 3.0;            // seconds of silence before a track plays again

extern "alch_music_open" fn music_open() -> bool;
extern "alch_music_start" fn music_start(data: const u8[:], rest: f64) -> i64;
extern "alch_music_fade" fn music_fade(player: i64, target: f64, seconds: f64, stop: bool);
extern "alch_music_volume" fn music_volume(gain: f64);
extern "alch_music_pump" fn music_pump(dt: f64);

var music_ready = false;        // set when audio is on and the player is open
var music_level = MUSIC_DEFAULT;    // the slider, percent
var music_dir: u8[>..];
var music_now = -1;             // the track playing, or -1
var music_player = -1;          // its player
var music_bytes: u8[>..];       // a track's file, read to start it

// Opens the player; the tracks are read from `dir` as they are wanted.
fn init_music(dir: const u8[:]) {
    music_dir.clear();
    music_dir.append(dir);
    music_ready = sound_ready && music_open();
}

// Once a frame: plays `track`, crossfading from what played before.
fn step_music(track: i64, dt: f64) {
    if !music_ready { return; }
    let want = if music_level > 0 { track } else { -1 };
    if want != music_now {
        if music_player >= 0 { music_fade(music_player, 0.0, CROSSFADE, true); }
        music_player = -1;
        music_now = want;
        if want >= 0 {
            music_bytes.clear();
            if read_file(str(music_dir, "/", track_name(want), ".ogg"), music_bytes) {
                music_player = music_start(music_bytes, REST);
                // Every player busy fading: try again next frame.
                if music_player < 0 { music_now = -2; }
                else { music_fade(music_player, 1.0, CROSSFADE, false); }
            }
        }
    }
    music_volume(music_gain(music_level));
    music_pump(dt);
}

// Writes every track, decoded, to <dir>/<track>.wav, for listening.
fn export_music(dir: const u8[:], from: const u8[:]) -> bool {
    make_dir(dir);
    for t in MUSIC_TRACKS {
        let t0 = clock();
        var bytes: u8[>..] = [];
        let src = str(from, "/", track_name(t), ".ogg");
        if !read_file(src, bytes) { write_stderr(str("could not read ", src, "\n")); return false; }
        let d = dec_open(bytes);
        if d < 0 { write_stderr(str("not Ogg Vorbis: ", src, "\n")); return false; }
        var pcm: f32[>..] = [];
        pcm.resize(2 * dec_frames(d), 0.0);
        let got = dec_read(d, pcm);
        dec_close(d);
        pcm.resize(2 * got);
        let path = str(dir, "/", track_name(t), ".wav");
        if !write_wav(path, pcm) { write_stderr(str("could not write ", path, "\n")); return false; }
        print(path, ": ", round(got * 10.0 / TRACK_RATE) / 10.0, " s, decoded in ", round((clock() - t0) * 1000.0), " ms");
    }
    true
}

fn put_u32(out: u8[>..]&, x: i64) { for k in 4 { out.push(((x >> (8 * k)) & 255) as! u8); } }
fn put_u16(out: u8[>..]&, x: i64) { for k in 2 { out.push(((x >> (8 * k)) & 255) as! u8); } }

// Writes interleaved stereo pcm as a 16-bit WAV.
fn write_wav(path: const u8[:], pcm: const f32[:]) -> bool {
    var out: u8[>..] = [];
    out.append("RIFF");
    put_u32(out, 36 + pcm.len * 2);
    out.append("WAVEfmt ");
    put_u32(out, 16);
    put_u16(out, 1);                // PCM
    put_u16(out, 2);                // stereo
    put_u32(out, TRACK_RATE);
    put_u32(out, TRACK_RATE * 4);
    put_u16(out, 4);
    put_u16(out, 16);
    out.append("data");
    put_u32(out, pcm.len * 2);
    for v in pcm { put_u16(out, (round(clamp(v as f64, -1.0, 1.0) * 32767.0) as! i64) & 65535); }
    write_file(path, out)
}
