// The instruments the music is played on, as recordings of single notes: a
// Celtic harp, a strumstick (the dulcimer), cellos and a violin section, a
// solo violin, a bowed psaltery, rubbed wine glasses and a flute, from the
// CC0 sample libraries named in samples/SOURCES.md. Each note is an Ogg
// Vorbis file, decoded by stb_vorbis (src/c/ogg.h); samples/bank.txt says
// which instrument each is, the pitch it sounds at and, for a held note,
// which stretch of it loops. They are decoded once, at start-up, into one
// array of samples; voices.goose plays them.

import std;
import os;

// The sampled instruments.
let HARP = 0;
let DULCIMER = 1;
let CELLO = 2;
let STRINGS = 3;                // a section of violins
let VIOLIN = 4;
let PSALTERY = 5;               // bowed
let GLASS = 6;                  // wine glasses, rubbed: a glass harmonica
let FLUTE = 7;
let SAMPLED = 8;

let INSTRUMENT_NAMES: const (const u8[:])[8] = ["harp", "dulcimer", "cello", "strings", "violin", "psaltery", "glass", "flute"];

// A recorded note: where its samples are in bank_pcm, its rate, the pitch it
// sounds at (a MIDI number, with cents), and the stretch it loops, if any.
struct Zone {
    inst: i64 = 0,
    at: i64 = 0,
    len: i64 = 0,
    rate: f64 = 0.0,
    midi: f64 = 0.0,
    loop_at: i64 = 0,
    loop_len: i64 = 0,          // none when zero
}

struct OggInfo { channels: i64 = 0, rate: i64 = 0, frames: i64 = 0 }

extern "alch_ogg_info" fn ogg_info(data: const u8[:], info: OggInfo&) -> bool;
extern "alch_ogg_decode" fn ogg_decode(data: const u8[:], out: f32[:]) -> i64;

var bank_pcm: f32[>..];
var bank_zones: Zone[..48];
var bank_listed = 0;            // the notes bank.txt names
var bank_tried = false;

// Adds the note in `bytes` (an Ogg Vorbis file's) to the bank. False if it
// isn't mono Ogg Vorbis.
fn add_zone(inst: i64, bytes: const u8[:], midi: f64, loop_start: i64, loop_end: i64) -> bool {
    var info = OggInfo {};
    guard ogg_info(bytes, info) && info.channels == 1 && info.frames > 0 && bank_zones.len < 48 else { return false; }
    let at = bank_pcm.len;
    bank_pcm.resize(at + info.frames, 0.0);
    let got = ogg_decode(bytes, bank_pcm[at..]);
    guard got > 0 else { bank_pcm.resize(at); return false; }
    bank_pcm.resize(at + got);
    var z = Zone { inst: inst, at: at, len: got, rate: info.rate, midi: midi };
    if loop_end > loop_start && loop_end < got {
        z.loop_at = loop_start;
        z.loop_len = loop_end + 1 - loop_start;
    }
    bank_zones.push(z);
    true
}

// Reads every note bank.txt in `dir` lists, once. A note that is missing or
// unreadable is left out (its instrument plays on its other notes, or not at
// all) and named on stderr. True if all were read.
fn load_bank(dir: const u8[:]) -> bool {
    if bank_tried { return bank_listed > 0 && bank_zones.len == bank_listed; }
    bank_tried = true;
    var list: u8[>..] = [];
    if !read_file(str(dir, "/bank.txt"), list) {
        write_stderr(str("alchemists-sort: no instrument samples in ", dir, "\n"));
        return false;
    }
    var bad = 0;
    for line in split(list, '\n') {
        let w = words(line);
        if w.len == 0 || w[0][0] == '#' { continue; }
        bank_listed++;
        var inst = -1;
        for name, i in INSTRUMENT_NAMES { if name == w[0] { inst = i; } }
        var ok = inst >= 0 && w.len == 5;
        var midi = 0.0;
        var from = 0;
        var to = 0;
        if ok {
            let m, okm = parse_flt(w[2]);
            let a, oka = parse_int(w[3]);
            let b, okb = parse_int(w[4]);
            midi = m;
            from = a;
            to = b;
            ok = okm && oka && okb;
        }
        var bytes: u8[>..] = [];
        let path = str(dir, "/", if w.len > 1 { w[1] } else { "?" }, ".ogg");
        if !ok || !read_file(path, bytes) || !add_zone(inst, bytes, midi, from, to) {
            write_stderr(str("alchemists-sort: no instrument sample ", path, "\n"));
            bad++;
        }
    }
    bad == 0 && bank_listed > 0
}

// The recorded note of `inst` nearest `midi`, or -1 if it has none.
fn zone_for(inst: i64, midi: f64) -> i64 {
    var best = -1;
    var gap = 1000.0;
    for z, i in bank_zones {
        if z.inst != inst { continue; }
        let d = abs(z.midi - midi);
        if d < gap { gap = d; best = i; }
    }
    best
}

fn has_samples(inst: i64) -> bool { zone_for(inst, 60.0) >= 0 }
