// The shape pipeline's shaders and the numbers both sides agree on: which
// shape an instance draws (Shape) and which toolbar icon (Icon). The shader
// names the numbers with #defines, since it is compiled with the program and
// cannot be generated; the tests check the two lists stay the same.

import std;

enum Shape {
    Rect,       // rounded rectangle; p0: radius, border, gradient on; p1: second color
    Glow,       // soft ellipse; p0.x: softness 0..1
    FlaskBack,  // the inside of a flask
    Liquid,     // p0: colors of layers k and k + 4, as k + 32 (k + 4); p1: fill, murk bits, wave, height
    Glass,      // glass and rim; p0.x: glow
    Stream,     // a falling stream; p0.x: phase
    Symbol,     // color-blind symbol; p0.x: which
    Spark,      // four-pointed star
    Ice,        // ice block; p0.x: crack seed
    Cloth,      // draped cloth over a flask
    Curtain,    // stage curtain; p0.x: how far open 0..1
    Gift,       // wrapped box; p1: ribbon color
    Cork,       // cork; p1: key color band
    Padlock,    // padlock; color is the key color
    Wood,       // a wooden plank
    Backdrop,   // the room behind it all
    Icon,       // toolbar icons; p0.x: which Icon
    Seal,       // a completed flask's stopper with a wax seal
    Ring,       // a circle outline; p0.x: thickness
}

let ALL_SHAPES: const Shape[19] = [
    Shape.Rect, Shape.Glow, Shape.FlaskBack, Shape.Liquid, Shape.Glass, Shape.Stream, Shape.Symbol,
    Shape.Spark, Shape.Ice, Shape.Cloth, Shape.Curtain, Shape.Gift, Shape.Cork, Shape.Padlock, Shape.Wood,
    Shape.Backdrop, Shape.Icon, Shape.Seal, Shape.Ring,
];

fn shape_index(s: Shape) -> i64 {
    match s {
        Rect => 0, Glow => 1, FlaskBack => 2, Liquid => 3, Glass => 4, Stream => 5, Symbol => 6,
        Spark => 7, Ice => 8, Cloth => 9, Curtain => 10, Gift => 11, Cork => 12, Padlock => 13,
        Wood => 14, Backdrop => 15, Icon => 16, Seal => 17, Ring => 18,
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
        Icon => "SHAPE_ICON", Seal => "SHAPE_SEAL", Ring => "SHAPE_RING",
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
    layout(set = 3, binding = 0) uniform Look { vec4 palette[20]; vec4 screen; };

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
                float wave = v_p1.z * sin(p.x * 0.35 + t * 9.0) * 1.6;
                float surface = fill + wave;
                if (lvl < surface && v_p1.x > 0.001) {
                    float fi = clamp(floor(max(lvl, 0.0) / seg), 0.0, cap - 1.0);
                    int idx = int(fi) % 4;
                    float pair = idx == 0 ? v_p0.x : idx == 1 ? v_p0.y : idx == 2 ? v_p0.z : v_p0.w;
                    float ci = fi < 3.5 ? mod(pair, 32.0) : floor(pair / 32.0);
                    vec3 c = palette[int(ci + 0.5)].rgb;
                    bool hidden = ((int(v_p1.y + 0.5) >> int(fi)) & 1) != 0;
                    if (hidden) {
                        float n = noise(p * 0.12 + vec2(t * 0.3, fi * 7.0));
                        c = mix(vec3(0.20, 0.17, 0.28), vec3(0.33, 0.29, 0.42), n);
                    }
                    c = shade_liquid(c, p.x, h.x);
                    // A darker line between layers, a bright edge on top.
                    float edge = abs(lvl - (fi + 1.0) * seg);
                    if (fi + 1.0 < v_p1.x - 0.01) c *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 1.6, edge));
                    float surf = surface - lvl;
                    c += vec3(0.25) * (1.0 - smoothstep(0.0, 2.5, surf));
                    float a = fill_aa(inside) * clamp(surf + 0.5, 0.0, 1.0);
                    col = vec4(c, a * v_color.a);
                }
            }
        } else if (kind == SHAPE_GLASS) {                 // glass, rim and highlights
            float d = sd_flask(p, h);
            float wall = h.x * 0.13;
            float rim = fill_aa(abs(d + wall * 0.5) - wall * 0.5);
            float body = fill_aa(d);
            vec3 c = v_color.rgb;
            float a = body * 0.07 + rim * 0.55;
            float sx = p.x / h.x;
            float streak = smoothstep(-0.78, -0.62, sx) * (1.0 - smoothstep(-0.55, -0.4, sx)) *
                           smoothstep(-h.y * 0.45, -h.y * 0.25, p.y) * (1.0 - smoothstep(h.y * 0.5, h.y *
                           0.75, p.y));
            float streak2 = smoothstep(0.5, 0.6, sx) * (1.0 - smoothstep(0.62, 0.7, sx)) *
                            smoothstep(-h.y * 0.1, h.y * 0.1, p.y) * (1.0 - smoothstep(h.y * 0.3, h.y *
                            0.45, p.y));
            a += body * (streak * 0.45 + streak2 * 0.25);
            col = vec4(c, clamp(a, 0.0, 1.0) * v_color.a);
            if (v_p0.x > 0.0) {
                float g = exp(-max(d, 0.0) * 0.28) * (1.0 - body) * v_p0.x;
                col = vec4(mix(col.rgb, v_p1.rgb, g / max(col.a + g, 0.001)), max(col.a, g * 0.8));
            }
        } else if (kind == SHAPE_STREAM) {                 // falling stream
            float y01 = clamp((p.y + h.y) / (2.0 * h.y), 0.0, 1.0);
            float w = h.x * (0.65 + 0.35 * y01) * (0.85 + 0.15 * sin(p.y * 0.25 - t * 30.0 + v_p0.x));
            float d = abs(p.x) - w;
            float a = fill_aa(d) * smoothstep(0.0, 0.04, y01);
            vec3 c = v_color.rgb * (0.85 + 0.3 * (1.0 - abs(p.x / max(w, 0.1))));
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
            vec2 uv = (p + h) / (2.0 * h);
            vec3 top = vec3(0.10, 0.08, 0.20);
            vec3 mid = vec3(0.21, 0.13, 0.28);
            vec3 c = mix(top, mid, smoothstep(0.0, 0.85, uv.y));
            // A warm glow, as from candles on the table.
            float glow = exp(-pow(length((uv - vec2(0.5, 0.92)) * vec2(1.0, 1.8)), 2.0) * 3.0);
            c += vec3(0.45, 0.25, 0.10) * glow * 0.55;
            // Stone wall blocks, faintly.
            vec2 bp = vec2(uv.x * 6.0 + step(0.5, fract(uv.y * 7.0)) * 0.5, uv.y * 7.0);
            vec2 f = abs(fract(bp) - 0.5);
            float mortar = smoothstep(0.47, 0.5, max(f.x, f.y));
            c *= 1.0 - mortar * 0.25;
            c *= 0.9 + 0.1 * noise(p * 0.02);
            float vig = smoothstep(1.25, 0.35, length((uv - 0.5) * vec2(1.3, 1.0)));
            c *= mix(0.55, 1.0, vig);
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
        }
        if (col.a <= 0.001) discard;
        result = vec4(col.rgb * col.a, col.a);
    }
    """;
