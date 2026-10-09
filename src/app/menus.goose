// The title screen, a study at dusk with its flask simmering before a
// turning astrolabe, and the chapter map, a page of an old chart: the rooms
// in roundels along a gilt line, each chapter's fifteen level stones and the
// potion that lights when the chapter is done.
//
// Part of the game in main.goose: it uses its buttons, its state and its
// way of starting levels.

import std;
import vec;
import math;
import gfx;
import core.board;
import core.campaign;
import .draw;
import .shaders;
import .palette;
import .text;
import .sfx;

// Each chapter's potion color (Great Work last).
let CHAPTER_POTION: const i64[7] = [5, 6, 2, 8, 4, 1, 3];

fn chapter_color(i: i64) -> float4 { palette_color(CHAPTER_POTION[clamp(i, 0, 6)], save.color_safe) }

fn chapter_done(i: i64) -> bool {
    let c = chapter_info(i);
    c.last > 0 && save.level > c.last
}

fn chapter_open(i: i64) -> bool { chapter_info(i).first <= save.level }

// --- the title screen ----------------------------------------------------------------------

// A study at dusk: an astrolabe turning slowly behind the simmering flask,
// motes of light drifting up, steam that now and then draws an alchemical
// sign, bubbles that pop with a glint, and once in a while a spark leaping
// from the flask to a rune that flares. Everything is moved by the clock
// alone, so a slow frame rate only makes it step.

let FLASK_AT = float2 { 270.0, 432.0 };
let FLASK_HALF = float2 { 96.0, 146.0 };
let FLASK_FILL: f32 = 0.58;
let BENCH_Y: f32 = 620.0;
let ASTROLABE_R: f32 = 228.0;
let RUNE_COUNT = 24;
let RUNE_RING: f32 = 0.80;          // the runes' band, in the astrolabe's radii

// A number in 0..1 that looks random, the same for the same x.
fn hash01(x: f64) -> f64 {
    let s = sin(x * 12.9898 + 4.1) * 43758.5453;
    s - floor(s)
}

// The clock the shader sees (look.screen.z), for things that must line up
// with what it turns.
fn shader_time() -> f64 { now % 1000.0 }

// The round body's center, as Shape.Alembic draws it.
fn flask_sphere() -> float2 { FLASK_AT + v2(0.0, FLASK_HALF.y - FLASK_HALF.x * 0.92 - 2.0) }

// The simmering flask's liquid drifts from one color to the next.
fn title_liquid() -> float4 {
    let cycle: i64[5] = [8, 1, 3, 5, 6];
    let x = now / 7.0;
    let k = x as! i64;
    let f = ease((x - k) * 3.0 - 2.0);       // hold, then blend over the last third
    mix4(palette_color(cycle[k % 5], save.color_safe), palette_color(cycle[(k + 1) % 5], save.color_safe), f)
}

fn small_flask(out: Inst[>..]&, pos: float2, colors: const i64[:], hx: f32) {
    var b = Bottle { .. };
    for c, k in colors { b.seg[k] = c as u8; }
    b.n = colors.len as u8;
    let half = bottle_half(hx, CAP);
    draw_flask(out, -1, b, pos - v2(0.0, half.y), half, 0.0, b.n, 0.0, 0.0, gold(1.0), false);
}

// Where rune k of the turning band is at shader time t (it turns as the
// shader turns it).
fn rune_pos(k: i64, t: f64) -> float2 {
    let a = (k + 0.5) * TAU / RUNE_COUNT + t * 0.02;
    flask_sphere() + v2(cos(a) as f32, sin(a) as f32) * float2 { ASTROLABE_R * RUNE_RING, ASTROLABE_R * RUNE_RING }
}

// Every so often a spark leaps from the flask's mouth to a rune in the upper
// half of the band, and the rune flares: which rune, how far the spark has
// gone (0..1, or -1 when there is none) and the flare 0..1.
let SPARK_EVERY: f64 = 13.0;
let SPARK_FLIGHT: f64 = 1.3;

fn rune_event() -> i64, f32, f32 {
    let t = shader_time();
    let cycle = floor((t + 4.0) / SPARK_EVERY);
    let u = t + 4.0 - cycle * SPARK_EVERY;
    // Aim where the rune will be when the spark gets there.
    let arrive = cycle * SPARK_EVERY - 4.0 + SPARK_FLIGHT;
    let aim = -PI * 0.5 + (hash01(cycle) - 0.5) * 2.2;
    let cell = floor((aim - arrive * 0.02) / TAU * RUNE_COUNT);
    let k = ((cell as! i64) % RUNE_COUNT + RUNE_COUNT) % RUNE_COUNT;
    let flight: f32 = if u < SPARK_FLIGHT { (u / SPARK_FLIGHT) as f32 } else { -1.0 };
    let flare = if u < SPARK_FLIGHT - 0.1 { 0.0 } else { clamp((1.0 - (u - SPARK_FLIGHT) / 2.6), 0.0, 1.0) as f32 };
    return k, flight, flare * flare;
}

fn draw_astrolabe(out: Inst[>..]&) {
    let sphere = flask_sphere();
    let rune, flight, flare = rune_event();
    var a = inst(Shape.Astrolabe, sphere, v2(ASTROLABE_R, ASTROLABE_R), white(0.55));
    a.p0 = float4 { rune, flare, (BENCH_Y - sphere.y) / ASTROLABE_R, 0.0 };
    a.misc.z = 0.0;
    out.push(a);
    if flare > 0.0 {
        let p = rune_pos(rune, shader_time());
        glow(out, p, v2(34.0, 34.0), 1.0, gold(0.3 * flare));
    }
}

// The spark's flight from the flask's mouth to its rune, over the flask.
fn draw_rune_spark(out: Inst[>..]&) {
    let rune, flight, flare = rune_event();
    if flight < 0.0 { return; }
    let t = shader_time();
    let cycle = floor((t + 4.0) / SPARK_EVERY);
    let from = FLASK_AT - v2(0.0, FLASK_HALF.y + 4.0);
    let to = rune_pos(rune, cycle * SPARK_EVERY - 4.0 + SPARK_FLIGHT);
    let ctrl = v2((from.x + to.x) * 0.5, min(from.y, to.y) - 90.0);
    let head = ease(flight as f64 * 1.2);
    curve(out, Shape.Beam, from, ctrl, to, 2.2, head, float4 { 1.0, 0.85, 0.55, 0.85 });
    let p = lerp2(lerp2(from, ctrl, head), lerp2(ctrl, to, head), head);
    spark(out, p, 9.0, white(0.9));
}

// Motes of light drifting up through the room, each living a while.
fn draw_arcane_motes(out: Inst[>..]&) {
    let tints: float4[3] = [float4 { 1.0, 0.82, 0.45, 1.0 }, float4 { 0.78, 0.62, 1.0, 1.0 },
                            float4 { 0.55, 0.95, 0.85, 1.0 }];
    for k in 26 {
        let h1 = hash01(k * 1.37);
        let h2 = hash01(k * 2.71 + 5.0);
        let h3 = hash01(k * 3.97 + 9.0);
        let life = (now * (0.045 + 0.04 * h1) + h2) % 1.0;
        let x = 30.0 + h3 * (VW - 60.0) + sin(now * 0.3 + k * 1.7) * 18.0;
        let y = 330.0 + h1 * 280.0 - life * 190.0;
        let twinkle = 0.6 + 0.4 * sin(now * (1.5 + h2 * 2.0) + k);
        let a = (sin(life * PI) * twinkle) as f32;
        let c = tints[k % 3];
        let p = v2(x as f32, y as f32);
        glow(out, p, v2(9.0, 9.0), 1.0, with_alpha(c, 0.12 * a));
        glow(out, p, v2(1.8, 1.8), 0.8, with_alpha(c, 0.8 * a));
    }
}

// Bubbles reaching the surface and popping, a glint and a fleck or two
// thrown up.
fn draw_bubble_pops(out: Inst[>..]&) {
    let sphere = flask_sphere();
    let r = FLASK_HALF.x * 0.92;
    let surface = sphere.y + r * (1.0 - 2.0 * FLASK_FILL);
    for k in 4 {
        let period = 2.3 + k * 0.7;
        let x = now + k * 1.3;
        let cycle = floor(x / period);
        let ph = ((x - cycle * period) / period) as f32;
        if ph > 0.3 { continue; }
        let u = ph / 0.3;
        let at = v2(sphere.x + ((hash01(cycle * 4.0 + k) - 0.5) * 120.0) as f32, surface);
        ring(out, at, 2.0 + 7.0 * u, 1.2, white(0.5 * (1.0 - u)));
        spark(out, at - v2(0.0, 4.0 + 6.0 * u), 6.0 * (1.0 - u) + 1.0, with_alpha(gold(1.0), 0.9 * (1.0 - u)));
        for j in 2 {
            let dx = (j * 2 - 1) * (3.0 + 6.0 * u);
            glow(out, at + v2(dx, -18.0 * u + 30.0 * u * u), v2(1.6, 1.6), 0.6, white(0.7 * (1.0 - u)));
        }
    }
}

// Steam that, every few seconds, draws one of the old signs and lets it go.
let ALCHEMY_SIGNS = 6;

fn draw_steam_sign(out: Inst[>..]&, liquid: float4) {
    let every: f64 = 9.0;
    let cycle = floor(now / every);
    let u = (now - cycle * every) / every;
    let shown = sin(u * PI);
    let mouth = FLASK_AT - v2(0.0, FLASK_HALF.y);
    var w = inst(Shape.Wisp, mouth - v2(0.0, (30.0 + u * 34.0) as f32), v2(34.0, 34.0), liquid);
    w.p0 = float4 { (cycle % 7.0) as f32 * 1.7, ((cycle as! i64) % ALCHEMY_SIGNS) as f32, (shown * shown) as f32, 0.0 };
    w.misc.z = 0.0;
    out.push(w);
}

// The title in gilt: a shadow, a bronze edge under it, and each letter in
// gold that a slow gleam passes over now and then.
fn gilded_text(out: Inst[>..]&, x: f32, y: f32, s: const u8[:], style: TextStyle, gleam_x: f32) {
    let w = text_width(style, s);
    let left = x - w * 0.5;
    text(0, x + 2.0, y + 4.0, s, style, float4 { 0.0, 0.0, 0.0, 0.55 }, Align.Center);
    text(0, x, y + 1.8, s, style, float4 { 0.45, 0.25, 0.08, 1.0 }, Align.Center);
    for i in s.len {
        let at = left + text_width(style, s[..i]);
        let mid = at + text_width(style, s[i..i + 1]) * 0.5;
        let d = (mid - gleam_x) / 30.0;
        let k = exp(-d * d) as f32;
        text(0, at, y, s[i..i + 1], style, mix4(float4 { 0.98, 0.80, 0.42, 1.0 }, float4 { 1.0, 0.98, 0.9, 1.0 }, k),
             Align.Left);
    }
}

fn draw_title(out: Inst[>..]&) {
    // A darker hush behind the words, and a faint gold air about them.
    glow(out, v2(VW * 0.5, 114.0), v2(230.0, 92.0), 1.0, float4 { 0.0, 0.0, 0.0, 0.35 });
    glow(out, v2(VW * 0.5, 132.0), v2(150.0, 46.0), 1.0, gold(0.07 + 0.02 * look.light.w));
    let every: f64 = 8.0;
    let u = (now % every) / every;
    let span = text_width(TextStyle.Grand, "Sort") * 0.5 + 160.0;
    let gleam = if u < 0.3 { VW * 0.5 - span + (u / 0.3) as f32 * span * 2.0 } else { -1000.0 };
    gilded_text(out, VW * 0.5, 76.0, "Alchemist's", TextStyle.Heading, gleam - 40.0);
    gilded_text(out, VW * 0.5, 138.0, "Sort", TextStyle.Grand, gleam);
    var f = inst(Shape.Flourish, v2(VW * 0.5, 190.0), v2(118.0, 8.0), white(0.95));
    f.p0 = float4 { if u < 0.3 { (u / 0.3) as f32 * 2.6 - 1.3 } else { -9.0 }, 0.0, 0.0, 0.0 };
    out.push(f);
    // A star glinting on a letter after the gleam has passed.
    if u > 0.32 && u < 0.42 {
        let k = sin((u - 0.32) / 0.1 * PI) as f32;
        let cycle = floor(now / every);
        let x = VW * 0.5 + ((hash01(cycle) - 0.5) * 140.0) as f32;
        spark(out, v2(x, 108.0), 12.0 * k, white(0.9 * k));
    }
}

fn draw_home(out: Inst[>..]&) {
    var room = inst(Shape.Sanctum, v2(VW * 0.5, VH * 0.5), v2(VW * 0.5 + 400.0, VH * 0.5 + 200.0), white(1.0));
    room.p0 = float4 { VW * 0.5 + 400.0, 0.0, 0.0, 0.0 };
    out.push(room);
    draw_astrolabe(out);
    draw_arcane_motes(out);
    draw_title(out);

    // The workbench: a table, candles, a few finished potions, and the
    // flask simmering in the middle.
    let table = BENCH_Y;
    let liquid = title_liquid();
    let center = FLASK_AT;
    let half = FLASK_HALF;
    let sphere = flask_sphere();
    glow(out, sphere, v2(230.0, 210.0), 1.0, with_alpha(liquid, 0.16 + 0.04 * look.light.w));
    glow(out, v2(VW * 0.5, table), v2(250.0, 60.0), 1.0, float4 { 1.0, 0.7, 0.35, 0.10 + 0.05 * look.light.w });
    var plank = inst(Shape.Wood, v2(VW * 0.5, table + 9.0), v2(240.0, 10.0), float4 { 0.45, 0.28, 0.16, 1.0 });
    plank.p0 = float4 { 3.0, 0.0, 0.0, 0.0 };
    glow(out, v2(VW * 0.5, table + 26.0), v2(240.0, 12.0), 0.9, float4 { 0.0, 0.0, 0.0, 0.45 });
    out.push(plank);
    small_flask(out, v2(112.0, table), [1, 1, 1, 1], 15.0);
    small_flask(out, v2(156.0, table), [7, 7, 7], 13.0);
    small_flask(out, v2(390.0, table), [3, 3], 13.0);
    small_flask(out, v2(432.0, table), [9, 9, 9, 9], 15.0);
    // Candles, each with a pool of light about its flame.
    let candles: float4[2] = [float4 { 56.0, 58.0, 0.7, 0.0 }, float4 { 486.0, 44.0, 2.9, 0.0 }];
    for c in candles {
        let tip = v2(c.x, table - c.y - 8.0);
        glow(out, tip, v2(70.0, 80.0), 1.0, float4 { 1.0, 0.65, 0.3, 0.07 + 0.04 * look.light.w });
        candle(out, v2(c.x, table), c.y, c.z);
    }
    // A brass stand over the burner.
    let ring_y = sphere.y + 70.0;
    for side in 2 {
        let sx: f32 = if side == 0 { -1.0 } else { 1.0 };
        var leg = inst(Shape.Rect, v2(VW * 0.5 + sx * 62.0, (ring_y + table) * 0.5), v2(2.5, (table - ring_y) * 0.5 + 4.0),
                       float4 { 0.62, 0.46, 0.24, 1.0 });
        leg.misc.y = sx * -0.28;
        leg.p0 = float4 { 2.0, 0.0, 0.0, 0.0 };
        out.push(leg);
    }
    candle(out, v2(VW * 0.5, table), 34.0, 5.3);
    glow(out, v2(VW * 0.5, sphere.y + 82.0), v2(40.0, 24.0), 1.0, float4 { 1.0, 0.55, 0.2, 0.35 + 0.15 * look.light.w });
    rect(out, v2(VW * 0.5, ring_y - 4.0), v2(66.0, 3.0), 3.0, float4 { 0.70, 0.52, 0.27, 1.0 });
    var flask = inst(Shape.Alembic, center, half, liquid);
    flask.p0 = float4 { FLASK_FILL, 0.0, 0.0, 0.0 };
    out.push(flask);
    draw_bubble_pops(out);
    var steam = inst(Shape.Steam, center - v2(0.0, half.y + 70.0), v2(48.0, 78.0), white(1.0));
    steam.p0 = float4 { 1.7, 0.0, 0.0, 0.0 };
    out.push(steam);
    draw_steam_sign(out, liquid);
    draw_rune_spark(out);

    // Where the player is, and the way in.
    let ch = chapter_of(save.level);
    text(0, VW * 0.5, 672.0, str(chapter_info(ch).name, "  ·  Level ", save.level), TextStyle.Small,
         white(0.75), Align.Center);
    if button(out, 0, v2(VW * 0.5, 728.0), v2(130.0, 30.0), "Play", float4 { 0.2, 0.55, 0.38, 1.0 }, true) {
        open_map();
    }
    let y: f32 = 836.0;
    if round_button(out, 0, v2(VW * 0.5 - 75.0, y), 32.0, Icon.Seed, "Seed", 0, true) { screen_id = Screen.Seed; }
    if round_button(out, 0, v2(VW * 0.5 + 75.0, y), 32.0, Icon.Gear, "Settings", 0, true) { screen_id = Screen.Settings; }
    if now < message_until { text(0, VW * 0.5, 912.0, message, TextStyle.Small, white(0.85), Align.Center); }
}

// --- the chapter map ---------------------------------------------------------------------------

// A page of an old chart on the desk: the rooms in roundels along a gilt
// line at the top, and below them the chapter's fifteen level stones
// winding down to its potion. The way already walked is gilt, and draws
// itself in when the page opens; the way to come is faint ink.

var map_page = 0;
var map_opened_at: f64 = 0.0;      // when the page's gilt starts drawing itself in

// Ink on the parchment, and its paler wash.
let MAP_INK = float4 { 0.20, 0.10, 0.04, 1.0 };
let MAP_INK_PALE = float4 { 0.34, 0.2, 0.09, 1.0 };

fn open_map() { open_map_at(save.level); }

// The map, open at the chapter of level n: its gilt draws in once the ink
// between the screens has cleared.
fn open_map_at(n: i64) {
    map_page = chapter_of(n);
    if screen_id != Screen.Map { map_opened_at = now + T_COVER + T_REVEAL * 0.4; }
    else { map_opened_at = now; }
    screen_id = Screen.Map;
}

// Turns to chapter k's page.
fn turn_map_page(k: i64) {
    if k == map_page { return; }
    map_page = k;
    map_opened_at = now;
}

fn map_theme() -> i64 {
    let c = chapter_info(map_page);
    if c.last < 0 { return scene_theme(max(save.level, c.first)); }
    c.theme
}

// The first level shown on a page: the Great Work shows the stretch around
// the player's level.
fn page_first(i: i64) -> i64 {
    let c = chapter_info(i);
    if c.last < 0 { return max(c.first, save.level - 7); }
    c.first
}

fn route_pos(k: i64) -> float2 { v2(58.0 + k * 70.67, 150.0 + sin(k * 1.4 + 0.5) as f32 * 14.0) }

// Stone k of 15: three rows, winding back and forth.
fn stone_pos(k: i64) -> float2 {
    let row = k / 5;
    let col = if row % 2 == 0 { k % 5 } else { 4 - k % 5 };
    v2(90.0 + col * 90.0, 285.0 + row * 145.0 + sin(k * 2.1) as f32 * 8.0)
}

let POTION_AT = float2 { 270.0, 760.0 };

// How far the gilt of step k has drawn in, 0..1, once the page is open.
fn gilt_drawn(k: i64) -> f32 { clamp((now - map_opened_at - k * 0.07) / 0.16, 0.0, 1.0) as f32 }

// A gilt line along a curve, drawn up to `head`; past it, faint ink dots.
fn gild_path(out: Inst[>..]&, a: float2, ctrl: float2, b: float2, width: f32, head: f32) {
    curve(out, Shape.GildPath, a, ctrl, b, width, head, white(1.0));
}

fn arrow_button(out: Inst[>..]&, center: float2, right: bool, enabled: bool) -> bool {
    let r: f32 = 26.0;
    let hover = in_rect(pointer, center, v2(r, r)) && enabled;
    let k = press_squash(center);
    let rr = r * (1.0 - 0.1 * k);
    if hover { glow(out, center, v2(r + 16.0, r + 16.0), 0.8, gold(0.2)); }
    glow(out, center + v2(0.0, 4.0), v2(r + 6.0, r + 6.0), 0.6, float4 { 0.0, 0.0, 0.0, 0.4 });
    let base = if enabled { float4 { 0.30, 0.20, 0.42, 1.0 } } else { float4 { 0.22, 0.2, 0.26, 0.6 } };
    gradient_rect(out, center, v2(rr, rr), rr, mix4(base, white(1.0), if hover { 0.25 } else { 0.1 }),
                  mix4(base, float4 { 0.0, 0.0, 0.0, 1.0 }, 0.3));
    ring(out, center, rr, 2.5, gold(if enabled { 0.8 } else { 0.3 }));
    var i = inst(Shape.Icon, center, v2(rr * 0.5, rr * 0.5), if enabled { gold(1.0) } else { white(0.3) });
    i.p0 = float4 { icon_index(Icon.Back), 0.0, 0.0, 0.0 };
    if right { i.misc.y = PI; }
    out.push(i);
    let hit = enabled && clicked(center, v2(r, r));
    if hit { note_press(center); }
    hit
}

// The rooms in their roundels along the top, joined by the way between them.
fn draw_chapter_route(out: Inst[>..]&) {
    for k in chapter_count() - 1 {
        let p = route_pos(k);
        let q = route_pos(k + 1);
        let ctrl = (p + q) * float2 { 0.5, 0.5 } + v2(0.0, 14.0);
        gild_path(out, p, ctrl, q, 2.4, if chapter_open(k + 1) { gilt_drawn(k) } else { 0.0 });
    }
    for k in chapter_count() {
        let p = route_pos(k);
        let open = chapter_open(k);
        let done = chapter_done(k);
        let r: f32 = 23.0;
        if k == map_page {
            let pulse = 0.5 + 0.5 * sin(now * 2.0) as f32;
            glow(out, p, v2(40.0 + 3.0 * pulse, 40.0 + 3.0 * pulse), 1.0, float4 { 1.0, 0.75, 0.35, 0.35 + 0.15 * pulse });
        }
        if done { glow(out, p, v2(34.0, 34.0), 1.0, with_alpha(chapter_color(k), 0.3 + 0.08 * look.light.w)); }
        var m = inst(Shape.Medallion, p, v2(r, r), white(1.0));
        m.p0 = float4 { chapter_info(k).theme, if done { 2.0 } else if open { 1.0 } else { 0.0 }, 0.0, 0.0 };
        m.p1 = chapter_color(k);
        m.misc.z = 6.0;
        out.push(m);
        if k == map_page { ring(out, p, r + 4.0, 2.0, float4 { 0.62, 0.36, 0.08, 0.95 }); }
        if clicked(p, v2(r + 2.0, r + 2.0)) && k != map_page {
            turn_map_page(k);
            note_press(p);
            play(Sfx.Select);
        }
    }
}

// Dust drifting in the candlelight over the page.
fn draw_map_dust(out: Inst[>..]&) {
    for k in 14 {
        let h1 = hash01(k * 1.91 + 2.0);
        let h2 = hash01(k * 3.13 + 7.0);
        let life = (now * (0.03 + 0.03 * h1) + h2) % 1.0;
        let x = 40.0 + hash01(k * 5.3) * (VW - 80.0) + sin(now * 0.2 + k) * 24.0;
        let y = 260.0 + h1 * 640.0 - life * 160.0;
        let a = (sin(life * PI) * (0.6 + 0.4 * sin(now * 1.7 + k * 2.0))) as f32;
        let p = v2(x as f32, y as f32);
        glow(out, p, v2(8.0, 8.0), 1.0, float4 { 1.0, 0.85, 0.5, 0.10 * a });
        glow(out, p, v2(1.6, 1.6), 0.8, float4 { 1.0, 0.9, 0.6, 0.6 * a });
    }
}

// The level the player is on: a glow breathing, a ripple going out, two
// motes circling.
fn draw_current_stone(out: Inst[>..]&, p: float2, r: f32) {
    let pulse = 0.5 + 0.5 * sin(now * 2.4) as f32;
    glow(out, p, v2(r + 22.0 + pulse * 6.0, r + 22.0 + pulse * 6.0), 1.0, float4 { 1.0, 0.72, 0.3, 0.30 + 0.2 * pulse });
    let ripple = (now * 0.5 % 1.0) as f32;
    ring(out, p, r + 4.0 + ripple * 18.0, 1.6, float4 { 0.7, 0.42, 0.1, 0.7 * (1.0 - ripple) });
    for j in 2 {
        let a = now * 1.3 + j * PI;
        let at = p + v2(cos(a) as f32 * (r + 9.0), sin(a) as f32 * (r + 9.0) * 0.85);
        glow(out, at, v2(6.0, 6.0), 1.0, float4 { 1.0, 0.8, 0.4, 0.5 });
        spark(out, at, 4.5, float4 { 1.0, 0.95, 0.8, 0.9 });
    }
}

fn draw_map(out: Inst[>..]&) {
    var bg = inst(Shape.Parchment, v2(VW * 0.5, VH * 0.5), v2(VW * 0.5 + 400.0, VH * 0.5 + 200.0), white(1.0));
    bg.p0 = float4 { VW * 0.5 + 400.0, 0.0, 0.0, 0.0 };
    out.push(bg);
    let page = chapter_info(map_page);
    if round_button(out, 0, v2(48.0, 52.0), 26.0, Icon.Home, "", 0, true) { screen_id = Screen.Home; }
    // The page's heading, in ink pressed into the paper.
    glow(out, v2(VW * 0.5 + 10.0, 62.0), v2(170.0, 44.0), 1.0, float4 { 1.0, 0.93, 0.76, 0.45 });
    text(0, VW * 0.5 + 10.0, 47.0, page.name, TextStyle.Heading, float4 { 1.0, 0.95, 0.82, 0.5 }, Align.Center);
    text(0, VW * 0.5 + 10.0, 46.0, page.name, TextStyle.Heading, MAP_INK, Align.Center);
    let sub = if page.last < 0 { str("The endless work  ·  levels ", page.first, " onward") }
              else { str("Chapter ", map_page + 1, "  ·  levels ", page.first, " to ", page.last) };
    text(0, VW * 0.5 + 10.0, 84.0, sub, TextStyle.Tiny, MAP_INK_PALE, Align.Center);

    draw_map_dust(out);
    draw_chapter_route(out);
    var f = inst(Shape.Flourish, v2(VW * 0.5, 206.0), v2(150.0, 8.0), white(0.9));
    f.p0 = float4 { (sin(now * 0.25) * 1.4) as f32, 0.0, 0.0, 0.0 };
    out.push(f);

    // The level stones, winding down to the chapter's potion.
    let first = page_first(map_page);
    let c = chapter_color(map_page);
    let lit = chapter_done(map_page);
    for k in 15 {
        let a = stone_pos(k);
        let b = if k < 14 { stone_pos(k + 1) } else { POTION_AT - v2(0.0, 60.0) };
        let turn = k % 5 == 4;
        let ctrl = if k == 14 { v2(a.x + 30.0, b.y - 10.0) }
                   else if turn { v2(if (k / 5) % 2 == 0 { a.x + 75.0 } else { a.x - 75.0 }, (a.y + b.y) * 0.5) }
                   else { (a + b) * float2 { 0.5, 0.5 } + v2(0.0, if k % 2 == 0 { 16.0 } else { -16.0 }) };
        let n = first + k;
        let walked = if k < 14 { n < save.level } else { lit };
        gild_path(out, a, ctrl, b, 3.0, if walked { gilt_drawn(k + 2) } else { 0.0 });
    }
    for k in 15 {
        let n = first + k;
        let p = stone_pos(k);
        let done = n < save.level;
        let current = n == save.level;
        let r: f32 = if k == 14 && page.last > 0 { 31.0 } else { 27.0 };
        if current { draw_current_stone(out, p, r); }
        let tint = if current { float4 { 1.0, 0.95, 0.84, 1.0 } } else { mix4(c, gold(1.0), 0.2) };
        var s = inst(Shape.Pebble, p, v2(r, r), tint);
        s.p0 = float4 { if current { 2.0 } else if done { 1.0 } else { 0.0 }, n * 0.77, 0.0, 0.0 };
        s.misc.z = 8.0;
        let k2 = press_squash(p);
        s.half = v2(r * (1.0 + 0.08 * k2), r * (1.0 - 0.1 * k2));
        out.push(s);
        let d = difficulty_of(n);
        if d != Difficulty.Normal {
            ring(out, p, r - 4.0, 2.0, with_alpha(difficulty_color(d), if done || current { 0.9 } else { 0.5 }));
        }
        let ink = if current { float4 { 0.3, 0.15, 0.05, 1.0 } } else if done { white(1.0) } else { with_alpha(MAP_INK, 0.6) };
        if done { text(0, p.x + 1.0, p.y + 2.0, str(n), TextStyle.Label, float4 { 0.0, 0.0, 0.0, 0.45 }, Align.Center); }
        text(0, p.x, p.y, str(n), TextStyle.Label, ink, Align.Center);
        if clicked(p, v2(r, r)) {
            if n <= save.level {
                note_press(p);
                play(Sfx.Select);
                start_campaign(n);
            } else {
                say(str("Brew level ", save.level, " first."), 2.0);
                play(Sfx.Denied);
            }
        }
    }

    // The chapter's potion: it fills as the chapter goes, and lights when done.
    let done_here = if page.last > 0 { clamp(save.level - page.first, 0, 15) } else { 0 };
    let pot_half = bottle_half(26.0, CAP);
    var b = Bottle { .. };
    let col = CHAPTER_POTION[clamp(map_page, 0, 6)];
    for s in 4 { b.seg[s] = col as u8; }
    b.n = 4;
    let fill: f32 = if page.last < 0 { 2.0 + sin(now * 0.5) as f32 * 0.3 } else { done_here * 4.0 / 15.0 };
    glow(out, POTION_AT + v2(0.0, pot_half.y + 10.0), v2(70.0, 12.0), 1.0, float4 { 0.2, 0.1, 0.03, 0.35 });
    if lit {
        glow(out, POTION_AT, v2(90.0, 110.0), 1.0, with_alpha(c, 0.35 + 0.1 * look.light.w));
        spark(out, POTION_AT + v2(sin(now * 0.7) as f32 * 20.0, -30.0 + cos(now * 0.9) as f32 * 20.0), 7.0, white(0.8));
    }
    var stand = inst(Shape.Wood, POTION_AT + v2(0.0, pot_half.y + 6.0), v2(54.0, 7.0), float4 { 0.45, 0.28, 0.16, 1.0 });
    stand.p0 = float4 { 3.0, 0.0, 0.0, 0.0 };
    out.push(stand);
    draw_flask(out, -1, b, POTION_AT, pot_half, 0.0, fill, 0.0, if lit { 0.8 } else { 0.0 }, c, false);
    if lit { draw_completion(out, -1, b, POTION_AT, pot_half); }

    if arrow_button(out, v2(62.0, POTION_AT.y), false, map_page > 0) || gfx::key_pressed("Left") {
        turn_map_page(max(0, map_page - 1));
    }
    if arrow_button(out, v2(VW - 62.0, POTION_AT.y), true, map_page + 1 < chapter_count()) || gfx::key_pressed("Right") {
        turn_map_page(min(chapter_count() - 1, map_page + 1));
    }
    if button(out, 0, v2(VW * 0.5, 880.0), v2(130.0, 28.0), str("Level ", save.level), float4 { 0.2, 0.55, 0.38, 1.0 }, true) {
        start_campaign(save.level);
    }
    if now < message_until { text(0, VW * 0.5, 932.0, message, TextStyle.Small, MAP_INK, Align.Center); }
}
