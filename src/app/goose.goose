// The goose: a secret on the title screen, and a nod to Goose, the
// language the game is brewed in. Now and then a goose peeks over the far
// end of the bench, looks about, and ducks away again. Tap it while it
// peeks and it hops up onto the bench, fluffs itself up and bobs its head
// at you, indignant; it dashes off, stops dead, doubles back, thinks
// better of it, then spreads its wings wide and charges, neck stretched
// out low, hissing, and barges breast first into the little yellow
// vial. Over goes the vial with a splash
// and a puff of sparkles; the goose honks, a feather or two drifting down,
// folds its wings and storms off home behind the bench. A moment later the
// vial is back in its place. Tap it on the bench and it spreads its wings
// and honks at you.
//
// Part of the title screen in menus.goose: the goose stands along the
// bench's front, and takes no click but those on itself. Everything is
// timed from `now`, so a slow frame rate only makes it step.

import std;
import vec;
import math;
import core.board;
import .draw;
import .shaders;
import .palette;
import .sfx;

let GOOSE_U: f32 = 62.0;            // its unit: from its feet to its crown is about one and a half
let GOOSE_HOME: f32 = 494.0;        // where it lives, behind the bench between the pink vial and a candle
let BENCH_TOP: f32 = 620.0;         // where the bench's things stand, and the edge it hides behind
let GOOSE_ON: f32 = 625.0;          // where it stands: along the bench's front, before its things
let PEEK_GROUND: f32 = 681.0;       // where its feet are as it peeks, its head over the edge
let HIDDEN_GROUND: f32 = 716.0;     // and where they are when it is out of sight

// The vial it knocks over: where it stands on the bench, and what is in it.
let GOOSE_VIAL_X: f32 = 390.0;
let GOOSE_VIAL: const i64[2] = [3, 3];
let GOOSE_VIAL_HX: f32 = 13.0;

// What the goose is doing: out of sight, peeking over the bench, or out on it.
enum GooseAct { Away, Peek, Romp }

var goose_act = GooseAct.Away;
var goose_from: f64 = 0.0;          // when the act began
var goose_next: f64 = 0.0;          // when it next peeks
var goose_last: f64 = 0.0;          // the act's clock at the last frame, for its cues
var goose_drawn: f64 = -9.0;        // when the title screen was last drawn
var goose_fluster: f64 = -9.0;      // when it was last tapped on the bench

// A peek, in seconds: up over the edge, a look round, and down again.
let PEEK_TIME: f64 = 5.0;

// The romp, in seconds from the tap.
let G_HOPPED: f64 = 0.7;            // up on the bench
let G_HIT: f64 = 3.5;               // it runs into the vial
let G_POP: f64 = 3.88;              // the vial, tipped over, pops
let G_HOME: f64 = 5.8;              // stormed off home
let G_GONE: f64 = 6.5;              // down behind the bench
let G_VIAL_BACK: f64 = 7.0;         // the vial comes back
let G_END: f64 = 7.8;

// Its way along the bench: from time t0 to t1 it goes from x0 to x1 in so
// many steps, so it stops with both feet down. Between them it stands.
struct Leg { t0: f64, t1: f64, x0: f32, x1: f32, steps: f32 }

let GOOSE_LEGS: const Leg[5] = [
    Leg { t0: 1.5, t1: 1.85, x0: 494.0, x1: 456.0, steps: 4.0 },    // a dash
    Leg { t0: 2.3, t1: 2.55, x0: 456.0, x1: 486.0, steps: 3.0 },    // back, the other way
    Leg { t0: 3.1, t1: 3.5, x0: 486.0, x1: 432.0, steps: 6.0 },     // the charge: its breast meets the vial
    Leg { t0: 3.5, t1: 3.64, x0: 432.0, x1: 442.0, steps: 1.0 },    // bounced back off it
    Leg { t0: 4.9, t1: 5.8, x0: 442.0, x1: 494.0, steps: 6.0 },     // and home in a huff
];

// How the shader poses it (Shape.Goose).
struct GoosePose {
    x: f32 = 0.0,
    ground: f32 = 0.0,              // its feet, in canvas units
    facing: f32 = -1.0,             // -1 left, 1 right, nearer 0 as it turns
    phase: f32 = 1.5707963,         // the walk's, in radians: PI/2 is standing
    neck: f32 = 0.0,                // -1 stretched forward low, 1 stretched up
    look: f32 = 0.0,                // 0 in profile, 1 its head turned to us
    beak: f32 = 0.0,
    spread: f32 = 0.0,              // its wings, folded 0 to spread wide 1
    blink: f32 = 0.0,
    fluff: f32 = 0.0,
}

// 0..1 as e goes from a to b, held outside.
fn span(e: f64, a: f64, b: f64) -> f64 { clamp((e - a) / (b - a), 0.0, 1.0) }
fn eased(e: f64, a: f64, b: f64) -> f32 { ease(span(e, a, b)) }
// Up and down again, 0..1..0, over a..b.
fn bump(e: f64, a: f64, b: f64) -> f32 { sin(span(e, a, b) * PI) as f32 }
// n beats over a..b, each 0..1..0: wings flapping, a head bobbing.
fn pulses(e: f64, a: f64, b: f64, n: f64) -> f32 { (0.5 - 0.5 * cos(span(e, a, b) * n * TAU)) as f32 }
// How long it glares when tapped on the bench.
let GOOSE_GLARE: f64 = 1.4;

// A blink at time a.
fn blink_at(e: f64, a: f64) -> f32 { bump(e, a, a + 0.16) }

fn peek_pose(e: f64) -> GoosePose {
    var g = GoosePose { .. };
    let shown = eased(e, 0.0, 0.8) * (1.0 - eased(e, PEEK_TIME - 0.8, PEEK_TIME));
    g.x = GOOSE_HOME;
    g.ground = HIDDEN_GROUND + (PEEK_GROUND - HIDDEN_GROUND) * shown;
    // It looks at us, blinks, glances back over its shoulder.
    g.look = eased(e, 1.0, 1.3) * (1.0 - eased(e, 2.0, 2.3));
    g.facing = -cos((eased(e, 2.6, 2.8) - eased(e, 3.4, 3.6)) * PI);
    g.neck = 0.25 * shown;
    g.blink = max(blink_at(e, 1.6), blink_at(e, 3.9));
    g
}

// Where it is along the bench, and the walk's phase.
fn goose_way(e: f64) -> f32, f32 {
    var x = GOOSE_HOME;
    var steps: f32 = 0.0;
    for l in GOOSE_LEGS {
        if e < l.t0 { break; }
        let k = span(e, l.t0, l.t1) as f32;
        x = l.x0 + (l.x1 - l.x0) * k;
        steps += l.steps * k;
    }
    return x, PI * 0.5 + PI * steps;
}

fn romp_pose(e: f64) -> GoosePose {
    var g = GoosePose { .. };
    // Up onto the bench in a hop, and down behind it at the end.
    let up = span(e, 0.0, G_HOPPED) as f32;
    let down = span(e, G_HOME, G_GONE) as f32;
    g.ground = PEEK_GROUND + (GOOSE_ON - PEEK_GROUND) * up - 34.0 * bump(e, 0.0, G_HOPPED);
    if e > G_HOME { g.ground = GOOSE_ON + (HIDDEN_GROUND - GOOSE_ON) * down - 16.0 * bump(e, G_HOME, G_GONE); }
    let x, phase = goose_way(e);
    g.x = x;
    g.phase = phase;
    // It stops dead and turns about, turns back, and at last turns for home.
    g.facing = -cos((eased(e, 2.12, 2.28) - eased(e, 2.66, 2.8) + eased(e, 4.6, 4.8)) * PI);
    // Its neck: up and bobbing at us, out forward to run, bobbing at each
    // stop, out low and level to hiss as it sets off, reared up as it barges
    // in breast first, up to honk, and held high going home.
    let necks: f64[14] = [0.0, 0.5, 0.5, -0.3, -0.3, 0.3, -0.2, 0.2, -1.0, -1.0, 0.6, 0.9, 0.9, 0.6];
    let at: f64[14] = [G_HOPPED, 0.9, 1.45, 1.6, 1.9, 2.0, 2.4, 2.55, 2.95, 3.15, 3.38, G_HIT + 0.2, 4.5, 4.8];
    var n = necks[0];
    for k in 1..14 {
        if e > at[k - 1] { n = necks[k - 1] + (necks[k] - necks[k - 1]) * ease((e - at[k - 1]) / (at[k] - at[k - 1])); }
    }
    let bobbing = 0.22 * (pulses(e, 0.95, 1.45, 3.0) + pulses(e, 1.95, 2.3, 2.0) + pulses(e, 4.55, 4.9, 2.0));
    g.neck = n as f32 - bobbing + 0.1 * (bump(e, G_HIT, G_HIT + 0.22) + bump(e, G_POP + 0.02, G_POP + 0.24));
    // Fluffed up from the start, more so in the flurry, still ruffled as it goes.
    g.fluff = max(eased(e, 0.75, 1.0) * (1.0 - 0.5 * eased(e, 4.6, 5.2)), bump(e, G_HIT, G_HIT + 1.0));
    // It glares at us, and again once the vial is gone.
    g.look = max(eased(e, 0.85, 1.05) * (1.0 - eased(e, 1.35, 1.5)), eased(e, 4.15, 4.3) * (1.0 - eased(e, 4.45, 4.6)));
    // A grumble, a hiss as it charges, and two honks.
    g.beak = max(max(0.4 * bump(e, 1.0, 1.2), 0.55 * eased(e, 2.7, 2.9) * (1.0 - eased(e, 3.4, 3.5))),
                 max(bump(e, G_HIT, G_HIT + 0.22), bump(e, G_POP + 0.02, G_POP + 0.24)));
    // Its wings: half spread to hop up and down, and the threat: slowly
    // out and up, wide as a cape, held trembling through the charge and the
    // honks, and slowly folded again.
    let threat = eased(e, 2.55, 3.05) * (1.0 - eased(e, 4.15, 4.75));
    let tremble = 0.03 * sin(e * 47.0) as f32 * eased(e, 3.0, 3.1) * (1.0 - eased(e, 4.1, 4.2));
    g.spread = max(max(0.5 * bump(e, 0.0, G_HOPPED), 0.4 * bump(e, G_HOME, G_GONE)), threat + tremble);
    // The knock staggers it: a little hop back, rocking.
    g.ground -= 6.0 * bump(e, G_HIT, G_HIT + 0.2);
    g.phase += 0.5 * bump(e, G_HIT, G_HIT + 0.3);
    g.blink = max(max(blink_at(e, 1.3), blink_at(e, 2.3)), max(blink_at(e, 4.7), blink_at(e, 5.4)));
    // Tapped on the bench: it spreads its wings at you, neck low, and honks.
    let f = now - goose_fluster;
    if f < GOOSE_GLARE {
        let k = eased(f, 0.0, 0.35) * (1.0 - eased(f, 0.8, GOOSE_GLARE));
        g.spread = max(g.spread, 0.85 * k);
        g.neck = g.neck + (-0.6 - g.neck) * k;
        g.beak = max(g.beak, bump(f, 0.25, 0.5));
        g.fluff = max(g.fluff, k);
    }
    g
}

fn goose_pose() -> GoosePose {
    if goose_act == GooseAct.Peek { return peek_pose(now - goose_from); }
    if goose_act == GooseAct.Romp { return romp_pose(now - goose_from); }
    var g = GoosePose { .. };
    g.ground = HIDDEN_GROUND + 40.0;
    g
}

// Plans the next peek, `wait` to `wait` * 2 seconds from now.
fn goose_rest(wait: f64) {
    goose_act = GooseAct.Away;
    goose_next = now + wait * (1.0 + hash01(now * 0.37));
}

// Whether a cue at time a of the act passed this frame.
fn goose_cue(e: f64, a: f64) -> bool { goose_last < a && e >= a }

// --- the vial ------------------------------------------------------------------------------

fn goose_vial_half() -> float2 { bottle_half(GOOSE_VIAL_HX, CAP) }

// How much of the vial stands in its place, 0..1: none once it is knocked
// over, and growing back after.
fn goose_vial_shown() -> f32 {
    if goose_act != GooseAct.Romp { return 1.0; }
    let e = now - goose_from;
    if e < G_HIT { return 1.0; }
    if e < G_VIAL_BACK { return 0.0; }
    bounce_in((e - G_VIAL_BACK) / 0.5)
}

// The vial knocked over, its angle td seconds after the goose's breast
// meets it: shoved, it tips over its left foot at once, then faster and
// faster, till it lies on its side at G_POP.
fn vial_tipped(td: f64) -> f32 {
    let s = span(td, 0.0, G_POP - G_HIT) as f32;
    -0.5 * PI * (0.3 * s + 0.7 * s * s)
}

// Its middle, turned by that angle about its bottom left corner.
fn vial_center(angle: f32) -> float2 {
    let h = goose_vial_half();
    let c = cos(angle);
    let s = sin(angle);
    v2(GOOSE_VIAL_X - h.x, BENCH_TOP) + v2(c * h.x + s * h.y, s * h.x - c * h.y)
}

fn goose_vial(out: Inst[>..]&, center: float2, angle: f32) {
    var b = Bottle { .. };
    for c, k in GOOSE_VIAL { b.seg[k] = c as u8; }
    b.n = GOOSE_VIAL.len as u8;
    draw_flask(out, -1, b, center, goose_vial_half(), angle, b.n, 0.0, 0.0, gold(1.0), false);
}

// --- each frame ----------------------------------------------------------------------------

// Moves the goose on and takes the clicks on it. Called by draw_home.
fn update_goose() {
    // Back on the title screen after a while: it starts out of sight.
    if now - goose_drawn > 0.5 {
        goose_act = GooseAct.Away;
        goose_next = now + 9.0 + 6.0 * hash01(now * 0.53);
        goose_last = 0.0;
    }
    goose_drawn = now;
    let e = now - goose_from;
    if goose_act == GooseAct.Away && now >= goose_next {
        goose_act = GooseAct.Peek;
        goose_from = now;
        goose_last = 0.0;
        return;
    }
    if goose_act == GooseAct.Peek {
        if e >= PEEK_TIME { goose_rest(35.0); return; }
        // Its head over the bench's edge.
        if e > 0.3 && e < PEEK_TIME - 0.4 && clicked(v2(GOOSE_HOME - 20.0, 594.0), v2(32.0, 32.0)) {
            goose_act = GooseAct.Romp;
            goose_from = now;
            goose_last = 0.0;
            play_pitched(Sfx.Rustle, 1.4, 0.5);
        }
        goose_last = e;
        return;
    }
    if goose_act != GooseAct.Romp { return; }
    if e >= G_END { goose_rest(60.0); return; }
    // Tapped on the bench: it honks and flaps at you again.
    let g = romp_pose(e);
    if e > G_HOPPED && e < G_HOME && now - goose_fluster > GOOSE_GLARE &&
       clicked(v2(g.x, GOOSE_ON - 0.8 * GOOSE_U), v2(0.85 * GOOSE_U, 0.8 * GOOSE_U)) {
        goose_fluster = now;
        play_pitched(Sfx.Rustle, 1.0, 0.4);
    }
    if goose_cue(e, 1.0) { play_pitched(Sfx.Honk, 1.35, 0.35); }
    if goose_cue(e, 2.55) { play_pitched(Sfx.Rustle, 0.9, 0.45); }
    if goose_cue(e, 2.7) { play_pitched(Sfx.Sizzle, 0.6, 0.18); }
    if goose_cue(e, G_HIT) { play_pitched(Sfx.Honk, 1.0, 0.8); }
    if goose_cue(e, 4.15) { play_pitched(Sfx.Rustle, 0.8, 0.35); }
    if goose_cue(e, G_POP) {
        play_pitched(Sfx.Pop, 1.2, 0.6);
        play_pitched(Sfx.Select, 1.45, 0.3);
        let at = vial_center(vial_tipped(G_POP - G_HIT));
        burst(at, 16, palette_color(GOOSE_VIAL[0], save.color_safe), 150.0);
        burst(at, 8, gold(1.0), 110.0);
    }
    if goose_cue(e, G_POP + 0.02) { play_pitched(Sfx.Honk, 1.15, 0.7); }
    if goose_cue(e, G_HOME + 0.05) { play_pitched(Sfx.Rustle, 1.2, 0.4); }
    if goose_cue(e, G_VIAL_BACK) { play_pitched(Sfx.Chime, 1.25, 0.25); }
    // The honk of a goose tapped on the bench, once its wings are out.
    if goose_cue(e, goose_fluster - goose_from + 0.3) { play_pitched(Sfx.Honk, 1.1, 0.75); }
    goose_last = e;
}

// The goose, over the bench's things, with the vial it knocks over, its
// pop, the feathers it loses, and the vial coming back.
fn draw_goose(out: Inst[>..]&) {
    if goose_act == GooseAct.Away { return; }
    let e = now - goose_from;
    let romp = goose_act == GooseAct.Romp;
    if romp && e >= G_HIT && e < G_POP {
        let a = vial_tipped(e - G_HIT);
        goose_vial(out, vial_center(a), a);
    }
    let g = goose_pose();
    if g.ground < HIDDEN_GROUND {
        // Its shadow on the bench, when it is up on it.
        let on = clamp(1.0 - abs(g.ground - GOOSE_ON) / 24.0, 0.0, 1.0);
        if on > 0.0 { glow(out, v2(g.x + 2.0, GOOSE_ON), v2(0.55 * GOOSE_U, 5.0), 0.9, float4 { 0.0, 0.0, 0.0, 0.4 * on }); }
        var s = inst(Shape.Goose, v2(g.x, g.ground - 0.92 * GOOSE_U), v2(1.6 * GOOSE_U, 1.6 * GOOSE_U),
                     float4 { g.fluff, 0.0, 0.0, 1.0 });
        s.p0 = float4 { g.facing, g.phase, g.neck, g.look };
        // Behind the bench, it is hidden below its far edge; up on it, not.
        let behind = !romp || e < G_HOPPED * 0.5 || e > (G_HOME + G_GONE) * 0.5;
        let edge = if behind { BENCH_TOP } else { VH };
        s.p1 = float4 { g.beak, g.spread, g.blink, (edge - (g.ground - 0.92 * GOOSE_U)) / GOOSE_U };
        s.misc.z = 0.0;
        out.push(s);
    }
    if !romp { return; }
    if e >= G_POP && e < G_POP + 0.9 {
        // A splash of its color and a puff of smoke and sparkles where it lay.
        let k = span(e, G_POP, G_POP + 0.9) as f32;
        let at = vial_center(vial_tipped(G_POP - G_HIT));
        let c = palette_color(GOOSE_VIAL[0], save.color_safe);
        glow(out, at, v2(70.0, 50.0), 1.0, with_alpha(c, 0.45 * (1.0 - k) * (1.0 - k)));
        var sm = inst(Shape.Smoke, at - v2(0.0, 8.0), v2(40.0, 30.0), white(1.0));
        sm.p0 = float4 { k, 3.7, 0.0, 0.0 };
        sm.misc.z = 20.0;
        out.push(sm);
        ring(out, at, 10.0 + 40.0 * k, 2.0 * (1.0 - k), with_alpha(gold(1.0), 0.8 * (1.0 - k)));
        for j in 5 {
            let a = j * 1.2566 + 0.4;
            let r = 14.0 + 30.0 * k;
            let tw = (sin(k * PI) * (0.6 + 0.4 * sin(e * 20.0 + j))) as f32;
            spark(out, at + v2(cos(a) as f32 * r, sin(a) as f32 * r * 0.7 - 14.0 * k), 8.0 * tw, white(0.9 * tw));
        }
    }
    draw_feathers(out, e - G_HIT);
    if e >= G_VIAL_BACK && e < G_VIAL_BACK + 0.8 {
        // A glint as it comes back.
        let h = goose_vial_half();
        let k = span(e, G_VIAL_BACK, G_VIAL_BACK + 0.8) as f32;
        let at = v2(GOOSE_VIAL_X, BENCH_TOP - h.y * 1.2);
        glow(out, at, v2(40.0, 50.0), 1.0, with_alpha(gold(1.0), 0.3 * sin(k * PI)));
        spark(out, at - v2(0.0, h.y * 0.6), 14.0 * sin(k * PI), white(0.9 * sin(k * PI)));
    }
}

// The feathers it loses in the bump, `a` seconds after: thrown up and
// out, then see-sawing down onto the bench and fading.
fn draw_feathers(out: Inst[>..]&, a: f64) {
    if a < 0.0 || a > 2.6 { return; }
    for k in 4 {
        let h1 = hash01(k * 1.73 + 0.5);
        let h2 = hash01(k * 2.91 + 1.5);
        let v = v2(((h1 - 0.5) * 220.0) as f32, (-120.0 - 110.0 * h2) as f32);
        let thrown = ((1.0 - exp(-a * 3.5)) / 3.5) as f32;
        let sway = sin(a * (3.0 + h2 * 2.0) + k * 1.9);
        var p = v2(420.0, 575.0) + v * float2 { thrown, thrown } + v2((sway * 9.0) as f32, (a * 26.0) as f32);
        p.y = min(p.y, BENCH_TOP + 2.0);
        let fade = (clamp(a / 0.1, 0.0, 1.0) * clamp((2.6 - a) / 0.6, 0.0, 1.0)) as f32;
        let turn = (sway * 0.7 + h1 * 3.0) as f32;
        glow(out, p, v2(6.5, 2.2), 0.7, float4 { 1.0, 0.98, 0.94, 0.9 * fade });
        out[out.len - 1].misc.y = turn;
        glow(out, p, v2(5.5, 0.6), 0.5, float4 { 0.55, 0.5, 0.48, 0.5 * fade });
        out[out.len - 1].misc.y = turn;
    }
}

// How far the credit line has come in, 0..1: from the honks till it is home.
fn goose_credit() -> f32 {
    if goose_act != GooseAct.Romp { return 0.0; }
    let e = now - goose_from;
    eased(e, G_HIT, G_HIT + 0.6) * (1.0 - eased(e, G_HOME, G_GONE + 0.2))
}
