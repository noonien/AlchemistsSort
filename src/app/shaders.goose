// The shape pipeline's shaders and the numbers both sides agree on: which
// shape an instance draws (Shape) and which toolbar icon (Icon). The shader
// names the numbers with #defines, since it is compiled with the program and
// cannot be generated; the tests check the two lists stay the same.

import std;

enum Shape {
    Rect,       // rounded rectangle; p0: radius, border, gradient on; p1: second color
    Glow,       // soft ellipse; p0.x: softness 0..1
    FlaskBack,  // the inside of a flask
    Liquid,     // p0: colors of layers k and k + 4, as k + 32 (k + 4); p1: fill, murk bits, ripple, height;
                // color: slosh slope, seed, ripple center (in half widths), alpha
    Glass,      // glass and rim; p0.x: glow
    Stream,     // a falling stream along a curve; p0: start, control; p1: end, width, phase
    Symbol,     // color-blind symbol; p0.x: which
    Spark,      // four-pointed star
    Ice,        // ice block; p0.x: crack seed
    Cloth,      // draped cloth over a flask
    Curtain,    // stage curtain; p0.x: how far open 0..1
    Gift,       // wrapped box; p1: ribbon color
    Cork,       // cork; p1: key color band
    Padlock,    // padlock; color is the key color
    Wood,       // a wooden plank
    Backdrop,   // the room behind it all; p0: theme, unscaled half width
    Icon,       // toolbar icons; p0.x: which Icon
    Seal,       // a completed flask's stopper with a wax seal
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
}

let ALL_SHAPES: const Shape[29] = [
    Shape.Rect, Shape.Glow, Shape.FlaskBack, Shape.Liquid, Shape.Glass, Shape.Stream, Shape.Symbol,
    Shape.Spark, Shape.Ice, Shape.Cloth, Shape.Curtain, Shape.Gift, Shape.Cork, Shape.Padlock, Shape.Wood,
    Shape.Backdrop, Shape.Icon, Shape.Seal, Shape.Ring, Shape.Candle, Shape.Beam, Shape.Glyph, Shape.Stone,
    Shape.Ink, Shape.Alembic, Shape.Steam, Shape.Label, Shape.Pebble, Shape.Vial,
];

fn shape_index(s: Shape) -> i64 {
    match s {
        Rect => 0, Glow => 1, FlaskBack => 2, Liquid => 3, Glass => 4, Stream => 5, Symbol => 6,
        Spark => 7, Ice => 8, Cloth => 9, Curtain => 10, Gift => 11, Cork => 12, Padlock => 13,
        Wood => 14, Backdrop => 15, Icon => 16, Seal => 17, Ring => 18, Candle => 19, Beam => 20,
        Glyph => 21, Stone => 22, Ink => 23, Alembic => 24, Steam => 25, Label => 26, Pebble => 27,
        Vial => 28,
    }
}

// The shader's name for a shape.
fn shape_define(s: Shape) -> const u8[:] {
    match s {
        Rect => "SHAPE_RECT", Glow => "SHAPE_GLOW", FlaskBack => "SHAPE_FLASK_BACK",
        Liquid => "SHAPE_LIQUID", Glass => "SHAPE_GLASS", Stream => "SHAPE_STREAM",
        Symbol => "SHAPE_SYMBOL", Spark => "SHAPE_SPARK", Ice => "SHAPE_ICE", Cloth => "SHAPE_CLOTH",
        Curtain => "SHAPE_CURTAIN", Gift => "SHAPE_GIFT", Cork => "SHAPE_CORK",
        Padlock => "SHAPE_PADLOCK", Wood => "SHAPE_WOOD", Backdrop => "SHAPE_BACKDROP",
        Icon => "SHAPE_ICON", Seal => "SHAPE_SEAL", Ring => "SHAPE_RING", Candle => "SHAPE_CANDLE",
        Beam => "SHAPE_BEAM", Glyph => "SHAPE_GLYPH", Stone => "SHAPE_STONE", Ink => "SHAPE_INK",
        Alembic => "SHAPE_ALEMBIC", Steam => "SHAPE_STEAM", Label => "SHAPE_LABEL",
        Pebble => "SHAPE_PEBBLE", Vial => "SHAPE_VIAL",
    }
}

// The pictures Shape.Icon draws.
enum Icon {
    Undo, Restart, Shuffle, Bottle, Hint, Home, Gear, SoundOn, SoundOff, Play, Eye, Seed, Book, Back, Check,
}

let ALL_ICONS: const Icon[15] = [
    Icon.Undo, Icon.Restart, Icon.Shuffle, Icon.Bottle, Icon.Hint, Icon.Home, Icon.Gear, Icon.SoundOn,
    Icon.SoundOff, Icon.Play, Icon.Eye, Icon.Seed, Icon.Book, Icon.Back, Icon.Check,
];

fn icon_index(i: Icon) -> i64 {
    match i {
        Undo => 0, Restart => 1, Shuffle => 2, Bottle => 3, Hint => 4, Home => 5, Gear => 6, SoundOn => 7,
        SoundOff => 8, Play => 9, Eye => 10, Seed => 11, Book => 12, Back => 13, Check => 14,
    }
}

// The shader's name for an icon.
fn icon_define(i: Icon) -> const u8[:] {
    match i {
        Undo => "ICON_UNDO", Restart => "ICON_RESTART", Shuffle => "ICON_SHUFFLE", Bottle => "ICON_BOTTLE",
        Hint => "ICON_HINT", Home => "ICON_HOME", Gear => "ICON_GEAR", SoundOn => "ICON_SOUND_ON",
        SoundOff => "ICON_SOUND_OFF", Play => "ICON_PLAY", Eye => "ICON_EYE", Seed => "ICON_SEED",
        Book => "ICON_BOOK", Back => "ICON_BACK", Check => "ICON_CHECK",
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
        vec2 world = i_pos + vec2(c * local.x - s * local.y, s * local.x + c * local.y);
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
    #define SHAPE_CURTAIN 10
    #define SHAPE_GIFT 11
    #define SHAPE_CORK 12
    #define SHAPE_PADLOCK 13
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

    // The flask: a round-bottomed body, a neck and a lip, at half size h.
    float sd_flask(vec2 p, vec2 h) {
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
    // Where the liquid sits: the body's inside, bottom and height.
    void flask_body(vec2 h, out float bottom, out float top) {
        float body_top = -h.y + h.x * 0.95;
        bottom = h.y - h.x * 0.16;
        top = body_top + h.x * 0.25;
    }

    vec3 shade_liquid(vec3 c, float x, float w) {
        float t = x / w;
        float light = 1.0 - 0.38 * t * t + 0.12 * (1.0 - smoothstep(-0.75, -0.35, t)) * 0.0;
        vec3 col = c * light;
        float streak = smoothstep(-0.62, -0.5, t) * (1.0 - smoothstep(-0.44, -0.3, t));
        return col + vec3(0.22) * streak;
    }

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
            float f = abs(sd_flask(p - vec2(-r * 0.25, 0.1 * r), vec2(r * 0.32, r * 0.8))) - r * 0.08;
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
        } else if (which == ICON_BOOK) {   // book
            float l = abs(sd_box(p - vec2(-r * 0.4, 0.0), vec2(r * 0.38, r * 0.6))) - r * 0.07;
            float rr = abs(sd_box(p - vec2(r * 0.4, 0.0), vec2(r * 0.38, r * 0.6))) - r * 0.07;
            return min(l, rr);
        } else if (which == ICON_BACK) {   // back arrow
            float shaft = sd_segment(p, vec2(-r * 0.6, 0.0), vec2(r * 0.7, 0.0)) - r * 0.1;
            float head = sd_triangle(p, vec2(-r * 0.85, 0.0), vec2(-r * 0.2, -r * 0.55), vec2(-r * 0.2, r
            * 0.55));
            return min(shaft, head);
        }
        // check mark
        return min(sd_segment(p, vec2(-r * 0.6, 0.0), vec2(-r * 0.15, r * 0.45)),
                   sd_segment(p, vec2(-r * 0.15, r * 0.45), vec2(r * 0.7, -r * 0.5))) - r * 0.12;
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
            float a = fill_aa(d + 1.5);
            float shade = 0.75 + 0.25 * (1.0 - abs(p.x / h.x));
            col = vec4(v_color.rgb * shade, v_color.a * a);
        } else if (kind == SHAPE_LIQUID) {                 // liquid
            float bottom; float top;
            flask_body(h, bottom, top);
            float cap = max(v_p1.w, 4.0);
            float seg = (bottom - top) / cap;
            float inside = sd_flask(p, h) + h.x * 0.13;
            if (inside < 0.5) {
                float tilt = clamp(tan(v_misc.y), -2.6, 2.6);
                float lvl = bottom - p.y - tilt * p.x;
                float fill = v_p1.x * seg;
                // The surface: a slow idle drift, the slosh's tilt, and ripples
                // spreading from where a stream lands.
                float seed = v_color.g;
                float drift = h.x * 0.035 * (0.6 * sin(p.x / h.x * 1.7 + t * 1.1 + seed * 6.3) +
                                             0.4 * sin(p.x / h.x * 3.9 - t * 1.6 + seed * 2.1));
                float rx = (p.x - v_color.b * h.x) / h.x;
                float ripple = v_p1.z * h.x * 0.09 * sin(rx * 7.0 - t * 15.0) * exp(-abs(rx) * 1.1);
                float surface = fill + drift + v_color.r * p.x + ripple;
                if (lvl < surface && v_p1.x > 0.001) {
                    float fi = clamp(floor(max(lvl, 0.0) / seg), 0.0, min(cap, ceil(v_p1.x - 0.001)) - 1.0);
                    int idx = int(fi) % 4;
                    float pair = idx == 0 ? v_p0.x : idx == 1 ? v_p0.y : idx == 2 ? v_p0.z : v_p0.w;
                    float ci = fi < 3.5 ? mod(pair, 32.0) : floor(pair / 32.0);
                    vec3 c = palette[int(ci + 0.5)].rgb;
                    bool hidden = ((int(v_p1.y + 0.5) >> int(fi)) & 1) != 0;
                    if (hidden) {
                        float n = noise(p * 0.12 + vec2(t * 0.3, fi * 7.0));
                        c = mix(vec3(0.20, 0.17, 0.28), vec3(0.33, 0.29, 0.42), n);
                    } else {
                        c = personality(c, int(ci + 0.5), p / h.x + vec2(seed * 3.0, 0.0), t);
                    }
                    c = shade_liquid(c, p.x, h.x);
                    // A darker line between layers, a bright edge on top.
                    float edge = abs(lvl - (fi + 1.0) * seg);
                    if (fi + 1.0 < v_p1.x - 0.01) c *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 1.6, edge));
                    float surf = surface - lvl;
                    c += vec3(0.25) * (1.0 - smoothstep(0.0, 2.5, surf));
                    // Now and then a bubble rises from the bottom.
                    float period = 7.0 + fract(seed * 7.13) * 5.0;
                    float cyc = t / period + seed;
                    float rise = 2.4 / period;
                    if (fract(cyc) < rise && tilt == 0.0 && fill > seg * 0.6) {
                        float k = fract(cyc) / rise;
                        vec2 bc = vec2((hash12(vec2(floor(cyc), seed * 13.0)) - 0.5) * h.x * 0.9 +
                                       sin(k * 9.0) * h.x * 0.06, bottom - k * (fill - h.x * 0.1));
                        float bd = length(p - bc) - h.x * (0.05 + 0.03 * k);
                        c = mix(c, c * 0.8 + vec3(0.3), fill_aa(abs(bd) - 0.6) * 0.8);
                        c += vec3(0.08) * fill_aa(bd);
                    }
                    float a = fill_aa(inside) * clamp(surf + 0.5, 0.0, 1.0);
                    col = vec4(c, a * v_color.a);
                }
            }
        } else if (kind == SHAPE_GLASS) {                 // glass, rim and highlights
            float d = sd_flask(p, h);
            float wall = h.x * 0.13;
            float rim = fill_aa(abs(d + wall * 0.5) - wall * 0.5);
            float body = fill_aa(d);
            // The candlelight warms the glass, and flickers in it.
            vec3 c = mix(v_color.rgb, light.rgb, 0.18 + 0.22 * light.a);
            float a = body * 0.07 + rim * (0.47 + 0.16 * light.a);
            float sx = p.x / h.x;
            float streak = smoothstep(-0.78, -0.62, sx) * (1.0 - smoothstep(-0.55, -0.4, sx)) *
                           smoothstep(-h.y * 0.45, -h.y * 0.25, p.y) * (1.0 - smoothstep(h.y * 0.5, h.y *
                           0.75, p.y));
            float streak2 = smoothstep(0.5, 0.6, sx) * (1.0 - smoothstep(0.62, 0.7, sx)) *
                            smoothstep(-h.y * 0.1, h.y * 0.1, p.y) * (1.0 - smoothstep(h.y * 0.3, h.y *
                            0.45, p.y));
            a += body * (streak * (0.36 + 0.16 * light.a) + streak2 * 0.25);
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
        } else if (kind == SHAPE_ICE) {                 // ice block
            float d = sd_round_box(p, h, vec4(h.x * 0.25));
            float a = fill_aa(d);
            float n = noise(p * 0.05 + v_p0.x) * 0.6 + noise(p * 0.15 + v_p0.x * 3.0) * 0.4;
            vec3 c = mix(vec3(0.70, 0.86, 0.97), vec3(0.93, 0.98, 1.0), n);
            // Cracks: thin lines of a cell pattern.
            vec2 g = p * 0.045 + v_p0.x;
            vec2 ip = floor(g);
            float m1 = 9.0; float m2 = 9.0;
            for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
                vec2 o = vec2(float(i), float(j));
                vec2 r = o + vec2(hash12(ip + o), hash12(ip + o + 17.0)) - fract(g);
                float dd = dot(r, r);
                if (dd < m1) { m2 = m1; m1 = dd; } else if (dd < m2) { m2 = dd; }
            }
            float crack = 1.0 - smoothstep(0.0, 0.06, sqrt(m2) - sqrt(m1));
            c = mix(c, vec3(1.0), crack * 0.7);
            float edge = 1.0 - smoothstep(0.0, 5.0, -d);
            c = mix(c, vec3(1.0), edge * 0.5);
            col = vec4(c, a * (0.78 + 0.15 * crack) * v_color.a);
        } else if (kind == SHAPE_CLOTH) {                 // cloth over a flask
            float hem = h.y - 6.0 + 5.0 * sin(p.x * 0.18 + 1.3) + 3.0 * sin(p.x * 0.41);
            float top = -h.y;
            float halfw = mix(h.x * 0.55, h.x, smoothstep(top, top + h.y * 0.5, p.y));
            float d = max(abs(p.x) - halfw, max(top - p.y, p.y - hem));
            float a = fill_aa(d);
            float folds = 0.5 + 0.5 * sin(p.x * 0.22 + 0.7 * sin(p.y * 0.05));
            vec3 c = v_color.rgb * (0.62 + 0.38 * folds);
            c *= 0.9 + 0.1 * noise(p * 0.3);
            float knot = fill_aa(sd_circle(p - vec2(0.0, top + h.x * 0.35), h.x * 0.28));
            c = mix(c, v_color.rgb * 1.15, knot);
            col = vec4(c, a * v_color.a);
        } else if (kind == SHAPE_CURTAIN) {                // curtain
            float open = v_p0.x;
            float half_w = h.x * (1.0 - open * 0.85);
            float side = sign(p.x);
            float x = abs(p.x);
            float panel_edge = h.x - half_w;
            float d = max(panel_edge - x, abs(p.y) - h.y);
            if (open < 0.01) d = sd_box(p, h);
            float a = fill_aa(d);
            float folds = 0.5 + 0.5 * sin(x * 0.35 * (1.0 + open * 1.5));
            vec3 c = v_color.rgb * (0.55 + 0.45 * folds);
            float valance = step(p.y, -h.y + h.y * 0.12);
            c = mix(c, v_color.rgb * 0.8 + vec3(0.25, 0.18, 0.0), valance);
            float tassel = 1.0 - smoothstep(-1.0, 1.0, abs(p.y + h.y * 0.85) - 2.0);
            c = mix(c, vec3(0.95, 0.78, 0.35), tassel * 0.8);
            col = vec4(c, a * v_color.a);
        } else if (kind == SHAPE_GIFT) {                // gift box
            float box = sd_round_box(p - vec2(0.0, h.y * 0.12), vec2(h.x, h.y * 0.88), vec4(5.0));
            float lid = sd_round_box(p - vec2(0.0, -h.y * 0.72), vec2(h.x * 1.06, h.y * 0.14), vec4(4.0));
            float d = min(box, lid);
            float a = fill_aa(d);
            vec3 c = v_color.rgb * (0.85 + 0.15 * step(lid, 0.5));
            float stripes = step(0.5, fract((p.x + p.y) * 0.04));
            c *= 0.92 + 0.08 * stripes;
            float ribbon = min(abs(p.x) - h.x * 0.14, 1e5);
            float bow = min(sd_circle(p - vec2(-h.x * 0.32, -h.y * 0.92), h.x * 0.26),
                            sd_circle(p - vec2(h.x * 0.32, -h.y * 0.92), h.x * 0.26));
            float rib = max(fill_aa(ribbon), fill_aa(bow));
            c = mix(c, v_p1.rgb, rib);
            col = vec4(c, max(a, fill_aa(bow)) * v_color.a);
        } else if (kind == SHAPE_CORK) {                // cork
            float d = sd_round_box(p, h, vec4(h.x * 0.25, h.x * 0.15, h.x * 0.25, h.x * 0.15));
            float a = fill_aa(d);
            float n = noise(p * 0.5);
            vec3 c = mix(vec3(0.62, 0.45, 0.28), vec3(0.78, 0.6, 0.4), n);
            float band = 1.0 - smoothstep(0.0, 1.0, abs(p.y + h.y * 0.05) - h.y * 0.32);
            c = mix(c, v_p1.rgb, band);
            col = vec4(c, a * v_color.a);
        } else if (kind == SHAPE_PADLOCK) {                // padlock
            float shackle = sd_arc(p - vec2(0.0, -h.y * 0.15), h.x * 0.55, 3.14159, 6.28318, h.x * 0.12);
            float body = sd_round_box(p - vec2(0.0, h.y * 0.35), vec2(h.x, h.y * 0.62), vec4(h.x * 0.25));
            float hole = min(sd_circle(p - vec2(0.0, h.y * 0.25), h.x * 0.17),
                             sd_box(p - vec2(0.0, h.y * 0.45), vec2(h.x * 0.07, h.y * 0.2)));
            float d = min(shackle, max(body, -hole));
            float a = fill_aa(d);
            vec3 c = mix(vec3(0.72, 0.72, 0.78), v_color.rgb, step(body, 0.5));
            c *= 0.8 + 0.2 * (1.0 - (p.y + h.y) / (2.0 * h.y));
            col = vec4(c, a);
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
            vec3 c = room(int(v_p0.x + 0.5), cv, t);
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
        } else if (kind == SHAPE_SEAL) {                // seal: stopper and wax
            float stop = sd_round_box(p - vec2(0.0, -h.y * 0.25), vec2(h.x * 0.8, h.y * 0.55), vec4(h.x *
            0.25));
            float wax = sd_circle(p - vec2(0.0, h.y * 0.45), h.x * 0.55) +
                        0.8 * sin(atan(p.y - h.y * 0.45, p.x) * 7.0);
            float a = max(fill_aa(stop), fill_aa(wax));
            vec3 c = mix(vec3(0.66, 0.5, 0.33), v_color.rgb * 0.9, fill_aa(wax));
            float shine = fill_aa(sd_circle(p - vec2(-h.x * 0.15, h.y * 0.35), h.x * 0.15));
            c += vec3(0.25) * shine;
            col = vec4(c, a);
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
        }
        if (col.a <= 0.001) discard;
        result = vec4(col.rgb * col.a, col.a);
    }
    """;
