// Sound effects, synthesized at start-up: no audio files. Each is a few
// sine partials or a little filtered noise with an envelope.

import std;
import math;
import os;
import audio;

enum Sfx {
    Select, Deselect, Pour, Denied, Complete, Win, Pop, Ice, Reveal, Tool, Lose, Bell, Swish,
    Sizzle, Crack, Chime, Whoosh, Rustle, Chirp, Gong,      // the forces
    Jingle, Clunk, Creak, Drape,                            // keys, locks, doors and curtains
    Honk,                                                   // the title screen's goose
}

let ALL_SFX: const Sfx[25] = [Sfx.Select, Sfx.Deselect, Sfx.Pour, Sfx.Denied, Sfx.Complete, Sfx.Win,
                              Sfx.Pop, Sfx.Ice, Sfx.Reveal, Sfx.Tool, Sfx.Lose, Sfx.Bell, Sfx.Swish,
                              Sfx.Sizzle, Sfx.Crack, Sfx.Chime, Sfx.Whoosh, Sfx.Rustle, Sfx.Chirp, Sfx.Gong,
                              Sfx.Jingle, Sfx.Clunk, Sfx.Creak, Sfx.Drape, Sfx.Honk];

fn sfx_index(s: Sfx) -> i64 {
    match s {
        Select => 0, Deselect => 1, Pour => 2, Denied => 3, Complete => 4, Win => 5, Pop => 6,
        Ice => 7, Reveal => 8, Tool => 9, Lose => 10, Bell => 11, Swish => 12, Sizzle => 13, Crack => 14,
        Chime => 15, Whoosh => 16, Rustle => 17, Chirp => 18, Gong => 19, Jingle => 20, Clunk => 21,
        Creak => 22, Drape => 23, Honk => 24,
    }
}

let RATE = 44100;

var sounds: audio::Sound[25];
var sound_ready = false;
var sound_on = true;

fn tone(pcm: f32[>..]&, at: f64, freq: f64, length: f64, volume: f64, decay: f64) {
    let start = (at * RATE) as! i64;
    let n = (length * RATE) as! i64;
    while pcm.len < start + n { pcm.push(0.0); }
    for i in n {
        let t = i as f64 / RATE;
        let attack = min(1.0, t * 400.0);
        let env = attack * exp(-t * decay);
        let v = sin(TAU * freq * t) * 0.8 + sin(TAU * freq * 2.0 * t) * 0.15 + sin(TAU * freq * 3.01 * t) * 0.05;
        pcm[start + i] = pcm[start + i] + (v * env * volume) as f32;
    }
}

fn noise_burst(pcm: f32[>..]&, at: f64, length: f64, volume: f64, decay: f64, smooth: f64, seed: u64) {
    var r = rng { seed };
    let start = (at * RATE) as! i64;
    let n = (length * RATE) as! i64;
    while pcm.len < start + n { pcm.push(0.0); }
    var low = 0.0;
    for i in n {
        let t = i as f64 / RATE;
        let white = r.rand_flt() * 2.0 - 1.0;
        low = low + (white - low) * smooth;
        let env = min(1.0, t * 300.0) * exp(-t * decay);
        pcm[start + i] = pcm[start + i] + (low * env * volume) as f32;
    }
}

// Liquid: bubbles of rising pitch over a soft wash.
fn pour_sound(pcm: f32[>..]&) {
    noise_burst(pcm, 0.0, 0.55, 0.25, 4.0, 0.08, 7);
    var r = rng { 99 };
    var at = 0.02;
    while at < 0.45 {
        let f = 300.0 + r.rand_flt() * 500.0 + at * 600.0;
        let start = (at * RATE) as! i64;
        let n = (0.05 * RATE) as! i64;
        while pcm.len < start + n { pcm.push(0.0); }
        for i in n {
            let t = i as f64 / RATE;
            let sweep = f * (1.0 + t * 8.0);
            let env = sin(PI * t / 0.05);
            pcm[start + i] = pcm[start + i] + (sin(TAU * sweep * t) * env * 0.12) as f32;
        }
        at += 0.03 + r.rand_flt() * 0.04;
    }
}

fn make(id: Sfx, pcm: f32[>..]&) {
    // Keep the peak under 0.9.
    var peak = 0.0;
    for v in pcm { peak = max(peak, abs(v as f64)); }
    if peak > 0.9 { for &v in pcm { v = (v * 0.9 / peak) as f32; } }
    sounds[sfx_index(id)] = audio::create_sound(pcm, RATE, 1);
}

fn init_sounds() {
    if !audio::available() || !audio::open(RATE) {
        write_stderr(str("alchemists-sort: no sound (", audio::error(), ")\n"));
        return;
    }
    sound_ready = true;
    assert(ALL_SFX.len == sounds.len);
    for id, k in ALL_SFX {
        assert(sfx_index(id) == k);     // the list is in index order, every sound once
        var pcm: f32[>..] = [];
        match id {
            Select => tone(pcm, 0.0, 1320.0, 0.12, 0.25, 30.0),
            Deselect => tone(pcm, 0.0, 990.0, 0.1, 0.18, 35.0),
            Pour => pour_sound(pcm),
            Denied => {
                tone(pcm, 0.0, 180.0, 0.18, 0.35, 18.0);
                tone(pcm, 0.05, 150.0, 0.18, 0.3, 18.0);
            },
            Complete => {
                tone(pcm, 0.0, 880.0, 0.6, 0.25, 6.0);
                tone(pcm, 0.08, 1318.5, 0.7, 0.22, 5.0);
                tone(pcm, 0.16, 1760.0, 0.8, 0.18, 4.0);
            },
            Win => {
                // A shimmer over the chord of the level's colors.
                let notes: f64[6] = [1046.5, 1318.5, 1567.98, 2093.0, 2637.0, 3136.0];
                for f, i in notes { tone(pcm, i * 0.05, f, 1.2, 0.07, 3.0); }
                noise_burst(pcm, 0.0, 1.0, 0.08, 3.0, 0.6, 31);
            },
            Pop => {
                noise_burst(pcm, 0.0, 0.08, 0.6, 60.0, 0.5, 3);
                tone(pcm, 0.0, 520.0, 0.12, 0.3, 40.0);
            },
            Ice => {
                noise_burst(pcm, 0.0, 0.35, 0.4, 12.0, 0.9, 11);
                tone(pcm, 0.0, 2400.0, 0.3, 0.06, 15.0);
                tone(pcm, 0.07, 3100.0, 0.25, 0.05, 15.0);
            },
            Reveal => {
                noise_burst(pcm, 0.0, 0.5, 0.35, 5.0, 0.04, 21);
                tone(pcm, 0.1, 660.0, 0.5, 0.12, 6.0);
                tone(pcm, 0.18, 990.0, 0.5, 0.1, 6.0);
            },
            Tool => tone(pcm, 0.0, 740.0, 0.15, 0.2, 25.0),
            Lose => {
                tone(pcm, 0.0, 392.0, 0.5, 0.2, 5.0);
                tone(pcm, 0.18, 311.1, 0.7, 0.2, 4.0);
            },
            Bell => bell(pcm, NOTE_BASE),
            Swish => {
                // Ink: a soft swell of low noise.
                let n = (0.45 * RATE) as! i64;
                var r = rng { 41 };
                var low = 0.0;
                for i in n {
                    let t = i as f64 / RATE;
                    low = low + (r.rand_flt() * 2.0 - 1.0 - low) * 0.03;
                    pcm.push((low * sin(PI * t / 0.45) * 0.5) as f32);
                }
            },
            Sizzle => {
                // Heat: hissing high noise, crackling.
                noise_burst(pcm, 0.0, 0.5, 0.3, 5.0, 0.85, 51);
                var r = rng { 52 };
                for k in 7 { noise_burst(pcm, r.rand_flt() * 0.35, 0.02, 0.35, 120.0, 0.9, (60 + k) as u64); }
            },
            Crack => {
                // Ice or wax giving way: a sharp snap and a short splinter.
                noise_burst(pcm, 0.0, 0.06, 0.8, 70.0, 0.95, 71);
                noise_burst(pcm, 0.03, 0.15, 0.35, 30.0, 0.6, 72);
                tone(pcm, 0.0, 1900.0, 0.08, 0.1, 50.0);
            },
            Chime => {
                // Light: two glassy notes, a fifth apart.
                tone(pcm, 0.0, 1567.98, 0.9, 0.18, 4.5);
                tone(pcm, 0.06, 2349.3, 0.9, 0.14, 4.0);
                tone(pcm, 0.12, 3136.0, 0.7, 0.06, 5.0);
            },
            Whoosh => {
                // A flask turning over: noise swelling and falling, rising in pitch.
                let n = (0.6 * RATE) as! i64;
                var r = rng { 81 };
                var low = 0.0;
                for i in n {
                    let t = i as f64 / RATE;
                    let k = 0.02 + 0.12 * t / 0.6;
                    low = low + (r.rand_flt() * 2.0 - 1.0 - low) * k;
                    pcm.push((low * sin(PI * t / 0.6) * 0.9) as f32);
                }
            },
            Rustle => {
                // Leaves: soft bursts of noise.
                var r = rng { 91 };
                for k in 9 { noise_burst(pcm, k * 0.045 + r.rand_flt() * 0.02, 0.06, 0.22, 40.0, 0.35, (92 + k) as u64); }
            },
            Chirp => {
                // The salamander: a quick rising squeak, twice.
                for k in 2 {
                    let start = (k * 0.09 * RATE) as! i64;
                    let n = (0.06 * RATE) as! i64;
                    while pcm.len < start + n { pcm.push(0.0); }
                    for i in n {
                        let t = i as f64 / RATE;
                        let f = 1800.0 + 2600.0 * t / 0.06;
                        pcm[start + i] = pcm[start + i] + (sin(TAU * f * t) * sin(PI * t / 0.06) * 0.22) as f32;
                    }
                }
            },
            Gong => {
                // The catalyst: a low bronze ring with inharmonic partials.
                let n = (2.2 * RATE) as! i64;
                let partials: f64[5] = [1.0, 1.48, 2.03, 2.74, 3.6];
                let amps: f64[5] = [0.5, 0.3, 0.2, 0.12, 0.08];
                for i in n {
                    let t = i as f64 / RATE;
                    var v = 0.0;
                    for k in 5 { v += sin(TAU * 110.0 * partials[k] * t) * amps[k] * exp(-t * (1.6 + k * 0.9)); }
                    pcm.push((v * min(1.0, t * 200.0) * 0.6) as f32);
                }
            },
            Jingle => {
                // A key coming free: small bright pings of metal, inharmonic,
                // tumbling over one another.
                let pings: f64[4] = [2637.0, 3520.0, 2960.0, 3951.0];
                for f, k in pings {
                    let at = k * 0.055;
                    let start = (at * RATE) as! i64;
                    let n = (0.35 * RATE) as! i64;
                    while pcm.len < start + n { pcm.push(0.0); }
                    for i in n {
                        let t = i as f64 / RATE;
                        let v = sin(TAU * f * t) * 0.6 + sin(TAU * f * 2.76 * t) * 0.25 * exp(-t * 30.0);
                        pcm[start + i] = pcm[start + i] + (v * min(1.0, t * 800.0) * exp(-t * 14.0) * 0.16) as f32;
                    }
                }
            },
            Clunk => {
                // A lock giving: a click, then a low wooden knock.
                noise_burst(pcm, 0.0, 0.03, 0.6, 120.0, 0.9, 111);
                tone(pcm, 0.0, 2200.0, 0.04, 0.12, 90.0);
                noise_burst(pcm, 0.045, 0.18, 0.55, 28.0, 0.12, 112);
                tone(pcm, 0.045, 110.0, 0.22, 0.45, 22.0);
                tone(pcm, 0.05, 185.0, 0.15, 0.2, 30.0);
            },
            Creak => {
                // Old hinges: a rasp of quick pulses whose pitch wanders down.
                let n = (0.6 * RATE) as! i64;
                var r = rng { 121 };
                var phase = 0.0;
                var low = 0.0;
                for i in n {
                    let t = i as f64 / RATE;
                    let f = 95.0 + 40.0 * sin(t * 7.0) - 30.0 * t;
                    phase += f / RATE;
                    let pulse = exp(-(phase - floor(phase)) * 9.0);
                    low = low + (r.rand_flt() * 2.0 - 1.0 - low) * 0.3;
                    let tone_v = sin(TAU * phase * 6.0) * 0.5 + low * 0.5;
                    pcm.push((pulse * tone_v * sin(PI * t / 0.6) * 0.5) as f32);
                }
            },
            Drape => {
                // Velvet drawn aside: a soft rising swish of cloth and the rings on the rod.
                let n = (0.5 * RATE) as! i64;
                var r = rng { 131 };
                var low = 0.0;
                for i in n {
                    let t = i as f64 / RATE;
                    low = low + (r.rand_flt() * 2.0 - 1.0 - low) * (0.05 + 0.15 * t / 0.5);
                    pcm.push((low * sin(PI * t / 0.5) * 0.7) as f32);
                }
                for k in 4 { tone(pcm, 0.05 + k * 0.07, 1900.0 + k * 140.0, 0.12, 0.035, 35.0); }
            },
            Honk => honk(pcm),
        }
        make(id, pcm);
    }
}

// The goose: a reedy, nasal call whose pitch leaps up and sags, its
// harmonics lifted round two formants, a rasp in it, and a breath before.
fn honk(pcm: f32[>..]&) {
    let length = 0.3;
    let n = (length * RATE) as! i64;
    var r = rng { 141 };
    var phase = 0.0;
    var low = 0.0;
    var peak = 0.0;
    for i in n {
        let t = i as f64 / RATE;
        let f = (360.0 + 130.0 * sin(PI * clamp(t / length * 1.2, 0.0, 1.0))) * (1.0 + 0.025 * sin(TAU * 29.0 * t));
        phase += f / RATE;
        var v = 0.0;
        for k in 1..11 {
            let fk = f * k;
            let x1 = (fk - 950.0) / 380.0;
            let x2 = (fk - 2300.0) / 550.0;
            let a = (0.25 + exp(-x1 * x1) + 0.7 * exp(-x2 * x2)) / pow(k as f64, 0.7);
            v += sin(TAU * phase * k) * a;
        }
        let env = min(1.0, t / 0.02) * clamp((length - t) / 0.08, 0.0, 1.0) * (0.82 + 0.18 * sin(TAU * 31.0 * t));
        low = low + (r.rand_flt() * 2.0 - 1.0 - low) * 0.25;
        let s = v * env + low * exp(-t * 40.0) * 0.6;
        peak = max(peak, abs(s));
        pcm.push(s as f32);
    }
    for &v in pcm { v = (v * 0.55 / max(peak, 1e-6)) as f32; }
}

fn play(id: Sfx) {
    if !sound_ready || !sound_on { return; }
    audio::play(sounds[sfx_index(id)], 0.8);
}

fn play_pitched(id: Sfx, pitch: f64, volume: f64) {
    if !sound_ready || !sound_on { return; }
    audio::play(sounds[sfx_index(id)], clamp(volume, 0.0, 1.0) as f32, 0.0, clamp(pitch, 0.125, 8.0) as f32);
}

// --- each color is a note ---------------------------------------------------------------
//
// The colors climb a major pentatonic scale from C4, so any of them sound
// well together: a completed flask rings its color's note, and the win plays
// the chord of the level's colors.

let NOTE_BASE: f64 = 261.63;
let PENTATONIC: const i64[17] = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26, 28, 31, 33, 36, 38];

// A glassy bell: a few partials, the higher ones dying first.
fn bell(pcm: f32[>..]&, freq: f64) {
    let n = (1.8 * RATE) as! i64;
    let partials: f64[4] = [1.0, 2.0, 3.01, 4.17];
    let amps: f64[4] = [0.55, 0.22, 0.1, 0.06];
    let decays: f64[4] = [2.2, 3.5, 5.0, 7.0];
    for i in n {
        let t = i as f64 / RATE;
        var v = 0.0;
        for k in 4 { v += sin(TAU * freq * partials[k] * t) * amps[k] * exp(-t * decays[k]); }
        pcm.push((v * min(1.0, t * 300.0) * 0.5) as f32);
    }
}

fn note_pitch(color: i64) -> f64 { pow(2.0, PENTATONIC[clamp(color - 1, 0, PENTATONIC.len - 1)] / 12.0) }

fn play_note(color: i64, volume: f64) { play_pitched(Sfx.Bell, note_pitch(color), volume); }

fn play_chord(colors: const i64[:]) {
    let v = 0.5 / max(1.0, sqrt(colors.len as f64));
    for c in colors { play_note(c, v); }
}

fn close_sounds() {
    if sound_ready { audio::close(); }
    sound_ready = false;
}
