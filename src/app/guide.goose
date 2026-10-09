// Explaining the board, on screen: the Grimoire (this level's modifiers, how
// they meet here, and the flasks they're about), a flask's card when it is
// held down, and while a flask is selected, what each other flask would make
// of its pour. The words all come from core/explain.goose; this draws them.
//
// Part of the game in main.goose: it reads the game's state as main.goose's
// other parts do.

import std;
import vec;
import math;
import gfx;
import core.board;
import core.campaign;
import core.explain;
import .draw;
import .shaders;
import .palette;
import .text;
import .sfx;
import .parts;
import .forces;

// --- state --------------------------------------------------------------------------------

let HOLD_TIME: f64 = 0.4;       // a press this long shows a flask's card
let FOCUS_TIME: f64 = 4.5;      // a Grimoire line's flasks stay lit this long

var book_entries: Entry[..19];
var book_page = 0;
var book_pulse_at: f64 = -10.0;

// The flasks a Grimoire line is about, lit on the board for a while.
var focus_flasks: i64[..MAX_BOTTLES];
var focus_pairs: Pair[..16];
var focus_until: f64 = 0.0;

// A press on a flask that may become a hold, and the card a hold shows.
var press_flask = -1;
var press_t: f64 = 0.0;
var press_pos = float2_0;
var card_flask = -1;
var card_held = false;          // goes when the press is let go; else at the next tap
var card_t: f64 = 0.0;
var flask_card: Card;

fn reset_guides() {
    focus_until = 0.0;
    press_flask = -1;
    card_flask = -1;
}

// --- colors and icons ---------------------------------------------------------------------

fn tie_color(t: Tie) -> float4 {
    match t {
        Heat => float4 { 1.0, 0.55, 0.2, 1.0 },
        Light => float4 { 1.0, 0.9, 0.5, 1.0 },
        Key => float4 { 0.95, 0.78, 0.4, 1.0 },
        Vine => float4 { 0.5, 0.85, 0.35, 1.0 },
        Salamander => float4 { 1.0, 0.4, 0.25, 1.0 },
        Catalyst => float4 { 0.85, 0.6, 1.0, 1.0 },
        Flow => float4 { 0.85, 0.88, 0.95, 1.0 },
    }
}

fn tie_icon(t: Tie) -> Icon {
    match t {
        Heat => Icon.Flame, Light => Icon.Sun, Key => Icon.Key, Vine => Icon.Leaf,
        Salamander => Icon.Hop, Catalyst => Icon.Rune, Flow => Icon.Seed,
    }
}

// A small icon on a dark disc, so it reads over glass and liquid alike.
fn badge_icon(out: Inst[>..]&, c: float2, r: f32, which: Icon, color: float4) {
    glow(out, c + v2(0.0, r * 0.15), v2(r * 1.35, r * 1.35), 0.6, float4 { 0.0, 0.0, 0.0, 0.35 * color.w });
    rect(out, c, v2(r, r), r, float4 { 0.08, 0.05, 0.12, 0.88 * color.w });
    ring(out, c, r, max(1.0, r * 0.12), with_alpha(color, 0.75));
    icon(out, c, r * 0.68, which, color);
}

// A flask's middle and its rim, where it stands now.
fn flask_mid(i: i64) -> float2 { at(slot_anchors(i), slot_anchors(i).body) }
fn flask_rim(i: i64) -> float2 { at(slot_anchors(i), slot_anchors(i).rim) }

// A dotted tie between two flasks, arching over, its icon nearer b.
fn tie_line(out: Inst[>..]&, a: i64, b: i64, tie: Tie, alpha: f32) {
    let p = flask_mid(a);
    let q = flask_mid(b);
    let hx = slots[a].half.x;
    let lift = max(hx * 1.2, abs(q.x - p.x) * 0.25);
    let ctrl = v2((p.x + q.x) * 0.5, min(p.y, q.y) - lift);
    let c = tie_color(tie);
    let len = length(ctrl - p) + length(q - ctrl);
    let n = max(3, (len / 9.0) as! i64);
    // The dots run from a to b.
    let run = (now * 1.5 % 1.0) as f32;
    for k in 1..n {
        let t = (k + run) / n;
        let pt = lerp2(lerp2(p, ctrl, t), lerp2(ctrl, q, t), t);
        glow(out, pt, v2(3.4, 3.4), 0.5, with_alpha(c, alpha));
    }
    let mid = lerp2(lerp2(p, ctrl, 0.7), lerp2(ctrl, q, 0.7), 0.7);
    badge_icon(out, mid, max(9.0, hx * 0.36), tie_icon(tie), with_alpha(c, alpha));
}

// A flask picked out: a soft light round it and a ring at its foot.
fn pick_out(out: Inst[>..]&, i: i64, color: float4, alpha: f32) {
    let a = slot_anchors(i);
    let pulse = (0.75 + 0.25 * sin(now * 5.0)) as f32;
    glow(out, a.center, a.half * v2(1.6, 1.15), 1.0, with_alpha(color, 0.5 * alpha * pulse));
    let foot = at(a, a.base);
    var e = inst(Shape.Ring, foot, v2(a.hx * 1.25, a.hx * 1.25), with_alpha(color, 0.85 * alpha));
    e.p0 = float4 { 2.5, 0.0, 0.0, 0.0 };
    e.misc.w = FLASK_E;
    out.push(e);
}

// --- the Grimoire ------------------------------------------------------------------------------

fn open_grimoire() {
    book_entries = grimoire(board);
    book_page = 0;
    card_flask = -1;
    press_flask = -1;
    overlay = Overlay.Grimoire;
    overlay_t = now;
    play(Sfx.Tool);
}

// The book button pulses once after a tutorial's panel goes, so it is found.
fn pulse_book() { book_pulse_at = now; }

fn draw_book_pulse(out: Inst[>..]&, center: float2, r: f32) {
    let t = now - book_pulse_at;
    if t < 0.0 || t > 1.8 { return; }
    for k in 2 {
        let u = ((t - k * 0.45) / 1.0) as f32;
        if u < 0.0 || u > 1.0 { continue; }
        ring(out, center, r + 4.0 + 22.0 * u, 3.0 * (1.0 - u) + 1.0, gold(0.9 * (1.0 - u)));
    }
    glow(out, center, v2(r + 20.0, r + 20.0), 0.8, gold(0.35 * (1.0 - t / 1.8) as f32));
}

// The panel: its top, the entries' area under its heading, and the most
// a page of entries may take.
let BOOK_PANEL_TOP: f32 = 88.0;
let BOOK_TOP: f32 = 168.0;
let BOOK_PAGE_H: f32 = 600.0;
let BOOK_HALF_W: f32 = 252.0;
let BOOK_TEXT_X: f32 = 104.0;       // the words, right of the pictures
let BOOK_TEXT_W: f32 = 396.0;

// An effect as it reads under its entry's name: without the name it starts
// with ("Brazier: each pour..." is "Each pour..." under Brazier).
fn effect_words(s: const u8[:]) -> u8[>..] {
    let at = find(s, ": ");
    if at < 0 || at > 24 { return str(s); }
    capitalized(s[at + 2..])
}

// An entry's parts' heights: its name and rule, then each effect.
fn entry_head_h(e: Entry) -> f32 {
    34.0 + text_block(1, 0.0, 0.0, BOOK_TEXT_W, e.rule, TextStyle.Small, white(1.0), Align.Left, false)
}
fn effect_h(x: Effect) -> f32 {
    text_block(1, 0.0, 0.0, BOOK_TEXT_W - 18.0, effect_words(x.text), TextStyle.Tiny, white(1.0), Align.Left, false) + 6.0
}
fn entry_h(e: Entry) -> f32 {
    var h = entry_head_h(e);
    for x in e.effects { h += effect_h(x); }
    max(h, 84.0) + 16.0
}

// The first entry of each page, the entries split to fit the page.
fn book_page_starts() -> i64[..19] {
    var starts: i64[..19] = [0];
    var y = 0.0;
    for e, k in book_entries {
        let h = entry_h(e);
        if y > 0.0 && y + h > BOOK_PAGE_H {
            starts.push(k);
            y = 0.0;
        }
        y += h;
    }
    starts
}

// The flask that shows an entry best: the vine's root before its tendrils,
// a key before what its door hides.
fn entry_flask(e: Entry) -> i64 {
    if e.feature == Feature.Vine {
        for i in e.flasks { if board.bottles[i].fixture == Fixture.VineRoot { return i; } }
    }
    if e.feature == Feature.Keys {
        for i in e.flasks { if board.bottles[i].key_color != KeyColor.None { return i; } }
    }
    e.flasks[0]
}

// A flask from the board as an entry's picture shows it: without a cover
// another entry is about (a curtain over the smoke it hides), and a key in
// view.
fn picture_flask(b: Bottle, f: Feature) -> Bottle {
    var x = b;
    let own = match x.cover {
        Seal => f == Feature.Seal, Rime => f == Feature.Rime, Shroud => f == Feature.Shroud,
        Vine => f == Feature.Vine, Curtain => f == Feature.Curtain, None => true,
    };
    if !own { x.cover = Cover.None; }
    x.behind = false;
    if f == Feature.Keys {
        let k = key_segment(x);
        if k >= 0 { x.murk = ((x.murk as i64) & ~(1 << k)) as u16; }
    }
    x
}

// The modifier on a small flask from the board, standing on `foot`.
fn draw_entry_picture(out: Inst[>..]&, e: Entry, foot: float2) {
    let i = entry_flask(e);
    if i < 0 || i >= shown.count { return; }
    let b = picture_flask(shown.bottles[i], e.feature);
    let hx: f32 = min(14.0, 84.0 / (b.cap * SEGMENT + FLASK_EXTRA));
    parts_layer = 1;
    let half = bottle_half(hx, b.cap);
    var at_x = foot.x;
    if e.feature == Feature.Keys && b.key_color != KeyColor.None {
        // The key's flask before the door of its metal.
        draw_door(out, v2(foot.x + 2.0, foot.y - 60.0), v2(foot.x + 41.0, foot.y), b.key_color, 0.0, 0.0);
        at_x = foot.x - 14.0;
    }
    let a = flask_anchors(v2(at_x, foot.y - half.y), half, 0.0, 1.0);
    draw_stand_back(out, i, b, a, StandLook {});
    draw_flask(out, i, b, a.center, a.half, 0.0, b.n, 0.0, 0.0, gold(1.0), true);
    draw_stand_front(out, i, b, a, StandLook {});
    parts_layer = 0;
}

// Lights a Grimoire line's flasks on the board, and says the line.
fn focus_on(flasks: const i64[:], pairs: const Pair[:], words: const u8[:]) {
    focus_flasks.clear();
    focus_pairs.clear();
    for i in flasks { if focus_flasks.len < focus_flasks.cap { focus_flasks.push(i); } }
    for p in pairs { if focus_pairs.len < focus_pairs.cap { focus_pairs.push(p); } }
    focus_until = now + FOCUS_TIME;
    say(words, FOCUS_TIME);
    overlay = Overlay.None;
    play(Sfx.Select);
}

fn draw_grimoire(out: Inst[>..]&) {
    let starts = book_page_starts();
    let pages = starts.len;
    book_page = clamp(book_page, 0, pages - 1);
    let first = starts[book_page];
    let last = if book_page + 1 < pages { starts[book_page + 1] } else { book_entries.len };
    // As tall as the page's entries, under the level's title.
    var content: f32 = 0.0;
    for k in first..last { content += entry_h(book_entries[k]); }
    if pages > 1 { content = BOOK_PAGE_H; }
    let foot: f32 = if pages > 1 { 70.0 } else { 18.0 };
    let bottom = BOOK_TOP + max(content, 120.0) + foot;
    let c = v2(VW * 0.5, (BOOK_PANEL_TOP + bottom) * 0.5);
    let half = v2(BOOK_HALF_W, (bottom - BOOK_PANEL_TOP) * 0.5);
    panel(out, c, half);
    text_shadowed(1, c.x, BOOK_PANEL_TOP + 34.0, "Grimoire", TextStyle.Heading, gold(1.0), Align.Center);
    text(1, c.x, BOOK_PANEL_TOP + 64.0, "This level's modifiers. Tap one to find it on the board.", TextStyle.Tiny, white(0.7),
         Align.Center);
    if round_button(out, 1, v2(c.x + half.x - 34.0, BOOK_PANEL_TOP + 32.0), 20.0, Icon.Close, "", 0, true) {
        overlay = Overlay.None;
        play(Sfx.Deselect);
        return;
    }
    var y = BOOK_TOP + 4.0;
    for k in first..last {
        let e = book_entries[k];
        let h = entry_h(e);
        // A faint rule between entries.
        if k > first { rect(out, v2(c.x, y - 8.0), v2(half.x - 30.0, 0.6), 0.0, gold(0.18)); }
        draw_entry_picture(out, e, v2(60.0, y + 74.0));
        // The name and rule: tapping lights every flask with it.
        let head_h = entry_head_h(e);
        let head_c = v2(c.x + 30.0, y + head_h * 0.5);
        let head_half = v2(half.x - 34.0, head_h * 0.5);
        if in_rect(pointer, head_c, head_half) { rect(out, head_c, head_half + v2(4.0, 2.0), 10.0, gold(0.08)); }
        text(1, BOOK_TEXT_X, y + 12.0, e.name, TextStyle.Label, gold(1.0), Align.Left);
        text_block(1, BOOK_TEXT_X, y + 40.0, BOOK_TEXT_W, e.rule, TextStyle.Small, white(0.92), Align.Left, true);
        if clicked(head_c, head_half) {
            focus_on(e.flasks[..], [], str(e.name, ": ", e.rule));
            return;
        }
        var ey = y + head_h + 2.0;
        for x in e.effects {
            let eh = effect_h(x);
            let ec = v2(c.x + 30.0, ey + eh * 0.5 - 4.0);
            let ehalf = v2(half.x - 34.0, eh * 0.5);
            if in_rect(pointer, ec, ehalf) { rect(out, ec, ehalf + v2(4.0, 1.0), 8.0, gold(0.08)); }
            // A tie's icon for a bullet.
            let tie = if x.pairs.len > 0 { x.pairs[0].tie } else { Tie.Flow };
            badge_icon(out, v2(BOOK_TEXT_X + 6.0, ey + 8.0), 8.0, tie_icon(tie), tie_color(tie));
            text_block(1, BOOK_TEXT_X + 20.0, ey + 8.0, BOOK_TEXT_W - 18.0, effect_words(x.text), TextStyle.Tiny,
                       float4 { 1.0, 0.92, 0.75, 0.95 }, Align.Left, true);
            if clicked(ec, ehalf) {
                focus_on(x.flasks[..], x.pairs[..], x.text);
                return;
            }
            ey += eh;
        }
        y += h;
    }
    if pages > 1 {
        let py = bottom - 40.0;
        text(1, c.x, py, str(book_page + 1, " / ", pages), TextStyle.Small, white(0.8), Align.Center);
        if arrow_button(out, v2(c.x - 80.0, py), false, book_page > 0) || gfx::key_pressed("Left") { book_page = max(0, book_page - 1); }
        if arrow_button(out, v2(c.x + 80.0, py), true, book_page + 1 < pages) || gfx::key_pressed("Right") {
            book_page = min(pages - 1, book_page + 1);
        }
    }
}

// The flasks a Grimoire line is about, picked out, with their ties.
fn draw_focus(out: Inst[>..]&) {
    if now >= focus_until { return; }
    let alpha = clamp((focus_until - now) / 0.6, 0.0, 1.0) as f32;
    for i in focus_flasks { if i < shown.count { pick_out(out, i, gold(1.0), alpha); } }
    for p in focus_pairs {
        if p.a != p.b && p.a >= 0 && p.b >= 0 && p.a < shown.count && p.b < shown.count { tie_line(out, p.a, p.b, p.tie, alpha); }
    }
}

// --- a flask's card ---------------------------------------------------------------------------

fn show_card(i: i64, held: bool) {
    card_flask = i;
    card_held = held;
    card_t = now;
    flask_card = explain_flask(board, i);
    play(Sfx.Select);
}

// Presses on the board: a short one is a tap, a long one shows a flask's
// card instead; a right-click shows it at once. Taps go to `taps`.
// `holding` says the press is still down, `steady` that it hasn't moved off.
fn board_input(down: const float2[:], up: bool, right: const float2[:], holding: bool, steady: bool) {
    for c in right {
        let i = flask_hit(c);
        if i >= 0 && i != card_flask { show_card(i, false); } else { card_flask = -1; }
        press_flask = -1;
    }
    for c in down {
        // A tap while a card is up only puts it away.
        if card_flask >= 0 { card_flask = -1; press_flask = -1; continue; }
        let i = flask_hit(c);
        if i >= 0 {
            // Taps act at once, as they always have; a press held still
            // long enough also shows the card.
            taps.push(i);
            press_flask = i;
            press_t = now;
            press_pos = c;
        }
    }
    if press_flask >= 0 {
        if up || !holding || !steady {
            press_flask = -1;
        } else if now - press_t >= HOLD_TIME {
            // The press only picked the flask up: put it back for the card.
            if selected == press_flask && !any_pouring() { selected = -1; }
            show_card(press_flask, true);
            press_flask = -1;
        }
    } else if up && card_flask >= 0 && card_held {
        card_flask = -1;
    }
}

// The card beside its flask, on the screen and clear of it, and dotted ties
// to the flasks that act on it or that it acts on.
fn draw_card(out: Inst[>..]&) {
    if card_flask < 0 || card_flask >= shown.count { return; }
    let i = card_flask;
    let fade = clamp((now - card_t) * 6.0, 0.0, 1.0) as f32;
    for r in flask_card.related {
        // A brazier's heat is only drawn going where it does something.
        if r.tie == Tie.Heat && r.acts && r.flask < board.count && !heat_takes(board.bottles[r.flask]) { continue; }
        if r.flask >= 0 && r.flask < shown.count {
            pick_out(out, r.flask, tie_color(r.tie), fade * 0.8);
            tie_line(out, i, r.flask, r.tie, fade);
        }
    }
    pick_out(out, i, gold(1.0), fade);

    // Size the card for its words, then put it where it covers least of
    // the flask and the flasks tied to it: beside it, above or below.
    let edge: f32 = 20.0;
    let a = slot_anchors(i);
    let w: f32 = 280.0;
    let tw = w - edge * 2.0;
    var h = edge * 2.0 + 26.0;
    for l in flask_card.lines {
        h += text_block(1, 0.0, 0.0, tw - (if l.kind == LineKind.Blocked { 18.0 } else { 0.0 }), l.text, TextStyle.Tiny, white(1.0),
                        Align.Left, false) + 6.0;
    }
    let half = v2(w * 0.5, h * 0.5);
    let lo = a.center - a.half - v2(a.hx * 0.3, a.hx * 0.3);
    let hi = a.center + a.half + v2(a.hx * 0.3, a.hx * 0.3);
    fn within(x: f32, y: f32) -> float2 {
        v2(clamp(x, 10.0 + half.x, VW - 10.0 - half.x), clamp(y, 10.0 + half.y, VH - 10.0 - half.y))
    }
    var spots: float2[..6] = [];
    spots.push(within(hi.x + 6.0 + half.x, a.center.y));
    spots.push(within(lo.x - 6.0 - half.x, a.center.y));
    spots.push(within(a.center.x, lo.y - 6.0 - half.y));
    spots.push(within(a.center.x, hi.y + 6.0 + half.y));
    spots.push(within(a.center.x, VH - 120.0 - half.y));
    // The area of a box that falls on another.
    fn overlap(c0: float2, h0: float2, l1: float2, h1: float2) -> f32 {
        let x = max(0.0, min(c0.x + h0.x, h1.x) - max(c0.x - h0.x, l1.x));
        let y = max(0.0, min(c0.y + h0.y, h1.y) - max(c0.y - h0.y, l1.y));
        x * y
    }
    var c = spots[0];
    var best: f32 = 1e12;
    for p, k in spots {
        var cost = overlap(p, half, lo, hi) * 4.0 + k * 50.0;
        for r in flask_card.related {
            if r.flask < 0 || r.flask >= shown.count { continue; }
            let s = slots[r.flask];
            cost += overlap(p, half, s.pos - s.half, s.pos + s.half);
        }
        if cost < best {
            best = cost;
            c = p;
        }
    }
    glow(out, c + v2(0.0, 8.0), half + v2(18.0, 18.0), 0.6, float4 { 0.0, 0.0, 0.0, 0.45 * fade });
    plate(out, c, half, 3, with_alpha(VELVET, fade), 0.0, 3.0, 0.0);
    let x0 = c.x - half.x + edge;
    var y = c.y - half.y + edge + 10.0;
    text(1, x0, y, flask_card.title, TextStyle.Small, gold(fade), Align.Left);
    y += 26.0;
    for l in flask_card.lines {
        if l.kind == LineKind.Blocked {
            badge_icon(out, v2(x0 + 7.0, y + 1.0), 7.5, Icon.Lock, float4 { 1.0, 0.6, 0.55, fade });
            y += text_block(1, x0 + 18.0, y, tw - 18.0, l.text, TextStyle.Tiny, float4 { 1.0, 0.8, 0.75, fade }, Align.Left, true) + 6.0;
        } else {
            y += text_block(1, x0, y, tw, l.text, TextStyle.Tiny, white(0.93 * fade), Align.Left, true) + 6.0;
        }
    }
}

fn guides_lively() -> bool {
    now < focus_until || press_flask >= 0 || now - book_pulse_at < 2.0 || (card_flask >= 0 && now - card_t < 0.3) ||
    card_flask >= 0
}
