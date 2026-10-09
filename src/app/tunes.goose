// The background music: a piece for each room, written out as a score and
// played on recorded instruments (bank.goose, voices.goose) when it is first
// needed. A piece is a few parts over a chord progression, in the room's own
// mode and meter: a melody and a countermelody written note by note, harp or
// dulcimer patterns that follow the chords, strings or a choir holding them,
// and the room's colors (singing bowls, glass, a drone, swells that rise into
// a new phrase). Each phrase's tempo breathes, broadening into its ends, the
// level swells and recedes bar by bar, and every note is placed and weighed
// by a player's hand rather than a clock's.
//
// A loop is one period of an endlessly repeating performance: what still
// sounds at the loop's end sounds again at its start, and the hall plays for
// WARM seconds before the part that is kept, so its tail from the end is
// there at the start. tune_step does the work a slice at a time (see
// main.goose's step_jobs), in stereo.
//
// No audio here, so the tests can render a loop: music.goose plays them.

import std;
import math;
import os;
import .bank;
import .voices;

let MUSIC_ROOMS = 6;
let WARM: f64 = 12.0;           // seconds played before the loop; no note rings longer
let LOOP_SECONDS = 130;         // the longest a loop may be
let LOOP_SAMPLES = LOOP_SECONDS * MUSIC_RATE * 2;   // its samples, left and right
let TARGET_RMS: f64 = 0.089;    // -21 dBFS
let PEAK_LIMIT: f64 = 0.85;

// --- the score ------------------------------------------------------------------------
//
// A part's notes are words: a note name and octave with its length in beats
// (`d5:1.5`, `f#4:2`, `bb3:1/3`), a rest (`r:2`, or `r*4` for four bars),
// a bar line `|` (each bar must add up), dynamics (`pp p mp mf f`), slurs
// around legato notes (`(a4:1 d5 e5)`), and `_` after a note tied to the
// next. A length carries over to the notes after it.
//
// Chords are written a bar at a time (`Dm | G/D | Asus4:2 A:1 |`): a root,
// a quality (m 5 sus2 sus4 add9 madd9 6 m6 7 m7 maj7 dim m7b5), a bass.
// A pattern names chord tones counted up from the chord's bass above the
// part's lowest note: 0 the bass, 1 the next chord tone up, and so on; `.`
// is a rest, `!` an accent, `+` plays two at once.

let LINE = 0;                   // its notes, written out
let ARP = 1;                    // patterns over the chords: `notes` holds them, a; b; c..., `plan` picks one a bar
let PAD = 2;                    // the chords, held, voiced close above `lo`
let BASS = 3;                   // each chord's bass

struct Part {
    inst: i64,
    kind: i64 = LINE,
    notes: const u8[:] = "",
    plan: const u8[:] = "",     // ARP, PAD, BASS: a letter a bar (a pattern, or x to play), - to rest
    lo: i64 = 48,               // ARP, PAD, BASS: its lowest note
    vel: f64 = 0.7,
    pan: f64 = 0.0,
    step: f64 = 0.5,            // ARP: beats a step
    ring: f64 = 3.0,            // plucked and struck notes: beats they ring
    attack: f64 = 0.0,          // held notes: seconds more to swell in
    swell: f64 = 0.0,           // held notes: how much each grows to its middle and recedes
    reverse: bool = false,      // LINE: each note played backwards into the time it is written at
    jitter: f64 = 0.012,        // seconds its timing may stray
}

struct Piece {
    bpm: f64,
    beats: i64,                 // a bar
    bars: i64,
    phrase: i64 = 4,            // bars a phrase: the tempo breathes over each
    rubato: f64 = 0.06,
    chords: const u8[:],
    dynamics: const u8[:],      // a digit a bar, 1 to 9
    parts: Part[..12],
    drone: i64 = 0,             // its root (MIDI), or none
    drone_vel: f64 = 0.0,
    // The hall.
    size: f64 = 1.0,
    rt60: f64 = 3.0,
    damp: f64 = 5000.0,
    predelay: f64 = 0.03,
    wet: f64 = 0.35,
    shimmer: f64 = 0.0,
    vowels: f64 = 1.0,          // the choir's sways through its vowels, a loop
    seed: u64,
}

fn piece(room: i64) -> Piece {
    match room {
        // Frost cellar: a glass harmonica's slow tune over high harp, answered
        // by a bowed psaltery, a choir in the middle, a halo of shimmer. E minor,
        // whose C chords are Lydian.
        1 => Piece {
            bpm: 52.0, beats: 4, bars: 24, rubato: 0.07, seed: 211,
            chords: """
                Emadd9 | Cmaj7 | Emadd9 | Dsus2 |
                Em | Cmaj7 | G | D | Em | Cmaj7 | Am7 | Bsus4:2 B:2 |
                C | G/B | Am | Em | C | D | Bsus4:2 B:2 | Em |
                Emadd9 | Cmaj7 | Emadd9 | Dsus2 |
                """,
            dynamics: "3334 44555566 55677765 4333",
            parts: [
                Part { inst: GLASS, vel: 0.7, pan: -0.1, swell: 0.5, jitter: 0.02, notes: """
                    r*4 |
                    mp (e5:2 f#5:1 g5:1) | b5:3 a5:1 | (g5:2 d5:2) | f#5:4 |
                    (e5:2 f#5:1 g5:1) | (b5:2 c6:1 b5:1) | (a5:2 g5:1 e5:1) | (f#5:2 e5:1 d#5:1) |
                    mf (c6:2 b5:1 g5:1) | d6:4 | r:4 | r:4 |
                    (g5:2 a5:1 b5:1) | (a5:2 f#5:2) | (e5:2 d#5:2) | e5:4 |
                    r*4 |
                    """ },
                Part { inst: PSALTERY, vel: 0.7, pan: 0.35, swell: 0.6, attack: 0.3, jitter: 0.02, notes: """
                    r*12 |
                    r:4 | r:4 | mp (a5:2 c6:1 e6:1) | b5:4 |
                    r:4 | r:4 | b5:4 | g5:4 |
                    p b5:4 | r*3 |
                    """ },
                Part { inst: HARP, kind: ARP, lo: 64, vel: 0.42, ring: 4.0, notes: ". 0 . 2 . 4 3 . ; 4 . 2 . . 3 . . ; 0 . . . 2 . . .",
                       plan: "abab cbcbcbcb abababab abab" },
                Part { inst: HARP, reverse: true, vel: 0.5, pan: 0.2, notes: """
                    r:4 | r:4 | r:4 | r:2 e5:2 |
                    r*7 | r:2 b5:2 |
                    r*7 | r:2 e5:2 |
                    r*4 |
                    """ },
                Part { inst: CHOIR, kind: PAD, lo: 52, vel: 0.55, attack: 2.0, plan: "---- -------- xxxxxxxx ----" },
                Part { inst: BOWL, vel: 0.5, ring: 16.0, pan: -0.3, notes: """
                    r*2 | e4:4 | r*9 | b3:4 | r*7 | e4:4 | r*3 |
                    """ },
            ],
            drone: 40, drone_vel: 0.02,
            size: 1.35, rt60: 5.5, damp: 6500.0, predelay: 0.045, wet: 0.5, shimmer: 0.28, vowels: 1.0,
        },
        // Glassworks: a dulcimer's busy pattern, three and three and two,
        // under a violin's reel-like tune; a cello answers in the middle.
        // A Dorian.
        2 => Piece {
            bpm: 84.0, beats: 4, bars: 36, rubato: 0.035, seed: 307,
            chords: """
                Am | G | Am | G |
                Am | G | Am | Em | Am | G | D/F# | Am |
                Am | G | Am | Em | Am | G | D/F# | Am |
                C | G | D | Am | C | G | D | Esus4:2 E:2 |
                Am | G | Am | Em |
                Am | G | Am | G |
                """,
            dynamics: "4444 55555566 66666677 77888876 6655 5444",
            parts: [
                Part { inst: VIOLIN, vel: 0.72, pan: 0.25, jitter: 0.01, notes: """
                    r*4 |
                    mf (a4:1 c5:0.5 e5:0.5 a5:1 g5:0.5 e5:0.5) | (d5:1 g5:1 b5:1 a5:0.5 g5:0.5) | (e5:1.5 d5:0.5 c5:1 a4:1) | b4:3 r:1 |
                    (a4:1 c5:0.5 e5:0.5 a5:1 b5:0.5 c6:0.5) | (d6:1.5 b5:0.5 g5:1 a5:0.5 b5:0.5) | (a5:1 f#5:1 d5:1 e5:0.5 f#5:0.5) | e5:2 a4:2 |
                    (a4:1 c5:0.5 e5:0.5 a5:1 g5:0.5 e5:0.5) | (d5:1 g5:1 b5:1 a5:0.5 g5:0.5) | (e5:1.5 d5:0.5 c5:1 a4:1) | b4:3 r:1 |
                    (a4:1 c5:0.5 e5:0.5 a5:1 b5:0.5 c6:0.5) | (d6:1.5 b5:0.5 g5:1 a5:0.5 b5:0.5) | (a5:1 f#5:1 d5:1 e5:0.5 f#5:0.5) | (e5:1 c5:1 a4:2) |
                    p e6:4 | d6:4 | a5:4 | c6:4 | e6:4 | d6:4 | a5:4 | (b5:2 g#5:2) |
                    mf (a4:1 c5:0.5 e5:0.5 a5:1 g5:0.5 e5:0.5) | (d5:1 g5:1 b5:1 a5:0.5 g5:0.5) | (e5:1.5 d5:0.5 c5:1 a4:1) | b4:4 |
                    r*4 |
                    """ },
                Part { inst: CELLO, vel: 0.62, pan: -0.25, swell: 0.3, jitter: 0.015, notes: """
                    r*12 |
                    p (c4:2 b3:1 a3:1) | (b3:2 d4:2) | (c4:2 e4:2) | b3:4 | (c4:2 b3:1 a3:1) | (b3:1 d4:1 g4:2) | (f#4:2 a4:2) | e4:4 |
                    mf (g4:1.5 e4:0.5 c4:2) | (d4:1.5 b3:0.5 g3:2) | (a3:1 d4:1 f#4:1 a4:1) | (g4:2 e4:2) |
                    (g4:1.5 e4:0.5 c4:2) | (d4:1 b3:1 d4:1 g4:1) | (f#4:2 a4:1 f#4:1) | (e4:2 g#4:2) |
                    p a2:4 | g2:4 | a2:4 | e2:4 |
                    r*4 |
                    """ },
                Part { inst: DULCIMER, kind: ARP, lo: 50, vel: 0.68, pan: 0.15, ring: 2.0, jitter: 0.006,
                       notes: "0! 2 4 2! . 4 3! 4 ; 0! 3 2 3! 4 3 2! 3 ; 0! . 4 2! . 4 3! .",
                       plan: "aaaa aaaaaaaa aaaaaaaa bbbbbbbb cccc aaaa" },
                Part { inst: HARP, kind: ARP, lo: 36, vel: 0.48, ring: 3.0, jitter: 0.006,
                       notes: "0! . . 0 . . 2 .", plan: "---- aaaaaaaa aaaaaaaa aaaaaaaa aaaa ----" },
                Part { inst: STRINGS, kind: PAD, lo: 57, vel: 0.42, attack: 0.8, swell: 0.4,
                       plan: "---- -------- xxxxxxxx xxxxxxxx ---- ----" },
            ],
            size: 0.9, rt60: 2.0, damp: 6000.0, predelay: 0.02, wet: 0.25,
        },
        // Observatory: strings holding wide chords, a cello's tune and then a
        // violin's, soaring, stars of harp, a choir, the shimmer. D Lydian,
        // whose bright second chord is the sound of wonder.
        3 => Piece {
            bpm: 54.0, beats: 4, bars: 28, rubato: 0.07, seed: 401,
            chords: """
                D | E/D | D | E/D |
                D | E/D | F#m | Bm | A | E | Bm | E |
                D | E/D | F#m | Bm | D | E/D | A/C# | Bm |
                Bm | E | F#m | E |
                D | E/D | D | E/D |
                """,
            dynamics: "3344 44556655 55667766 7887 5433",
            parts: [
                Part { inst: CELLO, vel: 0.7, pan: -0.25, swell: 0.5, jitter: 0.02, notes: """
                    r*4 |
                    mp (a3:3 b3:1) | (d4:1 e4:1 g#4:2) | (a4:3 f#4:1) | (f#4:2 e4:1 d4:1) | (c#4:2 e4:2) | b3:4 | (d4:2 f#4:1 e4:1) | e4:4 |
                    p d3:4 | d3:4 | c#3:4 | b2:4 | d3:4 | d3:4 | c#3:4 | b2:2 a2:2 |
                    mf (b2:2 d3:2) | e3:4 | (f#3:2 a3:2) | e3:4 |
                    r*4 |
                    """ },
                Part { inst: VIOLIN, vel: 0.68, pan: 0.25, swell: 0.4, jitter: 0.02, notes: """
                    r*12 |
                    mp (f#5:2 a5:2) | (g#5:3 b5:1) | (c#6:2 a5:2) | b5:4 | (d6:2 c#6:1 a5:1) | (b5:2 g#5:2) | (a5:2 e5:2) | f#5:4 |
                    mf (d6:2 e6:2) | e6:4 | (c#6:2 a5:2) | b5:4 |
                    r*4 |
                    """ },
                Part { inst: PSALTERY, vel: 0.5, pan: 0.4, swell: 0.6, attack: 0.4, jitter: 0.02, notes: """
                    r*20 |
                    (d6:2 e6:2) | e6:4 | (c#6:2 a5:2) | b5:4 |
                    p f#5:4 | g#5:4 | a5:4 | b5:4 |
                    """ },
                Part { inst: GLASS, vel: 0.7, pan: -0.35, swell: 0.6, notes: """
                    p a5:4 | g#5:4 | f#5:4 | g#5:4 | r*24 |
                    """ },
                Part { inst: HARP, kind: ARP, lo: 55, vel: 0.38, ring: 4.0, notes: "4 . . 2 . 5 . . ; . 3 . . 6 . 4 . ; 6 . . . . 4 . .",
                       plan: "abab cbcacbca abababab abab abac" },
                Part { inst: HARP, reverse: true, vel: 0.5, pan: 0.3, notes: """
                    r*11 | r:2 e6:2 | r*7 | r:2 b5:2 | r*7 | r:2 a5:2 |
                    """ },
                Part { inst: STRINGS, kind: PAD, lo: 62, vel: 0.36, attack: 3.0, swell: 0.7, plan: "xxxx xxxxxxxx xxxxxxxx xxxx xxxx" },
                Part { inst: CHOIR, kind: PAD, lo: 50, vel: 0.5, attack: 2.5, plan: "---- xxxxxxxx xxxxxxxx xxxx ----" },
                Part { inst: BOWL, vel: 0.45, ring: 16.0, pan: 0.2, notes: "r*2 | d4:4 | r*9 | a3:4 | r*11 | d4:4 | r*3 |" },
            ],
            drone: 38, drone_vel: 0.028,
            size: 1.5, rt60: 6.0, damp: 5500.0, predelay: 0.05, wet: 0.5, shimmer: 0.3, vowels: 1.0,
        },
        // Greenhouse: a flute's lilting tune in six-eight over a rolling harp,
        // a violin answering, and in the middle a turn to the flattened
        // seventh's chord. G major, with Mixolydian moments.
        4 => Piece {
            bpm: 156.0, beats: 6, bars: 40, rubato: 0.05, seed: 503,
            chords: """
                G | C/G | G | D |
                G | C | G | D | Em | C | D | G |
                G | C | G | D | Em | C | D | G |
                F | C | G | G | F | C | Am | D |
                G | C | G | D | Em | C | D | G |
                G | C/G | G | D |
                """,
            dynamics: "3344 44445555 55556666 66777766 55554444 4433",
            parts: [
                Part { inst: FLUTE, vel: 0.72, pan: 0.15, jitter: 0.012, notes: """
                    r*4 |
                    mp (b4:2 c5:1 d5:2 g5:1) | (e5:3 d5:2 c5:1) | (b4:2 a4:1 g4:2 b4:1) | a4:6 |
                    (b4:2 c5:1 d5:2 e5:1) | (g5:3 e5:2 d5:1) | (c5:2 b4:1 a4:2 f#4:1) | g4:6 |
                    (b4:2 c5:1 d5:2 g5:1) | (e5:3 d5:2 c5:1) | (b4:2 a4:1 g4:2 b4:1) | a4:6 |
                    (b4:2 c5:1 d5:2 e5:1) | (g5:3 a5:2 b5:1) | (a5:2 g5:1 f#5:2 d5:1) | g5:6 |
                    r*8 |
                    (b4:2 c5:1 d5:2 g5:1) | (e5:3 d5:2 c5:1) | (b4:2 a4:1 g4:2 b4:1) | a4:6 |
                    (b4:2 c5:1 d5:2 e5:1) | (g5:3 e5:2 d5:1) | (c5:2 b4:1 a4:2 f#4:1) | g4:6 |
                    r*4 |
                    """ },
                Part { inst: VIOLIN, vel: 0.62, pan: 0.3, swell: 0.4, jitter: 0.015, notes: """
                    r*12 |
                    p g4:6 | (g4:3 e4:3) | d4:6 | (f#4:3 d4:3) | e4:6 | (e4:3 c5:3) | (d5:3 c5:3) | b4:6 |
                    mf (a4:2 c5:1 f5:3) | (e5:2 d5:1 c5:3) | (d5:2 b4:1 g4:3) | d5:6 |
                    (c5:2 d5:1 f5:2 a5:1) | (g5:3 e5:3) | (e5:2 d5:1 c5:2 a4:1) | (f#5:3 a5:3) |
                    p g4:6 | (g4:3 e4:3) | d4:6 | (f#4:3 d4:3) | e4:6 | (e4:3 c5:3) | (d5:3 c5:3) | b4:6 |
                    r*4 |
                    """ },
                Part { inst: HARP, kind: ARP, lo: 43, vel: 0.45, step: 1.0, ring: 6.0,
                       notes: "0 2 3 4 3 2 ; 0 3 4 5 4 3 ; 0 . 3 . 4 .",
                       plan: "aaaa aaaaaaaa aaaaaaaa bbbbbbbb aaaaaaaa aaaa" },
                Part { inst: CELLO, kind: BASS, lo: 36, vel: 0.45, attack: 0.3, swell: 0.3,
                       plan: "---- -------- xxxxxxxx xxxxxxxx xxxxxxxx ----" },
                Part { inst: STRINGS, kind: PAD, lo: 55, vel: 0.38, attack: 1.2, swell: 0.4,
                       plan: "---- -------- -------- xxxxxxxx xxxxxxxx ----" },
            ],
            size: 1.0, rt60: 2.4, damp: 5500.0, predelay: 0.025, wet: 0.3,
        },
        // Athanor: a ritual. The drone and the bowls keep time with a low harp,
        // a cello sings low in E Phrygian, the psaltery answers high, a choir
        // gathers, and the strings come in for the height of it.
        5 => Piece {
            bpm: 58.0, beats: 4, bars: 28, rubato: 0.04, seed: 601,
            chords: """
                Em | F/E | Em | F/E |
                Em | F | Em | Dm | Em | F | G | Em |
                Am | F | Em | Em | Am | F | Dm | Em |
                F | G | F | Em |
                Em | F/E | Em | F/E |
                """,
            dynamics: "4444 44555566 55666677 8887 5444",
            parts: [
                Part { inst: CELLO, vel: 0.72, pan: -0.2, swell: 0.4, jitter: 0.02, notes: """
                    r*4 |
                    mp (e3:2 f3:1 g3:1) | (a3:3 g3:1) | (f3:2 e3:2) | d3:4 | (e3:1 g3:1 b3:2) | (c4:2 b3:1 a3:1) | (d4:2 c4:1 b3:1) | e3:4 |
                    p a2:4 | f2:4 | e2:4 | (e2:2 f2:2) | a2:4 | f2:4 | d2:4 | e2:4 |
                    mf (a3:2 c4:2) | (d4:2 b3:2) | (c4:3 a3:1) | b3:4 |
                    r*4 |
                    """ },
                Part { inst: PSALTERY, vel: 0.6, pan: 0.35, swell: 0.5, attack: 0.2, jitter: 0.02, notes: """
                    r*12 |
                    mp (e5:2 a5:2) | (c6:3 a5:1) | (b5:2 g5:1 f5:1) | e5:4 | (a5:2 c6:2) | (a5:2 f5:2) | (d6:2 c6:1 a5:1) | b5:4 |
                    mf c6:4 | b5:4 | a5:4 | (g5:2 e5:2) |
                    r*4 |
                    """ },
                Part { inst: HARP, kind: ARP, lo: 40, vel: 0.6, ring: 3.0, jitter: 0.005,
                       notes: "0! . . 0 . . 2 . ; 0! . . 0 . . . .", plan: "bbbb aaaaaaaa aaaaaaaa aaaa bbbb" },
                Part { inst: HARP, reverse: true, vel: 0.55, pan: -0.2, notes: """
                    r*11 | r:2 e4:2 | r*7 | r:2 a4:2 | r*3 | r:2 e4:2 | r*4 |
                    """ },
                Part { inst: CHOIR, kind: PAD, lo: 45, vel: 0.55, attack: 2.5, plan: "---- -------- xxxxxxxx xxxx ----" },
                Part { inst: STRINGS, kind: PAD, lo: 52, vel: 0.45, attack: 1.5, swell: 0.6, plan: "---- -------- -------- xxxx ----" },
                Part { inst: BOWL, vel: 0.38, ring: 16.0, pan: 0.25, notes: """
                    e4:4 | b3:4 | e4:4 | b3:4 |
                    e4:4 | r:4 | b3:4 | r:4 | e4:4 | r:4 | b3:4 | r:4 |
                    e4:4 | r:4 | b3:4 | r:4 | e4:4 | r:4 | b3:4 | r:4 |
                    e4:4 | r:4 | b3:4 | r:4 |
                    e4:4 | b3:4 | e4:4 | b3:4 |
                    """ },
            ],
            drone: 40, drone_vel: 0.045,
            size: 1.3, rt60: 4.5, damp: 4000.0, predelay: 0.035, wet: 0.42, vowels: 2.0,
        },
        // Apothecary: a slow waltz in D Dorian. A harp rolls under a fiddle's
        // tune; the second time a cello answers it; then a turn to F, the
        // strings swelling; then the cello takes the tune under a high descant.
        _ => Piece {
            bpm: 66.0, beats: 3, bars: 40, rubato: 0.06, seed: 101,
            chords: """
                Dm | G/D | Dm | C |
                Dm | C | Am | G | Dm | F | C | Dm |
                Dm | C | Am | G | Dm | F | C | Dm |
                F | C | Dm | Am | G | Dm/F | Em | Asus4:2 A:1 |
                Dm | C | Am | G | Dm | F | C | Dm |
                Dm | G/D | Dm | C |
                """,
            dynamics: "3333 44444455 55555566 66778876 66555544 4333",
            parts: [
                Part { inst: VIOLIN, vel: 0.7, pan: 0.25, swell: 0.3, jitter: 0.015, notes: """
                    r*4 |
                    mp (a4:1 d5 e5) | (f5:2 e5:1) | (d5:1.5 c5:0.5 a4:1) | b4:3 | (a4:1 d5 e5) | (f5 g5 a5) | (g5:1.5 f5:0.5 e5:1) | d5:3 |
                    (a4:1 d5 e5) | (f5:2 e5:1) | (d5:1.5 c5:0.5 a4:1) | b4:3 | (a4:1 d5 e5) | (f5 g5 a5) | (g5:1.5 f5:0.5 e5:1) | (d5:2 f5:1) |
                    mf (a5:2 c6:1) | (g5:2 e5:1) | (f5:1.5 e5:0.5 d5:1) | e5:3 | (d5:1 e5:1 g5:1) | (a5:2 f5:1) | (g5:1.5 f5:0.5 e5:1) | (e5:2 c#5:1) |
                    p a5:3 | (a5:2 g5:1) | e5:3 | d5:3 | f5:3 | (a5:2 c6:1) | (b5:2 g5:1) | a5:3 |
                    pp (a4:1 d5 e5) | f5:3 | r*2 |
                    """ },
                Part { inst: CELLO, vel: 0.66, pan: -0.25, swell: 0.4, jitter: 0.02, notes: """
                    r*12 |
                    mp d3:3 | (c3:2 e3:1) | (a2:1.5 b2:0.5 c3:1) | (d3:2 b2:1) | f3:3 | (c4:2 a3:1) | (g3:1.5 f3:0.5 e3:1) | d3:3 |
                    c4:3 | (c4:2 b3:1) | a3:3 | (a3:2 g3:1) | (g3:2 b3:1) | (a3:2 d4:1) | (b3:1.5 a3:0.5 g3:1) | (a3:2 e3:1) |
                    mf (a3:1 d4 e4) | (f4:2 e4:1) | (d4:1.5 c4:0.5 a3:1) | b3:3 | (a3:1 d4 e4) | (f4 g4 a4) | (g4:1.5 f4:0.5 e4:1) | d4:3 |
                    r*4 |
                    """ },
                Part { inst: HARP, kind: ARP, lo: 36, vel: 0.45, ring: 3.0,
                       notes: "0 2 3 4 3 2 ; 0 2 4 5 6 5 ; 0 . 3 . 4 .",
                       plan: "cccc aaaaaaaa aaaaaaaa bbbbbbbb aaaaaaaa cccc" },
                Part { inst: STRINGS, kind: PAD, lo: 57, vel: 0.4, attack: 1.0, swell: 0.5,
                       plan: "---- -------- -------- xxxxxxxx xxxxxxxx ----" },
                Part { inst: BOWL, vel: 0.4, ring: 12.0, pan: -0.3, notes: "r*2 | d4:3 | r*17 | a3:3 | r*15 | d4:3 | r*3 |" },
            ],
            size: 1.0, rt60: 2.6, damp: 5000.0, predelay: 0.025, wet: 0.32,
        },
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

// --- reading the score ----------------------------------------------------------------

// A note name (c4, f#3, bb5) as a MIDI number; false if `t` isn't one.
fn note_midi(t: const u8[:]) -> i64, bool {
    guard t.len >= 2 && t[0] >= 'a' && t[0] <= 'g' else { return 0, false; }
    let names: i64[7] = [9, 11, 0, 2, 4, 5, 7];
    var m = names[(t[0] - 'a') as i64];
    var i = 1;
    if t[1] == '#' { m++; i++; }
    else if t[1] == 'b' && t.len > 2 { m--; i++; }
    let octave, ok = parse_int(t[i..]);
    guard ok else { return 0, false; }
    return m + 12 * (octave + 1), true;
}

// A length in beats: 1.5, or 1/3.
fn beats_of(t: const u8[:]) -> f64, bool {
    let slash = find(t, "/");
    if slash < 0 { return parse_flt(t); }
    let a, oka = parse_flt(t[..slash]);
    let b, okb = parse_flt(t[slash + 1..]);
    guard oka && okb && b > 0.0 else { return 0.0, false; }
    return a / b, true;
}

// A chord: when it begins and how long it lasts, in beats, and its pitch
// classes counted up from its bass, the bass first.
struct Chord {
    at: f64 = 0.0,
    len: f64 = 0.0,
    root: i64 = 0,
    bass: i64 = 0,
    tones: i64[..6] = [],
    foreign: bool = false,      // the bass isn't one of the chord's own tones
}

fn pitch_class(t: const u8[:]) -> i64, i64 {
    let names: i64[7] = [9, 11, 0, 2, 4, 5, 7];
    guard t.len >= 1 && t[0] >= 'A' && t[0] <= 'G' else { return -1, 0; }
    var pc = names[(t[0] - 'A') as i64];
    var used = 1;
    if t.len > 1 && t[1] == '#' { pc++; used++; }
    else if t.len > 1 && t[1] == 'b' { pc--; used++; }
    return pc % 12, used;
}

fn read_chord(t: const u8[:]) -> Chord, bool {
    var c = Chord {};
    let root, used = pitch_class(t);
    guard root >= 0 else { return c, false; }
    var rest = t[used..];
    var bass = root;
    let slash = find(rest, "/");
    if slash >= 0 {
        let b, bu = pitch_class(rest[slash + 1..]);
        guard b >= 0 && bu == rest.len - slash - 1 else { return c, false; }
        bass = b;
        rest = rest[..slash];
    }
    var steps: i64[..6] = [];
    if rest == "" { steps = [0, 4, 7]; }
    else if rest == "m" { steps = [0, 3, 7]; }
    else if rest == "5" { steps = [0, 7]; }
    else if rest == "sus2" { steps = [0, 2, 7]; }
    else if rest == "sus4" { steps = [0, 5, 7]; }
    else if rest == "add9" { steps = [0, 2, 4, 7]; }
    else if rest == "madd9" { steps = [0, 2, 3, 7]; }
    else if rest == "6" { steps = [0, 4, 7, 9]; }
    else if rest == "m6" { steps = [0, 3, 7, 9]; }
    else if rest == "7" { steps = [0, 4, 7, 10]; }
    else if rest == "m7" { steps = [0, 3, 7, 10]; }
    else if rest == "maj7" { steps = [0, 4, 7, 11]; }
    else if rest == "dim" { steps = [0, 3, 6]; }
    else if rest == "m7b5" { steps = [0, 3, 6, 10]; }
    else { return c, false; }
    c.root = root;
    c.bass = bass;
    // From the bass up: the bass, then the chord's tones above it in order.
    var offs: i64[..6] = [];
    for s in steps { offs.push((root + s - bass) % 12); }
    if !offs.contains(0) { offs.push(0); c.foreign = true; }
    sort(offs);
    for o in offs { c.tones.push((bass + o) % 12); }
    return c, true;
}

// Reads the chords of `p` into `out`; what is wrong goes to `errors`.
fn read_chords(p: Piece, out: Chord[>..]&, errors: u8[>..]&) {
    out.clear();
    var beat = 0.0;
    var bar_start = 0.0;
    var bar = 0;
    var open = 0;               // chords in this bar with no length, which share what is left of it
    for it in words(p.chords) {
        if it == "|" {
            if open > 0 {
                // The last `open` chords share the rest of the bar.
                let share = (bar_start + p.beats - beat) / open;
                var at = beat;
                for &c in out[out.len - open..] { c.at = at; c.len = share; at += share; }
                beat = at;
                open = 0;
            }
            if abs(beat - (bar_start + p.beats)) > 1e-6 { format(errors, "chords, bar ", bar + 1, ": ", beat - bar_start, " beats\n"); }
            bar++;
            bar_start = bar * p.beats;
            beat = bar_start;
        } else {
            let colon = find(it, ":");
            let name = if colon >= 0 { it[..colon] } else { it };
            var c, ok = read_chord(name);
            if !ok { format(errors, "chords, bar ", bar + 1, ": no chord ", it, "\n"); }
            c.at = beat;
            if colon >= 0 {
                let len, okl = beats_of(it[colon + 1..]);
                if !okl { format(errors, "chords, bar ", bar + 1, ": bad length ", it, "\n"); }
                c.len = len;
                beat += len;
            } else {
                open++;
            }
            out.push(c);
        }
    }
    if bar != p.bars { format(errors, "chords: ", bar, " bars, not ", p.bars, "\n"); }
}

fn chord_at(chords: const Chord[:], beat: f64) -> Chord {
    for c in chords { if beat < c.at + c.len - 1e-9 { return c; } }
    if chords.len > 0 { return chords[chords.len - 1]; }
    Chord {}
}

// The idx-th note up from the chord's bass, at or above lo.
fn ladder(c: Chord, lo: i64, idx: i64) -> i64 {
    let n = c.tones.len;
    let bass = lo + (c.bass - lo) % 12;
    let k = idx % n;
    bass + idx / n * 12 + (c.tones[k] - c.bass) % 12
}

// The letter of `plan` for bar b (spaces aside), or - past its end.
fn plan_at(plan: const u8[:], b: i64) -> u8 {
    var k = 0;
    for ch in plan {
        if ch == ' ' { continue; }
        if k == b { return ch; }
        k++;
    }
    '-'
}

fn plan_bars(plan: const u8[:]) -> i64 {
    var k = 0;
    for ch in plan { if ch != ' ' { k++; } }
    k
}

// --- the performance ------------------------------------------------------------------

// The sample beat b falls on. Each phrase breathes: slower into and out of
// its ends, a little faster in its middle, the same length overall.
fn when(p: Piece, b: f64) -> f64 {
    let spb = 60.0 / p.bpm * MUSIC_RATE;
    let span = (p.phrase * p.beats) as f64;
    (b + p.rubato * span / TAU * sin(TAU * b / span)) * spb
}

// The room's level at beat b, from the bar-by-bar dynamics, gliding from
// each bar's middle to the next (and from the last bar to the first).
fn level(p: Piece, b: f64) -> f64 {
    let bars = plan_bars(p.dynamics);
    if bars == 0 { return 1.0; }
    let x = b / p.beats - 0.5;
    let i = floor(x);
    let f = x - i;
    let d0 = (plan_at(p.dynamics, (i as! i64) % bars) - '0') as f64;
    let d1 = (plan_at(p.dynamics, (i as! i64 + 1) % bars) - '0') as f64;
    let d = d0 + (d1 - d0) * smooth(f);
    (0.25 + 0.075 * d) / 0.625
}

// A note as written, before it is performed.
struct Written { beat: f64, beats: f64, midi: i64, vel: f64, legato: bool }

struct Player {
    p: Piece,
    period: i64,
    beats: f64,                 // the loop's
    dice: rng,
}

// Where the pan of a note of `part` lies: a harp's or dulcimer's low strings
// to the left of its high ones.
fn pan_of(part: Part, midi: f64) -> f64 {
    if part.inst == HARP || part.inst == DULCIMER { return clamp(part.pan + (midi - 62.0) / 40.0 * 0.6, -0.8, 0.8); }
    part.pan
}

// Performs written note w of `part`: its time and weight given a player's
// give, its length its instrument's.
fn perform(pl: Player&, part: Part, w: Written, joined: bool, notes: Note[>..]&) {
    if w.beat >= pl.beats - 1e-9 { return; }
    let tb = TIMBRES[part.inst];
    let spb = 60.0 / pl.p.bpm * MUSIC_RATE;
    let late = (pl.dice.rand_flt() * 2.0 - 1.0) * part.jitter * MUSIC_RATE;
    let t0 = when(pl.p, w.beat) + late;
    let t1 = when(pl.p, w.beat + w.beats);
    var len = t1 - t0;
    if part.reverse {
        len = when(pl.p, w.beat + w.beats) - when(pl.p, w.beat);
    } else if !tb.held {
        len = max(len, part.ring * spb);
    } else if joined {
        len += 0.08 * MUSIC_RATE;       // into the next note, as a bow changes
    } else {
        len = max(0.12 * MUSIC_RATE, len - 0.04 * MUSIC_RATE);
    }
    len = min(len, (WARM - 2.0) * MUSIC_RATE);
    let vel = w.vel * level(pl.p, w.beat) * (0.94 + 0.12 * pl.dice.rand_flt());
    let start = if part.reverse { when(pl.p, w.beat) } else { t0 };
    notes.push(Note { start: (round(start) as! i64) % pl.period, len: round(len) as! i64, midi: w.midi as f64,
                      vel: clamp(vel, 0.03, 1.0), inst: part.inst, pan: pan_of(part, w.midi as f64),
                      attack: part.attack, swell: part.swell, legato: w.legato, reverse: part.reverse });
}

// A part's written notes, read from its score.
fn read_line(p: Piece, part: Part, line: Written[>..]&, errors: u8[>..]&, which: i64) {
    var beat = 0.0;
    var bar = 0;
    var bar_start = 0.0;
    var len = 1.0;
    var dyn = 1.0;
    var slur = false;
    var slur_first = false;
    var tie = false;
    for it in words(part.notes) {
        var t = it;
        if t == "|" {
            if abs(beat - bar_start - p.beats) > 1e-6 { format(errors, "part ", which, ", bar ", bar + 1, ": ", beat - bar_start, " beats\n"); }
            bar++;
            bar_start = bar * p.beats;
            beat = bar_start;
            continue;
        }
        if t == "pp" { dyn = 0.55; continue; }
        if t == "p" { dyn = 0.7; continue; }
        if t == "mp" { dyn = 0.85; continue; }
        if t == "mf" { dyn = 1.0; continue; }
        if t == "f" { dyn = 1.15; continue; }
        if t.len > 2 && t[0] == 'r' && t[1] == '*' {
            let n, ok = parse_int(t[2..]);
            if !ok || beat != bar_start { format(errors, "part ", which, ", bar ", bar + 1, ": bad ", t, "\n"); continue; }
            // n whole bars; the bar line after closes the last.
            bar += n - 1;
            bar_start = bar * p.beats;
            beat = bar_start + p.beats;
            continue;
        }
        var opens = false;
        var closes = false;
        var ties = false;
        if t.len > 0 && t[0] == '(' { opens = true; t = t[1..]; }
        if t.len > 0 && t[t.len - 1] == ')' { closes = true; t = t[..t.len - 1]; }
        if t.len > 0 && t[t.len - 1] == '_' { ties = true; t = t[..t.len - 1]; }
        let colon = find(t, ":");
        let name = if colon >= 0 { t[..colon] } else { t };
        if colon >= 0 {
            let b, ok = beats_of(t[colon + 1..]);
            if !ok || b <= 0.0 { format(errors, "part ", which, ", bar ", bar + 1, ": bad length ", it, "\n"); }
            else { len = b; }
        }
        if opens { slur = true; slur_first = true; }
        if name == "r" {
            beat += len;
        } else {
            let m, ok = note_midi(name);
            if !ok { format(errors, "part ", which, ", bar ", bar + 1, ": no note ", it, "\n"); }
            else if tie && line.len > 0 && line[line.len - 1].midi == m {
                line[line.len - 1].beats += len;
            } else {
                line.push(Written { beat: beat, beats: len, midi: m, vel: part.vel * dyn, legato: slur && !slur_first });
            }
            beat += len;
            slur_first = false;
        }
        tie = ties;
        if closes { slur = false; }
    }
    if bar != p.bars { format(errors, "part ", which, ": ", bar, " bars, not ", p.bars, "\n"); }
}

fn play_line(pl: Player&, part: Part, line: const Written[:], notes: Note[>..]&) {
    for w, i in line {
        let joined = i + 1 < line.len && line[i + 1].legato;
        perform(pl, part, w, joined, notes);
    }
}

fn play_arp(pl: Player&, part: Part, chords: const Chord[:], notes: Note[>..]&) {
    let patterns = split(part.notes, ';');
    let p = pl.p;
    let steps = (p.beats / part.step + 0.5) as! i64;
    for bar in p.bars {
        let ch = plan_at(part.plan, bar);
        if ch < 'a' || ch > 'z' { continue; }
        let k = (ch - 'a') as i64;
        if k >= patterns.len { continue; }
        let pattern = words(patterns[k]);
        if pattern.len == 0 { continue; }
        for s in steps {
            let tok = pattern[s % pattern.len];
            if tok == "." { continue; }
            let accent = tok[tok.len - 1] == '!';
            let body = if accent { tok[..tok.len - 1] } else { tok };
            let beat = bar * p.beats + s * part.step;
            let c = chord_at(chords, beat);
            let weight = if accent { 1.0 } else if s == 0 { 0.9 } else { 0.74 };
            var roll = 0.0;
            each_split(body, '+') {
                let idx, ok = parse_int(it);
                if ok {
                    // A chord is rolled, low to high, as a harpist's fingers do.
                    perform(pl, part, Written { beat: beat + roll, beats: part.step, midi: ladder(c, part.lo, idx),
                                                vel: part.vel * weight, legato: false }, false, notes);
                    roll += 0.03;
                }
            };
        }
    }
}

// The chord's own tones (not a bass from outside it) voiced close, in the
// inversion nearest the last voicing, or the lowest the first time.
fn voicing(c: Chord, lo: i64, last: const i64[:], out: i64[..4]&) {
    out.clear();
    var pcs: i64[..6] = [];
    for t in c.tones { if !(c.foreign && t == c.bass) { pcs.push(t); } }
    let n = min(4, pcs.len);
    var best = 1e9;
    for inv in n {
        // Each tone the next one up from the one before.
        var v: i64[..4] = [];
        var at = lo + (pcs[inv] - lo) % 12;
        for i in n {
            if i > 0 { at += 1 + (pcs[(inv + i) % pcs.len] - at - 1) % 12; }
            v.push(at);
        }
        var cost = 0.0;
        if last.len == n { for i in n { cost += abs(v[i] - last[i]) as f64; } }
        else { cost = (v[0] - lo) as f64; }
        if cost < best {
            best = cost;
            out.clear();
            for x in v { out.push(x); }
        }
    }
}

fn play_pad(pl: Player&, part: Part, chords: const Chord[:], notes: Note[>..]&) {
    let p = pl.p;
    var last: i64[..4] = [];
    var held: i64[4] = [-1; 4];         // the note each voice is holding, while it may go on
    var from: f64[4] = [0.0; 4];        // the beat it began on
    for c in chords {
        if c.at >= pl.beats - 1e-9 { break; }
        let bar = (c.at / p.beats + 1e-9) as! i64;
        if plan_at(part.plan, bar) == '-' {
            last.clear();
            held = [-1; 4];
            continue;
        }
        var v: i64[..4] = [];
        if part.kind == BASS { v.push(part.lo + (c.bass - part.lo) % 12); }
        else { voicing(c, part.lo, last, v); }
        for m, i in v {
            if held[i] >= 0 && notes[held[i]].midi == m as f64 && TIMBRES[part.inst].held {
                // A tone the chords share is held on, not played again.
                let n .= notes[held[i]];
                let end = min(when(p, c.at + c.len), when(p, from[i]) + (WARM - 2.0) * MUSIC_RATE);
                n.len = round(end - when(p, from[i])) as! i64;
                continue;
            }
            held[i] = notes.len;
            from[i] = c.at;
            perform(pl, part, Written { beat: c.at, beats: c.len, midi: m, vel: part.vel * (if i == 0 { 1.0 } else { 0.85 }), legato: false },
                    false, notes);
            if notes.len == held[i] { held[i] = -1; }
        }
        for i in v.len..4 { held[i] = -1; }
        last.clear();
        for m in v { last.push(m); }
    }
}

// Every note of piece p, cut to its first `bars` bars when that is fewer.
// What is wrong with the score goes to `errors`.
fn compose(p: Piece, bars: i64, notes: Note[>..]&, errors: u8[>..]&) -> i64 {
    notes.clear();
    var chords: Chord[>..] = [];
    read_chords(p, chords, errors);
    let n = if bars > 0 { min(bars, p.bars) } else { p.bars };
    let beats = (n * p.beats) as f64;
    var pl = Player { p: p, period: round(when(p, beats)) as! i64, beats: beats, dice: rng { p.seed } };
    if plan_bars(p.dynamics) != p.bars { format(errors, "dynamics: ", plan_bars(p.dynamics), " bars, not ", p.bars, "\n"); }
    for part, k in p.parts {
        if part.kind == LINE {
            var line: Written[>..] = [];
            read_line(p, part, line, errors, k);
            play_line(pl, part, line, notes);
        } else {
            if plan_bars(part.plan) != p.bars { format(errors, "part ", k, ": a plan of ", plan_bars(part.plan), " bars, not ", p.bars, "\n"); }
            if part.kind == ARP { play_arp(pl, part, chords, notes); }
            else { play_pad(pl, part, chords, notes); }
        }
    }
    sort(notes) { a, b => a.start < b.start };
    pl.period
}

// --- rendering a loop, a slice at a time ----------------------------------------------

struct TuneJob {
    room: i64 = 0,
    period: i64 = 0,            // the loop, in samples
    warm: i64 = 0,
    at: i64 = 0,                // the next sample, counting the warm-up
    next: i64 = 0,              // the next note to begin
    next_back: i64 = 0,         // the next note whose sounding a loop earlier is still to begin
    filled: i64 = 0,            // samples of the loop made
    scaled: i64 = 0,            // and given their final gain
    gain: f64 = 1.0,
    wet: f64 = 0.3,
    mean_l: f64 = 0.0,
    mean_r: f64 = 0.0,
    sum_l: f64 = 0.0,
    sum_r: f64 = 0.0,
    sum_sq: f64 = 0.0,
    peak: f64 = 0.0,
    done: bool = false,
    voices: Voice[MAX_VOICES],
    hall: Hall,
    drone: Drone,
}

// Starts the loop for `room`; `bars`, when above zero, shortens it (for the tests).
fn tune_begin(room: i64, bars: i64, notes: Note[>..]&) -> TuneJob {
    tune_of(piece(room), room, bars, notes)
}

// Starts the loop of piece p, `room`'s or one made from it.
fn tune_of(p: Piece, room: i64, bars: i64, notes: Note[>..]&) -> TuneJob {
    var errors: u8[>..] = [];
    let period = compose(p, bars, notes, errors);
    var job = TuneJob { room: room, period: period, warm: (WARM * MUSIC_RATE) as! i64, wet: p.wet,
                        voices: [Voice { .. }; MAX_VOICES],
                        hall: hall_for(p.size, p.rt60, p.damp, p.predelay, p.shimmer, period),
                        drone: drone_for(p.drone, p.drone_vel, period) };
    job.hall.vowel_cycles = p.vowels;
    job
}

fn begin_note(job: TuneJob&, n: Note, at: i64, now: i64) {
    // A free voice, else the one that would fall silent soonest.
    var pick = 0;
    var soonest = job.voices[0].end;
    for v, i in job.voices {
        if !v.on { pick = i; break; }
        if v.end < soonest { soonest = v.end; pick = i; }
    }
    start_voice(job.voices[pick], n, at, now);
}

// Works on the loop for about `seconds`. True once pcm holds the whole loop,
// left and right samples in turn (job.filled of them). The loop is 33 MB at
// most, so it is kept in one buffer made once (see music.goose) rather than
// grown afresh each time.
fn tune_step(job: TuneJob&, notes: const Note[:], pcm: f32[:], seconds: f64) -> bool {
    let until = clock() + seconds;
    assert(pcm.len >= 2 * job.period);
    let total = job.warm + job.period;
    let longest = (WARM * MUSIC_RATE) as! i64;
    while job.at < total {
        // Loop time of the block's first sample: negative during the warm-up.
        let b0 = job.at - job.warm;
        let b1 = b0 + BLOCK;
        // The notes that begin in this block, and their soundings a loop
        // earlier that still ring into the warm-up.
        while job.next_back < notes.len && notes[job.next_back].start - job.period < b1 {
            let n = notes[job.next_back];
            job.next_back++;
            let at = n.start - job.period;
            if at + longest > -job.warm { begin_note(job, n, at, b0); }
        }
        while job.next < notes.len && notes[job.next].start < b1 {
            let n = notes[job.next];
            job.next++;
            begin_note(job, n, n.start, b0);
        }
        var m = Mix {};
        for &v in job.voices {
            if v.on && !play_voice(v, b0, m) { v.on = false; }
        }
        play_drone(job.drone, b0, job.period, m);
        hall_block(job.hall, b0, job.period);
        for i in BLOCK {
            if job.at + i >= total { break; }
            let j = b0 + i;
            let cl, cr = sing(job.hall, m.choir[i]);
            let wl, wr = reverb(job.hall, m.send_l[i] + cl * 0.7, m.send_r[i] + cr * 0.7, j, job.period);
            let l = m.l[i] + cl + wl * job.wet;
            let r = m.r[i] + cr + wr * job.wet;
            if j >= 0 {
                pcm[job.filled] = l as f32;
                pcm[job.filled + 1] = r as f32;
                job.filled += 2;
                job.sum_l += l;
                job.sum_r += r;
                job.sum_sq += l * l + r * r;
                job.peak = max(job.peak, max(abs(l), abs(r)));
            }
        }
        job.at = min(total, job.at + BLOCK);
        if job.at >= total {
            // The level: TARGET_RMS, the peak kept under PEAK_LIMIT.
            job.mean_l = job.sum_l / job.period;
            job.mean_r = job.sum_r / job.period;
            let ms = job.sum_sq / (2 * job.period) - 0.5 * (job.mean_l * job.mean_l + job.mean_r * job.mean_r);
            let rms = sqrt(max(1e-12, ms));
            job.gain = min(TARGET_RMS / rms, PEAK_LIMIT / (job.peak + max(abs(job.mean_l), abs(job.mean_r))));
        }
        if clock() >= until { return false; }
    }
    while job.scaled < job.filled {
        let end = min(job.filled, job.scaled + 65536);
        for i in job.scaled..end {
            let mean = if i % 2 == 0 { job.mean_l } else { job.mean_r };
            pcm[i] = ((pcm[i] - mean) * job.gain) as f32;
        }
        job.scaled = end;
        if clock() >= until && job.scaled < job.filled { return false; }
    }
    job.done = true;
    true
}

// What is wrong with room's score, if anything: bars that don't add up,
// words that aren't notes. Empty when it is sound.
fn score_errors(room: i64) -> u8[>..] {
    var errors: u8[>..] = [];
    var notes: Note[>..] = [];
    compose(piece(room), 0, notes, errors);
    errors
}

// --- a WAV file, for listening outside the game -----------------------------------------

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
    put_u32(out, MUSIC_RATE);
    put_u32(out, MUSIC_RATE * 4);
    put_u16(out, 4);
    put_u16(out, 16);
    out.append("data");
    put_u32(out, pcm.len * 2);
    for v in pcm { put_u16(out, (round(clamp(v as f64, -1.0, 1.0) * 32767.0) as! i64) & 65535); }
    write_file(path, out)
}
