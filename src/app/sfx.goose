// Sound effects, synthesized at start-up: no audio files. Each is a few
// sine partials or a little filtered noise with an envelope.

import std;
import math;
import os;
import audio;

enum Sfx { Select, Deselect, Pour, Denied, Complete, Win, Pop, Ice, Reveal, Tool, Lose }

let ALL_SFX: const Sfx[11] = [Sfx.Select, Sfx.Deselect, Sfx.Pour, Sfx.Denied, Sfx.Complete, Sfx.Win,
                              Sfx.Pop, Sfx.Ice, Sfx.Reveal, Sfx.Tool, Sfx.Lose];

fn sfx_index(s: Sfx) -> i64 {
    match s {
        Select => 0, Deselect => 1, Pour => 2, Denied => 3, Complete => 4, Win => 5, Pop => 6,
        Ice => 7, Reveal => 8, Tool => 9, Lose => 10,
    }
}

let RATE = 44100;

var sounds: audio::Sound[11];
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
                let notes: f64[6] = [523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98];
                for f, i in notes { tone(pcm, i * 0.11, f, 1.0, 0.2, 3.5); }
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
        }
        make(id, pcm);
    }
}

fn play(id: Sfx) {
    if !sound_ready || !sound_on { return; }
    audio::play(sounds[sfx_index(id)], 0.8);
}

fn close_sounds() {
    if sound_ready { audio::close(); }
    sound_ready = false;
}
