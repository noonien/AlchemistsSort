// The forces at work: what a pour set off (PourResult.events), played in
// order once the liquid lands, each with its picture and its sound -- heat
// rippling across, ice shattering, wax softening and cracking off, lanterns
// flaring, shrouds sliding away, smoke clearing, an hourglass turning over,
// vines growing, withering and burning, the salamander's hop, the athanor's
// gold, the twins' overflow, the catalyst's runes, a vow's band taking its color.
//
// The board drawn, `shown`, trails the board in play while they play: it
// starts as the pour left it before anything it set off, and each event's
// change is made to it when its animation gets there, so nothing on screen
// changes before it is seen to happen. A new pour, an undo or any tool
// first finishes what is still playing (settle_beats).
//
// Part of the game in main.goose: it reads the game's state as main.goose's
// other parts do.

import std;
import vec;
import math;
import core.board;
import .draw;
import .palette;
import .sfx;
import .parts;

struct Beat {
    kind: EventKind,
    bottle: i64 = -1,
    from: i64 = -1,
    at: f64 = 0.0,          // when its animation starts
    span: f64 = 0.0,        // and how long it lasts
    apply_at: f64 = 0.0,    // when its change shows
    started: bool = false,
    applied: bool = false,
    quiet: bool = false,    // one of a group that another plays the sound of
    by_pour: bool = false,  // SealBroken: by the liquid poured onto it
    mask: i64 = 0,          // MurkCleared: the layers cleared
    n0: i64 = 0,            // Overflowed: the twin's layers before
    color: i64 = 0,         // the liquid it is about
    alt: Bottle,            // Flipped: the stack turned over, before quicksilver sinks
}

var beats: Beat[..40];
var shown: Board;           // the board as drawn
var landing_at: f64 = -1.0; // when the last pour's liquid landed, for the counters
var salamander_facing: f32 = 1.0;

struct Bit {
    pos: float2,
    vel: float2,
    angle: f32 = 0.0,
    spin: f32 = 0.0,
    life: f32 = 0.0,
    span: f32 = 1.0,
    size: f32 = 3.0,
    kind: f32 = 0.0,        // Shard's: 0 ice, 1 wax, 2 leaf, 3 ember
    color: float4,
    gravity: f32 = 400.0,
}

var bits: Bit[96];
var next_bit = 0;

fn fling(pos: float2, vel: float2, size: f32, kind: f32, color: float4, span: f32, gravity: f32) {
    bits[next_bit] = Bit { pos: pos, vel: vel, angle: rand.rand_flt() as f32 * 6.0,
                           spin: (rand.rand_flt() as f32 - 0.5) * 14.0, life: span, span: span, size: size,
                           kind: kind, color: color, gravity: gravity };
    next_bit = (next_bit + 1) % bits.len;
}

// n bits flung out from around `at`, r across.
fn shatter(at: float2, r: float2, n: i64, kind: f32, color: float4, speed: f32) {
    for k in n {
        let a = rand.rand_flt() * TAU;
        let ox = (rand.rand_flt() - 0.5) * 2.0 * r.x;
        let oy = (rand.rand_flt() - 0.5) * 2.0 * r.y;
        let s = speed * (0.4 + rand.rand_flt() as f32 * 0.8);
        fling(at + v2(ox as f32, oy as f32), v2(cos(a) as f32 * s, sin(a) as f32 * s - speed * 0.5),
              2.5 + rand.rand_flt() as f32 * 3.5, kind, color, 0.7 + rand.rand_flt() as f32 * 0.5,
              if kind == 3.0 { -60.0 } else if kind == 2.0 { 120.0 } else { 520.0 });
    }
}

fn update_bits(dt: f32) {
    for &b in bits {
        if b.life <= 0.0 { continue; }
        b.life -= dt;
        b.vel.y += b.gravity * dt;
        if b.kind == 2.0 { b.vel.x += sin(b.life * 9.0) * 60.0 * dt; }     // leaves flutter
        b.pos = b.pos + b.vel * float2 { dt, dt };
        b.angle += b.spin * dt;
    }
}

fn draw_bits(out: Inst[>..]&) {
    for b in bits {
        if b.life <= 0.0 { continue; }
        let a = clamp(b.life / b.span * 2.0, 0.0, 1.0);
        var i = inst(Shape.Shard, b.pos, v2(b.size, b.size), with_alpha(b.color, a));
        i.p0 = float4 { b.kind, 0.0, 0.0, 0.0 };
        i.misc.y = b.angle;
        out.push(i);
    }
}

fn bits_alive() -> bool {
    for b in bits { if b.life > 0.0 { return true; } }
    false
}

// --- the timeline -------------------------------------------------------------------------

// How long each kind's animation lasts, and when in it the change shows.
fn beat_span(kind: EventKind) -> f64, f64 {
    match kind {
        HeatPulse => { return 0.6, 0.3; },
        Thawed => { return 0.8, 0.22; },
        SealSoftened => { return 0.7, 0.0; },
        SealBroken => { return 0.85, 0.2; },
        Lit => { return 1.2, 0.0; },
        ShroudLifted => { return 0.8, 0.0; },
        MurkCleared => { return 0.8, 0.0; },
        Flipped => { return 1.0, 0.45; },
        VineSpread => { return 1.0, 0.45; },
        VineWithered => { return 1.1, 0.5; },
        TendrilBurned => { return 0.9, 0.55; },
        SalamanderHop => { return 0.55, 0.0; },
        Transmuted => { return 0.9, 0.0; },
        Overflowed => { return 0.6, 0.0; },
        CatalystFired => { return 1.1, 0.0; },
        Completed => { return 0.0, 0.0; },
        Vowed => { return 0.8, 0.0; },
    }
}

// What heat does to a flask: these follow the pulse that reached it.
fn heat_result(kind: EventKind) -> bool {
    kind == EventKind.Thawed || kind == EventKind.SealSoftened || kind == EventKind.SealBroken ||
    kind == EventKind.TendrilBurned
}

// The board just after a pour's liquid moved, before anything it set off:
// what landed in the destination and what went on into its twin. A seal
// on the destination stays until its own event breaks it.
fn liquid_moved(before: Board, from: i64, to: i64, r: PourResult) -> Board {
    var m = before;
    var scratch = PourResult {};
    for k in r.amount { move_one(m, from, to, scratch); }
    let tw: i64 = m.bottles[to].twin;
    if tw >= 0 { for k in r.overflow { move_one(m, from, tw, scratch); } }
    // A vow takes its color when its own event plays.
    for e in r.events { if e.kind == EventKind.Vowed { m.bottles[e.bottle].vow = 0; } }
    m
}

// Lays out a pour's events from t0, its start (the liquid lands T_LIFT +
// T_POUR later), and shows the board as the liquid left it.
fn schedule_pour(before: Board, from: i64, to: i64, r: PourResult, t0: f64) {
    settle_beats();
    let mid = liquid_moved(before, from, to, r);
    shown = mid;
    shown.pours = board.pours;
    let land = t0 + T_LIFT + T_POUR;
    landing_at = land;
    var cursor = land;
    var heat_src = -2;
    var heat_at = 0.0;
    var light_src = -1;
    var light_at = 0.0;
    var transmuted = false;
    for e, k in r.events {
        if beats.len >= 40 { break; }
        let span, delay0 = beat_span(e.kind);
        var delay = delay0;
        var b = Beat { kind: e.kind, bottle: e.bottle, from: e.from, span: span, alt: mid.bottles[0] };
        let heat_follow = heat_result(e.kind) && e.from >= 0 && e.from == heat_src;
        let light_follow = (e.kind == EventKind.MurkCleared || e.kind == EventKind.ShroudLifted) && e.from >= 0 &&
                           e.from == light_src;
        if e.kind == EventKind.SealBroken && k == 0 && r.popped && e.bottle == to {
            // The stream hits the seal.
            b.at = t0 + T_LIFT - 0.04;
            b.span = 0.7;
            b.by_pour = true;
            delay = 0.08;
        } else if e.kind == EventKind.Transmuted {
            b.at = t0 + T_LIFT + 0.12;
            b.quiet = transmuted;
            if transmuted { b.span = 0.0; }
            transmuted = true;
        } else if e.kind == EventKind.Vowed {
            // As the liquid lands.
            b.at = land - T_POUR * 0.4;
        } else if e.kind == EventKind.Overflowed {
            b.at = t0 + T_LIFT + T_POUR * 0.5;
            b.n0 = before.bottles[e.bottle].n;
            b.color = top(mid.bottles[e.bottle]);
        } else if e.kind == EventKind.HeatPulse {
            b.quiet = e.from == heat_src;
            if e.from != heat_src {
                heat_src = e.from;
                heat_at = cursor;
                cursor = max(cursor, heat_at + 0.35);
            }
            b.at = heat_at;
        } else if heat_follow {
            b.at = heat_at + 0.3;
            cursor = max(cursor, b.at + 0.3);
        } else if light_follow {
            b.at = light_at + 0.3;
            cursor = max(cursor, b.at + 0.25);
        } else if e.kind == EventKind.MurkCleared && e.from < 0 {
            b.at = cursor;
        } else {
            b.at = cursor;
            cursor += match e.kind {
                Lit => 0.45, Flipped => 1.0, VineSpread => 0.75, VineWithered => 0.65, SalamanderHop => 0.55,
                CatalystFired => 0.6, Completed => 0.12, _ => 0.3,
            };
            if e.kind == EventKind.Lit {
                light_src = e.bottle;
                light_at = b.at;
            }
        }
        if e.kind != EventKind.HeatPulse && !heat_follow { heat_src = -2; }
        b.apply_at = b.at + delay;
        beats.push(b);
    }
}

// Makes every change still to come at once: the board drawn is the board.
fn settle_beats() {
    for &b in beats { if !b.applied { apply_beat(b, false); } }
    beats.clear();
    shown = board;
    landing_at = -1.0;
}

fn beats_running() -> bool { beats.len > 0 }

fn update_beats() {
    if beats.len == 0 {
        shown = board;
        return;
    }
    if landing_at >= 0.0 && now >= landing_at {
        // Every pour counts toward ice, hourglasses and vines.
        landing_at = -1.0;
        for i in shown.count {
            var s .= shown.bottles[i];
            if s.cover == Cover.Rime && s.thaw > 1 { s.thaw--; }
            s.flip_count = board.bottles[i].flip_count;
            if board.bottles[i].fixture == Fixture.VineRoot { s.spread_count = board.bottles[i].spread_count; }
        }
    }
    var done = true;
    for &b in beats {
        if !b.started && now >= b.at {
            b.started = true;
            start_beat(b);
        }
        if !b.applied && now >= b.apply_at { apply_beat(b, true); }
        if !b.applied || now < b.at + b.span { done = false; }
    }
    if done && landing_at < 0.0 {
        beats.clear();
        shown = board;
    }
}

// How far into its animation the beat of this kind on flask i is, 0..1, or
// -1 when none is playing.
fn beat_k(kind: EventKind, i: i64) -> f32 {
    for b in beats {
        if b.kind != kind || b.bottle != i || !b.started || b.span <= 0.0 { continue; }
        let k = (now - b.at) / b.span;
        if k < 1.0 { return clamp(k, 0.0, 1.0) as f32; }
    }
    -1.0
}

fn beat_waiting(kind: EventKind, i: i64) -> bool {
    for b in beats { if b.kind == kind && b.bottle == i && !b.applied { return true; } }
    false
}

// --- what each does as it starts, and to the board drawn ---------------------------------------

fn slot_anchors(i: i64) -> Anchors {
    var a = flask_anchors(rest_pos(i), slots[i].half, 0.0, 1.0);
    a.hang = hang_side(i);
    a
}

fn stand_anchors(i: i64) -> Anchors {
    var a = flask_anchors(slots[i].pos + v2(0.0, drop_offset(i)), slots[i].half, 0.0, 1.0);
    a.hang = hang_side(i);
    a
}

let ICE_COLOR = float4 { 0.82, 0.93, 1.0, 1.0 };
let LEAF_COLOR = float4 { 0.3, 0.6, 0.22, 1.0 };
let DEAD_LEAF = float4 { 0.55, 0.4, 0.18, 1.0 };
let EMBER = float4 { 1.0, 0.5, 0.15, 1.0 };

fn start_beat(b: Beat&) {
    let i = b.bottle;
    if i < 0 || i >= shown.count { return; }
    let a = slot_anchors(i);
    let hx = a.hx;
    match b.kind {
        HeatPulse => if !b.quiet { play_pitched(Sfx.Sizzle, 0.9 + rand.rand_flt() * 0.2, 0.6); },
        Thawed => play(Sfx.Crack),
        SealSoftened => play_pitched(Sfx.Sizzle, 0.7, 0.5),
        SealBroken => {
            play(Sfx.Crack);
            if b.by_pour { play(Sfx.Pop); }
        },
        Lit => play(Sfx.Chime),
        ShroudLifted => play(Sfx.Reveal),
        Flipped => {
            play(Sfx.Whoosh);
            // The stack turned over, before quicksilver runs back down.
            let s = shown.bottles[i];
            var alt = s;
            let n: i64 = s.n;
            var murk = 0;
            for k in n {
                alt.seg[k] = s.seg[n - 1 - k];
                if murky(s, n - 1 - k) { murk |= 1 << k; }
            }
            alt.murk = murk as u16;
            b.alt = alt;
        },
        VineSpread => play(Sfx.Rustle),
        VineWithered => play_pitched(Sfx.Rustle, 0.7, 0.8),
        TendrilBurned => {
            play_pitched(Sfx.Sizzle, 1.2, 0.6);
            play_pitched(Sfx.Rustle, 1.3, 0.4);
        },
        SalamanderHop => {
            play(Sfx.Chirp);
            if b.from >= 0 && b.from != i { salamander_facing = if slots[i].pos.x >= slots[b.from].pos.x { 1.0 } else { -1.0 }; }
        },
        Transmuted => if !b.quiet {
            play_pitched(Sfx.Chime, 1.5, 0.6);
            burst(at(a, a.body), 26, float4 { 1.0, 0.82, 0.3, 1.0 }, 170.0);
        },
        Overflowed => play_pitched(Sfx.Pour, 1.35, 0.4),
        CatalystFired => {
            play(Sfx.Gong);
            burst(at(a, a.base), 30, float4 { 0.8, 0.5, 1.0, 1.0 }, 220.0);
        },
        Vowed => play_pitched(Sfx.Chime, 1.25, 0.5),
        MurkCleared, Completed => {},
    }
}

fn apply_beat(b: Beat&, live: bool) {
    b.applied = true;
    let i = b.bottle;
    if i < 0 || i >= shown.count { return; }
    var s .= shown.bottles[i];
    let a = slot_anchors(i);
    let hx = a.hx;
    match b.kind {
        SealBroken => {
            s.cover = Cover.None;
            s.soft = 0;
            if live { shatter(at(a, a.rim + v2(0.0, hx * 0.6)), v2(hx * 0.4, hx * 0.4), 10, 1.0, palette_color(s.key, save.color_safe), 140.0); }
        },
        SealSoftened => { s.soft = 1; },
        Thawed => {
            s.cover = Cover.None;
            s.thaw = 0;
            if live {
                play(Sfx.Ice);
                shatter(a.center, v2(hx, a.half.y * 0.8), 22, 0.0, ICE_COLOR, 180.0);
            }
        },
        HeatPulse => if s.cover == Cover.Rime && s.thaw > 1 { s.thaw--; },
        Lit => { s.lit = true; },
        ShroudLifted => { s.cover = Cover.None; },
        MurkCleared => {
            let old: i64 = s.murk;
            let n: i64 = s.n;
            if b.from < 0 { s.murk = (old & ((1 << max(0, n - 1)) - 1)) as u16; } else { s.murk = 0; }
            b.mask = old & ~(s.murk as i64);
        },
        Flipped => {
            let alt = b.alt;
            s.seg = alt.seg;
            s.murk = alt.murk;
            sink_quicksilver(s);
        },
        VineSpread => { s.cover = Cover.Vine; },
        VineWithered => {
            for j in shown.count {
                if shown.bottles[j].cover != Cover.Vine { continue; }
                shown.bottles[j].cover = Cover.None;
                if live {
                    let aj = slot_anchors(j);
                    shatter(aj.center, v2(aj.hx, aj.half.y * 0.8), 14, 2.0, DEAD_LEAF, 90.0);
                }
            }
            s.fixture = Fixture.None;
            if live { shatter(at(a, a.base), v2(hx, hx * 0.3), 10, 2.0, DEAD_LEAF, 70.0); }
        },
        TendrilBurned => {
            s.cover = Cover.None;
            if live { shatter(a.center, v2(hx * 0.9, a.half.y * 0.8), 18, 3.0, EMBER, 60.0); }
        },
        SalamanderHop => { shown.salamander = i; },
        CatalystFired => { s.spent = true; },
        Vowed => { s.vow = board.bottles[i].vow; },
        Completed => {
            s.done = true;
            s.murk = 0;
            if live {
                complete_at[i] = now;
                let c = flask_color(s);
                play_note(c, 0.6);
                burst(a.center, 30, palette_color(c, save.color_safe), 180.0);
            }
        },
        Transmuted, Overflowed => {},
    }
}

// --- how the flasks look meanwhile ---------------------------------------------------------------

// The cover's state this moment for flask i.
fn cover_look(i: i64) -> CoverLook {
    var l = CoverLook {};
    let b = shown.bottles[i];
    let soft = beat_k(EventKind.SealSoftened, i);
    l.soft = b.soft;
    if soft >= 0.0 { l.soft = max(0.0, l.soft - 1.0) + ease(soft / 0.6); }
    let br = beat_k(EventKind.SealBroken, i);
    if br >= 0.0 && beat_waiting(EventKind.SealBroken, i) { l.crack = 1.0; }
    for e in beats {
        if e.bottle != i || !e.started || e.applied { continue; }
        let into = ((now - e.at) / max(0.01, e.apply_at - e.at)) as f32;
        if e.kind == EventKind.SealBroken { l.crack = clamp(into, 0.0, 1.0); }
        if e.kind == EventKind.Thawed { l.shatter = clamp(into * 0.5, 0.0, 0.5); }
        if e.kind == EventKind.TendrilBurned { l.burn = clamp(into, 0.0, 1.0); }
    }
    let grow = beat_k(EventKind.VineSpread, i);
    if grow >= 0.0 { l.grow = clamp((grow - 0.45) / 0.55, 0.0, 1.0); }
    l.wither = withering();
    l
}

// How far a vine's withering has got, 0..1, while it plays.
fn withering() -> f32 {
    for e in beats {
        if e.kind != EventKind.VineWithered || !e.started || e.applied { continue; }
        return clamp((now - e.at) / (e.apply_at - e.at), 0.0, 1.0) as f32;
    }
    0.0
}

// What stands by flask i this moment.
fn stand_look(i: i64) -> StandLook {
    var l = StandLook {};
    let b = shown.bottles[i];
    for e in beats {
        if !e.started || e.span <= 0.0 { continue; }
        let k = ((now - e.at) / e.span) as f32;
        if k >= 1.0 { continue; }
        // A brazier flares as it sends its heat, a hearth as it makes gold.
        if e.kind == EventKind.HeatPulse && e.from == i && b.fixture == Fixture.Brazier { l.flare = max(l.flare, 1.0 - k); }
        if e.kind == EventKind.Transmuted && e.bottle == i { l.flare = max(l.flare, 1.0 - k); }
        if e.kind == EventKind.Lit && e.bottle == i {
            l.flare = max(l.flare, (1.0 - k) * 1.2);
            l.lit = ease(k as f64 * 4.0);
        }
    }
    if b.fixture == Fixture.VineRoot { l.wither = withering(); }
    l
}

// How an hourglass turning over is drawn: its squash, and the stack to show.
fn flip_view(i: i64, b: Bottle) -> f32, Bottle {
    for e in beats {
        if e.kind != EventKind.Flipped || e.bottle != i || !e.started { continue; }
        let k = (now - e.at) / e.span;
        if k >= 1.0 { continue; }
        if k < 0.45 { return cos(ease(k / 0.45) * PI * 0.5), b; }
        let up = sin(ease((k - 0.45) / 0.3) * PI * 0.5);
        if k < 0.75 { return max(up, 0.02), e.alt; }
        return 1.0, b;
    }
    return 1.0, b;
}

// A twin's fill while liquid comes through the tube.
fn overflow_fill(i: i64, fill: f32) -> f32 {
    for e in beats {
        if e.kind != EventKind.Overflowed || e.bottle != i { continue; }
        if now < e.at { return e.n0; }
        let k = ease((now - e.at - 0.15) / (e.span - 0.15));
        return e.n0 + (fill - e.n0) * k;
    }
    fill
}

// The liquid in the tube between twins i and j: how far it has run, its
// color and the flask it runs from; -1 there when none is.
fn tube_flow(i: i64, j: i64) -> f32, float4, i64 {
    for e in beats {
        if e.kind != EventKind.Overflowed || !e.started || !((e.bottle == i && e.from == j) || (e.bottle == j && e.from == i)) { continue; }
        let k = (now - e.at) / e.span;
        if k >= 1.0 { continue; }
        return (k * 1.7) as f32, palette_color(e.color, save.color_safe), e.from;
    }
    return -100.0, float4_0, -1;
}

// How bright a vow's band flashes as it takes its color, 0..1.
fn vow_flash(i: i64) -> f32 {
    let k = beat_k(EventKind.Vowed, i);
    if k < 0.0 { 0.0 } else { (1.0 - k) * (1.0 - k) }
}

fn hop_flying() -> bool { beat_k(EventKind.SalamanderHop, shown.salamander) >= 0.0 }

// --- what each draws over the board ----------------------------------------------------------------

fn draw_beats(out: Inst[>..]&) {
    for e in beats {
        if !e.started || e.span <= 0.0 { continue; }
        let k = ((now - e.at) / e.span) as f32;
        if k >= 1.0 { continue; }
        let i = e.bottle;
        if i < 0 || i >= shown.count { continue; }
        let a = slot_anchors(i);
        let hx = a.hx;
        match e.kind {
            HeatPulse => draw_heat(out, e, k),
            Thawed => if e.applied {
                // The shell, gone to pieces, fading.
                var ice = inst(Shape.Ice, a.center, a.half + v2(hx * 0.12, hx * 0.12), white(1.0));
                let after = clamp((now - e.apply_at) / (e.at + e.span - e.apply_at), 0.0, 1.0) as f32;
                ice.p0 = float4 { 0.0, 0.5 + 0.5 * after, (i * 0.37) % 1.0, 0.0 };
                out.push(ice);
                glow(out, a.center, a.half * v2(1.3, 1.1), 1.0, float4 { 0.85, 0.95, 1.0, 0.35 * (1.0 - after) });
            },
            SealSoftened => {
                let c = at(a, a.rim + v2(0.0, hx * 0.6));
                glow(out, c, v2(hx * 1.1, hx * 1.1), 1.0, float4 { 1.0, 0.5, 0.15, 0.4 * (1.0 - k) });
                var st = inst(Shape.Steam, c - v2(0.0, hx * 1.0), v2(hx * 0.6, hx * 1.2), white(1.0 - k));
                st.p0 = float4 { i * 1.3, 0.0, 0.0, 0.0 };
                out.push(st);
            },
            SealBroken => if e.applied {
                // The seal falls away, turning.
                let after = clamp((now - e.apply_at) / (e.at + e.span - e.apply_at), 0.0, 1.0) as f32;
                let side: f32 = if i % 2 == 0 { 1.0 } else { -1.0 };
                var fa = a;
                fa.center = a.center + v2(side * after * hx * 1.2, after * after * hx * 6.0);
                fa.angle = side * after * 1.6;
                draw_wax(out, shown.bottles[i].key, fa, shown.bottles[i].soft, 1.0, (i * 0.618) % 1.0,
                         1.0 - after * after, save.color_safe);
                // What it hid comes out of the smoke.
                for kk in shown.bottles[i].n as i64 {
                    var sm = inst(Shape.Smoke, a.center + segment_center(a.half, kk), v2(hx * 1.0, hx * 0.75), white(1.0));
                    sm.p0 = float4 { after, i * 0.7 + kk, 0.0, 0.0 };
                    sm.misc.z = hx * 0.5;
                    out.push(sm);
                }
            },
            Lit => draw_light(out, e, k),
            ShroudLifted => {
                // The cloth slides up and away.
                let up = ease(k);
                var cl = inst(Shape.Cloth, a.center + v2(up * hx * 0.6, hx * 0.15 - up * a.half.y * 1.1),
                              a.half + v2(hx * 0.2, hx * 0.15), float4 { 0.17, 0.13, 0.32, 1.0 - up });
                cl.misc.y = up * 0.35;
                out.push(cl);
            },
            MurkCleared => if e.applied {
                for kk in shown.bottles[i].n as i64 {
                    if (e.mask >> kk) & 1 == 0 { continue; }
                    var sm = inst(Shape.Smoke, a.center + segment_center(a.half, kk), v2(hx * 1.0, hx * 0.75), white(1.0));
                    sm.p0 = float4 { k, i * 0.7 + kk, 0.0, 0.0 };
                    sm.misc.z = hx * 0.5;
                    out.push(sm);
                }
            },
            Flipped => draw_flip(out, e, k),
            VineSpread => if !e.applied { draw_vine_reach(out, e, k / 0.45); },
            VineWithered => if e.applied {
                // The root crumbles away.
                let after = clamp((now - e.apply_at) / (e.at + e.span - e.apply_at), 0.0, 1.0) as f32;
                var gone = shown.bottles[i];
                gone.fixture = Fixture.VineRoot;
                draw_roots(out, gone, stand_anchors(i), 1.0, 0.99 * (1.0 - after));
            },
            TendrilBurned => if !e.applied {
                // Flames running over it.
                for f in 3 {
                    if rand.rand_int(4) == 0 {
                        emit(a.center + v2((rand.rand_flt() as f32 - 0.5) * hx * 1.8, (rand.rand_flt() as f32 - 0.5) * a.half.y * 1.6),
                             v2(0.0, -60.0), 0.5, 3.0 + rand.rand_flt() as f32 * 3.0, EMBER, -40.0);
                    }
                }
                glow(out, a.center, a.half * v2(1.4, 1.1), 1.0, float4 { 1.0, 0.45, 0.1, 0.3 * k });
                // The fire runs down it from the top.
                let burn = clamp((now - e.at) / (e.apply_at - e.at), 0.0, 1.0) as f32;
                let y = a.center.y - a.half.y + a.half.y * 2.0 * clamp(burn * 1.2 - 0.1, 0.0, 1.0);
                var fl = inst(Shape.Brazier, v2(a.center.x, y), v2(hx * 1.2, hx * 0.7), white(0.95));
                fl.p0 = float4 { 0.0, 0.2, 0.0, 0.0 };
                fl.misc.z = hx * 0.4;
                out.push(fl);
            },
            SalamanderHop => draw_hop(out, e, k),
            Transmuted => {
                let c = at(a, a.body);
                let f = (1.0 - k) * (1.0 - k);
                glow(out, c, v2(hx * 2.2, hx * 2.2), 1.0, float4 { 1.0, 0.85, 0.35, 0.65 * f });
                spark(out, c, hx * (0.6 + 1.6 * k), float4 { 1.0, 0.95, 0.7, f });
            },
            Overflowed => {},
            CatalystFired => {
                let base = at(a, a.base);
                let r = hx * (1.3 + 2.4 * ease(k));
                rune_circle(out, base, r, float4 { 0.85, 0.6, 1.0, 1.0 - k });
                var rg = inst(Shape.Ring, base, v2(r * 1.1, r * 1.1), float4 { 0.85, 0.6, 1.0, 0.6 * (1.0 - k) });
                rg.p0 = float4 { 3.0, 0.0, 0.0, 0.0 };
                rg.misc.w = 0.3;
                out.push(rg);
                glow(out, base - v2(0.0, hx), v2(hx * 3.0, hx * 3.0), 1.0, float4 { 0.7, 0.4, 1.0, 0.35 * (1.0 - k) });
            },
            Vowed => {
                // The band lights up in the color it took.
                let c = palette_color(shown.bottles[i].vow, save.color_safe);
                let f = (1.0 - k) * (1.0 - k);
                let band = at(a, a.shoulder + v2(0.0, hx * 0.12));
                glow(out, band, v2(hx * 1.7, hx * 0.8), 1.0, with_alpha(c, 0.8 * f));
                spark(out, band, hx * (0.5 + 1.2 * k), with_alpha(c, f));
            },
            Completed => {},
        }
    }
    draw_bits(out);
}

// Where heat comes from: a brazier under the flask, or the salamander on it.
fn heat_source_point(src: i64) -> float2 {
    let a = stand_anchors(src);
    if shown.salamander == src && shown.bottles[src].fixture != Fixture.Brazier { return at(a, a.lip); }
    at(a, a.base - v2(0.0, a.hx * 0.3))
}

fn draw_heat(out: Inst[>..]&, e: Beat, k: f32) {
    let i = e.bottle;
    let a = slot_anchors(i);
    let hx = a.hx;
    let target = at(a, a.body);
    let travel = clamp(k / 0.5, 0.0, 1.0);
    if e.from >= 0 && e.from != i && e.from < shown.count {
        let src = heat_source_point(e.from);
        let ctrl = v2((src.x + target.x) * 0.5, min(src.y, target.y) - hx * 1.4);
        curve(out, Shape.Heat, src, ctrl, target, hx * 0.35, travel * 1.15, white(1.0 - clamp((k - 0.6) / 0.4, 0.0, 1.0)));
    } else {
        // The salamander's own flask: a ring of heat spreading from it.
        var rg = inst(Shape.Ring, target, v2(hx * (0.5 + 1.6 * k), hx * (0.5 + 1.6 * k)), float4 { 1.0, 0.5, 0.15, 0.7 * (1.0 - k) });
        rg.p0 = float4 { 3.0, 0.0, 0.0, 0.0 };
        out.push(rg);
    }
    // It arrives: the flask warms.
    let arrive = clamp((k - 0.45) / 0.55, 0.0, 1.0);
    if arrive > 0.0 {
        let f = sin(arrive * PI);
        glow(out, target, a.half * v2(1.5, 1.05), 1.0, float4 { 1.0, 0.42, 0.1, 0.45 * f });
    }
}

// A lantern lights: it flares, and beams sweep to the flasks its light
// reaches (its own and its neighbors).
fn draw_light(out: Inst[>..]&, e: Beat, k: f32) {
    let i = e.bottle;
    let a = stand_anchors(i);
    let hx = a.hx;
    let src = lantern_pos(a);
    let fade = 1.0 - clamp((k - 0.6) / 0.4, 0.0, 1.0);
    glow(out, src, v2(hx * 3.5, hx * 3.5), 1.0, float4 { 1.0, 0.85, 0.5, 0.5 * (1.0 - k) });
    var reach: i64[..7] = [i];
    for j in neighbors(shown, i) { reach.push(j); }
    for j in reach {
        let aj = slot_anchors(j);
        let to = at(aj, aj.body);
        let ctrl = v2((src.x + to.x) * 0.5, (src.y + to.y) * 0.5 - hx * 0.4);
        let head = clamp(k / 0.45, 0.0, 1.0);
        curve(out, Shape.Beam, src, ctrl, to, hx * 0.22, head, float4 { 1.0, 0.88, 0.55, 0.8 * fade });
        if head >= 1.0 { glow(out, to, aj.half * v2(1.3, 0.9), 1.0, float4 { 1.0, 0.9, 0.6, 0.3 * fade }); }
    }
}

// An hourglass turning over: the squash is done by the flask's drawing;
// here quicksilver runs back down once it is upright.
fn draw_flip(out: Inst[>..]&, e: Beat, k: f32) {
    if k < 0.72 || k > 0.98 { return; }
    let i = e.bottle;
    let a = slot_anchors(i);
    let s = shown.bottles[i];
    let alt = e.alt;
    let run = clamp((k - 0.72) / 0.24, 0.0, 1.0);
    var to_k = 0;
    for kk in alt.n as i64 {
        if alt.seg[kk] != QUICKSILVER { continue; }
        let from_c = a.center + segment_center(a.half, kk);
        let to_c = a.center + segment_center(a.half, to_k);
        to_k++;
        let p = lerp2(from_c, to_c, ease(run));
        glow(out, p, v2(a.hx * 0.45, a.hx * 0.32), 0.6, float4 { 0.9, 0.93, 1.0, 0.9 * (1.0 - run * 0.6) });
        glow(out, p + v2(-a.hx * 0.12, -a.hx * 0.08), v2(a.hx * 0.12, a.hx * 0.08), 0.5, white(0.9));
    }
    if run >= 0.99 { slosh(i, 0.25); }
}

// A vine reaching across from the flask next to the new tendril.
fn draw_vine_reach(out: Inst[>..]&, e: Beat, k: f32) {
    let i = e.bottle;
    var src = e.from;
    for j in neighbors(shown, i) {
        if shown.bottles[j].cover == Cover.Vine || j == e.from { src = j; }
    }
    if src < 0 || src >= shown.count { return; }
    let sa = stand_anchors(src);
    let ta = slot_anchors(i);
    let p = at(sa, sa.base - v2(0.0, sa.hx * 0.5));
    let q = at(ta, ta.base - v2(0.0, ta.hx * 0.6));
    let ctrl = v2((p.x + q.x) * 0.5, min(p.y, q.y) - sa.hx * 1.2);
    let g = clamp(k, 0.0, 1.0);
    // Draw the stem along the curve up to where it has grown.
    let end = lerp2(lerp2(p, ctrl, g), lerp2(ctrl, q, g), g);
    let c2 = lerp2(p, ctrl, g);
    curve(out, Shape.Stream, p, c2, end, sa.hx * 0.1, i * 1.3, float4 { 0.2, 0.42, 0.15, 1.0 });
    var leaf = inst(Shape.Shard, end, v2(sa.hx * 0.16, sa.hx * 0.16), LEAF_COLOR);
    leaf.p0 = float4 { 2.0, 0.0, 0.0, 0.0 };
    leaf.misc.y = (now * 3.0) as f32;
    out.push(leaf);
}

// The salamander's leap, from its old perch to the flask poured from.
fn draw_hop(out: Inst[>..]&, e: Beat, k: f32) {
    let i = e.bottle;
    let to_a = slot_anchors(i);
    let from_a = if e.from >= 0 && e.from < shown.count { slot_anchors(e.from) } else { to_a };
    let p = at(from_a, from_a.lip);
    let q = at(to_a, to_a.lip);
    let up = max(abs(q.x - p.x) * 0.45, to_a.hx * 1.6);
    let ctrl = v2((p.x + q.x) * 0.5, min(p.y, q.y) - up * 2.0);
    let u = ease(k);
    let pos = lerp2(lerp2(p, ctrl, u), lerp2(ctrl, q, u), u);
    let vel = lerp2(ctrl - p, q - ctrl, u);
    let tilt = clamp(atan2(vel.y, abs(vel.x) + 0.001) * 0.5, -0.6, 0.6);
    draw_salamander(out, pos, to_a.hx, tilt * salamander_facing, salamander_facing, sin(k * PI), 0.6);
    if k > 0.9 { burst(q, 2, EMBER, 80.0); }
}

fn forces_lively() -> bool { beats.len > 0 || bits_alive() }
