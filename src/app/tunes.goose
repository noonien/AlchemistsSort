// The background music, composed and synthesized when it is first needed: no
// audio files. Each room has a loop of a whole number of bars: a seeded
// melody over a chord progression, a pad, and the room's own colors (a
// drone, wind, arpeggios, twinkles), through a little reverb.
//
// A loop is rendered as one period of an endlessly repeating piece: notes
// wrap around the loop's end, the drones and the wind's noise repeat exactly
// once a loop, and the reverb runs for WARM seconds before the part that is
// kept, so its tail from the loop's end is already there at the start.
// tune_step does the work a slice at a time (see main.goose's step_jobs).
//
// No audio here, so the tests can render a loop: music.goose plays them.

import std;
import math;
import os;

let MUSIC_RATE = 22050;
let MUSIC_ROOMS = 6;
let WARM: f64 = 8.0;            // seconds of reverb warm-up before the loop
let BLOCK = 512;                // samples rendered between looks at the clock
let TARGET_RMS: f64 = 0.089;    // -21 dBFS
let PEAK_LIMIT: f64 = 0.85;
let TOP_PARTIAL: f64 = 5000.0;  // partials above this are left out

// The instruments, an index into VOICES.
let MUSIC_BOX = 0;
let BELL = 1;
let MARIMBA = 2;
let KALIMBA = 3;
let HARP = 4;
let TWINKLE = 5;
let PAD = 6;
let FLUTE = 7;

// A note of the loop, in samples from its start.
struct Note { start: i64, len: i64, freq: f64, vel: f64, inst: i64 }

// What a room's music is made of. Degrees count up the mode from `root`
// (a MIDI note); the progression has one chord, a degree, every two bars.
struct TuneSpec {
    bpm: f64,
    beats: i64,                 // a bar
    bars: i64,                  // the loop: a multiple of 4
    root: i64,
    mode: i64[7],
    chords: i64[16],
    plan: const u8[:],          // a phrase every 4 bars: motifs A B C, a/b/c their variants, - rests
    lead: i64,
    lead_lo: i64,               // its range, in degrees
    lead_hi: i64,
    lead_vel: f64,
    density: f64,               // how many of the weak eighths it plays
    pentatonic: bool,           // the melody leaves out the 4th and 7th
    arp: i64,
    arp_vel: f64 = 0.0,         // none when zero
    arp_lo: i64 = 0,            // the chord's lowest note, in degrees
    arp_fill: f64 = 0.7,        // the share of a pattern's notes played
    pad_vel: f64,
    pad_lo: i64 = 0,            // the voicing's floor, in degrees
    pad_attack: f64 = 1.5,
    color: i64 = 0,             // an added 7th (6) or 9th (8), or 0
    bass_vel: f64 = 0.0,
    drone_vel: f64 = 0.0,
    wind: f64 = 0.0,
    twinkle: f64 = 0.0,         // the chance of a high note in each beat
    wet: f64 = 0.3,
    rt60: f64 = 2.5,
    echo_beats: f64 = 0.0,      // a soft echo this long, or none
    echo_mix: f64 = 0.0,
    seed: u64,
}

let IONIAN: i64[7] = [0, 2, 4, 5, 7, 9, 11];
let LYDIAN: i64[7] = [0, 2, 4, 6, 7, 9, 11];
let DORIAN: i64[7] = [0, 2, 3, 5, 7, 9, 10];
let MIXOLYDIAN: i64[7] = [0, 2, 4, 5, 7, 9, 10];
let AEOLIAN: i64[7] = [0, 2, 3, 5, 7, 8, 10];

fn tune_spec(room: i64) -> TuneSpec {
    match room {
        // Frost cellar: sparse glassy bells and their echo, an airy pad, wind. D Lydian.
        1 => TuneSpec { bpm: 60.0, beats: 4, bars: 20, root: 50, mode: LYDIAN,
                        chords: [0, 1, 0, 5, 0, 1, 2, 4, 5, 1, 0, 0, 0, 0, 0, 0], plan: "A-Ba-",
                        lead: BELL, lead_lo: 11, lead_hi: 18, lead_vel: 0.5, density: 0.25, pentatonic: false,
                        arp: BELL, pad_vel: 0.22, pad_lo: 5, pad_attack: 3.0, color: 8,
                        wind: 0.05, twinkle: 0.08, wet: 0.42, rt60: 3.2, echo_beats: 0.75, echo_mix: 0.3, seed: 211 },
        // Glassworks: marimba arpeggios over the furnace's low hum. G major.
        2 => TuneSpec { bpm: 76.0, beats: 4, bars: 24, root: 55, mode: IONIAN,
                        chords: [0, 3, 5, 4, 0, 3, 1, 4, 5, 3, 4, 0, 0, 0, 0, 0], plan: "AB-aCb",
                        lead: MARIMBA, lead_lo: 7, lead_hi: 14, lead_vel: 0.45, density: 0.3, pentatonic: true,
                        arp: MARIMBA, arp_vel: 0.32, arp_lo: 0, arp_fill: 0.75,
                        pad_vel: 0.1, pad_lo: 2, drone_vel: 0.2, wet: 0.25, rt60: 2.0, seed: 307 },
        // Observatory: slow pads that open and close, stars twinkling. D Dorian.
        3 => TuneSpec { bpm: 60.0, beats: 4, bars: 24, root: 50, mode: DORIAN,
                        chords: [0, 3, 0, 6, 2, 3, 0, 4, 0, 3, 6, 0, 0, 0, 0, 0], plan: "A-B-a-",
                        lead: BELL, lead_lo: 9, lead_hi: 16, lead_vel: 0.5, density: 0.2, pentatonic: false,
                        arp: BELL, pad_vel: 0.24, pad_lo: 3, pad_attack: 3.5, color: 6, bass_vel: 0.25,
                        twinkle: 0.14, wet: 0.45, rt60: 3.5, echo_beats: 1.5, echo_mix: 0.25, seed: 401 },
        // Greenhouse: kalimba and harp, and a soft flute. G Mixolydian.
        4 => TuneSpec { bpm: 78.0, beats: 4, bars: 28, root: 55, mode: MIXOLYDIAN,
                        chords: [0, 6, 3, 0, 4, 3, 6, 0, 3, 0, 6, 1, 3, 0, 0, 0], plan: "ABa-Cb-",
                        lead: FLUTE, lead_lo: 7, lead_hi: 14, lead_vel: 0.3, density: 0.3, pentatonic: false,
                        arp: KALIMBA, arp_vel: 0.28, arp_lo: 0, arp_fill: 0.6,
                        pad_vel: 0.12, pad_lo: 2, bass_vel: 0.3, wet: 0.3, rt60: 2.2, seed: 503 },
        // Athanor: a low warm drone and slow bells, in the dark of A minor.
        5 => TuneSpec { bpm: 64.0, beats: 4, bars: 24, root: 45, mode: AEOLIAN,
                        chords: [0, 5, 6, 0, 3, 0, 5, 4, 0, 3, 6, 0, 0, 0, 0, 0], plan: "A-B-a-",
                        lead: BELL, lead_lo: 14, lead_hi: 21, lead_vel: 0.45, density: 0.2, pentatonic: false,
                        arp: HARP, arp_vel: 0.16, arp_lo: 0, arp_fill: 0.35,
                        pad_vel: 0.2, pad_lo: 5, pad_attack: 2.5, drone_vel: 0.3, wet: 0.4, rt60: 3.0, seed: 601 },
        // Apothecary: a music box over a warm pad, in a slow three. F major pentatonic.
        _ => TuneSpec { bpm: 72.0, beats: 3, bars: 32, root: 53, mode: IONIAN,
                        chords: [0, 5, 3, 4, 0, 2, 3, 0, 1, 4, 0, 5, 3, 4, 0, 0], plan: "AB-aC-bc",
                        lead: MUSIC_BOX, lead_lo: 7, lead_hi: 16, lead_vel: 0.5, density: 0.35, pentatonic: true,
                        arp: HARP, arp_vel: 0.2, arp_lo: 0, arp_fill: 0.55,
                        pad_vel: 0.2, pad_lo: 2, wet: 0.3, rt60: 2.4, seed: 101 },
    }
}

fn tune_name(room: i64) -> const u8[:] {
    match room { 1 => "frost_cellar", 2 => "glassworks", 3 => "observatory", 4 => "greenhouse",
                 5 => "athanor", _ => "apothecary" }
}

// The room whose music goes with level n: its chapter's, and in the Great
// Work a different room every 15 levels.
fn music_room(level: i64, chapter_theme: i64, chapter_first: i64) -> i64 {
    if chapter_theme < MUSIC_ROOMS { return chapter_theme; }
    (level - chapter_first) / 15 % MUSIC_ROOMS
}

// --- composing ------------------------------------------------------------------------

fn midi_freq(m: i64) -> f64 { 440.0 * pow(2.0, (m - 69) / 12.0) }

fn degree_midi(spec: TuneSpec, d: i64) -> i64 {
    let k = d % 7;
    spec.root + (d - k) / 7 * 12 + spec.mode[k]
}

fn is_chord_tone(d: i64, chord: i64) -> bool {
    let k = (d - chord) % 7;
    k == 0 || k == 2 || k == 4
}

// The chord tone nearest d, the lower on a tie.
fn nearest_chord_tone(d: i64, chord: i64) -> i64 {
    for k in 3 {
        if is_chord_tone(d - k, chord) { return d - k; }
        if is_chord_tone(d + k, chord) { return d + k; }
    }
    d
}

// A rhythm and a contour for three bars: an eighth's slot is a note when its
// step is not NONE.
let NONE = 99;
struct Motif { steps: i64[24] = [99; 24] }

fn motif(r: rng&, spec: TuneSpec) -> Motif {
    var m = Motif {};
    let slots = spec.beats * 2;
    let steps: i64[10] = [-2, -1, -1, -1, 1, 1, 1, 2, 3, -3];
    for bar in 3 {
        for s in slots {
            let p = if s == 0 { 0.75 } else if s == slots / 2 { 0.45 }
                    else if s % 2 == 0 { spec.density * 0.6 } else { spec.density * 0.25 };
            // The middle bar answers more quietly.
            let q = if bar == 1 { p * 0.7 } else { p };
            if r.rand_flt() < q { m.steps[bar * 8 + s] = steps[r.rand_int(steps.len)]; }
        }
    }
    if m.steps[0] == NONE { m.steps[0] = 0; }
    m
}

// The same rhythm, mostly; a third of the steps go elsewhere.
fn vary(m: Motif, r: rng&, spec: TuneSpec) -> Motif {
    var v = m;
    let slots = spec.beats * 2;
    for bar in 3 {
        for s in slots {
            let i = bar * 8 + s;
            if v.steps[i] != NONE && r.rand_flt() < 0.35 { v.steps[i] = r.rand_int(5) - 2; }
            else if v.steps[i] == NONE && s % 2 == 1 && r.rand_flt() < 0.08 { v.steps[i] = 1 - 2 * r.rand_int(2); }
        }
    }
    v
}

fn chord_at(spec: TuneSpec, bar: i64) -> i64 { spec.chords[bar / 2 % 16] }

// Turns a degree back into the lead's range and out of the notes it leaves out.
fn fit_lead(spec: TuneSpec, d: i64, dir: i64) -> i64 {
    var x = d;
    if x > spec.lead_hi { x = spec.lead_hi - (x - spec.lead_hi); }
    if x < spec.lead_lo { x = spec.lead_lo + (spec.lead_lo - x); }
    x = clamp(x, spec.lead_lo, spec.lead_hi);
    if spec.pentatonic && (x % 7 == 3 || x % 7 == 6) { x = if dir > 0 && x < spec.lead_hi { x + 1 } else { x - 1 }; }
    x
}

struct Timing { beat: f64, bar: f64, period: i64 }

fn timing(spec: TuneSpec, bars: i64) -> Timing {
    let beat = 60.0 / spec.bpm * MUSIC_RATE;
    Timing { beat: beat, bar: beat * spec.beats, period: (beat * spec.beats * bars + 0.5) as! i64 }
}

fn add_note(notes: Note[>..]&, tm: Timing, beat_at: f64, beats_long: f64, d: i64, spec: TuneSpec, vel: f64, inst: i64) {
    let start = (beat_at * tm.beat + 0.5) as! i64;
    var secs = beats_long * tm.beat / MUSIC_RATE;
    if !sustained(inst) { secs = ring_time(inst); }
    if inst == PAD { secs += 1.5; }       // into the next chord, as this one fades
    notes.push(Note { start: start % tm.period, len: (secs * MUSIC_RATE) as! i64,
                      freq: midi_freq(degree_midi(spec, d)), vel: vel, inst: inst });
}

fn compose(spec: TuneSpec, bars: i64, notes: Note[>..]&) {
    notes.clear();
    let tm = timing(spec, bars);
    var r = rng { spec.seed };
    let slots = spec.beats * 2;
    let mid = (spec.lead_lo + spec.lead_hi) / 2;

    // The melody, a phrase every four bars.
    var motifs: Motif[3];
    for k in 3 { motifs[k] = motif(r, spec); }
    let phrases = bars / 4;
    for p in phrases {
        let letter = spec.plan[p % spec.plan.len];
        if letter == '-' { continue; }
        let upper = letter >= 'A' && letter <= 'C';
        let k = if upper { (letter - 'A') as i64 } else { (letter - 'a') as i64 };
        let m = if upper { motifs[k] } else { vary(motifs[k], r, spec) };
        var d = nearest_chord_tone(mid + k * 2 - 2, chord_at(spec, p * 4));
        var dir = 1;
        for bar in 3 {
            let b = p * 4 + bar;
            for s in slots {
                let step = m.steps[bar * 8 + s];
                if step == NONE { continue; }
                if step != 0 { dir = if step > 0 { 1 } else { -1 }; }
                d = fit_lead(spec, d + step, dir);
                let strong = s == 0 || s == slots / 2;
                if strong { d = fit_lead(spec, nearest_chord_tone(d, chord_at(spec, b)), dir); }
                // Held until the next note, at most a beat and a half.
                var gap = 1;
                while s + gap < slots && m.steps[bar * 8 + s + gap] == NONE && gap < 3 { gap++; }
                let vel = spec.lead_vel * (if strong { 1.0 } else { 0.78 }) * (0.9 + r.rand_flt() * 0.15);
                add_note(notes, tm, b * spec.beats + s * 0.5, gap * 0.5, d, spec, vel, spec.lead);
            }
        }
        // The phrase comes to rest on a chord tone, the root if it is near.
        let last = p * 4 + 3;
        let chord = chord_at(spec, last);
        var end = nearest_chord_tone(d, chord);
        for c in [chord, chord + 7, chord + 14] { if abs(c - d) <= 2 && c >= spec.lead_lo && c <= spec.lead_hi { end = c; } }
        add_note(notes, tm, last * spec.beats, spec.beats * 0.9, fit_lead(spec, end, 0), spec, spec.lead_vel * 0.85, spec.lead);
    }

    // The pad, a chord every two bars, voiced close above pad_lo.
    for c in bars / 2 {
        let chord = spec.chords[c % 16];
        let tones: i64[4] = [chord, chord + 2, chord + 4, chord + spec.color];
        let n = if spec.color > 0 { 4 } else { 3 };
        for i in n {
            let t = tones[i];
            let d = spec.pad_lo + (t - spec.pad_lo) % 7;
            let v = spec.pad_vel * (if i == 3 { 0.6 } else { 1.0 });
            add_note(notes, tm, c * 2 * spec.beats, 2 * spec.beats, d, spec, v, PAD);
        }
        if spec.bass_vel > 0.0 {
            let d = spec.pad_lo - 7 + (chord - spec.pad_lo) % 7;
            add_note(notes, tm, c * 2 * spec.beats, 2 * spec.beats, d, spec, spec.bass_vel, PAD);
        }
    }

    // Arpeggios: a pattern of the chord's notes in eighths, one of three each bar.
    if spec.arp_vel > 0.0 {
        let patterns: i64[24] = [0, 2, 3, 2, 4, 3, 2, 1,
                                 0, -1, 2, 3, -1, 4, 3, -1,
                                 0, 1, 2, -1, 3, -1, 2, 1];
        var pick: i64[4] = [0, 1, 0, 2];
        for bar in bars {
            if bar % 4 == 0 { for &x in pick { x = r.rand_int(3); } }
            let pat = pick[bar % 4];
            let chord = chord_at(spec, bar);
            let tones: i64[5] = [chord, chord + 2, chord + 4, chord + 7, chord + 9];
            for s in slots {
                let i = patterns[pat * 8 + s % 8];
                if i < 0 || (s > 0 && r.rand_flt() > spec.arp_fill) { continue; }
                let d = spec.arp_lo + (tones[i] - spec.arp_lo) % 7 + (tones[i] - chord) / 7 * 7;
                let vel = spec.arp_vel * (if s == 0 { 1.0 } else if s % 2 == 0 { 0.8 } else { 0.62 }) * (0.9 + r.rand_flt() * 0.2);
                add_note(notes, tm, bar * spec.beats + s * 0.5, 0.5, d, spec, vel, spec.arp);
            }
        }
    }

    // High notes here and there, from the chord.
    if spec.twinkle > 0.0 {
        for beat in bars * spec.beats {
            if r.rand_flt() >= spec.twinkle { continue; }
            let chord = chord_at(spec, beat / spec.beats);
            let d = 21 + (chord + 2 * r.rand_int(3)) % 7;
            let at = beat + (if r.rand_flt() < 0.5 { 0.0 } else { 0.5 });
            add_note(notes, tm, at, 1.0, d, spec, 0.14 + r.rand_flt() * 0.08, TWINKLE);
        }
    }
}

// --- the instruments ------------------------------------------------------------------

// Up to four sine partials, each dying away at its own rate.
struct Voice { n: i64, ratio: f64[4], amp: f64[4], decay: f64[4], attack: f64 }

fn sustained(inst: i64) -> bool { inst == PAD || inst == FLUTE }

let VOICES: Voice[8] = [
    Voice { n: 4, ratio: [1.0, 2.0, 3.0, 5.4], amp: [1.0, 0.2, 0.05, 0.04], decay: [1.5, 3.0, 5.0, 9.0], attack: 0.006 },    // MusicBox
    Voice { n: 4, ratio: [1.0, 2.0, 2.76, 5.4], amp: [1.0, 0.22, 0.14, 0.04], decay: [0.8, 1.4, 2.2, 4.0], attack: 0.012 },    // Bell
    Voice { n: 3, ratio: [1.0, 4.0, 10.0, 0.0], amp: [1.0, 0.08, 0.015, 0.0], decay: [2.4, 8.0, 18.0, 0.0], attack: 0.01 },    // Marimba
    Voice { n: 3, ratio: [1.0, 2.0, 5.95, 0.0], amp: [1.0, 0.08, 0.06, 0.0], decay: [1.8, 4.0, 12.0, 0.0], attack: 0.007 },    // Kalimba
    Voice { n: 4, ratio: [1.0, 2.0, 3.0, 4.0], amp: [1.0, 0.3, 0.12, 0.05], decay: [1.2, 2.0, 3.0, 4.0], attack: 0.008 },    // Harp
    Voice { n: 2, ratio: [1.0, 2.0, 0.0, 0.0], amp: [1.0, 0.08, 0.0, 0.0], decay: [1.6, 3.0, 0.0, 0.0], attack: 0.02 },    // Twinkle
    // Two fundamentals a few cents apart beat slowly.
    Voice { n: 4, ratio: [1.0, 1.0035, 2.0, 3.0], amp: [0.5, 0.5, 0.1, 0.03], decay: [0.0; 4], attack: 1.5 },    // Pad
    Voice { n: 3, ratio: [1.0, 2.0, 3.0, 0.0], amp: [1.0, 0.1, 0.03, 0.0], decay: [0.0; 4], attack: 0.12 },    // Flute
];

fn voice(inst: i64) -> Voice { VOICES[inst] }

// Seconds until a struck note has died away (-55 dB on its slowest partial).
fn ring_time(inst: i64) -> f64 { min(7.0, 6.3 / voice(inst).decay[0]) }

fn smooth(x: f64) -> f64 {
    let t = clamp(x, 0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

// Adds the part of note `n`, started at sample `at`, that falls in the block
// starting at sample b0.
fn render_note(dry: f64[BLOCK]&, b0: i64, at: i64, n: Note, attack: f64) {
    let j0 = max(b0, at);
    let j1 = min(b0 + BLOCK, at + n.len);
    if j1 <= j0 { return; }
    let v = voice(n.inst);
    let len = n.len as f64 / MUSIC_RATE;
    let release = 2.0;          // a pad's, into the next chord
    for k in v.n {
        let f = n.freq * v.ratio[k];
        if f > TOP_PARTIAL { continue; }
        let w = TAU * f / MUSIC_RATE;
        let t0 = (j0 - at) as f64 / MUSIC_RATE;
        // A rotating phasor: a sine without calling sin each sample.
        var c = cos(w * (j0 - at));
        var s = sin(w * (j0 - at));
        let cw = cos(w);
        let sw = sin(w);
        var g = n.vel * v.amp[k] * exp(-v.decay[k] * t0);
        let gm = exp(-v.decay[k] / MUSIC_RATE);
        var t = t0;
        let dt = 1.0 / MUSIC_RATE;
        let sus = sustained(n.inst);
        for j in j0..j1 {
            let env = if sus { smooth(t / attack) * smooth((len - t) / release) } else { min(1.0, t / attack) * min(1.0, (len - t) * 4.0) };
            dry[j - b0] += s * g * env;
            let c2 = c * cw - s * sw;
            s = s * cw + c * sw;
            c = c2;
            g *= gm;
            t += dt;
        }
    }
}

// A flute: a sine with a little breath of vibrato.
fn render_flute(dry: f64[BLOCK]&, b0: i64, at: i64, n: Note) {
    let j0 = max(b0, at);
    let j1 = min(b0 + BLOCK, at + n.len);
    let len = n.len as f64 / MUSIC_RATE;
    let depth = 0.004 * n.freq / 4.8;
    for j in j0..j1 {
        let t = (j - at) as f64 / MUSIC_RATE;
        let env = smooth(t / 0.12) * smooth((len - t) / 0.3);
        let ph = TAU * n.freq * t + depth * (1.0 - cos(TAU * 4.8 * t)) * smooth(t / 0.5) * TAU;
        dry[j - b0] += (sin(ph) + 0.1 * sin(2.0 * ph) + 0.03 * sin(3.0 * ph)) * env * n.vel;
    }
}

// --- the room: reverb, echo -----------------------------------------------------------

let COMB_LEN: i64[4] = [781, 832, 894, 949];
let ALLPASS_LEN: i64[2] = [389, 307];
let ECHO_MAX = 34000;

struct Comb { buf: f32[960] = [0.0; 960], len: i64 = 1, at: i64 = 0, feedback: f64 = 0.0, low: f64 = 0.0 }
struct Allpass { buf: f32[400] = [0.0; 400], len: i64 = 1, at: i64 = 0 }

struct Room {
    combs: Comb[4],
    allpasses: Allpass[2],
    echo: f32[ECHO_MAX] = [0.0; ECHO_MAX],
    echo_len: i64 = 0,
    echo_at: i64 = 0,
    echo_low: f64 = 0.0,
    tone: f64 = 0.0,            // the master's low-pass
    wind_a: f64 = 0.0,          // the wind's two low-passes: their difference is a band
    wind_b: f64 = 0.0,
}

fn room_for(spec: TuneSpec) -> Room {
    var r = Room { combs: [Comb {}; 4], allpasses: [Allpass {}; 2] };
    for &c, i in r.combs {
        c.len = COMB_LEN[i];
        c.feedback = pow(10.0, -3.0 * c.len / (spec.rt60 * MUSIC_RATE));
    }
    for &a, i in r.allpasses { a.len = ALLPASS_LEN[i]; }
    r.echo_len = min(ECHO_MAX, (spec.echo_beats * 60.0 / spec.bpm * MUSIC_RATE) as! i64);
    r
}

fn reverb(r: Room&, x: f64) -> f64 {
    var out = 0.0;
    for &c in r.combs {
        let y = c.buf[c.at] as f64;
        c.low = y * 0.65 + c.low * 0.35;          // the walls soak up the highs
        c.buf[c.at] = (x * 0.25 + c.low * c.feedback) as f32;
        c.at = (c.at + 1) % c.len;
        out += y;
    }
    for &a in r.allpasses {
        let y = a.buf[a.at] as f64;
        a.buf[a.at] = (out + y * 0.5) as f32;
        a.at = (a.at + 1) % a.len;
        out = y - out * 0.5;
    }
    out
}

// White noise that repeats every `period` samples.
fn periodic_noise(i: i64, period: i64) -> f64 {
    let h = hash((i % period) as u64 * 0x9E3779B97F4A7C15 + 0x5EED);
    (h >> 11) / 9007199254740992.0 * 2.0 - 1.0
}

// --- rendering a loop, a slice at a time ----------------------------------------------

struct TuneJob {
    room: i64 = 0,
    spec: TuneSpec,
    period: i64 = 0,            // the loop, in samples
    warm: i64 = 0,
    at: i64 = 0,                // the next sample, counting the warm-up
    scaled: i64 = 0,            // samples of the loop given their final gain
    gain: f64 = 1.0,
    mean: f64 = 0.0,
    sum: f64 = 0.0,
    sum_sq: f64 = 0.0,
    peak: f64 = 0.0,
    drone: f64[4] = [0.0; 4],   // frequencies, a whole number of cycles a loop
    done: bool = false,
    space: Room,
}

// Starts the loop for `room`; `bars`, when above zero, shortens it (for the tests).
fn tune_begin(room: i64, bars: i64, notes: Note[>..]&, pcm: f32[>..]&) -> TuneJob {
    let spec = tune_spec(room);
    let n = if bars > 0 { bars } else { spec.bars };
    compose(spec, n, notes);
    let tm = timing(spec, n);
    var job = TuneJob { room: room, spec: spec, period: tm.period, warm: (WARM * MUSIC_RATE) as! i64, space: room_for(spec) };
    // The drone: the root two octaves down, and its fifth.
    let base = midi_freq(spec.root - 12);
    let freqs: f64[4] = [base, base * 1.5, base * 2.0, base * 3.0];
    for f, k in freqs {
        let cycles = round(f * tm.period / MUSIC_RATE);
        job.drone[k] = cycles * MUSIC_RATE / tm.period;
    }
    pcm.clear();
    job
}

// Works on the loop for about `seconds`. True once pcm holds the whole loop.
fn tune_step(job: TuneJob&, notes: const Note[:], pcm: f32[>..]&, seconds: f64) -> bool {
    let until = clock() + seconds;
    let spec = job.spec;
    let total = job.warm + job.period;
    while job.at < total {
        // Loop time of the block's first sample: negative during the warm-up.
        let b0 = job.at - job.warm;
        var dry: f64[BLOCK] = [0.0; BLOCK];
        for n in notes {
            // Each repeat of the note that sounds in this block.
            let x = b0 - n.start - n.len;
            var k = (x - x % job.period) / job.period + 1;
            while n.start + k * job.period < b0 + BLOCK {
                let at = n.start + k * job.period;
                if n.inst == FLUTE { render_flute(dry, b0, at, n); }
                else { render_note(dry, b0, at, n, if n.inst == PAD { spec.pad_attack } else { voice(n.inst).attack }); }
                k++;
            }
        }
        let p = job.period as f64;
        let tone_k = 1.0 - exp(-TAU * 4200.0 / MUSIC_RATE);
        for i in BLOCK {
            if job.at + i >= total { break; }
            let j = b0 + i;
            var x = dry[i];
            if spec.drone_vel > 0.0 {
                let swell = 0.75 + 0.25 * sin(TAU * 3.0 * j / p);
                let d = sin(TAU * job.drone[0] * j / MUSIC_RATE) + 0.5 * sin(TAU * job.drone[1] * j / MUSIC_RATE) +
                        0.3 * sin(TAU * job.drone[2] * j / MUSIC_RATE) + 0.08 * sin(TAU * job.drone[3] * j / MUSIC_RATE);
                x += d * spec.drone_vel * swell * 0.5;
            }
            if spec.wind > 0.0 {
                let w = periodic_noise(j, job.period);
                job.space.wind_a += (w - job.space.wind_a) * 0.22;
                job.space.wind_b += (w - job.space.wind_b) * 0.05;
                let gust = (0.55 + 0.45 * sin(TAU * 2.0 * j / p + 1.0)) * (0.8 + 0.2 * sin(TAU * 7.0 * j / p));
                x += (job.space.wind_a - job.space.wind_b) * spec.wind * gust;
            }
            var y = x + reverb(job.space, x) * spec.wet;
            if job.space.echo_len > 0 {
                let e = job.space.echo[job.space.echo_at] as f64;
                job.space.echo_low += (e - job.space.echo_low) * 0.5;
                job.space.echo[job.space.echo_at] = (x + job.space.echo_low * 0.35) as f32;
                job.space.echo_at = (job.space.echo_at + 1) % job.space.echo_len;
                y += e * spec.echo_mix;
            }
            job.space.tone += (y - job.space.tone) * tone_k;
            if j >= 0 {
                let v = job.space.tone;
                pcm.push(v as f32);
                job.sum += v;
                job.sum_sq += v * v;
                job.peak = max(job.peak, abs(v));
            }
        }
        job.at = min(total, job.at + BLOCK);
        if job.at >= total {
            // The level: TARGET_RMS, the peak kept under PEAK_LIMIT.
            job.mean = job.sum / job.period;
            let rms = sqrt(max(1e-12, job.sum_sq / job.period - job.mean * job.mean));
            job.gain = min(TARGET_RMS / rms, PEAK_LIMIT / (job.peak + abs(job.mean)));
        }
        if clock() >= until { return false; }
    }
    while job.scaled < pcm.len {
        let end = min(pcm.len, job.scaled + 65536);
        for i in job.scaled..end { pcm[i] = ((pcm[i] - job.mean) * job.gain) as f32; }
        job.scaled = end;
        if clock() >= until && job.scaled < pcm.len { return false; }
    }
    job.done = true;
    true
}

// --- a WAV file, for listening outside the game -----------------------------------------

fn put_u32(out: u8[>..]&, x: i64) { for k in 4 { out.push(((x >> (8 * k)) & 255) as! u8); } }
fn put_u16(out: u8[>..]&, x: i64) { for k in 2 { out.push(((x >> (8 * k)) & 255) as! u8); } }

fn write_wav(path: const u8[:], pcm: const f32[:]) -> bool {
    var out: u8[>..] = [];
    out.append("RIFF");
    put_u32(out, 36 + pcm.len * 2);
    out.append("WAVEfmt ");
    put_u32(out, 16);
    put_u16(out, 1);                // PCM
    put_u16(out, 1);                // mono
    put_u32(out, MUSIC_RATE);
    put_u32(out, MUSIC_RATE * 2);
    put_u16(out, 2);
    put_u16(out, 16);
    out.append("data");
    put_u32(out, pcm.len * 2);
    for v in pcm { put_u16(out, (round(clamp(v as f64, -1.0, 1.0) * 32767.0) as! i64) & 65535); }
    write_file(path, out)
}
