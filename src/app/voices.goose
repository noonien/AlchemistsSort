// The players, and the hall they play in. A voice sounds one note: it reads
// a recorded note from the bank (bank.goose) at the note's pitch, shaping it
// with an envelope and a soft low-pass that opens as the note grows louder,
// or it synthesizes a singing bowl, or one voice of a wordless choir. Under
// them a drone may hum, and all of it goes through the hall, a stereo
// reverb that can add a shimmer an octave up. tunes.goose decides what is
// played and when.
//
// What a voice does follows from its note and the time since the note began
// and nothing else, so a note played again a loop later sounds the same: a
// loop repeats exactly. The drone, the choir's vowels and the shimmer move
// in whole cycles a loop for the same reason.

import std;
import math;
import .bank;

let MUSIC_RATE = 32000;
let BLOCK = 256;                // samples made at a time; envelopes run straight across a block

// The synthesized instruments, after the sampled ones.
let BOWL = SAMPLED;             // a singing bowl, struck softly
let CHOIR = SAMPLED + 1;        // a voice of the choir; the hall gives the choir its vowels
let INSTRUMENTS = SAMPLED + 2;

// A note of the loop, in samples from its start.
struct Note {
    start: i64,
    len: i64,                   // held for (a plucked or struck note: rings for, unless damped sooner)
    midi: f64,
    vel: f64,                   // 0 to 1
    inst: i64,
    pan: f64 = 0.0,             // -1 (left) to 1 (right)
    attack: f64 = 0.0,          // a held note: seconds more to swell in, beyond its instrument's
    swell: f64 = 0.0,           // a held note: how much it grows to its middle and recedes
    legato: bool = false,       // joined to the note before: it begins past its recording's attack
    reverse: bool = false,      // played backwards, ending where the note does: a swell into what follows
}

// How an instrument's notes are played.
struct Timbre {
    held: bool,                 // bowed, blown or rubbed: it sounds as long as the note; else it rings
    attack: f64,                // seconds of fade-in over the recording's own onset
    release: f64,               // seconds it takes to fall silent after the note
    gain: f64,
    dark: f64,                  // the low-pass on its softest notes, Hz
    bright: f64,                // and on its loudest
    send: f64,                  // how much of it goes to the hall
}

let TIMBRES: Timbre[10] = [
    Timbre { held: false, attack: 0.0, release: 0.4, gain: 1.0, dark: 2400.0, bright: 13000.0, send: 0.45 },   // Harp
    Timbre { held: false, attack: 0.0, release: 0.3, gain: 0.7, dark: 2600.0, bright: 13000.0, send: 0.4 },    // Dulcimer
    Timbre { held: true, attack: 0.15, release: 0.7, gain: 0.95, dark: 900.0, bright: 7000.0, send: 0.5 },     // Cello
    Timbre { held: true, attack: 0.4, release: 1.0, gain: 0.75, dark: 1200.0, bright: 9000.0, send: 0.6 },     // Strings
    Timbre { held: true, attack: 0.09, release: 0.5, gain: 0.85, dark: 1500.0, bright: 10000.0, send: 0.5 },   // Violin
    Timbre { held: true, attack: 0.3, release: 0.9, gain: 1.65, dark: 2000.0, bright: 11000.0, send: 0.65 },   // Psaltery
    Timbre { held: true, attack: 0.5, release: 1.4, gain: 0.8, dark: 3000.0, bright: 10000.0, send: 0.65 },    // Glass
    Timbre { held: true, attack: 0.07, release: 0.4, gain: 0.8, dark: 1800.0, bright: 10000.0, send: 0.5 },    // Flute
    Timbre { held: false, attack: 0.004, release: 1.5, gain: 0.32, dark: 0.0, bright: 0.0, send: 0.6 },        // Bowl
    Timbre { held: true, attack: 0.8, release: 1.6, gain: 0.16, dark: 0.0, bright: 0.0, send: 0.7 },           // Choir
];

let LEGATO_SKIP: f64 = 0.22;    // seconds of a recording's attack a legato note leaves out
let LEGATO_ATTACK: f64 = 0.07;

fn smooth(x: f64) -> f64 {
    let t = clamp(x, 0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

// The one-pole low-pass that lets through about `hz`.
fn lowpass_k(hz: f64) -> f64 { 1.0 - exp(-TAU * min(hz, 0.45 * MUSIC_RATE) / MUSIC_RATE) }

// A number from 0 to 1 that only `x` decides.
fn hashed(x: u64) -> f64 { (hash(x) >> 11) / 9007199254740992.0 }

// --- the voices -----------------------------------------------------------------------

let MAX_VOICES = 64;
let PARTIALS = 12;              // a bowl's: six modes, each a pair a little apart that beat

struct Voice {
    on: bool = false,
    n: Note,
    at: i64 = 0,                // the sample it began at
    end: i64 = 0,               // and the one it is silent from
    zone: i64 = -1,
    pos: f64 = 0.0,             // where it reads its recording, in the recording's samples
    step: f64 = 0.0,            // how far it reads on each sample; backwards when negative
    gl: f64 = 0.0,              // its place between the speakers, as gains
    gr: f64 = 0.0,
    low: f64 = 0.0,             // its low-pass, two poles
    low2: f64 = 0.0,
    seed: f64 = 0.0,            // where its slow wanderings start, 0 to 1
    // A bowl's partials, each a rotating phasor dying away; a choir voice's
    // singers use the first three phases.
    c: f64[PARTIALS] = [0.0; PARTIALS],
    s: f64[PARTIALS] = [0.0; PARTIALS],
    cw: f64[PARTIALS] = [0.0; PARTIALS],
    sw: f64[PARTIALS] = [0.0; PARTIALS],
    g: f64[PARTIALS] = [0.0; PARTIALS],
    gm: f64[PARTIALS] = [0.0; PARTIALS],
}

// A block's worth of what the voices play: the dry sound, what goes to the
// hall, and the choir, which the hall shapes into vowels first.
struct Mix {
    l: f64[BLOCK] = [0.0; BLOCK],
    r: f64[BLOCK] = [0.0; BLOCK],
    send_l: f64[BLOCK] = [0.0; BLOCK],
    send_r: f64[BLOCK] = [0.0; BLOCK],
    choir: f64[BLOCK] = [0.0; BLOCK],
}

// A singing bowl's modes: their frequencies against the lowest, levels,
// seconds to die away, and how fast each beats with its twin.
let BOWL_RATIO: f64[6] = [1.0, 2.77, 5.33, 8.75, 12.9, 17.6];
let BOWL_AMP: f64[6] = [1.0, 0.5, 0.26, 0.12, 0.06, 0.03];
let BOWL_T60: f64[6] = [11.0, 7.5, 4.5, 2.6, 1.5, 0.9];
let BOWL_BEAT: f64[6] = [0.55, 1.1, 1.7, 2.6, 3.4, 4.3];

// The seconds after its start that note `n` is silent from.
fn note_extent(n: Note, z: Zone) -> f64 {
    let tb = TIMBRES[n.inst];
    let len = n.len as f64 / MUSIC_RATE;
    if n.inst == BOWL || n.inst == CHOIR { return len + tb.release; }
    let step = pow(2.0, (n.midi - z.midi) / 12.0) * z.rate / MUSIC_RATE;
    let skip = if n.legato && tb.held { LEGATO_SKIP * z.rate } else { 0.0 };
    let recorded = (z.len - 3 - skip) / step / MUSIC_RATE;
    if z.loop_len > 0 { len + tb.release } else { min(recorded, len + tb.release) }
}

// Starts voice `v` on note `n`, which begins at sample `at`. When `at` is
// already behind `now`, the voice is caught up to `now`.
fn start_voice(v: Voice&, n: Note, at: i64, now: i64) {
    v = Voice { on: true, n: n, at: at, .. };
    let p = (clamp(n.pan, -1.0, 1.0) + 1.0) * PI * 0.25;
    v.gl = cos(p);
    v.gr = sin(p);
    v.seed = hashed((n.start * 7919 + n.inst * 104729) as! u64 + (n.midi * 64.0) as! u64);
    let behind = max(0, now - at);
    if n.inst < SAMPLED {
        v.zone = zone_for(n.inst, n.midi);
        if v.zone < 0 { v.on = false; return; }
        let z = bank_zones[v.zone];
        let tb = TIMBRES[n.inst];
        v.step = pow(2.0, (n.midi - z.midi) / 12.0) * z.rate / MUSIC_RATE;
        if n.reverse {
            // Backwards from as far into the recording as the note is long,
            // to its onset at the note's end; later, if the recording is shorter.
            let from = min(n.len * v.step, (z.len - 3) as f64);
            v.at = at + n.len - (from / v.step) as! i64;
            v.end = at + n.len;
            v.pos = from - max(0, now - v.at) * v.step;
            v.step = -v.step;
            return;
        }
        v.pos = if n.legato && tb.held { LEGATO_SKIP * z.rate } else { 0.0 };
        v.end = at + (note_extent(n, z) * MUSIC_RATE) as! i64;
        v.pos += behind * v.step;
        if z.loop_len > 0 && v.pos >= z.loop_at + z.loop_len {
            v.pos = z.loop_at + (v.pos - z.loop_at) % (z.loop_len as f64);
        }
    } else if n.inst == BOWL {
        let f = 440.0 * pow(2.0, (n.midi - 69.0) / 12.0);
        let t = behind as f64 / MUSIC_RATE;
        for k in PARTIALS {
            let mode = k / 2;
            let fk = f * BOWL_RATIO[mode] + (if k % 2 == 1 { BOWL_BEAT[mode] } else { 0.0 });
            if fk > 0.42 * MUSIC_RATE { continue; }
            let w = TAU * fk / MUSIC_RATE;
            // Lower bowls ring longer.
            let decay = 6.91 / (BOWL_T60[mode] * pow(220.0 / f, 0.3));
            let ph = w * behind + v.seed * TAU * (mode + 1);
            v.c[k] = cos(ph);
            v.s[k] = sin(ph);
            v.cw[k] = cos(w);
            v.sw[k] = sin(w);
            v.g[k] = 0.5 * BOWL_AMP[mode] * exp(-decay * t);
            v.gm[k] = exp(-decay / MUSIC_RATE);
        }
        v.end = at + n.len + (TIMBRES[BOWL].release * MUSIC_RATE) as! i64;
    } else {
        for k in 3 { v.c[k] = hashed((k + 17) as! u64 + (v.seed * 1e9) as! u64); }
        v.end = at + n.len + (TIMBRES[CHOIR].release * MUSIC_RATE) as! i64;
    }
}

// The level of voice `v` at sample j, before its velocity, and how far
// along its swell it is (for its brightness).
fn envelope(v: Voice, j: i64) -> f64, f64 {
    let tb = TIMBRES[v.n.inst];
    let t = (j - v.at) as f64 / MUSIC_RATE;
    let len = v.n.len as f64 / MUSIC_RATE;
    if v.n.reverse {
        // In from silence, as a ring played backwards grows, to a quick end.
        let e = smooth(t / max(0.05, (v.end - v.at) * 0.6 / MUSIC_RATE)) * min(1.0, (v.end - j) as f64 / (0.006 * MUSIC_RATE));
        return e, e;
    }
    var e = 1.0;
    var shape = 1.0;
    if tb.held {
        let a = if v.n.legato { LEGATO_ATTACK } else { tb.attack + v.n.attack };
        e = smooth(t / a);
        if v.n.swell > 0.0 {
            // Messa di voce: from below to full in the note's middle, and back.
            shape = (1.0 + v.n.swell * sin(PI * clamp(t / len, 0.0, 1.0))) / (1.0 + v.n.swell);
            e *= shape;
        }
    } else {
        e = min(1.0, t / max(tb.attack, 1e-4));
    }
    if t > len { e *= 1.0 - smooth((t - len) / tb.release); }
    return e, shape;
}

// The low-pass for a note of velocity `vel`, `shape` of the way into its swell.
fn brightness(tb: Timbre, vel: f64, shape: f64) -> f64 {
    let x = clamp(0.1 + 0.9 * vel * shape * shape, 0.0, 1.0);
    lowpass_k(tb.dark * pow(tb.bright / tb.dark, x))
}

fn hermite(a: f64, b: f64, c: f64, d: f64, f: f64) -> f64 {
    let c1 = 0.5 * (c - a);
    let c2 = a - 2.5 * b + 2.0 * c - 0.5 * d;
    let c3 = 0.5 * (d - a) + 1.5 * (b - c);
    ((c3 * f + c2) * f + c1) * f + b
}

// Sample i of zone z, through its loop; silence outside the recording.
fn zone_sample(z: Zone, i: i64) -> f64 {
    var k = i;
    if z.loop_len > 0 && k >= z.loop_at + z.loop_len { k -= z.loop_len; }
    if k < 0 || k >= z.len { return 0.0; }
    bank_pcm[z.at + k]
}

fn play_sampled(v: Voice&, b0: i64, m: Mix&) {
    let j0 = max(b0, v.at);
    let j1 = min(b0 + BLOCK, v.end);
    if j1 <= j0 { return; }
    let z = bank_zones[v.zone];
    let tb = TIMBRES[v.n.inst];
    var step = v.step;
    if tb.held && !v.n.reverse {
        // A held note wanders a cent or two, slowly, as a player's does.
        let t = (j0 - v.at) as f64 / MUSIC_RATE;
        step *= 1.0 + 0.0009 * sin(TAU * (0.19 + 0.1 * v.seed) * t + TAU * v.seed) * smooth(t / 1.5);
    }
    let e0, s0 = envelope(v, j0);
    let e1, s1 = envelope(v, j1);
    let gain = tb.gain * pow(v.n.vel, 1.5);
    // Louder is brighter: a bow pressed harder, a string plucked harder.
    let k0 = brightness(tb, v.n.vel, s0);
    let k1 = brightness(tb, v.n.vel, s1);
    let n = (j1 - j0) as f64;
    let de = (e1 - e0) * gain / n;
    let dk = (k1 - k0) / n;
    var e = e0 * gain;
    var k = k0;
    var pos = v.pos;
    var low = v.low;
    var low2 = v.low2;
    let limit = if z.loop_len > 0 { z.loop_at + z.loop_len } else { z.len };
    let base = z.at;
    let send = tb.send;
    for j in j0..j1 {
        let i = pos as! i64;
        let f = pos - i;
        var x = 0.0;
        if i >= 1 && i + 2 < limit {
            x = hermite(bank_pcm[base + i - 1], bank_pcm[base + i], bank_pcm[base + i + 1], bank_pcm[base + i + 2], f);
        } else {
            x = hermite(zone_sample(z, i - 1), zone_sample(z, i), zone_sample(z, i + 1), zone_sample(z, i + 2), f);
        }
        low += (x - low) * k;
        low2 += (low - low2) * k;
        let y = low2 * e;
        let o = j - b0;
        m.l[o] += y * v.gl;
        m.r[o] += y * v.gr;
        m.send_l[o] += y * v.gl * send;
        m.send_r[o] += y * v.gr * send;
        pos += step;
        if z.loop_len > 0 && pos >= limit { pos -= z.loop_len; }
        e += de;
        k += dk;
    }
    v.pos = pos;
    v.low = low;
    v.low2 = low2;
    if pos < 0.0 || (z.loop_len == 0 && pos >= z.len - 2) { v.end = j1; }
}

fn play_bowl(v: Voice&, b0: i64, m: Mix&) {
    let j0 = max(b0, v.at);
    let j1 = min(b0 + BLOCK, v.end);
    if j1 <= j0 { return; }
    let e0, s0 = envelope(v, j0);
    let e1, s1 = envelope(v, j1);
    let gain = TIMBRES[BOWL].gain * pow(v.n.vel, 1.3);
    let n = (j1 - j0) as f64;
    for k in PARTIALS {
        if v.g[k] < 1e-6 { continue; }
        var c = v.c[k];
        var s = v.s[k];
        var g = v.g[k] * gain;
        var e = e0;
        let de = (e1 - e0) / n;
        let cw = v.cw[k];
        let sw = v.sw[k];
        let gm = v.gm[k];
        for j in j0..j1 {
            let y = s * g * e;
            let o = j - b0;
            m.l[o] += y * v.gl;
            m.r[o] += y * v.gr;
            m.send_l[o] += y * v.gl * 0.6;
            m.send_r[o] += y * v.gr * 0.6;
            let c2 = c * cw - s * sw;
            s = s * cw + c * sw;
            c = c2;
            g *= gm;
            e += de;
        }
        // Renormalized now and then, so rounding doesn't make it grow.
        let r = 1.0 / sqrt(c * c + s * s);
        v.c[k] = c * r;
        v.s[k] = s * r;
        v.g[k] = g / gain;
    }
}

// A band-limited sawtooth's correction near its jump (PolyBLEP).
fn blep(t: f64, dt: f64) -> f64 {
    if t < dt { let x = t / dt; return x + x - x * x - 1.0; }
    if t > 1.0 - dt { let x = (t - 1.0) / dt; return x * x + x + x + 1.0; }
    0.0
}

// Three singers on one note, each a little apart in pitch and in vibrato,
// with a breath of noise: into the choir's bus, which the hall gives vowels.
fn play_choir(v: Voice&, b0: i64, m: Mix&) {
    let j0 = max(b0, v.at);
    let j1 = min(b0 + BLOCK, v.end);
    if j1 <= j0 { return; }
    let e0, s0 = envelope(v, j0);
    let e1, s1 = envelope(v, j1);
    let gain = TIMBRES[CHOIR].gain * pow(v.n.vel, 1.3);
    let f = 440.0 * pow(2.0, (v.n.midi - 69.0) / 12.0);
    let t = (j0 - v.at) as f64 / MUSIC_RATE;
    let n = (j1 - j0) as f64;
    let detune: f64[3] = [1.0, 1.0046, 0.9958];
    let vib: f64[3] = [5.1, 5.6, 4.7];
    for q in 3 {
        // Vibrato that comes in after the onset, as a singer's does.
        let depth = 0.0045 * smooth((t - 0.35) / 1.0);
        let dt = f * detune[q] * (1.0 + depth * sin(TAU * vib[q] * t + TAU * (v.seed + q * 0.31))) / MUSIC_RATE;
        var ph = v.c[q];
        var e = e0 * gain;
        let de = (e1 - e0) * gain / n;
        for j in j0..j1 {
            m.choir[j - b0] += (2.0 * ph - 1.0 - blep(ph, dt)) * e;
            ph += dt;
            if ph >= 1.0 { ph -= 1.0; }
            e += de;
        }
        v.c[q] = ph;
    }
    let base = (v.seed * 1e9) as! u64;
    var e = e0 * gain * 0.12;
    let de = (e1 - e0) * gain * 0.12 / n;
    for j in j0..j1 {
        m.choir[j - b0] += (hashed(base + (j - v.at) as! u64) * 2.0 - 1.0) * e;
        e += de;
    }
}

// Plays voice `v` into the block starting at b0. False once it is silent.
fn play_voice(v: Voice&, b0: i64, m: Mix&) -> bool {
    if v.n.inst < SAMPLED { play_sampled(v, b0, m); }
    else if v.n.inst == BOWL { play_bowl(v, b0, m); }
    else { play_choir(v, b0, m); }
    v.end > b0 + BLOCK
}

// --- the drone ------------------------------------------------------------------------
// A hum on the room's keynote and its fifth, like a hurdy-gurdy's or a
// tanpura's drone strings: harmonics whose levels breathe, each at its own
// slow pace, so its color keeps turning. Each frequency and each breath is a
// whole number of cycles a loop.

let DRONE_PARTIALS = 14;

struct Drone {
    n: i64 = 0,
    level: f64 = 0.0,
    freq: f64[DRONE_PARTIALS] = [0.0; DRONE_PARTIALS],
    amp: f64[DRONE_PARTIALS] = [0.0; DRONE_PARTIALS],
    breath: f64[DRONE_PARTIALS] = [0.0; DRONE_PARTIALS],   // cycles a loop
    phase: f64[DRONE_PARTIALS] = [0.0; DRONE_PARTIALS],
    pan: f64[DRONE_PARTIALS] = [0.0; DRONE_PARTIALS],
}

fn drone_for(root: i64, level: f64, period: i64) -> Drone {
    var d = Drone { level: level };
    if root <= 0 || level <= 0.0 { return d; }
    let f0 = 440.0 * pow(2.0, (root - 69) / 12.0);
    // The root's harmonics, then the fifth's, then the octave below.
    let mult: f64[DRONE_PARTIALS] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 1.5, 3.0 * 1.5, 4.5, 6.0, 0.5, 2.5];
    let amp: f64[DRONE_PARTIALS] = [1.0, 0.62, 0.42, 0.3, 0.2, 0.16, 0.1, 0.08, 0.45, 0.2, 0.12, 0.08, 0.35, 0.14];
    for k in DRONE_PARTIALS {
        let f = f0 * mult[k];
        let cycles = max(1.0, round(f * period / MUSIC_RATE));
        d.freq[d.n] = cycles * MUSIC_RATE / period;
        d.amp[d.n] = amp[k];
        d.breath[d.n] = (1 + (k * 5) % 7) as f64;
        d.phase[d.n] = k * 2.399;
        d.pan[d.n] = if k % 2 == 0 { -0.35 } else { 0.35 };
        d.n++;
    }
    d
}

fn play_drone(d: Drone, b0: i64, period: i64, m: Mix&) {
    if d.n == 0 { return; }
    let p = period as f64;
    for k in d.n {
        // The exact phase at the block's start; a rotating phasor across it.
        let cyc = d.freq[k] * b0 / MUSIC_RATE;
        let ph = TAU * (cyc - floor(cyc));
        var c = cos(ph);
        var s = sin(ph);
        let w = TAU * d.freq[k] / MUSIC_RATE;
        let cw = cos(w);
        let sw = sin(w);
        let a0 = d.amp[k] * (0.55 + 0.45 * sin(TAU * d.breath[k] * b0 / p + d.phase[k]));
        let a1 = d.amp[k] * (0.55 + 0.45 * sin(TAU * d.breath[k] * (b0 + BLOCK) / p + d.phase[k]));
        var a = a0 * d.level;
        let da = (a1 - a0) * d.level / BLOCK;
        let gl = 0.7071 - d.pan[k] * 0.4;
        let gr = 0.7071 + d.pan[k] * 0.4;
        for o in BLOCK {
            let y = s * a;
            m.l[o] += y * gl;
            m.r[o] += y * gr;
            m.send_l[o] += y * gl * 0.5;
            m.send_r[o] += y * gr * 0.5;
            let c2 = c * cw - s * sw;
            s = s * cw + c * sw;
            c = c2;
            a += da;
        }
    }
}

// --- the hall -------------------------------------------------------------------------
// A feedback delay network: sixteen delay lines whose outputs are mixed by a
// Hadamard matrix and fed back, each through a low-pass, so the high notes
// die first as they do in a stone room. Each line's length sways a little,
// slowly, which keeps the tail from settling into the ringing tones a fixed
// network has. The two sides go in through their own diffusing all-passes
// after a pre-delay and come out of different lines. A shimmer feeds the
// hall's sound back in an octave up, for a halo that rises. The choir's bus
// goes through three band-passes, its vowel's formants, sliding between
// "oo", "oh" and "ah".

let LINES = 16;
let LINE_MAX = 8192;            // a power of two: positions wrap with a mask
let FDN_MS: f64[16] = [23.1, 27.7, 31.9, 36.7, 41.3, 45.1, 49.9, 54.7, 59.3, 64.1, 69.7, 75.1, 81.3, 87.7, 95.3, 103.9];
let SWAY_HZ: f64[16] = [0.21, 0.37, 0.29, 0.53, 0.17, 0.43, 0.31, 0.61, 0.23, 0.47, 0.39, 0.13, 0.57, 0.27, 0.49, 0.33];
let SWAY: f64 = 20.0;           // samples a line's length sways by
let DIFFUSE: i64[6] = [142, 379, 631, 167, 419, 701];
let PRE_MAX = 3200;
let SHIFT_MAX = 4096;
let SHIFT_LEN = 1600.0;         // the shimmer's grain, in samples

// The formants of "oo", "oh" and "ah", Hz, and their levels.
let VOWEL_F: f64[9] = [320.0, 800.0, 2500.0, 450.0, 850.0, 2600.0, 700.0, 1150.0, 2700.0];
let VOWEL_A: f64[9] = [1.0, 0.32, 0.07, 1.0, 0.42, 0.09, 1.0, 0.55, 0.13];
let VOWEL_BW: f64[3] = [80.0, 100.0, 140.0];

struct Hall {
    lines: f32[131072] = [0.0; 131072],     // LINES * LINE_MAX
    at: i64 = 0,                // where every line is written next
    len: f64[16] = [1.0; 16],   // each line's length, in samples
    sway: f64[16] = [0.0; 16],  // and its sway's cycles a loop
    delay: f64[16] = [1.0; 16], // its length now
    step: f64[16] = [0.0; 16],  // and how it changes each sample, across a block
    low: f64[16] = [0.0; 16],
    gain: f64[16] = [0.0; 16],
    damp: f64 = 0.5,
    ap: f32[6144] = [0.0; 6144],
    ap_at: i64[6] = [0; 6],
    pre: f32[6400] = [0.0; 6400],
    pre_len: i64 = 1,
    pre_at: i64 = 0,
    rumble_l: f64 = 0.0,        // the low end kept out of the hall, which would only boom
    rumble_r: f64 = 0.0,
    shift: f32[SHIFT_MAX] = [0.0; SHIFT_MAX],
    shift_at: i64 = 0,
    shift_cycles: i64 = 1,      // grains a loop
    shift_len: f64 = 1.0,       // a grain, in samples: the loop over shift_cycles
    shimmer: f64 = 0.0,
    shim_hp: f64 = 0.0,
    shim_lp: f64 = 0.0,
    shim_out: f64 = 0.0,
    // The choir: three band-passes' coefficients and states, and the right
    // side's short delay.
    vowel_cycles: f64 = 1.0,
    fb0: f64[3] = [0.0; 3],
    fa1: f64[3] = [0.0; 3],
    fa2: f64[3] = [0.0; 3],
    fgain: f64[3] = [0.0; 3],
    fx1: f64[3] = [0.0; 3],
    fx2: f64[3] = [0.0; 3],
    fy1: f64[3] = [0.0; 3],
    fy2: f64[3] = [0.0; 3],
    echo: f32[512] = [0.0; 512],
    echo_at: i64 = 0,
}

// A hall `size` times the usual, its tail dying by 60 dB in rt60 seconds,
// its walls soaking up what is above `damp` Hz.
fn hall_for(size: f64, rt60: f64, damp: f64, predelay: f64, shimmer: f64, period: i64) -> Hall {
    var h = Hall {};
    for k in LINES {
        h.len[k] = clamp(FDN_MS[k] * size * 0.001 * MUSIC_RATE, 64.0, LINE_MAX - SWAY - 4.0);
        h.delay[k] = h.len[k];
        h.gain[k] = pow(10.0, -3.0 * h.len[k] / (rt60 * MUSIC_RATE));
        h.sway[k] = max(1.0, round(SWAY_HZ[k] * period / MUSIC_RATE));
    }
    h.damp = lowpass_k(damp);
    h.pre_len = clamp((predelay * MUSIC_RATE) as! i64, 1, PRE_MAX - 1);
    h.shimmer = shimmer;
    h.shift_cycles = max(1, (period / SHIFT_LEN + 0.5) as! i64);
    h.shift_len = period as f64 / h.shift_cycles;
    h
}

// Sets each line's sway for the block starting at loop time j.
fn sway_lines(h: Hall&, j: i64, period: i64) {
    let p = period as f64;
    for k in LINES {
        let a = h.len[k] + SWAY * sin(TAU * h.sway[k] * (j % period) / p + k);
        let b = h.len[k] + SWAY * sin(TAU * h.sway[k] * ((j + BLOCK) % period) / p + k);
        h.delay[k] = a;
        h.step[k] = (b - a) / BLOCK;
    }
}

fn allpass(h: Hall&, k: i64, x: f64) -> f64 {
    let i = k * 1024 + h.ap_at[k];
    let d = h.ap[i] as f64;
    let w = x - 0.6 * d;
    h.ap[i] = w as f32;
    h.ap_at[k] = (h.ap_at[k] + 1) % DIFFUSE[k];
    d + 0.6 * w
}

// Reads the shimmer's buffer `d` samples back, between samples.
fn shift_read(h: Hall&, d: f64) -> f64 {
    let x = h.shift_at + SHIFT_MAX - d;
    let i = x as! i64;
    let f = x - i;
    let a = i % SHIFT_MAX;
    let b = (a + 1) % SHIFT_MAX;
    h.shift[a] * (1.0 - f) + h.shift[b] * f
}

// One sample through the hall: the sends in, the reverberation out. j is the
// sample's time in the loop.
fn reverb(h: Hall&, xl: f64, xr: f64, j: i64, period: i64) -> f64, f64 {
    let pl = h.pre[2 * h.pre_at] as f64;
    let pr = h.pre[2 * h.pre_at + 1] as f64;
    h.pre[2 * h.pre_at] = xl as f32;
    h.pre[2 * h.pre_at + 1] = xr as f32;
    h.pre_at = (h.pre_at + 1) % h.pre_len;
    h.rumble_l += (pl - h.rumble_l) * 0.024;
    h.rumble_r += (pr - h.rumble_r) * 0.024;
    let dl = allpass(h, 2, allpass(h, 1, allpass(h, 0, pl - h.rumble_l))) + h.shim_out;
    let dr = allpass(h, 5, allpass(h, 4, allpass(h, 3, pr - h.rumble_r))) + h.shim_out;
    // Each line read between samples, its length swaying.
    var z: f64[16] = [0.0; 16];
    var ol = 0.0;
    var or = 0.0;
    for k in LINES {
        let x = (h.at + LINE_MAX) as f64 - h.delay[k];
        let i = x as! i64;
        let f = x - i;
        let base = k * LINE_MAX;
        let y = h.lines[base + (i & (LINE_MAX - 1))] * (1.0 - f) + h.lines[base + ((i + 1) & (LINE_MAX - 1))] * f;
        h.delay[k] += h.step[k];
        let sign = if k & 2 == 0 { 1.0 } else { -1.0 };
        if k % 2 == 0 { ol += y * sign; } else { or += y * sign; }
        h.low[k] += (y - h.low[k]) * h.damp;
        z[k] = h.low[k] * h.gain[k];
    }
    // The Hadamard matrix, in four butterflies.
    var span = 1;
    while span < LINES {
        for k in LINES {
            if k & span != 0 { continue; }
            let a = z[k];
            let b = z[k + span];
            z[k] = a + b;
            z[k + span] = a - b;
        }
        span *= 2;
    }
    let w = h.at & (LINE_MAX - 1);
    for k in LINES {
        h.lines[k * LINE_MAX + w] = (z[k] * 0.25 + (if k % 2 == 0 { dl } else { dr }) * 0.35) as f32;
    }
    h.at++;
    if h.shimmer > 0.0 {
        // An octave up: two read heads sweep through the buffer twice as
        // fast as it fills, crossfading so each is heard away from its jump.
        h.shift[h.shift_at] = ((ol + or) * 0.2) as f32;
        let ph = (j % period * h.shift_cycles % period) as f64 / period;
        let ph2 = if ph < 0.5 { ph + 0.5 } else { ph - 0.5 };
        let wa = 1.0 - abs(2.0 * ph - 1.0);
        let up = shift_read(h, h.shift_len * (1.0 - ph) + 2.0) * wa + shift_read(h, h.shift_len * (1.0 - ph2) + 2.0) * (1.0 - wa);
        h.shift_at = (h.shift_at + 1) % SHIFT_MAX;
        h.shim_lp += (up - h.shim_lp) * 0.45;
        h.shim_hp += (h.shim_lp - h.shim_hp) * 0.08;
        h.shim_out = (h.shim_lp - h.shim_hp) * h.shimmer;
    }
    return ol * 0.4, or * 0.4;
}

// Readies the hall for the block starting at loop time j.
fn hall_block(h: Hall&, j: i64, period: i64) {
    set_vowel(h, j, period);
    sway_lines(h, j, period);
}

// Sets the choir's formants for the block starting at loop time j.
fn set_vowel(h: Hall&, j: i64, period: i64) {
    // 0 is "oo", 1 "oh", 2 "ah": a slow sway through them and back.
    let v = (1.0 - cos(TAU * h.vowel_cycles * j / period)) ;
    let i = min(1, floor(v) as! i64);
    let f = v - i;
    for k in 3 {
        let hz = VOWEL_F[i * 3 + k] * (1.0 - f) + VOWEL_F[i * 3 + 3 + k] * f;
        let a = VOWEL_A[i * 3 + k] * (1.0 - f) + VOWEL_A[i * 3 + 3 + k] * f;
        let w = TAU * hz / MUSIC_RATE;
        let alpha = sin(w) * VOWEL_BW[k] / (2.0 * hz);
        let a0 = 1.0 + alpha;
        h.fb0[k] = alpha / a0;
        h.fa1[k] = -2.0 * cos(w) / a0;
        h.fa2[k] = (1.0 - alpha) / a0;
        h.fgain[k] = a;
    }
}

// The choir's bus through its vowel; the right side a moment later, for width.
fn sing(h: Hall&, x: f64) -> f64, f64 {
    var y = 0.0;
    for k in 3 {
        let o = h.fb0[k] * (x - h.fx2[k]) - h.fa1[k] * h.fy1[k] - h.fa2[k] * h.fy2[k];
        h.fx2[k] = h.fx1[k];
        h.fx1[k] = x;
        h.fy2[k] = h.fy1[k];
        h.fy1[k] = o;
        y += o * h.fgain[k];
    }
    let late = h.echo[h.echo_at] as f64;
    h.echo[h.echo_at] = y as f32;
    h.echo_at = (h.echo_at + 1) % 397;
    return y, late;
}
