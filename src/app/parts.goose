// What a flask can have, drawn: its body (a vow band, a siphon's tap, an
// hourglass's stand, an athanor's hearth, a moonpetal's bloom), its cover
// (wax, rime, a shroud, a vine, a curtain), what stands by it (a brazier, a
// lantern, a catalyst's runes, a vine's roots), a key in its liquid, the
// door before it and the salamander.
//
// Every part hangs off a few points of the flask worked out in one place,
// flask_anchors, so a new way of drawing flasks only has to move those.
//
// Part of the game in main.goose: it reads the game's state as main.goose's
// other parts do, and the forces' animations (forces.goose) for how far
// each change has got.

import std;
import vec;
import math;
import core.board;
import .draw;
import .palette;
import .text;

// The flask as the shader draws it (shaders.goose): a glass cylinder seen
// from above at a slant, its rim and bottom ellipses FLASK_E of its half
// width deep, its body FLASK_BODY of the lip's width, the liquid's column a
// little narrower still.
let FLASK_E: f32 = 0.36;
let FLASK_BODY: f32 = 0.92;
let LIQUID_W: f32 = 0.84;

// Where a flask's parts go, in the flask's own frame: offsets from its
// middle before it is turned or squashed. `at` places them on the screen.
struct Anchors {
    center: float2,     // the flask's middle, on the screen
    half: float2,       // its half size
    hx: f32,            // its half width, the unit parts are sized in
    angle: f32,         // turned by (radians)
    squash: f32,        // squashed upright, 1 when not
    rim: float2,        // the middle of the opening
    lip: float2,        // the near edge of the rim
    neck: float2,       // just under the rim, on the near side
    shoulder: float2,   // below that, where a band goes round
    body: float2,       // the middle of the liquid
    base: float2,       // the middle of the bottom, where it stands
    side: float2,       // the right of the body, low down (left is its mirror)
    hang: f32 = 1.0,    // the side a lantern's crook rises on: 1 right, -1 left
    room: f32 = 2.0,    // the free space over the rim's middle, in half widths, for a lantern
}

fn flask_anchors(pos: float2, half: float2, angle: f32, squash: f32) -> Anchors {
    let hx = half.x;
    let ry = hx * FLASK_E;
    let top = -half.y + ry;
    let bottom = half.y - ry * FLASK_BODY;
    Anchors { center: pos, half: half, hx: hx, angle: angle, squash: squash,
              rim: float2 { 0.0, top },
              lip: float2 { 0.0, top + ry },
              neck: float2 { 0.0, top + ry + hx * 0.25 },
              shoulder: float2 { 0.0, top + ry + hx * 0.55 },
              body: float2 { 0.0, (top + ry + bottom) * 0.5 },
              base: float2 { 0.0, bottom },
              side: float2 { hx * FLASK_BODY, bottom - hx * 0.45 } }
}

// The middle of the near face of liquid segment k, relative to the flask's
// middle, from the bottom up. The shader shares the flask's height among
// its cap's segments less SHADER_EXTRA half widths of glass.
let SHADER_EXTRA: f32 = 1.25;

fn segment_center(half: float2, k: i64) -> float2 {
    let hx = half.x;
    let cap = max(CAP, ((half.y * 2.0 / hx - FLASK_EXTRA) / SEGMENT + 0.5) as! i64);
    let seg = (half.y * 2.0 - hx * SHADER_EXTRA) / cap;
    let base = half.y - hx * FLASK_E * FLASK_BODY - hx * 0.05;
    float2 { 0.0, base + hx * LIQUID_W * FLASK_E - (k + 0.5) * seg }
}

// The middle of the liquid's surface with `fill` layers in a flask of
// `cap`, relative to the flask's middle, as the shader draws it upright.
fn surface_mid(half: float2, cap: i64, fill: f32) -> float2 {
    let hx = half.x;
    let seg = (half.y * 2.0 - hx * SHADER_EXTRA) / max(cap, CAP);
    float2 { 0.0, half.y - hx * FLASK_E * FLASK_BODY - hx * 0.05 - fill * seg }
}

// A point in the flask's frame (an anchor plus an offset), on the screen.
fn at(a: Anchors, local: float2) -> float2 {
    let y = local.y * a.squash;
    let c = cos(a.angle);
    let s = sin(a.angle);
    float2 { a.center.x + c * local.x - s * y, a.center.y + s * local.x + c * y }
}

// An instance of a part that turns with the flask.
fn part(shape: Shape, a: Anchors, local: float2, half: float2, color: float4) -> Inst {
    var i = inst(shape, at(a, local), half, color);
    i.misc.y = a.angle;
    i
}

// The text layer numbers on flasks go in: 1 when drawn over an overlay.
var parts_layer = 0;

let PARCHMENT_INK = float4 { 0.24, 0.15, 0.07, 1.0 };

// --- the body ---------------------------------------------------------------------------

// What of the body is behind the glass: the moonpetal's lotus.
fn draw_body_back(out: Inst[>..]&, b: Bottle, a: Anchors, open: f32) {
    if b.body != Body.Moonpetal { return; }
    let h = float2 { a.hx * 1.5, a.hx * 1.9 };
    var i = part(Shape.Bloom, a, a.base - float2 { 0.0, h.y - a.hx * 0.1 }, h, rgba(1.0, 1.0, 1.0, 0.9));
    i.p0 = float4 { open, 0.0, 0.0, 0.0 };
    out.push(i);
}

// A siphon's tap, in the flask's frame: low on the right, its pipe through
// the glass. Liquid leaves at tap_spout.
fn tap_at(a: Anchors) -> float2 { a.side + float2 { a.hx * 0.3, 0.0 } }
fn tap_spout(a: Anchors) -> float2 { at(a, tap_at(a) + float2 { a.hx * 0.25, a.hx * 0.33 }) }

// What of the body is on the glass: the vow's band, the tap, the bud.
fn draw_body(out: Inst[>..]&, i: i64, b: Bottle, a: Anchors, open: f32, safe: bool) {
    let hx = a.hx;
    match b.body {
        Vow => {
            var r = part(Shape.Ribbon, a, a.shoulder + float2 { 0.0, hx * 0.22 }, float2 { hx * 1.2, hx * 0.8 }, rgba(1.0, 1.0, 1.0, 1.0));
            let vowed = b.vow != 0;
            // It flashes in its color as it takes it (forces.goose).
            let flash = if i >= 0 { vow_flash(i) } else { 0.0 };
            r.p0 = float4 { if vowed { 1.0 } else { 0.0 }, flash, i * 0.37, 0.0 };
            r.p1 = if vowed { palette_color(b.vow, safe) } else { float4_0 };
            out.push(r);
            if vowed && safe && a.angle == 0.0 {
                var s = part(Shape.Symbol, a, a.shoulder + float2 { 0.0, hx * 0.12 }, float2 { hx * 0.13, hx * 0.13 }, rgba(1.0, 1.0, 1.0, 0.9));
                s.p0 = float4 { b.vow, 0.0, 0.0, 0.0 };
                out.push(s);
            }
        },
        Siphon => out.push(part(Shape.Tap, a, tap_at(a), float2 { hx * 0.6, hx * 0.45 }, rgba(1.0, 1.0, 1.0, 1.0))),
        Moonpetal => {
            var bud = part(Shape.Bloom, a, a.rim - float2 { 0.0, hx * 0.36 }, float2 { hx * 0.75, hx * 0.75 }, rgba(1.0, 1.0, 1.0, 1.0));
            bud.p0 = float4 { open, 1.0, 0.0, 0.0 };
            out.push(bud);
        },
        Plain, Hourglass, Athanor => {},
    }
}

// --- the cover --------------------------------------------------------------------------

// How a cover looks this moment: the forces' animations set these.
struct CoverLook {
    soft: f32 = 0.0,        // a seal softened, 0..1
    crack: f32 = 0.0,       // a seal cracking, 0..1
    shatter: f32 = 0.0,     // ice shattering, 0..1
    grow: f32 = 1.0,        // a tendril grown, 0..1
    wither: f32 = 0.0,      // a vine withered, 0..1
    burn: f32 = 0.0,        // a tendril burnt, 0..1
}

fn draw_cover(out: Inst[>..]&, i: i64, b: Bottle, a: Anchors, look: CoverLook, safe: bool) {
    let hx = a.hx;
    let pos = a.center;
    match b.cover {
        Rime => {
            var ice = inst(Shape.Ice, pos, a.half + float2 { hx * 0.12, hx * 0.12 }, rgba(1.0, 1.0, 1.0, 1.0));
            let thaw: i64 = b.thaw;
            let thick = clamp((thaw - 1) / 5.0, 0.0, 1.0) as f32;
            ice.p0 = float4 { thick, look.shatter, (i * 0.37) % 1.0, 0.0 };
            out.push(ice);
            if look.shatter < 0.3 {
                // How many pours it has left, on a dark frosted disc.
                let c = at(a, a.body);
                glow(out, c, float2 { hx * 0.58, hx * 0.58 }, 0.6, float4 { 0.06, 0.16, 0.3, 0.6 });
                text_shadowed(parts_layer, c.x, c.y, str(b.thaw), if hx < 22.0 { TextStyle.Small } else { TextStyle.Heading }, rgba(0.95, 0.99, 1.0, 1.0), Align.Center);
            }
        },
        Shroud => out.push(inst(Shape.Cloth, pos + float2 { 0.0, hx * 0.15 }, a.half + float2 { hx * 0.2, hx * 0.15 },
                                float4 { 0.17, 0.13, 0.32, 1.0 })),
        Seal => draw_wax(out, b.key, a, look.soft, look.crack, (i * 0.618) % 1.0, 1.0, safe),
        Vine => draw_vines(out, a, look.grow, look.wither, look.burn, (i * 0.414) % 1.0, 1.0),
        Curtain => draw_curtain(out, a, b.badge, 0.0, safe),
        None => {},
    }
}

let CURTAIN_COLOR = float4 { 0.5, 0.08, 0.12, 1.0 };

// A curtain on a rod over the flask, `up` 0..1 drawn up and away, with its
// color's badge on it.
fn draw_curtain(out: Inst[>..]&, a: Anchors, badge: i64, up: f32, safe: bool) {
    let hx = a.hx;
    let alpha = 1.0 - up;
    let c = a.center + float2 { up * hx * 0.3, hx * 0.05 - up * a.half.y * 1.1 };
    var cl = inst(Shape.Cloth, c, a.half + float2 { hx * 0.18, hx * 0.1 }, with_alpha(CURTAIN_COLOR, alpha));
    cl.p0 = float4 { 1.0, 0.0, 0.0, 0.0 };
    cl.misc.z = 6.0;
    out.push(cl);
    // The badge: a disc of the color that opens it, on a gold ring.
    let bp = c - float2 { 0.0, a.half.y * 0.15 };
    let r = hx * 0.42;
    glow(out, bp + float2 { 0.0, r * 0.2 }, float2 { r * 1.5, r * 1.5 }, 0.6, float4 { 0.0, 0.0, 0.0, 0.4 * alpha });
    rect(out, bp, float2 { r, r }, r, with_alpha(palette_color(badge, safe), alpha));
    ring(out, bp, r, max(1.5, r * 0.18), float4 { 0.95, 0.78, 0.42, alpha });
    if safe {
        var s = inst(Shape.Symbol, bp, float2 { r * 0.7, r * 0.7 }, rgba(1.0, 1.0, 1.0, 0.95 * alpha));
        s.p0 = float4 { badge, 0.0, 0.0, 0.0 };
        out.push(s);
    }
}

// --- keys and doors -----------------------------------------------------------------------

// A key's metal.
fn key_tint(k: KeyColor) -> float4 {
    match k {
        Brass => float4 { 0.86, 0.66, 0.3, 1.0 },
        Silver => float4 { 0.8, 0.83, 0.88, 1.0 },
        Copper => float4 { 0.8, 0.42, 0.24, 1.0 },
        None => float4 { 0.5, 0.5, 0.5, 1.0 },
    }
}

// A key `u` across each way from `c`, tilted a little; glint 0..1 flashes it.
fn draw_key(out: Inst[>..]&, c: float2, u: f32, k: KeyColor, glint: f32, alpha: f32) {
    var i = inst(Shape.Key, c, float2 { u, u * 0.5 }, with_alpha(key_tint(k), alpha));
    i.p0 = float4 { glint, 0.0, 0.0, 0.0 };
    i.misc.y = -0.25;
    i.misc.z = u * 0.3;
    out.push(i);
}

// The key in a flask's liquid, at its layer: in view unless smoke or a
// cover hides its layer.
fn draw_flask_key(out: Inst[>..]&, b: Bottle, a: Anchors) {
    let k = key_segment(b);
    if b.key_color == KeyColor.None || k < 0 || murky(b, k) || contents_hidden(b) { return; }
    draw_key(out, at(a, segment_center(a.half, k)), a.hx * 0.62, b.key_color, 0.0, 1.0);
}

// A door from lo to hi (its top left and bottom right), drawn `up` 0..1
// slid up and faded as it opens.
fn draw_door(out: Inst[>..]&, lo: float2, hi: float2, k: KeyColor, up: f32) {
    let half = (hi - lo) * float2 { 0.5, 0.5 };
    let c = (lo + hi) * float2 { 0.5, 0.5 } - float2 { 0.0, up * half.y * 0.8 };
    let alpha = 1.0 - up * up;
    glow(out, c + float2 { 6.0, 8.0 }, half + float2 { 10.0, 10.0 }, 0.5, float4 { 0.0, 0.0, 0.0, 0.45 * alpha });
    var d = inst(Shape.Door, c, half, float4 { 0.42, 0.27, 0.15, alpha });
    d.p1 = key_tint(k);
    out.push(d);
}

fn draw_wax(out: Inst[>..]&, key: i64, a: Anchors, soft: f32, crack: f32, seed: f32, alpha: f32, safe: bool) {
    let hx = a.hx;
    // Over the whole opening, running down the near side.
    let c = at(a, a.rim + float2 { 0.0, hx * 0.62 });
    var w = inst(Shape.Wax, c, float2 { hx * 1.1, hx * 1.43 }, with_alpha(palette_color(key, safe), alpha));
    w.p0 = float4 { soft, crack, seed, 0.0 };
    w.misc.y = a.angle;
    out.push(w);
    if safe {
        let m = at(a, a.rim + float2 { 0.0, hx * (0.72 + 0.26 * soft) });
        var s = inst(Shape.Symbol, m, float2 { hx * 0.26, hx * 0.26 }, rgba(1.0, 1.0, 1.0, alpha));
        s.p0 = float4 { key, 0.0, 0.0, 0.0 };
        out.push(s);
    }
}

fn draw_vines(out: Inst[>..]&, a: Anchors, grow: f32, wither: f32, burn: f32, seed: f32, alpha: f32) {
    let hx = a.hx;
    var v = inst(Shape.Vines, a.center, a.half + float2 { hx * 0.25, hx * 0.12 }, rgba(1.0, 1.0, 1.0, alpha));
    v.p0 = float4 { grow, wither, burn, seed };
    out.push(v);
}

// --- what stands by it --------------------------------------------------------------------
//
// These stay where the flask stands when it is lifted: `a` is its place.

struct StandLook {
    flare: f32 = 0.0,       // a brazier's or hearth's sudden heat, a lantern's flash
    wither: f32 = 0.0,      // a vine root dying
    lit: f32 = -1.0,        // a lantern's light, -1 for the flask's own state
    dial: f32 = -1.0,       // an hourglass's dial filling again as it turns over, 0..1; -1 when not
}

// Behind the flask: a brazier's flames, an athanor's hearth, the hourglass's
// stand, a catalyst's runes, a lantern over the rim.
fn draw_stand_back(out: Inst[>..]&, i: i64, b: Bottle, a: Anchors, look: StandLook) {
    let hx = a.hx;
    let base = at(a, a.base);
    match b.body {
        Hourglass => out.push(inst(Shape.Frame, a.center, float2 { hx * 1.42, a.half.y + hx * 0.06 }, rgba(1.0, 1.0, 1.0, 1.0))),
        Athanor => {
            // A low brick hearth the flask stands in, no higher than its foot.
            var f = inst(Shape.Furnace, base - float2 { 0.0, hx * 0.42 }, float2 { hx * 1.3, hx * 0.62 }, rgba(1.0, 1.0, 1.0, 1.0));
            f.p0 = float4 { 0.0, look.flare, 0.0, 0.0 };
            out.push(f);
            glow(out, base - float2 { 0.0, hx * 0.3 }, float2 { hx * 1.5, hx * 0.7 }, 1.0,
                 float4 { 1.0, 0.45, 0.12, 0.15 + 0.3 * look.flare });
        },
        Plain, Vow, Siphon, Moonpetal => {},
    }
    match b.fixture {
        Lantern => {
            let lit = if look.lit >= 0.0 { look.lit } else if b.lit { 1.0 } else { 0.0 };
            draw_lantern(out, a, lit, look.flare, i);
        },
        Brazier => {
            var f = inst(Shape.Brazier, base - float2 { 0.0, hx * 0.75 }, float2 { hx * 1.4, hx * 0.75 }, rgba(1.0, 1.0, 1.0, 1.0));
            f.p0 = float4 { 0.0, look.flare, 0.0, 0.0 };
            f.misc.z = hx * 0.5;
            out.push(f);
        },
        Catalyst => {
            let pulse = (0.5 + 0.5 * sin(now * 2.2 + i)) as f32;
            let c = if b.spent { float4 { 0.45, 0.42, 0.5, 0.4 } } else { float4 { 0.85, 0.6, 1.0, 1.0 } };
            if !b.spent { glow(out, base, float2 { hx * 1.7, hx * 0.6 }, 1.0, float4 { 0.6, 0.3, 0.9, 0.3 + 0.15 * pulse }); }
            rune_circle(out, base + float2 { 0.0, hx * 0.04 }, hx * 1.3, c);
        },
        None, VineRoot => {},
    }
}

// A catalyst's circle of runes, lying flat round a flask's foot.
fn rune_circle(out: Inst[>..]&, center: float2, r: f32, color: float4) {
    var g = inst(Shape.Glyph, center, float2 { r, r }, color);
    g.p0 = float4 { 1.0, 0.0, 0.0, 0.0 };
    g.misc.w = 0.3;
    out.push(g);
}

// In front: a brazier's bowl, the hearth's coals, the dial, a vine's roots.
fn draw_stand_front(out: Inst[>..]&, i: i64, b: Bottle, a: Anchors, look: StandLook) {
    let hx = a.hx;
    let base = at(a, a.base);
    match b.body {
        Hourglass => {
            // On the stand's post, clear of the glass and of the next column.
            let c = at(a, float2 { hx * 1.2, 0.0 });
            let every: i64 = b.flip_every;
            var left: f32 = max(0, every - b.flip_count);
            // Run out, it fills again pip by pip as the flask turns over.
            if look.dial >= 0.0 && left == 0.0 {
                left = every * look.dial;
                glow(out, c, float2 { hx * 0.9, hx * 0.9 }, 1.0, float4 { 1.0, 0.8, 0.4, 0.6 * sin(look.dial * 3.14159) });
            }
            var d = inst(Shape.Dial, c, float2 { hx * 0.36, hx * 0.36 }, rgba(1.0, 1.0, 1.0, 1.0));
            d.p0 = float4 { b.flip_every, left, 0.0, 0.0 };
            d.misc.z = hx * 0.3;
            out.push(d);
            text(parts_layer, c.x, c.y + 0.5, str((left + 0.5) as! i64), TextStyle.Tiny, PARCHMENT_INK, Align.Center);
        },
        Athanor => {
            var f = inst(Shape.Furnace, base + float2 { 0.0, hx * 0.22 }, float2 { hx * 1.2, hx * 0.3 }, rgba(1.0, 1.0, 1.0, 1.0));
            f.p0 = float4 { 1.0, look.flare, 0.0, 0.0 };
            out.push(f);
        },
        Plain, Vow, Siphon, Moonpetal => {},
    }
    match b.fixture {
        Brazier => {
            var f = inst(Shape.Brazier, base + float2 { 0.0, hx * 0.28 }, float2 { hx * 1.25, hx * 0.42 }, rgba(1.0, 1.0, 1.0, 1.0));
            f.p0 = float4 { 1.0, look.flare, 0.0, 0.0 };
            out.push(f);
        },
        VineRoot => draw_roots(out, b, a, look.wither, 1.0),
        None, Lantern, Catalyst => {},
    }
}

// A lantern hangs over the rim from a shepherd's crook rising from behind
// the flask on the side a.hang says. It stands in the free space over the
// rim (a.room), as large as fits there, and is drawn behind everything in
// front of it, so it covers no other flask's liquid or count.
fn lantern_unit(a: Anchors) -> f32 { max(clamp((a.room - 0.1) / 1.76, 0.6, 1.0) * a.hx, 12.0) }
fn lantern_pos(a: Anchors) -> float2 { at(a, a.rim) - float2 { 0.0, a.hx * 0.1 + lantern_unit(a) * 0.65 } }

fn draw_lantern(out: Inst[>..]&, a: Anchors, lit: f32, flare: f32, seed: i64) {
    let hx = a.hx;
    let u = lantern_unit(a);
    let c = lantern_pos(a);
    if lit > 0.0 {
        glow(out, c, float2 { hx * 2.2, hx * 2.0 }, 1.0, float4 { 1.0, 0.75, 0.4, 0.3 * lit + 0.4 * flare });
    }
    // The crook's post stands inside the flask's outline, its foot well down behind the glass.
    let post = a.hang * min(hx * 0.72 / u, 1.2);
    let foot = min((hx * 0.6 + u * 0.65) / u, 1.75);
    var l = inst(Shape.Lantern, c, float2 { u * 1.3, u * 1.85 }, rgba(1.0, 1.0, 1.0, 1.0));
    l.p0 = float4 { lit, flare, seed * 1.7, 0.0 };
    l.p1 = float4 { post, foot, 0.0, 0.0 };
    l.misc.z = u * 0.4;
    out.push(l);
}

fn draw_roots(out: Inst[>..]&, b: Bottle, a: Anchors, wither: f32, alpha: f32) {
    let hx = a.hx;
    // In front of the foot, on the table, clear of the liquid.
    let base = at(a, a.base + float2 { 0.0, hx * 0.38 });
    let every: i64 = b.spread_every;
    let left = max(0, every - b.spread_count);
    let ripe: f32 = if left <= 1 { 1.0 } else { clamp(b.spread_count / max(1.0, every - 1.0), 0.0, 0.9) as f32 };
    var r = inst(Shape.Roots, base, float2 { hx * 1.45, hx * 1.0 }, rgba(1.0, 1.0, 1.0, alpha));
    r.p0 = float4 { wither, ripe, 0.3, 0.0 };
    out.push(r);
    if b.fixture == Fixture.VineRoot && alpha >= 1.0 {
        text(parts_layer, base.x, base.y + hx * 0.03, str(left), TextStyle.Tiny, float4 { 0.1, 0.16, 0.05, 1.0 }, Align.Center);
    }
}

// --- between flasks, and on them ------------------------------------------------------------

// The salamander at `at` (its feet), facing 1 right or -1 left; leap 0..1
// stretches it out.
fn draw_salamander(out: Inst[>..]&, feet: float2, hx: f32, angle: f32, facing: f32, leap: f32, heat: f32) {
    let u = max(hx * 1.25, 16.0);
    var s = inst(Shape.Salamander, feet - float2 { 0.0, u * 0.25 }, float2 { u * 1.05, u * 0.7 }, rgba(1.0, 1.0, 1.0, 1.0));
    s.p0 = float4 { 0.37, facing, leap, heat };
    s.misc.y = angle;
    s.misc.z = u * 0.3;
    out.push(s);
}
