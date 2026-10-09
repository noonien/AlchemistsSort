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
    hang: f32 = 1.0,    // the side a lantern hangs on: 1 right, -1 left
    open_side: bool = true, // nothing stands on that side, so the lantern can be larger
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

// A siphon at rest beads at its spout now and then, a drop of its bottom
// layer swelling and falling, so the tap reads as where it pours from.
fn draw_tap_drip(out: Inst[>..]&, i: i64, b: Bottle, a: Anchors, safe: bool) {
    if b.body != Body.Siphon || b.n == 0 || b.cover != Cover.None || b.behind { return; }
    let hx = a.hx;
    let ph = ((now / 4.2 + i * 0.37) % 1.0) as f32;
    if ph > 0.86 { return; }
    let spout = tap_spout(a) + float2 { 0.0, hx * 0.04 };
    let col = palette_color(b.seg[0], safe);
    let grow = clamp(ph / 0.66, 0.0, 1.0);
    let fall = clamp((ph - 0.66) / 0.2, 0.0, 1.0);
    let r = hx * 0.09 * sqrt(grow) * (1.0 - 0.4 * fall);
    if r < 0.6 { return; }
    let c = spout + float2 { 0.0, r * 0.9 + hx * 0.45 * fall * fall };
    let alpha = 1.0 - fall * fall;
    rect(out, c, float2 { r, r * (1.0 + 0.35 * grow) }, r, with_alpha(mix4(col, white(1.0), 0.1), alpha));
    rect(out, c - float2 { r * 0.35, r * 0.4 }, float2 { r * 0.3, r * 0.3 }, r * 0.3, white(0.7 * alpha));
}

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
                // On its last pour the ice glows, breathing.
                if thaw <= 1 {
                    let k = (0.5 + 0.5 * sin(now * 3.0 + i)) as f32;
                    glow(out, c, float2 { hx * (1.0 + 0.15 * k), hx * (1.0 + 0.15 * k) }, 1.0, float4 { 0.7, 0.9, 1.0, 0.25 + 0.25 * k });
                }
                glow(out, c, float2 { hx * 0.58, hx * 0.58 }, 0.6, float4 { 0.06, 0.16, 0.3, 0.6 });
                text_shadowed(parts_layer, c.x, c.y, str(b.thaw), if hx < 22.0 { TextStyle.Small } else { TextStyle.Heading }, rgba(0.95, 0.99, 1.0, 1.0), Align.Center);
            }
        },
        Shroud => out.push(inst(Shape.Cloth, pos + float2 { 0.0, hx * 0.15 }, a.half + float2 { hx * 0.2, hx * 0.15 },
                                float4 { 0.17, 0.13, 0.32, 1.0 })),
        Seal => draw_wax(out, b.key, a, look.soft, look.crack, (i * 0.618) % 1.0, 1.0, safe),
        Vine => draw_vines(out, a, look.grow, look.wither, look.burn, (i * 0.414) % 1.0, 1.0),
        Curtain => draw_curtain(out, a, b.badge, 0.0, 0.0, safe),
        None => {},
    }
}

let CURTAIN_COLOR = float4 { 0.5, 0.08, 0.12, 1.0 };

// The curtain's cloth over a flask drawn at `a`: as wide as the glass and a
// little more, its rod just over the rim.
fn curtain_box(a: Anchors) -> float2, float2 {
    return a.center + float2 { 0.0, a.hx * 0.05 }, a.half + float2 { a.hx * 0.18, a.hx * 0.1 };
}

// Where a curtain's badge hangs: on the drapes, just under the valance.
fn badge_at(a: Anchors) -> float2 {
    let c, half = curtain_box(a);
    c - float2 { 0.0, half.y - half.x * 0.55 - badge_r(a) * 1.05 }
}

fn badge_r(a: Anchors) -> f32 { max(a.hx * 0.45, 6.5) }

// A curtain on a rod over the flask, `open` 0..1 drawn aside, with its
// color's badge on it; `flash` 0..1 lights the badge up.
fn draw_curtain(out: Inst[>..]&, a: Anchors, badge: i64, open: f32, flash: f32, safe: bool) {
    let c, half = curtain_box(a);
    let alpha = 1.0 - clamp((open - 0.75) / 0.25, 0.0, 1.0);
    var cl = inst(Shape.Cloth, c, half, with_alpha(CURTAIN_COLOR, alpha));
    cl.p0 = float4 { 1.0, open, (a.center.x * 0.013) % 1.0, 0.0 };
    cl.misc.z = 11.0;
    out.push(cl);
    draw_badge(out, badge_at(a), badge_r(a), badge, flash, alpha * (1.0 - clamp(open * 2.5, 0.0, 1.0)), safe);
}

// A curtain's badge: a disc of the color that opens it, a gem, in a gold
// ring on a dark mount so it reads on the velvet whatever its color.
fn draw_badge(out: Inst[>..]&, c: float2, r: f32, color: i64, flash: f32, alpha: f32, safe: bool) {
    if alpha <= 0.0 { return; }
    let col = palette_color(color, safe);
    if flash > 0.0 { glow(out, c, float2 { r * 3.2, r * 3.2 }, 1.0, with_alpha(col, 0.8 * flash * alpha)); }
    glow(out, c + float2 { 0.0, r * 0.25 }, float2 { r * 1.7, r * 1.7 }, 0.6, float4 { 0.0, 0.0, 0.0, 0.45 * alpha });
    rect(out, c, float2 { r * 1.3, r * 1.3 }, r * 1.3, float4 { 0.16, 0.06, 0.06, alpha });
    ring(out, c, r * 1.12, max(1.4, r * 0.2), float4 { 0.95, 0.78, 0.42, alpha });
    rect(out, c, float2 { r, r }, r, with_alpha(mix4(col, white(1.0), 0.25 * flash), alpha));
    // The gem's shine.
    glow(out, c - float2 { r * 0.32, r * 0.36 }, float2 { r * 0.38, r * 0.28 }, 1.0, float4 { 1.0, 1.0, 1.0, 0.55 * alpha });
    if safe {
        var s = inst(Shape.Symbol, c, float2 { r * 0.7, r * 0.7 }, rgba(1.0, 1.0, 1.0, 0.95 * alpha));
        s.p0 = float4 { color, 0.0, 0.0, 0.0 };
        out.push(s);
    }
}

// --- keys and doors -----------------------------------------------------------------------

// A key's metal.
fn key_tint(k: KeyColor) -> float4 {
    match k {
        Brass => float4 { 0.9, 0.7, 0.3, 1.0 },
        Silver => float4 { 0.84, 0.87, 0.93, 1.0 },
        Copper => float4 { 0.88, 0.44, 0.27, 1.0 },
        None => float4 { 0.5, 0.5, 0.5, 1.0 },
    }
}

// A key `u` across each way from `c`, turned by `angle`; `glint` 0..1 sweeps
// a gleam along it, and `liquid` (its alpha: how far under) is the liquid it
// is seen through, which tints it.
fn draw_key(out: Inst[>..]&, c: float2, u: f32, k: KeyColor, angle: f32, glint: f32, liquid: float4, alpha: f32) {
    var i = inst(Shape.Key, c, float2 { u, u * 0.5 }, with_alpha(key_tint(k), alpha));
    i.p0 = float4 { glint, key_index(k), liquid.w, (c.x * 0.37) % 1.0 };
    i.p1 = liquid;
    i.misc.y = angle;
    i.misc.z = u * 0.3;
    out.push(i);
}

// How big a key is in a flask of half width hx.
fn key_size(hx: f32) -> f32 { hx * 0.72 }
let KEY_TILT: f32 = -0.22;

// Where the middle of layer k is on the screen in a flask drawn at `a`,
// `cap` deep, with `drain` layers run out of its bottom (less than none:
// held off it), as the liquid shader lays the layers out: along the glass
// when it is upright or the liquid turns with it (`rigid`); tipped, level,
// gathered in the lower side.
fn layer_spot(a: Anchors, cap: i64, k: i64, drain: f32, rigid: bool) -> float2 {
    let hx = a.hx;
    let seg = (a.half.y * 2.0 - hx * SHADER_EXTRA) / max(cap, CAP);
    let w = hx * LIQUID_W;
    let ry = w * FLASK_E;
    let base = a.half.y - hx * FLASK_E * FLASK_BODY - hx * 0.05;
    let v = (k + 0.5 - drain) * seg;
    if rigid || abs(a.angle) < 0.001 { return at(a, float2 { 0.0, base + ry - v }); }
    // Tipped: the level line holding the layer's middle (its volume under
    // it), and the middle of that line's stretch across the column.
    let ca = cos(a.angle);
    let sl = clamp(sin(a.angle) / max(ca, 0.05), -6.0, 6.0);
    let s = max(abs(sl), 0.0001);
    let area = v * 2.0 * w;
    let ms = if area >= 2.0 * s * w * w { area / (2.0 * w) } else { sqrt(2.0 * s * area) - s * w };
    let m = ms - ry / max(ca, 0.05);
    let lo = max(-w, -m / s);
    let xm = (w + lo) * 0.5;
    let x = if sl < 0.0 { -xm } else { xm };
    at(a, float2 { x, base - (m + sl * x) })
}

// A key catches the light now and then, each at its own moment: 0..1
// while the gleam passes, 0 otherwise.
fn key_glint(seed: f32) -> f32 {
    let ph = ((now / 3.7 + seed) % 1.0) as f32;
    if ph < 0.3 { ph / 0.3 } else { 0.0 }
}

// The key in a flask's liquid, at its layer, as the flask is drawn at `a`
// holding `b` (see layer_spot): in view unless smoke or a cover hides it.
fn draw_flask_key(out: Inst[>..]&, b: Bottle, a: Anchors, drain: f32, rigid: bool, safe: bool) {
    let k = key_segment(b);
    if b.key_color == KeyColor.None || k < 0 || murky(b, k) || contents_hidden(b) || k + 0.5 < drain { return; }
    let c = layer_spot(a, b.cap, k, drain, rigid);
    let u = key_size(a.hx);
    let glint = key_glint((a.center.x * 0.0123 + a.center.y * 0.0071) % 1.0);
    let turn = KEY_TILT + (if rigid { a.angle } else { 0.0 });
    draw_key(out, c, u, b.key_color, turn, glint, with_alpha(palette_color(b.seg[k], safe), 1.0), 1.0);
    if glint > 0.2 && glint < 0.95 {
        let f = sin((glint - 0.2) / 0.75 * PI);
        spark(out, c + float2 { -u * 0.7, -u * 0.32 }, u * 0.45 * f, white(0.9 * f));
    }
}

// A door from lo to hi (its top left and bottom right), its key's metal `k`;
// `swing` 0..1 its leaves swung open, `fade` 0..1 gone.
fn draw_door(out: Inst[>..]&, lo: float2, hi: float2, k: KeyColor, swing: f32, fade: f32) {
    let half = (hi - lo) * float2 { 0.5, 0.5 };
    let c = (lo + hi) * float2 { 0.5, 0.5 };
    let alpha = 1.0 - fade;
    let shut = alpha * (1.0 - swing);
    glow(out, c + float2 { 6.0, 10.0 }, half + float2 { 10.0, 8.0 }, 0.5, float4 { 0.0, 0.0, 0.0, 0.45 * shut });
    // Where it stands on the table: a dark line, and the light from behind
    // it spilling out under it.
    let foot = float2 { c.x, hi.y };
    glow(out, foot + float2 { 0.0, 2.0 }, float2 { half.x * 1.05, 7.0 }, 0.8, float4 { 0.0, 0.0, 0.0, 0.5 * shut });
    glow(out, foot + float2 { 0.0, 4.0 }, float2 { half.x * 0.8, 9.0 }, 1.0, float4 { 1.0, 0.75, 0.4, 0.3 * shut });
    var d = inst(Shape.Door, c, half, float4 { 0.42, 0.27, 0.15, alpha });
    d.p0 = float4 { swing, key_index(k), 0.0, 0.0 };
    d.p1 = key_tint(k);
    d.misc.z = half.x * 0.45 + 10.0;
    out.push(d);
}

// Where a door from lo to hi has its keyhole, and how big its lock plate is
// (as the shader draws it: door_frame, door_lock_r).
fn keyhole_at(lo: float2, hi: float2) -> float2, f32 {
    let half = (hi - lo) * float2 { 0.5, 0.5 };
    let t = clamp(min(half.x, half.y) * 0.07, 3.0, 8.0);
    let wl = half.x - t;
    let top = -half.y + t * 1.4;
    let tall = half.y - top;
    let r = clamp(min(wl * 0.34, tall * 0.16), 7.0, 24.0);
    return float2 { (lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5 + top + tall * 0.47 + r * 0.32 }, r;
}

// A key the size for a lock plate r big, in its keyhole at `hole`: its bit
// in the hole, its bow up over the plate. `turn` 0..1 turns it half round
// on its shaft, so its bow goes edge on and back.
let KEY_IN_LOCK: f32 = 1.1;

fn key_in_lock_at(hole: float2, r: f32) -> float2 { hole - float2 { 0.0, r * KEY_IN_LOCK * 0.55 } }

fn draw_key_in_lock(out: Inst[>..]&, hole: float2, r: f32, k: KeyColor, turn: f32, glint: f32, alpha: f32) {
    draw_key(out, key_in_lock_at(hole, r), r * KEY_IN_LOCK, k, PI * 0.5, glint, float4_0, alpha);
    out[out.len - 1].misc.w = max(abs(cos(turn * PI)), 0.08);
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
// stand, a catalyst's runes, the light a lantern throws behind it.
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
        Lantern => draw_lantern_light(out, a, lantern_lit(b, look), look.flare, i),
        Brazier => {
            var f = inst(Shape.Brazier, base - float2 { 0.0, hx * 0.75 }, float2 { hx * 1.4, hx * 0.75 }, rgba(1.0, 1.0, 1.0, 1.0));
            f.p0 = float4 { 0.0, look.flare, 0.0, 0.0 };
            f.misc.z = hx * 0.5;
            out.push(f);
            brazier_sparks(out, i, a, look.flare);
        },
        Catalyst => {
            let pulse = (0.5 + 0.5 * sin(now * 2.2 + i)) as f32;
            let c = if b.spent { float4 { 0.45, 0.42, 0.5, 0.4 } } else { float4 { 0.85, 0.6, 1.0, 1.0 } };
            if !b.spent { glow(out, base, float2 { hx * 1.7, hx * 0.6 }, 1.0, float4 { 0.6, 0.3, 0.9, 0.3 + 0.15 * pulse }); }
            rune_circle(out, base + float2 { 0.0, hx * 0.04 }, hx * 1.3, c);
            if !b.spent { catalyst_glints(out, i, a, false); }
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

// Two glints going slowly round a catalyst's circle of runes, each with a
// short trail: those on the far side of it are drawn behind the flask
// (`front` false), those on the near side in front.
fn catalyst_glints(out: Inst[>..]&, i: i64, a: Anchors, front: bool) {
    let hx = a.hx;
    let c = at(a, a.base) + float2 { 0.0, hx * 0.04 };
    let rx = hx * 1.3 * 0.89;
    let ry = rx * 0.3;
    for k in 2 {
        for tail in 4 {
            let ang = now * 0.8 + k * PI + i * 1.3 - tail * 0.09;
            let near = sin(ang) as f32;
            if (near >= 0.0) != front { continue; }
            let p = c + float2 { cos(ang) as f32 * rx, near * ry };
            let f = (1.0 - tail * 0.24) * (0.6 + 0.4 * near * near);
            if tail == 0 {
                glow(out, p, float2 { hx * 0.6, hx * 0.35 }, 1.0, float4 { 0.75, 0.45, 1.0, 0.6 });
                spark(out, p, max(hx * 0.24, 3.5), float4 { 1.0, 0.92, 1.0, 1.0 });
            } else {
                spark(out, p, max(hx * 0.14 * f, 1.8), float4 { 0.85, 0.65, 1.0, 0.8 * f });
            }
        }
    }
    if !front { return; }
    // Motes rising from the runes either side of the flask.
    for k in 3 {
        let side: f32 = if k % 2 == 0 { -1.0 } else { 1.0 };
        let rise = ((now * 0.3 + k * 0.33 + i * 0.17) % 1.0) as f32;
        let x = c.x + side * hx * (1.05 + 0.1 * sin(now * 1.4 + k * 2.0) as f32);
        let y = c.y - hx * (0.1 + rise * 1.8);
        let f = sin(rise * PI) as f32;
        spark(out, float2 { x, y }, max(hx * 0.1, 2.0), float4 { 0.85, 0.6, 1.0, 0.75 * f });
    }
}

// Sparks rising from a brazier's flames either side of its flask, now and
// then, more as it flares.
fn brazier_sparks(out: Inst[>..]&, i: i64, a: Anchors, flare: f32) {
    let hx = a.hx;
    let base = at(a, a.base);
    for k in 5 {
        let side: f32 = if k % 2 == 0 { -1.0 } else { 1.0 };
        let rise = ((now * (0.42 + 0.05 * k) + k * 0.37 + i * 0.21) % 1.0) as f32;
        let x = base.x + side * hx * (1.0 + 0.12 * sin(now * 2.3 + k * 1.9) as f32 + 0.08 * rise);
        let y = base.y - hx * (0.55 + rise * (1.6 + 0.8 * flare));
        let f = (1.0 - rise) * min(rise * 6.0, 1.0);
        let p = float2 { x, y };
        glow(out, p, float2 { hx * 0.22, hx * 0.22 }, 1.0, float4 { 1.0, 0.5, 0.15, 0.35 * f });
        spark(out, p, max(hx * (0.1 + 0.05 * f), 2.2), float4 { 1.0, 0.7 + 0.25 * f, 0.3, (0.85 + 0.15 * flare) * f });
    }
}

// In front: a brazier's bowl, the hearth's coals, the dial, a vine's roots,
// a lantern on its crook.
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
            // On its last pour the dial glows, breathing.
            if look.dial < 0.0 && left == 1.0 {
                let k = (0.5 + 0.5 * sin(now * 3.0 + i)) as f32;
                glow(out, c, float2 { hx * (0.75 + 0.12 * k), hx * (0.75 + 0.12 * k) }, 1.0, float4 { 1.0, 0.7, 0.3, 0.3 + 0.3 * k });
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
        Lantern => draw_lantern(out, a, lantern_lit(b, look), look.flare, i),
        Catalyst => if !b.spent { catalyst_glints(out, i, a, true); },
        None => {},
    }
}

// A lantern hangs beside the flask's neck from a shepherd's crook, in the
// gap to the next column, so neither hides the other: the crook's post
// stands on the ledge in front of the glass's edge, outside the liquid, and
// its arm reaches out over the gap to hold the lantern there. With a flask
// on that side it is as wide as the gap between the two liquids; with none,
// or one set lower down, a little larger. It is drawn over the flasks, but covers no liquid.
fn lantern_unit(a: Anchors) -> f32 { max(a.hx * (if a.open_side { 0.68 } else { 0.52 }), 7.0) }
fn lantern_post_x(a: Anchors) -> f32 { a.hx * 0.9 }
fn lantern_pos(a: Anchors) -> float2 {
    let u = lantern_unit(a);
    at(a, a.lip + float2 { a.hang * (lantern_post_x(a) + u * 0.66), u * 0.85 })
}

fn lantern_lit(b: Bottle, look: StandLook) -> f32 { if look.lit >= 0.0 { look.lit } else if b.lit { 1.0 } else { 0.0 } }

// How a lantern's light breathes, 0..1: a slow swell with a quicker flicker
// on it, each lantern its own.
fn lantern_breath(seed: i64) -> f32 {
    let s = seed * 1.7;
    (0.5 + 0.3 * sin(now * 1.3 + s) + 0.2 * sin(now * 4.7 + s * 2.3)) as f32
}

// Behind the flasks, the warm light it throws round itself, breathing; a
// cold glimmer while it waits to be lit.
fn draw_lantern_light(out: Inst[>..]&, a: Anchors, lit: f32, flare: f32, seed: i64) {
    let hx = a.hx;
    let c = lantern_pos(a);
    if lit > 0.0 {
        let k = lantern_breath(seed);
        glow(out, c, float2 { hx * (2.0 + 0.2 * k), hx * (2.0 + 0.2 * k) }, 1.0,
             float4 { 1.0, 0.72, 0.38, (0.22 + 0.12 * k) * lit + 0.4 * flare });
    } else {
        let wait = (0.5 + 0.5 * sin(now * 1.9 + seed * 1.7)) as f32;
        glow(out, c, float2 { hx * 1.1, hx * 1.1 }, 1.0, float4 { 0.45, 0.6, 1.0, 0.08 + 0.08 * wait });
    }
}

fn draw_lantern(out: Inst[>..]&, a: Anchors, lit: f32, flare: f32, seed: i64) {
    let hx = a.hx;
    let u = lantern_unit(a);
    let c = lantern_pos(a);
    // The crook's post, from just under its bend down to its foot on the
    // ledge: a dark edge, the brass, and its shine.
    let px = at(a, a.lip).x + a.hang * lantern_post_x(a);
    let top = c.y - u * 0.82;
    let foot = at(a, a.base).y + hx * 0.12;
    let mid = float2 { px, (top + foot) * 0.5 };
    let len = (foot - top) * 0.5;
    rect(out, mid, float2 { u * 0.085, len + u * 0.03 }, u * 0.04, float4 { 0.06, 0.04, 0.02, 0.75 });
    rect(out, mid, float2 { u * 0.055, len }, u * 0.03, float4 { 0.62, 0.45, 0.2, 1.0 });
    rect(out, mid - float2 { u * 0.018, 0.0 }, float2 { u * 0.016, len - u * 0.05 }, u * 0.01, float4 { 1.0, 0.86, 0.55, 0.55 });
    rect(out, float2 { px, foot }, float2 { u * 0.2, u * 0.05 }, u * 0.04, float4 { 0.55, 0.4, 0.18, 1.0 });
    // The lantern on its arm, swinging a little.
    var l = inst(Shape.Lantern, c, float2 { u * 1.3, u * 1.2 }, rgba(1.0, 1.0, 1.0, 1.0));
    l.p0 = float4 { lit, flare, seed * 1.7, 0.0 };
    l.p1 = float4 { -a.hang * 0.66, 0.0, 0.0, 0.0 };
    l.misc.z = u * 0.5;
    out.push(l);
    if lit <= 0.0 { return; }
    // Lit, motes of light circle it slowly, brightest as they pass in front.
    for k in 3 {
        let ang = now * (0.55 + 0.12 * k) + k * 2.1 + seed;
        let x = sin(ang) as f32;
        let z = cos(ang) as f32;
        let bob = sin(now * 1.1 + k * 1.9) as f32;
        // Round the lantern and out over the gap, never over the liquid.
        let p = c + float2 { a.hang * u * 0.3 + x * u * (0.85 + 0.12 * k), u * (0.1 + 0.3 * bob - 0.25 * k) + z * u * 0.2 };
        let f = 0.35 + 0.65 * (0.5 + 0.5 * z);
        spark(out, p, max(u * (0.18 + 0.1 * f), 2.5), float4 { 1.0, 0.86, 0.5, 0.9 * f * lit });
    }
}

// A vine's roots on the table in front of its flask's foot, tendrils
// climbing out either side, and its seed pod showing the pours left until
// it spreads. Pollen drifts up from the pod, more as the spread nears.
fn draw_roots(out: Inst[>..]&, b: Bottle, a: Anchors, wither: f32, alpha: f32) {
    let hx = a.hx;
    // In front of the foot, on the table, clear of the liquid.
    let base = at(a, a.base + float2 { 0.0, hx * 0.38 });
    let every: i64 = b.spread_every;
    let left = max(0, every - b.spread_count);
    let ripe: f32 = if left <= 1 { 1.0 } else { clamp(b.spread_count / max(1.0, every - 1.0), 0.0, 0.9) as f32 };
    // A green light about it, breathing, quicker and brighter on its last pour.
    let beat = (0.5 + 0.5 * sin(now * (if left <= 1 { 3.0 } else { 1.6 }) + 0.3)) as f32;
    glow(out, base - float2 { 0.0, hx * 0.15 }, float2 { hx * 1.5, hx * 0.95 }, 1.0,
         float4 { 0.45, 0.9, 0.3, (0.1 + 0.12 * ripe + 0.1 * beat * ripe) * alpha * (1.0 - wither) });
    var r = inst(Shape.Roots, base, float2 { hx * 1.45, hx * 1.45 }, rgba(1.0, 1.0, 1.0, alpha));
    r.p0 = float4 { wither, ripe, 0.3, 0.0 };
    out.push(r);
    if b.fixture != Fixture.VineRoot || alpha < 1.0 { return; }
    text(parts_layer, base.x, base.y + hx * 0.03, str(left), TextStyle.Tiny, float4 { 0.1, 0.16, 0.05, 1.0 }, Align.Center);
    let motes = 2 + (ripe * 3.0) as! i64;
    for k in motes {
        let rise = ((now * 0.22 + k * 0.29 + base.x * 0.011) % 1.0) as f32;
        let x = base.x + hx * (sin(k * 2.4 + now * 0.7) as f32 * 0.7 + (k % 2) * 0.2 - 0.1);
        let y = base.y - hx * (0.25 + rise * 1.6);
        let f = sin(rise * PI) as f32;
        spark(out, float2 { x, y }, max(hx * 0.07, 1.8), float4 { 0.85, 1.0, 0.5, (0.45 + 0.35 * ripe) * f * (1.0 - wither) });
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
