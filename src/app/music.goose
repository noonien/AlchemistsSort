// The background music: a loop for each room (see tunes.goose), made when
// first needed and kept playing across levels and screens. A change of room
// crossfades to the new room's loop once it is ready; the music toggle fades
// it out or in. At most two loops are kept.

import std;
import math;
import os;
import audio;
import .sfx;
import .tunes;

let MUSIC_VOLUME: f64 = 0.5;    // under the sound effects
let CROSSFADE: f64 = 3.0;       // seconds
let MUSIC_SLICE: f64 = 0.003;   // seconds of synthesis a frame

struct Loop { room: i64 = -1, sound: audio::Sound, }
struct Track { room: i64 = -1, voice: audio::Voice, gain: f64 = 0.0 }

var music_on = true;
var music_ready = false;        // set when audio is on and music may be made
var music_loops: Loop[2];
var music_now = Track { .. };       // what is playing, rising to full
var music_old = Track { .. };        // what it replaced, fading away
var music_making = false;
var tune_job: TuneJob;
var tune_notes: Note[>..];
var tune_pcm: f32[>..];

fn init_music() { music_ready = sound_ready; }

fn loop_slot(room: i64) -> i64 {
    for l, i in music_loops { if l.room == room { return i; } }
    -1
}

// A slot for a new loop: an empty one, else one nothing is playing.
fn free_slot() -> i64 {
    for l, i in music_loops { if l.room < 0 { return i; } }
    for l, i in music_loops {
        if l.room != music_now.room && l.room != music_old.room {
            audio::release_sound(l.sound);
            music_loops[i].room = -1;
            return i;
        }
    }
    -1
}

fn stop_track(t: Track&) {
    if t.room >= 0 { audio::stop(t.voice); }
    t.room = -1;
    t.gain = 0.0;
}

fn fade_track(t: Track&, target: f64, dt: f64) {
    if t.room < 0 { return; }
    let step = dt / CROSSFADE;
    t.gain = if t.gain < target { min(target, t.gain + step) } else { max(target, t.gain - step) };
    // Equal power, so the crossfade doesn't dip in the middle.
    audio::set_voice(t.voice, (sin(t.gain * PI * 0.5) * MUSIC_VOLUME) as f32, 0.0, 1.0);
}

// Once a frame: plays `room`'s loop, making it first if need be.
fn step_music(room: i64, dt: f64) {
    if !music_ready { return; }
    let on = music_on;
    if on && music_now.room != room {
        let slot = loop_slot(room);
        if slot >= 0 {
            stop_track(music_old);
            music_old = music_now;
            music_now = Track { room: room, voice: audio::play(music_loops[slot].sound, 0.0, 0.0, 1.0, true), gain: 0.0 };
        } else if !music_making || tune_job.room != room {
            if free_slot() >= 0 {
                tune_job = tune_begin(room, 0, tune_notes, tune_pcm);
                music_making = true;
            }
        }
    }
    if music_making && on {
        if tune_step(tune_job, tune_notes, tune_pcm, MUSIC_SLICE) {
            music_making = false;
            let slot = free_slot();
            if slot >= 0 {
                music_loops[slot] = Loop { room: tune_job.room, sound: audio::create_sound(tune_pcm, MUSIC_RATE, 1) };
                if music_loops[slot].sound.id == 0 { music_loops[slot].room = -1; music_ready = false; }
            }
            tune_pcm.clear();
            tune_notes.clear();
        }
    }
    fade_track(music_now, if on { 1.0 } else { 0.0 }, dt);
    fade_track(music_old, 0.0, dt);
    if music_old.room >= 0 && music_old.gain <= 0.0 { stop_track(music_old); }
    if !on && music_now.room >= 0 && music_now.gain <= 0.0 { stop_track(music_now); }
}

// Renders every room's loop to <dir>/<room>.wav, for listening.
fn export_music(dir: const u8[:]) -> bool {
    make_dir(dir);
    for room in MUSIC_ROOMS {
        let t0 = clock();
        var job = tune_begin(room, 0, tune_notes, tune_pcm);
        while !tune_step(job, tune_notes, tune_pcm, 1.0) {}
        let took = clock() - t0;
        let path = str(dir, "/", tune_name(room), ".wav");
        if !write_wav(path, tune_pcm) { write_stderr(str("could not write ", path, "\n")); return false; }
        print(path, ": ", tune_pcm.len / MUSIC_RATE, " s, ", tune_notes.len, " notes, made in ", round(took * 1000.0), " ms");
    }
    true
}
