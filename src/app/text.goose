// Text, through the ui module's font rendering. There are two text layers so
// that an overlay panel can cover the board's labels: the board's text is
// drawn between the board and the overlay, the overlay's on top of all.
//
// Positions are in the game's virtual units (a 540 x 960 portrait canvas);
// the ui's scale turns them into pixels.

import std;
import vec;
import os;
import gfx;
import ui;

enum TextStyle {
    Title,      // Cinzel, large
    Heading,    // Cinzel, medium
    Label,      // Cinzel, small
    Body,       // Raleway, for sentences
    Small,      // Raleway, small
    Tiny,       // Raleway, for badges
}

let ALL_STYLES: const TextStyle[6] = [TextStyle.Title, TextStyle.Heading, TextStyle.Label, TextStyle.Body,
                                      TextStyle.Small, TextStyle.Tiny];

fn style_index(f: TextStyle) -> i64 {
    match f { Title => 0, Heading => 1, Label => 2, Body => 3, Small => 4, Tiny => 5 }
}

fn style_size(f: TextStyle) -> f32 {
    match f { Title => 54.0, Heading => 34.0, Label => 24.0, Body => 22.0, Small => 18.0, Tiny => 14.0 }
}

fn style_is_title(f: TextStyle) -> bool {
    match f { Title, Heading, Label => true, Body, Small, Tiny => false }
}

enum Align { Left, Center, Right }

var atlas = ui::FontAtlas { 0 };
var fonts: ui::Font[6];
var contexts: ui::Context[2];
var text_scale: f32 = 0.0;
var text_offset = float2_0;     // the canvas's top-left corner in pixels, over the scale

fn font_path(dir: const u8[:], name: const u8[:]) -> u8[>..] {
    if dir.len == 0 { return str(name); }
    str(dir, "/", name)
}

// Loads the fonts from `dir` (falling back to the built-in font) and makes
// the two layers.
fn init_text(dir: const u8[:]) -> bool {
    atlas = ui::create_font_atlas();
    if atlas.id == 0 { return false; }
    let title = font_path(dir, "Cinzel-Bold.ttf");
    let body = font_path(dir, "Raleway-Bold.ttf");
    let have_title = file_exists(title);
    let have_body = file_exists(body);
    if !have_title || !have_body {
        write_stderr(str("alchemists-sort: fonts not found in '", dir,
                         "', using the built-in font (set ALCHEMIST_SORT_DATA)\n"));
    }
    assert(ALL_STYLES.len == fonts.len);
    for f, k in ALL_STYLES {
        assert(style_index(f) == k);    // the list is in index order, every style once
        let size = style_size(f);
        let path = if style_is_title(f) { title[..] } else { body[..] };
        let have = if style_is_title(f) { have_title } else { have_body };
        let i = style_index(f);
        fonts[i] = if have { ui::add_font_from_file(atlas, path, size) }
                   else { ui::add_default_font(atlas, size) };
        if fonts[i].id == 0 { fonts[i] = ui::add_default_font(atlas, size); }
    }
    if !ui::bake(atlas) { return false; }
    for l in 2 {
        contexts[l] = ui::create_context(fonts[style_index(TextStyle.Body)]);
        if contexts[l].id == 0 { return false; }
        var style = ui::style(contexts[l]);
        style.window.fixed_background = ui::style_item_hide();
        style.window.border = 0.0;
        style.window.padding = float2 { 0.0, 0.0 };
        ui::set_style(contexts[l], style);
    }
    true
}

// Matches the text to the canvas: `scale` pixels per unit, the canvas's
// top-left at `offset` pixels. Re-bakes the glyphs when the scale changes.
fn set_text_scale(scale: f32, offset: float2) {
    text_offset = float2 { offset.x / scale, offset.y / scale };
    if abs(scale - text_scale) < 0.001 { return; }
    text_scale = scale;
    ui::bake(atlas, scale);
    for l in 2 { ui::set_scale(contexts[l], scale); }
}

fn begin_text(layer: i64, screen: int2) {
    let c = contexts[layer];
    ui::input_begin(c);
    ui::input_end(c);
    let w = screen.x / text_scale;
    let h = screen.y / text_scale;
    ui::begin(c, if layer == 0 { "text0" } else { "text1" }, ui::rect(0.0, 0.0, w, h),
              ui::WINDOW_NO_INPUT | ui::WINDOW_NO_SCROLLBAR);
}

fn end_text(layer: i64) {
    ui::end(contexts[layer]);
    ui::render(contexts[layer]);
}

fn text_width(font: TextStyle, s: const u8[:]) -> f32 { ui::text_width(fonts[style_index(font)], s) }

fn line_height(font: TextStyle) -> f32 { style_size(font) * 1.25 }

fn ucolor(c: float4) -> ui::Color {
    ui::Color { (clamp(c.x, 0.0, 1.0) * 255.0) as! u8, (clamp(c.y, 0.0, 1.0) * 255.0) as! u8,
                (clamp(c.z, 0.0, 1.0) * 255.0) as! u8, (clamp(c.w, 0.0, 1.0) * 255.0) as! u8 }
}

// Draws `s` with its vertical middle at y, aligned at x.
fn text(layer: i64, x: f32, y: f32, s: const u8[:], font: TextStyle, color: float4, align: Align) {
    if s.len == 0 || color.w <= 0.0 { return; }
    let w = text_width(font, s);
    let h = style_size(font) * 1.3;
    let left = match align { Left => x, Center => x - w * 0.5, Right => x - w };
    ui::draw_text(contexts[layer], ui::rect(left + text_offset.x, y - h * 0.5 + text_offset.y, w + 4.0, h),
                  s, fonts[style_index(font)], ui::Color { 0, 0, 0, 0 }, ucolor(color));
}

// Text with a soft dark shadow under it, for words over busy art.
fn text_shadowed(layer: i64, x: f32, y: f32, s: const u8[:], font: TextStyle, color: float4, align: Align) {
    let shadow = float4 { 0.0, 0.0, 0.0, color.w * 0.55 };
    text(layer, x + 1.5, y + 2.0, s, font, shadow, align);
    text(layer, x, y, s, font, color, align);
}

// Wraps `s` into lines no wider than `width`, centered on x, starting at y.
// Returns the height used.
fn text_wrapped(layer: i64, x: f32, y: f32, width: f32, s: const u8[:], font: TextStyle, color: float4) -> f32 {
    text_block(layer, x, y, width, s, font, color, Align.Center, true)
}

// The same, aligned at x as `align` says; `draw` false only measures.
fn text_block(layer: i64, x: f32, y: f32, width: f32, s: const u8[:], font: TextStyle, color: float4, align: Align,
              draw: bool) -> f32 {
    var line: u8[>..] = [];
    var lines = 0;
    let lh = line_height(font);
    var trial: u8[>..] = [];
    each_word(s) {
        trial.clear();
        trial.append(line);
        if trial.len > 0 { trial.push(' '); }
        trial.append(it);
        if line.len > 0 && text_width(font, trial) > width {
            if draw { text(layer, x, y + lines * lh, line, font, color, align); }
            lines++;
            line.clear();
            line.append(it);
        } else {
            line.clear();
            line.append(trial);
        }
    };
    if line.len > 0 {
        if draw { text(layer, x, y + lines * lh, line, font, color, align); }
        lines++;
    }
    lines * lh
}
