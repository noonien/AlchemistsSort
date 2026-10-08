// The game's small motions: flasks dropping onto the shelf, liquid that
// sloshes and ripples, droplets, the stopper and label of a finished potion,
// buttons that squash, the ink between screens, and the win's finale.
//
// Part of the game in main.goose: it reads the game's state (the board,
// the slots, the clock) as main.goose's other parts do. Everything here is
// timed from `now`, so a slow frame rate only makes it step.

import std;
import vec;
import math;
import gfx;
import core.board;
import .draw;
import .palette;
import .text;
import .sfx;

fn bounce_in(x: f64) -> f32 {
    // 0..1, landing with a small bounce.
    let u = clamp(x, 0.0, 1.0);
    if u < 0.7 { let v = u / 0.7; return (v * v) as f32; }
    (1.0 - 0.14 * sin((u - 0.7) / 0.3 * PI)) as f32
}

// --- flasks dropping onto the shelf ------------------------------------------------------

let DROP_STEP: f64 = 0.06;     // between one flask and the next
let DROP_TIME: f64 = 0.45;

var drop_t0: f64 = -100.0;

// Starts the drop, after the ink has uncovered the screen if it is moving.
fn start_drop() { drop_t0 = max(now, transition_reveal_at()); }

// How far above its place flask i still is, in canvas units.
fn drop_offset(i: i64) -> f32 {
    let k = (now - drop_t0 - i * DROP_STEP) / DROP_TIME;
    if k >= 1.0 { return 0.0; }
    -(1.0 - bounce_in(k)) * 60.0
}

fn dropping() -> bool { now - drop_t0 < DROP_TIME + DROP_STEP * MAX_BOTTLES }

// --- slosh and ripples -----------------------------------------------------------------------

var slosh_at: f64[MAX_BOTTLES] = [-10.0; MAX_BOTTLES];
var slosh_amp: f32[MAX_BOTTLES];
var ripple_x: f32[MAX_BOTTLES];       // where a stream lands, in half widths from the middle

// Sets flask i's surface swinging, amp its first tilt (a slope).
fn slosh(i: i64, amp: f32) {
    if i < 0 || i >= MAX_BOTTLES { return; }
    slosh_at[i] = now;
    slosh_amp[i] = amp;
}

fn slosh_slope(i: i64) -> f32 {
    if i < 0 || i >= MAX_BOTTLES { return 0.0; }
    let t = now - slosh_at[i];
    if t < 0.0 || t > 1.6 { return 0.0; }
    (slosh_amp[i] * exp(-t * 3.2) * sin(t * 13.0)) as f32
}

fn sloshing() -> bool {
    for t in slosh_at { if now - t < 1.6 { return true; } }
    false
}

// The liquid shader's extra channels for flask i: slope, seed, ripple center.
fn liquid_fx(i: i64) -> float4 {
    let seed = if i < 0 { 0.5 } else { (i * 0.618034) % 1.0 };
    let rx = if i < 0 || i >= MAX_BOTTLES { 0.0 } else { ripple_x[i] };
    float4 { slosh_slope(i), seed, rx, 1.0 }
}

// --- droplets ----------------------------------------------------------------------------------

struct Drop { pos: float2, vel: float2, life: f32 = 0.0, size: f32 = 2.0, color: float4 }

var drops: Drop[64];
var next_drop = 0;

fn splash(at: float2, color: float4, side: f32) {
    let r = rand.rand_flt() as f32;
    drops[next_drop] = Drop { pos: at, vel: float2 { (r - 0.5) * 70.0 + side * 15.0, -60.0 - r * 70.0 },
                              life: 0.35 + r * 0.2, size: 1.5 + r * 1.5, color: color };
    next_drop = (next_drop + 1) % drops.len;
}

fn update_drops(dt: f32) {
    for &d in drops {
        if d.life <= 0.0 { continue; }
        d.life -= dt;
        d.vel.y += 500.0 * dt;
        d.pos = d.pos + d.vel * float2 { dt, dt };
    }
}

fn draw_drops(out: Inst[>..]&) {
    for d in drops {
        if d.life <= 0.0 { continue; }
        glow(out, d.pos, float2 { d.size, d.size }, 0.35, with_alpha(d.color, clamp(d.life * 4.0, 0.0, 1.0)));
    }
}

fn drops_alive() -> bool {
    for d in drops { if d.life > 0.0 { return true; } }
    false
}

// --- a finished potion: the stopper drops in and a label slides on --------------------------

fn draw_completion(out: Inst[>..]&, i: i64, b: Bottle, pos: float2, half: float2) {
    if i >= 0 && busy(i) { return; }        // still being poured into
    let c = palette_color(flask_color(b), save.color_safe);
    let since = if i >= 0 { now - complete_at[i] } else { 10.0 };
    let neck = pos - float2 { 0.0, half.y - half.x * 0.35 };
    let fall = (1.0 - bounce_in(since / 0.4)) * half.x * 3.0;
    let a = clamp(since * 8.0, 0.0, 1.0) as f32;
    var seal = inst(Shape.Seal, neck - float2 { 0.0, half.x * 0.1 + fall }, float2 { half.x * 0.55, half.x * 0.55 }, c);
    seal.color.w = a;
    out.push(seal);
    // The label, sliding on once the stopper is in.
    var k = clamp((since - 0.35) / 0.35, 0.0, 1.0);
    // Out of the way while a flask pours close by, as its text would show over it.
    for p in pours {
        if p.active && i >= 0 && (abs(slots[p.to].pos.x - pos.x) < half.x * 5.0 && abs(slots[p.to].pos.y - pos.y) < half.y * 2.0) {
            k = 0.0;
        }
    }
    if k <= 0.0 { return; }
    let e = (1.0 - (1.0 - k) * (1.0 - k)) as f32;
    let name = COLOR_NAMES[clamp(flask_color(b), 0, COLOR_NAMES.len - 1)];
    let w = max(text_width(TextStyle.Tiny, name) * 0.5 + 6.0, half.x * 0.8);
    let lp = float2 { pos.x + (1.0 - e) * half.x * 2.0, pos.y + half.y * 0.3 };
    var label = inst(Shape.Label, lp, float2 { w, 10.0 }, float4 { 1.0, 1.0, 1.0, e });
    label.p1 = c;
    out.push(label);
    text(0, lp.x, lp.y + 1.5, name, TextStyle.Tiny, float4 { 0.28, 0.17, 0.08, e }, Align.Center);
}

fn completing() -> bool {
    for t in complete_at { if now - t < 0.8 { return true; } }
    false
}

// --- buttons squash and spring back -------------------------------------------------------

var press_center: float2[8];
var press_at: f64[8] = [-10.0; 8];
var next_press = 0;

fn note_press(center: float2) {
    press_center[next_press] = center;
    press_at[next_press] = now;
    next_press = (next_press + 1) % press_at.len;
}

// 1 just pressed (squashed), swinging back to 0.
fn press_squash(center: float2) -> f32 {
    for k in press_at.len {
        let c = press_center[k];
        let t = now - press_at[k];
        if t < 0.6 && abs(c.x - center.x) < 0.5 && abs(c.y - center.y) < 0.5 {
            return (exp(-t * 7.0) * cos(t * 26.0)) as f32;
        }
    }
    0.0
}

fn pressing() -> bool {
    for t in press_at { if now - t < 0.6 { return true; } }
    false
}

// --- the ink between screens -----------------------------------------------------------------
//
// Whatever changes `screen_id` during a frame, the change is held back while
// ink swirls over the old screen, then made, and the ink swirls away.

let T_COVER: f64 = 0.3;
let T_REVEAL: f64 = 0.45;

var shown_screen = Screen.Home;
var trans_to = Screen.Home;
var trans_t0: f64 = -10.0;
var trans_phase = 0;           // 0 none, 1 covering, 2 revealing
var ink_layer = Layer { buffer: gfx::Buffer { 0 } };

fn begin_transitions() { shown_screen = screen_id; }

// Called once a frame, after the frame has had its chance to change screens.
fn update_transition() {
    if screen_id != shown_screen {
        if trans_phase != 1 {
            trans_phase = 1;
            trans_t0 = now;
            play(Sfx.Swish);
        }
        trans_to = screen_id;
        screen_id = shown_screen;
    }
    if trans_phase == 1 && now - trans_t0 >= T_COVER {
        screen_id = trans_to;
        shown_screen = trans_to;
        trans_phase = 2;
        trans_t0 = now;
    } else if trans_phase == 2 && now - trans_t0 >= T_REVEAL {
        trans_phase = 0;
    }
}

fn transition_busy() -> bool { trans_phase != 0 }

// When the ink will have left the screen to see.
fn transition_reveal_at() -> f64 {
    if trans_phase == 1 { return trans_t0 + T_COVER + T_REVEAL * 0.4; }
    if trans_phase == 2 { return trans_t0 + T_REVEAL * 0.4; }
    now
}

fn draw_transition(out: Inst[>..]&) {
    if trans_phase == 0 { return; }
    let t = now - trans_t0;
    let cover = if trans_phase == 1 { ease(t / T_COVER) } else { 1.0 - ease(t / T_REVEAL) };
    let turn = if trans_phase == 1 { t * 3.0 } else { T_COVER * 3.0 + t * 3.0 };
    var ink = inst(Shape.Ink, float2 { VW * 0.5, VH * 0.5 }, float2 { VW * 0.5 + 400.0, VH * 0.5 + 200.0 },
                   rgba(1.0, 1.0, 1.0, 1.0));
    ink.p0 = float4 { cover, turn as f32, 0.0, 0.0 };
    out.push(ink);
}

// --- the finale: light flows from the potions into the Philosopher's Stone -------------------

let GLYPH_AT = float2 { 270.0, 430.0 };
let STONE_REST = float2 { 270.0, 152.0 };

// The flasks that send their light, at most 24.
fn finale_sources(out: i64[..24]&) {
    out.clear();
    for i in board.count { if board.bottles[i].n > 0 && out.len < 24 { out.push(i); } }
}

fn beam_step(n: i64) -> f64 { min(0.1, 0.9 / max(1, n)) }
fn beam_start(k: i64, n: i64) -> f64 { 0.35 + k * beam_step(n) }
let BEAM_TIME: f64 = 0.55;

// When the stone forms, when it rises, and when the Win panel shows.
fn finale_stone_at() -> f64 {
    var src: i64[..24] = [];
    finale_sources(src);
    max(1.7, beam_start(src.len - 1, src.len) + BEAM_TIME + 0.25)
}
fn finale_overlay_at() -> f64 { finale_stone_at() + 0.75 }

var finale_rung = 0;           // notes played so far
var finale_chimed = false;

fn neck_of(i: i64) -> float2 { slots[i].pos - float2 { 0.0, slots[i].half.y - slots[i].half.x * 0.2 } }

// Plays the notes as the light arrives, and the chord when the stone forms.
fn update_finale() {
    if won_at < 0.0 || screen_id != Screen.Play {
        finale_rung = 0;
        finale_chimed = false;
        return;
    }
    let t = now - won_at;
    var src: i64[..24] = [];
    finale_sources(src);
    while finale_rung < src.len && t >= beam_start(finale_rung, src.len) + BEAM_TIME {
        let c = flask_color(board.bottles[src[finale_rung]]);
        play_note(c, 0.35);
        finale_rung++;
    }
    if !finale_chimed && t >= finale_stone_at() {
        finale_chimed = true;
        var colors: i64[..16] = [];
        for i in src {
            let c = flask_color(board.bottles[i]);
            if !contains(colors, c) && colors.len < 16 { colors.push(c); }
        }
        play_chord(colors);
        play(Sfx.Win);
        burst(GLYPH_AT, 40, gold(1.0), 220.0);
        burst(GLYPH_AT, 16, float4 { 1.0, 0.4, 0.45, 1.0 }, 140.0);
    }
}

fn finale_running() -> bool { won_at >= 0.0 && screen_id == Screen.Play && now - won_at < finale_overlay_at() + 1.0 }

fn draw_finale(out: Inst[>..]&) {
    if won_at < 0.0 || screen_id != Screen.Play { return; }
    let t = now - won_at;
    let stone_at = finale_stone_at();
    let rise_at = stone_at + 0.6;
    var src: i64[..24] = [];
    finale_sources(src);
    // The room darkens a little around the circle.
    let dim = clamp(t / 0.4, 0.0, 1.0) as f32 * (1.0 - clamp((t - rise_at) / 0.4, 0.0, 1.0) as f32);
    glow(out, GLYPH_AT, float2 { 260.0, 260.0 }, 1.0, float4 { 0.02, 0.01, 0.05, 0.7 * dim });
    // The beams.
    let fade = 1.0 - clamp((t - stone_at) / 0.4, 0.0, 1.0) as f32;
    for i, k in src {
        let head = clamp((t - beam_start(k, src.len)) / BEAM_TIME, 0.0, 1.0) as f32;
        if head <= 0.0 || fade <= 0.0 { continue; }
        let a = neck_of(i);
        let ctrl = float2 { (a.x + GLYPH_AT.x) * 0.5, min(a.y, GLYPH_AT.y) - 140.0 };
        let c = palette_color(flask_color(board.bottles[i]), save.color_safe);
        curve(out, Shape.Beam, a, ctrl, GLYPH_AT, 4.0, head, with_alpha(c, fade));
        glow(out, a, float2 { 14.0, 14.0 }, 1.0, with_alpha(c, 0.6 * fade));
    }
    // The circle, drawn as the light comes, then the stone.
    let glyph_k = clamp((t - 0.2) / 1.2, 0.0, 1.0) as f32;
    let morph = clamp((t - stone_at) / 0.3, 0.0, 1.0) as f32;
    if morph < 1.0 {
        var g = inst(Shape.Glyph, GLYPH_AT, float2 { 120.0, 120.0 }, gold(0.95));
        g.p0 = float4 { glyph_k, morph, 0.0, 0.0 };
        g.misc.z = 20.0;
        out.push(g);
    }
    if t >= stone_at {
        let up = ease((t - rise_at) / 0.5);
        let p = lerp2(GLYPH_AT, STONE_REST, up);
        let pop = bounce_in((t - stone_at) / 0.35);
        let r = (120.0 - 40.0 * up) * pop;
        let flash = clamp(1.0 - (t - stone_at) / 0.5, 0.0, 1.0) as f32;
        glow(out, p, float2 { r * 1.6, r * 1.6 }, 1.0, float4 { 1.0, 0.85, 0.6, 0.7 * flash });
        var s = inst(Shape.Stone, p, float2 { r, r }, rgba(1.0, 1.0, 1.0, 1.0));
        s.p0 = float4 { 0.6 + 0.4 * flash, 0.0, 0.0, 0.0 };
        out.push(s);
    }
}

// --- all of it -----------------------------------------------------------------------------------

fn update_fx(dt: f32) {
    update_drops(dt);
    update_finale();
}

// Whether any of it is moving and wants full frame rate.
fn fx_lively() -> bool {
    dropping() || sloshing() || drops_alive() || completing() || pressing() || transition_busy() ||
    finale_running() || back_shelf_lively()
}
