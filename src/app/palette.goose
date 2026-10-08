// The potion colors, in two palettes: the usual one and one chosen to stay
// apart under the common kinds of color blindness (which also turns on a
// symbol per color). Indices match the level format's letters.

import std;
import vec;
import .draw;

let COLOR_NAMES: const u8[:][15] = ["", "Ruby", "Amber", "Sun", "Lime", "Emerald", "Sky", "Sapphire",
                                    "Violet", "Rose", "Umber", "Pearl", "Slate", "Teal", "Olive"];

let NORMAL_PALETTE: const f32[3][15] = [
    [0.0, 0.0, 0.0],
    [0.88, 0.17, 0.22],     // ruby
    [0.98, 0.56, 0.13],     // amber
    [0.99, 0.86, 0.22],     // sun
    [0.63, 0.88, 0.22],     // lime
    [0.13, 0.62, 0.31],     // emerald
    [0.33, 0.82, 0.96],     // sky
    [0.17, 0.33, 0.88],     // sapphire
    [0.58, 0.28, 0.88],     // violet
    [0.98, 0.53, 0.76],     // rose
    [0.52, 0.32, 0.17],     // umber
    [0.95, 0.94, 0.90],     // pearl
    [0.45, 0.49, 0.56],     // slate
    [0.05, 0.53, 0.56],     // teal
    [0.52, 0.52, 0.12],     // olive
];

// Built from the Okabe-Ito set and spread out in lightness; with symbols.
let SAFE_PALETTE: const f32[3][15] = [
    [0.0, 0.0, 0.0],
    [0.84, 0.37, 0.0],      // vermillion
    [0.90, 0.62, 0.0],      // orange
    [0.94, 0.89, 0.26],     // yellow
    [0.60, 0.80, 0.55],     // pale green
    [0.0, 0.62, 0.45],      // bluish green
    [0.34, 0.71, 0.91],     // sky blue
    [0.0, 0.45, 0.70],      // blue
    [0.47, 0.27, 0.62],     // purple
    [0.80, 0.47, 0.65],     // reddish purple
    [0.40, 0.24, 0.10],     // dark brown
    [0.97, 0.97, 0.97],     // white
    [0.30, 0.30, 0.30],     // dark gray
    [0.10, 0.20, 0.45],     // navy
    [0.70, 0.70, 0.70],     // light gray
];

fn palette_color(c: i64, safe: bool) -> float4 {
    let k = clamp(c, 0, 14);
    let v = if safe { SAFE_PALETTE[k] } else { NORMAL_PALETTE[k] };
    float4 { v[0], v[1], v[2], 1.0 }
}

fn fill_palette(look: Look&, safe: bool) {
    for c in 15 { look.palette[c] = palette_color(c, safe); }
    look.palette[15] = float4 { 0.3, 0.27, 0.4, 1.0 };
}
