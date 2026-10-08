// The shape pipeline's shaders and the numbers both sides agree on: which
// shape an instance draws (Shape) and which toolbar icon (Icon). The shader
// names the numbers with #defines, since it is compiled with the program and
// cannot be generated; the tests check the two lists stay the same.

import std;

enum Shape {
    Rect,       // rounded rectangle; p0: radius, border, gradient on; p1: second color
    Glow,       // soft ellipse; p0.x: softness 0..1
    FlaskBack,  // the inside of a flask
    Liquid,     // p0: the layers' colors, four to a number at five bits each, bottom first;
                // p1: fill, murk bits, ripple, height; color: slosh slope, seed, ripple center
                // (in half widths), alpha
    Glass,      // glass and rim; p0.x: glow
    Stream,     // a falling stream along a curve; p0: start, control; p1: end, width, phase
    Symbol,     // color-blind symbol; p0.x: which
    Spark,      // four-pointed star
    Ice,        // a shell of rime over a flask; p0: thickness 0..1, shatter 0..1, seed
    Cloth,      // a shroud draped over a flask, embroidered with stars
    Wax,        // a wax seal over the neck; color: the key; p0: softened 0..1, crack 0..1, seed
    Vines,      // a vine wrapped round a flask; p0: grown 0..1, withered 0..1, burnt 0..1, seed
    Tap,        // a siphon's brass tap
    Lantern,    // a hanging lantern; p0: lit 0..1, flare, seed
    Wood,       // a wooden plank
    Backdrop,   // the room behind it all; p0: theme, unscaled half width, the table's far edge (0: none)
    Icon,       // toolbar icons; p0.x: which Icon
    Seal,       // a completed flask's cork with a wax seal
    Ring,       // a circle outline; p0.x: thickness
    Candle,     // wax, wick and a flickering flame; p0.x: seed
    Beam,       // a stream of light along a curve; p0: start, control; p1: end, width, head 0..1
    Glyph,      // a transmutation circle; p0.x: how much is drawn 0..1, p0.y: fading into the stone
    Stone,      // the Philosopher's Stone; p0.x: glow
    Ink,        // the ink swirl between screens; p0.x: cover 0..1, p0.y: turn
    Alembic,    // a round flask simmering; color: liquid; p0.x: fill 0..1
    Steam,      // wisps rising; p0.x: seed
    Label,      // a parchment label; p1: the potion's color
    Pebble,     // a level stone on the map; p0.x: 0 locked, 1 done, 2 current; p0.y: seed
    Vial,       // a little bottle on the back shelf; p0.x: lit 0..1
    Smoke,      // a puff of smoke clearing; p0: gone 0..1, seed
    Ribbon,     // a vow flask's band; p1: its color; p0: vowed, flash, seed
    Frame,      // an hourglass's brass stand
    Dial,       // the hourglass's dial; p0: pours between flips, pours left
    Furnace,    // an athanor's hearth; p0: 0 the bricks behind or 1 the coals in front, flare
    Bloom,      // a moonpetal's petals; p0: open 0..1, 0 behind the flask or 1 the bud on its neck
    Brazier,    // p0: 0 the flames behind the flask or 1 the bowl in front, flare
    Roots,      // a creeping vine's roots and seed pod; p0: withered, ripeness 0..1, seed
    Tube,       // a twin's glass tube along a curve; p0: start, control; p1: end, width, liquid head;
                // color: the liquid passing
    Salamander, // the fire lizard; p0: seed, facing (1 right, -1 left), leap 0..1, glow
    Heat,       // a heat pulse along a curve; p0: start, control; p1: end, width, head
    Shard,      // a flying bit; p0.x: 0 ice, 1 wax, 2 leaf, 3 ember
}

let ALL_SHAPES: const Shape[41] = [
    Shape.Rect, Shape.Glow, Shape.FlaskBack, Shape.Liquid, Shape.Glass, Shape.Stream, Shape.Symbol,
    Shape.Spark, Shape.Ice, Shape.Cloth, Shape.Wax, Shape.Vines, Shape.Tap, Shape.Lantern, Shape.Wood,
    Shape.Backdrop, Shape.Icon, Shape.Seal, Shape.Ring, Shape.Candle, Shape.Beam, Shape.Glyph, Shape.Stone,
    Shape.Ink, Shape.Alembic, Shape.Steam, Shape.Label, Shape.Pebble, Shape.Vial, Shape.Smoke, Shape.Ribbon,
    Shape.Frame, Shape.Dial, Shape.Furnace, Shape.Bloom, Shape.Brazier, Shape.Roots, Shape.Tube,
    Shape.Salamander, Shape.Heat, Shape.Shard,
];

fn shape_index(s: Shape) -> i64 {
    match s {
        Rect => 0, Glow => 1, FlaskBack => 2, Liquid => 3, Glass => 4, Stream => 5, Symbol => 6,
        Spark => 7, Ice => 8, Cloth => 9, Wax => 10, Vines => 11, Tap => 12, Lantern => 13,
        Wood => 14, Backdrop => 15, Icon => 16, Seal => 17, Ring => 18, Candle => 19, Beam => 20,
        Glyph => 21, Stone => 22, Ink => 23, Alembic => 24, Steam => 25, Label => 26, Pebble => 27,
        Vial => 28, Smoke => 29, Ribbon => 30, Frame => 31, Dial => 32, Furnace => 33, Bloom => 34,
        Brazier => 35, Roots => 36, Tube => 37, Salamander => 38, Heat => 39, Shard => 40,
    }
}

// The shader's name for a shape.
fn shape_define(s: Shape) -> const u8[:] {
    match s {
        Rect => "SHAPE_RECT", Glow => "SHAPE_GLOW", FlaskBack => "SHAPE_FLASK_BACK",
        Liquid => "SHAPE_LIQUID", Glass => "SHAPE_GLASS", Stream => "SHAPE_STREAM",
        Symbol => "SHAPE_SYMBOL", Spark => "SHAPE_SPARK", Ice => "SHAPE_ICE", Cloth => "SHAPE_CLOTH",
        Wax => "SHAPE_WAX", Vines => "SHAPE_VINES", Tap => "SHAPE_TAP", Lantern => "SHAPE_LANTERN",
        Wood => "SHAPE_WOOD", Backdrop => "SHAPE_BACKDROP",
        Icon => "SHAPE_ICON", Seal => "SHAPE_SEAL", Ring => "SHAPE_RING", Candle => "SHAPE_CANDLE",
        Beam => "SHAPE_BEAM", Glyph => "SHAPE_GLYPH", Stone => "SHAPE_STONE", Ink => "SHAPE_INK",
        Alembic => "SHAPE_ALEMBIC", Steam => "SHAPE_STEAM", Label => "SHAPE_LABEL",
        Pebble => "SHAPE_PEBBLE", Vial => "SHAPE_VIAL", Smoke => "SHAPE_SMOKE", Ribbon => "SHAPE_RIBBON",
        Frame => "SHAPE_FRAME", Dial => "SHAPE_DIAL", Furnace => "SHAPE_FURNACE", Bloom => "SHAPE_BLOOM",
        Brazier => "SHAPE_BRAZIER", Roots => "SHAPE_ROOTS", Tube => "SHAPE_TUBE",
        Salamander => "SHAPE_SALAMANDER", Heat => "SHAPE_HEAT", Shard => "SHAPE_SHARD",
    }
}

// The pictures Shape.Icon draws.
enum Icon {
    Undo, Restart, Shuffle, Bottle, Hint, Home, Gear, SoundOn, SoundOff, Play, Eye, Seed, Book, Back, Check, Map,
    // What a pour sets off, what ties two flasks, and what can't take a pour.
    Lock, Flame, Flake, Unseal, Flip, Leaf, Wither, Sun, Gold, Overflow, Hop, Rune, Close,
}

let ALL_ICONS: const Icon[29] = [
    Icon.Undo, Icon.Restart, Icon.Shuffle, Icon.Bottle, Icon.Hint, Icon.Home, Icon.Gear, Icon.SoundOn,
    Icon.SoundOff, Icon.Play, Icon.Eye, Icon.Seed, Icon.Book, Icon.Back, Icon.Check, Icon.Map,
    Icon.Lock, Icon.Flame, Icon.Flake, Icon.Unseal, Icon.Flip, Icon.Leaf, Icon.Wither, Icon.Sun, Icon.Gold,
    Icon.Overflow, Icon.Hop, Icon.Rune, Icon.Close,
];

fn icon_index(i: Icon) -> i64 {
    match i {
        Undo => 0, Restart => 1, Shuffle => 2, Bottle => 3, Hint => 4, Home => 5, Gear => 6, SoundOn => 7,
        SoundOff => 8, Play => 9, Eye => 10, Seed => 11, Book => 12, Back => 13, Check => 14, Map => 15,
        Lock => 16, Flame => 17, Flake => 18, Unseal => 19, Flip => 20, Leaf => 21, Wither => 22, Sun => 23,
        Gold => 24, Overflow => 25, Hop => 26, Rune => 27, Close => 28,
    }
}

// The shader's name for an icon.
fn icon_define(i: Icon) -> const u8[:] {
    match i {
        Undo => "ICON_UNDO", Restart => "ICON_RESTART", Shuffle => "ICON_SHUFFLE", Bottle => "ICON_BOTTLE",
        Hint => "ICON_HINT", Home => "ICON_HOME", Gear => "ICON_GEAR", SoundOn => "ICON_SOUND_ON",
        SoundOff => "ICON_SOUND_OFF", Play => "ICON_PLAY", Eye => "ICON_EYE", Seed => "ICON_SEED",
        Book => "ICON_BOOK", Back => "ICON_BACK", Check => "ICON_CHECK", Map => "ICON_MAP",
        Lock => "ICON_LOCK", Flame => "ICON_FLAME", Flake => "ICON_FLAKE", Unseal => "ICON_UNSEAL",
        Flip => "ICON_FLIP", Leaf => "ICON_LEAF", Wither => "ICON_WITHER", Sun => "ICON_SUN", Gold => "ICON_GOLD",
        Overflow => "ICON_OVERFLOW", Hop => "ICON_HOP", Rune => "ICON_RUNE", Close => "ICON_CLOSE",
    }
}

let VERTEX_SHADER = """
    layout(location = 0) in vec2 a_corner;
    layout(location = 1) in vec2 i_pos;
    layout(location = 2) in vec2 i_half;
    layout(location = 3) in vec4 i_color;
    layout(location = 4) in vec4 i_p0;
    layout(location = 5) in vec4 i_p1;
    layout(location = 6) in vec4 i_misc;
    layout(set = 1, binding = 0) uniform View { vec4 view; };
    layout(location = 0) out vec2 v_local;
    layout(location = 1) out vec2 v_half;
    layout(location = 2) out vec4 v_color;
    layout(location = 3) out vec4 v_p0;
    layout(location = 4) out vec4 v_p1;
    layout(location = 5) out vec4 v_misc;
    void main() {
        vec2 local = a_corner * (i_half + vec2(i_misc.z));
        float c = cos(i_misc.y);
        float s = sin(i_misc.y);
        // misc.w squashes it upright (0 means not at all), as a flask turning over.
        float sy = i_misc.w == 0.0 ? 1.0 : i_misc.w;
        vec2 world = i_pos + vec2(c * local.x - s * local.y * sy, s * local.x + c * local.y * sy);
        gl_Position = vec4(world.x / view.x * 2.0 - 1.0, 1.0 - world.y / view.y * 2.0, 0.0, 1.0);
        v_local = local;
        v_half = i_half;
        v_color = i_color;
        v_p0 = i_p0;
        v_p1 = i_p1;
        v_misc = i_misc;
    }
    """;

let FRAGMENT_SHADER = """
    // Shape and icon numbers: kept equal to shape_index and icon_index
    // by the tests.
    #define SHAPE_RECT 0
    #define SHAPE_GLOW 1
    #define SHAPE_FLASK_BACK 2
    #define SHAPE_LIQUID 3
    #define SHAPE_GLASS 4
    #define SHAPE_STREAM 5
    #define SHAPE_SYMBOL 6
    #define SHAPE_SPARK 7
    #define SHAPE_ICE 8
    #define SHAPE_CLOTH 9
    #define SHAPE_WAX 10
    #define SHAPE_VINES 11
    #define SHAPE_TAP 12
    #define SHAPE_LANTERN 13
    #define SHAPE_WOOD 14
    #define SHAPE_BACKDROP 15
    #define SHAPE_ICON 16
    #define SHAPE_SEAL 17
    #define SHAPE_RING 18
    #define SHAPE_CANDLE 19
    #define SHAPE_BEAM 20
    #define SHAPE_GLYPH 21
    #define SHAPE_STONE 22
    #define SHAPE_INK 23
    #define SHAPE_ALEMBIC 24
    #define SHAPE_STEAM 25
    #define SHAPE_LABEL 26
    #define SHAPE_PEBBLE 27
    #define SHAPE_VIAL 28
    #define SHAPE_SMOKE 29
    #define SHAPE_RIBBON 30
    #define SHAPE_FRAME 31
    #define SHAPE_DIAL 32
    #define SHAPE_FURNACE 33
    #define SHAPE_BLOOM 34
    #define SHAPE_BRAZIER 35
    #define SHAPE_ROOTS 36
    #define SHAPE_TUBE 37
    #define SHAPE_SALAMANDER 38
    #define SHAPE_HEAT 39
    #define SHAPE_SHARD 40
    #define ICON_UNDO 0
    #define ICON_RESTART 1
    #define ICON_SHUFFLE 2
    #define ICON_BOTTLE 3
    #define ICON_HINT 4
    #define ICON_HOME 5
    #define ICON_GEAR 6
    #define ICON_SOUND_ON 7
    #define ICON_SOUND_OFF 8
    #define ICON_PLAY 9
    #define ICON_EYE 10
    #define ICON_SEED 11
    #define ICON_BOOK 12
    #define ICON_BACK 13
    #define ICON_CHECK 14
    #define ICON_MAP 15
    #define ICON_LOCK 16
    #define ICON_FLAME 17
    #define ICON_FLAKE 18
    #define ICON_UNSEAL 19
    #define ICON_FLIP 20
    #define ICON_LEAF 21
    #define ICON_WITHER 22
    #define ICON_SUN 23
    #define ICON_GOLD 24
    #define ICON_OVERFLOW 25
    #define ICON_HOP 26
    #define ICON_RUNE 27
    #define ICON_CLOSE 28

    layout(location = 0) in vec2 v_local;
    layout(location = 1) in vec2 v_half;
    layout(location = 2) in vec4 v_color;
    layout(location = 3) in vec4 v_p0;
    layout(location = 4) in vec4 v_p1;
    layout(location = 5) in vec4 v_misc;
    layout(location = 0) out vec4 result;
    // light: the room's candlelight, its color and flicker 0..1.
    layout(set = 3, binding = 0) uniform Look { vec4 palette[20]; vec4 screen; vec4 light; };

    float hash12(vec2 p) {
        vec3 p3 = fract(vec3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }
    float noise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        vec2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
                   mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
    }
    // A box with each corner's own radius: x top-right, y bottom-right,
    // z top-left, w bottom-left (y down).
    float sd_round_box(vec2 p, vec2 b, vec4 r) {
        r.xy = (p.x > 0.0) ? r.xy : r.zw;
        r.x = (p.y > 0.0) ? r.y : r.x;
        vec2 q = abs(p) - b + r.x;
        return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
    }
    float sd_box(vec2 p, vec2 b) {
        vec2 d = abs(p) - b;
        return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    }
    float sd_circle(vec2 p, float r) { return length(p) - r; }
    float sd_segment(vec2 p, vec2 a, vec2 b) {
        vec2 pa = p - a;
        vec2 ba = b - a;
        float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        return length(pa - ba * h);
    }
    float sd_triangle(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
        vec2 e0 = p1 - p0; vec2 e1 = p2 - p1; vec2 e2 = p0 - p2;
        vec2 v0 = p - p0; vec2 v1 = p - p1; vec2 v2 = p - p2;
        vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
        vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
        vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
        float s = sign(e0.x * e2.y - e0.y * e2.x);
        vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                         vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                         vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
        return -sqrt(d.x) * sign(d.y);
    }
    float sd_star5(vec2 p, float r, float rf) {
        const vec2 k1 = vec2(0.809016994375, -0.587785252292);
        const vec2 k2 = vec2(-k1.x, k1.y);
        p.x = abs(p.x);
        p -= 2.0 * max(dot(k1, p), 0.0) * k1;
        p -= 2.0 * max(dot(k2, p), 0.0) * k2;
        p.x = abs(p.x);
        p.y -= r;
        vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
        float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
        return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
    }
    float sd_hexagon(vec2 p, float r) {
        const vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
        p = abs(p);
        p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
        p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
        return length(p) * sign(p.y);
    }
    float sd_heart(vec2 p) {
        p.x = abs(p.x);
        if (p.y + p.x > 1.0) return sqrt(dot(p - vec2(0.25, 0.75), p - vec2(0.25, 0.75))) - sqrt(2.0) / 4.0;
        return sqrt(min(dot(p - vec2(0.0, 1.0), p - vec2(0.0, 1.0)),
                        dot(p - 0.5 * max(p.x + p.y, 0.0), p - 0.5 * max(p.x + p.y, 0.0)))) *
               sign(p.x - p.y);
    }
    float sd_arc(vec2 p, float r, float a0, float a1, float th) {
        // A ring segment between angles a0 and a1 (radians, y down).
        float a = atan(p.y, p.x);
        float mid = 0.5 * (a0 + a1);
        float half_span = 0.5 * (a1 - a0);
        float da = abs(mod(a - mid + 3.14159265, 6.2831853) - 3.14159265);
        if (da <= half_span) return abs(length(p) - r) - th;
        vec2 e0 = r * vec2(cos(a0), sin(a0));
        vec2 e1 = r * vec2(cos(a1), sin(a1));
        return min(length(p - e0), length(p - e1)) - th;
    }
    float fill_aa(float d) { return clamp(0.5 - d, 0.0, 1.0); }
    mat2 rot(float a) { float c = cos(a); float s = sin(a); return mat2(c, s, -s, c); }

    // Distance to the quadratic Bezier curve a-b-c, and the curve's parameter
    // 0..1 at the nearest point (after Inigo Quilez).
    vec2 sd_bezier(vec2 pos, vec2 A, vec2 B, vec2 C) {
        if (abs((B.x - A.x) * (C.y - A.y) - (B.y - A.y) * (C.x - A.x)) < 0.5) B += vec2(0.7, -0.7);
        vec2 a = B - A;
        vec2 b = A - 2.0 * B + C;
        vec2 c = a * 2.0;
        vec2 d = A - pos;
        float kk = 1.0 / dot(b, b);
        float kx = kk * dot(a, b);
        float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
        float kz = kk * dot(d, a);
        float p = ky - kx * kx;
        float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
        float h = q * q + 4.0 * p * p * p;
        float res; float tt;
        if (h >= 0.0) {
            h = sqrt(h);
            vec2 x = (vec2(h, -h) - q) / 2.0;
            vec2 uv = sign(x) * pow(abs(x), vec2(1.0 / 3.0));
            tt = clamp(uv.x + uv.y - kx, 0.0, 1.0);
            vec2 qv = d + (c + b * tt) * tt;
            res = dot(qv, qv);
        } else {
            float z = sqrt(-p);
            float v = acos(clamp(q / (p * z * 2.0), -1.0, 1.0)) / 3.0;
            float m = cos(v);
            float n = sin(v) * 1.732050808;
            vec2 t2 = clamp(vec2(m + m, -n - m) * z - kx, 0.0, 1.0);
            vec2 qx = d + (c + b * t2.x) * t2.x;
            vec2 qy = d + (c + b * t2.y) * t2.y;
            float dx = dot(qx, qx);
            float dy = dot(qy, qy);
            if (dx < dy) { res = dx; tt = t2.x; } else { res = dy; tt = t2.y; }
        }
        return vec2(sqrt(res), tt);
    }

    // One soft dot per grid cell, at a random spot in it; g is in cells.
    float dots(vec2 g, float size) {
        vec2 id = floor(g);
        vec2 o = vec2(hash12(id + 7.1), hash12(id + 3.7)) - 0.5;
        float d = length(fract(g) - 0.5 - o * 0.6);
        return 1.0 - smoothstep(size * 0.3, size, d);
    }
    // The same dots, each lighting up now and then.
    float speckle(vec2 g, float t, float rate, float size) {
        float tw = pow(max(0.0, sin(t * rate + hash12(floor(g)) * 6.2831853)), 8.0);
        return dots(g, size) * tw;
    }

    // A candle flame at p (its base at the origin, y down), r wide: the
    // color in rgb, coverage in a. f is the flicker 0..1.
    vec4 flame(vec2 p, float r, float f, float seed, float t) {
        float sway = (sin(t * 7.0 + seed) * 0.5 + sin(t * 12.7 + seed * 2.3) * 0.25) * (0.5 + f);
        p.x -= sway * r * 0.35 * clamp(-p.y / (r * 2.5), 0.0, 1.0);
        vec2 q = vec2(p.x, p.y < 0.0 ? p.y * 0.42 : p.y * 1.1);
        float d = length(q) - r * (0.85 + 0.25 * f);
        float a = clamp(0.5 - d * 1.2, 0.0, 1.0);
        float core = clamp(1.0 - length(q + vec2(0.0, r * 0.1)) / (r * 0.75), 0.0, 1.0);
        vec3 c = mix(vec3(1.0, 0.45, 0.1), vec3(1.0, 0.85, 0.45), smoothstep(0.0, 0.6, core));
        c = mix(c, vec3(1.0, 0.98, 0.9), smoothstep(0.55, 1.0, core));
        float halo = exp(-length(p + vec2(0.0, r * 0.8)) / (r * 2.2)) * 0.35 * (0.7 + 0.3 * f);
        return vec4(c, clamp(a + halo, 0.0, 1.0));
    }

    // Each color's own small life, never enough to change its hue: q is the
    // position in half widths of the flask.
    vec3 personality(vec3 c, int ci, vec2 q, float t) {
        if (ci == 1) {              // ruby: a slow, deep glow
            c *= 1.0 + 0.07 * sin(t * 1.2 + q.y * 1.5);
        } else if (ci == 2) {       // amber: honey, turning slowly
            c *= 0.95 + 0.1 * noise(q * vec2(2.0, 4.0) + vec2(t * 0.15, t * 0.1));
        } else if (ci == 3) {       // sun: sparkles
            c += vec3(0.6, 0.55, 0.35) * speckle(q * 3.0 + vec2(0.0, t * 0.1), t, 2.3, 0.22);
        } else if (ci == 4) {       // lime: a faint glow
            c += c * 0.1 * (0.6 + 0.4 * sin(t * 1.7 + q.y * 2.5));
        } else if (ci == 5) {       // emerald: fine bubbles rising
            c += vec3(0.09) * dots(q * vec2(3.0, 2.5) + vec2(0.0, t * 0.45), 0.13);
        } else if (ci == 6) {       // sky: a shimmer
            c += vec3(0.06) * sin(q.y * 9.0 + sin(q.x * 3.0 + t * 1.3) * 1.6 - t * 1.8);
        } else if (ci == 7) {       // sapphire: faint stars deep inside
            c += vec3(0.25, 0.3, 0.45) * speckle(q * 3.0, t, 1.1, 0.13);
        } else if (ci == 8) {       // violet: a swirling mist
            c *= 0.92 + 0.16 * noise(q * 2.5 + vec2(t * 0.22, -t * 0.12));
        } else if (ci == 9) {       // rose: a pearly sheen passing over
            c += vec3(0.08) * smoothstep(0.85, 1.0, sin(q.x * 1.3 + q.y * 0.8 - t * 0.6));
        } else if (ci == 10) {      // umber: faint smoke curling up
            c *= 1.0 - 0.2 * smoothstep(0.45, 0.8, noise(q * vec2(3.0, 1.6) + vec2(0.0, t * 0.3)));
        } else if (ci == 11) {      // pearl: iridescence
            float a = q.x * 2.0 + q.y * 1.4 + t * 0.4;
            c += 0.05 * vec3(sin(a), sin(a + 2.1), sin(a + 4.2));
        } else if (ci == 12) {      // slate: a metal glint
            c += vec3(0.12) * pow(max(0.0, sin(q.x * 1.5 - q.y * 0.7 + t * 0.5)), 12.0);
        } else if (ci == 13) {      // teal: caustics
            float n = noise(q * 3.0 + vec2(t * 0.3, t * 0.2)) + noise(q * 3.0 - vec2(t * 0.25, -t * 0.3));
            c += vec3(0.09) * (1.0 - smoothstep(0.0, 0.12, abs(n - 1.0)));
        } else if (ci == 14) {      // olive: specks drifting
            c *= 1.0 - 0.3 * dots(q * 4.5 + vec2(t * 0.05, t * 0.12), 0.12);
        } else if (ci == 15) {      // quicksilver: a mirror, the room sliding over it
            float r = q.x * 1.8 + 0.3 * sin(q.y * 2.0 + t * 0.9) + 0.2 * sin(t * 0.5 + q.y);
            float band = 0.5 + 0.5 * sin(r * 2.6 - t * 0.7);
            c = mix(vec3(0.28, 0.31, 0.38), vec3(0.97, 0.98, 1.0), smoothstep(0.25, 0.8, band));
            c += vec3(0.5) * pow(max(0.0, sin(r * 5.0 + t * 1.3)), 24.0);
            c = mix(c, c * light.rgb * 1.2, 0.25);
        } else if (ci == 16) {      // gold: a metal sheen
            float s = sin(q.x * 2.2 - q.y * 0.6 + t * 0.45);
            c = mix(c, vec3(1.0, 0.8, 0.32), 0.25) * (0.92 + 0.16 * s);
            c += vec3(1.0, 0.9, 0.55) * pow(max(0.0, s), 10.0) * 0.45;
            c += vec3(1.0, 0.95, 0.7) * speckle(q * 4.0, t, 1.7, 0.12) * 0.6;
        } else if (ci == 17) {      // the Drop: pearly, its colors turning
            float a = q.x * 1.5 - q.y * 1.1 + t * 0.6;
            c = mix(c, 0.5 + 0.5 * vec3(sin(a), sin(a + 2.1), sin(a + 4.2)), 0.25) * 1.05;
        }
        return c;
    }

    // --- the rooms: one per chapter, at canvas position cv (540 x 960) -----
    float bricks(vec2 cv, vec2 size, float line) {
        vec2 b = vec2(cv.x / size.x + step(0.5, fract(cv.y / size.y * 0.5)) * 0.5, cv.y / size.y);
        vec2 f = abs(fract(b) - 0.5) * size;
        return smoothstep(size.x * 0.5 - line, size.x * 0.5, f.x) + smoothstep(size.y * 0.5 - line, size.y * 0.5, f.y);
    }
    vec3 room_apothecary(vec2 cv, float t) {
        vec3 c = mix(vec3(0.12, 0.07, 0.10), vec3(0.24, 0.14, 0.12), smoothstep(0.0, 900.0, cv.y));
        c *= 1.0 - 0.2 * clamp(bricks(cv, vec2(90.0, 64.0), 2.5), 0.0, 1.0);
        // Far shelves with jars on them, dim behind the work.
        for (int s = 0; s < 2; s++) {
            float sy = s == 0 ? 236.0 : 470.0;
            float jx = floor(cv.x / 46.0);
            float hj = hash12(vec2(jx, float(s)));
            float jh = 22.0 + hj * 34.0;
            vec2 jp = vec2(mod(cv.x, 46.0) - 23.0, cv.y - (sy - jh * 0.5));
            float body = sd_round_box(jp, vec2(11.0 + hj * 6.0, jh * 0.5), vec4(5.0));
            float neck = sd_box(jp + vec2(0.0, jh * 0.5 + 4.0), vec2(5.0, 5.0));
            float jar = min(body, neck);
            vec3 tint = mix(vec3(0.35, 0.22, 0.16), vec3(0.25, 0.3, 0.2), hash12(vec2(jx, 9.0 + float(s))));
            if (hj > 0.18) c = mix(c, tint * 0.9, fill_aa(jar) * 0.55);
            c = mix(c, vec3(0.30, 0.18, 0.10), fill_aa(abs(cv.y - sy - 4.0) - 4.0));
        }
        // Wooden paneling below.
        float panel = smoothstep(640.0, 642.0, cv.y);
        float grain = noise(vec2(cv.x * 0.08, cv.y * 0.006)) * 0.5 + noise(vec2(cv.x * 0.3, cv.y * 0.02)) * 0.25;
        vec3 wood = vec3(0.22, 0.12, 0.07) * (0.8 + grain);
        wood *= 1.0 - 0.35 * smoothstep(27.0, 30.0, abs(mod(cv.x, 60.0) - 30.0));
        c = mix(c, wood, panel);
        c = mix(c, vec3(0.36, 0.22, 0.12), fill_aa(abs(cv.y - 640.0) - 5.0));
        return c;
    }
    vec3 room_frost(vec2 cv, float t) {
        vec3 c = mix(vec3(0.07, 0.10, 0.17), vec3(0.14, 0.19, 0.27), smoothstep(0.0, 900.0, cv.y));
        float m = clamp(bricks(cv, vec2(120.0, 80.0), 3.0), 0.0, 1.0);
        c *= 1.0 - 0.28 * m;
        c *= 0.88 + 0.2 * noise(cv * 0.025);
        // Frost creeping down from above, icicles hanging from the vault.
        c = mix(c, vec3(0.55, 0.7, 0.85), (1.0 - smoothstep(0.0, 70.0, cv.y)) * 0.35 * noise(cv * 0.06));
        float col = floor(cv.x / 22.0);
        float len = 18.0 + hash12(vec2(col, 3.0)) * 70.0;
        float ix = abs(mod(cv.x, 22.0) - 11.0);
        float icicle = ix - 8.0 * (1.0 - cv.y / len);
        if (hash12(vec2(col, 5.0)) > 0.3) c = mix(c, vec3(0.75, 0.88, 0.98), fill_aa(icicle) * 0.6 * (1.0 - cv.y / len * 0.5));
        // Embers glowing low in a brazier.
        c += vec3(0.5, 0.18, 0.04) * exp(-pow(length((cv - vec2(270.0, 1010.0)) * vec2(0.6, 1.0)) / 260.0, 2.0)) * 0.7;
        return c;
    }
    vec3 room_glassworks(vec2 cv, float t) {
        vec3 c = mix(vec3(0.11, 0.06, 0.06), vec3(0.22, 0.10, 0.08), smoothstep(0.0, 900.0, cv.y));
        float m = clamp(bricks(cv, vec2(48.0, 22.0), 1.6), 0.0, 1.0);
        c *= (1.0 - 0.3 * m) * (0.85 + 0.25 * hash12(floor(vec2(cv.x / 48.0 + step(0.5, fract(cv.y / 44.0)) * 0.5, cv.y / 22.0))));
        // The furnace mouth at the bottom, glowing.
        vec2 fm = cv - vec2(270.0, 1060.0);
        float arch = sd_round_box(fm, vec2(190.0, 150.0), vec4(170.0, 0.0, 170.0, 0.0));
        float flick = 0.85 + 0.15 * light.a;
        vec3 fire = mix(vec3(0.85, 0.42, 0.12), vec3(0.42, 0.11, 0.04), smoothstep(-150.0, 0.0, fm.y));
        c = mix(c, fire * flick, fill_aa(arch) * 0.55);
        c = mix(c, vec3(0.30, 0.16, 0.10), fill_aa(abs(arch + 6.0) - 6.0) * 0.8);
        c += vec3(0.5, 0.2, 0.05) * exp(-max(arch, 0.0) / 90.0) * 0.3 * flick;
        // Glass tubes: one along the wall, one down its side.
        float tube = min(abs(cv.y - 200.0), abs(cv.x - 20.0) + step(cv.y, 200.0) * 1e4) - 9.0;
        float elbow = abs(length(cv - vec2(48.0, 228.0)) - 28.0) - 9.0;
        if (cv.x < 48.0 && cv.y < 228.0) tube = elbow;
        float rim = fill_aa(abs(tube + 1.5) - 1.5);
        float inside = fill_aa(tube);
        float flow = 0.5 + 0.5 * sin((cv.x - cv.y) * 0.05 - t * 1.5);
        c = mix(c, vec3(0.9, 0.55, 0.15) * (0.35 + 0.15 * flow), inside * 0.7);
        c = mix(c, vec3(0.7, 0.75, 0.8), rim * 0.35);
        return c;
    }
    vec3 room_observatory(vec2 cv, float t) {
        vec3 wall = mix(vec3(0.08, 0.06, 0.10), vec3(0.17, 0.11, 0.12), smoothstep(0.0, 900.0, cv.y));
        float plank = noise(vec2(cv.x * 0.05, cv.y * 0.004));
        wall *= 0.85 + 0.25 * plank;
        // A tall arched window onto the night sky.
        vec2 wp = cv - vec2(270.0, 330.0);
        float win = sd_round_box(wp, vec2(235.0, 300.0), vec4(235.0, 0.0, 235.0, 0.0));
        vec3 sky = mix(vec3(0.03, 0.04, 0.12), vec3(0.08, 0.10, 0.25), smoothstep(30.0, 630.0, cv.y));
        sky += vec3(0.12, 0.07, 0.18) * smoothstep(0.55, 0.85, noise(cv * 0.008 + vec2(3.0, 1.0))) * 0.6;
        float stars = speckle(cv / 26.0, t, 0.8, 0.09) * 0.8 + dots(cv / 17.0 + 3.3, 0.06) * 0.35;
        sky += vec3(0.85, 0.88, 1.0) * stars;
        vec2 mp = cv - vec2(400.0, 150.0);
        float moon = max(length(mp) - 34.0, -(length(mp - vec2(-14.0, -8.0)) - 30.0));
        sky = mix(sky, vec3(0.95, 0.92, 0.8), fill_aa(moon));
        sky += vec3(0.2, 0.2, 0.3) * exp(-length(mp) / 70.0) * 0.5;
        vec3 c = mix(wall, sky, fill_aa(win));
        // Brass: the window frame, its bars, and an armillary ring.
        float frame = abs(win) - 4.0;
        float bars = max(min(abs(wp.x) - 2.0, abs(wp.y - 40.0) - 2.0), win);
        float brass = min(frame, bars);
        c = mix(c, vec3(0.72, 0.55, 0.28) * (0.8 + 0.2 * sin(cv.y * 0.05)), fill_aa(brass));
        float ring = abs(length((cv - vec2(270.0, 760.0)) * vec2(1.0, 2.6)) - 300.0) - 2.0;
        c = mix(c, vec3(0.55, 0.42, 0.22), fill_aa(ring) * 0.5);
        return c;
    }
    vec3 room_greenhouse(vec2 cv, float t) {
        vec3 c = mix(vec3(0.04, 0.09, 0.12), vec3(0.08, 0.17, 0.17), smoothstep(0.0, 900.0, cv.y));
        c += vec3(0.25, 0.32, 0.38) * exp(-length(cv - vec2(110.0, 90.0)) / 220.0) * 0.6;
        // Panes of glass in an iron frame.
        vec2 g = abs(mod(cv + vec2(0.0, 30.0), vec2(90.0, 130.0)) - vec2(45.0, 65.0));
        float mull = min(45.0 - g.x, 65.0 - g.y);
        c += vec3(0.04, 0.06, 0.06) * smoothstep(0.0, 40.0, mull) * (cv.y < 700.0 ? 1.0 : 0.0);
        c = mix(c, vec3(0.05, 0.07, 0.07), fill_aa(mull - 2.5) * 0.8);
        // Leaves crowding in from the sides.
        float side = min(cv.x, 540.0 - cv.x);
        float leaf = noise(cv * 0.035 + vec2(0.0, sin(t * 0.3) * 0.2)) * 0.7 + noise(cv * 0.09) * 0.3;
        float foliage = smoothstep(0.52, 0.56, leaf + 0.45 - side / 160.0);
        c = mix(c, vec3(0.06, 0.20, 0.10) * (0.6 + 0.6 * noise(cv * 0.2)), foliage * 0.9);
        // Mist drifting low.
        float mist = noise(vec2(cv.x * 0.006 + t * 0.03, cv.y * 0.012)) * smoothstep(560.0, 960.0, cv.y);
        c += vec3(0.25, 0.32, 0.32) * mist * 0.5;
        return c;
    }
    vec3 room_athanor(vec2 cv, float t) {
        vec3 c = mix(vec3(0.09, 0.03, 0.04), vec3(0.20, 0.06, 0.05), smoothstep(0.0, 900.0, cv.y));
        float m = clamp(bricks(cv, vec2(100.0, 70.0), 2.5), 0.0, 1.0);
        c *= (1.0 - 0.3 * m) * (0.85 + 0.25 * noise(cv * 0.03));
        // A great circle of runes, turning slowly behind the work.
        vec2 rp = cv - vec2(270.0, 450.0);
        float r = length(rp);
        float a = atan(rp.y, rp.x) + t * 0.02;
        float rings = min(abs(r - 238.0) - 1.5, abs(r - 206.0) - 1.0);
        float seg = fract(a / 6.2831853 * 36.0);
        float runes = max(abs(r - 222.0) - 7.0, abs(seg - 0.5) * 30.0 - (hash12(vec2(floor(a / 6.2831853 * 36.0), 1.0)) > 0.5 ? 2.0 : 6.0));
        float glyph = min(rings, runes);
        float pulse = 0.75 + 0.25 * sin(t * 0.8);
        c += vec3(0.85, 0.55, 0.2) * fill_aa(glyph) * 0.22 * pulse;
        c += vec3(0.8, 0.3, 0.1) * exp(-abs(r - 222.0) / 30.0) * 0.06;
        // The furnace's red glow from below.
        c += vec3(0.65, 0.12, 0.03) * exp(-pow(length((cv - vec2(270.0, 1020.0)) * vec2(0.55, 1.0)) / 280.0, 2.0)) * (0.8 + 0.2 * light.a);
        return c;
    }
    vec3 room(int theme, vec2 cv, float t) {
        if (theme == 1) return room_frost(cv, t);
        if (theme == 2) return room_glassworks(cv, t);
        if (theme == 3) return room_observatory(cv, t);
        if (theme == 4) return room_greenhouse(cv, t);
        if (theme == 5) return room_athanor(cv, t);
        return room_apothecary(cv, t);
    }

    // --- the tables: in a level the flasks stand on one, seen from above at a
    // slant, its far edge at canvas height `edge` with the room beyond -----
    // Planks running away from the eye: q is the table's own coordinates.
    vec3 planks(vec2 q, vec3 wood, float width, float seed) {
        float k = floor(q.x / width);
        float u = q.x / width - k;
        float grain = noise(vec2(q.x * 0.09, q.y * 0.012 + k * 7.0 + seed)) * 0.55 +
                      noise(vec2(q.x * 0.4, q.y * 0.03 + k * 3.0)) * 0.3;
        vec3 c = wood * (0.72 + 0.5 * grain) * (0.9 + 0.2 * hash12(vec2(k, seed)));
        c *= 1.0 - 0.45 * (1.0 - smoothstep(0.0, 0.025, u)) - 0.25 * smoothstep(0.975, 1.0, u);
        // A joint now and then along a plank.
        float j = fract(q.y / 260.0 + hash12(vec2(k, 3.0 + seed)));
        c *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.006, abs(j - 0.5)));
        return c;
    }
    vec3 table_top(int theme, vec2 q, float t) {
        if (theme == 1) {           // frost cellar: frosted stone slabs
            vec2 g = q / vec2(118.0, 92.0);
            vec2 f = abs(fract(g + vec2(step(0.5, fract(g.y * 0.5)) * 0.5, 0.0)) - 0.5);
            float seam = 1.0 - smoothstep(0.47, 0.49, max(f.x, f.y));
            vec3 c = vec3(0.30, 0.36, 0.44) * (0.8 + 0.35 * noise(q * 0.02) + 0.15 * noise(q * 0.11));
            c *= 0.55 + 0.45 * seam;
            float frost = smoothstep(0.45, 0.8, noise(q * 0.012 + 4.0) * 0.7 + noise(q * 0.06) * 0.3);
            c = mix(c, vec3(0.78, 0.88, 0.96), frost * 0.45);
            c += vec3(0.9, 0.95, 1.0) * speckle(q / 9.0, t, 1.2, 0.1) * 0.5 * frost;
            return c;
        }
        if (theme == 2) {           // glassworks: a scorched workbench
            vec3 c = planks(q, vec3(0.30, 0.17, 0.09), 84.0, 2.0);
            float scorch = smoothstep(0.5, 0.85, noise(q * 0.008 + 1.3) * 0.65 + noise(q * 0.035) * 0.35);
            c = mix(c, vec3(0.06, 0.035, 0.03), scorch * 0.8);
            // Rings left by hot crucibles, and a few embers in the char.
            vec2 rc = vec2(mod(q.x + 40.0, 230.0) - 115.0, mod(q.y + 70.0, 300.0) - 150.0);
            c *= 1.0 - 0.4 * fill_aa(abs(length(rc) - 46.0) - 3.0) * step(0.5, hash12(floor((q + vec2(40.0, 70.0)) / vec2(230.0, 300.0))));
            c += vec3(1.0, 0.4, 0.1) * speckle(q / 14.0, t, 0.7, 0.08) * scorch * 0.8;
            return c;
        }
        if (theme == 3) {           // observatory: dark wood, brass inlay, a star chart
            vec3 c = planks(q, vec3(0.20, 0.11, 0.08), 120.0, 5.0) * 0.9;
            vec2 m = q - vec2(0.0, 420.0);
            float r = length(m * vec2(1.0, 1.05));
            float chart = 1.0 - smoothstep(236.0, 240.0, r);
            c = mix(c, vec3(0.08, 0.09, 0.17) * (0.85 + 0.3 * noise(q * 0.02)), chart * 0.85);
            float stars = dots(q / 22.0 + 1.7, 0.08) * chart;
            c += vec3(0.85, 0.8, 0.6) * stars * 0.7;
            float a = atan(m.y, m.x);
            float lines = (abs(r - 236.0) < 4.0 ? 1.0 : 0.0) + fill_aa(abs(r - 160.0) - 0.8) * 0.6 +
                          fill_aa(abs(mod(a, 0.5236) - 0.2618) * r - 0.8) * step(r, 236.0) * step(40.0, r) * 0.35;
            vec3 brass = vec3(0.78, 0.6, 0.3);
            c = mix(c, brass, clamp(lines, 0.0, 1.0) * 0.8);
            // The inlaid border.
            float border = min(abs(abs(q.x) - 300.0), abs(q.y - 30.0));
            c = mix(c, brass * 0.9, fill_aa(border - 2.5) * 0.9);
            return c;
        }
        if (theme == 4) {           // greenhouse: a mossy potting bench
            float k = q.x / 64.0;
            float gap = smoothstep(0.0, 0.06, fract(k)) * (1.0 - smoothstep(0.94, 1.0, fract(k)));
            vec3 c = planks(q, vec3(0.30, 0.22, 0.13), 64.0, 8.0);
            c = mix(vec3(0.04, 0.05, 0.03), c, gap);
            float moss = smoothstep(0.5, 0.75, noise(q * 0.01 + 7.0) * 0.6 + noise(q * 0.05) * 0.4);
            c = mix(c, vec3(0.18, 0.32, 0.12) * (0.7 + 0.6 * noise(q * 0.3)), moss * 0.85 * gap);
            c = mix(c, vec3(0.13, 0.09, 0.06), dots(q / 7.0, 0.18) * 0.5 * (1.0 - moss));
            return c;
        }
        if (theme == 5) {           // athanor: dark stone, runes inlaid
            vec3 c = vec3(0.17, 0.10, 0.10) * (0.75 + 0.35 * noise(q * 0.015) + 0.2 * noise(q * 0.09));
            float crack = 1.0 - smoothstep(0.0, 0.03, abs(noise(q * 0.01 + 3.0) - 0.5));
            c *= 1.0 - 0.35 * crack;
            vec2 m = q - vec2(0.0, 430.0);
            float r = length(m);
            float a = atan(m.y, m.x) + t * 0.015;
            float ring = min(abs(r - 250.0) - 2.0, abs(r - 214.0) - 1.5);
            float cell = fract(a / 6.2831853 * 28.0);
            float rune = max(abs(r - 232.0) - 9.0, abs(cell - 0.5) * 34.0 - (hash12(vec2(floor(a / 6.2831853 * 28.0), 2.0)) > 0.5 ? 2.0 : 5.0));
            float glow = fill_aa(min(ring, rune));
            float pulse = 0.7 + 0.3 * sin(t * 0.8);
            c = mix(c, vec3(1.0, 0.55, 0.2) * pulse, glow * 0.55);
            c += vec3(0.6, 0.2, 0.05) * exp(-abs(r - 232.0) / 26.0) * 0.12 * pulse;
            return c;
        }
        return planks(q, vec3(0.42, 0.25, 0.13), 96.0, 0.0);   // apothecary: warm wood
    }
    // The table in perspective below `edge`, and its near edge's lip; the
    // room beyond, seen from farther off.
    vec3 table(int theme, vec2 cv, float edge, float t) {
        if (cv.y < edge) {
            vec2 far = vec2(270.0 + (cv.x - 270.0) * 1.35, 40.0 + cv.y * 1.9);
            vec3 c = room(theme, far, t) * 0.85;
            // The table's shadow on the wall just above it.
            c *= 1.0 - 0.45 * smoothstep(edge - 24.0, edge, cv.y);
            return c;
        }
        float k = clamp((cv.y - edge) / (960.0 - edge), 0.0, 1.0);
        float f = mix(0.58, 1.0, k);
        vec2 q = vec2((cv.x - 270.0) / f, (cv.y - edge) / sqrt(f));
        vec3 c = table_top(theme, q, t);
        // Light falls off toward the far edge and the sides.
        c *= mix(0.7, 1.0, smoothstep(0.0, 0.35, k)) * (1.0 - 0.3 * pow(abs(cv.x - 270.0) / 300.0, 2.0));
        // The far edge: a bright lip, then the board's thickness in shadow.
        float lip = cv.y - edge;
        c = mix(c, c * 1.5 + vec3(0.05), 1.0 - smoothstep(0.0, 2.5, lip));
        c *= 1.0 - 0.3 * (1.0 - smoothstep(2.0, 14.0, lip)) * step(2.0, lip);
        return c;
    }

    // A bottle with a round body, a neck and a lip (the extra-flask icon),
    // at half size h.
    float sd_bottle(vec2 p, vec2 h) {
        float bw = h.x;
        float neck_w = h.x * 0.52;
        float lip_w = h.x * 0.66;
        float lip_h = h.x * 0.22;
        float body_top = -h.y + h.x * 0.95;
        float body_h = (h.y - body_top) * 0.5;
        vec2 bc = vec2(0.0, body_top + body_h);
        float body = sd_round_box(p - bc, vec2(bw, body_h), vec4(bw * 0.45, bw * 0.92, bw * 0.45, bw * 0.92));
        float neck = sd_box(p - vec2(0.0, (-h.y + body_top) * 0.5 + lip_h * 0.5),
                            vec2(neck_w, (body_top + h.y) * 0.5));
        float lip = sd_round_box(p - vec2(0.0, -h.y + lip_h * 0.5), vec2(lip_w, lip_h * 0.5),
                                 vec4(lip_h * 0.45));
        float k = bw * 0.35;
        float hsm = clamp(0.5 + 0.5 * (neck - body) / k, 0.0, 1.0);
        float d = mix(neck, body, hsm) - k * hsm * (1.0 - hsm);
        return min(d, lip);
    }

    // The flasks are glass cylinders on the table, seen from above at a
    // slant: the rim and the bottom are ellipses FLASK_E of their half width
    // deep, and the body is a little narrower than the lip. FLASK_EXTRA is
    // the glass beyond its segments, in half widths (parts.goose's
    // SHADER_EXTRA; board.goose's FLASK_EXTRA leaves room for the rim too).
    const float FLASK_E = 0.36;
    const float FLASK_EXTRA = 1.25;
    const float FLASK_BODY = 0.92;
    // An ellipse of radii r, near enough a distance (after Inigo Quilez).
    float sd_ellipse(vec2 p, vec2 r) {
        float k0 = length(p / r);
        float k1 = length(p / (r * r));
        return k0 * (k0 - 1.0) / max(k1, 1e-5);
    }
    // An upright cylinder, from the ellipse round yt down to the one round yb.
    float sd_cylinder(vec2 p, vec2 r, float yt, float yb) {
        return sd_ellipse(vec2(p.x, p.y - clamp(p.y, yt, yb)), r);
    }
    float flask_top(vec2 h) { return -h.y + h.x * FLASK_E; }                   // the rim's middle
    float flask_bottom(vec2 h) { return h.y - h.x * FLASK_E * FLASK_BODY; }    // the bottom's
    float sd_flask(vec2 p, vec2 h) {
        float ry = h.x * FLASK_E;
        float body = sd_cylinder(p, vec2(h.x, ry) * FLASK_BODY, flask_top(h), flask_bottom(h));
        float lip = sd_cylinder(p, vec2(h.x, ry), flask_top(h), flask_top(h) + h.x * 0.1);
        return min(body, lip);
    }
    // The liquid inside: its column's half width, and the middle of its bottom.
    float liquid_w(vec2 h) { return h.x * (FLASK_BODY - 0.08); }
    float liquid_base(vec2 h) { return flask_bottom(h) - h.x * 0.05; }

    vec4 symbol(vec2 p, float which, float r) {
        float d = 1e5;
        int s = int(which + 0.5);
        if (s == 1) d = sd_circle(p, r * 0.8);
        else if (s == 2) d = sd_box(p, vec2(r * 0.7));
        else if (s == 3) d = sd_triangle(p, vec2(0.0, -r * 0.9), vec2(r * 0.9, r * 0.7), vec2(-r * 0.9, r
        * 0.7));
        else if (s == 4) d = sd_box(mat2(0.7071, -0.7071, 0.7071, 0.7071) * p, vec2(r * 0.62));
        else if (s == 5) d = sd_star5(p, r * 0.95, 0.45);
        else if (s == 6) d = min(sd_box(p, vec2(r * 0.85, r * 0.28)), sd_box(p, vec2(r * 0.28, r * 0.85)));
        else if (s == 7) d = abs(sd_circle(p, r * 0.65)) - r * 0.22;
        else if (s == 8) d = sd_hexagon(p, r * 0.75);
        else if (s == 9) d = sd_heart(vec2(p.x, -p.y + r * 0.5) / (r * 1.25)) * r * 1.25;
        else if (s == 10) d = min(sd_box(mat2(0.7071, -0.7071, 0.7071, 0.7071) * p, vec2(r * 0.9, r * 0.25)),
                                  sd_box(mat2(0.7071, 0.7071, -0.7071, 0.7071) * p, vec2(r * 0.9, r * 0.25)));
        else if (s == 11) d = max(sd_circle(p, r * 0.85), -sd_circle(p - vec2(r * 0.45, -r * 0.2), r * 0.7));
        else if (s == 12) d = min(sd_box(p - vec2(0.0, -r * 0.4), vec2(r * 0.85, r * 0.2)),
                                  sd_box(p + vec2(0.0, -r * 0.4), vec2(r * 0.85, r * 0.2)));
        else if (s == 13) d = sd_triangle(p, vec2(0.0, r * 0.9), vec2(-r * 0.9, -r * 0.7), vec2(r * 0.9,
        -r * 0.7));
        // Quicksilver, gold and the Drop: the alchemists' marks for mercury
        // (a ring over a cross) and the sun (a ring with a dot), and a star.
        else if (s == 15) d = min(abs(sd_circle(p - vec2(0.0, -r * 0.25), r * 0.42)) - r * 0.14,
                                  min(sd_box(p - vec2(0.0, r * 0.55), vec2(r * 0.12, r * 0.4)),
                                      sd_box(p - vec2(0.0, r * 0.62), vec2(r * 0.4, r * 0.12))));
        else if (s == 16) d = min(abs(sd_circle(p, r * 0.75)) - r * 0.16, sd_circle(p, r * 0.22));
        else if (s == 17) d = min(sd_box(p, vec2(r * 0.9, r * 0.16)),
                                  min(sd_box(mat2(0.5, -0.866, 0.866, 0.5) * p, vec2(r * 0.9, r * 0.16)),
                                      sd_box(mat2(0.5, 0.866, -0.866, 0.5) * p, vec2(r * 0.9, r * 0.16))));
        else d = min(sd_circle(p - vec2(-r * 0.45, 0.0), r * 0.36), sd_circle(p - vec2(r * 0.45, 0.0), r *
        0.36));
        float a = fill_aa(d);
        float outline = fill_aa(d - 1.6) - a;
        return vec4(mix(vec3(0.05), vec3(1.0), a / max(a + outline, 0.001)), max(a, outline));
    }

    float sd_icon(vec2 p, int which, float r) {
        if (which == ICON_UNDO) {           // undo: an arc with an arrowhead
            float arc = sd_arc(p, r * 0.6, -2.4, 1.6, r * 0.11);
            float head = sd_triangle(p, vec2(-r * 0.95, -r * 0.48), vec2(-r * 0.25, -r * 0.62), vec2(-r *
            0.62, r * 0.05));
            return min(arc, head);
        } else if (which == ICON_RESTART) {    // restart: a nearly closed circle arrow
            float arc = sd_arc(p, r * 0.6, -1.2, 4.3, r * 0.11);
            float head = sd_triangle(p, vec2(r * 0.05, -r * 0.92), vec2(r * 0.55, -r * 0.55), vec2(r *
            0.02, -r * 0.2));
            return min(arc, head);
        } else if (which == ICON_SHUFFLE) {    // shuffle: two crossing arrows
            float a = sd_segment(p, vec2(-r * 0.8, r * 0.45), vec2(r * 0.45, -r * 0.45)) - r * 0.1;
            float b = sd_segment(p, vec2(-r * 0.8, -r * 0.45), vec2(r * 0.45, r * 0.45)) - r * 0.1;
            float h1 = sd_triangle(p, vec2(r * 0.85, -r * 0.45), vec2(r * 0.35, -r * 0.8), vec2(r * 0.35,
            -r * 0.1));
            float h2 = sd_triangle(p, vec2(r * 0.85, r * 0.45), vec2(r * 0.35, r * 0.1), vec2(r * 0.35, r
            * 0.8));
            return min(min(a, b), min(h1, h2));
        } else if (which == ICON_BOTTLE) {    // extra bottle: a flask outline and a plus
            float f = abs(sd_bottle(p - vec2(-r * 0.25, 0.1 * r), vec2(r * 0.32, r * 0.8))) - r * 0.08;
            float plus = min(sd_box(p - vec2(r * 0.55, r * 0.35), vec2(r * 0.32, r * 0.09)),
                             sd_box(p - vec2(r * 0.55, r * 0.35), vec2(r * 0.09, r * 0.32)));
            return min(f, plus);
        } else if (which == ICON_HINT) {    // hint: a light bulb
            float bulb = abs(sd_circle(p - vec2(0.0, -r * 0.2), r * 0.5)) - r * 0.09;
            float base = sd_box(p - vec2(0.0, r * 0.55), vec2(r * 0.26, r * 0.08));
            float base2 = sd_box(p - vec2(0.0, r * 0.78), vec2(r * 0.18, r * 0.07));
            return min(bulb, min(base, base2));
        } else if (which == ICON_HOME) {    // home
            float roof = abs(sd_triangle(p, vec2(0.0, -r * 0.85), vec2(r * 0.85, -r * 0.05), vec2(-r *
            0.85, -r * 0.05))) - r * 0.08;
            float wall = abs(sd_box(p - vec2(0.0, r * 0.38), vec2(r * 0.55, r * 0.42))) - r * 0.08;
            return min(roof, wall);
        } else if (which == ICON_GEAR) {    // gear
            float a = atan(p.y, p.x);
            float teeth = r * (0.62 + 0.14 * smoothstep(-0.3, 0.3, cos(a * 8.0)));
            float g = length(p) - teeth;
            return max(g, -sd_circle(p, r * 0.25));
        } else if (which == ICON_SOUND_ON || which == ICON_SOUND_OFF) {  // sound on and off
            float body = sd_box(p - vec2(-r * 0.5, 0.0), vec2(r * 0.18, r * 0.25));
            float cone = sd_triangle(p, vec2(-r * 0.5, 0.0), vec2(r * 0.05, -r * 0.7), vec2(r * 0.05, r *
            0.7));
            float d = min(body, cone);
            if (which == ICON_SOUND_ON) {
                d = min(d, sd_arc(p - vec2(r * 0.05, 0.0), r * 0.4, -0.8, 0.8, r * 0.07));
                d = min(d, sd_arc(p - vec2(r * 0.05, 0.0), r * 0.7, -0.8, 0.8, r * 0.07));
            } else {
                d = min(d, sd_segment(p, vec2(r * 0.35, -r * 0.3), vec2(r * 0.85, r * 0.3)) - r * 0.08);
                d = min(d, sd_segment(p, vec2(r * 0.35, r * 0.3), vec2(r * 0.85, -r * 0.3)) - r * 0.08);
            }
            return d;
        } else if (which == ICON_PLAY) {    // play
            return sd_triangle(p, vec2(-r * 0.45, -r * 0.65), vec2(r * 0.7, 0.0), vec2(-r * 0.45, r *
            0.65)) - r * 0.05;
        } else if (which == ICON_EYE) {   // eye (color-blind symbols)
            float outer = max(sd_circle(p - vec2(0.0, r * 0.75), r * 1.05), sd_circle(p + vec2(0.0, r *
            0.75), r * 1.05));
            float ring = abs(outer) - r * 0.08;
            return min(ring, sd_circle(p, r * 0.24));
        } else if (which == ICON_SEED) {   // seed: a drop
            float d = sd_circle(p - vec2(0.0, r * 0.2), r * 0.5);
            float tip = sd_triangle(p, vec2(0.0, -r * 0.85), vec2(r * 0.47, r * 0.05), vec2(-r * 0.47, r *
            0.05));
            return min(d, tip);
        } else if (which == ICON_BOOK) {   // an open book: two pages from the spine, a few lines on each
            vec2 q = vec2(abs(p.x), p.y);
            float d = sd_segment(q, vec2(0.0, -r * 0.5), vec2(r * 0.88, -r * 0.68));
            d = min(d, sd_segment(q, vec2(r * 0.88, -r * 0.68), vec2(r * 0.88, r * 0.5)));
            d = min(d, sd_segment(q, vec2(r * 0.88, r * 0.5), vec2(0.0, r * 0.7)));
            d = min(d, sd_segment(q, vec2(0.0, -r * 0.5), vec2(0.0, r * 0.7)));
            d -= r * 0.08;
            for (int k = 0; k < 3; k++) {
                float y = (-0.3 + 0.28 * float(k)) * r;
                d = min(d, sd_segment(q, vec2(r * 0.22, y), vec2(r * 0.66, y - r * 0.08)) - r * 0.05);
            }
            return d;
        } else if (which == ICON_LOCK) {   // a padlock: a shackle over a body with a keyhole
            float shackle = min(sd_arc(p - vec2(0.0, -r * 0.18), r * 0.36, -3.1416, 0.0, r * 0.11),
                                sd_box(vec2(abs(p.x) - r * 0.36, p.y + r * 0.08), vec2(r * 0.11, r * 0.12)));
            float body = sd_round_box(p - vec2(0.0, r * 0.36), vec2(r * 0.6, r * 0.42), vec4(r * 0.12));
            float hole = min(sd_circle(p - vec2(0.0, r * 0.28), r * 0.12),
                             sd_box(p - vec2(0.0, r * 0.45), vec2(r * 0.05, r * 0.14)));
            return min(shackle, max(body, -hole));
        } else if (which == ICON_FLAME) {  // a flame, its heart cut out
            vec2 q = vec2(p.x + p.y * 0.12, p.y);
            float outer = min(sd_circle(q - vec2(0.0, r * 0.32), r * 0.52),
                              sd_triangle(q, vec2(r * 0.1, -r * 0.95), vec2(r * 0.5, r * 0.2), vec2(-r * 0.5, r * 0.2)));
            float inner = min(sd_circle(q - vec2(0.0, r * 0.48), r * 0.24),
                              sd_triangle(q, vec2(r * 0.02, -r * 0.15), vec2(r * 0.23, r * 0.45), vec2(-r * 0.23, r * 0.45)));
            return max(outer, -inner);
        } else if (which == ICON_FLAKE) {  // ice melting: a snowflake
            float d = 1e5;
            for (int k = 0; k < 3; k++) {
                float a = float(k) * 1.0472 + 1.5708;
                vec2 u = vec2(cos(a), sin(a));
                d = min(d, sd_segment(p, -u * r * 0.85, u * r * 0.85));
                for (int s = -1; s <= 1; s += 2) {
                    vec2 c = u * r * 0.5 * float(s);
                    vec2 v = vec2(-u.y, u.x);
                    d = min(d, sd_segment(p, c, c + (u * float(s) + v) * r * 0.24));
                    d = min(d, sd_segment(p, c, c + (u * float(s) - v) * r * 0.24));
                }
            }
            return d - r * 0.08;
        } else if (which == ICON_UNSEAL) { // a wax seal cracked in two
            float disc = sd_circle(p, r * 0.68);
            float crack = min(min(sd_segment(p, vec2(-r * 0.1, -r * 0.8), vec2(r * 0.12, -r * 0.2)),
                                  sd_segment(p, vec2(r * 0.12, -r * 0.2), vec2(-r * 0.14, r * 0.2))),
                              sd_segment(p, vec2(-r * 0.14, r * 0.2), vec2(r * 0.08, r * 0.8))) - r * 0.09;
            return max(disc, -crack);
        } else if (which == ICON_FLIP) {   // an hourglass turning over
            vec2 q = vec2(p.x, abs(p.y));
            float glass = abs(sd_triangle(q, vec2(0.0, r * 0.04), vec2(r * 0.5, r * 0.62), vec2(-r * 0.5, r * 0.62))) - r * 0.07;
            float bar = sd_box(q - vec2(0.0, r * 0.74), vec2(r * 0.62, r * 0.08));
            float sand = sd_triangle(p, vec2(0.0, r * 0.12), vec2(r * 0.3, r * 0.5), vec2(-r * 0.3, r * 0.5));
            return min(min(glass, bar), sand);
        } else if (which == ICON_LEAF || which == ICON_WITHER) {   // a leaf, drooping and struck through when it withers
            vec2 q = which == ICON_LEAF ? rot(-0.785) * p : rot(2.4) * p;
            float leaf = max(sd_circle(q - vec2(r * 0.42, 0.0), r * 0.72), sd_circle(q + vec2(r * 0.42, 0.0), r * 0.72));
            float vein = sd_segment(q, vec2(0.0, -r * 0.55), vec2(0.0, r * 0.85)) - r * 0.05;
            if (which == ICON_LEAF) return min(max(leaf, -(vein + r * 0.02)), sd_segment(q, vec2(0.0, r * 0.5), vec2(0.0, r * 0.9)) - r * 0.07);
            float d = min(abs(leaf) - r * 0.07, vein);
            return min(d, sd_segment(p, vec2(-r * 0.75, -r * 0.75), vec2(r * 0.75, r * 0.75)) - r * 0.08);
        } else if (which == ICON_SUN) {    // light: a sun with rays
            float d = sd_circle(p, r * 0.32);
            for (int k = 0; k < 8; k++) {
                float a = float(k) * 0.7854;
                vec2 u = vec2(cos(a), sin(a));
                d = min(d, sd_segment(p, u * r * 0.52, u * r * 0.86) - r * 0.08);
            }
            return d;
        } else if (which == ICON_GOLD) {   // gold: the alchemists' sun, a ring with a dot
            return min(abs(sd_circle(p, r * 0.68)) - r * 0.12, sd_circle(p, r * 0.2));
        } else if (which == ICON_OVERFLOW) {   // a flask's worth running over through a tube
            float cup = abs(sd_box(p - vec2(-r * 0.45, r * 0.3), vec2(r * 0.3, r * 0.42))) - r * 0.07;
            cup = max(cup, -sd_box(p - vec2(-r * 0.45, -r * 0.2), vec2(r * 0.22, r * 0.2)));
            float tube = sd_arc(p - vec2(0.0, -r * 0.1), r * 0.45, -3.1416, -0.2, r * 0.08);
            float head = sd_triangle(p, vec2(r * 0.42, r * 0.5), vec2(r * 0.12, r * 0.02), vec2(r * 0.8, r * 0.02));
            return min(cup, min(tube, head));
        } else if (which == ICON_HOP) {    // the salamander's hop: a leap over, with a landing mark
            float arc = sd_arc(p - vec2(0.0, r * 0.25), r * 0.62, -2.9, -0.45, r * 0.08);
            float head = sd_triangle(p, vec2(r * 0.68, r * 0.45), vec2(r * 0.2, -r * 0.02), vec2(r * 0.92, -r * 0.15));
            float spot = sd_circle(p - vec2(-r * 0.62, r * 0.48), r * 0.16);
            return min(min(arc, head), spot);
        } else if (which == ICON_RUNE) {   // a catalyst: a circle of runes round a triangle
            float ring = abs(sd_circle(p, r * 0.78)) - r * 0.07;
            float tri = abs(sd_triangle(p, vec2(0.0, -r * 0.58), vec2(r * 0.5, r * 0.3), vec2(-r * 0.5, r * 0.3))) - r * 0.07;
            return min(ring, tri);
        } else if (which == ICON_CLOSE) {  // close: a cross
            return min(sd_segment(p, vec2(-r * 0.55), vec2(r * 0.55)),
                       sd_segment(p, vec2(-r * 0.55, r * 0.55), vec2(r * 0.55, -r * 0.55))) - r * 0.11;
        } else if (which == ICON_BACK) {   // back arrow
            float shaft = sd_segment(p, vec2(-r * 0.6, 0.0), vec2(r * 0.7, 0.0)) - r * 0.1;
            float head = sd_triangle(p, vec2(-r * 0.85, 0.0), vec2(-r * 0.2, -r * 0.55), vec2(-r * 0.2, r
            * 0.55));
            return min(shaft, head);
        } else if (which == ICON_MAP) {    // map: folded in three, a path to a mark
            float d = 1e5;
            for (int k = 0; k < 3; k++) {
                float x0 = (float(k) - 1.5) * 0.53 * r;
                float x1 = x0 + 0.53 * r;
                float y0 = (k == 1 ? -0.5 : -0.65) * r;
                float y1 = (k == 1 ? -0.65 : -0.5) * r;
                d = min(d, sd_segment(p, vec2(x0, y0), vec2(x1, y1)));
                d = min(d, sd_segment(p, vec2(x0, y0 + 1.15 * r), vec2(x1, y1 + 1.15 * r)));
                d = min(d, sd_segment(p, vec2(x0, y0), vec2(x0, y0 + 1.15 * r)));
            }
            d = min(d, sd_segment(p, vec2(0.8 * r, -0.65 * r), vec2(0.8 * r, 0.5 * r)));
            d -= r * 0.07;
            // A dotted path across it to a cross.
            for (int k = 0; k < 3; k++) {
                d = min(d, sd_circle(p - vec2((-0.55 + 0.28 * float(k)) * r, (0.25 - 0.17 * float(k)) * r), r * 0.065));
            }
            vec2 x = p - vec2(0.42 * r, -0.2 * r);
            d = min(d, min(sd_segment(x, vec2(-0.13 * r), vec2(0.13 * r)),
                           sd_segment(x, vec2(-0.13 * r, 0.13 * r), vec2(0.13 * r, -0.13 * r))) - r * 0.06);
            return d;
        }
        // check mark
        return min(sd_segment(p, vec2(-r * 0.6, 0.0), vec2(-r * 0.15, r * 0.45)),
                   sd_segment(p, vec2(-r * 0.15, r * 0.45), vec2(r * 0.7, -r * 0.5))) - r * 0.12;
    }

    // The liquid's layer fi: its color, and whether murk hides it. Four
    // layers share each number in p0, five bits each, bottom first.
    float layer_color(float fi) {
        int k = int(fi);
        float v = k < 4 ? v_p0.x : k < 8 ? v_p0.y : k < 12 ? v_p0.z : v_p0.w;
        return float((int(v + 0.5) >> (5 * (k % 4))) & 31);
    }
    bool layer_murky(float fi) { return ((int(v_p1.y + 0.5) >> int(fi)) & 1) != 0; }

    // --- the modifiers' parts ----------------------------------------------------
    float smin(float a, float b, float k) {
        float m = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
        return mix(b, a, m) - k * m * (1.0 - m);
    }
    // Color c at coverage a, laid over what is there.
    vec4 over(vec4 under, vec3 c, float a) {
        float oa = a + under.a * (1.0 - a);
        return vec4((c * a + under.rgb * under.a * (1.0 - a)) / max(oa, 0.0001), oa);
    }
    // A pointed leaf or petal, L long and W wide, from the origin up (y down).
    float sd_petal(vec2 q, float L, float W) {
        float R = (0.25 * L * L + W * W) / (2.0 * W);
        float off = R - W;
        vec2 c = q + vec2(0.0, 0.5 * L);
        return max(length(c - vec2(off, 0.0)), length(c + vec2(off, 0.0))) - R;
    }
    // Polished metal lit from the upper left: d is the distance to the part's
    // edge, g its gradient, r how far in the bevel goes.
    vec3 metal(vec3 base, float d, vec2 g, float r) {
        float inside = clamp(-d / r, 0.0, 1.0);
        vec3 n = normalize(vec3(g * (1.0 - inside), 0.4 + inside));
        vec3 L = normalize(vec3(-0.5, -0.7, 0.6));
        float diff = max(dot(n, L), 0.0);
        float spec = pow(max(dot(reflect(-L, n), vec3(0.0, 0.0, 1.0)), 0.0), 14.0);
        return base * (0.3 + 0.9 * diff) + vec3(1.0, 0.95, 0.8) * spec * 0.55;
    }
    const vec3 BRASS = vec3(0.78, 0.58, 0.26);
    const vec3 IRON = vec3(0.30, 0.28, 0.30);
    // A row of glowing coals along y = 0, about r big: color and coverage.
    vec4 coals(vec2 q, float r, float seed, float heat, float t) {
        float best = 1e5;
        float id = 0.0;
        vec2 cc = vec2(0.0);
        float k0 = floor(q.x / (r * 1.5) + 0.5);
        for (int j = -1; j <= 1; j++) {
            float k = k0 + float(j);
            vec2 c = vec2(k * r * 1.5, (hash12(vec2(k, seed)) - 0.5) * r * 0.5);
            float d = length(q - c) - r * (0.75 + 0.35 * hash12(vec2(seed, k)));
            if (d < best) { best = d; id = k; cc = c; }
        }
        float n = noise((q - cc) / r * 1.8 + vec2(id * 3.1, t * 0.7));
        float hot = clamp(smoothstep(0.3, 0.8, n) * heat * (0.75 + 0.25 * light.a), 0.0, 1.0);
        float rim = smoothstep(-r * 0.5, 0.0, best);
        vec3 ember = mix(vec3(0.85, 0.22, 0.04), vec3(1.0, 0.72, 0.28), hot);
        vec3 c = mix(vec3(0.14, 0.06, 0.05), ember, clamp(hot * (1.0 - 0.5 * rim) + 0.2 * heat, 0.0, 1.0));
        return vec4(c, fill_aa(best));
    }
    // A siphon's tap, u the flask's half width: a pipe out of the glass, an
    // elbow down to the spout, and a handle on top.
    float sd_tap(vec2 q, float u) {
        float pipe = sd_segment(q, vec2(-0.55 * u, -0.05 * u), vec2(0.12 * u, -0.05 * u)) - 0.085 * u;
        float elbow = sd_segment(q, vec2(0.12 * u, -0.05 * u), vec2(0.24 * u, 0.22 * u)) - 0.07 * u;
        float spout = sd_round_box(q - vec2(0.25 * u, 0.27 * u), vec2(0.1 * u, 0.04 * u), vec4(0.03 * u));
        float collar = sd_round_box(q - vec2(-0.42 * u, -0.05 * u), vec2(0.05 * u, 0.14 * u), vec4(0.03 * u));
        float stem = sd_segment(q, vec2(-0.08 * u, -0.05 * u), vec2(-0.08 * u, -0.26 * u)) - 0.03 * u;
        float handle = sd_round_box(q - vec2(-0.08 * u, -0.28 * u), vec2(0.17 * u, 0.035 * u), vec4(0.03 * u));
        float knobs = min(sd_circle(q - vec2(-0.25 * u, -0.28 * u), 0.05 * u),
                          sd_circle(q - vec2(0.09 * u, -0.28 * u), 0.05 * u));
        return min(min(min(pipe, elbow), min(spout, collar)), min(min(stem, handle), knobs));
    }
    // An hourglass's stand: posts either side with the pivots at the middle,
    // on a bar along the table; hy is the flask's half height.
    float sd_frame(vec2 q, float u, float hy) {
        vec2 a = vec2(abs(q.x), q.y);
        float top = -0.35 * u;
        float bottom = hy - 0.08 * u;
        float post = sd_round_box(a - vec2(1.2 * u, 0.5 * (top + bottom)), vec2(0.085 * u, 0.5 * (bottom - top)),
                                  vec4(0.04 * u));
        float finial = sd_circle(a - vec2(1.2 * u, -0.43 * u), 0.09 * u);
        float hub = sd_circle(a - vec2(1.2 * u, 0.0), 0.16 * u);
        float axle = sd_segment(a, vec2(0.9 * u, 0.0), vec2(1.2 * u, 0.0)) - 0.06 * u;
        float bar = sd_round_box(q - vec2(0.0, hy - 0.07 * u), vec2(1.3 * u, 0.055 * u), vec4(0.04 * u));
        float foot = sd_round_box(a - vec2(1.2 * u, hy - 0.03 * u), vec2(0.17 * u, 0.045 * u), vec4(0.03 * u));
        return min(min(min(post, finial), min(hub, axle)), min(bar, foot));
    }
    // A lantern's brass: a ring to hang it by, a roof, the frame round its
    // panes and a base.
    float sd_lantern(vec2 q, float u) {
        vec2 a = vec2(abs(q.x), q.y);
        float ring = abs(length(q - vec2(0.0, -0.74 * u)) - 0.09 * u) - 0.028 * u;
        float slope = mix(0.1 * u, 0.46 * u, clamp((q.y + 0.64 * u) / (0.24 * u), 0.0, 1.0));
        float roof = max(a.x - slope, abs(q.y + 0.52 * u) - 0.12 * u);
        float bars = sd_box(a - vec2(0.36 * u, 0.02 * u), vec2(0.045 * u, 0.42 * u));
        float mid = sd_box(q - vec2(0.0, 0.02 * u), vec2(0.018 * u, 0.42 * u));
        float band = sd_box(q - vec2(0.0, -0.39 * u), vec2(0.4 * u, 0.035 * u));
        float base = sd_round_box(q - vec2(0.0, 0.48 * u), vec2(0.44 * u, 0.07 * u), vec4(0.03 * u));
        float foot = sd_round_box(q - vec2(0.0, 0.6 * u), vec2(0.2 * u, 0.05 * u), vec4(0.03 * u));
        return min(min(min(ring, roof), min(bars, mid)), min(min(band, base), foot));
    }

    void main() {
        int kind = int(v_misc.x + 0.5);
        vec2 p = v_local;
        vec2 h = v_half;
        float t = screen.z;
        vec4 col = vec4(0.0);

        if (kind == SHAPE_RECT) {                        // rounded rectangle
            float d = sd_round_box(p, h, vec4(v_p0.x));
            vec4 c = v_color;
            if (v_p0.z > 0.5) c = mix(v_color, v_p1, clamp(p.y / (2.0 * h.y) + 0.5, 0.0, 1.0));
            if (v_p0.y > 0.0) {
                float a = fill_aa(abs(d + v_p0.y * 0.5) - v_p0.y * 0.5);
                col = vec4(c.rgb, c.a * a);
            } else {
                col = vec4(c.rgb, c.a * fill_aa(d));
            }
        } else if (kind == SHAPE_GLOW) {                 // soft glow
            float r = length(p / h);
            float soft = max(v_p0.x, 0.01);
            float a = 1.0 - smoothstep(1.0 - soft, 1.0, r);
            col = vec4(v_color.rgb, v_color.a * a);
        } else if (kind == SHAPE_FLASK_BACK) {                 // inside of a flask
            float d = sd_flask(p, h);
            float nx = clamp(p.x / (h.x * FLASK_BODY), -1.0, 1.0);
            vec3 c = v_color.rgb * (0.6 + 0.4 * sqrt(1.0 - nx * nx));
            // In at the open top: the inside of the far wall, darker.
            float open = fill_aa(sd_ellipse(p - vec2(0.0, flask_top(h)), vec2(h.x, h.x * FLASK_E) * 0.86));
            c = mix(c, v_color.rgb * 0.4, open);
            col = vec4(c, min(1.0, v_color.a * (1.0 + 0.4 * open)) * fill_aa(d + 1.0));
        } else if (kind == SHAPE_LIQUID) {                 // liquid
            // p1.w: the cap, plus a sixteenth of how many segments have
            // drained out of the bottom (a siphon pouring from its tap).
            float cap = max(floor(v_p1.w), 4.0);
            float drain = fract(v_p1.w) * 16.0;
            float seg = (2.0 * h.y - FLASK_EXTRA * h.x) / cap;
            float w = liquid_w(h);
            float ry = w * FLASK_E;
            float base = liquid_base(h);
            float nx = p.x / w;
            if (abs(nx) < 1.0 && v_p1.x > 0.001) {
                float s = sqrt(1.0 - nx * nx);
                float tilt = clamp(tan(v_misc.y), -2.6, 2.6);
                // How high above the bottom is the point of the column's front
                // seen here; a level stays level when the flask tips.
                float lvl = base - p.y + ry * s - tilt * p.x;
                float fill = v_p1.x * seg;
                // The surface: a slow idle drift, the slosh's tilt, and ripples
                // spreading from where a stream lands.
                float seed = v_color.g;
                float drift = h.x * 0.035 * (0.6 * sin(nx * 1.7 + t * 1.1 + seed * 6.3) +
                                             0.4 * sin(nx * 3.9 - t * 1.6 + seed * 2.1));
                float rx = (p.x - v_color.b * h.x) / h.x;
                float ripple = v_p1.z * h.x * 0.09 * sin(rx * 7.0 - t * 15.0) * exp(-abs(rx) * 1.1);
                float surface = fill + drift + v_color.r * p.x + ripple;
                // Upright, the top is seen from above: the surface's ellipse.
                float top_d = sd_ellipse(vec2(p.x, p.y - (base - surface)), vec2(w, ry));
                bool on_top = tilt == 0.0 && lvl >= surface && top_d < 0.5;
                if (lvl > -0.5 && (lvl < surface || on_top)) {
                    float n = ceil(v_p1.x + drain - 0.001);
                    float fi = on_top ? n - 1.0 : clamp(floor(max(lvl, 0.0) / seg + drain), 0.0, n - 1.0);
                    float ci = layer_color(fi);
                    vec3 c = palette[int(ci + 0.5)].rgb;
                    bool hidden = layer_murky(fi);
                    if (hidden) {
                        // Murk: colorless smoke curling inside, one band however deep.
                        vec2 sq = p / h.x;
                        vec2 wq = vec2(noise(sq * 1.6 + vec2(t * 0.18, 0.0)), noise(sq * 1.6 + vec2(5.2, -t * 0.15)));
                        float n2 = noise(sq * 2.8 + wq * 2.2 + vec2(-t * 0.25, t * 0.1));
                        float wisp = noise(sq * vec2(6.0, 3.0) + wq * 3.0 + vec2(t * 0.3, 0.0));
                        c = mix(vec3(0.15, 0.13, 0.19), vec3(0.36, 0.33, 0.42), smoothstep(0.2, 0.9, n2));
                        c += vec3(0.07) * smoothstep(0.55, 0.85, wisp) * smoothstep(0.3, 0.6, n2);
                    } else {
                        c = personality(c, int(ci + 0.5), p / h.x + vec2(seed * 3.0, 0.0), t);
                        if (int(ci + 0.5) == 17 && !on_top) {
                            // The Drop: a pearl in its own glow.
                            vec2 dq = vec2(p.x, (fi + 0.5 - drain) * seg - lvl) / (seg * 0.55);
                            float dd = length(vec2(dq.x * (1.0 + max(0.0, -dq.y) * 0.9), dq.y - 0.15)) - 0.5;
                            float a0 = dq.x * 2.0 + dq.y * 1.5 + t * 0.8;
                            vec3 iri = 0.5 + 0.5 * vec3(sin(a0), sin(a0 + 2.1), sin(a0 + 4.2));
                            vec3 pearl = mix(vec3(0.97, 0.98, 1.0), iri, 0.25 + 0.4 * smoothstep(-0.3, 0.0, dd));
                            pearl += vec3(1.0) * exp(-length(dq - vec2(-0.15, -0.05)) * 9.0);
                            c += vec3(0.5, 0.85, 0.8) * exp(-max(dd, 0.0) * 4.0) * 0.35;
                            c = mix(c, pearl, fill_aa(dd * seg * 0.55));
                        }
                    }
                    float a = clamp((1.0 - abs(nx)) * w, 0.0, 1.0) * clamp(lvl + 0.5, 0.0, 1.0);
                    if (on_top) {
                        // The surface catches the light: brighter, with a bright edge
                        // and the room's glow across it.
                        c = c * 1.12 + vec3(0.05) + light.rgb * 0.06 * (0.5 - (p.y - (base - surface)) / ry);
                        c += vec3(0.28) * (1.0 - smoothstep(0.0, 2.2, -top_d));
                        a *= fill_aa(top_d);
                    } else {
                        // Round like the glass: darker to the sides, a gleam on the left.
                        c *= 0.66 + 0.34 * s;
                        c += vec3(0.2) * smoothstep(-0.66, -0.52, nx) * (1.0 - smoothstep(-0.44, -0.3, nx));
                        // A darker line where one liquid meets another, curving
                        // round the column (smoke is all one); a run of one color
                        // reads as a single band.
                        float edge = abs(lvl - (fi + 1.0 - drain) * seg);
                        bool next_same = (layer_murky(fi + 1.0) ? hidden : !hidden) && (hidden || layer_color(fi + 1.0) == ci);
                        if (fi + 1.0 < v_p1.x + drain - 0.01 && !next_same) c *= 1.0 - 0.22 * (1.0 - smoothstep(0.0, 1.6, edge));
                        float surf = surface - lvl;
                        c += vec3(0.2) * (1.0 - smoothstep(0.0, 2.0, surf));
                        if (tilt != 0.0) a *= clamp(surf + 0.5, 0.0, 1.0);
                        // Now and then a bubble rises from the bottom.
                        float period = 7.0 + fract(seed * 7.13) * 5.0;
                        float cyc = t / period + seed;
                        float rise = 2.4 / period;
                        if (fract(cyc) < rise && tilt == 0.0 && fill > seg * 0.6) {
                            float k = fract(cyc) / rise;
                            vec2 bc = vec2((hash12(vec2(floor(cyc), seed * 13.0)) - 0.5) * w * 0.9 +
                                           sin(k * 9.0) * h.x * 0.06, base + ry * 0.6 - k * (fill - h.x * 0.1));
                            float bd = length(p - bc) - h.x * (0.05 + 0.03 * k);
                            c = mix(c, c * 0.8 + vec3(0.3), fill_aa(abs(bd) - 0.6) * 0.8);
                            c += vec3(0.08) * fill_aa(bd);
                        }
                    }
                    col = vec4(c, a * v_color.a);
                }
            }
        } else if (kind == SHAPE_GLASS) {                 // glass, rim and highlights
            float d = sd_flask(p, h);
            float yt = flask_top(h);
            float ry = h.x * FLASK_E;
            float body = fill_aa(d);
            // The candlelight warms the glass, and flickers in it.
            vec3 c = mix(v_color.rgb, light.rgb, 0.18 + 0.22 * light.a);
            // Thin glass shows most at its sides, where the eye looks through more of it.
            float nx = clamp(p.x / (h.x * FLASK_BODY), -1.0, 1.0);
            float a = body * (0.05 + 0.3 * pow(abs(nx), 8.0));
            a = max(a, fill_aa(abs(d + 0.8) - 0.8) * (0.42 + 0.15 * light.a));
            // The rim: the lip's thickness between two ellipses, bright on the
            // near side and fainter across the opening's far side.
            vec2 rp = p - vec2(0.0, yt);
            float outer = sd_ellipse(rp, vec2(h.x, ry));
            float inner = sd_ellipse(rp, vec2(h.x, ry) * 0.84);
            float near = smoothstep(-ry * 0.3, ry * 0.3, rp.y);
            a = max(a, fill_aa(max(outer, -inner)) * mix(0.22, 0.5, near));
            a = max(a, fill_aa(abs(inner) - 0.6) * mix(0.3, 0.6, near));
            a = max(a, fill_aa(abs(outer + 0.5) - 0.7) * mix(0.35, 0.75, near) * (0.85 + 0.15 * light.a));
            // A glint on the near lip, up and to the left.
            a += exp(-length((rp - vec2(-h.x * 0.55, ry * 0.62)) / vec2(h.x * 0.16, ry * 0.18))) * 0.5 * near;
            // Highlights down the body: a broad one on the left, a thin one on the right.
            float top_y = yt + ry * 1.2;
            float bot_y = flask_bottom(h) - ry * 0.2;
            float along = smoothstep(top_y, top_y + h.x * 0.6, p.y) * (1.0 - smoothstep(bot_y - h.x * 0.7, bot_y, p.y));
            float streak = smoothstep(-0.74, -0.62, nx) * (1.0 - smoothstep(-0.5, -0.36, nx));
            float streak2 = smoothstep(0.5, 0.58, nx) * (1.0 - smoothstep(0.62, 0.7, nx));
            a += body * along * (streak * (0.3 + 0.16 * light.a) + streak2 * 0.2);
            col = vec4(c, clamp(a, 0.0, 1.0) * v_color.a);
            if (v_p0.x > 0.0) {
                float g = exp(-max(d, 0.0) * 0.28) * (1.0 - body) * v_p0.x;
                col = vec4(mix(col.rgb, v_p1.rgb, g / max(col.a + g, 0.001)), max(col.a, g * 0.8));
            }
        } else if (kind == SHAPE_STREAM) {                 // falling stream, along a curve
            vec2 bz = sd_bezier(p, v_p0.xy, v_p0.zw, v_p1.xy);
            float len = length(v_p1.xy - v_p0.xy) + length(v_p0.zw - v_p0.xy);
            float w = v_p1.z * (1.0 - 0.3 * bz.y) * (0.92 + 0.08 * sin(bz.y * len * 0.12 - t * 24.0 + v_p1.w));
            float d = bz.x - w;
            float a = fill_aa(d);
            float e = clamp(bz.x / max(w, 0.5), 0.0, 1.0);
            vec3 c = v_color.rgb * (1.12 - 0.35 * e * e);
            c += vec3(0.3) * (1.0 - smoothstep(0.0, 0.35, abs(e - 0.45))) * 0.4;
            col = vec4(c, a * v_color.a);
        } else if (kind == SHAPE_SYMBOL) {                 // color-blind symbol
            col = symbol(p, v_p0.x, min(h.x, h.y));
            col.a *= v_color.a;
        } else if (kind == SHAPE_SPARK) {                 // sparkle
            vec2 q = abs(p / h);
            float star = 1.0 - smoothstep(0.0, 0.08, q.x * q.y * 6.0 + max(q.x, q.y) * 0.25 - 0.18);
            float core = exp(-dot(p / h, p / h) * 6.0);
            col = vec4(v_color.rgb, v_color.a * clamp(star + core, 0.0, 1.0));
        } else if (kind == SHAPE_ICE) {                 // a shell of rime over a flask
            float u = h.x / 1.12;
            vec2 hf = vec2(u, h.y - 0.12 * u);
            float thick = v_p0.x;
            float shatter = v_p0.y;
            float seed = v_p0.z;
            float th = u * (0.05 + 0.08 * thick);
            float d = sd_flask(p, hf) - th;
            // Frost: thick at the edges, in ferny patches over the middle.
            float n = noise(p / u * 1.4 + seed) * 0.55 + noise(p / u * 3.6 + seed * 2.0) * 0.3 +
                      noise(p / u * 9.0) * 0.15;
            float edge = 1.0 - smoothstep(0.0, u * (0.25 + 0.3 * thick), -d);
            float frost = clamp(edge + smoothstep(0.5, 0.8, n) * (0.3 + 0.5 * thick), 0.0, 1.0);
            // Cracks: the edges of a cell pattern, finer and more of them as it thins.
            vec2 g = p / (u * (0.45 + 0.35 * thick)) + seed * 7.0;
            vec2 ip = floor(g);
            float m1 = 9.0; float m2 = 9.0;
            for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
                vec2 o = vec2(float(i), float(j));
                vec2 r = o + vec2(hash12(ip + o), hash12(ip + o + 17.0)) - fract(g);
                float dd = dot(r, r);
                if (dd < m1) { m2 = m1; m1 = dd; } else if (dd < m2) { m2 = dd; }
            }
            float cw = 0.03 + 0.05 * (1.0 - thick) + 0.1 * shatter;
            float crack = (1.0 - smoothstep(0.0, cw, sqrt(m2) - sqrt(m1))) * (0.45 + 0.55 * (1.0 - 0.7 * thick));
            vec3 c = mix(vec3(0.58, 0.77, 0.93), vec3(0.94, 0.98, 1.0), frost);
            c = mix(c, vec3(1.0), crack * 0.8);
            c += vec3(1.0) * speckle(p / (u * 0.22), t, 1.3, 0.12) * 0.7;
            float a = 0.14 + 0.5 * frost * (0.45 + 0.55 * thick) + crack * 0.5;
            a = max(a, fill_aa(abs(d + 0.8) - 0.8) * 0.8);     // the shell's bright rim
            c = mix(c, vec3(1.0), shatter * 0.6);
            a *= fill_aa(d) * (1.0 - smoothstep(0.4, 1.0, shatter));
            col = vec4(c, clamp(a, 0.0, 1.0) * v_color.a);
        } else if (kind == SHAPE_CLOTH) {               // a shroud: night blue, stars in gold thread
            float hem = h.y - 6.0 + 5.0 * sin(p.x * 0.18 + 1.3 + 0.3 * sin(t * 0.7)) + 3.0 * sin(p.x * 0.41);
            float top = -h.y;
            float halfw = mix(h.x * 0.55, h.x, smoothstep(top, top + h.y * 0.5, p.y));
            float d = max(abs(p.x) - halfw, max(top - p.y, p.y - hem));
            float folds = 0.5 + 0.5 * sin(p.x * 0.22 + 0.7 * sin(p.y * 0.05));
            vec3 c = v_color.rgb * (0.6 + 0.45 * folds) * (0.9 + 0.1 * noise(p * 0.3));
            vec3 thread = vec3(0.95, 0.80, 0.45);
            float u = h.x;
            // A crescent moon, and stars scattered round it.
            vec2 mc = p - vec2(0.0, -h.y * 0.05);
            float moon = max(sd_circle(mc, u * 0.3), -sd_circle(mc - vec2(u * 0.13, -u * 0.09), u * 0.25));
            vec2 sg = p / (u * 0.46);
            vec2 id = floor(sg);
            vec2 so = (vec2(hash12(id + 3.1), hash12(id + 8.7)) - 0.5) * 0.45;
            float star = sd_star5((fract(sg) - 0.5 - so) * u * 0.46, u * 0.08, 0.42);
            float has = step(0.4, hash12(id + 1.7)) * step(u * 0.45, length(mc));
            float tw = 0.65 + 0.35 * sin(t * 1.7 + hash12(id) * 6.2831853);
            c = mix(c, thread * tw, fill_aa(star) * has);
            c = mix(c, vec3(0.98, 0.9, 0.62), fill_aa(moon));
            // A gold band along the hem with tassels under it, a clasp at the top.
            c = mix(c, thread * 0.85, fill_aa(abs(p.y - hem + 5.0) - 1.2));
            float clasp = sd_circle(p - vec2(0.0, top + h.x * 0.35), h.x * 0.2);
            c = mix(c, thread * (0.8 + 0.3 * smoothstep(h.x * 0.2, -h.x * 0.2, p.y - top - h.x * 0.35 + p.x)), fill_aa(clasp));
            float tx = (fract(p.x / (u * 0.4)) - 0.5) * u * 0.4;
            float tassel = fill_aa(sd_circle(vec2(tx, p.y - hem - 2.0), 2.2)) * step(abs(p.x), halfw - 2.0);
            c = mix(c, thread * 0.8, tassel * (1.0 - fill_aa(d)));
            col = vec4(c, max(fill_aa(d), tassel) * v_color.a);
        } else if (kind == SHAPE_WAX) {                 // a wax seal over the neck
            float u = h.x / 0.85;
            float soft = v_p0.x;
            float crack = v_p0.y;
            float seed = v_p0.z;
            // The wax over the lip, running down the neck in drips, longer once softened.
            float d = sd_round_box(p - vec2(0.0, -0.52 * u), vec2(0.76 * u, 0.2 * u + 0.03 * u * soft), vec4(0.14 * u));
            for (int k = 0; k < 4; k++) {
                float fk = float(k);
                float x = (fk - 1.5) * 0.36 * u + (hash12(vec2(fk, seed)) - 0.5) * 0.12 * u;
                float len = (0.2 + 0.4 * hash12(vec2(seed, fk + 3.0))) * u * (1.0 + 1.4 * soft);
                float w = 0.07 * u * (1.0 + 0.35 * soft);
                float drip = min(sd_segment(p, vec2(x, -0.45 * u), vec2(x, -0.45 * u + len)) - w,
                                 sd_circle(p - vec2(x, -0.45 * u + len), w * 1.3));
                d = smin(d, drip, 0.06 * u);
            }
            // The stamped medallion, sagging as it softens.
            vec2 m = vec2(0.0, 0.08 * u + 0.2 * u * soft);
            vec2 mq = (p - m) / vec2(1.0 + 0.05 * soft, 1.0 + 0.22 * soft);
            float ang = atan(mq.y, mq.x);
            float md = length(mq) - 0.48 * u - 0.025 * u * sin(ang * 9.0 + seed * 6.0);
            d = smin(d, md, 0.08 * u);
            vec3 base = v_color.rgb;
            float bulge = clamp(-d / (0.2 * u), 0.0, 1.0);
            vec3 c = base * (0.55 + 0.45 * bulge) * (0.92 + 0.12 * noise(p / u * 4.0 + seed));
            float lit = clamp(dot(normalize(mq + 0.0001), vec2(-0.6, -0.8)), 0.0, 1.0) *
                        (1.0 - smoothstep(0.0, 0.08 * u, -md));
            c += vec3(0.25) * lit * 0.6;
            // The sigil pressed into it: a ring round a keyhole.
            float groove = abs(length(mq) - 0.33 * u) - 0.025 * u;
            float hole = min(sd_circle(mq - vec2(0.0, -0.06 * u), 0.09 * u),
                             sd_triangle(mq, vec2(0.0, -0.06 * u), vec2(0.09 * u, 0.18 * u), vec2(-0.09 * u, 0.18 * u)));
            float sig = min(groove, hole);
            c = mix(c, base * 0.42, fill_aa(sig) * (1.0 - 0.4 * soft));
            c = mix(c, base * 1.25 + 0.1, fill_aa(abs(sig - 0.025 * u) - 0.012 * u) * 0.35 * step(0.0, mq.x + mq.y));
            float spec = exp(-length(p - m - vec2(-0.17 * u, -0.2 * u)) / (0.05 * u * (1.0 + soft)));
            c += vec3(1.0, 0.95, 0.9) * spec * (0.45 + 0.25 * soft);
            // Cracks running out from the middle when it breaks.
            float reach = crack * 0.6 * u;
            float cr = abs(mq.x - 0.07 * u * sin(mq.y / u * 11.0 + seed * 3.0)) - 0.016 * u;
            float cr2 = abs(mq.y + 0.4 * mq.x - 0.05 * u * sin(mq.x / u * 13.0)) - 0.014 * u;
            c = mix(c, vec3(0.08, 0.03, 0.03), clamp(fill_aa(cr) * step(abs(mq.y), reach) +
                                                    fill_aa(cr2) * step(abs(mq.x), reach * 0.8), 0.0, 1.0));
            col = vec4(c, fill_aa(d) * v_color.a);
        } else if (kind == SHAPE_VINES) {               // a vine wrapped round a flask
            float u = h.x / 1.25;
            float grow = v_p0.x;
            float wither = v_p0.y;
            float burn = v_p0.z;
            float seed = v_p0.w;
            float y01 = (h.y - p.y) / (2.0 * h.y);         // 0 at the foot
            float n = noise(p / u * 2.2 + seed * 5.0);
            vec4 c = vec4(0.0);
            float f = 1.0 / (u * 0.95);
            for (int k = 0; k < 3; k++) {
                float fk = float(k);
                float ph = fk * 2.1 + seed * 6.2831853;
                float amp = u * (1.02 - 0.08 * fk);
                float reach = grow * 1.1 - fk * 0.05;
                // The stem, winding round: dimmer where it passes behind.
                float s = p.y * f + ph;
                float slope = amp * f * cos(s);
                float front = cos(s);
                float sd = abs(p.x - amp * sin(s)) / sqrt(1.0 + slope * slope) - u * (0.05 + 0.015 * front);
                vec3 stem = mix(vec3(0.17, 0.36, 0.13), vec3(0.42, 0.30, 0.14), wither) * (0.75 + 0.35 * max(front, 0.0));
                c = over(c, stem, fill_aa(sd) * step(y01, reach) * (front < 0.0 ? 0.45 : 1.0));
                // Leaves along it, turned out to one side and the other.
                float sp = u * 0.5;
                for (int jj = -1; jj <= 1; jj++) {
                    float j = floor(p.y / sp) + float(jj);
                    float yc = (j + 0.5) * sp;
                    if (abs(yc) > h.y - 0.25 * u) continue;
                    float sc = yc * f + ph;
                    float side = mod(j + fk, 2.0) < 1.0 ? -1.0 : 1.0;
                    vec2 dir = normalize(vec2(side * (1.0 - 0.6 * wither), -0.7 + 0.6 * wither));
                    vec2 lq = p - vec2(amp * sin(sc), yc);
                    lq = vec2(dot(lq, vec2(-dir.y, dir.x)), -dot(lq, dir));
                    float size = u * (0.32 + 0.1 * hash12(vec2(j, fk + seed))) * (1.0 - 0.3 * wither);
                    float leaf = sd_petal(lq, size, size * 0.36);
                    float shown = step((h.y - yc) / (2.0 * h.y), reach - 0.04) * (cos(sc) > -0.3 ? 1.0 : 0.4);
                    vec3 lc = mix(vec3(0.24, 0.56, 0.2), vec3(0.55, 0.38, 0.16), wither) * (lq.x > 0.0 ? 1.0 : 0.78);
                    lc = mix(lc, lc * 0.65, fill_aa(abs(lq.x) - 0.5));
                    c = over(c, lc, fill_aa(leaf) * shown);
                }
            }
            // Crumbling as it withers; burning away from the top down.
            float keep = step(smoothstep(0.5, 1.0, wither) * 1.05, n);
            float v = (1.0 - y01) * 0.7 + n * 0.3;
            float fr = burn * 1.35 - 0.1;
            float on = step(0.001, burn);
            float burnt = step(v, fr - 0.12) * on;
            float rim = (1.0 - smoothstep(0.0, 0.1, abs(v - fr + 0.06))) * on;
            vec3 cc = mix(c.rgb, vec3(0.08, 0.05, 0.03), smoothstep(fr + 0.12, fr - 0.06, v) * on);
            cc = mix(cc, vec3(1.0, 0.55, 0.15), rim);
            col = vec4(cc, c.a * keep * (1.0 - burnt) * v_color.a);
        } else if (kind == SHAPE_TAP) {                 // a brass tap at a siphon's foot
            float u = h.x / 0.6;
            float d = sd_tap(p, u);
            vec2 e = vec2(0.5, 0.0);
            vec2 g = vec2(sd_tap(p + e.xy, u) - sd_tap(p - e.xy, u), sd_tap(p + e.yx, u) - sd_tap(p - e.yx, u));
            col = vec4(metal(BRASS, d, g, 0.08 * u), fill_aa(d) * v_color.a);
        } else if (kind == SHAPE_LANTERN) {             // a hanging lantern, dark until lit
            float u = h.x / 0.55;
            float lit = v_p0.x;
            float flare = v_p0.y;
            float glowk = lit * (0.82 + 0.18 * light.a) + flare;
            float pane = sd_box(p - vec2(0.0, 0.03 * u), vec2(0.34 * u, 0.39 * u));
            float d = sd_lantern(p, u);
            vec2 e = vec2(0.5, 0.0);
            vec2 g = vec2(sd_lantern(p + e.xy, u) - sd_lantern(p - e.xy, u), sd_lantern(p + e.yx, u) - sd_lantern(p - e.yx, u));
            // Its light round it, then the panes, the candle and the frame.
            float edge = clamp(min(h.x + v_misc.z - abs(p.x), h.y + v_misc.z - abs(p.y)) / max(v_misc.z, 1.0), 0.0, 1.0);
            float halo = exp(-max(pane, 0.0) / (0.3 * u)) * (1.0 - fill_aa(pane)) * glowk * 0.55 * edge * edge;
            vec4 c = vec4(vec3(1.0, 0.78, 0.42), clamp(halo, 0.0, 1.0));
            float inner = clamp(1.0 - length((p - vec2(0.0, 0.15 * u)) / u) * 1.1, 0.0, 1.0);
            vec3 glass = mix(vec3(0.07, 0.06, 0.10), vec3(1.0, 0.70, 0.30), clamp(glowk * (0.35 + 0.75 * inner), 0.0, 1.0));
            glass += vec3(0.2) * (1.0 - smoothstep(0.0, 0.035 * u, abs(p.x + 0.2 * u + p.y * 0.25))) * (1.0 - 0.6 * lit);
            c = over(c, glass, fill_aa(pane));
            float wax = sd_round_box(p - vec2(0.0, 0.31 * u), vec2(0.065 * u, 0.1 * u), vec4(0.02 * u));
            c = over(c, vec3(0.92, 0.86, 0.72) * (0.35 + 0.65 * min(glowk, 1.0)), fill_aa(wax));
            if (lit > 0.01) {
                vec4 fl = flame(p - vec2(0.0, 0.2 * u), 0.075 * u * (1.0 + flare * 0.8), light.a, v_p0.z, t);
                c = over(c, fl.rgb, fl.a * min(lit, 1.0) * fill_aa(pane));
            }
            c = over(c, metal(BRASS * 0.9, d, g, 0.05 * u), fill_aa(d));
            col = vec4(c.rgb, c.a * v_color.a);
        } else if (kind == SHAPE_WOOD) {                // wood
            float d = sd_round_box(p, h, vec4(v_p0.x));
            float a = fill_aa(d);
            float grain = noise(vec2(p.x * 0.02, p.y * 0.4)) * 0.6 + noise(vec2(p.x * 0.08, p.y * 1.3)) * 0.4;
            vec3 c = mix(v_color.rgb * 0.75, v_color.rgb * 1.1, grain);
            c *= 1.0 - 0.35 * smoothstep(h.y * 0.2, h.y, p.y);
            c += vec3(0.08) * (1.0 - smoothstep(-h.y, -h.y + 3.0, p.y));
            col = vec4(c, a * v_color.a);
        } else if (kind == SHAPE_BACKDROP) {                // the room
            vec2 cv = p * (v_p0.y / h.x) + vec2(270.0, 480.0);      // canvas units
            vec3 c = v_p0.z > 0.0 ? table(int(v_p0.x + 0.5), cv, v_p0.z, t) : room(int(v_p0.x + 0.5), cv, t);
            // Candlelight from the back shelf and the work below, flickering.
            float f = 0.8 + 0.2 * light.a;
            float glow = exp(-pow(length((cv - vec2(270.0, 880.0)) * vec2(0.9, 1.6)) / 520.0, 2.0) * 2.0);
            c += light.rgb * 0.3 * glow * f;
            c += light.rgb * 0.1 * exp(-length((cv - vec2(270.0, 90.0)) * vec2(0.7, 1.4)) / 160.0) * f;
            float vig = smoothstep(1.2, 0.3, length((cv / vec2(540.0, 960.0) - 0.5) * vec2(1.3, 1.0)));
            c *= mix(0.5, 1.0, vig);
            col = vec4(c, 1.0);
        } else if (kind == SHAPE_ICON) {                // icon
            float r = min(h.x, h.y);
            float d = sd_icon(p, int(v_p0.x + 0.5), r);
            col = vec4(v_color.rgb, v_color.a * fill_aa(d));
        } else if (kind == SHAPE_SEAL) {                // a completed flask's cork, sealed with wax
            // The cork's top, an ellipse seen from above, over its side; the
            // wax a blob on top running down the near side.
            float ry = h.x * FLASK_E;
            float ty = -h.y + ry;
            float top = sd_ellipse(p - vec2(0.0, ty), vec2(h.x, ry));
            float cork = sd_cylinder(p, vec2(h.x, ry), ty, ty + h.x * 0.34);
            vec2 wq = p - vec2(0.0, ty + ry * 0.15);
            float wax = sd_ellipse(wq, vec2(h.x * 0.5, ry * 0.62)) + 0.6 * sin(atan(wq.y, wq.x) * 7.0);
            float drip = sd_segment(p, vec2(h.x * 0.12, ty + ry * 0.5), vec2(h.x * 0.15, ty + ry + h.x * 0.38)) - h.x * 0.07;
            wax = min(wax, drip);
            float grain = noise(p / h.x * vec2(6.0, 9.0)) * 0.25;
            vec3 c = vec3(0.62, 0.45, 0.28) * (0.75 + grain) * (top < 0.0 ? 1.15 : 0.8);
            c = mix(c, c * 0.7, fill_aa(abs(top) - 0.6));
            c = mix(c, v_color.rgb * (0.75 + 0.35 * clamp(-wq.y / ry, 0.0, 1.0)), fill_aa(wax));
            c += vec3(0.3) * fill_aa(sd_ellipse(wq + vec2(h.x * 0.18, ry * 0.2), vec2(h.x * 0.1, ry * 0.12)));
            col = vec4(c, max(fill_aa(cork), fill_aa(wax)) * v_color.a);
        } else if (kind == SHAPE_RING) {                // ring
            float d = abs(length(p) - (h.x - v_p0.x * 0.5)) - v_p0.x * 0.5;
            col = vec4(v_color.rgb, v_color.a * fill_aa(d));
        } else if (kind == SHAPE_CANDLE) {              // candle: the wax below, the flame above
            float w = h.x * 0.42;
            float top = -h.y + h.x * 1.7;
            vec2 wp = p - vec2(0.0, (top + h.y) * 0.5);
            float wax = sd_round_box(wp, vec2(w, (h.y - top) * 0.5), vec4(w * 0.25, 1.0, w * 0.25, 1.0));
            wax = min(wax, sd_circle(p - vec2(w * 0.55, top + h.x * 0.25), w * 0.28));     // a drip
            float sx = p.x / w;
            vec3 wc = vec3(0.93, 0.86, 0.70) * (0.75 + 0.25 * (1.0 - sx * sx));
            wc += vec3(0.25, 0.12, 0.0) * (1.0 - smoothstep(0.0, h.x * 1.2, p.y - top)) * light.a;
            col = vec4(wc, fill_aa(wax));
            float wick = sd_segment(p, vec2(0.0, top), vec2(0.0, top - h.x * 0.25)) - 0.8;
            col = mix(col, vec4(0.15, 0.1, 0.08, 1.0), fill_aa(wick));
            vec4 fl = flame(p - vec2(0.0, top - h.x * 0.3), h.x * 0.24, light.a, v_p0.x, t);
            col = vec4(mix(col.rgb, fl.rgb, fl.a), max(col.a, fl.a));
            col.a *= v_color.a;
        } else if (kind == SHAPE_BEAM) {                // a stream of light, drawn up to its head
            vec2 bz = sd_bezier(p, v_p0.xy, v_p0.zw, v_p1.xy);
            float head = v_p1.w;
            float w = v_p1.z;
            float shown = 1.0 - smoothstep(head - 0.01, head + 0.01, bz.y);
            float trail = 0.3 + 0.7 * smoothstep(head - 0.45, head, bz.y);
            float core = exp(-bz.x * bz.x / (w * w * 0.25));
            float halo = exp(-bz.x / (w * 1.6)) * 0.5;
            vec2 hp = mix(mix(v_p0.xy, v_p0.zw, head), mix(v_p0.zw, v_p1.xy, head), head);
            float spot = exp(-length(p - hp) / (w * 1.2)) * step(head, 0.999);
            float a = (core + halo) * shown * trail + spot;
            vec3 c = mix(v_color.rgb, vec3(1.0), core * 0.6 + spot * 0.5);
            col = vec4(c, clamp(a, 0.0, 1.0) * v_color.a);
        } else if (kind == SHAPE_GLYPH) {               // transmutation circle
            float r = min(h.x, h.y);
            float prog = v_p0.x;
            float ang = fract(atan(p.x, -p.y) / 6.2831853 + 1.0);      // 0 at the top, clockwise
            float drawn = 1.0 - smoothstep(prog * 1.6 - 0.02, prog * 1.6, ang);
            float c1 = min(abs(length(p) - r * 0.95) - 1.6, abs(length(p) - r * 0.83) - 1.0);
            float ticks = max(abs(length(p) - r * 0.89) - r * 0.035,
                              abs(fract(ang * 36.0) - 0.5) * r * 0.17 - 0.9);
            vec2 pr = rot(t * 0.15) * p;
            float tri = abs(sd_triangle(pr, vec2(0.0, -r * 0.83), vec2(r * 0.719, r * 0.415),
                                        vec2(-r * 0.719, r * 0.415))) - 1.2;
            float sq = abs(sd_box(rot(-t * 0.1) * p, vec2(r * 0.29))) - 1.0;
            float c3 = abs(length(p) - r * 0.41) - 1.0;
            float inner = min(tri, min(sq, c3));
            float a = max(fill_aa(min(c1, ticks)) * drawn, fill_aa(inner) * smoothstep(0.45, 0.9, prog));
            float g = exp(-max(min(c1, inner), 0.0) * 0.25) * 0.35 * prog;
            a = max(a, g) * (1.0 - v_p0.y);
            col = vec4(mix(v_color.rgb, vec3(1.0), 0.3 * a), a * v_color.a);
        } else if (kind == SHAPE_STONE) {               // the Philosopher's Stone
            float R = min(h.x, h.y);
            float r = R * 0.34;
            vec2 q = rot(0.5236) * p;
            float d = sd_hexagon(q, r);
            float table = sd_hexagon(q, r * 0.52);
            // Facets: twelve around the table, each lit by its own angle to
            // a light above and to the left.
            float ang = atan(p.y, p.x);
            float sector = floor(ang / 0.5236 + 6.0);
            float mid = (sector - 5.5) * 0.5236;
            float lit = 0.5 + 0.5 * dot(vec2(cos(mid), sin(mid)), normalize(vec2(-0.6, -0.8)));
            vec3 ruby = vec3(0.80, 0.06, 0.14);
            vec3 c = ruby * (0.45 + 0.75 * lit) * (0.9 + 0.2 * hash12(vec2(sector, 3.0)));
            vec3 top = mix(vec3(0.95, 0.25, 0.32), vec3(1.0, 0.55, 0.55), smoothstep(r * 0.5, -r * 0.5, p.y + p.x * 0.5));
            c = mix(c, top, fill_aa(table));
            c = mix(c, vec3(1.0, 0.7, 0.65), fill_aa(abs(table) - 0.5) * 0.5);
            c += vec3(1.0, 0.9, 0.9) * fill_aa(sd_circle(p - vec2(-r * 0.22, -r * 0.3), r * 0.1));
            c *= 0.9 + 0.15 * sin(t * 2.0);
            c = mix(c, vec3(1.0, 0.8, 0.6), fill_aa(abs(d) - 0.8) * 0.7);
            float body = fill_aa(d);
            // A halo and slowly turning rays, gone before the edge.
            float dist = max(d, 0.0);
            float fade = 1.0 - smoothstep(0.55, 1.0, length(p) / R);
            float rays = pow(abs(sin(ang * 6.0 + t * 0.4)), 16.0) * exp(-dist / (r * 1.1));
            float halo = exp(-dist / (r * 0.4));
            float glow_a = (halo * 0.7 + rays * 0.55) * v_p0.x * fade;
            vec3 gc = mix(vec3(1.0, 0.45, 0.3), vec3(1.0, 0.85, 0.6), rays);
            col = vec4(mix(gc, c, body), clamp(body + glow_a, 0.0, 1.0) * v_color.a);
        } else if (kind == SHAPE_INK) {                 // ink swirling over the screen
            float L = length(h);
            vec2 q = p / L;
            float r = length(q);
            float a = atan(q.y, q.x);
            float sw = a + r * 5.0 - v_p0.y;
            vec2 rq = rot(r * 4.0 - v_p0.y) * q;
            float wob = 0.10 * sin(sw * 3.0) + 0.14 * (noise(rq * 5.0 + 3.0) - 0.5);
            float edge = (1.0 - v_p0.x) * 1.6 - 0.3;
            float d = (r - edge - wob) * L;       // positive in the ink
            float ink = clamp(0.5 + d, 0.0, 1.0);
            vec3 c = mix(vec3(0.05, 0.03, 0.10), vec3(0.13, 0.07, 0.21), noise(rq * 8.0) * (0.5 + 0.5 * sin(sw * 4.0)));
            float rim = exp(-abs(d) / 7.0);
            c = mix(c, vec3(0.75, 0.55, 0.95), rim * 0.45);
            col = vec4(c, max(ink, rim * 0.5));
        } else if (kind == SHAPE_ALEMBIC) {             // a round flask, simmering
            float R = h.x * 0.92;
            vec2 bc = vec2(0.0, h.y - R - 2.0);
            float neck_w = h.x * 0.2;
            float sphere = length(p - bc) - R;
            float neck = sd_box(p - vec2(0.0, (-h.y + bc.y) * 0.5), vec2(neck_w, (bc.y + h.y) * 0.5));
            float lip = sd_round_box(p - vec2(0.0, -h.y + 4.0), vec2(neck_w * 1.35, 4.0), vec4(3.0));
            float hsm = clamp(0.5 + 0.5 * (neck - sphere) / (R * 0.25), 0.0, 1.0);
            float glass = min(mix(neck, sphere, hsm) - R * 0.25 * hsm * (1.0 - hsm), lip);
            float inner = sphere + 3.5;
            // The liquid, with a surface that rolls as it simmers.
            float level = bc.y + R - v_p0.x * 2.0 * R;
            float surf = level + sin(p.x * 0.09 + t * 2.3) * 2.0 + sin(p.x * 0.21 - t * 3.1) * 1.2;
            vec4 liquid = vec4(0.0);
            if (p.y > surf && inner < 0.5) {
                vec3 c = v_color.rgb * (0.65 + 0.45 * smoothstep(bc.y + R, bc.y - R, p.y));
                c *= 0.92 + 0.16 * noise(p * 0.04 + vec2(0.0, t * 0.4));
                // Bubbles rising from the bottom.
                for (int k = 0; k < 7; k++) {
                    float fk = float(k);
                    float sp = 0.35 + 0.3 * hash12(vec2(fk, 1.0));
                    float ph = fract(t * sp + hash12(vec2(fk, 2.0)));
                    vec2 bp = vec2((hash12(vec2(fk, 3.0)) - 0.5) * R * 1.2 + sin(ph * 8.0 + fk) * 4.0,
                                   mix(bc.y + R * 0.85, surf, ph));
                    float bd = length(p - bp) - (2.0 + 3.0 * hash12(vec2(fk, 4.0))) * (0.6 + ph * 0.6);
                    c = mix(c, c * 0.7 + vec3(0.35), fill_aa(abs(bd) - 0.8) * 0.85);
                }
                c += vec3(0.3) * (1.0 - smoothstep(0.0, 3.0, p.y - surf));
                liquid = vec4(c, fill_aa(inner) * clamp(p.y - surf + 0.5, 0.0, 1.0));
            }
            float rim = fill_aa(abs(glass + 1.8) - 1.8);
            float body = fill_aa(glass);
            float sx = (p.x - bc.x) / R;
            float streak = smoothstep(-0.75, -0.6, sx) * (1.0 - smoothstep(-0.5, -0.35, sx)) *
                           smoothstep(bc.y - R * 0.5, bc.y - R * 0.2, p.y) * (1.0 - smoothstep(bc.y + R * 0.2, bc.y + R * 0.5, p.y));
            vec3 gcol = mix(vec3(0.86, 0.92, 1.0), light.rgb, 0.3);
            vec4 gl = vec4(gcol, clamp(body * 0.08 + rim * 0.6 + body * streak * 0.4, 0.0, 1.0));
            vec3 back = vec3(0.10, 0.08, 0.16);
            vec4 under = vec4(back, body * 0.55);
            col = vec4(mix(under.rgb, liquid.rgb, liquid.a), max(under.a, liquid.a));
            col = vec4(mix(col.rgb, gl.rgb, gl.a), max(col.a, gl.a));
        } else if (kind == SHAPE_STEAM) {               // wisps of steam
            float y01 = clamp((h.y - p.y) / (2.0 * h.y), 0.0, 1.0);    // 0 at the bottom
            float sway = sin(p.y * 0.03 + t * 0.9 + v_p0.x) * h.x * 0.25 * y01;
            float width = h.x * (0.25 + 0.75 * y01);
            float x = (p.x - sway) / width;
            float n = noise(vec2(p.x * 0.035 + v_p0.x, p.y * 0.025 + t * 0.7)) * 0.6 +
                      noise(vec2(p.x * 0.08 - v_p0.x, p.y * 0.06 + t * 1.1)) * 0.4;
            float a = exp(-x * x * 2.5) * smoothstep(0.35, 0.75, n) * smoothstep(0.0, 0.15, y01) * (1.0 - y01);
            col = vec4(vec3(0.92, 0.9, 0.98), a * 0.45 * v_color.a);
        } else if (kind == SHAPE_LABEL) {               // a parchment label
            float d = sd_round_box(p, h - vec2(0.5, 0.5), vec4(2.5)) + 0.6 * sin(p.x * 0.7 + p.y * 1.3);
            float a = fill_aa(d);
            vec3 c = vec3(0.93, 0.86, 0.68) * (0.88 + 0.14 * noise(p * 0.35));
            c = mix(c, vec3(0.55, 0.4, 0.25), fill_aa(abs(d + 1.8) - 0.6) * 0.7);
            float band = fill_aa(abs(p.y + h.y - 3.0) - 1.3);
            c = mix(c, v_p1.rgb, band);
            col = vec4(c, a * v_color.a);
        } else if (kind == SHAPE_PEBBLE) {              // a level stone on the map
            float r = min(h.x, h.y);
            float ang = atan(p.y, p.x);
            float d = length(p) - r * (0.9 + 0.05 * sin(ang * 3.0 + v_p0.y) + 0.03 * sin(ang * 5.0 - v_p0.y));
            vec2 u = p / r;
            float z = sqrt(max(0.0, 1.0 - dot(u, u)));
            float diff = clamp(dot(normalize(vec3(u, z + 0.3)), normalize(vec3(-0.4, -0.6, 0.7))), 0.0, 1.0);
            vec3 base = v_p0.x < 0.5 ? vec3(0.26, 0.24, 0.30) : v_color.rgb;
            vec3 c = base * (0.45 + 0.7 * diff);
            c *= 0.9 + 0.15 * noise(p * 0.25 + v_p0.y);
            float edge = fill_aa(abs(d + 1.2) - 1.0);
            c = mix(c, v_p0.x < 0.5 ? vec3(0.4, 0.38, 0.45) : vec3(1.0, 0.88, 0.55), edge * 0.6);
            float shadow = exp(-max(length(p - vec2(0.0, r * 0.25)) - r, 0.0) / 4.0) * 0.5;
            float body = fill_aa(d);
            col = vec4(c * body, max(body, shadow));
            col.a *= v_color.a;
        } else if (kind == SHAPE_VIAL) {                // a little bottle on the back shelf
            float lit = v_p0.x;
            float body = sd_round_box(p - vec2(0.0, h.y * 0.3), vec2(h.x, h.y * 0.7), vec4(h.x * 0.6));
            float neck = sd_box(p - vec2(0.0, -h.y * 0.55), vec2(h.x * 0.4, h.y * 0.3));
            float cork = sd_round_box(p - vec2(0.0, -h.y * 0.88), vec2(h.x * 0.48, h.y * 0.12), vec4(1.0));
            float glass = min(body, neck);
            float liquid = max(body + 1.2, (h.y * 0.05) - p.y);
            vec3 lc = v_color.rgb * mix(0.3, 1.25, lit);
            vec3 c = mix(vec3(0.12, 0.1, 0.16), lc, fill_aa(liquid));
            c = mix(c, vec3(0.8, 0.85, 0.95), fill_aa(abs(glass) - 0.6) * 0.5);
            c = mix(c, vec3(0.6, 0.42, 0.26), fill_aa(cork));
            float a = max(fill_aa(glass) * 0.9, fill_aa(cork));
            float halo = exp(-max(body, 0.0) / (h.x * 0.9)) * 0.55 * lit * (0.85 + 0.15 * light.a);
            col = vec4(mix(v_color.rgb, c, a), clamp(a + halo * (1.0 - a), 0.0, 1.0) * v_color.a);
        } else if (kind == SHAPE_SMOKE) {               // a puff of smoke, swirling away
            float k = v_p0.x;
            vec2 q = p / h;
            q.y += k * 0.7;
            q = rot(k * 3.0 * (1.2 - length(q))) * q;
            q /= 1.0 + 0.6 * k;
            float n = noise(q * 2.4 + v_p0.y * 7.0 + vec2(0.0, -t * 0.5)) * 0.6 +
                      noise(q * 5.0 - v_p0.y * 3.0 + vec2(t * 0.4, 0.0)) * 0.4;
            float body = 1.0 - smoothstep(0.55, 1.0, length(q));
            float a = body * smoothstep(k * 0.8, k * 0.8 + 0.3, n) * (1.0 - k);
            col = vec4(mix(vec3(0.16, 0.14, 0.20), vec3(0.5, 0.46, 0.56), n), a * v_color.a);
        } else if (kind == SHAPE_RIBBON) {              // a vow flask's band round its shoulder
            float u = h.x / 1.2;
            float vowed = v_p0.x;
            float flash = v_p0.y;
            vec3 cloth = mix(vec3(0.80, 0.74, 0.60), v_p1.rgb, vowed);
            float W = 0.9 * u;
            float x = clamp(p.x / W, -1.0, 1.0);
            float yc = 0.07 * u * (1.0 - x * x) - 0.1 * u;
            float band = max(abs(p.y - yc) - 0.2 * u, abs(p.x) - W);
            // A knot at the side, and two tails hanging from it.
            vec2 kn = vec2(0.84 * u, -0.1 * u);
            float sway = sin(t * 1.3 + v_p0.z * 6.0) * 0.04 * u;
            vec2 e1 = kn + vec2(0.12 * u + sway, 0.62 * u);
            vec2 e2 = kn + vec2(0.34 * u + sway, 0.5 * u);
            float tails = min(sd_segment(p, kn, e1) - 0.085 * u, sd_segment(p, kn, e2) - 0.08 * u);
            tails = max(tails, -min(sd_circle(p - e1 - vec2(0.0, 0.1 * u), 0.1 * u), sd_circle(p - e2 - vec2(0.03 * u, 0.1 * u), 0.1 * u)));
            float knot = sd_circle(p - kn, 0.12 * u);
            float d = min(band, min(tails, knot));
            // Shaded round the neck, a weave, gold stitching along its edges.
            vec3 c = cloth * (0.62 + 0.38 * sqrt(max(0.0, 1.0 - x * x))) * (0.93 + 0.07 * sin(p.x * 1.1 + p.y * 0.4));
            float stitch = (1.0 - smoothstep(0.0, 1.0, abs(abs(p.y - yc) - 0.14 * u) - 0.4)) *
                           step(band, 0.0) * step(0.5, fract(p.x / (0.09 * u)));
            c = mix(c, vec3(0.98, 0.82, 0.45), stitch * 0.85);
            c = mix(c, cloth * 0.75, fill_aa(tails) * (1.0 - fill_aa(band)));
            c = mix(c, cloth * 1.02, fill_aa(knot));
            // A rune in a diamond at the front: dim until vowed, then glowing.
            vec2 rq = p - vec2(0.0, yc);
            float dia = sd_box(rot(0.7853982) * rq, vec2(0.16 * u));
            float rune = min(sd_segment(rq, vec2(0.0, -0.14 * u), vec2(0.0, 0.14 * u)),
                         min(sd_segment(rq, vec2(0.0, 0.0), vec2(-0.09 * u, -0.1 * u)),
                             sd_segment(rq, vec2(0.0, 0.0), vec2(0.09 * u, -0.1 * u)))) - 0.025 * u;
            c = mix(c, vec3(0.2, 0.14, 0.1), fill_aa(dia));
            c = mix(c, vec3(0.98, 0.82, 0.45), fill_aa(abs(dia) - 0.022 * u));
            c = mix(c, mix(vec3(0.6, 0.5, 0.35), vec3(1.0, 0.92, 0.6), vowed), fill_aa(rune));
            c += vec3(1.0, 0.85, 0.45) * exp(-max(rune, 0.0) / (0.05 * u)) * (vowed * 0.4 + flash) * fill_aa(dia);
            c += vec3(1.0, 0.9, 0.6) * flash * 0.4;
            col = vec4(c, fill_aa(d) * v_color.a);
        } else if (kind == SHAPE_FRAME) {               // an hourglass's brass stand
            float u = h.x / 1.42;
            float hy = h.y - 0.06 * u;
            float d = sd_frame(p, u, hy);
            vec2 e = vec2(0.5, 0.0);
            vec2 g = vec2(sd_frame(p + e.xy, u, hy) - sd_frame(p - e.xy, u, hy),
                          sd_frame(p + e.yx, u, hy) - sd_frame(p - e.yx, u, hy));
            col = vec4(metal(BRASS, d, g, 0.07 * u), fill_aa(d) * v_color.a);
        } else if (kind == SHAPE_DIAL) {                // the hourglass's dial: a pip for each pour to go
            float r = h.x;
            float total = max(floor(v_p0.x + 0.5), 1.0);
            float left = v_p0.y;
            float L = length(p);
            vec3 c = vec3(0.93, 0.87, 0.72) * (0.82 + 0.18 * smoothstep(r, -r, p.y + p.x));
            float ang = mod(atan(p.x, -p.y), 6.2831853);      // 0 at the top, clockwise
            float span = 6.2831853 / total;
            float k = floor(ang / span + 0.5);
            float ak = k * span;
            float pip = length(p - 0.64 * r * vec2(sin(ak), -cos(ak))) - r * 0.13;
            bool on = mod(k, total) < left - 0.5;
            float warn = left < 1.5 ? 0.5 + 0.5 * sin(t * 6.0) : 0.0;
            vec3 pc = on ? mix(vec3(0.92, 0.5, 0.1), vec3(1.0, 0.86, 0.45), warn) : vec3(0.68, 0.6, 0.48);
            c = mix(c, pc, fill_aa(pip) * (on ? 1.0 : 0.6));
            float rim = abs(L - r * 0.9) - r * 0.11;
            c = mix(c, metal(BRASS, rim, normalize(p + 0.001) * sign(L - 0.9 * r), 0.1 * r), fill_aa(rim));
            float glowa = exp(-max(L - r, 0.0) / (0.3 * r)) * warn * 0.6 * (1.0 - fill_aa(L - r));
            col = vec4(mix(vec3(1.0, 0.7, 0.3), c, fill_aa(L - r)), max(fill_aa(L - r), glowa) * v_color.a);
        } else if (kind == SHAPE_FURNACE) {             // an athanor's hearth
            float u = h.x / 1.45;
            float flare = v_p0.y;
            if (v_p0.x < 0.5) {
                // Behind the flask: a brick hearth glowing at its two mouths.
                float d = sd_round_box(p, h - vec2(0.05 * u), vec4(0.7 * u, 0.06 * u, 0.7 * u, 0.06 * u));
                vec2 bp = p / u * vec2(4.0, 6.0);
                bp.x += step(0.5, fract(bp.y * 0.5)) * 0.5;
                vec2 bf = abs(fract(bp) - 0.5);
                float mortar = max(smoothstep(0.42, 0.5, bf.x), smoothstep(0.38, 0.5, bf.y));
                float heat = smoothstep(-h.y, h.y, p.y);
                vec3 brick = mix(vec3(0.34, 0.16, 0.11), vec3(0.6, 0.25, 0.12), heat) * (0.85 + 0.25 * hash12(floor(bp)));
                vec3 c = mix(brick, vec3(0.15, 0.09, 0.07), mortar);
                c += vec3(0.9, 0.35, 0.08) * heat * heat * 0.35 * (0.8 + 0.2 * light.a + flare);
                vec2 mq = vec2(abs(p.x) - 1.05 * u, p.y - (h.y - 0.3 * u));
                float mouth = sd_round_box(mq, vec2(0.2 * u, 0.24 * u), vec4(0.2 * u, 0.0, 0.2 * u, 0.0));
                vec4 fl = flame(mq - vec2(0.0, 0.22 * u), 0.13 * u * (1.0 + flare), light.a, sign(p.x) + 3.0, t);
                c = mix(c, mix(vec3(0.45, 0.1, 0.04), fl.rgb, fl.a), fill_aa(mouth));
                c = mix(c, vec3(0.5, 0.42, 0.38), fill_aa(abs(d + 0.06 * u) - 0.05 * u) * step(p.y, 0.0));
                col = vec4(c, fill_aa(d) * v_color.a);
            } else {
                // In front: a bed of coals at the foot under an iron grate.
                vec4 cl = coals(p, 0.16 * u, 5.0, 0.8 + flare, t);
                vec4 c = vec4(cl.rgb, cl.a * step(abs(p.x), 1.05 * u));
                float grate = sd_round_box(p - vec2(0.0, 0.17 * u), vec2(1.1 * u, 0.045 * u), vec4(0.03 * u));
                c = over(c, metal(IRON, grate, vec2(0.0, sign(p.y - 0.17 * u)), 0.04 * u), fill_aa(grate));
                col = vec4(c.rgb, c.a * v_color.a);
            }
        } else if (kind == SHAPE_BLOOM) {               // a moonpetal's petals
            float open = v_p0.x;
            vec3 dark = vec3(0.42, 0.45, 0.72);
            vec3 pale = vec3(0.82, 0.86, 1.0);
            vec4 c = vec4(0.0);
            if (v_p0.y < 0.5) {
                // Behind the flask: a lotus of five petals cupping it.
                float u = h.x / 1.9;
                vec2 base = vec2(0.0, h.y - 0.1 * u);
                float halo = exp(-length((p - base + vec2(0.0, 1.0 * u)) / vec2(1.4, 1.0)) / (0.8 * u)) * open * 0.45;
                c = vec4(pale, halo);
                for (int j = 0; j < 5; j++) {
                    float fk = j == 0 ? -2.0 : j == 1 ? 2.0 : j == 2 ? -1.0 : j == 3 ? 1.0 : 0.0;
                    vec2 q = rot(-fk * (0.5 + 0.08 * open)) * (p - base);
                    float L = u * (2.3 - 0.3 * abs(fk));
                    float pd = sd_petal(q, L, u * 0.5);
                    float along = clamp(-q.y / L, 0.0, 1.0);
                    vec3 pc = mix(dark, pale, 0.15 + 0.6 * open) * (0.65 + 0.4 * along);
                    pc = mix(pc, pc * 0.75, fill_aa(abs(q.x) - 0.8) * 0.6);
                    pc += pale * open * 0.15 * (0.8 + 0.2 * sin(t * 1.3 + fk));
                    c = over(c, pc, fill_aa(pd) * 0.92);
                }
            } else {
                // On the neck: a bud, opening and glowing once a lantern is lit.
                float u = h.x / 0.9;
                vec2 base = vec2(0.0, h.y - 0.25 * u);
                float halo = exp(-length(p - base + vec2(0.0, 0.35 * u)) / (0.35 * u)) * open * 0.7;
                c = vec4(pale, clamp(halo, 0.0, 1.0));
                for (int j = 0; j < 2; j++) {           // green sepals
                    float s = j == 0 ? -1.0 : 1.0;
                    vec2 q = rot(-s * 1.0) * (p - base - vec2(s * 0.1 * u, 0.0));
                    c = over(c, vec3(0.2, 0.42, 0.22) * (0.7 + 0.4 * clamp(-q.y / (0.3 * u), 0.0, 1.0)),
                             fill_aa(sd_petal(q, 0.32 * u, 0.09 * u)));
                }
                for (int j = 0; j < 5; j++) {
                    float fk = j == 0 ? -2.0 : j == 1 ? 2.0 : j == 2 ? -1.0 : j == 3 ? 1.0 : 0.0;
                    vec2 q = rot(-fk * mix(-0.13, 0.5, open)) * (p - base - vec2(fk * 0.15 * u, 0.0));
                    float L = u * mix(1.0, 0.8, open) * (1.0 - 0.08 * abs(fk));
                    float pd = sd_petal(q, L, u * mix(0.2, 0.24, open));
                    float along = clamp(-q.y / L, 0.0, 1.0);
                    vec3 pc = mix(dark, pale, 0.12 + 0.88 * open) * (0.62 + 0.45 * along);
                    pc = mix(pc, pc * 0.8, fill_aa(abs(q.x) - 0.6) * 0.5);
                    c = over(c, pc, fill_aa(pd));
                }
                // Gold stamens in the open flower.
                vec2 sq = p - base + vec2(0.0, 0.28 * u);
                float st = dots(sq / (0.09 * u) + 3.0, 0.3) * step(length(sq), 0.2 * u);
                c = over(c, vec3(1.0, 0.85, 0.4), st * open);
            }
            col = vec4(c.rgb, c.a * v_color.a);
        } else if (kind == SHAPE_BRAZIER) {             // a brazier under a flask
            float flare = v_p0.y;
            if (v_p0.x < 0.5) {
                // Behind the flask: flames licking up either side of it.
                float u = h.x / 1.4;
                vec4 c = vec4(0.0);
                for (int k = 0; k < 3; k++) {
                    float fk = float(k) - 1.0;
                    vec2 b = vec2(fk * 0.92 * u, h.y - 0.05 * u);
                    float r = u * (0.2 + 0.08 * (1.0 - abs(fk))) * (1.0 + 0.7 * flare);
                    vec4 fl = flame(p - b, r, light.a, fk * 3.0 + 1.0, t);
                    c = over(c, fl.rgb, fl.a);
                }
                col = vec4(c.rgb, c.a * v_color.a);
            } else {
                // In front: an iron bowl of coals on three legs.
                float u = h.x / 1.25;
                vec2 q = p - vec2(0.0, -0.12 * u);
                float bowl = max(length(q * vec2(1.0, 2.4)) - 1.0 * u, -q.y);
                float rim = sd_round_box(q, vec2(1.04 * u, 0.05 * u), vec4(0.04 * u));
                float legs = min(sd_segment(vec2(abs(p.x), p.y), vec2(0.5 * u, 0.2 * u), vec2(0.72 * u, h.y - 0.04 * u)) - 0.045 * u,
                                 sd_segment(p, vec2(0.0, 0.3 * u), vec2(0.0, h.y - 0.04 * u)) - 0.04 * u);
                vec4 c = vec4(0.0);
                c = over(c, IRON * 0.8, fill_aa(legs));
                vec4 cl = coals(q + vec2(0.0, 0.08 * u), 0.15 * u, 2.0, 0.85 + flare, t);
                c = over(c, cl.rgb, cl.a * step(abs(q.x), 0.95 * u));
                float iron = min(bowl, rim);
                vec3 ic = metal(IRON, iron, normalize(q * vec2(1.0, 5.76) + vec2(0.0, 0.001)), 0.12 * u);
                ic += vec3(1.0, 0.4, 0.1) * 0.25 * (0.6 + flare) * smoothstep(0.2 * u, -0.05 * u, q.y);
                c = over(c, ic, fill_aa(iron));
                col = vec4(c.rgb, c.a * v_color.a);
            }
        } else if (kind == SHAPE_ROOTS) {               // a creeping vine's roots and seed pod
            float u = h.x / 1.45;
            float wither = v_p0.x;
            float ripe = v_p0.y;
            float seed = v_p0.z;
            vec2 q = p + (vec2(noise(p / u * 6.0 + seed), noise(p / u * 6.0 + 4.0)) - 0.5) * 0.08 * u;
            vec2 A[5] = vec2[5](vec2(-0.3, -0.12), vec2(0.3, -0.12), vec2(-0.15, -0.05), vec2(0.18, -0.05), vec2(-0.55, -0.25));
            vec2 B[5] = vec2[5](vec2(-0.8, -0.18), vec2(0.85, -0.12), vec2(-0.45, 0.25), vec2(0.45, 0.22), vec2(-1.0, -0.4));
            vec2 C[5] = vec2[5](vec2(-1.35, 0.04), vec2(1.38, 0.07), vec2(-0.65, 0.5), vec2(0.7, 0.48), vec2(-1.3, -0.62));
            float d = 1e5;
            float along = 0.0;
            float dc = 0.0;
            for (int k = 0; k < 5; k++) {
                vec2 bz = sd_bezier(q, A[k] * u, B[k] * u, C[k] * u);
                float w = u * (0.12 - 0.09 * bz.y);
                if (bz.x - w < d) { d = bz.x - w; along = bz.y; dc = clamp(1.0 - bz.x / w, 0.0, 1.0); }
            }
            vec3 bark = mix(vec3(0.52, 0.35, 0.2), vec3(0.42, 0.40, 0.37), wither);
            vec3 c = bark * (0.5 + 0.6 * dc) * (0.85 + 0.2 * sin(along * 30.0 + q.x * 0.5));
            float keep = step(smoothstep(0.4, 1.0, wither) * 1.05, noise(p / u * 3.0 + seed * 2.0));
            vec4 res = vec4(c, fill_aa(d) * keep);
            // The seed pod, swelling and paling as the next spread nears.
            vec2 pq = p - vec2(0.0, 0.02 * u);
            float pod = (length(pq / vec2(0.36, 0.28)) - u) * 0.28;
            vec3 pc = mix(vec3(0.22, 0.45, 0.16), vec3(0.72, 0.78, 0.25), ripe) * (0.7 + 0.4 * smoothstep(0.25 * u, -0.25 * u, pq.y + pq.x * 0.5));
            pc = mix(pc, pc * 0.7, fill_aa(abs(abs(pq.x) - 0.16 * u) - 0.6) * 0.6);
            pc = mix(pc, bark, wither);
            float pulse = ripe > 0.99 ? 0.5 + 0.5 * sin(t * 5.0) : 0.0;
            float sprout = min(sd_petal(rot(0.8) * (pq + vec2(0.06 * u, 0.24 * u)), 0.3 * u, 0.1 * u),
                               sd_petal(rot(-0.7) * (pq + vec2(-0.06 * u, 0.24 * u)), 0.26 * u, 0.09 * u));
            res = over(res, vec3(0.75, 0.95, 0.4), exp(-max(pod, 0.0) / (0.12 * u)) * pulse * 0.6 * (1.0 - fill_aa(pod)));
            res = over(res, mix(vec3(0.25, 0.55, 0.2), bark, wither), fill_aa(sprout) * keep);
            res = over(res, pc, fill_aa(pod) * keep);
            col = vec4(res.rgb, res.a * v_color.a);
        } else if (kind == SHAPE_TUBE) {                // a glass tube, liquid passing through
            vec2 bz = sd_bezier(p, v_p0.xy, v_p0.zw, v_p1.xy);
            float w = v_p1.z;
            float head = v_p1.w;
            float d = bz.x - w;
            vec4 c = vec4(0.10, 0.08, 0.16, 0.45 * fill_aa(d));
            float slug = smoothstep(head - 0.7, head - 0.55, bz.y) * (1.0 - smoothstep(head - 0.03, head, bz.y));
            c = over(c, v_color.rgb * (1.1 - 0.4 * bz.x / w), fill_aa(bz.x - w * 0.72) * slug * v_color.a);
            vec3 gc = mix(vec3(0.86, 0.92, 1.0), light.rgb, 0.18 + 0.22 * light.a);
            float rim = fill_aa(abs(d + 1.1) - 1.1);
            float shine = fill_aa(abs(bz.x - w * 0.4) - 0.6) * 0.3 * fill_aa(d);
            c = over(c, gc, clamp(rim * 0.6 + shine, 0.0, 1.0));
            col = c;
        } else if (kind == SHAPE_SALAMANDER) {          // the fire lizard
            float u = h.x / 1.05;
            float seed = v_p0.x;
            float leap = v_p0.z;
            vec2 q = vec2(p.x * v_p0.y, p.y);
            float cyc = fract(t / 3.2 + seed);
            float flick = (sin(t * 1.7 + seed * 5.0) * 0.06 + exp(-cyc * 9.0) * sin(cyc * 40.0) * 0.14) * u;
            vec2 bb = sd_bezier(q, vec2(-0.32 * u, 0.02 * u), vec2(0.0, -0.1 * u - leap * 0.05 * u), vec2(0.3 * u, -0.02 * u));
            float body = bb.x - u * (0.15 - 0.06 * abs(bb.y - 0.5));
            vec2 hq = q - vec2(0.48 * u, -0.07 * u);
            float head = (length(hq / vec2(0.21, 0.14)) - u) * 0.14;
            vec2 tb = sd_bezier(q, vec2(-0.3 * u, 0.02 * u), vec2(-0.78 * u, flick * 0.5 - leap * 0.1 * u),
                                vec2((-0.86 + 0.3 * leap) * u, 0.42 * u + flick - leap * 0.45 * u));
            float tail = tb.x - u * 0.1 * (1.0 - 0.85 * tb.y);
            float lg = 1e5;
            for (int k = 0; k < 2; k++) {
                float x0 = k == 0 ? 0.2 * u : -0.2 * u;
                float s = k == 0 ? 1.0 : -1.0;
                vec2 a = vec2(x0, 0.04 * u);
                vec2 b = vec2(x0 + s * 0.1 * u * (1.0 + leap * 1.5), 0.24 * u - leap * 0.1 * u);
                lg = min(lg, min(sd_segment(q, a, b) - 0.045 * u, sd_circle(q - b, 0.055 * u)));
            }
            float d = smin(smin(body, head, 0.06 * u), smin(tail, lg, 0.04 * u), 0.05 * u);
            // Red along the back, gold underneath, dark spots.
            float belly = smoothstep(-0.12 * u, 0.1 * u, q.y);
            vec3 c = mix(vec3(0.8, 0.15, 0.05), vec3(1.0, 0.72, 0.2), belly);
            c = mix(c, vec3(0.45, 0.05, 0.03), dots(q / (0.1 * u) + seed * 9.0, 0.24) * (1.0 - belly));
            c *= 0.75 + 0.35 * clamp(-d / (0.08 * u), 0.0, 1.0);
            c += vec3(1.0, 0.5, 0.1) * 0.15 * light.a;
            vec2 ep = q - vec2(0.55 * u, -0.12 * u);
            c = mix(c, vec3(0.05), fill_aa(length(ep) - 0.045 * u));
            c = mix(c, vec3(1.0), fill_aa(length(ep - vec2(0.012 * u, -0.014 * u)) - 0.015 * u));
            // Its glow under it, small flames along its back over it.
            float halo = exp(-max(d, 0.0) / (0.12 * u)) * (0.3 + 0.4 * v_p0.w) * (1.0 - fill_aa(d));
            vec4 res = over(vec4(vec3(1.0, 0.45, 0.12), clamp(halo, 0.0, 1.0)), c, fill_aa(d));
            for (int k = 0; k < 3; k++) {
                float fk = float(k);
                vec2 fb = vec2((-0.22 + 0.2 * fk) * u, -0.13 * u);
                vec4 fl = flame(q - fb, u * (0.065 + 0.015 * fk) * (1.0 + v_p0.w * 0.6), light.a, seed * 10.0 + fk * 2.0, t);
                res = over(res, fl.rgb, fl.a * 0.9);
            }
            col = vec4(res.rgb, res.a * v_color.a);
        } else if (kind == SHAPE_HEAT) {                // a heat pulse travelling along a curve
            vec2 bz = sd_bezier(p, v_p0.xy, v_p0.zw, v_p1.xy);
            float w = v_p1.z;
            float packet = exp(-pow((bz.y - v_p1.w) / 0.16, 2.0));
            float ripple = 0.5 + 0.5 * sin(bz.y * 38.0 - t * 26.0 + bz.x * 0.5);
            float band = exp(-bz.x * bz.x / (w * w));
            float a = band * packet * (0.3 + 0.7 * ripple);
            col = vec4(mix(vec3(1.0, 0.32, 0.06), vec3(1.0, 0.86, 0.45), ripple * packet), clamp(a, 0.0, 1.0) * v_color.a);
        } else if (kind == SHAPE_SHARD) {               // a bit flying off
            float r = min(h.x, h.y);
            int which = int(v_p0.x + 0.5);
            if (which == 2) {
                float d = sd_petal(p + vec2(0.0, r * 0.9), r * 1.8, r * 0.6);
                col = vec4(v_color.rgb * (p.x > 0.0 ? 1.0 : 0.8), fill_aa(d) * v_color.a);
            } else if (which == 3) {
                float g = exp(-dot(p, p) / (r * r * 0.4));
                col = vec4(mix(v_color.rgb, vec3(1.0, 0.9, 0.6), g), g * v_color.a);
            } else {
                float d = sd_triangle(p, vec2(-0.9 * r, -0.5 * r), vec2(0.8 * r, -0.85 * r), vec2(0.15 * r, 0.95 * r));
                vec3 c = v_color.rgb * (0.85 + 0.25 * smoothstep(-r, r, -p.x - p.y));
                if (which == 0) c = mix(c, vec3(1.0), fill_aa(abs(d + 0.7) - 0.6) * 0.8);
                col = vec4(c, fill_aa(d) * v_color.a * (which == 0 ? 0.85 : 1.0));
            }
        }
        if (col.a <= 0.001) discard;
        result = vec4(col.rgb * col.a, col.a);
    }
    """;
