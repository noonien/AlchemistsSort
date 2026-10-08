// The workbench around the puzzle: a room for each chapter, candlelight
// that flickers in the glass, motes drifting in the air, and a back shelf
// that lights a little bottle for each color completed.
//
// Part of the game in main.goose: it reads the game's state (the screen,
// the level, the board) as main.goose's other parts do.

import std;
import vec;
import math;
import core.board;
import core.campaign;
import .draw;
import .palette;

let THEMES = 6;

// The room for a level: its chapter's, the Great Work cycling through them.
fn scene_theme(level: i64) -> i64 {
    let c = chapter_info(chapter_of(level));
    if c.theme < THEMES { return c.theme; }
    (level - c.first) % THEMES
}

// The room behind the current screen.
fn current_theme() -> i64 {
    if screen_id == Screen.Map { return map_theme(); }
    if screen_id == Screen.Play {
        if mode == PlayMode.Campaign || pending_load { return scene_theme(level_number); }
        if mode == PlayMode.Seed { return scene_theme(play_like); }
        return 0;
    }
    scene_theme(save.level)
}

// The candlelight's color in each room.
fn theme_light(theme: i64) -> float4 {
    match theme {
        1 => float4 { 0.70, 0.84, 1.0, 1.0 },      // frost cellar: icy
        2 => float4 { 1.0, 0.62, 0.30, 1.0 },      // glassworks: the furnace
        3 => float4 { 0.72, 0.78, 1.0, 1.0 },      // observatory: moonlight
        4 => float4 { 0.72, 0.95, 0.82, 1.0 },     // greenhouse: moon through leaves
        5 => float4 { 1.0, 0.50, 0.30, 1.0 },      // athanor: red gold
        _ => float4 { 1.0, 0.74, 0.44, 1.0 },      // apothecary: candles
    }
}

// How brightly the candles burn now, 0..1: a few beating waves.
fn candle_flicker(t: f64) -> f32 {
    let f = 0.62 + 0.18 * sin(t * 7.3) + 0.12 * sin(t * 13.1 + 1.0) + 0.08 * sin(t * 23.7 + 2.0);
    clamp(f, 0.0, 1.0) as f32
}

// The uniform's light: the room's color and the flicker.
fn scene_light(theme: i64, t: f64) -> float4 {
    let c = theme_light(theme);
    float4 { c.x, c.y, c.z, candle_flicker(t) }
}

fn draw_scene(out: Inst[>..]&, theme: i64) {
    var bg = inst(Shape.Backdrop, float2 { VW * 0.5, VH * 0.5 }, float2 { VW * 0.5 + 400.0, VH * 0.5 + 200.0 },
                  rgba(1.0, 1.0, 1.0, 1.0));
    bg.p0 = float4 { theme, VW * 0.5 + 400.0, 0.0, 0.0 };
    out.push(bg);
    draw_motes(out, theme);
}

// What floats in each room's air, moved by time alone so a slow frame rate
// only makes it step.
fn draw_motes(out: Inst[>..]&, theme: i64) {
    let t = now;
    for k in 16 {
        let fx = (k * 0.618034) % 1.0;
        let speed = 6.0 + k % 5;
        let span: f64 = VH + 40.0;
        var x: f64 = fx * VW;
        var y = 0.0;
        var size: f32 = 2.5;
        var c = float4 { 0.98, 0.82, 0.45, 0.25 };
        match theme {
            1 => {      // snow, falling
                x += sin(t * 0.5 + k) * 24.0;
                y = (t * (speed * 2.0) + k * 97.0) % span - 20.0;
                size = 2.0 + (k % 3);
                c = float4 { 0.85, 0.93, 1.0, 0.45 };
            },
            2 => {      // sparks from the furnace, rising fast
                x += sin(t * 1.3 + k * 2.0) * 14.0;
                y = VH - (t * (speed * 7.0) + k * 131.0) % span;
                size = 1.6;
                c = float4 { 1.0, 0.6, 0.2, 0.7 * clamp(y / VH, 0.0, 1.0) as f32 };
            },
            3 => {      // starlight dust, slow and twinkling
                x += sin(t * 0.15 + k) * 30.0;
                y = VH - (t * speed * 0.6 + k * 97.0) % span;
                c = float4 { 0.8, 0.85, 1.0, (0.12 + 0.2 * (0.5 + 0.5 * sin(t * 2.0 + k * 1.7))) as f32 };
            },
            4 => {      // fireflies wandering
                x = fx * VW + sin(t * 0.31 + k * 1.9) * 50.0;
                y = 200.0 + ((k * 0.381966) % 1.0) * 700.0 + sin(t * 0.43 + k) * 40.0;
                size = 3.0;
                let pulse = 0.5 + 0.5 * sin(t * 1.7 + k * 2.3);
                c = float4 { 0.8, 1.0, 0.45, (0.1 + 0.5 * pulse * pulse) as f32 };
            },
            5 => {      // embers rising
                x += sin(t * 0.7 + k) * 22.0;
                y = VH - (t * (speed * 3.0) + k * 97.0) % span;
                size = 2.2;
                c = float4 { 1.0, 0.4, 0.15, 0.55 * clamp(y / VH + 0.2, 0.0, 1.0) as f32 };
            },
            _ => {      // dust in the candlelight
                x += sin(t * 0.2 + k) * 30.0;
                y = VH - (t * speed + k * 97.0) % span;
            },
        }
        glow(out, float2 { x as f32, y as f32 }, float2 { size, size }, 0.9, c);
        if theme == 4 || theme == 2 { glow(out, float2 { x as f32, y as f32 }, float2 { size * 4.0, size * 4.0 }, 1.0, with_alpha(c, 0.25)); }
    }
}

// --- the back shelf --------------------------------------------------------------------

let SHELF_Y: f32 = 117.0;

var shelf_colors: i64[..16];        // the level's colors, in order
var shelf_lit_at: f64[16];          // when each color's bottle lit, or -1

// Takes the level's colors from the board as dealt.
fn reset_back_shelf(b: Board) {
    shelf_colors.clear();
    var seen: bool[16] = [false; 16];
    for i in b.count {
        let bt = b.bottles[i];
        for k in bt.n as i64 {
            let c: i64 = bt.seg[k];
            if c > 0 && c < 16 && !seen[c] { seen[c] = true; }
        }
    }
    for c in 1..16 { if seen[c] && shelf_colors.len < 16 { shelf_colors.push(c); } }
    for &t in shelf_lit_at { t = -1.0; }
}

// Lights the bottle of each color that has a completed flask.
fn update_back_shelf(b: Board) {
    for c, k in shelf_colors {
        var done = false;
        for i in b.count { if b.bottles[i].done && b.bottles[i].seg[0] == c { done = true; } }
        if done && shelf_lit_at[k] < 0.0 { shelf_lit_at[k] = now; }
        if !done { shelf_lit_at[k] = -1.0; }
    }
}

// Where bottle k of n stands: half on each side of the candles.
fn vial_pos(k: i64, n: i64) -> float2 {
    let left = (n + 1) / 2;
    let step: f32 = 17.0;
    if k < left { return float2 { 128.0 - (left - 1 - k) * step, SHELF_Y - 11.0 }; }
    float2 { 412.0 + (k - left) * step, SHELF_Y - 11.0 }
}

fn draw_back_shelf(out: Inst[>..]&) {
    glow(out, float2 { VW * 0.5, SHELF_Y + 6.0 }, float2 { 250.0, 6.0 }, 0.9, float4 { 0.0, 0.0, 0.0, 0.35 });
    var plank = inst(Shape.Wood, float2 { VW * 0.5, SHELF_Y + 2.0 }, float2 { 252.0, 3.5 }, float4 { 0.36, 0.22, 0.13, 0.9 });
    plank.p0 = float4 { 2.0, 0.0, 0.0, 0.0 };
    out.push(plank);
    candle(out, float2 { 156.0, SHELF_Y - 1.0 }, 34.0, 1.3);
    candle(out, float2 { 384.0, SHELF_Y - 1.0 }, 28.0, 4.1);
    let n = shelf_colors.len;
    for c, k in shelf_colors {
        let p = vial_pos(k, n);
        let lit_t = shelf_lit_at[k];
        var lit: f32 = 0.0;
        if lit_t >= 0.0 { lit = clamp((now - lit_t) / 0.5, 0.0, 1.0) as f32; }
        var v = inst(Shape.Vial, p, float2 { 5.0, 11.0 }, palette_color(c, save.color_safe));
        v.p0 = float4 { lit, 0.0, 0.0, 0.0 };
        v.misc.z = 8.0;
        out.push(v);
        // A flare as it lights.
        if lit_t >= 0.0 && now - lit_t < 0.8 {
            let k2 = (1.0 - (now - lit_t) / 0.8) as f32;
            spark(out, p, 14.0 * k2 + 4.0, with_alpha(palette_color(c, save.color_safe), k2));
        }
    }
}

fn back_shelf_lively() -> bool {
    for t in shelf_lit_at { if t >= 0.0 && now - t < 0.8 { return true; } }
    false
}
