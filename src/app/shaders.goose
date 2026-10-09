// The shapes' shaders and the numbers both sides agree on: which shape an
// instance draws (Shape), which toolbar icon (Icon), and which program
// draws each shape (Program). The shader names the numbers with #defines,
// and keeps each program's shapes under its own, since it is compiled with
// the program and cannot be generated; the tests check that the lists and
// the shader agree.

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
    Cloth,      // a shroud draped over a flask, embroidered with stars; p0.x 1: a curtain on a rod
                // instead, p0.y: drawn aside 0..1, p0.z: seed
    Wax,        // a wax seal over the neck; color: the key; p0: softened 0..1, crack 0..1, seed
    Vines,      // a vine wrapped round a flask; p0: grown 0..1, withered 0..1, burnt 0..1, seed
    Tap,        // a siphon's brass tap
    Lantern,    // a lantern on a crook, 1.3 of its units wide; p0: lit 0..1, flare, seed;
                // p1: the crook's post across and its foot down, in its units
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
    Door,       // a double door in its frame before a few flasks; color: the frame; p0: swung open
                // 0..1, the key (1..3: its bow engraved on the lock); p1: the lock's metal
    Salamander, // the fire lizard; p0: seed, facing (1 right, -1 left), leap 0..1, glow
    Heat,       // a heat pulse along a curve; p0: start, control; p1: end, width, head
    Shard,      // a flying bit; p0.x: 0 ice, 1 wax, 2 leaf, 3 ember
    Key,        // a key, its bow on the left; color: its metal; p0: glint 0..1, which (1..3: its
                // bow's shape), under liquid 0..1, seed; p1: the liquid's color
    Sanctum,    // the title screen's room; p0.x: unscaled half width
    Astrolabe,  // gilt rings turning behind the title flask; p0: flared rune, flare 0..1, cut below
                // (in radii)
    Wisp,       // an alchemical sign drawn in steam; p0: seed, which sign, shown 0..1
    Flourish,   // a gilded scroll divider; p0.x: where the glint is, -1..1
    Parchment,  // the map's page on a dark desk; p0.x: unscaled half width
    Medallion,  // a chapter's roundel on the map; p0: theme, 0 locked 1 open 2 done; p1: its potion
    GildPath,   // a gilt line along a curve, faint ink dots past its head; p0: start, control;
                // p1: end, width, head 0..1
    Plinth,     // the ledge a flask stands on in a level; p0: theme, seed
    Plate,      // a widget's gilt-rimmed plate of enamel; color: the enamel; p0: style (0 a tablet,
                // 1 a banner, 2 a slot sunk in, 3 a panel), hover 0..1 (-1: disabled), rim width, pressed
    Bezel,      // a round widget: p0: style (0 enamel in a gilt ring, 1 a gilt bead), hover 0..1
                // (-1: disabled), rim width, pressed; color: the enamel
}

const SHAPES = 52;
let ALL_SHAPES: const Shape[SHAPES] = [
    Shape.Rect, Shape.Glow, Shape.FlaskBack, Shape.Liquid, Shape.Glass, Shape.Stream, Shape.Symbol,
    Shape.Spark, Shape.Ice, Shape.Cloth, Shape.Wax, Shape.Vines, Shape.Tap, Shape.Lantern, Shape.Wood,
    Shape.Backdrop, Shape.Icon, Shape.Seal, Shape.Ring, Shape.Candle, Shape.Beam, Shape.Glyph, Shape.Stone,
    Shape.Ink, Shape.Alembic, Shape.Steam, Shape.Label, Shape.Pebble, Shape.Vial, Shape.Smoke, Shape.Ribbon,
    Shape.Frame, Shape.Dial, Shape.Furnace, Shape.Bloom, Shape.Brazier, Shape.Roots, Shape.Door,
    Shape.Salamander, Shape.Heat, Shape.Shard, Shape.Key,
    Shape.Sanctum, Shape.Astrolabe, Shape.Wisp, Shape.Flourish, Shape.Parchment, Shape.Medallion, Shape.GildPath,
    Shape.Plinth, Shape.Plate, Shape.Bezel,
];

fn shape_index(s: Shape) -> i64 {
    match s {
        Rect => 0, Glow => 1, FlaskBack => 2, Liquid => 3, Glass => 4, Stream => 5, Symbol => 6,
        Spark => 7, Ice => 8, Cloth => 9, Wax => 10, Vines => 11, Tap => 12, Lantern => 13,
        Wood => 14, Backdrop => 15, Icon => 16, Seal => 17, Ring => 18, Candle => 19, Beam => 20,
        Glyph => 21, Stone => 22, Ink => 23, Alembic => 24, Steam => 25, Label => 26, Pebble => 27,
        Vial => 28, Smoke => 29, Ribbon => 30, Frame => 31, Dial => 32, Furnace => 33, Bloom => 34,
        Brazier => 35, Roots => 36, Door => 37, Salamander => 38, Heat => 39, Shard => 40, Key => 41,
        Sanctum => 42, Astrolabe => 43, Wisp => 44, Flourish => 45, Parchment => 46, Medallion => 47,
        GildPath => 48, Plinth => 49, Plate => 50, Bezel => 51,
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
        Brazier => "SHAPE_BRAZIER", Roots => "SHAPE_ROOTS", Door => "SHAPE_DOOR",
        Salamander => "SHAPE_SALAMANDER", Heat => "SHAPE_HEAT", Shard => "SHAPE_SHARD", Key => "SHAPE_KEY",
        Sanctum => "SHAPE_SANCTUM", Astrolabe => "SHAPE_ASTROLABE", Wisp => "SHAPE_WISP",
        Flourish => "SHAPE_FLOURISH", Parchment => "SHAPE_PARCHMENT", Medallion => "SHAPE_MEDALLION",
        GildPath => "SHAPE_GILDPATH", Plinth => "SHAPE_PLINTH", Plate => "SHAPE_PLATE", Bezel => "SHAPE_BEZEL",
    }
}

// The pictures Shape.Icon draws.
enum Icon {
    Undo, Restart, Shuffle, Bottle, Hint, Home, Gear, SoundOn, SoundOff, Play, Eye, Seed, Book, Back, Check, Map,
    // What a pour sets off, what ties two flasks, and what can't take a pour.
    Lock, Flame, Flake, Unseal, Flip, Leaf, Wither, Sun, Gold, Key, Hop, Rune, Close,
}

let ALL_ICONS: const Icon[29] = [
    Icon.Undo, Icon.Restart, Icon.Shuffle, Icon.Bottle, Icon.Hint, Icon.Home, Icon.Gear, Icon.SoundOn,
    Icon.SoundOff, Icon.Play, Icon.Eye, Icon.Seed, Icon.Book, Icon.Back, Icon.Check, Icon.Map,
    Icon.Lock, Icon.Flame, Icon.Flake, Icon.Unseal, Icon.Flip, Icon.Leaf, Icon.Wither, Icon.Sun, Icon.Gold,
    Icon.Key, Icon.Hop, Icon.Rune, Icon.Close,
];

fn icon_index(i: Icon) -> i64 {
    match i {
        Undo => 0, Restart => 1, Shuffle => 2, Bottle => 3, Hint => 4, Home => 5, Gear => 6, SoundOn => 7,
        SoundOff => 8, Play => 9, Eye => 10, Seed => 11, Book => 12, Back => 13, Check => 14, Map => 15,
        Lock => 16, Flame => 17, Flake => 18, Unseal => 19, Flip => 20, Leaf => 21, Wither => 22, Sun => 23,
        Gold => 24, Key => 25, Hop => 26, Rune => 27, Close => 28,
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
        Key => "ICON_KEY", Hop => "ICON_HOP", Rune => "ICON_RUNE", Close => "ICON_CLOSE",
    }
}

// The fragment shader is compiled as several programs, each drawing a few
// of the shapes, so that none is the whole of the art at once: a browser on
// Windows translates a shader to HLSL and compiles that slowly, the more so
// the bigger it is. The shapes every screen has (rectangles, glows, sparks
// and rings) are in all of them. The shader keeps each program's shapes
// under #ifdef PROGRAM_...; each room is a program of its own, ROOM naming
// its theme.
enum Program {
    Any,        // in every program
    Ui,         // the widgets and their icons, and the ink between screens
    Title,      // the title screen's study and the map
    Board,      // flasks, their liquid and what pours, the shelves and plinths
    Cellar,     // the first chapters' modifiers: wax seals, vows, rime, braziers, taps, keys, doors, cloth
    Garden,     // the Observatory's and the Greenhouse's: lanterns, hourglasses, vines, moonpetals
    Forge,      // fire and gold: the salamander, heat, the athanor, the Philosopher's Stone
    Room,       // a room behind a level or a menu, one program for each
}

fn shape_program(s: Shape) -> Program {
    match s {
        Rect, Glow, Spark, Ring => Program.Any,
        Plate, Bezel, Icon, Ink => Program.Ui,
        Sanctum, Astrolabe, Wisp, Flourish, Alembic, Steam, Parchment, Medallion, GildPath, Pebble => Program.Title,
        FlaskBack, Liquid, Glass, Stream, Symbol, Seal, Label, Wood, Candle, Vial, Plinth, Smoke, Shard,
        Beam => Program.Board,
        Wax, Ribbon, Ice, Brazier, Tap, Key, Door, Cloth => Program.Cellar,
        Lantern, Frame, Dial, Vines, Roots, Bloom => Program.Garden,
        Salamander, Heat, Furnace, Glyph, Stone => Program.Forge,
        Backdrop => Program.Room,
    }
}

// The shader's name for a program's shapes ("" for those in every program).
fn program_define(p: Program) -> const u8[:] {
    match p {
        Any => "", Ui => "PROGRAM_UI", Title => "PROGRAM_TITLE", Board => "PROGRAM_BOARD",
        Cellar => "PROGRAM_CELLAR", Garden => "PROGRAM_GARDEN", Forge => "PROGRAM_FORGE", Room => "PROGRAM_ROOM",
    }
}

// The programs by number: the six above, then a room for each theme.
const ROOMS = 6;
const PROGRAMS = 6 + ROOMS;

fn program_number(p: Program, theme: i64) -> i64 {
    match p {
        Any => -1, Ui => 0, Title => 1, Board => 2, Cellar => 3, Garden => 4, Forge => 5,
        Room => 6 + (if theme >= 0 && theme < ROOMS { theme } else { 0 }),
    }
}

// Each program's fragment shader, by number.
let PROGRAM_SHADERS: const u8[:][PROGRAMS] = [
    embed_shader("frag", "#define PROGRAM_UI", FRAGMENT_SHADER),
    embed_shader("frag", "#define PROGRAM_TITLE", FRAGMENT_SHADER),
    embed_shader("frag", "#define PROGRAM_BOARD", FRAGMENT_SHADER),
    embed_shader("frag", "#define PROGRAM_CELLAR", FRAGMENT_SHADER),
    embed_shader("frag", "#define PROGRAM_GARDEN", FRAGMENT_SHADER),
    embed_shader("frag", "#define PROGRAM_FORGE", FRAGMENT_SHADER),
    embed_shader("frag", "#define PROGRAM_ROOM", "#define ROOM 0", FRAGMENT_SHADER),
    embed_shader("frag", "#define PROGRAM_ROOM", "#define ROOM 1", FRAGMENT_SHADER),
    embed_shader("frag", "#define PROGRAM_ROOM", "#define ROOM 2", FRAGMENT_SHADER),
    embed_shader("frag", "#define PROGRAM_ROOM", "#define ROOM 3", FRAGMENT_SHADER),
    embed_shader("frag", "#define PROGRAM_ROOM", "#define ROOM 4", FRAGMENT_SHADER),
    embed_shader("frag", "#define PROGRAM_ROOM", "#define ROOM 5", FRAGMENT_SHADER),
];

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
    #define SHAPE_DOOR 37
    #define SHAPE_SALAMANDER 38
    #define SHAPE_HEAT 39
    #define SHAPE_SHARD 40
    #define SHAPE_KEY 41
    #define SHAPE_SANCTUM 42
    #define SHAPE_ASTROLABE 43
    #define SHAPE_WISP 44
    #define SHAPE_FLOURISH 45
    #define SHAPE_PARCHMENT 46
    #define SHAPE_MEDALLION 47
    #define SHAPE_GILDPATH 48
    #define SHAPE_PLINTH 49
    #define SHAPE_PLATE 50
    #define SHAPE_BEZEL 51
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
    #define ICON_KEY 25
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
    // In a level the flasks stand in the room itself, each on a ledge of its
    // own (Shape.Plinth), so each room is a whole picture from top to bottom:
    // a back wall and the room's landmark, the architecture around them, a
    // floor running away from the eye, and dark shapes close in front at the
    // edges, with the air thickening into the distance between. Each room is
    // painted back to front; then the backdrop's own pass calms and darkens
    // the middle, where the board stands (SHAPE_BACKDROP), so the brightest
    // things in a room keep to its edges and nothing in it outshines a flask.
    //
    // Everything moves slowly with time. The rare events (a moth, a falling
    // star, an ember burst) come round on long periods of their own, each
    // period's hash choosing where, so two of them seldom meet. The canvas
    // runs past 0..540 across on a wide window, so each room keeps going
    // sideways rather than stopping at the edges.

    #ifdef PROGRAM_ROOM
    float fbm(vec2 p) { return noise(p) * 0.62 + noise(p * 2.13 + 17.0) * 0.38; }
    // A painter's ground: long strokes on a slant and a fine tooth, so a flat
    // wall reads as brushed rather than printed.
    vec3 brushed(vec3 c, vec2 cv) {
        float stroke = noise(vec2(cv.x * 0.010 + cv.y * 0.018, cv.y * 0.06 - cv.x * 0.012));
        return c * (0.88 + 0.2 * stroke + 0.07 * noise(cv * 0.5));
    }
    float bricks(vec2 cv, vec2 size, float line) {
        vec2 b = vec2(cv.x / size.x + step(0.5, fract(cv.y / size.y * 0.5)) * 0.5, cv.y / size.y);
        vec2 f = abs(fract(b) - 0.5) * size;
        return clamp(smoothstep(size.x * 0.5 - line, size.x * 0.5, f.x) + smoothstep(size.y * 0.5 - line, size.y * 0.5, f.y), 0.0, 1.0);
    }
    // Which brick cv is in, as a number 0..1 to vary it by.
    float brick_id(vec2 cv, vec2 size) {
        return hash12(floor(vec2(cv.x / size.x + step(0.5, fract(cv.y / size.y * 0.5)) * 0.5, cv.y / size.y)));
    }
    // Planks running away from the eye: q is the floor's own coordinates.
    vec3 planks(vec2 q, vec3 wood, float width, float seed) {
        float k = floor(q.x / width);
        float u = q.x / width - k;
        float grain = noise(vec2(q.x * 0.09, q.y * 0.012 + k * 7.0 + seed)) * 0.55 +
                      noise(vec2(q.x * 0.4, q.y * 0.03 + k * 3.0)) * 0.3;
        vec3 c = wood * (0.72 + 0.5 * grain) * (0.9 + 0.2 * hash12(vec2(k, seed)));
        c *= 1.0 - 0.45 * (1.0 - smoothstep(0.0, 0.025, u)) - 0.25 * smoothstep(0.975, 1.0, u);
        float j = fract(q.y / 260.0 + hash12(vec2(k, 3.0 + seed)));
        c *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.006, abs(j - 0.5)));
        return c;
    }
    // The floor below the wall's foot at height `base`, seen from an eye 300
    // above it: x across and z away in floor units, and in .z how far off
    // the point is, 1 at the wall and less nearer.
    vec3 floor_at(vec2 cv, float base) {
        float d = max(cv.y - (base - 300.0), 1.0);
        return vec3((cv.x - 270.0) * 300.0 / d, 90000.0 / d, 300.0 / d);
    }
    // A round-headed arch: its springing line through p's origin, w half
    // wide, the jambs running h down from it.
    float sd_arch(vec2 p, float w, float h) {
        if (p.y < 0.0) return length(p) - w;
        return max(abs(p.x) - w, p.y - h);
    }
    // A pointed arch, the same, sharper as k grows past 1.
    float sd_pointed(vec2 p, float w, float h, float k) {
        if (p.y < 0.0) {
            float r = w * k;
            return max(length(p - vec2(r - w, 0.0)) - r, length(p + vec2(r - w, 0.0)) - r);
        }
        return max(abs(p.x) - w, p.y - h);
    }
    // A shaft of light from `from` along the unit vector dir, w wide there,
    // widening by `spread` a unit and fading out over len: 0..1.
    float shaft(vec2 cv, vec2 from, vec2 dir, float w, float spread, float len) {
        vec2 d = cv - from;
        float along = dot(d, dir);
        float across = abs(dot(d, vec2(-dir.y, dir.x)));
        float ww = w + max(along, 0.0) * spread;
        return (1.0 - smoothstep(ww * 0.3, ww, across)) * smoothstep(0.0, 80.0, along) *
               (1.0 - smoothstep(len * 0.25, len, along));
    }
    // Dust turning in the light: two drifts of specks at different depths,
    // the near one larger and slower to fall.
    float dust(vec2 cv, float t) {
        vec2 a = (cv + vec2(t * 4.0 + sin(t * 0.21) * 14.0, -t * 2.5)) / 17.0;
        vec2 b = (cv + vec2(-t * 2.0, t * 1.5 + sin(t * 0.17) * 9.0)) / 37.0 + 5.3;
        return speckle(a, t, 0.7, 0.10) + dots(b, 0.07) * 0.5;
    }
    // A circle of the Art, chalked or inlaid: three rings, a square and a
    // triangle turning within, and a band of n runes between the outer two.
    // The distance to its lines, lw wide; `rune` says which rune p is by
    // (0..n-1), or -1 away from the band.
    float sigil(vec2 p, float r, float turn, float n, float lw, out float rune) {
        float l = length(p);
        vec2 q = rot(turn) * p;
        float d = min(min(abs(l - r), abs(l - r * 0.84)), abs(l - r * 0.42));
        d = min(d, abs(sd_box(rot(0.7853982) * q, vec2(r * 0.594))));
        d = min(d, abs(sd_triangle(q, vec2(0.0, -r * 0.84), vec2(r * 0.7275, r * 0.42), vec2(-r * 0.7275, r * 0.42))));
        float a = atan(q.y, q.x) / 6.2831853 * n;
        float id = floor(a);
        vec2 rp = vec2((fract(a) - 0.5) * 6.2831853 * r * 0.92 / n, l - r * 0.92);
        float h = hash12(vec2(mod(id, n), 4.0));
        float s = r * 0.05;
        float g = sd_segment(rp, vec2(0.0, -s), vec2(0.0, s));
        if (h < 0.33) g = min(g, sd_segment(rp, vec2(-s * 0.7, -s * 0.2), vec2(s * 0.7, s * 0.5)));
        else if (h < 0.66) g = min(g, abs(length(rp - vec2(0.0, -s * 0.45)) - s * 0.45));
        else g = min(g, sd_segment(rp, vec2(-s * 0.7, s), vec2(0.0, s * 0.1)));
        rune = abs(l - r * 0.92) < r * 0.08 ? mod(id, n) : -1.0;
        return min(d, g) - lw;
    }
    // How lit rune i of n is while a light runs round the band, one rune a
    // `pace` seconds, leaving a fading trail.
    float rune_run(float i, float n, float t, float pace) {
        float k = mod(t / pace - i, n);
        return exp(-k * 0.6);
    }
    // The athanor's ember bursts, one every 19 seconds: 0..1, quick to
    // flare and slow to settle (draw_ember_burst throws up the embers).
    float ember_burst(float t) {
        float u = mod(t, 19.0);
        return u < 3.0 ? exp(-u * 1.6) * (1.0 - exp(-u * 12.0)) : 0.0;
    }
    // A row of jars on a shelf at height sy, one every `step` (a few gaps),
    // dim and various: the distance to them, their tint in `tint`.
    float jars(vec2 cv, float sy, float step, float seed, out vec3 tint) {
        float jx = floor(cv.x / step);
        float hj = hash12(vec2(jx, seed));
        float jh = step * (0.5 + hj * 0.7);
        float jw = step * (0.2 + 0.14 * hash12(vec2(jx, seed + 2.0)));
        vec2 jp = vec2(mod(cv.x, step) - step * 0.5, cv.y - (sy - jh * 0.5));
        float body = hj > 0.7 ? sd_circle(jp - vec2(0.0, jh * 0.5 - jw * 1.15), jw * 1.15)
                              : sd_round_box(jp, vec2(jw, jh * 0.5), vec4(jw * 0.45));
        float neck = sd_box(jp + vec2(0.0, jh * 0.5 + 2.0), vec2(jw * 0.42, 4.0));
        tint = mix(vec3(0.45, 0.25, 0.14), vec3(0.20, 0.34, 0.26), hash12(vec2(jx, seed + 9.0)));
        tint = mix(tint, vec3(0.32, 0.18, 0.34), step(0.8, hash12(vec2(jx, seed + 5.0))));
        return hj < 0.12 ? 1e3 : min(body, neck);
    }
    // Jars standing on a shelf: a glass body in its tint, a highlight down
    // the side the light comes from, and a glint now and then.
    vec3 jar_row(vec3 c, vec2 cv, float sy, float step, float seed, float from, float t) {
        vec3 tint;
        float jar = jars(cv, sy, step, seed, tint);
        if (jar > 3.0) return c;
        float u = fract(cv.x / step) - 0.5;
        vec3 g = tint * (0.42 + 0.25 * smoothstep(0.3, -0.3, u * from));
        g += vec3(0.55, 0.45, 0.3) * fill_aa(abs(u * step + from * step * 0.12) - 1.0) * 0.25;
        float tw = pow(max(0.0, sin(t * 0.4 + hash12(vec2(floor(cv.x / step), seed)) * 40.0)), 30.0);
        g += vec3(1.0, 0.9, 0.7) * tw * 0.4 * fill_aa(length(vec2(u * step + from * step * 0.12, cv.y - sy + step * 0.5)) - 2.0);
        return mix(c, g, fill_aa(jar) * 0.9);
    }
    // A shelf's plank at height sy between x0 and x1, its shadow under it.
    vec3 shelf(vec3 c, vec2 cv, float sy, float x0, float x1) {
        float across = max(x0 - cv.x, cv.x - x1);
        c = mix(c, c * 0.45, fill_aa(max(abs(cv.y - sy - 14.0) - 6.0, across)) * 0.6);
        vec3 wood = vec3(0.30, 0.18, 0.10) * (0.85 + 0.3 * noise(cv * vec2(0.08, 0.5)));
        wood += vec3(0.12, 0.07, 0.03) * (1.0 - smoothstep(0.0, 2.0, cv.y - sy));
        return mix(c, wood, fill_aa(max(abs(cv.y - sy - 4.0) - 4.0, across)));
    }
    // A link chain hanging from the top at x down to y1, swaying with phase.
    float chain(vec2 cv, float x, float y1, float phase, float t) {
        float sway = sin(t * 0.4 + phase) * 0.012 * cv.y;
        vec2 q = vec2(cv.x - x - sway, cv.y);
        float k = floor(q.y / 14.0);
        vec2 l = vec2(q.x, mod(q.y, 14.0) - 7.0);
        float link = mod(k, 2.0) < 1.0 ? abs(length(l / vec2(4.0, 8.0)) - 1.0) * 4.0 - 1.1 : abs(l.x) - 1.3;
        return max(link, cv.y - y1);
    }
    // Leaves: a cluster of broad pointed leaves around `at`, swaying; the
    // distance to them.
    float leaves(vec2 cv, vec2 at, float size, float seed, float t) {
        float d = 1e3;
        for (int i = 0; i < 4; i++) {
            float fi = float(i);
            float a = seed + fi * 1.7 + sin(t * 0.35 + fi + seed) * 0.08;
            vec2 q = rot(a) * (cv - at);
            float len = size * (0.7 + 0.5 * hash12(vec2(fi, seed)));
            q.x -= len * 0.55;
            float w = len * 0.28 * (1.0 - pow(abs(q.x) / (len * 0.55), 2.0));
            d = min(d, max(abs(q.y) - w, abs(q.x) - len * 0.55));
        }
        return d;
    }

    #if ROOM == 0
    vec3 room_apothecary(vec2 cv, float t) {
        float f = light.a;
        float base = 780.0;
        // Warm plaster, the brick showing where it has fallen away.
        vec3 c = mix(vec3(0.09, 0.05, 0.07), vec3(0.23, 0.13, 0.10), smoothstep(-50.0, base, cv.y));
        float bare = smoothstep(0.56, 0.62, fbm(cv * 0.007 + 3.0));
        c *= 1.0 - bare * (0.12 + 0.2 * bricks(cv, vec2(56.0, 26.0), 2.0));
        c = brushed(c, cv);
        // Tall niches either side, shelves of jars up them; their shadows
        // lean as the candles flicker.
        float side = cv.x < 270.0 ? 1.0 : -1.0;
        float nx = 270.0 - side * 205.0;
        vec2 np = vec2(cv.x - nx, cv.y - 150.0);
        float niche = sd_arch(np, 70.0, base - 160.0);
        if (niche < 8.0) {
            vec3 back = c * mix(0.35, 0.65, smoothstep(-70.0, 600.0, np.y));
            c = mix(c, back, fill_aa(niche));
            // Rim light down the niche's inner edge, from the room's middle.
            c += vec3(0.5, 0.33, 0.18) * fill_aa(abs(niche + 2.0) - 1.5) * 0.25 * smoothstep(0.0, 1.0, -np.x * side / 70.0 + 0.5);
            vec2 sway = vec2(side * (4.0 + 3.0 * f), -4.0 - 2.0 * f);
            for (int s = 0; s < 6; s++) {
                float sy = 205.0 + float(s) * 92.0;
                vec3 tint;
                float sh = jars(cv - sway, sy, 26.0, float(s) + side * 3.0, tint);
                c = mix(c, c * 0.55, fill_aa(sh - 2.0) * 0.6 * fill_aa(niche));
                c = jar_row(c, cv, sy, 26.0, float(s) + side * 3.0, side, t);
                c = shelf(c, cv, sy, nx - 70.0, nx + 70.0);
            }
            c = mix(c, c * 0.5, (1.0 - fill_aa(niche + 4.0)) * fill_aa(niche + 0.0));
        }
        // The rose window high in the middle: six petals of leaded glass,
        // dusk outside, and its shaft of light falling across the room.
        vec2 wp = cv - vec2(270.0, 112.0);
        float wr = length(wp);
        float win = wr - 64.0;
        float sector = 1.0471976;
        float pa = atan(wp.y, wp.x);
        float pid = floor((pa + sector * 0.5) / sector);
        float ang = pa - pid * sector;
        vec2 pp = wr * vec2(cos(ang), sin(ang));
        float lead = min(min(abs(wr - 20.0), abs(length(pp - vec2(42.0, 0.0)) - 20.0)), abs(pp.y) + step(wr, 20.0) * 99.0) - 1.6;
        vec3 glass = mix(vec3(0.62, 0.34, 0.22), vec3(0.36, 0.22, 0.42), hash12(vec2(pid, 2.0)));
        glass = mix(glass, vec3(0.75, 0.55, 0.3), step(wr, 20.0));
        glass *= 0.3 + 0.16 * smoothstep(-64.0, 64.0, wp.y) + 0.08 * noise(wp * 0.08) + 0.05 * sin(t * 0.3 + pid);
        c = mix(c, vec3(0.06, 0.04, 0.05), fill_aa(win - 10.0));
        c = mix(c, vec3(0.30, 0.20, 0.15) * (0.8 + 0.3 * noise(wp * 0.2)), fill_aa(abs(win - 5.0) - 4.0));
        c = mix(c, glass, fill_aa(win) * fill_aa(-lead));
        c += vec3(0.5, 0.32, 0.2) * exp(-max(win, 0.0) / 50.0) * 0.07;
        float sh = shaft(cv, vec2(250.0, 130.0), normalize(vec2(0.42, 1.0)), 52.0, 0.3, 900.0) * step(0.0, win);
        float haze = 0.8 + 0.4 * noise(vec2(cv.x * 0.01 - t * 0.03, cv.y * 0.004));
        c += vec3(0.9, 0.62, 0.38) * sh * 0.07 * haze;
        c += vec3(1.0, 0.85, 0.6) * dust(cv, t) * sh * 0.3;
        // A circle of the Art chalked on the wall, turning so slowly you only
        // notice it has moved; a light runs round its runes.
        float rune;
        float sg = sigil(cv - vec2(270.0, 460.0), 170.0, t * 0.012, 24.0, 0.8, rune);
        c += vec3(0.75, 0.62, 0.48) * fill_aa(sg) * 0.07;
        if (rune >= 0.0) c += vec3(1.0, 0.7, 0.35) * fill_aa(sg) * 0.3 * rune_run(rune, 24.0, t, 1.6);
        // The floor: old boards going away, the candlelight lying on them.
        if (cv.y > base) {
            vec3 fl = floor_at(cv, base);
            vec3 boards = planks(fl.xy, vec3(0.30, 0.17, 0.09), 90.0, 0.0);
            boards *= 0.55 + 0.45 * (1.0 - fl.z);
            boards += light.rgb * 0.12 * exp(-abs(fl.x) / 260.0) * (0.8 + 0.2 * f) * (1.0 - fl.z * 0.5);
            boards += vec3(0.6, 0.4, 0.25) * sh * 0.08;
            c = boards;
            c = mix(c, vec3(0.05, 0.03, 0.03), 1.0 - smoothstep(0.0, 10.0, cv.y - base));
        }
        c = mix(c, vec3(0.30, 0.18, 0.10), fill_aa(abs(cv.y - base + 8.0) - 5.0));      // the skirting
        // Close in front: bunches of herbs hanging at the top corners, soft
        // and dark, turning a little in the draught.
        for (int i = 0; i < 2; i++) {
            float hx = i == 0 ? 18.0 : 524.0;
            vec2 hp = rot(sin(t * 0.3 + float(i) * 2.0) * 0.05) * (cv - vec2(hx, -10.0));
            float string = sd_segment(hp, vec2(0.0, 0.0), vec2(0.0, 70.0)) - 1.2;
            float bunch = sd_triangle(hp, vec2(0.0, 60.0), vec2(-34.0, 200.0), vec2(34.0, 200.0)) + 8.0 * noise(hp * 0.12);
            float d = min(string, bunch);
            vec3 herb = mix(vec3(0.03, 0.03, 0.015), vec3(0.08, 0.07, 0.03), noise(hp * vec2(0.3, 0.06)));
            herb += vec3(0.25, 0.15, 0.06) * smoothstep(-6.0, 0.0, bunch) * 0.4;    // rim light
            c = mix(c, herb, smoothstep(3.0, -3.0, d));
        }
        // Now and then a moth comes in at the window and crosses the room.
        float period = 37.0;
        float n = floor(t / period);
        float u = (t - n * period) / 9.0;
        if (u < 1.0) {
            float hy = hash12(vec2(n, 7.0));
            float dir = hy > 0.5 ? 1.0 : -1.0;
            vec2 mp = vec2(270.0 + dir * (u - 0.5) * 680.0, 150.0 + hy * 200.0 + sin(u * 19.0) * 26.0 + u * 60.0);
            vec2 m = (cv - mp) / 1.7;
            if (dot(m, m) < 400.0) {
                float flap = 0.35 + 0.65 * abs(sin(t * 23.0));
                vec2 wq = vec2(abs(m.x) / flap, m.y);
                float wing = length((wq - vec2(5.0, -1.0)) / vec2(5.5, 4.0)) - 1.0;
                float body = length(m / vec2(1.4, 4.0)) - 1.0;
                float d = min(wing, body) * 4.0;
                c = mix(c, vec3(0.16, 0.12, 0.10), fill_aa(d) * 0.9);
                c += vec3(0.6, 0.42, 0.25) * fill_aa(abs(d + 1.0) - 0.7) * 0.25 * flap;
            }
        }
        return c;
    }
    #endif

    // The frost cellar: a vaulted passage running away from the eye, rib
    // after rib, to a grate with the moon in it. Every surface (vault,
    // walls, floor) is found from the eye by its depth s (1 near, smaller
    // farther), so the ribs and the stones fall in perspective of themselves.
    #if ROOM == 1
    vec3 room_frost(vec2 cv, float t) {
        vec2 v = vec2(270.0, 430.0);            // where the passage vanishes
        vec2 p = cv - v;
        float W = 330.0;                        // the passage's half width, near
        float S = 260.0;                        // the vault's springing, above the eye
        float F = 560.0;                        // the floor, below it
        float s_wall = abs(p.x) / W;
        float s_floor = p.y / F;
        float pp = dot(p, p);
        float s_vault = (520.0 * p.y + sqrt(270400.0 * p.y * p.y + 165200.0 * pp)) / 82600.0;
        float s; vec2 uv; int surf;
        if (p.y > 0.0 && s_floor > s_wall) { s = s_floor; uv = vec2(p.x / s, 1.0 / s); surf = 0; }
        else if (p.y < -S * s_wall) { s = s_vault; uv = vec2(atan(p.y + S * s, p.x) * W, 1.0 / s); surf = 2; }
        else { s = s_wall; uv = vec2(p.y / s, 1.0 / s); surf = 1; }
        float z = 1.0 / max(s, 0.001);
        float end = 4.6;                        // the far wall, where the grate is
        vec3 c;
        vec3 moon = vec3(0.45, 0.6, 0.85);
        if (z > end) {
            // The far wall, the grate in it, moonlight pouring through.
            vec2 q = p * end;
            vec2 gp = p - vec2(0.0, -40.0);
            float grate = sd_round_box(gp, vec2(30.0, 22.0), vec4(10.0, 2.0, 10.0, 2.0));
            c = vec3(0.07, 0.09, 0.14) * (1.0 - 0.3 * bricks(q, vec2(110.0, 70.0), 4.0));
            vec3 night = mix(vec3(0.25, 0.34, 0.5), vec3(0.55, 0.65, 0.8), smoothstep(20.0, -20.0, gp.y + gp.x * 0.3));
            night = mix(night, vec3(0.04, 0.05, 0.08), fill_aa(abs(mod(gp.x + 5.0, 10.0) - 5.0) - 1.2));
            c = mix(c, night, fill_aa(grate));
        } else {
            vec2 g = surf == 0 ? vec2(uv.x, uv.y * 120.0) : vec2(uv.y * 120.0, uv.x);
            vec2 size = surf == 0 ? vec2(130.0, 90.0) : vec2(100.0, 64.0);
            float m = bricks(g, size, 3.0 * z);
            float id = brick_id(g, size);
            vec3 stone = vec3(0.085, 0.11, 0.16) * (0.8 + 0.3 * id) * (1.0 - 0.45 * m);
            if (surf == 0) stone *= 0.8;
            if (surf == 2) stone *= 0.85;
            // Racks of bottles laid down along the walls, their ends catching the light.
            if (surf == 1 && uv.x > -200.0 && uv.x < 230.0) {
                vec2 r = vec2(mod(uv.y * 120.0, 34.0) - 17.0, mod(uv.x, 30.0) - 15.0);
                float bottle = length(r) - 11.0;
                float bay = step(0.3, fract(uv.y * 120.0 / 220.0));
                vec3 glass = mix(vec3(0.05, 0.06, 0.08), vec3(0.06, 0.08, 0.08), hash12(floor(vec2(uv.y * 120.0 / 34.0, uv.x / 30.0))));
                vec3 rack = mix(stone * 0.3, glass, fill_aa(bottle * s));
                rack += vec3(0.5, 0.65, 0.8) * fill_aa((length(r - vec2(-3.0, -4.0)) - 2.5) * s) * 0.2;
                stone = mix(stone, rack, bay);
            }
            // The ribs: an arch every 0.55 of depth, its stone a little paler.
            float rk = (z - 1.0) / 0.55;
            float rib = abs(fract(rk + 0.5) - 0.5) * 0.55;
            float ribw = 0.06;
            float px = W * s * s;                  // pixels per unit of depth here
            stone = mix(stone, vec3(0.12, 0.15, 0.21) * (0.9 + 0.2 * noise(uv * 0.05)), fill_aa((rib - ribw) * px));
            stone += vec3(0.25, 0.32, 0.42) * fill_aa(abs(rib - ribw) * px - 0.8) * 0.15;
            c = stone;
            // Moonlight from the grate along the floor and up the walls.
            float lit = exp(-abs(z - end) * 0.9) * (surf == 0 ? exp(-abs(uv.x) / 160.0) : 0.6);
            c += moon * lit * 0.08;
            // Rime: thick where the passage is near, creeping and receding, glinting.
            vec2 rq = uv * vec2(0.012, 1.4);
            float creep = 0.06 * sin(t * 0.07) + 0.03 * sin(t * 0.19 + 1.0);
            float rime = smoothstep(0.58, 0.7, fbm(rq + vec2(0.0, float(surf) * 7.0)) * 0.6 + (1.0 - smoothstep(1.0, 2.6, z)) * 0.35 + creep);
            float fern = noise(rq * vec2(6.0, 2.0) + noise(rq * 3.0) * 2.0);
            c = mix(c, vec3(0.36, 0.46, 0.6) * (0.6 + 0.5 * fern), rime * 0.25);
            float sweep = mod(t, 23.0) * 160.0 - 400.0;
            float glint = exp(-pow((cv.x + cv.y * 0.6 - sweep) / 50.0, 2.0));
            c += vec3(0.85, 0.93, 1.0) * rime * (speckle(cv / 9.0, t, 1.3, 0.1) * (0.3 + 1.5 * glint) + glint * 0.06);
        }
        // The cold air thickens down the passage.
        float fogk = smoothstep(1.0, end, z);
        c = mix(c, vec3(0.07, 0.10, 0.16), fogk * 0.65);
        c += moon * exp(-length(p - vec2(0.0, -40.0)) / 90.0) * 0.12;
        // The moon's shaft coming down the passage, dust in it.
        float sh = shaft(cv, v + vec2(0.0, -40.0), normalize(vec2(0.0, 1.0)), 30.0, 0.35, 900.0);
        c += moon * sh * (0.05 + 0.02 * noise(vec2(cv.x * 0.01, t * 0.1)));
        c += vec3(0.8, 0.9, 1.0) * dust(cv, t * 0.6) * sh * 0.18;
        // Cold mist low over the floor, drifting.
        float mist = noise(vec2(cv.x * 0.005 + t * 0.02, cv.y * 0.01 - t * 0.01)) * smoothstep(600.0, 960.0, cv.y);
        c += vec3(0.3, 0.38, 0.5) * mist * 0.16;
        // Close in front: icicles hanging from the nearest rib, out of focus.
        float col = floor(cv.x / 26.0);
        float len = 20.0 + hash12(vec2(col, 3.0)) * 60.0;
        float ix = abs(mod(cv.x, 26.0) - 13.0);
        float icicle = ix - 9.0 * (1.0 - cv.y / len);
        if (hash12(vec2(col, 5.0)) > 0.35) {
            float a = smoothstep(2.0, -2.0, icicle) * (1.0 - cv.y / len * 0.6);
            c = mix(c, vec3(0.22, 0.30, 0.40), a * 0.8);
            c += vec3(0.6, 0.75, 0.9) * smoothstep(1.5, 0.0, abs(mod(cv.x, 26.0) - 10.0)) * a * 0.25;
        }
        return c;
    }
    #endif

    #if ROOM == 2
    vec3 room_glassworks(vec2 cv, float t) {
        float f = light.a;
        float base = 770.0;
        // The kiln breathes: a slow swell with the flicker on top.
        float breath = 0.82 + 0.12 * sin(t * 0.55) + 0.06 * f;
        // Over the kiln the air shimmers, and the wall with it.
        vec2 kp = cv - vec2(270.0, 200.0);
        float above = smoothstep(40.0, -40.0, kp.y + 160.0) * (1.0 - smoothstep(40.0, 140.0, abs(kp.x)));
        vec2 w = cv + vec2(noise(vec2(cv.x * 0.05, cv.y * 0.03 + t * 1.4)) - 0.5, 0.0) * 9.0 * above;
        vec3 c = mix(vec3(0.09, 0.045, 0.045), vec3(0.20, 0.09, 0.065), smoothstep(0.0, base, cv.y));
        float m = bricks(w, vec2(48.0, 22.0), 1.6);
        c *= (1.0 - 0.32 * m) * (0.82 + 0.28 * brick_id(w, vec2(48.0, 22.0)));
        c = brushed(c, cv);
        // The firelight warms the wall round the kiln.
        c += vec3(0.4, 0.15, 0.04) * exp(-length(kp * vec2(0.8, 1.0)) / 220.0) * 0.25 * breath;
        // The kiln: a beehive dome of firebrick, its mouth burning, two
        // glory holes either side.
        float dome = sd_arch(kp, 150.0, base - 200.0);
        float rows = abs(fract(length(kp) / 18.0) - 0.5);
        vec3 fire_brick = vec3(0.22, 0.10, 0.065) * (0.8 + 0.3 * noise(kp * 0.1));
        fire_brick *= 1.0 - 0.35 * smoothstep(0.42, 0.5, rows) * step(kp.y, 0.0);
        fire_brick *= 1.0 - 0.3 * bricks(cv, vec2(36.0, 18.0), 1.4) * step(0.0, kp.y);
        fire_brick += vec3(0.6, 0.25, 0.06) * exp(-length(kp - vec2(0.0, 20.0)) / 80.0) * 0.3 * breath;
        // Rim light round the dome, from the furnace below.
        fire_brick += vec3(0.7, 0.3, 0.08) * fill_aa(abs(dome + 3.0) - 2.5) * 0.25 * smoothstep(-150.0, 50.0, kp.y);
        c = mix(c, fire_brick, fill_aa(dome));
        c = mix(c, vec3(0.05, 0.03, 0.03), fill_aa(abs(dome) - 2.0) * 0.7);
        vec2 mp = kp - vec2(0.0, 20.0);
        float mouth = sd_arch(mp, 52.0, 36.0);
        float heat = noise(vec2(mp.x * 0.06, mp.y * 0.05 + t * 1.8));
        vec3 fire = mix(vec3(1.0, 0.72, 0.32), vec3(0.75, 0.25, 0.06), smoothstep(-50.0, 36.0, mp.y + heat * 30.0));
        c = mix(c, fire * 0.55 * breath, fill_aa(mouth));
        c = mix(c, vec3(0.30, 0.15, 0.09), fill_aa(abs(mouth - 4.0) - 4.0));
        for (int i = 0; i < 2; i++) {
            vec2 hp = kp - vec2(i == 0 ? -98.0 : 98.0, 0.0);
            float hole = length(hp) - 13.0;
            c = mix(c, vec3(0.95, 0.55, 0.18) * 0.5 * (breath + 0.1 * sin(t * 1.3 + float(i) * 2.0)), fill_aa(hole));
            c = mix(c, vec3(0.30, 0.15, 0.09), fill_aa(abs(hole - 3.0) - 3.0));
        }
        c += vec3(0.6, 0.24, 0.06) * exp(-max(mouth, 0.0) / 60.0) * 0.16 * breath * step(0.0, mouth);
        // The flue up from the dome's crown.
        float flue = max(abs(cv.x - 270.0) - 24.0, cv.y - 55.0);
        c = mix(c, vec3(0.12, 0.06, 0.05) * (0.8 + 0.4 * noise(cv * vec2(0.3, 0.05))), fill_aa(flue));
        // Racks of finished glass up both walls, their shoulders catching the fire.
        float side = cv.x < 270.0 ? 1.0 : -1.0;
        float rx = 270.0 - side * 222.0;
        if (abs(cv.x - rx) < 70.0) {
            for (int s = 0; s < 6; s++) {
                float sy = 170.0 + float(s) * 96.0;
                c = jar_row(c, cv, sy, 30.0, float(s) + 20.0 + side, side, t);
                c += vec3(1.0, 0.55, 0.2) * 0.08 * breath * fill_aa(abs(cv.y - sy + 18.0) - 16.0) * smoothstep(70.0, 0.0, abs(cv.x - rx)) * 0.4;
                c = shelf(c, cv, sy, rx - 66.0, rx + 66.0);
            }
        }
        // Glass tubes along the wall, the melt flowing in them.
        float tube = abs(cv.y - 128.0) - 6.0;
        if (abs(cv.x - 270.0) < 160.0) tube = 1e3;
        float flow = 0.5 + 0.5 * sin((cv.x - cv.y) * 0.05 - t * 1.2);
        c = mix(c, vec3(0.9, 0.55, 0.15) * (0.3 + 0.15 * flow), fill_aa(tube) * 0.7);
        c = mix(c, vec3(0.7, 0.75, 0.8), fill_aa(abs(tube + 1.5) - 1.0) * 0.3);
        // The floor: firebrick laid flat, the kiln's light pooling on it.
        if (cv.y > base) {
            vec3 fl = floor_at(cv, base);
            vec2 g = fl.xy * vec2(1.0, 1.0);
            float fm = bricks(g, vec2(70.0, 36.0), 2.5 / fl.z);
            vec3 fc = vec3(0.17, 0.08, 0.055) * (0.75 + 0.4 * brick_id(g, vec2(70.0, 36.0))) * (1.0 - 0.5 * fm);
            fc *= 0.6 + 0.4 * (1.0 - fl.z);
            fc += vec3(0.5, 0.2, 0.05) * exp(-abs(fl.x) / 200.0) * fl.z * 0.25 * breath;
            c = mix(vec3(0.04, 0.02, 0.02), fc, smoothstep(0.0, 10.0, cv.y - base));
        }
        // Close in front: chains hanging at the edges, and a blowpipe on a hook.
        float ch = min(chain(cv, 14.0, 520.0, 0.0, t), chain(cv, 528.0, 430.0, 2.0, t));
        c = mix(c, vec3(0.05, 0.035, 0.03), fill_aa(ch));
        c += vec3(0.6, 0.3, 0.1) * fill_aa(abs(ch + 1.0) - 0.6) * 0.15;
        return c;
    }
    #endif

    #if ROOM == 3
    vec3 room_observatory(vec2 cv, float t) {
        float base = 760.0;
        vec3 wall = mix(vec3(0.06, 0.045, 0.09), vec3(0.15, 0.10, 0.12), smoothstep(0.0, base, cv.y));
        wall *= 0.85 + 0.25 * noise(vec2(cv.x * 0.05, cv.y * 0.004));
        wall = brushed(wall, cv);
        // The dome's ribs curving down to the wall's top.
        float ribs = abs(mod(atan(cv.y + 400.0, cv.x - 270.0) * 9.0, 1.0) - 0.5);
        wall *= 1.0 - 0.25 * smoothstep(0.43, 0.5, ribs) * smoothstep(80.0, 0.0, cv.y);
        // A tall arched window onto the night sky.
        vec2 wp = cv - vec2(270.0, 330.0);
        float win = sd_round_box(wp, vec2(235.0, 330.0), vec4(235.0, 0.0, 235.0, 0.0));
        vec3 c = wall;
        if (win < 6.0) {
            vec3 sky = mix(vec3(0.02, 0.03, 0.10), vec3(0.08, 0.09, 0.22), smoothstep(30.0, 660.0, cv.y));
            sky += vec3(0.12, 0.07, 0.18) * smoothstep(0.5, 0.85, fbm(cv * 0.006 + vec2(3.0, 1.0))) * 0.5;
            // The Milky Way, a faint band of haze and fine stars.
            float band = exp(-pow((cv.y - cv.x * 0.7 - 120.0) / 90.0, 2.0));
            sky += vec3(0.2, 0.18, 0.3) * band * fbm(cv * 0.02) * 0.35;
            // An aurora's curtains, slowly folding.
            float ay = 190.0 + 70.0 * noise(vec2(cv.x * 0.004 + t * 0.015, 1.0)) + 26.0 * sin(cv.x * 0.012 + t * 0.09);
            float curtain = exp(-pow((cv.y - ay) / 46.0, 2.0)) * (cv.y < ay ? 1.0 : 0.6);
            float folds = 0.45 + 0.55 * noise(vec2(cv.x * 0.045 + t * 0.06, cv.y * 0.004));
            vec3 aur = mix(vec3(0.15, 0.75, 0.55), vec3(0.5, 0.3, 0.8), smoothstep(ay + 20.0, ay - 70.0, cv.y));
            sky += aur * curtain * folds * (0.13 + 0.05 * sin(t * 0.2));
            // The stars, wheeling about the pole very slowly.
            vec2 sp = rot(t * 0.004) * (cv - vec2(330.0, 90.0));
            float stars = speckle(sp / 26.0, t, 0.8, 0.09) * 0.8 + dots(sp / 17.0 + 3.3, 0.06) * (0.35 + 0.5 * band);
            sky += vec3(0.85, 0.88, 1.0) * stars;
            // A constellation, faintly joined: the Swan.
            vec2 a0 = vec2(150.0, 120.0), a1 = vec2(190.0, 175.0), a2 = vec2(222.0, 228.0), a3 = vec2(268.0, 290.0);
            vec2 b0 = vec2(128.0, 238.0), b1 = vec2(300.0, 205.0);
            float lines = min(min(sd_segment(cv, a0, a1), sd_segment(cv, a1, a2)), min(sd_segment(cv, a2, a3), min(sd_segment(cv, b0, a2), sd_segment(cv, a2, b1))));
            sky += vec3(0.5, 0.6, 0.9) * fill_aa(lines - 0.5) * 0.12;
            float knots = min(min(length(cv - a0), length(cv - a1)), min(min(length(cv - a2), length(cv - a3)), min(length(cv - b0), length(cv - b1))));
            sky += vec3(0.9, 0.92, 1.0) * (fill_aa(knots - 1.8) * 0.7 + exp(-knots / 5.0) * 0.25);
            // The moon, a halo round it.
            vec2 mp = cv - vec2(400.0, 150.0);
            float moon = max(length(mp) - 34.0, -(length(mp - vec2(-14.0, -8.0)) - 30.0));
            sky = mix(sky, vec3(0.92, 0.9, 0.8) * (0.9 + 0.1 * noise(mp * 0.2)), fill_aa(moon));
            sky += vec3(0.2, 0.2, 0.3) * exp(-length(mp) / 70.0) * 0.5;
            // A star falls now and then.
            float period = 23.0;
            float n = floor(t / period);
            float u = (t - n * period) / 1.1;
            if (u < 1.0) {
                vec2 s0 = vec2(80.0 + hash12(vec2(n, 1.0)) * 380.0, 60.0 + hash12(vec2(n, 2.0)) * 150.0);
                vec2 dir = normalize(vec2(hash12(vec2(n, 3.0)) > 0.5 ? 1.0 : -1.0, 0.55));
                vec2 head = s0 + dir * u * 260.0;
                vec2 tail = head - dir * 90.0 * min(u * 3.0, 1.0);
                vec2 st = sd_bezier(cv, tail, (tail + head) * 0.5 + vec2(0.0, 0.01), head);
                float fade = sin(u * 3.14159);
                sky += vec3(0.9, 0.95, 1.0) * fill_aa(st.x - 0.9 * st.y) * st.y * fade;
                sky += vec3(0.6, 0.7, 1.0) * exp(-length(cv - head) / 7.0) * fade * 0.6;
            }
            // Hills far off on the horizon.
            float hill = cv.y - (600.0 + 30.0 * noise(vec2(cv.x * 0.01, 2.0)) + 15.0 * noise(vec2(cv.x * 0.04, 5.0)));
            sky = mix(sky, vec3(0.03, 0.035, 0.07), fill_aa(-hill));
            c = mix(wall, sky, fill_aa(win));
            // Brass: the window frame and its bars, a glint running up them.
            float frame = abs(win) - 4.0;
            float bars = max(min(abs(wp.x) - 2.0, abs(wp.y - 40.0) - 2.0), win);
            float glint = exp(-pow((cv.y - mod(t * 30.0, 1400.0) + 200.0) / 30.0, 2.0));
            c = mix(c, vec3(0.62, 0.48, 0.25) * (0.8 + 0.2 * sin(cv.y * 0.05) + glint), fill_aa(min(frame, bars)));
        }
        // The great telescope across the window, on its mount: a dark tube
        // with brass bands, its eye end low on the left.
        vec2 tp = rot(-0.62) * (cv - vec2(130.0, 420.0));
        float tw = mix(14.0, 22.0, clamp((tp.x + 170.0) / 360.0, 0.0, 1.0));
        float tube = max(abs(tp.y) - tw, abs(tp.x - 10.0) - 180.0);
        float bands = step(abs(mod(tp.x + 20.0, 110.0) - 55.0), 5.0) + step(abs(tp.x - 190.0), 8.0);
        vec3 tc = mix(vec3(0.06, 0.05, 0.08), vec3(0.42, 0.32, 0.17), clamp(bands, 0.0, 1.0));
        tc *= 0.75 + 0.5 * smoothstep(tw, -tw, tp.y);
        tc += vec3(0.4, 0.45, 0.6) * fill_aa(abs(tp.y + tw - 2.0) - 1.0) * 0.25;           // moonlight along its top
        c = mix(c, tc, fill_aa(tube));
        float post = sd_segment(cv, vec2(130.0, 420.0), vec2(120.0, base - 20.0)) - 7.0;
        post = min(post, sd_segment(cv, vec2(125.0, 660.0), vec2(65.0, base + 30.0)) - 4.0);
        post = min(post, sd_segment(cv, vec2(125.0, 660.0), vec2(185.0, base + 30.0)) - 4.0);
        c = mix(c, vec3(0.08, 0.06, 0.07), fill_aa(post));
        c = mix(c, vec3(0.5, 0.38, 0.2), fill_aa(length(cv - vec2(130.0, 420.0)) - 10.0));
        // An armillary sphere on its stand on the right, its rings slowly turning.
        vec2 ap = cv - vec2(440.0, 600.0);
        float ring = abs(length(ap) - 52.0) - 1.6;
        float tilt = sin(t * 0.15);
        ring = min(ring, abs(length(ap * vec2(1.0, 1.0 / max(abs(tilt), 0.08))) - 52.0) * max(abs(tilt), 0.08) - 1.4);
        ring = min(ring, abs(length(ap * vec2(1.0 / max(abs(cos(t * 0.1)), 0.08), 1.0)) - 52.0) * max(abs(cos(t * 0.1)), 0.08) - 1.4);
        ring = min(ring, abs(length(rot(0.41) * ap * vec2(1.0, 3.2)) - 52.0) / 3.2 - 1.6);
        ring = min(ring, max(abs(ap.x) - 3.0, abs(ap.y - 110.0) - 56.0));
        ring = min(ring, sd_round_box(ap - vec2(0.0, 166.0), vec2(30.0, 5.0), vec4(3.0)));
        c = mix(c, vec3(0.62, 0.46, 0.22) * 0.8, fill_aa(ring) * 0.85);
        c = mix(c, vec3(0.8, 0.62, 0.3), fill_aa(length(ap) - 5.0));
        // The floor: dark boards, a brass circle inlaid, moonlight on it.
        if (cv.y > base) {
            vec3 fl = floor_at(cv, base);
            vec3 boards = planks(fl.xy, vec3(0.16, 0.09, 0.08), 110.0, 5.0);
            boards *= 0.6 + 0.4 * (1.0 - fl.z);
            float r = length(fl.xy - vec2(0.0, 250.0));
            float inlay = min(abs(r - 160.0), abs(r - 140.0));
            float spokes = abs(mod(atan(fl.y - 250.0, fl.x) * 8.0 / 3.14159, 1.0) - 0.5) * r * 0.39;
            inlay = min(inlay, max(spokes, abs(r - 80.0) - 60.0));
            boards = mix(boards, vec3(0.6, 0.45, 0.22) * 0.7, fill_aa((inlay - 2.0) * fl.z * 0.7) * 0.8);
            float lit = (1.0 - smoothstep(-30.0, 20.0, sd_round_box(fl.xy - vec2(60.0 + 10.0 * sin(t * 0.013), 120.0), vec2(170.0, 200.0), vec4(0.0))));
            boards += vec3(0.25, 0.3, 0.5) * lit * 0.12;
            c = mix(vec3(0.03, 0.02, 0.04), boards, smoothstep(0.0, 10.0, cv.y - base));
        }
        // Moonlight from the window, cool, lying across the room.
        float sh = shaft(cv, vec2(330.0, 200.0), normalize(vec2(-0.25, 1.0)), 120.0, 0.2, 1000.0);
        c += vec3(0.45, 0.5, 0.8) * sh * 0.05;
        c += vec3(0.8, 0.85, 1.0) * dust(cv, t * 0.5) * sh * 0.18;
        // Close in front: heavy velvet curtains drawn back at the sides, swaying.
        float cx = abs(cv.x - 270.0);
        float edge = 236.0 + 26.0 * smoothstep(100.0, 600.0, cv.y) - 30.0 * smoothstep(600.0, 760.0, cv.y) + 4.0 * sin(t * 0.3 + cv.y * 0.01);
        float drape = edge - cx;
        float folds = 0.5 + 0.5 * sin((cx - edge) * 0.16 + sin(cv.y * 0.01 + t * 0.25) * 1.2);
        vec3 velvet = vec3(0.10, 0.05, 0.14) * (0.45 + 0.75 * folds);
        velvet += vec3(0.35, 0.3, 0.55) * fill_aa(abs(drape) - 1.5) * 0.25;                // rim
        c = mix(c, velvet, smoothstep(1.0, -2.0, drape));
        // A gold tieback holding each one.
        c = mix(c, vec3(0.55, 0.42, 0.2), fill_aa(length(vec2(cx - edge - 10.0, cv.y - 560.0) * vec2(0.5, 1.0)) - 6.0) * step(edge, cx));
        return c;
    }
    #endif

    #if ROOM == 4
    vec3 room_greenhouse(vec2 cv, float t) {
        float base = 770.0;
        // Night outside the glass, the moon high on the left.
        vec3 c = mix(vec3(0.03, 0.07, 0.10), vec3(0.06, 0.13, 0.14), smoothstep(0.0, base, cv.y));
        vec2 mp = cv - vec2(118.0, 92.0);
        c += vec3(0.25, 0.32, 0.38) * exp(-length(mp) / 200.0) * 0.6;
        c = mix(c, vec3(0.75, 0.82, 0.78), fill_aa(length(mp) - 26.0) * 0.8);
        c += vec3(0.7, 0.8, 0.9) * dots(cv / 21.0 + 1.3, 0.05) * 0.25 * (1.0 - smoothstep(100.0, 500.0, cv.y));
        // Trees far off beyond the glass, a darker band.
        float trees = cv.y - (520.0 + 50.0 * fbm(vec2(cv.x * 0.01, 1.0)) - 30.0 * noise(vec2(cv.x * 0.05, 4.0)));
        c = mix(c, vec3(0.03, 0.06, 0.06), smoothstep(-2.0, 2.0, trees) * 0.8);
        // The glasshouse: pointed iron bays, panes between them, a sheen
        // passing over the glass.
        vec2 g = vec2(mod(cv.x + 45.0, 90.0) - 45.0, mod(cv.y + 30.0, 130.0) - 65.0);
        float bay = sd_pointed(vec2(g.x, cv.y - 180.0), 40.0, 1e4, 1.5);
        float mull = min(-bay, 65.0 - abs(g.y) + step(cv.y, 180.0) * 1e3);
        float pane = noise(floor((cv + vec2(45.0, 30.0)) / vec2(90.0, 130.0)) * 3.7);
        c += vec3(0.04, 0.07, 0.07) * (0.5 + pane) * smoothstep(0.0, 40.0, mull) * step(cv.y, base);
        float sheen = exp(-pow((cv.x - cv.y * 0.5 - mod(t * 18.0, 1400.0) + 500.0) / 60.0, 2.0));
        c += vec3(0.1, 0.14, 0.14) * sheen * step(0.0, mull) * step(cv.y, base);
        c = mix(c, vec3(0.04, 0.06, 0.06), fill_aa(mull - 2.5) * 0.85 * step(cv.y, base));
        c += vec3(0.2, 0.3, 0.3) * fill_aa(abs(mull - 3.5) - 0.8) * 0.15 * step(cv.y, base);       // moonlit edge of the iron
        // Moonlight through the panes, the mullions' shadows in it.
        float sh = shaft(cv, vec2(118.0, 92.0), normalize(vec2(0.45, 1.0)), 60.0, 0.32, 1100.0);
        c += vec3(0.5, 0.65, 0.65) * sh * 0.07 * (0.6 + 0.4 * smoothstep(0.0, 6.0, mull));
        c += vec3(0.8, 0.95, 0.85) * dust(cv, t * 0.4) * sh * 0.15;
        // Benches of potted plants along the glass, low behind the board.
        float bench = abs(cv.y - 700.0) - 5.0;
        c = mix(c, vec3(0.10, 0.07, 0.05), fill_aa(bench));
        float pot = floor(cv.x / 60.0);
        vec2 pq = vec2(mod(cv.x, 60.0) - 30.0, cv.y - 680.0);
        float potd = sd_round_box(pq, vec2(14.0 - pq.y * 0.2, 15.0), vec4(2.0));
        c = mix(c, vec3(0.30, 0.13, 0.08) * (0.7 + 0.4 * hash12(vec2(pot, 1.0))), fill_aa(potd));
        float sprig = leaves(cv, vec2(pot * 60.0 + 30.0, 665.0), 34.0 + 20.0 * hash12(vec2(pot, 2.0)), pot * 2.3 - 2.2, t);
        c = mix(c, vec3(0.05, 0.14, 0.08) * (0.8 + 0.4 * noise(cv * 0.1)), fill_aa(sprig));
        // The floor: tiles of a path between the beds, moss in the joints.
        if (cv.y > base) {
            vec3 fl = floor_at(cv, base);
            float tm = bricks(fl.xy, vec2(80.0, 80.0), 3.0 / fl.z);
            vec3 tile = vec3(0.22, 0.12, 0.08) * (0.7 + 0.4 * brick_id(fl.xy, vec2(80.0, 80.0)));
            float moss = smoothstep(0.4, 0.7, noise(fl.xy * 0.02) * 0.7 + tm * 0.5);
            tile = mix(tile, vec3(0.08, 0.18, 0.08), moss * 0.85);
            tile *= 0.6 + 0.4 * (1.0 - fl.z);
            tile += vec3(0.2, 0.3, 0.3) * sh * 0.08;
            c = mix(vec3(0.02, 0.04, 0.03), tile, smoothstep(0.0, 10.0, cv.y - base));
        }
        // Leaves crowding in from the sides and hanging from above, swaying.
        float sway = sin(t * 0.33) * 6.0 + sin(t * 0.71 + cv.y * 0.01) * 3.0;
        vec2 lp = cv + vec2(sway * smoothstep(0.0, 300.0, cv.y), 0.0);
        float side = min(lp.x, 540.0 - lp.x);
        float leaf = noise(lp * 0.035) * 0.7 + noise(lp * 0.09 + 3.0) * 0.3;
        float hang = smoothstep(220.0, 0.0, cv.y) * 0.25 * (0.5 + 0.5 * sin(lp.x * 0.03 + 1.0));
        float foliage = smoothstep(0.52, 0.56, leaf + 0.40 - side / 120.0 + hang);
        float vein = noise(lp * vec2(0.2, 0.05));
        vec3 green = vec3(0.05, 0.16, 0.09) * (0.6 + 0.6 * vein) + vec3(0.1, 0.12, 0.1) * sh;
        c = mix(c, green, foliage * 0.92);
        // Vines trailing from the roof ribs.
        for (int i = 0; i < 3; i++) {
            float vx = 135.0 + float(i) * 135.0;
            float vlen = 110.0 + 70.0 * hash12(vec2(float(i), 4.0));
            float y = clamp(cv.y, 0.0, vlen);
            float x = vx + sin(y * 0.04 + float(i)) * 8.0 + sin(t * 0.5 + float(i) * 1.7) * y * 0.05;
            float vine = abs(cv.x - x) - 1.4 + step(vlen, cv.y) * 1e3;
            float lv = length(vec2(abs(cv.x - x) - 5.0, mod(cv.y + float(i) * 7.0, 18.0) - 9.0) * vec2(1.0, 0.7)) - 4.0 + step(vlen, cv.y) * 1e3;
            c = mix(c, vec3(0.06, 0.14, 0.08), fill_aa(min(vine, lv)) * 0.9);
        }
        // Close in front: broad leaves at the corners, dark and soft.
        float near = min(leaves(cv, vec2(-30.0, 860.0), 190.0, -0.9, t), leaves(cv, vec2(575.0, 820.0), 170.0, 2.4, t));
        near = min(near, leaves(cv, vec2(560.0, 60.0), 130.0, 1.9, t * 0.8));
        vec3 dark = vec3(0.02, 0.05, 0.03) + vec3(0.12, 0.2, 0.14) * smoothstep(-8.0, 0.0, near) * 0.5;
        c = mix(c, dark, smoothstep(3.0, -3.0, near));
        // Mist drifting low.
        float mist = noise(vec2(cv.x * 0.006 + t * 0.03, cv.y * 0.012)) * smoothstep(560.0, 960.0, cv.y);
        c += vec3(0.25, 0.32, 0.32) * mist * 0.22;
        return c;
    }
    #endif

    #if ROOM == 5
    vec3 room_athanor(vec2 cv, float t) {
        float f = light.a;
        float base = 770.0;
        // Embers burst from the furnace now and then; the room flares with them.
        float burst = ember_burst(t);
        float pulse = 0.78 + 0.14 * sin(t * 0.8) + 0.08 * f + 0.35 * burst;
        vec3 c = mix(vec3(0.07, 0.025, 0.035), vec3(0.17, 0.05, 0.045), smoothstep(0.0, base, cv.y));
        float m = bricks(cv, vec2(100.0, 70.0), 2.5);
        c *= (1.0 - 0.3 * m) * (0.85 + 0.25 * noise(cv * 0.03));
        c = brushed(c, cv);
        // Pointed arches either side, banners of the Work hanging in them.
        vec2 ap = vec2(abs(cv.x - 270.0) - 222.0, cv.y - 150.0);
        float arch = sd_pointed(ap, 54.0, base - 150.0, 1.6);
        c = mix(c, c * 0.45, fill_aa(arch));
        c = mix(c, vec3(0.20, 0.08, 0.06), fill_aa(abs(arch + 5.0) - 5.0));
        c += vec3(0.7, 0.25, 0.08) * fill_aa(abs(arch + 1.0) - 1.0) * 0.2 * smoothstep(0.0, 1.0, -ap.x / 50.0) * pulse;
        vec2 bp = vec2(abs(cv.x - 270.0) - 222.0, cv.y - 110.0);
        float wave = sin(bp.y * 0.03 - t * 0.6) * 3.0 * smoothstep(0.0, 300.0, bp.y);
        bp.x += wave;
        float banner = max(abs(bp.x) - 30.0, max(-bp.y, bp.y - 330.0 + abs(bp.x) * 0.7 - 20.0));
        vec3 cloth = vec3(0.30, 0.06, 0.06) * (0.7 + 0.5 * (0.5 + 0.5 * sin(bp.x * 0.1 + bp.y * 0.02 + wave)));
        float emblem = abs(length(bp - vec2(0.0, 130.0)) - 14.0) - 1.4;
        emblem = min(emblem, abs(sd_triangle(bp - vec2(0.0, 130.0), vec2(0.0, -12.0), vec2(10.4, 6.0), vec2(-10.4, 6.0))) - 1.2);
        cloth = mix(cloth, vec3(0.75, 0.52, 0.2) * 0.6, fill_aa(emblem));
        cloth = mix(cloth, vec3(0.6, 0.42, 0.18) * 0.6, fill_aa(abs(banner + 3.0) - 1.2));
        c = mix(c, cloth, fill_aa(banner));
        // The great circle of runes, turning slowly behind the work; a light
        // runs round its runes, and they all flare with a burst.
        float rune;
        vec2 rp = cv - vec2(270.0, 420.0);
        float sg = sigil(rp, 225.0, t * 0.02, 32.0, 1.0, rune);
        float lit = rune >= 0.0 ? rune_run(rune, 32.0, t, 0.6) : 0.0;
        c += vec3(0.85, 0.5, 0.18) * fill_aa(sg) * (0.13 + 0.5 * lit + 0.4 * burst) * pulse;
        c += vec3(0.8, 0.3, 0.1) * exp(-abs(length(rp) - 207.0) / 30.0) * (0.04 + 0.1 * burst);
        // The floor: dark stone, cracks glowing with the heat below, the
        // furnace's light pooling on it.
        if (cv.y > base) {
            vec3 fl = floor_at(cv, base);
            float sm = bricks(fl.xy, vec2(120.0, 90.0), 2.5 / fl.z);
            vec3 st = vec3(0.12, 0.06, 0.06) * (0.7 + 0.4 * brick_id(fl.xy, vec2(120.0, 90.0))) * (1.0 - 0.5 * sm);
            float crack = 1.0 - smoothstep(0.0, 0.02 / fl.z, abs(noise(fl.xy * 0.008 + 3.0) - 0.5));
            st += vec3(1.0, 0.35, 0.08) * crack * (0.25 + 0.15 * sin(t * 0.7 + fl.x * 0.01)) * pulse;
            st *= 0.6 + 0.4 * (1.0 - fl.z);
            c = mix(vec3(0.03, 0.01, 0.01), st, smoothstep(0.0, 10.0, cv.y - base));
        }
        // The athanor's red glow from below, breathing.
        c += vec3(0.65, 0.12, 0.03) * exp(-pow(length((cv - vec2(270.0, 1040.0)) * vec2(0.55, 1.0)) / 280.0, 2.0)) * 0.6 * pulse;
        // Close in front: pillars at the very edges, chains hung between.
        float pil = abs(cv.x - 270.0) - 262.0;
        vec3 pc = vec3(0.06, 0.02, 0.025) * (0.8 + 0.4 * noise(vec2(cv.x * 0.2, cv.y * 0.01)));
        c = mix(c, pc, smoothstep(-2.0, 2.0, pil));
        c += vec3(0.7, 0.25, 0.08) * fill_aa(abs(pil) - 1.0) * 0.25 * pulse;
        float ch = chain(cv, 34.0, 360.0, 1.0, t);
        c = mix(c, vec3(0.04, 0.015, 0.015), fill_aa(ch));
        c += vec3(0.7, 0.3, 0.1) * fill_aa(abs(ch + 1.0) - 0.6) * 0.18 * pulse;
        // Heat haze over it all.
        c *= 1.0 + 0.05 * (noise(vec2(cv.x * 0.03, cv.y * 0.02 + t * 0.8)) - 0.5) * smoothstep(300.0, 900.0, cv.y);
        return c;
    }
    #endif
    // The room a backdrop shows. Each room is a program of its own, which
    // names it as ROOM (its theme), so a program holds one room's code.
    vec3 room(vec2 cv, float t) {
    #if ROOM == 1
        return room_frost(cv, t);
    #elif ROOM == 2
        return room_glassworks(cv, t);
    #elif ROOM == 3
        return room_observatory(cv, t);
    #elif ROOM == 4
        return room_greenhouse(cv, t);
    #elif ROOM == 5
        return room_athanor(cv, t);
    #else
        return room_apothecary(cv, t);
    #endif
    }
    #endif

    // The ledge a flask stands on in a level: a short drum floating in the
    // room's air, of the room's own stuff, its top lit by the work above it.
    // Its quad is the drum: the top's ellipse (FLASK_E of the half width)
    // at the top, the bottom's at the bottom.
    vec4 plinth(vec2 p, vec2 h, int theme, float seed, float t) {
        float rx = h.x;
        float ry = rx * 0.36;
        float yt = -h.y + ry;
        float yb = h.y - ry;
        float top = (length((p - vec2(0.0, yt)) / vec2(rx, ry)) - 1.0) * ry;
        float bot = (length((p - vec2(0.0, yb)) / vec2(rx, ry)) - 1.0) * ry;
        float side = max(abs(p.x) - rx, abs(p.y - (yt + yb) * 0.5) - (yb - yt) * 0.5);
        float body = min(min(top, bot), side);
        vec2 tq = (p - vec2(0.0, yt)) / vec2(rx, ry);      // the top, in its own unit circle
        float u = p.x / rx;
        vec3 mat; vec3 rim; vec3 lit = light.rgb;
        if (theme == 1) { mat = vec3(0.17, 0.22, 0.30); rim = vec3(0.6, 0.75, 0.9); }
        else if (theme == 2) { mat = vec3(0.26, 0.13, 0.08); rim = vec3(1.0, 0.55, 0.2); }
        else if (theme == 3) { mat = vec3(0.16, 0.12, 0.14); rim = vec3(0.85, 0.66, 0.32); }
        else if (theme == 4) { mat = vec3(0.24, 0.24, 0.20); rim = vec3(0.55, 0.75, 0.6); }
        else if (theme == 5) { mat = vec3(0.12, 0.07, 0.08); rim = vec3(1.0, 0.45, 0.15); }
        else { mat = vec3(0.34, 0.20, 0.11); rim = vec3(0.95, 0.7, 0.4); }
        // The side: rounded by the light, darker below.
        vec3 c = mat * (0.45 + 0.35 * (1.0 - u * u)) * mix(0.9, 0.55, clamp((p.y - yt) / max(yb - yt + ry, 1.0), 0.0, 1.0));
        if (theme == 0 || theme == 3) c *= 0.85 + 0.3 * noise(vec2(p.x * 0.3, p.y * 0.05 + seed));     // grain
        else c *= 0.85 + 0.3 * noise(p * 0.15 + seed);
        // The top: a pool of the room's light under the flask, fading out.
        float r = length(tq);
        vec3 tc = mat * (0.75 + 0.2 * noise(tq * 3.0 + seed));
        tc += lit * 0.25 * exp(-r * r * 2.0);
        if (theme == 1) tc = mix(tc, vec3(0.75, 0.85, 0.95), smoothstep(0.55, 0.8, noise(tq * 4.0 + seed) * 0.6 + r * 0.4) * 0.3);
        if (theme == 3) tc = mix(tc, rim * 0.8, fill_aa((abs(r - 0.82) - 0.03) * ry * 2.0));
        if (theme == 4) tc = mix(tc, vec3(0.12, 0.28, 0.1), smoothstep(0.5, 0.7, noise(tq * 3.0 + seed) * 0.6 + r * 0.5) * 0.9);
        if (theme == 5) {
            float a = atan(tq.y, tq.x);
            float runes = fill_aa((abs(r - 0.8) - 0.06) * ry * 2.0) * step(0.4, fract(a * 2.5 + t * 0.1 + seed));
            tc += rim * runes * (0.35 + 0.25 * sin(t * 0.8 + seed));
        }
        if (theme == 2) c += rim * 0.25 * smoothstep(0.6, 1.0, abs(u)) * (0.8 + 0.2 * light.a);      // the fire behind catches its sides
        c = mix(c, tc, fill_aa(top));
        // A bright lip round the top's near edge, and a rim of light down the sides.
        c += rim * 0.35 * fill_aa(abs(top) - 0.8) * smoothstep(-0.2, 0.4, tq.y);
        c += rim * 0.12 * smoothstep(0.75, 1.0, abs(u)) * step(yt, p.y);
        return vec4(c, fill_aa(body));
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

    // A key u across each way from its middle: a ring for a bow on the left,
    // the shaft, two teeth at the tip.
    float sd_key(vec2 p, float u) {
        float bow = abs(sd_circle(p - vec2(-0.6 * u, 0.0), 0.27 * u)) - 0.11 * u;
        float shaft = sd_box(p - vec2(0.25 * u, 0.0), vec2(0.62 * u, 0.085 * u));
        float t1 = sd_box(p - vec2(0.76 * u, 0.2 * u), vec2(0.08 * u, 0.14 * u));
        float t2 = sd_box(p - vec2(0.5 * u, 0.17 * u), vec2(0.07 * u, 0.1 * u));
        return min(min(bow, shaft), min(t1, t2));
    }
    // A key's bow, centered on q: style 1 a ring (brass), 2 a trefoil
    // (silver), 3 a square ring turned to a diamond (copper), so the three
    // metals differ in shape as well as in color.
    float sd_key_bow(vec2 q, float u, int style) {
        if (style == 2) {
            float d = sd_circle(q, 0.15 * u);
            for (int k = 0; k < 3; k++) {
                float a = 3.14159265 + (float(k) - 1.0) * 1.4;
                d = min(d, sd_circle(q - vec2(cos(a), sin(a)) * 0.16 * u, 0.13 * u));
            }
            return max(d, -sd_circle(q - vec2(-0.04 * u, 0.0), 0.075 * u));
        }
        if (style == 3) return abs(sd_round_box(rot(0.7853982) * q, vec2(0.18 * u), vec4(0.04 * u))) - 0.065 * u;
        return abs(sd_circle(q, 0.2 * u)) - 0.085 * u;
    }
    // A finer key for the board, u across each way from its middle, its bow
    // on the left: the bow, a collar, the shaft and a notched bit under its tip.
    float sd_key_styled(vec2 p, float u, int style) {
        float bow = sd_key_bow(p - vec2(-0.66 * u, 0.0), u, style);
        float collar = sd_round_box(p - vec2(-0.36 * u, 0.0), vec2(0.06 * u, 0.15 * u), vec4(0.03 * u));
        float shaft = sd_round_box(p - vec2(0.3 * u, 0.0), vec2(0.64 * u, 0.09 * u), vec4(0.04 * u));
        float bit = sd_round_box(p - vec2(0.74 * u, 0.18 * u), vec2(0.17 * u, 0.15 * u), vec4(0.02 * u));
        bit = max(bit, -sd_box(p - vec2(0.72 * u, 0.33 * u), vec2(0.05 * u, 0.1 * u)));
        return min(min(bow, collar), min(shaft, bit));
    }
    #ifdef PROGRAM_UI
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
        } else if (which == ICON_KEY) {    // a key and the door it opens: a key, tilted
            return sd_key(rot(0.6) * p, r * 0.95);
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
    #endif

    // The liquid's layer fi: its color, and whether murk hides it. Four
    // layers share each number in p0, five bits each, bottom first.
    float layer_color(float fi) {
        int k = int(fi);
        float v = k < 4 ? v_p0.x : k < 8 ? v_p0.y : k < 12 ? v_p0.z : v_p0.w;
        return float((int(v + 0.5) >> (5 * (k % 4))) & 31);
    }
    bool layer_murky(float fi) { return ((int(v_p1.y + 0.5) >> int(fi)) & 1) != 0; }
    // A layer's plain color (smoke's middle tone), to blend across the line
    // where it meets the next.
    vec3 layer_rgb(float fi) {
        return layer_murky(fi) ? vec3(0.25, 0.23, 0.30) : palette[int(layer_color(fi) + 0.5)].rgb;
    }
    // Whether two layers read as one band: one color, or both smoke.
    bool layers_alike(float a, float b) {
        bool ma = layer_murky(a);
        bool mb = layer_murky(b);
        if (ma) return mb;
        return !mb && layer_color(a) == layer_color(b);
    }

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
    // A lantern's brass: a ring to hang it by, a knob, a peaked cap with a
    // brim, the posts either side of its panes, a base and a foot.
    float sd_lantern(vec2 q, float u) {
        vec2 a = vec2(abs(q.x), q.y);
        float ring = abs(length(q - vec2(0.0, -0.93 * u)) - 0.085 * u) - 0.03 * u;
        float knob = sd_circle(q - vec2(0.0, -0.8 * u), 0.07 * u);
        float slope = mix(0.08 * u, 0.5 * u, clamp((q.y + 0.75 * u) / (0.28 * u), 0.0, 1.0));
        float cap = max(a.x - slope, abs(q.y + 0.6 * u) - 0.15 * u);
        float brim = sd_round_box(q - vec2(0.0, -0.44 * u), vec2(0.53 * u, 0.055 * u), vec4(0.03 * u));
        float posts = sd_round_box(a - vec2(0.43 * u, 0.0), vec2(0.065 * u, 0.42 * u), vec4(0.02 * u));
        float mid = sd_box(q, vec2(0.018 * u, 0.4 * u));
        float base = sd_round_box(q - vec2(0.0, 0.47 * u), vec2(0.52 * u, 0.08 * u), vec4(0.03 * u));
        float foot = sd_round_box(q - vec2(0.0, 0.6 * u), vec2(0.32 * u, 0.055 * u), vec4(0.03 * u));
        return min(min(min(ring, knob), min(cap, brim)), min(min(posts, mid), min(base, foot)));
    }
    // The shepherd's crook it hangs from: a post at x = px rising from
    // y = bottom, bending over into an arm that ends past the ring.
    float sd_crook(vec2 q, float u, float px, float bottom) {
        vec2 c = vec2(q.x * sign(px), q.y);
        float x = abs(px);
        float r = 0.22 * u;
        float arm = -1.07 * u;
        float post = sd_segment(c, vec2(x, arm + r), vec2(x, bottom)) - 0.055 * u;
        vec2 b = c - vec2(x - r, arm + r);
        float bend = (b.x > 0.0 && b.y < 0.0) ? abs(length(b) - r) - 0.055 * u : 1e5;
        float bar = sd_segment(c, vec2(-0.1 * u, arm), vec2(x - r, arm)) - 0.05 * u;
        float tip = sd_circle(c - vec2(-0.13 * u, arm + 0.02 * u), 0.065 * u);
        float hook = sd_segment(c, vec2(0.0, arm), vec2(0.0, -1.0 * u)) - 0.025 * u;
        return min(min(post, bend), min(min(bar, tip), hook));
    }

    // A door's frame, how thick for a door h across each way (parts.goose's
    // keyhole_at knows it too).
    float door_frame(vec2 h) { return clamp(min(h.x, h.y) * 0.07, 3.0, 8.0); }
    // The lock plate's middle and size, below the lintel at yTop.
    float door_lock_r(float Wl, float H) { return clamp(min(Wl * 0.34, H * 0.16), 7.0, 24.0); }
    float plate_sd(vec2 q, float R) { return sd_round_box(q, vec2(R * 0.78, R * 1.2), vec4(R * 0.6, R * 0.25, R * 0.6, R * 0.25)); }
    // A double door's face as it stands shut, at f (from its middle, y down):
    // two leaves of planks Wl wide meeting in the middle, from yTop down to
    // the table, iron strap hinges, and across the meeting a lock plate of
    // its key's metal (mc), the key's bow (style) engraved over the keyhole.
    // While it is shut (`shut`), light from behind shows through the keyhole
    // and the cracks.
    vec3 door_face(vec2 f, vec2 h, float Wl, float yTop, int style, vec3 mc, float shut, float t) {
        float H = h.y - yTop;
        float lx = abs(f.x);
        float pw = max(Wl / 2.5, 7.0);
        float px = (fract(lx / pw) - 0.5) * pw;
        float grain = noise(vec2(f.x * 0.09, f.y * 0.015)) * 0.6 + noise(vec2(f.x * 0.35, f.y * 0.05)) * 0.4;
        vec3 c = vec3(0.42, 0.27, 0.15) * (0.68 + 0.45 * grain);
        c *= 1.0 - 0.45 * (1.0 - smoothstep(0.0, 1.4, pw * 0.5 - abs(px)));      // the seams between planks
        c *= 0.78 + 0.22 * smoothstep(yTop, yTop + H * 0.5, f.y);                // shade under the lintel
        float edge = min(min(lx, Wl - lx), min(f.y - yTop, h.y - f.y));
        c *= 0.6 + 0.4 * smoothstep(0.0, 2.5, edge);
        vec3 warm = vec3(1.0, 0.78, 0.42);
        float flick = (0.85 + 0.15 * sin(t * 2.3) * sin(t * 1.3 + 1.0)) * shut;
        c += warm * exp(-lx / 0.9) * 0.6 * flick;
        c += warm * exp(-(h.y - f.y) / 1.3) * 0.5 * flick;
        // Iron strap hinges from the outer edges, studded.
        vec3 iron = vec3(0.2, 0.2, 0.23);
        float sw = clamp(H * 0.035, 1.8, 4.0);
        float step_x = max(Wl * 0.2, 6.0);
        for (int k = 0; k < 2; k++) {
            float y = k == 0 ? yTop + H * 0.2 : h.y - H * 0.2;
            vec2 q = vec2(Wl - lx, f.y - y);
            float strap = min(sd_box(q - vec2(Wl * 0.33, 0.0), vec2(Wl * 0.33, sw)), sd_circle(q - vec2(Wl * 0.66, 0.0), sw * 1.5));
            c = mix(c, vec3(0.0), fill_aa(strap - 1.0) * 0.4);
            c = mix(c, iron * (1.0 + 0.6 * smoothstep(sw, -sw, q.y)), fill_aa(strap));
            vec2 rv = vec2((fract(q.x / step_x) - 0.5) * step_x, q.y);
            c = mix(c, vec3(0.55, 0.55, 0.58), fill_aa(sd_circle(rv, max(sw * 0.5, 1.0))) * step(q.x, Wl * 0.6) * step(2.0, q.x));
        }
        // The lock plate, shaded as metal, a dark line round it.
        float R = door_lock_r(Wl, H);
        vec2 lp = f - vec2(0.0, yTop + H * 0.47);
        vec2 e = vec2(0.5, 0.0);
        float plate = plate_sd(lp, R);
        vec2 g = vec2(plate_sd(lp + e.xy, R) - plate_sd(lp - e.xy, R), plate_sd(lp + e.yx, R) - plate_sd(lp - e.yx, R));
        c = mix(c, vec3(0.03), fill_aa(plate - 1.5) * 0.7);
        vec3 m = metal(mc, plate, g, 0.22 * R);
        // Rivets in its corners, the bow engraved, the keyhole.
        float riv = 1e5;
        for (int k = 0; k < 4; k++) {
            vec2 rp = vec2(k % 2 == 0 ? -R * 0.55 : R * 0.55, k < 2 ? -R * 0.85 : R * 0.95);
            riv = min(riv, sd_circle(lp - rp, max(R * 0.07, 0.9)));
        }
        m = mix(m, mc * 1.3 + 0.15, fill_aa(riv));
        float bow = sd_key_bow(lp - vec2(0.0, -R * 0.48), R * 1.35, style);
        m = mix(m, mc * 1.25 + 0.1, fill_aa(bow + 0.8) * 0.8);
        m = mix(m, mc * 0.3, fill_aa(bow));
        float hole = min(sd_circle(lp - vec2(0.0, R * 0.32), R * 0.17), sd_box(lp - vec2(0.0, R * 0.62), vec2(R * 0.08, R * 0.3)));
        m = mix(m, mix(vec3(0.04, 0.03, 0.02), warm, 0.55 * flick), fill_aa(hole));
        return mix(c, m, fill_aa(plate));
    }

    // --- the title screen and the map ----------------------------------------
    // An alchemical sign as strokes about one unit across, centered: its
    // distance in those units. 0 gold (the sun), 1 silver (the moon), 2
    // mercury, 3 sulfur, 4 salt, 5 air.
    #ifdef PROGRAM_TITLE
    float sd_alchemy(vec2 q, int which) {
        if (which == 0) return min(abs(length(q) - 0.36), length(q) - 0.05);
        if (which == 1) return abs(max(length(q) - 0.4, -(length(q - vec2(0.2, -0.06)) - 0.34)));
        if (which == 2) {
            float d = abs(length(q) - 0.19);
            d = min(d, sd_arc(q - vec2(0.0, -0.36), 0.16, 0.0, 3.14159265, 0.0));
            d = min(d, sd_segment(q, vec2(0.0, 0.19), vec2(0.0, 0.5)));
            return min(d, sd_segment(q, vec2(-0.13, 0.35), vec2(0.13, 0.35)));
        }
        if (which == 3) {
            float d = abs(sd_triangle(q, vec2(0.0, -0.48), vec2(0.28, 0.04), vec2(-0.28, 0.04)));
            d = min(d, sd_segment(q, vec2(0.0, 0.04), vec2(0.0, 0.5)));
            return min(d, sd_segment(q, vec2(-0.15, 0.28), vec2(0.15, 0.28)));
        }
        if (which == 4) return min(abs(length(q) - 0.36), sd_segment(q, vec2(-0.36, 0.0), vec2(0.36, 0.0)));
        float d = abs(sd_triangle(q, vec2(0.0, -0.42), vec2(0.36, 0.24), vec2(-0.36, 0.24)));
        return min(d, sd_segment(q, vec2(-0.44, 0.0), vec2(0.44, 0.0)));
    }
    #endif
    // Gilt: dark at the bottom of a raised line, bright along its top, in
    // the room's candlelight. k is across the line, -1 top to 1 bottom.
    vec3 gilt(float k) {
        vec3 c = mix(vec3(1.0, 0.9, 0.6), vec3(0.55, 0.33, 0.1), smoothstep(-0.8, 1.0, k));
        return mix(c, c * light.rgb * 1.15, 0.3);
    }
    // A chapter's room in a roundel (q: radius 1, y down): its air, and its
    // emblem, the color in rgb and coverage in a; r is the radius in pixels.
    #ifdef PROGRAM_TITLE
    vec3 medallion_air(int theme, vec2 q) {
        float k = q.y * 0.5 + 0.5;
        if (theme == 1) return mix(vec3(0.20, 0.32, 0.45), vec3(0.08, 0.13, 0.24), k);
        if (theme == 2) return mix(vec3(0.24, 0.08, 0.05), vec3(0.55, 0.20, 0.06), k);
        if (theme == 3) return mix(vec3(0.03, 0.04, 0.14), vec3(0.10, 0.12, 0.30), k);
        if (theme == 4) return mix(vec3(0.08, 0.22, 0.20), vec3(0.04, 0.12, 0.09), k);
        if (theme == 5) return mix(vec3(0.22, 0.04, 0.05), vec3(0.45, 0.10, 0.05), k);
        if (theme == 6) return mix(vec3(0.16, 0.08, 0.26), vec3(0.42, 0.25, 0.10), k);
        return mix(vec3(0.30, 0.17, 0.12), vec3(0.16, 0.08, 0.06), k);
    }
    vec4 medallion_emblem(int theme, vec2 q, float r, float t) {
        if (theme == 1) {           // frost cellar: a snowflake
            float d = 1e3;
            for (int k = 0; k < 3; k++) {
                vec2 dir = vec2(cos(float(k) * 1.0472 + 0.5236), sin(float(k) * 1.0472 + 0.5236));
                d = min(d, sd_segment(q, -dir * 0.55, dir * 0.55));
                vec2 qa = vec2(abs(dot(q, dir)), abs(dot(q, vec2(-dir.y, dir.x))));
                d = min(d, sd_segment(qa, vec2(0.28, 0.0), vec2(0.42, 0.13)));
            }
            return vec4(0.88, 0.96, 1.0, fill_aa((d - 0.06) * r));
        }
        if (theme == 2) {           // glassworks: the furnace's mouth, burning
            vec2 m = q - vec2(0.0, 0.2);
            float arch = sd_round_box(m, vec2(0.42, 0.42), vec4(0.42, 0.0, 0.42, 0.0));
            float fl = 0.8 + 0.2 * sin(t * 3.0 + q.x * 6.0);
            vec3 c = mix(vec3(1.0, 0.88, 0.45), vec3(0.95, 0.32, 0.05), smoothstep(-0.2, 0.55, -m.y + 0.2)) * fl;
            float brick = fill_aa((abs(arch + 0.07) - 0.07) * r);
            return vec4(mix(c, vec3(0.30, 0.13, 0.08), brick), max(fill_aa(arch * r), brick));
        }
        if (theme == 3) {           // observatory: the moon and a star
            float moon = max(length(q + vec2(0.12, 0.05)) - 0.42, -(length(q + vec2(-0.06, 0.16)) - 0.36));
            float star = sd_star5(q - vec2(0.34, -0.3), 0.16, 0.45);
            return vec4(1.0, 0.95, 0.75, fill_aa(min(moon, star) * r));
        }
        if (theme == 4) {           // greenhouse: a leaf and its vein
            vec2 l = rot(0.7854) * q;
            float leaf = max(length(l - vec2(0.3, 0.0)) - 0.52, length(l + vec2(0.3, 0.0)) - 0.52);
            float vein = max(abs(l.x) - 0.035, abs(l.y) - 0.38);
            vec3 c = mix(vec3(0.6, 0.9, 0.42), vec3(0.25, 0.58, 0.2), clamp(l.x + 0.5, 0.0, 1.0));
            return vec4(mix(c, vec3(0.15, 0.35, 0.12), fill_aa(vein * r)), fill_aa(leaf * r));
        }
        if (theme == 5) {           // athanor: a flame
            return flame((q - vec2(0.0, 0.3)) * r, r * 0.24, light.a, 2.0, t);
        }
        if (theme == 6) {           // the Great Work: the Stone, its rays turning
            float d = sd_hexagon(rot(0.5236) * q, 0.24);
            float a = atan(q.y, q.x);
            float rays = pow(abs(sin(a * 4.0 + t * 0.3)), 8.0) * (1.0 - smoothstep(0.2, 0.8, length(q)));
            vec3 c = mix(vec3(1.0, 0.85, 0.5), vec3(0.9, 0.15, 0.2), fill_aa(d * r));
            return vec4(c, max(fill_aa(d * r), rays * 0.7));
        }
        // apothecary: a stoppered bottle on its shelf
        float body = sd_round_box(q - vec2(0.0, 0.12), vec2(0.27, 0.25), vec4(0.15));
        float neck = sd_box(q - vec2(0.0, -0.22), vec2(0.09, 0.12));
        float shelf = sd_box(q - vec2(0.0, 0.43), vec2(0.62, 0.045));
        float d = min(min(body, neck), shelf);
        vec3 c = mix(vec3(0.95, 0.45, 0.3), vec3(0.7, 0.48, 0.28), step(0.4, q.y));
        c = mix(c, vec3(0.75, 0.55, 0.35), step(q.y, -0.1));
        return vec4(c, fill_aa(d * r));
    }
    #endif

    // --- the widgets: plates and bezels ---------------------------------------------
    // Buttons, panels, switches and badges are made as the room's things
    // are: enamel fired in a gilt rim that stands up from it, lit from above
    // and a little from the left by the candles.

    // Pixels per canvas unit, so a widget's lines and grain keep their size
    // on the canvas whatever the window's.
    #ifdef PROGRAM_UI
    float unit_px() { return max(min(screen.x / 540.0, screen.y / 960.0), 0.05); }

    // A plate's outline: 0 a tablet, its ends drawn to a blunt point; 1 a
    // banner, its ends forked; 2 a slot; 3 a panel.
    float widget_sd(vec2 p, vec2 h, int style, float s) {
        if (style == 0) {
            float L = min(h.y * 0.6, h.x * 0.3);
            vec2 n = normalize(vec2(h.y, L));
            return max(sd_box(p, h), dot(vec2(abs(p.x) - (h.x - L), abs(p.y) - h.y), n));
        }
        if (style == 1) {
            float notch = h.y * 0.7;
            float cut = sd_triangle(vec2(abs(p.x), p.y), vec2(h.x + 1.0, -h.y - 1.0), vec2(h.x - notch, 0.0),
                                    vec2(h.x + 1.0, h.y + 1.0));
            return max(sd_box(p, h), -cut);
        }
        if (style == 2) return sd_round_box(p, h, vec4(min(h.y, 12.0 * s)));
        return sd_round_box(p, h, vec4(16.0 * s));
    }

    // The gilt of a rim `rim` pixels wide, a rounded bead: e is the depth
    // into it from its outer edge, lit how much its outward side faces the
    // light. Dulled to old bronze when off.
    vec3 gilt_rim(float e, float rim, float lit, float hover, float off) {
        float across = clamp(e / rim, 0.0, 1.0);
        vec3 c = gilt(clamp(-lit * (1.0 - 2.0 * across) * 1.7, -1.0, 1.0)) +
                 vec3(1.0, 0.92, 0.75) * 0.16 * exp(-pow((across - 0.4) * 4.0, 2.0));
        // A dark hairline at its outer edge, where it meets what it stands on.
        c *= mix(0.4, 1.0, smoothstep(0.0, 1.2 * unit_px(), e));
        c *= 1.0 + 0.22 * hover;
        return mix(c, vec3(dot(c, vec3(0.35, 0.45, 0.2))) * vec3(0.8, 0.72, 0.62) * 0.75, off);
    }

    // The plate (SHAPE_PLATE): the rim, a dark groove inside it, then the
    // enamel, lighter at the top, mottled as fired glass is and shadowed
    // under the rim; a fine gilt line inset along the outline, with a
    // lozenge at each end of a long tablet and a bead in each corner of a
    // panel. A tablet and a banner are glazed, a gloss across their top;
    // a slot is sunk, deeper in shadow. hover brings a candle near, warming
    // it from below; pressed pushes it in.
    vec4 widget_plate(vec2 p, vec2 h, int style, vec4 tint, float hover, float rim, float press) {
        float s = unit_px();
        float d = widget_sd(p, h, style, s);
        if (d > 1.0) return vec4(0.0);
        vec2 g = vec2(widget_sd(p + vec2(1.0, 0.0), h, style, s), widget_sd(p + vec2(0.0, 1.0), h, style, s)) - d;
        vec2 n = g / max(length(g), 1e-4);
        float lit = dot(n, vec2(-0.35, -0.94));
        float off = step(hover, -0.5);
        hover = max(hover, 0.0);
        float e = -d;
        float inner = e - rim;
        vec2 cv = p / s;
        bool sunk = style == 2;

        vec3 c = mix(tint.rgb * 1.4 + 0.025, tint.rgb * 0.6, clamp(p.y / (2.0 * h.y) + 0.5, 0.0, 1.0));
        float grain = noise(cv * 0.09 + h.x * 0.13) * 0.6 + noise(cv * 0.3) * 0.4;
        c *= 0.88 + 0.22 * grain;
        if (style == 3) {
            // A panel's velvet: a faint nap, and the candlelight on its upper half.
            c *= 0.94 + 0.12 * noise(vec2(cv.x * 0.7, cv.y * 0.04));
            c += light.rgb * 0.06 * exp(-length((p + vec2(0.0, h.y * 0.9)) / vec2(h.x * 1.1, h.y)) * 2.0);
        }
        float sh = (sunk ? 8.0 : 4.5) * s * (0.6 + 0.9 * max(-n.y, 0.0));
        c *= mix(sunk ? 0.3 : 0.55, 1.0, smoothstep(0.0, sh, inner));
        if (style < 2) {
            float gy = (p.y + h.y * 0.45) / max(h.y * 0.3, 1.0);
            float gx = 1.0 - smoothstep(h.x * 0.5, h.x * 0.95, abs(p.x));
            c += vec3(1.0, 0.95, 0.85) * exp(-gy * gy) * gx * 0.12 * (1.0 - 0.7 * press);
        }
        c += light.rgb * vec3(1.0, 0.78, 0.5) * exp(-length((p - vec2(0.0, h.y * 0.9)) / vec2(h.x * 0.8, h.y * 1.4)) * 1.6) *
             hover * 0.4;
        c *= 1.0 - 0.18 * press;
        c = mix(c, vec3(dot(c, vec3(0.3, 0.5, 0.2))) * 0.8, off * 0.8);

        // The fine line inside, and its ornaments.
        if (style != 2) {
            float inset = rim + (style == 3 ? 7.0 : 2.5) * s;
            float fl = abs(d + inset) - 0.6 * s;
            if (style == 3) {
                vec2 ci = abs(p) - (h - vec2(inset));
                float R = 10.0 * s;
                fl = abs(max(sd_box(p, h - vec2(inset)), -(length(ci) - R))) - 0.6 * s;
                fl = min(fl, length(ci) - 2.6 * s);
                fl = min(fl, max(abs(length(ci) - R * 0.5) - 0.5 * s, max(ci.x, ci.y)));
                vec2 m = vec2(p.x, abs(p.y) - (h.y - inset));
                fl = min(fl, (abs(m.x) * 0.6 + abs(m.y) - 3.0 * s) * 0.85);
            } else if (style == 0 && h.x > 3.2 * h.y) {
                float L = min(h.y * 0.6, h.x * 0.3);
                vec2 m = vec2(abs(p.x) - (h.x - L * 0.55 - inset * 1.7), p.y);
                fl = min(fl, (abs(m.x) * 0.55 + abs(m.y) - 3.4 * s) * 0.85);
                fl = min(fl, length(m + vec2(9.0 * s, 0.0)) - 1.5 * s);
                fl = min(fl, length(m + vec2(14.0 * s, 0.0)) - 1.0 * s);
            }
            vec3 lc = gilt(p.y / h.y * 0.8);
            lc = mix(lc, vec3(dot(lc, vec3(0.35, 0.45, 0.2))) * 0.7, off);
            c = mix(c, lc, fill_aa(fl) * (style == 3 ? 0.75 : 0.65));
        }
        // The groove, then the rim over it.
        c *= 1.0 - 0.5 * fill_aa(abs(inner) - 0.7 * s);
        c = mix(c, gilt_rim(e, rim, sunk ? -lit : lit, hover, off), fill_aa(inner));
        return vec4(c, fill_aa(d) * tint.a);
    }

    // The bezel (SHAPE_BEZEL): style 0 a cabochon of enamel in a gilt ring
    // engraved with an astrolabe's ticks, glossed high on the left; style 1
    // a gilt bead, a switch's knob.
    vec4 widget_bezel(vec2 p, float r, int style, vec4 tint, float hover, float rim, float press) {
        float s = unit_px();
        float l = length(p);
        float d = l - r;
        if (d > 1.0) return vec4(0.0);
        vec2 q = p / r;
        float off = step(hover, -0.5);
        hover = max(hover, 0.0);
        if (style == 1) {
            vec3 N = vec3(q, sqrt(max(1.0 - dot(q, q), 0.0)));
            float diff = max(dot(N, normalize(vec3(-0.4, -0.75, 0.55))), 0.0);
            vec3 c = mix(vec3(0.42, 0.25, 0.08), vec3(1.0, 0.85, 0.52), diff);
            c += vec3(1.0, 0.97, 0.9) * exp(-pow(length(q - vec2(-0.3, -0.4)) / 0.25, 2.0)) * 0.6;
            c *= (1.0 + 0.15 * hover) * tint.rgb;
            c *= 1.0 - 0.3 * fill_aa(abs(d + 0.8 * s) - 0.6 * s);
            return vec4(c, fill_aa(d) * tint.a);
        }
        vec2 n = p / max(l, 1e-3);
        float lit = dot(n, vec2(-0.35, -0.94));
        float e = -d;
        float inner = e - rim;
        vec3 c = mix(tint.rgb * 1.5 + 0.03, tint.rgb * 0.55, clamp(q.y * 0.5 + 0.5, 0.0, 1.0));
        vec2 cv = p / s;
        c *= 0.86 + 0.28 * (noise(cv * 0.12 + r) * 0.6 + noise(cv * 0.37) * 0.4);
        // Flecks of gold in it, as lapis has.
        c = mix(c, vec3(0.95, 0.78, 0.42), dots(cv * 0.32 + r, 0.16) * step(0.8, hash12(floor(cv * 0.32 + r))) * 0.45);
        c *= mix(0.45, 1.0, smoothstep(0.0, (3.0 + 4.0 * max(-n.y, 0.0)) * s, inner));
        c += vec3(1.0, 0.95, 0.85) * exp(-pow(length((q - vec2(-0.2, -0.45)) * vec2(1.0, 1.8)) / 0.32, 2.0)) * 0.16 *
             (1.0 - 0.6 * press);
        c += light.rgb * vec3(1.0, 0.78, 0.5) * exp(-length(q - vec2(0.0, 0.75)) * 2.2) * hover * 0.5;
        c *= 1.0 - 0.18 * press;
        c = mix(c, vec3(dot(c, vec3(0.3, 0.5, 0.2))) * 0.8, off * 0.8);
        vec3 rc = gilt_rim(e, rim, lit, hover, off);
        if (r > 15.0 * s) {
            float count = 4.0 * floor(r / (3.2 * s));
            float a = atan(p.y, p.x) * count / 6.2831853;
            float tick = abs(fract(a) - 0.5) * 6.2831853 / count * l - 0.45 * s;
            rc *= 1.0 - 0.55 * fill_aa(tick) * (1.0 - smoothstep(rim * 0.35, rim * 0.6, e));
        }
        c *= 1.0 - 0.5 * fill_aa(abs(inner) - 0.7 * s);
        c = mix(c, rc, fill_aa(inner));
        return vec4(c, fill_aa(d) * tint.a);
    }
    #endif

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
        } else if (kind == SHAPE_SPARK) {                 // sparkle
            vec2 q = abs(p / h);
            float star = 1.0 - smoothstep(0.0, 0.08, q.x * q.y * 6.0 + max(q.x, q.y) * 0.25 - 0.18);
            float core = exp(-dot(p / h, p / h) * 6.0);
            col = vec4(v_color.rgb, v_color.a * clamp(star + core, 0.0, 1.0));
        } else if (kind == SHAPE_RING) {                // ring
            float d = abs(length(p) - (h.x - v_p0.x * 0.5)) - v_p0.x * 0.5;
            col = vec4(v_color.rgb, v_color.a * fill_aa(d));
    #ifdef PROGRAM_UI
        } else if (kind == SHAPE_PLATE) {               // a widget's plate
            col = widget_plate(p, h, int(v_p0.x + 0.5), v_color, v_p0.y, v_p0.z, v_p0.w);
        } else if (kind == SHAPE_BEZEL) {               // a round widget
            col = widget_bezel(p, min(h.x, h.y), int(v_p0.x + 0.5), v_color, v_p0.y, v_p0.z, v_p0.w);
        } else if (kind == SHAPE_ICON) {                // icon
            float r = min(h.x, h.y);
            float d = sd_icon(p, int(v_p0.x + 0.5), r);
            col = vec4(v_color.rgb, v_color.a * fill_aa(d));
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
    #endif
    #ifdef PROGRAM_TITLE
        } else if (kind == SHAPE_SANCTUM) {             // the title screen: a study at dusk, in candlelight
            vec2 cv = p * (v_p0.x / h.x) + vec2(270.0, 480.0);         // canvas units
            float f = 0.85 + 0.15 * light.a;
            // A painted wall: deep blue above, warming to umber at the bench.
            vec3 c = mix(vec3(0.045, 0.04, 0.10), vec3(0.14, 0.075, 0.18), smoothstep(-100.0, 560.0, cv.y));
            c = mix(c, vec3(0.24, 0.12, 0.09), smoothstep(400.0, 640.0, cv.y));
            // Broad brushstrokes: noise bent by noise, drifting very slowly.
            vec2 q = cv * vec2(0.0045, 0.009);
            float w = noise(q * 1.3 + vec2(t * 0.012, 3.0));
            float n = noise(q + vec2(w * 1.8, w * 0.6) + vec2(t * 0.01, 0.0));
            float fine = noise(cv * vec2(0.045, 0.014) + w * 3.0);
            c *= 0.7 + 0.55 * n + 0.14 * (fine - 0.5);
            // Shelves at either side in silhouette, their glass catching the
            // light.
            float side = abs(cv.x - 270.0);
            if (side > 130.0 && cv.y < 628.0) {
                float sy = cv.y < 380.0 ? 300.0 : 468.0;
                float jx = floor(cv.x / 38.0);
                float hj = hash12(vec2(jx, sy));
                float jh = 20.0 + hj * 36.0;
                vec2 jp = vec2(mod(cv.x, 38.0) - 19.0, cv.y - (sy - jh * 0.5));
                float jar = min(sd_round_box(jp, vec2(9.0 + hj * 6.0, jh * 0.5), vec4(5.0)),
                                sd_box(jp + vec2(0.0, jh * 0.5 + 4.0), vec2(4.0, 5.0)));
                float shelf = abs(cv.y - sy - 4.0) - 4.0;
                float far = smoothstep(130.0, 220.0, side);
                vec3 glass = mix(vec3(0.3, 0.12, 0.2), vec3(0.12, 0.25, 0.3), hash12(vec2(jx, sy + 1.0)));
                float sil = max(fill_aa(shelf), hj > 0.2 ? fill_aa(jar) : 0.0);
                c = mix(c, c * 0.35 + glass * 0.12 * step(-jh * 0.1, jp.y), sil * far);
                float facing = clamp(-sign(cv.x - 270.0) * jp.x / 10.0, 0.0, 1.0);
                c += light.rgb * fill_aa(abs(jar + 1.0) - 1.0) * facing * 0.25 * far * step(0.2, hj) * f;
            }
            // The candlelight round the flask, in layers, and slow rays
            // turning through the dusty air.
            vec2 L = (cv - vec2(270.0, 480.0)) * vec2(1.0, 1.1);
            float r = length(L);
            c += light.rgb * (0.32 * exp(-r / 150.0) + 0.13 * exp(-r / 400.0)) * f;
            float ang = atan(L.y, L.x);
            float rays = noise(vec2(ang * 5.0, t * 0.05)) * noise(vec2(ang * 9.0 + 5.0, 2.0 - t * 0.04));
            c += light.rgb * smoothstep(0.12, 0.5, rays) * exp(-r / 330.0) * smoothstep(80.0, 200.0, r) * 0.22 * f;
            // Mist drifting through the lower air.
            float mist = noise(vec2(cv.x * 0.004 - t * 0.02, cv.y * 0.01)) * noise(vec2(cv.x * 0.009 + t * 0.03, cv.y * 0.02 + 4.0));
            c += vec3(0.32, 0.24, 0.42) * mist * smoothstep(240.0, 520.0, cv.y) * (1.0 - smoothstep(560.0, 640.0, cv.y)) * 0.4;
            // The bench's front, dark wood in the candles' spill.
            if (cv.y > 626.0) {
                float k = cv.y - 628.0;
                float g = noise(vec2(cv.x * 0.012, cv.y * 0.12)) * 0.6 + noise(vec2(cv.x * 0.05, cv.y * 0.45)) * 0.4;
                vec3 wood = vec3(0.23, 0.125, 0.075) * (0.65 + 0.6 * g);
                wood *= 1.0 - 0.45 * (1.0 - smoothstep(0.0, 2.0, abs(mod(k, 112.0) - 56.0) - 54.0));
                wood += light.rgb * 0.22 * exp(-k / 70.0) * exp(-abs(cv.x - 270.0) / 240.0) * f;
                wood *= 1.0 - 0.4 * smoothstep(0.0, 330.0, k);
                c = mix(c, wood, smoothstep(626.0, 628.0, cv.y));
            }
            vec2 vq = (cv / vec2(540.0, 960.0) - 0.5) * vec2(1.25, 0.8);
            c *= mix(0.35, 1.0, smoothstep(0.85, 0.2, length(vq)));
            col = vec4(c, 1.0);
        } else if (kind == SHAPE_ASTROLABE) {           // gilt rings and runes, turning
            float R = min(h.x, h.y);
            vec2 u = p / R;
            float px = 1.0 / R;
            float r = length(u);
            float a = atan(u.y, u.x);
            // The outer band: two rings and the hours' ticks, turning one way.
            float ft = (a + t * 0.012) / 6.2831853 * 72.0;
            float k = floor(ft + 0.5);
            float major = 1.0 - step(0.5, mod(k + 72.0, 6.0));
            float along = abs(ft - k) * 0.0872665 * r;
            float d = min(abs(r - 0.97) - 0.9 * px, abs(r - 0.91) - 0.6 * px);
            d = min(d, max(along - mix(0.5, 0.9, major) * px, max(mix(0.94, 0.91, major) - r, r - 0.97)));
            // A band of runes, turning the other way; one may flare.
            float flare = 0.0;
            float rd = 1e3;
            if (r > 0.72 && r < 0.88) {
                float fc = (a - t * 0.02) / 6.2831853 * 24.0;
                float cell = floor(fc);
                float cid = mod(cell + 24.0, 24.0);
                vec2 g = vec2((fc - cell - 0.5) * 0.2094, r - 0.80);
                rd = sd_segment(g, vec2(0.0, -0.045), vec2(0.0, 0.045));
                for (int s = 1; s < 3; s++) {
                    vec2 hs = vec2(hash12(vec2(cid, float(s) * 7.0)), hash12(vec2(cid, float(s) * 7.0 + 3.0)));
                    vec2 ha = vec2(hash12(vec2(cid, float(s) * 5.0 + 1.0)), hash12(vec2(cid, float(s) * 5.0 + 2.0)));
                    vec2 pa = (floor(hs * 3.0) - 1.0) * vec2(0.035, 0.045);
                    vec2 pb = (floor(ha * 3.0) - 1.0) * vec2(0.035, 0.045) + vec2(0.001, 0.0);
                    rd = min(rd, sd_segment(g, pa, pb));
                }
                flare = v_p0.y * (1.0 - step(0.5, abs(cid - v_p0.x)));
                rd -= (0.7 + flare) * px;
                d = min(d, rd);
            }
            d = min(d, min(abs(r - 0.86), abs(r - 0.74)) - 0.5 * px);
            // Within, fainter: a hexagram turning slowly in its circle, and a
            // planet on its orbit.
            float di = 1e3;
            if (r < 0.7) {
                vec2 hq = rot(t * 0.03) * u;
                float tri = min(abs(sd_triangle(hq, vec2(0.0, -0.62), vec2(0.537, 0.31), vec2(-0.537, 0.31))),
                                abs(sd_triangle(hq, vec2(0.0, 0.62), vec2(0.537, -0.31), vec2(-0.537, -0.31))));
                di = min(tri - 0.6 * px, min(abs(r - 0.62), abs(r - 0.36)) - 0.6 * px);
                vec2 p1 = 0.49 * vec2(cos(t * 0.11), sin(t * 0.11));
                di = min(di, length(u - p1) - 0.025);
            }
            vec2 p2 = 0.80 * vec2(cos(-t * 0.07 + 2.0), sin(-t * 0.07 + 2.0));
            d = min(d, abs(length(u - p2) - 0.035) - 0.6 * px);
            // A slow gleam going round, a soft glow off the lines, and the
            // flaring rune's own bright halo.
            float sheen = 0.45 + 0.55 * pow(0.5 + 0.5 * cos(a - t * 0.25), 3.0);
            float line = max(fill_aa(d * R), 0.5 * fill_aa(di * R));
            float halo = exp(-max(min(d, di), 0.0) * R / 4.0) * 0.16;
            float burst = flare * exp(-max(rd, 0.0) * R / 3.5) * 0.85;
            vec3 c = mix(vec3(0.95, 0.74, 0.42), vec3(1.0, 0.96, 0.85), clamp(burst * 1.5, 0.0, 1.0));
            float aa = (line * sheen + halo + burst) * (1.0 - smoothstep(v_p0.z - 0.15, v_p0.z, u.y));
            aa *= 1.0 - smoothstep(0.98, 1.02, r);
            col = vec4(c, clamp(aa, 0.0, 1.0) * v_color.a);
        } else if (kind == SHAPE_WISP) {                // a sign drawn in steam
            float s = min(h.x, h.y);
            vec2 q = p / (s * 0.8);
            float shown = v_p0.z;
            // Steam wavers: the sign seen through moving noise, looser as it
            // comes and goes.
            vec2 wob = vec2(noise(q * 2.5 + vec2(v_p0.x, t * 0.35)), noise(q * 2.5 + vec2(t * 0.3, v_p0.x + 5.0))) - 0.5;
            q += wob * (0.08 + 0.25 * (1.0 - shown));
            float d = sd_alchemy(q, int(v_p0.y + 0.5));
            float n = noise(q * 5.0 + vec2(0.0, t * 0.6) + v_p0.x);
            float a = (smoothstep(0.06, 0.0, d) * 0.7 + exp(-d * d / 0.012) * 0.3) * (0.5 + 0.6 * n);
            a *= shown * (1.0 - smoothstep(0.8, 1.0, length(p / s)));
            vec3 c = mix(vec3(0.95, 0.92, 1.0), v_color.rgb, 0.35);
            col = vec4(c, clamp(a, 0.0, 1.0) * v_color.a);
        } else if (kind == SHAPE_FLOURISH) {            // a gilded scroll divider
            float L = h.x;
            float s = h.y;
            vec2 q = vec2(abs(p.x), p.y);
            // A lozenge in the middle, open at its heart, lines tapering out
            // from it to a bead and a curl at each end.
            float dia = max(q.x + abs(p.y) * 1.6 - s * 0.8, -(q.x + abs(p.y) * 1.6 - s * 0.4));
            float taper = clamp((q.x - s) / (L - s * 2.2), 0.0, 1.0);
            float line = max(abs(q.y) - (0.6 + s * 0.12 * (1.0 - taper)), max(s - q.x, q.x - (L - s * 1.1)));
            float curl = sd_arc(q - vec2(L - s * 0.75, -s * 0.38), s * 0.38, -1.2, 3.6, 0.8);
            float bead = length(q - vec2(s * 1.75, 0.0)) - s * 0.16;
            float d = min(min(min(dia, line), curl), min(bead, length(p) - s * 0.16));
            vec3 c = gilt(p.y / s);
            c += vec3(1.0, 0.95, 0.8) * exp(-pow((p.x / L - v_p0.x) * 5.0, 2.0)) * 0.6;
            float halo = exp(-max(d, 0.0) / 4.0) * 0.2;
            col = vec4(c, clamp(fill_aa(d) + halo, 0.0, 1.0) * v_color.a);
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
        } else if (kind == SHAPE_PARCHMENT) {           // the map's page on a dark desk
            vec2 cv = p * (v_p0.x / h.x) + vec2(270.0, 480.0);
            float f = 0.88 + 0.12 * light.a;
            vec3 desk = vec3(0.10, 0.06, 0.04) * (0.6 + 0.6 * noise(vec2(cv.x * 0.01, cv.y * 0.07)));
            // The page: its edge worn and a little torn.
            float en = noise(cv * 0.05) * 0.6 + noise(cv * 0.17) * 0.4;
            float d = sd_box(cv - vec2(270.0, 480.0), vec2(262.0, 470.0)) + (en - 0.5) * 8.0;
            vec2 q = cv * 0.0045;
            float stain = noise(q + 2.0) * 0.6 + noise(q * 2.7 + 5.0) * 0.4;
            vec3 c = mix(vec3(0.87, 0.77, 0.57), vec3(0.68, 0.51, 0.32), smoothstep(0.3, 0.85, stain));
            c *= 0.95 + 0.07 * noise(cv * vec2(0.5, 0.07));
            // Foxing: a brown spot here and there, and a ring where a cup stood.
            c = mix(c, vec3(0.6, 0.4, 0.22), dots(cv / 64.0 + 3.1, 0.22) * 0.3 * step(0.65, hash12(floor(cv / 64.0 + 3.1))));
            c = mix(c, vec3(0.55, 0.38, 0.22), fill_aa(abs(length(cv - vec2(96.0, 872.0)) - 30.0) - 1.2) * 0.25 * noise(cv * 0.08));
            // Rhumb lines from a wind rose, as on an old chart, and its circle.
            vec2 rq = cv - vec2(270.0, 470.0);
            float rr = length(rq);
            float ra = atan(rq.y, rq.x);
            float rhumb = abs(mod(ra + 0.19635, 0.3927) - 0.19635) * rr - 0.5;
            float ink = fill_aa(rhumb) * 0.09 * smoothstep(30.0, 60.0, rr) * (1.0 - smoothstep(200.0, 430.0, rr));
            ink = max(ink, fill_aa(min(abs(rr - 214.0), abs(rr - 208.0)) - 0.6) * 0.12);
            // A ruled border with knots at its corners.
            float bd = sd_box(cv - vec2(270.0, 480.0), vec2(240.0, 448.0));
            float corner = length(abs(cv - vec2(270.0, 480.0)) - vec2(240.0, 448.0));
            float heading = (1.0 - smoothstep(170.0, 190.0, abs(cv.x - 280.0))) * (1.0 - smoothstep(50.0, 60.0, cv.y));
            ink = max(ink, fill_aa(min(abs(bd) - 1.1, abs(bd + 6.0) - 0.5)) * 0.45 * (1.0 - heading));
            ink = max(ink, fill_aa(min(abs(corner - 9.0) - 1.0, corner - 3.0)) * 0.5);
            c = mix(c, vec3(0.30, 0.17, 0.08), ink);
            // Folds: one down the middle, one across.
            vec2 fd = cv - vec2(270.0, 480.0);
            c *= 1.0 - 0.07 * exp(-abs(fd.x) / 2.0) - 0.07 * exp(-abs(fd.y) / 2.0);
            c *= 1.0 + 0.04 * exp(-abs(fd.x - 3.0) / 3.0) + 0.04 * exp(-abs(fd.y - 3.0) / 3.0);
            // Aged and darker toward the edge, a little scorched at it.
            c *= mix(0.66, 1.0, smoothstep(0.0, 46.0, -d));
            c = mix(c, vec3(0.32, 0.18, 0.09), (1.0 - smoothstep(0.0, 5.0, -d)) * 0.75);
            // The room's candlelight falling on it.
            c *= mix(vec3(1.0), light.rgb, 0.2) * f;
            vec2 vq = (cv / vec2(540.0, 960.0) - 0.5) * vec2(1.1, 1.0);
            c *= mix(0.74, 1.0, smoothstep(0.8, 0.15, length(vq)));
            desk *= 1.0 - 0.7 * exp(-max(d, 0.0) / 10.0);
            col = vec4(mix(desk, c, fill_aa(d)), 1.0);
        } else if (kind == SHAPE_MEDALLION) {           // a chapter's roundel: its room, in a gilt rim
            float r = min(h.x, h.y);
            vec2 q = p / r;
            float rr = length(q);
            int theme = int(v_p0.x + 0.5);
            float state = v_p0.y;
            float lit = step(1.5, state);
            vec3 c = medallion_air(theme, q / 0.8) * (0.85 + 0.25 * noise(q * 3.0 + float(theme) * 4.0));
            vec4 em = medallion_emblem(theme, q / 0.8, r * 0.8, t);
            c = mix(c, em.rgb * (1.0 + 0.25 * lit), em.a);
            c += em.rgb * exp(-rr * 2.5) * 0.25 * lit;
            // A locked room is a faded engraving, in sepia.
            float lum = dot(c, vec3(0.3, 0.59, 0.11));
            c = mix(c, vec3(0.62, 0.48, 0.32) * (0.5 + lum), 0.85 * (1.0 - step(0.5, state)));
            float window = fill_aa((rr - 0.8) * r);
            // The rim: gilt for the open, dull bronze for the locked.
            float rim_d = (abs(rr - 0.9) - 0.1) * r;
            vec3 rim = gilt(q.y * 0.9 + (rr - 0.9) * 4.0);
            rim = mix(rim, vec3(0.45, 0.32, 0.2) * (1.0 - 0.3 * q.y), 0.8 * (1.0 - step(0.5, state)));
            rim = mix(rim, rim * 0.5, fill_aa(abs(rr - 0.8) * r - 0.5));
            c = mix(c, rim, fill_aa(rim_d));
            // A gem at its foot once the chapter's potion is made.
            vec2 gq = q - vec2(0.0, 0.9);
            float gem = fill_aa((length(gq) - 0.2) * r) * lit;
            vec3 gc = v_p1.rgb * (0.7 + 0.6 * smoothstep(0.2, -0.2, gq.y));
            gc += vec3(0.7) * fill_aa((length(gq + vec2(0.06, 0.07)) - 0.05) * r);
            c = mix(c, gc, gem);
            float body = max(max(window, fill_aa(rim_d)), gem);
            float shadow = exp(-max(length(q - vec2(0.03, 0.12)) - 1.0, 0.0) * r / 3.0) * 0.45;
            float a = max(body, shadow);
            col = vec4(c * body / max(a, 0.001), a * v_color.a);
        } else if (kind == SHAPE_GILDPATH) {            // a gilt line along a curve, ink dots past its head
            vec2 bz = sd_bezier(p, v_p0.xy, v_p0.zw, v_p1.xy);
            float w = v_p1.z;
            float head = v_p1.w;
            float len = length(v_p0.zw - v_p0.xy) + length(v_p1.xy - v_p0.zw);
            float s = bz.y * len;
            // The way still to go, in faint ink dots.
            float gap = w * 4.5;
            float dot_d = length(vec2((fract(s / gap) - 0.5) * gap, bz.x)) - w * 0.55;
            float ink = fill_aa(dot_d) * 0.55 * step(head, bz.y);
            // The way gone, in gilt, with specks twinkling along it, and a
            // bright point where it is being drawn.
            float shown = 1.0 - smoothstep(head - 0.01, head, bz.y);
            float line = fill_aa(bz.x - w * 0.7) * shown;
            vec3 g = mix(vec3(1.0, 0.9, 0.6), vec3(0.6, 0.38, 0.12), smoothstep(0.0, 1.0, bz.x / (w * 0.7)));
            float tw = speckle(vec2(s / (w * 3.0), hash12(v_p0.xy)), t, 1.3, 0.35) * shown * exp(-bz.x / w);
            vec2 hp = mix(mix(v_p0.xy, v_p0.zw, head), mix(v_p0.zw, v_p1.xy, head), head);
            float spot = exp(-length(p - hp) / (w * 1.4)) * step(0.001, head) * step(head, 0.999);
            float halo = exp(-bz.x / (w * 1.8)) * 0.25 * shown;
            float sparkle = clamp(tw + spot, 0.0, 1.0);
            vec3 c = mix(vec3(0.33, 0.2, 0.1), g, clamp(line + halo, 0.0, 1.0));
            c = mix(c, vec3(1.0, 0.97, 0.85), sparkle);
            float a = max(max(line, ink), max(halo, sparkle));
            col = vec4(c, clamp(a, 0.0, 1.0) * v_color.a);
        } else if (kind == SHAPE_PEBBLE) {              // a level stone on the map's parchment
            float r = min(h.x, h.y);
            float ang = atan(p.y, p.x);
            float d = length(p) - r * (0.9 + 0.035 * sin(ang * 3.0 + v_p0.y) + 0.02 * sin(ang * 5.0 - v_p0.y));
            vec2 u = p / r;
            float body = fill_aa(d);
            if (v_p0.x < 0.5) {
                // Still to come: a ring drawn in ink round a pale wash.
                float ring = fill_aa(abs(d + 1.4) - 1.0);
                float wash = body * 0.13 * (0.7 + 0.6 * noise(p * 0.15 + v_p0.y));
                col = vec4(0.33, 0.2, 0.1, max(ring * 0.65, wash));
            } else {
                // Walked: a glazed disc of the chapter's color in a gilt rim;
                // the current one ivory, warm at its heart.
                float z = sqrt(max(0.0, 1.0 - dot(u, u)));
                float diff = clamp(dot(normalize(vec3(u, z + 0.3)), normalize(vec3(-0.4, -0.6, 0.7))), 0.0, 1.0);
                vec3 c = v_color.rgb * (0.5 + 0.65 * diff);
                c *= 0.92 + 0.12 * noise(p * 0.2 + v_p0.y);
                c += vec3(1.0) * pow(diff, 14.0) * 0.3;
                if (v_p0.x > 1.5) c += vec3(1.0, 0.75, 0.4) * exp(-length(u) * 2.2) * (0.12 + 0.06 * sin(t * 2.4));
                c = mix(c, gilt(u.y), fill_aa(abs(d + 1.7) - 1.7));
                float shadow = exp(-max(length(p - vec2(r * 0.05, r * 0.14)) - r * 0.9, 0.0) / 3.5) * 0.4;
                float a = max(body, shadow);
                col = vec4(c * body / max(a, 0.001), a);
            }
            col.a *= v_color.a;
    #endif
    #ifdef PROGRAM_BOARD
        } else if (kind == SHAPE_FLASK_BACK) {                 // inside of a flask
            float d = sd_flask(p, h);
            float nx = clamp(p.x / (h.x * FLASK_BODY), -1.0, 1.0);
            vec3 c = v_color.rgb * (0.6 + 0.4 * sqrt(1.0 - nx * nx));
            // In at the open top: the inside of the far wall, darker.
            float open = fill_aa(sd_ellipse(p - vec2(0.0, flask_top(h)), vec2(h.x, h.x * FLASK_E) * 0.86));
            c = mix(c, v_color.rgb * 0.4, open);
            col = vec4(c, min(1.0, v_color.a * (1.0 + 0.4 * open)) * fill_aa(d + 1.0));
        } else if (kind == SHAPE_LIQUID) {                 // liquid
            // p1.w: the cap, plus a 32nd of how many layers have drained out
            // of the bottom (a siphon pouring from its tap), offset by a half;
            // less than none lifts the liquid off the bottom. Negative, the
            // liquid turns with the glass (an hourglass turning over);
            // otherwise its levels stay level however the flask is turned.
            float cap = max(floor(abs(v_p1.w)), 4.0);
            float drain = (fract(abs(v_p1.w)) - 0.5) * 32.0;
            bool rigid = v_p1.w < 0.0;
            float seg = (2.0 * h.y - FLASK_EXTRA * h.x) / cap;
            float w = liquid_w(h);
            float ry = w * FLASK_E;
            float base = liquid_base(h);
            float nx = p.x / w;
            float lifted = max(-drain, 0.0) * seg;
            if (abs(nx) < 1.0 && v_p1.x > 0.001) {
                float s = sqrt(1.0 - nx * nx);
                float ang = rigid ? 0.0 : v_misc.y;
                float ca = cos(ang);
                float sa = sin(ang);
                float S = clamp(sa / max(ca, 0.05), -6.0, 6.0);
                float AS = max(abs(S), 1e-4);
                float xm = S < 0.0 ? -p.x : p.x;
                // Upright, a point's level is its height above the bottom, plus
                // the curve of the column's front. Tipped, the levels stay level:
                // m is the level of the line through the point, and v the
                // liquid (in layers) under that line, so the layers keep their
                // amounts and the liquid gathers in the lower end.
                float u = base - p.y;
                float m = u - S * p.x;
                // The line's stretch across the column, and the front curve over it.
                float lo = max(-w, -m / AS);
                float hr = max((w - lo) * 0.5, 0.01);
                float sx = (xm - (w + lo) * 0.5) / hr;
                float sg = sqrt(max(0.0, 1.0 - sx * sx));
                float ms = m + ry * sg / ca;
                float wedge = AS * w;
                float area = ms >= wedge ? 2.0 * w * ms : (ms > -wedge ? (ms + wedge) * (ms + wedge) / (2.0 * AS) : 0.0);
                float v = area / (2.0 * w * seg);
                float lvl = v * seg;
                // Across a level line, layers per pixel: for the lines between them.
                float per_px = (ms >= wedge ? 1.0 : max((ms + wedge) / (2.0 * w * AS), 0.05)) / ca;
                // The surface: the level of the liquid's amount, a slow idle
                // drift, the slosh's tilt, and ripples from where a stream lands.
                float fill = v_p1.x * seg;
                float fa = fill * 2.0 * w;
                float msurf = fa >= 2.0 * AS * w * w ? fa / (2.0 * w) : sqrt(2.0 * AS * fa) - wedge;
                float seed = v_color.g;
                float drift = h.x * 0.035 * (0.6 * sin(nx * 1.7 + t * 1.1 + seed * 6.3) +
                                             0.4 * sin(nx * 3.9 - t * 1.6 + seed * 2.1));
                float rx = (p.x - v_color.b * h.x) / h.x;
                float ripple = v_p1.z * h.x * 0.09 * sin(rx * 7.0 - t * 15.0) * exp(-abs(rx) * 1.1);
                float wob = drift + v_color.r * p.x + ripple;
                float surface = msurf + wob;
                // The surface is seen from above: an ellipse across the column,
                // between the front curve and the back one. Tipped, it is
                // as long as the level line's stretch across the column.
                float back = m - ry * sg / ca;
                float top_d = max(surface - ms, back - surface) * ca;
                if (AS < 1e-3) top_d = sd_ellipse(vec2(p.x, p.y - (base - surface)), vec2(w, ry));
                bool on_top = ms >= surface && top_d < 0.5;
                // Inside the glass: above the bottom's curve (or the lifted
                // liquid's), below the rim.
                float bottom = u + ry * s - lifted;
                bool inside = bottom > -0.5 && p.y > flask_top(h) - 0.5;
                if (inside && (ms < surface || on_top)) {
                    float n = ceil(v_p1.x + drain - 0.001);
                    float fi = on_top ? n - 1.0 : clamp(floor(max(lvl, 0.0) / seg + drain), 0.0, n - 1.0);
                    float ci = layer_color(fi);
                    vec3 c = palette[int(ci + 0.5)].rgb;
                    bool hidden = layer_murky(fi);
                    if (hidden) {
                        // Murk: colorless smoke curling inside, one band however deep.
                        vec2 sq = p / h.x;
                        vec2 wq2 = vec2(noise(sq * 1.6 + vec2(t * 0.18, 0.0)), noise(sq * 1.6 + vec2(5.2, -t * 0.15)));
                        float n2 = noise(sq * 2.8 + wq2 * 2.2 + vec2(-t * 0.25, t * 0.1));
                        float wisp = noise(sq * vec2(6.0, 3.0) + wq2 * 3.0 + vec2(t * 0.3, 0.0));
                        c = mix(vec3(0.15, 0.13, 0.19), vec3(0.36, 0.33, 0.42), smoothstep(0.2, 0.9, n2));
                        c += vec3(0.07) * smoothstep(0.55, 0.85, wisp) * smoothstep(0.3, 0.6, n2);
                    } else {
                        c = personality(c, int(ci + 0.5), p / h.x + vec2(seed * 3.0, 0.0), t);
                        if (int(ci + 0.5) == 17 && !on_top) {
                            // The Drop: a pearl in its own glow.
                            vec2 pq = vec2(p.x, (fi + 0.5 - drain) * seg - lvl) / (seg * 0.55);
                            float dd = length(vec2(pq.x * (1.0 + max(0.0, -pq.y) * 0.9), pq.y - 0.15)) - 0.5;
                            float a0 = pq.x * 2.0 + pq.y * 1.5 + t * 0.8;
                            vec3 iri = 0.5 + 0.5 * vec3(sin(a0), sin(a0 + 2.1), sin(a0 + 4.2));
                            vec3 pearl = mix(vec3(0.97, 0.98, 1.0), iri, 0.25 + 0.4 * smoothstep(-0.3, 0.0, dd));
                            pearl += vec3(1.0) * exp(-length(pq - vec2(-0.15, -0.05)) * 9.0);
                            c += vec3(0.5, 0.85, 0.8) * exp(-max(dd, 0.0) * 4.0) * 0.35;
                            c = mix(c, pearl, fill_aa(dd * seg * 0.55));
                        }
                    }
                    float a = clamp((1.0 - abs(nx)) * w, 0.0, 1.0) * clamp(bottom + 0.5, 0.0, 1.0) *
                              clamp(p.y - flask_top(h) + 0.5, 0.0, 1.0);
                    // The surface and the column's front are shaded differently;
                    // across the line where they meet they blend over a pixel, so
                    // it doesn't step. fe: pixels above that line.
                    float fe = (ms - surface) * ca;
                    vec3 c_top = c * 1.12 + vec3(0.05) + light.rgb * 0.06 * (0.5 - (surface - m) * ca / ry);
                    vec3 c_side = c * (0.66 + 0.34 * s) + vec3(0.2);
                    float w_top = clamp(0.5 + fe, 0.0, 1.0);
                    if (on_top) {
                        // The surface catches the light: brighter, with a bright edge
                        // and the room's glow across it.
                        c = mix(c_side, c_top, w_top);
                        c += vec3(0.28) * (1.0 - smoothstep(0.0, 2.2, -top_d));
                        // Only the back edge meets air; the front edge sits on the
                        // column, so it must not thin there (the glass would show
                        // through as dark dashes).
                        if (ms - surface > surface - back) a *= fill_aa(top_d);
                    } else {
                        // Where one liquid meets another, the two colors blend over
                        // a pixel instead of stepping (a run of one color stays
                        // one band).
                        float f_in = v + drain - fi;
                        float du = (1.0 - f_in) / per_px * seg;
                        float dl = f_in / per_px * seg;
                        if (fi + 1.0 < v_p1.x + drain - 0.01 && !layers_alike(fi, fi + 1.0)) {
                            c = mix(c, layer_rgb(fi + 1.0), clamp(0.5 - du, 0.0, 0.5));
                        }
                        if (fi - 1.0 >= max(floor(drain), 0.0) && !layers_alike(fi, fi - 1.0)) {
                            c = mix(c, layer_rgb(fi - 1.0), clamp(0.5 - dl, 0.0, 0.5));
                        }
                        // Round like the glass: darker to the sides, a gleam on the left.
                        c *= 0.66 + 0.34 * s;
                        c += vec3(0.2) * smoothstep(-0.66, -0.52, nx) * (1.0 - smoothstep(-0.44, -0.3, nx));
                        // A darker line where one liquid meets another, curving
                        // round the column (smoke is all one); a run of one color
                        // reads as a single band.
                        float edge = abs(v + drain - (fi + 1.0)) / per_px * seg;
                        bool next_same = (layer_murky(fi + 1.0) ? hidden : !hidden) && (hidden || layer_color(fi + 1.0) == ci);
                        if (fi + 1.0 < v_p1.x + drain - 0.01 && !next_same) c *= 1.0 - 0.22 * (1.0 - smoothstep(0.0, 1.6, edge));
                        float surf = (surface - ms) * ca;
                        c += vec3(0.2) * (1.0 - smoothstep(0.0, 2.0, surf));
                        // Just under the surface's front line, half way to its shade.
                        if (surf < 1.0) c = mix(c, c_top + vec3(0.28), clamp(0.5 - surf, 0.0, 0.5));
                        // Now and then a bubble rises from the bottom.
                        float period = 7.0 + fract(seed * 7.13) * 5.0;
                        float cyc = t / period + seed;
                        float rise = 3.2 / period;
                        if (fract(cyc) < rise && v_misc.y == 0.0 && lifted == 0.0 && fill > seg * 0.6) {
                            float k = fract(cyc) / rise;
                            vec2 bc = vec2((hash12(vec2(floor(cyc), seed * 13.0)) - 0.5) * w * 0.9 +
                                           sin(k * 9.0) * h.x * 0.06, base + ry * 0.6 - k * (fill - h.x * 0.1));
                            // Big enough, and soft enough at the edge, not to shimmer
                            // as it crosses pixels.
                            float br = max(h.x * (0.08 + 0.04 * k), 2.5);
                            float bd = length(p - bc) - br;
                            float rim = 1.0 - smoothstep(0.0, 1.4, abs(bd + 0.5));
                            c = mix(c, c * 0.8 + vec3(0.3), rim * 0.7);
                            c += vec3(0.08) * (1.0 - smoothstep(-1.0, 1.0, bd));
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
        } else if (kind == SHAPE_LABEL) {               // a parchment label
            float d = sd_round_box(p, h - vec2(0.5, 0.5), vec4(2.5)) + 0.6 * sin(p.x * 0.7 + p.y * 1.3);
            float a = fill_aa(d);
            vec3 c = vec3(0.93, 0.86, 0.68) * (0.88 + 0.14 * noise(p * 0.35));
            c = mix(c, vec3(0.55, 0.4, 0.25), fill_aa(abs(d + 1.8) - 0.6) * 0.7);
            float band = fill_aa(abs(p.y + h.y - 3.0) - 1.3);
            c = mix(c, v_p1.rgb, band);
            col = vec4(c, a * v_color.a);
        } else if (kind == SHAPE_WOOD) {                // wood
            float d = sd_round_box(p, h, vec4(v_p0.x));
            float a = fill_aa(d);
            float grain = noise(vec2(p.x * 0.02, p.y * 0.4)) * 0.6 + noise(vec2(p.x * 0.08, p.y * 1.3)) * 0.4;
            vec3 c = mix(v_color.rgb * 0.75, v_color.rgb * 1.1, grain);
            c *= 1.0 - 0.35 * smoothstep(h.y * 0.2, h.y, p.y);
            c += vec3(0.08) * (1.0 - smoothstep(-h.y, -h.y + 3.0, p.y));
            col = vec4(c, a * v_color.a);
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
        } else if (kind == SHAPE_PLINTH) {              // the ledge a flask stands on
            col = plinth(p, h, int(v_p0.x + 0.5), v_p0.y, t);
            col.a *= v_color.a;
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
    #endif
    #ifdef PROGRAM_CELLAR
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
        } else if (kind == SHAPE_TAP) {                 // a brass tap at a siphon's foot
            float u = h.x / 0.6;
            float d = sd_tap(p, u);
            vec2 e = vec2(0.5, 0.0);
            vec2 g = vec2(sd_tap(p + e.xy, u) - sd_tap(p - e.xy, u), sd_tap(p + e.yx, u) - sd_tap(p - e.yx, u));
            col = vec4(metal(BRASS, d, g, 0.08 * u), fill_aa(d) * v_color.a);
        } else if (kind == SHAPE_KEY) {                 // a key in its metal, seen through its liquid
            float u = h.x;
            int style = int(v_p0.y + 0.5);
            float sub = v_p0.z;
            // Through the liquid it wavers a little.
            vec2 q = p + sub * 0.5 * vec2(sin(p.y * 0.4 + t * 2.1 + v_p0.w * 6.0), sin(p.x * 0.3 - t * 1.7 + v_p0.w * 3.0));
            float d = sd_key_styled(q, u, style);
            vec2 e = vec2(0.5, 0.0);
            vec2 g = vec2(sd_key_styled(q + e.xy, u, style) - sd_key_styled(q - e.xy, u, style),
                          sd_key_styled(q + e.yx, u, style) - sd_key_styled(q - e.yx, u, style));
            vec3 m = metal(v_color.rgb, d, g, max(0.07 * u, 1.2));
            // A glint sweeping along it.
            float sweep = (q.x + q.y * 0.8) / u - mix(-1.8, 1.8, v_p0.x);
            m += vec3(1.0, 0.96, 0.85) * exp(-sweep * sweep * 8.0) * sin(v_p0.x * 3.14159265);
            // The liquid tints it and dims it a little, and its edge.
            vec3 liq = v_p1.rgb;
            m = mix(m, m * (0.6 + 0.55 * liq), 0.3 * sub);
            vec3 edge = mix(vec3(0.05, 0.04, 0.03), liq * 0.15, sub * 0.5);
            vec4 c = vec4(edge, 0.85 * fill_aa(d - 1.5));
            c = over(c, m, fill_aa(d));
            col = vec4(c.rgb, c.a * v_color.a);
        } else if (kind == SHAPE_DOOR) {                // a double door in its frame; p0.x: swung open 0..1
            float T = door_frame(h);
            float Wl = h.x - T;
            float yTop = -h.y + T * 1.4;
            int style = int(v_p0.y + 0.5);
            float open = v_p0.x;
            float th = open * 1.45;
            float cw = cos(th);
            float sw = sin(th);
            vec3 warm = vec3(1.0, 0.8, 0.48);
            // The light behind spills out as it opens.
            float spill = sin(min(open * 1.6, 1.0) * 3.14159265) * step(abs(p.x), Wl) * step(yTop, p.y) * step(p.y, h.y);
            vec4 res = vec4(warm, 0.22 * spill);
            // The frame: two posts and a lintel, its top seen from above.
            float frame = max(sd_box(p, h), -sd_box(p - vec2(0.0, (yTop + h.y) * 0.5 + 2.0), vec2(Wl, (h.y - yTop) * 0.5 + 2.0)));
            vec3 fc = v_color.rgb * 0.62 * (0.8 + 0.35 * noise(p * vec2(0.4, 0.06)));
            fc *= 0.8 + 0.3 * smoothstep(T * 0.5, -T * 0.5, min(abs(p.x) - Wl - T * 0.5, p.y - yTop + T * 0.7));
            res = over(res, fc, fill_aa(frame));
            float topf = sd_box(p - vec2(0.0, -h.y - T * 0.45), vec2(h.x + T * 0.25, T * 0.45));
            res = over(res, v_color.rgb * (1.0 + 0.2 * noise(p * vec2(0.08, 0.5))) + light.rgb * 0.12, fill_aa(topf));
            // The two leaves, each turning on its hinge toward us as it opens:
            // narrower, darker, and its free edge lower.
            for (int k = 0; k < 2; k++) {
                float sgn = k == 0 ? -1.0 : 1.0;
                float s = (Wl - sgn * p.x) / max(Wl * cw, 0.01);
                float y = p.y - s * sw * Wl * 0.4;
                float inside = min(min(s, 1.0 - s) * Wl * cw, min(y - yTop, h.y - y));
                if (inside > -1.0) {
                    vec3 lc = door_face(vec2(sgn * Wl * (1.0 - s), y), h, Wl, yTop, style, v_p1.rgb, 1.0 - open, t);
                    res = over(res, lc * (1.0 - 0.5 * sw), clamp(inside + 0.5, 0.0, 1.0));
                }
            }
            col = vec4(res.rgb, res.a * v_color.a);
        } else if (kind == SHAPE_CLOTH && v_p0.x > 0.5) {   // a curtain: velvet folds on a rod, a gold fringe
            // p0.y: drawn aside 0..1, each drape gathering toward its own side
            // and its inner corner lifting.
            float open = v_p0.y;
            float top = -h.y;
            float W = h.x;
            float ax = abs(p.x);
            float keep = 1.0 - 0.8 * open;
            float o = (W - ax) / keep;                  // from the drape's outer edge, as it hangs shut
            float xl = sign(p.x) * (W - o);             // where that is on the drape shut
            float hem = h.y - 4.0 + 1.5 * sin(xl * 0.6) - open * clamp(o / W, 0.0, 1.0) * h.y * 0.35;
            float d = max(max(ax - W, o - W), max(top - p.y, p.y - hem));
            float sway = 0.5 * sin(p.y * 0.04 + t * 0.4 + v_p0.z * 5.0);
            float folds = 0.5 + 0.5 * sin(xl * 0.5 + sway);
            vec3 c = v_color.rgb * (0.4 + 0.75 * folds) * (0.92 + 0.08 * noise(vec2(xl, p.y) * 0.4));
            c += vec3(1.0, 0.75, 0.7) * v_color.rgb * 0.5 * pow(folds, 8.0);           // velvet's sheen on the crests
            c *= 1.0 - 0.5 * (1.0 - smoothstep(0.0, 3.0, W - o));                        // where the two drapes meet
            c *= 0.85 + 0.15 * smoothstep(top, top + h.y, p.y);
            vec3 thread = vec3(0.95, 0.78, 0.42);
            c = mix(c, thread * 0.85, fill_aa(abs(p.y - hem + 3.0) - 1.6));
            vec4 res = over(vec4(0.0), c, fill_aa(d));
            // Little tassels along the hem.
            float tx = (fract(xl / 7.0) - 0.5) * 7.0;
            float tas = sd_round_box(vec2(tx, p.y - hem - 2.5), vec2(1.2, 2.5), vec4(1.2)) + step(W - 2.0, ax);
            res = over(res, thread * 0.75, fill_aa(tas) * (1.0 - fill_aa(d)) * step(o, W));
            // The valance, scalloped, a gold braid on its edge; it stays as the drapes go.
            float val = top + W * 0.55 + 3.0 * abs(sin(p.x * 0.28));
            float vd = max(ax - W - 1.0, max(top - p.y, p.y - val));
            vec3 vc = v_color.rgb * (0.72 + 0.3 * abs(sin(p.x * 0.28))) * (0.9 + 0.1 * noise(p * 0.5));
            vc = mix(vc, thread * 0.95, fill_aa(abs(p.y - val + 1.5) - 1.3));
            res = over(res, vc, fill_aa(vd));
            // The rod, brass, with a knob at each end.
            float ry = top + 1.5;
            float rd = min(sd_segment(p, vec2(-W - 4.0, ry), vec2(W + 4.0, ry)) - 2.2,
                           min(sd_circle(p - vec2(-W - 6.0, ry), 3.6), sd_circle(p - vec2(W + 6.0, ry), 3.6)));
            float ny = clamp((p.y - ry) / 3.6, -1.0, 1.0);
            res = over(res, BRASS * (1.15 - 0.6 * ny) + vec3(0.3) * exp(-pow((ny + 0.45) * 3.0, 2.0)), fill_aa(rd));
            col = vec4(res.rgb, res.a * v_color.a);
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
    #endif
    #ifdef PROGRAM_GARDEN
        } else if (kind == SHAPE_LANTERN) {             // a lantern on its crook, dark until lit
            float u = h.x / 1.3;
            float lit = v_p0.x;
            float flare = v_p0.y;
            float glowk = lit * (0.82 + 0.18 * light.a) + flare;
            // Unlit, its panes pulse faintly, waiting.
            float wait = (1.0 - min(lit, 1.0)) * (0.5 + 0.5 * sin(t * 1.9 + v_p0.z));
            float pane = sd_box(p, vec2(0.4 * u, 0.4 * u));
            float d = sd_lantern(p, u);
            vec2 e = vec2(0.5, 0.0);
            vec2 g = vec2(sd_lantern(p + e.xy, u) - sd_lantern(p - e.xy, u), sd_lantern(p + e.yx, u) - sd_lantern(p - e.yx, u));
            float dc = sd_crook(p, u, v_p1.x * u, v_p1.y * u);
            vec2 gc = vec2(sd_crook(p + e.xy, u, v_p1.x * u, v_p1.y * u) - sd_crook(p - e.xy, u, v_p1.x * u, v_p1.y * u),
                           sd_crook(p + e.yx, u, v_p1.x * u, v_p1.y * u) - sd_crook(p - e.yx, u, v_p1.x * u, v_p1.y * u));
            // Its light round it: warm when lit, a cold glimmer while it waits.
            float edge = clamp(min(h.x + v_misc.z - abs(p.x), h.y + v_misc.z - abs(p.y)) / max(v_misc.z, 1.0), 0.0, 1.0);
            float near = exp(-max(pane, 0.0) / (0.45 * u)) * (1.0 - fill_aa(pane)) * edge * edge;
            vec3 hc = mix(vec3(0.55, 0.72, 1.0), vec3(1.0, 0.78, 0.42), clamp(glowk, 0.0, 1.0));
            vec4 c = vec4(hc, clamp(near * (glowk * 0.75 + (0.2 + 0.15 * wait) * (1.0 - min(lit, 1.0))), 0.0, 1.0));
            // The crook, behind, its post fading out down behind the flask.
            float fade = 1.0 - smoothstep(v_p1.y * u - 0.6 * u, v_p1.y * u, p.y);
            c = over(c, vec3(0.06, 0.04, 0.02), fill_aa(dc - 0.05 * u) * 0.7 * fade);
            c = over(c, metal(BRASS * 0.85, dc, gc, 0.05 * u), fill_aa(dc) * fade);
            // A dark edge round the lantern so it stands out on any table.
            c = over(c, vec3(0.06, 0.04, 0.02), fill_aa(d - 0.06 * u) * 0.8);
            // The panes: dark glass with a cold glint, lit warm from inside.
            float inner = clamp(1.0 - length((p - vec2(0.0, 0.1 * u)) / u) * 1.1, 0.0, 1.0);
            vec3 glass = mix(vec3(0.11, 0.12, 0.2) + vec3(0.05, 0.07, 0.14) * wait, vec3(1.0, 0.72, 0.32),
                             clamp(glowk * (0.4 + 0.8 * inner), 0.0, 1.0));
            float glint = 1.0 - smoothstep(0.0, 0.05 * u, abs(p.x + 0.18 * u + p.y * 0.35));
            glass += vec3(0.3, 0.38, 0.5) * glint * (1.0 - 0.7 * min(lit, 1.0)) * step(abs(p.y), 0.36 * u);
            c = over(c, glass, fill_aa(pane));
            // The candle and its wick.
            float wax = sd_round_box(p - vec2(0.0, 0.29 * u), vec2(0.085 * u, 0.1 * u), vec4(0.025 * u));
            c = over(c, vec3(0.92, 0.86, 0.72) * (0.7 + 0.3 * min(glowk, 1.0)), fill_aa(wax));
            float wick = sd_segment(p, vec2(0.0, 0.2 * u), vec2(0.02 * u, 0.1 * u)) - 0.022 * u;
            c = over(c, vec3(0.1, 0.07, 0.05), fill_aa(wick));
            if (lit > 0.01) {
                vec4 fl = flame(p - vec2(0.0, 0.14 * u), 0.12 * u * (1.0 + flare * 0.8), light.a, v_p0.z, t);
                c = over(c, fl.rgb, fl.a * min(lit, 1.0) * fill_aa(pane));
            }
            c = over(c, metal(BRASS * 1.05, d, g, 0.06 * u), fill_aa(d));
            col = vec4(c.rgb, c.a * v_color.a);
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
    #endif
    #ifdef PROGRAM_FORGE
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
    #endif
    #ifdef PROGRAM_ROOM
        } else if (kind == SHAPE_BACKDROP) {                // the room
            vec2 cv = p * (v_p0.y / h.x) + vec2(270.0, 480.0);      // canvas units
            vec3 c = room(cv, t);
            // Candlelight from the back shelf and the work below, flickering.
            float f = 0.8 + 0.2 * light.a;
            float glow = exp(-pow(length((cv - vec2(270.0, 880.0)) * vec2(0.9, 1.6)) / 520.0, 2.0) * 2.0);
            c += light.rgb * 0.22 * glow * f;
            c += light.rgb * 0.1 * exp(-length((cv - vec2(270.0, 90.0)) * vec2(0.7, 1.4)) / 160.0) * f;
            // In a level (p0.w), the middle where the board stands is calmer:
            // darker, and its colors drawn toward the air's, so the flasks
            // stand out against it and the room's life keeps to the edges.
            if (v_p0.w > 0.0) {
                vec2 bd = abs(cv - vec2(270.0, 480.0)) - vec2(190.0, 300.0);
                float board = 1.0 - smoothstep(-60.0, 90.0, length(max(bd, 0.0)) + min(max(bd.x, bd.y), 0.0));
                float lum = dot(c, vec3(0.3, 0.5, 0.2));
                c = mix(c, mix(vec3(lum), c, 0.65) * 0.52, board * v_p0.w);
            }
            float vig = smoothstep(1.2, 0.3, length((cv / vec2(540.0, 960.0) - 0.5) * vec2(1.3, 1.0)));
            c *= mix(0.5, 1.0, vig);
            col = vec4(c, 1.0);
    #endif
        }
        if (col.a <= 0.001) discard;
        result = vec4(col.rgb * col.a, col.a);
    }
    """;
