// The title screen, with its flask simmering over a candle, and the chapter
// map: the six rooms along a winding path, each with its fifteen level
// stones and the potion that lights when the chapter is done.
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

// The simmering flask's liquid drifts from one color to the next.
fn title_liquid() -> float4 {
    let cycle: i64[5] = [8, 1, 3, 5, 6];
    let x = now / 7.0;
    let k = x as! i64;
    let f = ease((x - k) * 3.0 - 2.0);       // hold, then blend over the last third
    mix4(palette_color(cycle[k % 5], save.color_safe), palette_color(cycle[(k + 1) % 5], save.color_safe), f)
}

fn small_flask(out: Inst[>..]&, pos: float2, colors: const i64[:], hx: f32) {
    var b = Bottle { seg: [0; 8], .. };
    for c, k in colors { b.seg[k] = c as u8; }
    b.n = colors.len as u8;
    let half = bottle_half(hx, CAP);
    draw_flask(out, -1, b, pos - v2(0.0, half.y), half, 0.0, b.n, 0.0, 0.0, gold(1.0), false);
}

fn draw_home(out: Inst[>..]&) {
    text_shadowed(0, VW * 0.5, 96.0, "Alchemist's", TextStyle.Heading, gold(0.95), Align.Center);
    text_shadowed(0, VW * 0.5, 148.0, "Sort", TextStyle.Title, gold(1.0), Align.Center);

    // The workbench: a table, candles, a few finished potions, and the
    // flask simmering in the middle.
    let table: f32 = 620.0;
    let liquid = title_liquid();
    let center = v2(VW * 0.5, 432.0);
    let half = v2(96.0, 146.0);
    let sphere = center + v2(0.0, half.y - half.x * 0.92 - 2.0);
    glow(out, sphere, v2(210.0, 190.0), 1.0, with_alpha(liquid, 0.16 + 0.04 * look.light.w));
    glow(out, v2(VW * 0.5, table), v2(250.0, 60.0), 1.0, float4 { 1.0, 0.7, 0.35, 0.10 + 0.05 * look.light.w });
    var plank = inst(Shape.Wood, v2(VW * 0.5, table + 9.0), v2(240.0, 10.0), float4 { 0.45, 0.28, 0.16, 1.0 });
    plank.p0 = float4 { 3.0, 0.0, 0.0, 0.0 };
    glow(out, v2(VW * 0.5, table + 26.0), v2(240.0, 12.0), 0.9, float4 { 0.0, 0.0, 0.0, 0.45 });
    out.push(plank);
    small_flask(out, v2(112.0, table), [1, 1, 1, 1], 15.0);
    small_flask(out, v2(156.0, table), [7, 7, 7], 13.0);
    small_flask(out, v2(390.0, table), [3, 3], 13.0);
    small_flask(out, v2(432.0, table), [9, 9, 9, 9], 15.0);
    candle(out, v2(56.0, table), 58.0, 0.7);
    candle(out, v2(486.0, table), 44.0, 2.9);
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
    flask.p0 = float4 { 0.58, 0.0, 0.0, 0.0 };
    out.push(flask);
    var steam = inst(Shape.Steam, center - v2(0.0, half.y + 70.0), v2(48.0, 78.0), white(1.0));
    steam.p0 = float4 { 1.7, 0.0, 0.0, 0.0 };
    out.push(steam);

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

var map_page = 0;

fn open_map() {
    map_page = chapter_of(save.level);
    screen_id = Screen.Map;
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

fn route_pos(k: i64) -> float2 { v2(58.0 + k * 70.67, 150.0 + sin(k * 1.4 + 0.5) as f32 * 16.0) }

// Stone k of 15: three rows, winding back and forth.
fn stone_pos(k: i64) -> float2 {
    let row = k / 5;
    let col = if row % 2 == 0 { k % 5 } else { 4 - k % 5 };
    v2(90.0 + col * 90.0, 285.0 + row * 145.0 + sin(k * 2.1) as f32 * 8.0)
}

let POTION_AT = float2 { 270.0, 760.0 };

// A dotted line along a curve.
fn dotted(out: Inst[>..]&, a: float2, ctrl: float2, b: float2, color: float4, gap: f32) {
    let len = length(ctrl - a) + length(b - ctrl);
    let n = max(2, (len / gap) as! i64);
    for k in 1..n {
        let t = k as f32 / n;
        let p = lerp2(lerp2(a, ctrl, t), lerp2(ctrl, b, t), t);
        glow(out, p, v2(2.6, 2.6), 0.5, color);
    }
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

fn draw_map(out: Inst[>..]&) {
    let page = chapter_info(map_page);
    if round_button(out, 0, v2(48.0, 52.0), 26.0, Icon.Home, "", 0, true) { screen_id = Screen.Home; }
    text_shadowed(0, VW * 0.5 + 10.0, 46.0, page.name, TextStyle.Heading, gold(1.0), Align.Center);
    let sub = if page.last < 0 { str("The endless work  ·  levels ", page.first, " onward") }
              else { str("Chapter ", map_page + 1, "  ·  levels ", page.first, " to ", page.last) };
    text(0, VW * 0.5 + 10.0, 84.0, sub, TextStyle.Tiny, white(0.7), Align.Center);

    // The rooms along their path.
    for k in chapter_count() {
        let p = route_pos(k);
        if k + 1 < chapter_count() {
            let q = route_pos(k + 1);
            dotted(out, p, (p + q) * float2 { 0.5, 0.5 } + v2(0.0, 14.0), q,
                   gold(if chapter_open(k + 1) { 0.5 } else { 0.15 }), 9.0);
        }
    }
    for k in chapter_count() {
        let p = route_pos(k);
        let open = chapter_open(k);
        let done = chapter_done(k);
        let c = chapter_color(k);
        if k == map_page { glow(out, p, v2(34.0, 34.0), 0.9, gold(0.35)); }
        var stone = inst(Shape.Pebble, p, v2(21.0, 21.0), if open { float4 { 0.42, 0.34, 0.48, 1.0 } } else { white(1.0) });
        stone.p0 = float4 { if open { 1.0 } else { 0.0 }, k * 1.7, 0.0, 0.0 };
        stone.misc.z = 6.0;
        out.push(stone);
        var vial = inst(Shape.Vial, p + v2(0.0, 1.0), v2(6.0, 13.0), c);
        vial.p0 = float4 { if done { 1.0 } else if open { 0.25 } else { 0.0 }, 0.0, 0.0, 0.0 };
        vial.misc.z = 10.0;
        out.push(vial);
        if k == map_page { ring(out, p, 23.0, 2.0, gold(0.95)); }
        if clicked(p, v2(24.0, 24.0)) && k != map_page {
            map_page = k;
            note_press(p);
            play(Sfx.Select);
        }
    }

    // The level stones, winding down to the chapter's potion.
    let first = page_first(map_page);
    let c = chapter_color(map_page);
    for k in 15 {
        let a = stone_pos(k);
        let b = if k < 14 { stone_pos(k + 1) } else { POTION_AT - v2(0.0, 60.0) };
        let turn = k % 5 == 4;
        let ctrl = if k == 14 { v2(a.x + 30.0, b.y - 10.0) }
                   else if turn { v2(if (k / 5) % 2 == 0 { a.x + 75.0 } else { a.x - 75.0 }, (a.y + b.y) * 0.5) }
                   else { (a + b) * float2 { 0.5, 0.5 } + v2(0.0, if k % 2 == 0 { 16.0 } else { -16.0 }) };
        let n = first + k;
        dotted(out, a, ctrl, b, gold(if n < save.level { 0.6 } else { 0.18 }), 10.0);
    }
    for k in 15 {
        let n = first + k;
        let p = stone_pos(k);
        let done = n < save.level;
        let current = n == save.level;
        let r: f32 = if k == 14 && page.last > 0 { 31.0 } else { 27.0 };
        if current {
            let pulse = 0.5 + 0.5 * sin(now * 3.0) as f32;
            glow(out, p, v2(r + 18.0 + pulse * 6.0, r + 18.0 + pulse * 6.0), 1.0, gold(0.25 + 0.25 * pulse));
            ring(out, p, r + 5.0 + pulse * 3.0, 2.0, gold(0.5 + 0.4 * pulse));
        }
        let tint = if current { float4 { 1.0, 0.95, 0.86, 1.0 } } else { mix4(c, gold(1.0), 0.35) };
        var s = inst(Shape.Pebble, p, v2(r, r), tint);
        s.p0 = float4 { if current { 2.0 } else if done { 1.0 } else { 0.0 }, n * 0.77, 0.0, 0.0 };
        s.misc.z = 8.0;
        let k2 = press_squash(p);
        s.half = v2(r * (1.0 + 0.08 * k2), r * (1.0 - 0.1 * k2));
        out.push(s);
        let d = difficulty_of(n);
        if d != Difficulty.Normal {
            ring(out, p, r - 3.0, 2.0, with_alpha(difficulty_color(d), if done || current { 0.9 } else { 0.4 }));
        }
        let ink = if current { float4 { 0.25, 0.13, 0.05, 1.0 } } else if done { white(1.0) } else { white(0.4) };
        if done { text(0, p.x + 1.0, p.y + 2.0, str(n), TextStyle.Label, float4 { 0.0, 0.0, 0.0, 0.4 }, Align.Center); }
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
    let lit = chapter_done(map_page);
    let pot_half = bottle_half(26.0, CAP);
    var b = Bottle { seg: [0; 8], .. };
    let col = CHAPTER_POTION[clamp(map_page, 0, 6)];
    for s in 4 { b.seg[s] = col as u8; }
    b.n = 4;
    let fill: f32 = if page.last < 0 { 2.0 + sin(now * 0.5) as f32 * 0.3 } else { done_here * 4.0 / 15.0 };
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
        map_page = max(0, map_page - 1);
    }
    if arrow_button(out, v2(VW - 62.0, POTION_AT.y), true, map_page + 1 < chapter_count()) || gfx::key_pressed("Right") {
        map_page = min(chapter_count() - 1, map_page + 1);
    }
    if button(out, 0, v2(VW * 0.5, 880.0), v2(130.0, 28.0), str("Level ", save.level), float4 { 0.2, 0.55, 0.38, 1.0 }, true) {
        start_campaign(save.level);
    }
    if now < message_until { text(0, VW * 0.5, 932.0, message, TextStyle.Small, white(0.85), Align.Center); }
}
