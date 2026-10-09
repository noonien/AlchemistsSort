// Alchemist's Sort: sort the potions so every flask holds one color.
//
//   goose src/main.goose                       play (in-process)
//   goose src/main.goose -- --level 12         jump to a campaign level
//   goose src/main.goose -- --seed 99 --like 30
//   goose src/main.goose -- --hand 8           play built-in hand-made level 8
//
// The rules live in core/ and know nothing of drawing; this file is the
// game around them: screens, input, animation and the board's pictures.

import std;
import vec;
import math;
import os;
import gfx;
import ui;
import core.board;
import core.solver;
import core.generator;
import core.levels;
import core.tools;
import core.campaign;
import core.variation;
import app.draw;
import app.shaders;
import app.palette;
import app.text;
import app.sfx;
import app.music;
import app.save;
import app.scene;
import app.fx;
import app.menus;
import app.parts;
import app.forces;
import app.guide;
import core.explain;

// The canvas everything is laid out on, scaled to fit the window.
let VW: f32 = 540.0;
let VH: f32 = 960.0;

enum Screen { Home, Play, Settings, Seed, Map }

// What covers the board, if anything.
enum Overlay { None, Win, Lose, Intro, Reset, Brewing, Grimoire }

enum PlayMode { Campaign, Seed, Hand }

// Solver positions each use may search.
let HINT_BUDGET = 80000;        // the board's search: a hint, the dead-end check, autoplay
let SHUFFLE_BUDGET = 30000;     // each shuffled deal tried
let SHUFFLE_TRIES = 40;

// A frame's length when only the idle life moves: thirty a second.
let IDLE_FRAME_MS: f64 = 33.0;

// The most flasks the layout keeps readable.
let MAX_ON_SCREEN = 22;

// Timing of a pour, in seconds.
let T_LIFT: f64 = 0.2;
let T_POUR: f64 = 0.5;
let T_BACK: f64 = 0.22;

struct Counters { undo: i64 = 0, restart: i64 = 0, shuffle: i64 = 0, extra: i64 = 0, hint: i64 = 0 }

struct PourAnim {
    active: bool = false,
    from: i64 = 0,
    to: i64 = 0,
    t0: f64 = 0.0,
    color: i64 = 0,
    amount: i64 = 0,
    src_before: Bottle,
    src_after: Bottle,
    dst_before: Bottle,
    dst_after: Bottle,
    popped: bool = false,
    effects_done: bool = false,
}

struct Particle {
    pos: float2,
    vel: float2,
    life: f32 = 0.0,
    span: f32 = 1.0,
    size: f32 = 4.0,
    color: float4,
    gravity: f32 = 0.0,
}

struct Slot { pos: float2, half: float2 }

// A click scripted for testing; a hold is not let go.
struct Scripted { pos: float2, hold: bool = false }

// --- state ------------------------------------------------------------------------

var scale: f32 = 1.0;
var offset = float2_0;
var screen_px = int2 { 540, 960 };
var now: f64 = 0.0;
var data_dir: u8[>..];
var font_dir: u8[>..];

var save: Save;
var screen_id = Screen.Home;
var overlay = Overlay.None;
var overlay_t: f64 = 0.0;

var mode = PlayMode.Campaign;
var level_number = 1;
var spec: LevelSpec;
var info: LevelInfo;
var play_seed: u64 = 0;
var play_like = 20;

var start_board: Board;
var board: Board;
var history: Board[>..];
var used: Counters;
var selected = -1;
var taps: i64[>..<];
var pours: PourAnim[8];
var particles: Particle[400];
var next_particle = 0;
var shake_until: f64[MAX_BOTTLES];
var complete_at: f64[MAX_BOTTLES];
var hint_from = -1;
var hint_to = -1;
var hint_until: f64 = 0.0;
var message: u8[..160];
var message_until: f64 = 0.0;
var won_at: f64 = -1.0;
var lost_checked = false;
var dead_end_shown = false;    // the Lose overlay is for a dead end, not no moves
var dead_end_waved = false;    // the player chose to keep pouring anyway
var slots: Slot[MAX_BOTTLES];
var drawing: i64[..MAX_BOTTLES];  // the flasks back to front
var pending_load = false;
var seed_text: u8[..20];
var autoplay = false;
var autoplay_next: f64 = 0.0;
var rand = rng { 12345 };

// --- background work ------------------------------------------------------------------
// The solver never holds up a frame: searches, shuffles and level generation
// are jobs that step_jobs advances a slice a frame, the same on the desktop and
// in the browser (which has no threads to spare). One search runs on the
// board in play, restarted on every change: it answers the Hint button, the
// dead-end check and autoplay alike.
let JOB_SLICE: f64 = 0.004;     // seconds of work a frame
let JOB_NODES = 16;             // positions between looks at the clock
var board_search: Search;       // on `board`; see restart_search
var hint_thinking = false;      // Hint was pressed; the answer waits on board_search
var shuffling = false;          // shuffle_job is dealing
var shuffle_job: ShuffleJob;
var brewing = false;            // brew is generating the level to load
var brew: GenJob;
var varying = false;            // vary_job is making this attempt's board
var vary_fresh = false;         //   to start the level with (else to restart it)
var vary_job: VariantJob;

// Every attempt at a level after the first is a variant of it (see
// core/variation.goose): the level as made, its hint (whose colors stay
// put), this attempt's number, and the attempts made at each level so far.
var level_board: Board;
var level_named: u8[..200];
var attempt_no = 0;
var level_tries: i64[1100] = [0; 1100];     // campaign levels, then hand-made ones
var seed_tries = 0;
var seed_tried: u64 = 0;

// This frame's clicks, in canvas units, and the pointer; right-clicks, and
// whether a left press was let go. A scripted hold keeps its press down.
var clicks: float2[..16];
var right_clicks: float2[..16];
var released = false;
var script_hold = false;
var pointer = float2_0;

var board_layer = Layer { buffer: gfx::Buffer { 0 } };
var motion_layer = Layer { buffer: gfx::Buffer { 0 } };
var motion: Inst[>..] = [];     // what moves over the board, drawn over its words
var overlay_layer = Layer { buffer: gfx::Buffer { 0 } };
var look: Look;

// --- small helpers -------------------------------------------------------------------

fn v2(x: f32, y: f32) -> float2 { float2 { x, y } }
fn white(a: f32) -> float4 { float4 { 1.0, 1.0, 1.0, a } }
fn gold(a: f32) -> float4 { float4 { 0.98, 0.82, 0.45, a } }
fn ease(t: f64) -> f32 {
    let x = clamp(t, 0.0, 1.0);
    (x * x * (3.0 - 2.0 * x)) as f32
}
fn lerp2(a: float2, b: float2, t: f32) -> float2 { float2 { a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t } }

fn say(s: const u8[:], seconds: f64) {
    message.clear();
    message.append(s[..min(160, s.len)]);
    message_until = now + seconds;
}

fn difficulty_color(d: Difficulty) -> float4 {
    match d {
        SuperHard => float4 { 0.85, 0.22, 0.35, 1.0 },
        Hard => float4 { 0.93, 0.55, 0.15, 1.0 },
        Normal => float4 { 0.25, 0.65, 0.45, 1.0 },
    }
}

fn in_rect(p: float2, center: float2, half: float2) -> bool {
    abs(p.x - center.x) <= half.x && abs(p.y - center.y) <= half.y
}

// True, once, when this frame has a click inside the rectangle.
fn clicked(center: float2, half: float2) -> bool {
    for i in clicks.len {
        if in_rect(clicks[i], center, half) {
            remove_at(clicks, i);
            return true;
        }
    }
    false
}

// --- particles -----------------------------------------------------------------------

fn emit(pos: float2, vel: float2, span: f32, size: f32, color: float4, gravity: f32) {
    particles[next_particle] = Particle { pos: pos, vel: vel, life: span, span: span, size: size,
                                          color: color, gravity: gravity };
    next_particle = (next_particle + 1) % particles.len;
}

fn burst(pos: float2, n: i64, color: float4, speed: f32) {
    for k in n {
        let a = rand.rand_flt() * TAU;
        let s = speed * (0.4 + rand.rand_flt() as f32 * 0.8);
        emit(pos, v2(cos(a) as f32 * s, sin(a) as f32 * s), 0.6 + rand.rand_flt() as f32 * 0.5,
             3.0 + rand.rand_flt() as f32 * 4.0, color, 60.0);
    }
}

fn update_particles(dt: f32) {
    for &p in particles {
        if p.life <= 0.0 { continue; }
        p.life -= dt;
        p.vel.y += p.gravity * dt;
        p.pos = p.pos + p.vel * float2 { dt, dt };
    }
}

fn draw_particles(out: Inst[>..]&) {
    for p in particles {
        if p.life <= 0.0 { continue; }
        let a = clamp(p.life / p.span * 1.5, 0.0, 1.0);
        spark(out, p.pos, p.size, with_alpha(p.color, a));
    }
}

// --- layout ---------------------------------------------------------------------------

// A flask's half size for a half width; every segment is as tall in any
// flask, so a tall one spans its rows exactly (see the grid in board.goose).
fn bottle_half(hx: f32, cap: i64) -> float2 { v2(hx, hx * (cap * SEGMENT + FLASK_EXTRA) as f32 * 0.5) }

// The board area's top, under the level's title and the back shelf.
let GRID_TOP: f32 = 132.0;

// Room left between one row's feet and the next row's rims, in half widths:
// what stands at a foot (a brazier's bowl, roots, the hearth) and what sits
// on a rim (the salamander, a bud) fit in it, so no row hides another's
// rims or liquid.
let ROW_GAP: f32 = 0.9;

// The half width the layout gives `rows` rows of `cols` columns.
fn layout_unit(cols: i64, rows: i64) -> f32 {
    let w = max(1, cols) * COLUMN_STEP;
    let h = max(1, rows) * (CAP * SEGMENT + FLASK_EXTRA) + (max(1, rows) - 1) * ROW_GAP +
            (if cols > 1 { STAGGER } else { 0.0 });
    min(min(GRID_W / w, GRID_H / h), MAX_UNIT)
}

// Places the flasks in the grid the board was given (place_grid), as large
// as fit the board area: columns side by side, alternate ones set back a
// little for depth, a tall flask standing on the table with its last row.
// `drawing` lists them back to front.
fn layout(board: Board) {
    let cols = max(1, board.cols);
    let rows = max(1, board.rows);
    let hx = layout_unit(cols, rows);
    let flask_h = bottle_half(hx, CAP).y * 2.0;
    let row_h = flask_h + hx * ROW_GAP;
    let stagger: f32 = if cols > 1 { hx * STAGGER } else { 0.0 };
    let total_h = row_h * (rows - 1) + flask_h + stagger;
    let top = GRID_TOP + (GRID_H - total_h) * 0.5;
    let step = hx * COLUMN_STEP;
    let x0 = VW * 0.5 - step * (cols - 1) * 0.5;
    for i in board.count {
        let h = bottle_half(hx, board.bottles[i].cap);
        let c: i64 = board.col[i];
        let r: i64 = board.row[i];
        let ahead: f32 = if c % 2 == 1 { stagger } else { 0.0 };
        let foot = top + ahead + (r + rows_of(board.bottles[i].cap) - 1) * row_h + flask_h;
        slots[i] = Slot { pos: v2(x0 + c * step, foot - h.y), half: h };
    }
    // Back to front: by where each stands on the table.
    drawing.clear();
    for i in board.count { drawing.push(i); }
    for k in 1..drawing.len {
        var j = k;
        while j > 0 && foot_y(drawing[j - 1]) > foot_y(drawing[j]) {
            let t = drawing[j];
            drawing[j] = drawing[j - 1];
            drawing[j - 1] = t;
            j--;
        }
    }
}

fn foot_y(i: i64) -> f32 { slots[i].pos.y + slots[i].half.y }

// The side a flask's lantern's crook rises on: the right, unless only the left of
// its top row is free.
fn hang_side(i: i64) -> f32 {
    if i < 0 || i >= shown.count || shown.rows == 0 { return 1.0; }
    let r: i64 = shown.row[i];
    let c: i64 = shown.col[i];
    let right = c + 1 < shown.cols && flask_at(shown, r, c + 1) >= 0;
    let left = c > 0 && flask_at(shown, r, c - 1) >= 0;
    if right && !left { -1.0 } else { 1.0 }
}

// The free space over a flask's rim, in half widths from the rim's middle:
// up to the liquid of the flask above it in its column, or to the top of
// the board area.
fn lantern_room(i: i64) -> f32 {
    if i < 0 || i >= shown.count { return 2.0; }
    let hx = slots[i].half.x;
    let rim = slots[i].pos.y - slots[i].half.y + hx * FLASK_E;
    var limit: f32 = GRID_TOP - 36.0;
    for j in shown.count {
        if j != i && shown.col[j] == shown.col[i] && foot_y(j) < rim { limit = max(limit, foot_y(j) - hx * 0.25); }
    }
    (rim - limit) / hx
}

// Where a bottle stands: its slot, raised when selected, shaken when refused.
fn rest_pos(i: i64) -> float2 {
    var p = slots[i].pos;
    p.y += drop_offset(i);
    if i == selected { p.y -= slots[i].half.x * 1.2; }
    if now < shake_until[i] {
        let k = (shake_until[i] - now) / 0.35;
        p.x += (sin(now * 60.0) * 5.0 * k) as f32;
    }
    p
}

// --- loading levels ---------------------------------------------------------------

fn reset_play_state() {
    history.clear();
    taps.clear();
    for &a in pours { a.active = false; }
    for i in MAX_BOTTLES {
        shake_until[i] = 0.0;
        complete_at[i] = -10.0;
    }
    hint_from = -1;
    hint_to = -1;
    message_until = 0.0;
    reset_guides();
    board_changed();
    settle_beats();
    reset_back_shelf(board);
}

fn begin_board(b: Board) {
    start_board = b;
    board = b;
    used = Counters {};
    reset_play_state();
    layout(board);
    start_drop();
    overlay = Overlay.None;
    if spec.is_tutorial || info.hint.len > 0 { overlay = Overlay.Intro; overlay_t = now; }
}

// The attempt about to start at the level in play: 0 for the first.
fn take_attempt() -> i64 {
    if mode == PlayMode.Seed {
        if seed_tried != play_seed { seed_tried = play_seed; seed_tries = 0; }
        seed_tries++;
        return seed_tries - 1;
    }
    let k = if mode == PlayMode.Hand { 1024 + clamp(hand_index, 0, 75) } else { clamp(level_number, 0, 1023) };
    level_tries[k]++;
    level_tries[k] - 1
}

fn variant_seed() -> u64 { if mode == PlayMode.Hand { hash(hand_index as u64 + 0xBEEF) } else { spec.seed } }

// Starts the level `b`: as it is the first time, else this attempt's variant.
fn begin_level(b: Board) {
    level_board = b;
    level_named.clear();
    level_named.append(info.hint[..min(200, info.hint.len)]);
    attempt_no = take_attempt();
    start_variant(true);
}

// Makes this attempt's board, at once when a frame's work is enough, else
// a slice a frame under the Brewing overlay (see step_jobs).
fn start_variant(fresh: bool) {
    vary_fresh = fresh;
    vary_job = variant_begin(level_board, variant_seed(), attempt_no, level_named[..]);
    let until = gfx::time() + JOB_SLICE;
    while !vary_job.done && gfx::time() < until { let over = variant_step(vary_job, JOB_NODES); }
    if vary_job.done {
        finish_variant();
        return;
    }
    varying = true;
    overlay = Overlay.Brewing;
    overlay_t = now;
}

fn finish_variant() {
    varying = false;
    if vary_fresh {
        begin_board(vary_job.result);
        return;
    }
    start_board = vary_job.result;
    board = start_board;
    reset_play_state();
    overlay = Overlay.None;
}

fn generated_info(d: Difficulty) {
    info = LevelInfo { name: [], hint: [], difficulty: d };
}

fn load_campaign(n: i64) {
    mode = PlayMode.Campaign;
    level_number = max(1, n);
    spec = level_spec(level_number);
    if spec.hand_made {
        let h, found = campaign_hand_made(level_number);
        info = h.info;
        if spec.is_tutorial && info.hint.len == 0 { info.hint.append(feature_name(spec.tutorial)); }
        begin_level(h.board);
        return;
    }
    brew_level();
}

// One of the built-in hand-made levels, by its place in levels.goose.
fn load_hand(k: i64) {
    mode = PlayMode.Hand;
    hand_index = clamp(k, 0, HAND_MADE_COUNT - 1);
    let h = hand_made(hand_index);
    info = h.info;
    begin_level(h.board);
}

fn load_seed(seed: u64, like: i64) {
    mode = PlayMode.Seed;
    play_seed = seed;
    play_like = like;
    spec = seed_spec(seed, like);
    brew_level();
}

// Generates `spec`'s level a slice a frame (see step_jobs), under the Brewing
// overlay, and starts it when it is done.
fn brew_level() {
    brew = gen_begin(spec.recipe, spec.seed);
    brewing = true;
    pending_load = true;
    overlay = Overlay.Brewing;
}

fn finish_brew() {
    brewing = false;
    pending_load = false;
    generated_info(spec.difficulty);
    begin_level(brew.result.board);
}

// Starts loading on the next frame, after a frame that says so is shown.
fn request_load() {
    brewing = false;
    pending_load = true;
    overlay = Overlay.Brewing;
    overlay_t = now;
    screen_id = Screen.Play;
}

var load_kind = PlayMode.Campaign;
var hand_index = 0;

fn start_campaign(n: i64) { load_kind = PlayMode.Campaign; level_number = n; request_load(); }
fn start_seed(seed: u64, like: i64) { load_kind = PlayMode.Seed; play_seed = seed; play_like = like; request_load(); }
fn start_hand(k: i64) { load_kind = PlayMode.Hand; hand_index = k; request_load(); }

fn do_pending_load() {
    pending_load = false;
    overlay = Overlay.None;
    spec = LevelSpec { number: 0, difficulty: Difficulty.Normal, recipe: Recipe {}, seed: 0 };
    if load_kind == PlayMode.Campaign { load_campaign(level_number); }
    else if load_kind == PlayMode.Seed { load_seed(play_seed, play_like); }
    else { load_hand(hand_index); }
}

// --- the game's actions ------------------------------------------------------------

fn busy(i: i64) -> bool {
    for a in pours { if a.active && (a.from == i || a.to == i) { return true; } }
    false
}

fn any_pouring() -> bool {
    for a in pours { if a.active { return true; } }
    false
}

fn finish_animations() {
    for &a in pours { a.active = false; }
    taps.clear();
    settle_beats();
}

fn refuse(i: i64, why: const u8[:]) {
    shake_until[i] = now + 0.35;
    slosh(i, 0.3);
    play(Sfx.Denied);
    if why.len > 0 { say(why, 2.2); }
}

fn start_pour(from: i64, to: i64) {
    settle_beats();
    let before = board;
    var after = board;
    let r = pour(after, from, to);
    if !r.ok { return; }
    history.push(before);
    board = after;
    // What the pour set off plays once the liquid lands (forces.goose);
    // until then the flasks show the liquid moved and nothing more.
    schedule_pour(before, from, to, r, now);
    let mid = shown;
    for &a in pours {
        if a.active { continue; }
        a = PourAnim { active: true, from: from, to: to, t0: now, color: r.color, amount: r.amount,
                       src_before: before.bottles[from], src_after: mid.bottles[from],
                       dst_before: before.bottles[to], dst_after: mid.bottles[to],
                       popped: r.popped, effects_done: false };
        break;
    }
    // The pour sounds higher as the flask it fills gets fuller.
    let full = after.bottles[to].n as f64 / max(1, after.bottles[to].cap as i64);
    play_pitched(Sfx.Pour, 0.85 + 0.45 * full, 0.8);
    ripple_x[to] = if slots[from].pos.x <= slots[to].pos.x { 0.2 } else { -0.2 };
    hint_from = -1;
    lost_checked = false;
    restart_search();
}

fn tap_bottle(i: i64) {
    if i < 0 || i >= board.count || won_at >= 0.0 { return; }
    let b = board.bottles[i];
    if selected < 0 {
        if can_pour_from(b) {
            selected = i;
            slosh(i, 0.18);
            play(Sfx.Select);
        } else {
            // The words for it are core/explain.goose's.
            refuse(i, refusal(board, -1, i));
        }
        return;
    }
    if selected == i {
        selected = -1;
        play(Sfx.Deselect);
        return;
    }
    let from = selected;
    if can_pour(board, from, i) {
        selected = -1;
        start_pour(from, i);
        return;
    }
    // Not a legal pour: pick the new bottle instead when it can pour.
    if can_pour_from(b) {
        selected = i;
        slosh(i, 0.18);
        play(Sfx.Select);
        return;
    }
    selected = -1;
    refuse(i, refusal(board, from, i));
}

fn process_taps() {
    while taps.len > 0 {
        let i = taps[0];
        if busy(i) || (selected >= 0 && busy(selected)) { break; }
        remove_at(taps, 0);
        tap_bottle(i);
    }
}

// After a tool changes the board: what was known about the old one is void.
fn board_changed() {
    selected = -1;
    won_at = -1.0;
    lost_checked = false;
    dead_end_waved = false;
    if overlay == Overlay.Lose { overlay = Overlay.None; }
    restart_search();
}

// After any change to the board: search the new one, dropping a hint being
// thought about and a shuffle being dealt for the old one.
fn restart_search() {
    board_search = search_begin(board, HINT_BUDGET);
    hint_thinking = false;
    shuffling = false;
}

fn do_undo() {
    if history.len == 0 { say("Nothing to undo.", 1.5); return; }
    finish_animations();
    board = history.pop();
    used.undo++;
    board_changed();
    play(Sfx.Tool);
}

// A new attempt: the level's next variant, from the beginning.
fn do_restart() {
    if varying { return; }
    finish_animations();
    used.restart++;
    play(Sfx.Tool);
    attempt_no = take_attempt();
    start_variant(false);
}

fn do_extra_bottle() {
    if board.count >= min(MAX_BOTTLES, MAX_ON_SCREEN) { say("No room for another flask.", 2.0); return; }
    finish_animations();
    add_empty_bottle(board);
    // The flask stays for this attempt, whatever is undone.
    for &h in history { add_empty_bottle(h); }
    used.extra++;
    layout(board);
    complete_at[board.count - 1] = -10.0;
    burst(slots[board.count - 1].pos, 20, gold(1.0), 140.0);
    board_changed();
    play(Sfx.Tool);
}

// Deals in the background (see step_jobs); finish_shuffle shows the result.
fn do_shuffle() {
    if shuffling { return; }
    finish_animations();
    shuffle_job = shuffle_begin(board, rng { random_seed() }, SHUFFLE_TRIES, SHUFFLE_BUDGET);
    shuffling = true;
    finish_shuffle();
}

fn finish_shuffle() {
    if !shuffling || !shuffle_job.done { return; }
    shuffling = false;
    if shuffle_job.found {
        history.push(board);
        board = shuffle_job.trial;
        used.shuffle++;
        board_changed();
        for i in board.count { burst(slots[i].pos, 6, gold(0.8), 90.0); }
        play(Sfx.Reveal);
    } else {
        say("No solvable shuffle found; try Undo.", 2.5);
        play(Sfx.Denied);
    }
}

// The answer comes from the board's search, at once if it is done already,
// else when it is (see finish_hint); the button thinks meanwhile.
fn do_hint() {
    if hint_thinking { return; }
    finish_animations();
    used.hint++;
    hint_thinking = true;
    finish_hint();
}

fn finish_hint() {
    if !hint_thinking || !board_search.done { return; }
    hint_thinking = false;
    let m, ok = search_first_move(board_search);
    if !ok {
        if board_search.stats.exhausted { say("No winning path from here. Try Undo or another flask.", 3.0); }
        else { say("No path found in time. Try Undo or another flask.", 3.0); }
        play(Sfx.Denied);
        return;
    }
    hint_from = m.from;
    hint_to = m.to;
    hint_until = now + 3.5;
    selected = -1;
    play(Sfx.Tool);
}

fn next_after_win() {
    let ch = chapter_info(chapter_of(level_number));
    if mode == PlayMode.Campaign && level_number == ch.last {
        // A chapter's finale: on to the next room, on the map.
        overlay = Overlay.None;
        open_map_at(level_number + 1);
    }
    else if mode == PlayMode.Campaign { start_campaign(level_number + 1); }
    else if mode == PlayMode.Seed { start_seed(play_seed + 1, play_like); }
    else { screen_id = Screen.Home; overlay = Overlay.None; }
}

// --- per-frame update ---------------------------------------------------------------

// Advances the background jobs by about JOB_SLICE: the level being brewed,
// else a shuffle being dealt, else the board's search.
fn step_jobs() {
    if (brewing || varying) && screen_bound() != Screen.Play {
        // Left before it was done.
        brewing = false;
        varying = false;
        pending_load = false;
        overlay = Overlay.None;
    }
    let until = gfx::time() + JOB_SLICE;
    loop {
        if brewing {
            if gen_step(brew, JOB_NODES) { finish_brew(); }
        } else if varying {
            if variant_step(vary_job, JOB_NODES) { finish_variant(); }
        } else if screen_id != Screen.Play || pending_load {
            break;
        } else if shuffling {
            if shuffle_step(shuffle_job, JOB_NODES) { finish_shuffle(); }
        } else if !board_search.done {
            let over = search_step(board_search, JOB_NODES);
        } else {
            break;
        }
        if gfx::time() >= until { break; }
    }
}

fn update_pours() {
    for &a in pours {
        if !a.active { continue; }
        let t = now - a.t0;
        if !a.effects_done && t >= T_LIFT {
            a.effects_done = true;
            slosh(a.to, ripple_x[a.to] * 0.5);
        }
        if t >= T_LIFT + T_POUR + T_BACK {
            a.active = false;
            slosh(a.from, if slots[a.from].pos.x <= slots[a.to].pos.x { -0.22 } else { 0.22 });
        }
    }
}

fn update_play(dt: f32) {
    finish_hint();
    process_taps();
    update_pours();
    update_beats();
    if any_pouring() || beats_running() { return; }
    if won_at < 0.0 && is_won(board) {
        won_at = now;
        selected = -1;
        if mode == PlayMode.Campaign && level_number >= save.level {
            save.level = level_number + 1;
            write_save(save);
        }
    }
    // The finale (fx.goose) plays first, then the panel.
    if won_at >= 0.0 && overlay == Overlay.None && now - won_at > finale_overlay_at() {
        overlay = Overlay.Win;
        overlay_t = now;
    }
    // No pour left shows at once; a dead end once the board's search has
    // tried every position, which on a big board takes a few frames.
    let stuck = won_at < 0.0 && !lost_checked && overlay == Overlay.None && is_lost(board);
    if won_at < 0.0 && !lost_checked && overlay == Overlay.None && (stuck || board_search.done) {
        lost_checked = true;
        let dead = !stuck && !dead_end_waved && board_search.stats.exhausted;
        if stuck || dead {
            dead_end_shown = dead;
            overlay = Overlay.Lose;
            overlay_t = now;
            play(Sfx.Lose);
        }
    }
    if autoplay && overlay == Overlay.None && won_at < 0.0 && now > autoplay_next && taps.len == 0 &&
       board_search.done {
        let m, ok = search_first_move(board_search);
        if ok {
            taps.push(m.from);
            taps.push(m.to);
        }
        autoplay_next = now + 1.1;
    }
    if autoplay && overlay == Overlay.Intro && now - overlay_t > 1.0 { overlay = Overlay.None; }
}

// --- drawing the board ---------------------------------------------------------------

// `drain` segments have run out of the bottom: the rest shows slid down
// (less than none: the liquid is held that far off the bottom). `rigid`
// turns the liquid with the glass instead of keeping it level.
fn liquid_inst(n: i64, b: Bottle, pos: float2, half: float2, angle: f32, fill: f32, murk: f32, wave: f32,
               drain: f32, rigid: bool) -> Inst {
    var i = inst(Shape.Liquid, pos, half, liquid_fx(n));
    // Four layers to a number, five bits each, bottom first.
    fn four(k: i64) -> f32 {
        var v = 0;
        for j in 4 { if k + j < MAX_CAP { v += (b.seg[k + j] as i64) << (5 * j); } }
        v
    }
    i.p0 = float4 { four(0), four(4), four(8), four(12) };
    let w = b.cap + 0.5 + clamp(drain, -15.9, 15.9) / 32.0;
    i.p1 = float4 { fill, murk, wave, if rigid { -w } else { w } };
    i.misc.y = angle;
    i
}

// One flask with its contents and whatever is on or over it.
fn draw_flask(out: Inst[>..]&, i: i64, b: Bottle, pos: float2, half: float2, angle: f32, fill: f32,
              wave: f32, glow_amount: f32, glow_color: float4, overlays: bool) {
    draw_flask_drained(out, i, b, pos, half, angle, fill, 0.0, wave, glow_amount, glow_color, overlays);
}

// The inside of a flask, behind its liquid; `alpha` fades it.
fn flask_back(out: Inst[>..]&, pos: float2, half: float2, angle: f32, alpha: f32) {
    var back = inst(Shape.FlaskBack, pos, half, float4 { 0.12, 0.10, 0.18, 0.45 * alpha });
    back.misc.y = angle;
    out.push(back);
}

// A flask's glass, over its liquid: an athanor's is warmed by its hearth, a
// tall flask's tinted with the one color it takes, and a lantern's light
// warms what it falls on.
fn flask_glass(out: Inst[>..]&, i: i64, b: Bottle, pos: float2, half: float2, angle: f32, alpha: f32,
               glow_amount: f32, glow_color: float4) {
    var tint = if b.body == Body.Athanor { float4 { 1.0, 0.8, 0.6, 1.0 } } else { float4 { 0.86, 0.92, 1.0, 1.0 } };
    if tall_color(b) > 0 { tint = mix4(tint, palette_color(tall_color(b), save.color_safe), 0.85); }
    if in_lantern_light(i) { tint = mix4(tint, float4 { 1.0, 0.76, 0.42, 1.0 }, 0.65); }
    tint.w = alpha;
    var glass = inst(Shape.Glass, pos, half, tint);
    glass.misc.y = angle;
    glass.misc.z = 18.0;
    glass.p0 = float4 { glow_amount, 0.0, 0.0, 0.0 };
    glass.p1 = glow_color;
    out.push(glass);
}

// The same, with `drain` segments run out of its bottom (a siphon pouring).
// Its parts are drawn in parts.goose, the forces' moments in forces.goose.
fn draw_flask_drained(out: Inst[>..]&, i: i64, b: Bottle, pos: float2, half: float2, angle: f32, fill: f32,
                      drain: f32, wave: f32, glow_amount: f32, glow_color: float4, overlays: bool) {
    let a = flask_anchors(pos, half, angle, 1.0);
    let open: f32 = if i >= 0 { petals_open() } else { 0.0 };
    draw_body_back(out, b, a, open);
    flask_back(out, pos, half, angle, 1.0);
    // A shroud hides the flask entirely; a seal hides what is in it.
    let shrouded = overlays && b.cover == Cover.Shroud;
    let sealed = overlays && b.cover == Cover.Seal;
    if !shrouded && fill > 0.0 {
        let murk: f32 = if sealed { (1 << b.cap) - 1 } else { b.murk };
        out.push(liquid_inst(i, b, pos, half, angle, fill, murk, wave, drain, false));
        // A key shows through the liquid, but not through smoke.
        draw_flask_key(out, b, a, drain, false, save.color_safe);
    }
    flask_glass(out, i, b, pos, half, angle, 1.0, glow_amount, glow_color);
    draw_body(out, i, b, a, open, save.color_safe);
    if !overlays || angle != 0.0 { return; }

    // Color-blind symbols on what is in view, and "?" on murk in that mode.
    if !shrouded && !sealed && save.color_safe {
        let key = if b.key_color != KeyColor.None { key_segment(b) } else { -1 };
        for k in b.n as i64 {
            var c = at(a, segment_center(half, k));
            var r = half.x * 0.42;
            if murky(b, k) {
                text(parts_layer, c.x, c.y, "?", TextStyle.Small, white(0.55), Align.Center);
            } else {
                // The key's layer leaves the key in view: its symbol shows on the
                // rest of its run, or small at the side.
                if k == key {
                    let alone = (k == 0 || b.seg[k - 1] != b.seg[k] || murky(b, k - 1)) &&
                                (k + 1 >= b.n || b.seg[k + 1] != b.seg[k] || murky(b, k + 1));
                    if !alone { continue; }
                    r = half.x * 0.24;
                    c = c + v2(half.x * 0.5, -half.x * 0.24);
                }
                var s = inst(Shape.Symbol, c, v2(r, r), white(0.95));
                s.p0 = float4 { b.seg[k], 0.0, 0.0, 0.0 };
                out.push(s);
            }
        }
    }
    draw_cover(out, i, b, a, if i >= 0 { cover_look(i) } else { CoverLook {} }, save.color_safe);
    if i >= 0 && i == shown.salamander && !hop_flying() {
        draw_salamander(out, at(a, a.lip), half.x, 0.0, salamander_facing, 0.0, 0.0);
    }
    if b.done { draw_completion(out, i, b, pos, half); }
}

// Whether a lit lantern's light falls on flask i: its own, or a neighbor's.
fn in_lantern_light(i: i64) -> bool {
    if i < 0 || i >= shown.count { return false; }
    let b = shown.bottles[i];
    if b.fixture == Fixture.Lantern && b.lit { return true; }
    for j in neighbors(shown, i) {
        if shown.bottles[j].fixture == Fixture.Lantern && shown.bottles[j].lit { return true; }
    }
    false
}

// The board. What moves over it -- the flasks being poured from, an
// hourglass turning over, the forces at work -- goes in `motion`, drawn
// over the board's words, so a flask passing by covers a label instead of
// showing it through.
fn draw_board(out: Inst[>..]&) {
    var moving: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
    for a in pours { if a.active { moving[a.from] = true; } }
    var turning: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
    for i in shown.count { turning[i] = flip_pose(i).on; }
    // Each flask's soft shadow on the table.
    for i in shown.count {
        if shown.bottles[i].behind { continue; }
        let a = stand_anchors(i);
        let foot = at(a, a.base);
        let lift = if i == selected || moving[i] { 0.6 } else { 1.0 };
        glow(out, foot + v2(a.hx * 0.18, -a.hx * 0.05), v2(a.hx * 1.3, a.hx * 0.5), 0.9, float4 { 0.0, 0.0, 0.0, 0.42 * lift });
    }
    // A lit lantern's light on its flask and neighbors.
    for i in shown.count {
        let b = shown.bottles[i];
        if b.fixture != Fixture.Lantern || !b.lit { continue; }
        var lo = slots[i].pos - slots[i].half;
        var hi = slots[i].pos + slots[i].half;
        for j in neighbors(shown, i) {
            lo = v2(min(lo.x, slots[j].pos.x - slots[j].half.x), min(lo.y, slots[j].pos.y - slots[j].half.y));
            hi = v2(max(hi.x, slots[j].pos.x + slots[j].half.x), max(hi.y, slots[j].pos.y + slots[j].half.y));
        }
        let h = slots[i].half;
        let f = 0.03 * look.light.w;
        glow(out, (lo + hi) * v2(0.5, 0.5), (hi - lo) * v2(0.5, 0.5) + v2(h.x * 1.5, h.x * 1.5),
             1.0, float4 { 1.0, 0.8, 0.45, 0.09 + f });
        // A warm wash behind each flask it reaches.
        var reach: i64[..7] = [i];
        for j in neighbors(shown, i) { reach.push(j); }
        for j in reach {
            let a = stand_anchors(j);
            glow(out, a.center, a.half * v2(1.25, 1.05), 0.8, float4 { 1.0, 0.72, 0.36, 0.26 + f });
        }
    }
    // Doors still shut, before the flasks they shut away: behind the row in
    // front of them.
    for d in shown.door_count {
        if shown.doors[d].open { continue; }
        let lo, hi = door_box(d);
        if lo.x < hi.x { draw_door(out, lo, hi, shown.doors[d].color, 0.0, 0.0); }
    }
    // Back to front: what stands behind each flask, and the flask. What
    // stands in front of them goes over them all, since a row's foot is
    // behind the rims of the row in front. Then what moves.
    for i in drawing {
        if i >= shown.count || shown.bottles[i].behind { continue; }
        draw_stand_back(out, i, shown.bottles[i], stand_anchors(i), stand_look(i));
        if !moving[i] && !turning[i] { draw_resting(out, i); }
    }
    for i in drawing {
        if i < shown.count && !shown.bottles[i].behind { draw_stand_front(out, i, shown.bottles[i], stand_anchors(i), stand_look(i)); }
    }
    // Doors swinging open, over the flasks they let out.
    for d in shown.door_count {
        let k = door_opening(d);
        if k < 0.0 { continue; }
        let lo, hi = door_box(d);
        if lo.x < hi.x { draw_door(out, lo, hi, shown.doors[d].color, door_swing(k), door_fade(k)); }
    }
    for i in drawing {
        if i < shown.count && turning[i] { draw_turning(motion, i, flip_pose(i)); }
    }
    for a in pours {
        if !a.active { continue; }
        draw_pouring(motion, a);
    }
    draw_beats(motion);
}

// A flask at rest (or lifted, or being poured into).
fn draw_resting(out: Inst[>..]&, i: i64) {
    var b = shown.bottles[i];
    var fill: f32 = b.n;
    var wave: f32 = 0.0;
    // A bottle being poured into shows its new contents rising.
    for a in pours {
        if !a.active || a.to != i { continue; }
        let t = now - a.t0;
        if t < T_LIFT {
            b = a.dst_before;
            fill = b.n;
        } else {
            let p = ease((t - T_LIFT) / T_POUR);
            fill = a.dst_before.n + (b.n - a.dst_before.n) * p;
            if covered(a.dst_before) && a.amount == 0 { fill = b.n; }
            wave = 1.0 - p * 0.7;
        }
    }
    let pos = rest_pos(i);
    var g: f32 = 0.0;
    var gc = gold(1.0);
    if i == selected { g = 0.9; }
    if (i == hint_from || i == hint_to) && now < hint_until {
        g = 0.6 + 0.4 * sin(now * 8.0) as f32;
        gc = if i == hint_from { float4 { 0.5, 1.0, 0.7, 1.0 } } else { float4 { 0.6, 0.8, 1.0, 1.0 } };
    }
    let since = now - complete_at[i];
    if since >= 0.0 && since < 1.2 {
        g = max(g, (1.0 - since / 1.2) as f32 * 1.4);
        gc = palette_color(flask_color(b), save.color_safe);
    }
    draw_flask(out, i, b, pos, slots[i].half, 0.0, fill, wave, g, gc, true);
    if (i == hint_from || i == hint_to) && now < hint_until {
        let label = if i == hint_from { "from" } else { "to" };
        text_shadowed(0, pos.x, pos.y - slots[i].half.y - 18.0, label, TextStyle.Small, white(0.95), Align.Center);
    }
}

// How far a flask holding `fill` layers is tipped for its surface to just
// reach the lip, as the liquid shader keeps the surface level: while the
// liquid still covers the bottom the slope takes what the column lacks,
// after that the liquid is a wedge in the lower corner.
fn brim_tilt(half: float2, cap: i64, fill: f32) -> f32 {
    let hx = half.x;
    let seg = (half.y * 2.0 - hx * SHADER_EXTRA) / max(cap, CAP);
    let w = hx * LIQUID_W;
    let l = half.y * 2.0 - hx * (FLASK_E * FLASK_BODY + 0.05 + FLASK_E);    // the liquid's bottom to the rim
    let v = max(fill, 0.05) * seg;
    var slope = (l - v) / w;
    if v < l * 0.5 { slope = l * l / (4.0 * w * v); }
    min(atan(slope), 1.4)
}

// How full flask `to` shows while a pour fills it.
fn filling(a: PourAnim) -> f32 {
    let t = now - a.t0;
    let n0: f32 = a.dst_before.n;
    let n1: f32 = a.dst_after.n;
    if t < T_LIFT { return n0; }
    if covered(a.dst_before) && a.amount == 0 { return n1; }
    n0 + (n1 - n0) * ease((t - T_LIFT) / T_POUR)
}

// The source of a pour: lifted over the target and tipped until its
// surface reaches the lip, then tipped further as it empties, so the
// liquid leaves over the lip; then put back. A siphon isn't tipped: it is
// held with its tap over the target and its bottom run drains out of the tap.
fn draw_pouring(out: Inst[>..]&, a: PourAnim) {
    if a.src_before.body == Body.Siphon {
        draw_siphoning(out, a);
        return;
    }
    let half = slots[a.from].half;
    let home = slots[a.from].pos;
    let target = slots[a.to].pos;
    let thalf = slots[a.to].half;
    let side: f32 = if home.x <= target.x { 1.0 } else { -1.0 };
    let t = now - a.t0;
    let cap: i64 = a.src_before.cap;
    let n0: f32 = a.src_before.n;
    let tilt0 = max(brim_tilt(half, cap, n0), 0.3);
    let tilt1 = max(brim_tilt(half, cap, n0 - a.amount), tilt0);
    let lip_target = v2(target.x - side * thalf.x * 0.1, target.y - thalf.y - half.x * 0.5);
    // The lip it pours over, in its own frame.
    let lip_local = v2(side * half.x * 0.96, -half.y + half.x * FLASK_E);
    fn lip_at(center: float2, angle: f32) -> float2 {
        let s = sin(angle);
        let c = cos(angle);
        center + v2(c * lip_local.x - s * lip_local.y, s * lip_local.x + c * lip_local.y)
    }
    // The center that puts the tipped lip over the target's mouth.
    fn center_for(angle: f32) -> float2 { lip_target - (lip_at(v2(0.0, 0.0), angle)) }
    var pos = home;
    var angle: f32 = 0.0;
    var fill: f32 = n0;
    var shown_src = a.src_before;
    var stream = false;
    var stream_a: f32 = 0.0;
    if t < T_LIFT {
        let k = ease(t / T_LIFT);
        angle = side * tilt0 * k;
        pos = lerp2(home - v2(0.0, half.x * 1.2), center_for(side * tilt0), k);
    } else if t < T_LIFT + T_POUR {
        let k = ease((t - T_LIFT) / T_POUR);
        fill = n0 - a.amount * k;
        angle = side * max(brim_tilt(half, cap, fill), tilt0);
        pos = center_for(angle);
        stream = a.amount > 0;
        stream_a = min(1.0, min((t - T_LIFT) / 0.08, (T_LIFT + T_POUR - t) / 0.08)) as f32;
    } else {
        let k = ease((t - T_LIFT - T_POUR) / T_BACK);
        angle = side * tilt1 * (1.0 - k);
        pos = lerp2(center_for(side * tilt1), home, k);
        shown_src = shown.bottles[a.from];
        fill = shown_src.n;
    }
    if stream {
        // The stream leaves the lip moving forward and arcs down under
        // gravity into the middle of the rising surface, splashing there.
        let lip = lip_at(pos, angle);
        let surface = target.y + surface_mid(thalf, a.dst_after.cap, filling(a)).y;
        let land = v2(target.x + side * thalf.x * 0.2, max(surface, lip.y + 6.0));
        let reach = ease((t - T_LIFT) / 0.12);
        let end = lerp2(lip, land, reach);
        let ctrl = v2(lip.x + (end.x - lip.x) * 0.8, lip.y + (end.y - lip.y) * 0.2);
        let color = palette_color(a.color, save.color_safe);
        curve(out, Shape.Stream, lip, ctrl, end, half.x * 0.16, a.from * 1.7, with_alpha(color, stream_a));
        glow(out, end, v2(half.x * 0.5, half.x * 0.2), 0.8, with_alpha(color, 0.5 * stream_a));
        if reach >= 1.0 && rand.rand_int(3) != 0 { splash(end, color, side); }
    }
    draw_flask(out, a.from, shown_src, pos, half, angle, fill, if stream { 0.6 } else { 0.0 }, 0.0, gold(1.0), false);
    // The salamander rides along on its rim.
    if a.from == shown.salamander && !hop_flying() {
        let an = flask_anchors(pos, half, angle, 1.0);
        draw_salamander(out, at(an, an.lip), half.x, angle, salamander_facing, 0.0, 0.0);
    }
}

fn draw_siphoning(out: Inst[>..]&, a: PourAnim) {
    let half = slots[a.from].half;
    let home = slots[a.from].pos;
    let target = slots[a.to].pos;
    let thalf = slots[a.to].half;
    let t = now - a.t0;
    // Where the flask is held: its spout a little over the target's mouth.
    let spout0 = tap_spout(flask_anchors(v2(0.0, 0.0), half, 0.0, 1.0));
    let over = v2(target.x, target.y - thalf.y - half.x * 0.5) - spout0;
    var pos = over;
    var fill: f32 = a.src_before.n;
    var drain: f32 = 0.0;
    var shown_src = a.src_before;
    var stream_a: f32 = 0.0;
    if t < T_LIFT {
        pos = lerp2(home - v2(0.0, half.x * 1.2), over, ease(t / T_LIFT));
    } else if t < T_LIFT + T_POUR {
        let k = ease((t - T_LIFT) / T_POUR);
        drain = a.amount * k;
        fill = a.src_before.n - drain;
        stream_a = if a.amount > 0 { min(1.0, min((t - T_LIFT) / 0.08, (T_LIFT + T_POUR - t) / 0.08)) as f32 } else { 0.0 };
    } else {
        pos = lerp2(over, home, ease((t - T_LIFT - T_POUR) / T_BACK));
        shown_src = shown.bottles[a.from];
        fill = shown_src.n;
    }
    if stream_a > 0.0 {
        // Straight down out of the tap into the rising surface, splashing there.
        let spout = pos + spout0;
        let surface = target.y + surface_mid(thalf, a.dst_after.cap, filling(a)).y;
        let land = v2(spout.x, max(surface, spout.y + 6.0));
        let end = lerp2(spout, land, ease((t - T_LIFT) / 0.12));
        let color = palette_color(a.color, save.color_safe);
        curve(out, Shape.Stream, spout, lerp2(spout, end, 0.5), end, half.x * 0.12, a.from * 1.7, with_alpha(color, stream_a));
        glow(out, end, v2(half.x * 0.4, half.x * 0.16), 0.8, with_alpha(color, 0.5 * stream_a));
        if end.y >= land.y - 0.5 && rand.rand_int(3) != 0 { splash(end, color, 1.0); }
    }
    draw_flask_drained(out, a.from, shown_src, pos, half, 0.0, fill, drain, if stream_a > 0.0 { 0.3 } else { 0.0 },
                       0.0, gold(1.0), false);
    if a.from == shown.salamander && !hop_flying() {
        let an = flask_anchors(pos, half, 0.0, 1.0);
        draw_salamander(out, at(an, an.lip), half.x, 0.0, salamander_facing, 0.0, 0.0);
    }
}

// An hourglass turning over on its stand's pivots, at its middle. The glass
// turns as one cylinder; as it passes level its open end crossfades back to
// the top, and from there it is drawn the other way round: the stack turned
// over, held at the far end until it falls, then quicksilver running down.
// Until then the liquid turns with the glass.
fn draw_turning(out: Inst[>..]&, i: i64, f: FlipPose) {
    let b = shown.bottles[i];
    let pos = rest_pos(i);
    let half = slots[i].half;
    let over = clamp((f.turn - PI * 0.5) / 0.5 + 0.5, 0.0, 1.0);
    let back_turn = f.turn - PI;
    if over < 1.0 { flask_back(out, pos, half, f.turn, 1.0 - over); }
    if over > 0.0 { flask_back(out, pos, half, back_turn, over); }
    if f.turn < PI * 0.5 {
        if b.n > 0 {
            out.push(liquid_inst(i, b, pos, half, f.turn, b.n, b.murk, 0.0, 0.0, true));
            draw_flask_key(out, b, flask_anchors(pos, half, f.turn, 1.0), 0.0, true, save.color_safe);
        }
    } else if b.n > 0 {
        let fill = f.stack.n + f.lift;
        out.push(liquid_inst(i, f.stack, pos, half, back_turn, fill, f.stack.murk, 0.0, -f.lift, true));
        if f.fade > 0.0 {
            var l = liquid_inst(i, f.next, pos, half, back_turn, fill, f.next.murk, 0.0, -f.lift, true);
            l.color.w = f.fade;
            out.push(l);
        }
        // The key goes over with its layer, and down a step with it.
        let ka = flask_anchors(pos, half, back_turn, 1.0);
        let k0 = key_segment(f.stack);
        let k1 = key_segment(f.next);
        if f.fade > 0.0 && k0 >= 0 && k1 >= 0 && k0 != k1 {
            draw_flask_key(out, f.stack, ka, -f.lift + (k0 - k1) * f.fade, true, save.color_safe);
        } else {
            draw_flask_key(out, if f.fade > 0.5 { f.next } else { f.stack }, ka, -f.lift, true, save.color_safe);
        }
    }
    if over < 1.0 { flask_glass(out, i, b, pos, half, f.turn, 1.0 - over, 0.0, gold(1.0)); }
    if over > 0.0 { flask_glass(out, i, b, pos, half, back_turn, over, 0.0, gold(1.0)); }
    // A salamander on it hops clear and lands back on the rim.
    if i == shown.salamander && !hop_flying() {
        let a = slot_anchors(i);
        draw_salamander(out, at(a, a.lip) - v2(0.0, a.hx * 1.4 * f.hop), half.x, 0.0, salamander_facing, f.hop, 0.0);
    }
}

// --- the intro's picture ----------------------------------------------------------------

// How new a flask's newest feature is, in the order the campaign brings
// them in; 0 for a plain flask.
fn feature_rank(bd: Board, i: i64) -> i64 {
    let b = bd.bottles[i];
    var has_q = false;
    var has_drop = false;
    for k in b.n as i64 {
        if b.seg[k] == QUICKSILVER { has_q = true; }
        if b.seg[k] == DROP { has_drop = true; }
    }
    var r = 0;
    fn up(x: bool, rank: i64) { if x { r = max(r, rank); } }
    up(b.murk != 0, 1);
    up(b.cover == Cover.Seal, 2);
    up(b.cap > CAP, 3);
    up(b.body == Body.Vow, 4);
    up(b.cover == Cover.Rime, 5);
    up(b.fixture == Fixture.Brazier, 6);
    up(has_q, 7);
    up(b.body == Body.Siphon, 8);
    up(b.key_color != KeyColor.None, 9);
    up(b.cover == Cover.Curtain, 10);
    up(b.fixture == Fixture.Lantern, 11);
    up(b.cover == Cover.Shroud, 12);
    up(b.body == Body.Hourglass, 13);
    up(b.fixture == Fixture.VineRoot || b.cover == Cover.Vine, 14);
    up(i == bd.salamander, 15);
    up(b.body == Body.Moonpetal, 16);
    up(b.body == Body.Athanor, 17);
    up(has_drop, 18);
    up(b.fixture == Fixture.Catalyst, 19);
    r
}

// The level's newest feature, drawn on its flask standing at `foot`.
fn draw_intro_picture(out: Inst[>..]&, foot: float2) {
    var best = -1;
    var rank = 0;
    for i in shown.count {
        let r = feature_rank(shown, i);
        if r > rank { rank = r; best = i; }
    }
    // The first level has nothing new: a plain flask of its own.
    if best < 0 {
        if shown.count == 0 { return; }
        best = 0;
    }
    let b = shown.bottles[best];
    // A tall flask smaller, so it fits its place on the panel.
    let hx: f32 = min(22.0, 128.0 / (b.cap * SEGMENT + FLASK_EXTRA));
    parts_layer = 1;
    let half = bottle_half(hx, b.cap);
    var x = foot.x;
    if rank == 9 {
        // The key's flask, and the door of its metal it opens.
        x -= hx * 1.6;
        draw_door(out, v2(foot.x - hx * 0.2, foot.y - hx * 4.6), v2(foot.x + hx * 3.4, foot.y), b.key_color, 0.0, 0.0);
    }
    let a = flask_anchors(v2(x, foot.y - half.y), half, 0.0, 1.0);
    if rank == 10 {
        // A flask of the badge's color, completed, and its ribbon to the badge.
        var done = Bottle { n: CAP as u8, cap: CAP as u8, done: true };
        for k in CAP { done.seg[k] = b.badge as u8; }
        let dc = v2(foot.x - hx * 3.4, foot.y - half.y);
        draw_flask(out, -1, done, dc, half, 0.0, CAP, 0.0, 0.6, palette_color(b.badge, save.color_safe), false);
        let bp = badge_at(a);
        curve(out, Shape.Beam, dc, v2((dc.x + bp.x) * 0.5, min(dc.y, bp.y) - hx * 2.0), bp, hx * 0.2, 1.0,
              with_alpha(palette_color(b.badge, save.color_safe), 0.7));
    }
    draw_stand_back(out, best, b, a, StandLook {});
    draw_flask(out, best, b, a.center, a.half, 0.0, b.n, 0.0, 0.0, gold(1.0), true);
    draw_stand_front(out, best, b, a, StandLook {});
    parts_layer = 0;
}

// --- the intro ------------------------------------------------------------------------

// A sentence's picture for its bullet, from what it talks about.
fn sentence_icon(s: const u8[:]) -> Icon, float4 {
    var low = str(s);
    for k in low.len { if low[k] >= 'A' && low[k] <= 'Z' { low[k] = low[k] + 32; } }
    fn has(w: const u8[:]) -> bool { find(low, w) >= 0 }
    if has("key") || has("door") { return Icon.Key, float4 { 0.95, 0.78, 0.4, 1.0 }; }
    if has("ice") || has("frost") || has("melt") || has("thaw") { return Icon.Flake, float4 { 0.7, 0.9, 1.0, 1.0 }; }
    if has("warm") || has("heat") || has("burn") { return Icon.Flame, float4 { 1.0, 0.55, 0.2, 1.0 }; }
    if has("light") || has("lantern") || has("lamp") { return Icon.Sun, float4 { 1.0, 0.9, 0.5, 1.0 }; }
    if has("vine") || has("wither") { return Icon.Leaf, float4 { 0.5, 0.85, 0.35, 1.0 }; }
    if has("hops") || has("salamander") { return Icon.Hop, float4 { 1.0, 0.4, 0.25, 1.0 }; }
    if has("gold") { return Icon.Gold, float4 { 1.0, 0.82, 0.3, 1.0 }; }
    if has("seal") || has("wax") { return Icon.Unseal, float4 { 0.95, 0.45, 0.45, 1.0 }; }
    if has("turns over") || has("bottom layer") || has("sinks") { return Icon.Flip, float4 { 0.85, 0.88, 0.95, 1.0 }; }
    if has("smoke") || has("hide") || has("hid") || has("mystery") || has("curtain") || has("shroud") {
        return Icon.Eye, float4 { 0.8, 0.7, 1.0, 1.0 };
    }
    if has("drop") || has("catalyst") || has("any color") { return Icon.Rune, float4 { 0.85, 0.6, 1.0, 1.0 }; }
    if has("only") || has("nothing") || has("shut") { return Icon.Lock, float4 { 1.0, 0.6, 0.55, 1.0 }; }
    if has("fill") || has("complete") || has("finish") { return Icon.Check, float4 { 0.45, 0.85, 0.55, 1.0 }; }
    if has("tap") { return Icon.Play, gold(1.0); }
    return Icon.Rune, gold(1.0);
}

// The hint, a sentence a line.
fn sentences(s: const u8[:]) -> u8[..200][..8] {
    var out: u8[..200][..8] = [];
    var from = 0;
    for k in s.len {
        let end = k + 1 == s.len || ((s[k] == '.' || s[k] == '!' || s[k] == '?') && s[k + 1] == ' ');
        if !end { continue; }
        if out.len + 1 == out.cap { break; }
        var l: u8[..200] = [];
        l.append(s[from..k + 1]);
        out.push(l);
        from = k + 2;
    }
    if from < s.len {
        var l: u8[..200] = [];
        l.append(s[from..]);
        out.push(l);
    }
    out
}

// Where the intro's parts go: its words' width and where they start.
let INTRO_HALF_W: f32 = 232.0;
let INTRO_TEXT_W: f32 = 360.0;

// The panel before a level with something to say: a page from the
// Grimoire, with the new modifier on its flask, lit, and the hint a line
// with a picture at a time.
fn draw_intro(out: Inst[>..]&) {
    let t = now - overlay_t;
    let lines = sentences(info.hint);
    var lines_h: f32 = 0.0;
    for l in lines { lines_h += text_block(1, 0.0, 0.0, INTRO_TEXT_W, l, TextStyle.Small, white(1.0), Align.Left, false) + 12.0; }
    let hero_h: f32 = 170.0;
    let h = 96.0 + hero_h + lines_h + 82.0;
    // In, rising and brightening.
    let a = clamp(t * 4.0, 0.0, 1.0) as f32;
    let rise = 26.0 * (1.0 - ease(t * 3.0));
    let c = v2(VW * 0.5, VH * 0.46 + rise);
    let top = c.y - h * 0.5;
    let mark = out.len;
    panel(out, c, v2(INTRO_HALF_W, h * 0.5));

    // The tag on the top edge, the name, and a rule.
    let tag = if spec.is_tutorial { str("New modifier") } else { level_title() };
    let tw = text_width(TextStyle.Tiny, tag) * 0.5 + 16.0;
    rect(out, v2(c.x, top), v2(tw, 13.0), 13.0, float4 { 0.36, 0.25, 0.12, 1.0 });
    frame_rect(out, v2(c.x, top), v2(tw, 13.0), 13.0, 1.5, gold(0.9));
    text(1, c.x, top, tag, TextStyle.Tiny, gold(a), Align.Center);
    let title = if spec.is_tutorial { str(feature_name(spec.tutorial)) }
                else if info.name.len > 0 { str(info.name) } else { str(level_title()) };
    text_shadowed(1, c.x, top + 46.0, title, TextStyle.Heading, gold(a), Align.Center);
    let ry = top + 78.0;
    rect(out, v2(c.x - 70.0, ry), v2(56.0, 0.7), 0.0, gold(0.45));
    rect(out, v2(c.x + 70.0, ry), v2(56.0, 0.7), 0.0, gold(0.45));
    spark(out, v2(c.x, ry), 6.0, gold(0.9));

    // The flask, on a lit stand, breathing; motes rising round it.
    let foot = v2(c.x, top + 96.0 + hero_h - 14.0);
    let pulse = (0.85 + 0.15 * sin(now * 2.2)) as f32;
    glow(out, foot - v2(0.0, 62.0), v2(130.0 * pulse, 92.0 * pulse), 1.0, float4 { 1.0, 0.8, 0.45, 0.2 });
    glow(out, foot + v2(0.0, 2.0), v2(86.0, 9.0), 0.8, float4 { 0.0, 0.0, 0.0, 0.45 });
    rect(out, foot + v2(0.0, 3.0), v2(78.0, 1.0), 1.0, gold(0.5));
    for k in 7 {
        let u = ((now * 0.35 + k * 0.143) % 1.0) as f32;
        let x = foot.x + sin(k * 2.4 + now * 0.9) as f32 * (40.0 + k * 9.0);
        let y = foot.y - 8.0 - u * 150.0;
        spark(out, v2(x, y), 2.0 + (k % 3) * 1.2, gold(0.8 * sin(u * 3.14159) as f32));
    }
    draw_intro_picture(out, foot);

    // The hint, a line at a time, each with its picture.
    var y = top + 96.0 + hero_h + 6.0;
    let x0 = c.x - INTRO_HALF_W + 72.0;
    for l, k in lines {
        let la = clamp((t - 0.3 - k * 0.22) * 4.0, 0.0, 1.0) as f32;
        let slide = 14.0 * (1.0 - la);
        let lh = text_block(1, 0.0, 0.0, INTRO_TEXT_W, l, TextStyle.Small, white(1.0), Align.Left, false);
        let which, color = sentence_icon(l);
        let ic = v2(x0 - 26.0 + slide, y + 9.0);
        if la > 0.0 {
            let pop = 1.0 + 0.35 * sin(la * 3.14159) as f32;
            badge_icon(out, ic, 14.0 * pop, which, with_alpha(color, la));
        }
        text_block(1, x0 + slide, y + 9.0, INTRO_TEXT_W, l, TextStyle.Small, white(0.94 * la * a), Align.Left, true);
        y += lh + 12.0;
    }
    for k in mark..out.len { out[k].color.w *= a; }

    if button(out, 1, v2(c.x, top + h - 46.0), v2(110.0, 26.0), if spec.is_tutorial { "Show me" } else { "Got it" },
              float4 { 0.2, 0.55, 0.38, 1.0 }, true) {
        close_intro();
    }
}

// --- buttons ---------------------------------------------------------------------------

fn button(out: Inst[>..]&, layer: i64, center: float2, half: float2, label: const u8[:],
          color: float4, enabled: bool) -> bool {
    let hover = in_rect(pointer, center, half) && enabled;
    let base = if enabled { color } else { float4 { 0.35, 0.33, 0.4, 1.0 } };
    let top = mix4(base, white(1.0), if hover { 0.28 } else { 0.15 });
    // Squashed when pressed, springing back (fx.goose).
    let k = press_squash(center);
    let sq = v2(half.x * (1.0 + 0.05 * k), half.y * (1.0 - 0.14 * k));
    if hover { glow(out, center, half + v2(22.0, 18.0), 0.8, gold(0.16)); }
    glow(out, center + v2(0.0, 5.0), sq + v2(6.0, 6.0), 0.6, float4 { 0.0, 0.0, 0.0, 0.35 });
    gradient_rect(out, center, sq, min(sq.y, 18.0), top, mix4(base, float4 { 0.0, 0.0, 0.0, 1.0 }, 0.25));
    frame_rect(out, center, sq, min(sq.y, 18.0), 2.0, gold(if hover { 0.95 } else { 0.6 }));
    text(layer, center.x, center.y, label, TextStyle.Label, white(if enabled { 1.0 } else { 0.5 }), Align.Center);
    let hit = enabled && clicked(center, half);
    if hit { note_press(center); }
    hit
}

fn round_button(out: Inst[>..]&, layer: i64, center: float2, r: f32, which: Icon, label: const u8[:],
                badge: i64, enabled: bool) -> bool {
    let hover = in_rect(pointer, center, v2(r, r)) && enabled;
    let rr = r * (1.0 - 0.1 * press_squash(center));
    if hover { glow(out, center, v2(r + 16.0, r + 16.0), 0.8, gold(0.2)); }
    glow(out, center + v2(0.0, 4.0), v2(r + 6.0, r + 6.0), 0.6, float4 { 0.0, 0.0, 0.0, 0.4 });
    let base = if enabled { float4 { 0.30, 0.20, 0.42, 1.0 } } else { float4 { 0.22, 0.2, 0.26, 1.0 } };
    gradient_rect(out, center, v2(rr, rr), rr, mix4(base, white(1.0), if hover { 0.25 } else { 0.1 }),
                  mix4(base, float4 { 0.0, 0.0, 0.0, 1.0 }, 0.3));
    ring(out, center, rr, 2.5, gold(if hover { 1.0 } else { 0.7 }));
    icon(out, center, rr * 0.55, which, if enabled { gold(1.0) } else { white(0.35) });
    if label.len > 0 { text(layer, center.x, center.y + r + 14.0, label, TextStyle.Tiny, white(0.85), Align.Center); }
    if badge > 0 {
        let bp = center + v2(r * 0.72, -r * 0.72);
        rect(out, bp, v2(12.0, 11.0), 11.0, float4 { 0.85, 0.25, 0.3, 1.0 });
        text(layer, bp.x, bp.y, str(badge), TextStyle.Tiny, white(1.0), Align.Center);
    }
    let hit = enabled && clicked(center, v2(r, r));
    if hit { note_press(center); }
    hit
}

// A tool still working: a ring pulsing out of its button, bubbles rising.
fn thinking(out: Inst[>..]&, center: float2, r: f32) {
    let pulse = (now * 1.4 % 1.0) as f32;
    ring(out, center, r + 3.0 + 9.0 * pulse, 2.0, gold(0.7 * (1.0 - pulse)));
    for k in 3 {
        let t = ((now * 0.8 + k / 3.0) % 1.0) as f32;
        let x = center.x + (k - 1) * 11.0 + sin(now * 3.0 + k * 2.1) as f32 * 3.0;
        glow(out, v2(x, center.y - r - 6.0 - 30.0 * t), v2(3.5, 3.5), 0.5, gold(0.9 * (1.0 - t)));
    }
}

fn panel(out: Inst[>..]&, center: float2, half: float2) {
    glow(out, center + v2(0.0, 10.0), half + v2(30.0, 30.0), 0.5, float4 { 0.0, 0.0, 0.0, 0.5 });
    gradient_rect(out, center, half, 22.0, float4 { 0.24, 0.17, 0.33, 0.98 }, float4 { 0.15, 0.10, 0.22, 0.98 });
    frame_rect(out, center, half, 22.0, 2.5, gold(0.75));
    frame_rect(out, center, half - v2(7.0, 7.0), 16.0, 1.0, gold(0.3));
}

fn badge_pill(out: Inst[>..]&, layer: i64, center: float2, label: const u8[:], color: float4) {
    let w = text_width(TextStyle.Tiny, label) * 0.5 + 12.0;
    rect(out, center, v2(w, 12.0), 12.0, color);
    text(layer, center.x, center.y, label, TextStyle.Tiny, white(1.0), Align.Center);
}

// --- screens ------------------------------------------------------------------------------

fn level_title() -> u8[>..] {
    if mode == PlayMode.Campaign { return str("Level ", level_number); }
    if mode == PlayMode.Seed { return str("Seed ", play_seed); }
    if info.name.len > 0 { return str(info.name); }
    str("Custom Level")
}

fn draw_play(out: Inst[>..]&) {
    // Top bar.
    if round_button(out, 0, v2(48.0, 52.0), 26.0, if mode == PlayMode.Campaign { Icon.Map } else { Icon.Home }, "", 0, true) {
        if mode == PlayMode.Campaign { open_map_at(level_number); } else { screen_id = Screen.Home; }
        overlay = Overlay.None;
        finish_animations();
        play(Sfx.Tool);
    }
    text_shadowed(0, VW * 0.5, 40.0, level_title(), TextStyle.Heading, gold(1.0), Align.Center);
    let d = info.difficulty;
    badge_pill(out, 0, v2(VW * 0.5, 78.0), difficulty_name(d), difficulty_color(d));
    if mode == PlayMode.Hand && info.name.len > 0 {
        text(0, VW * 0.5, 100.0, "hand-made", TextStyle.Tiny, white(0.6), Align.Center);
    }
    // The Grimoire, mirroring the map; the moves beside it.
    let book = v2(VW - 48.0, 52.0);
    draw_book_pulse(out, book, 26.0);
    if round_button(out, 0, book, 26.0, Icon.Book, "", 0, won_at < 0.0) || (gfx::key_pressed("G") && overlay == Overlay.None && won_at < 0.0) {
        open_grimoire();
    }
    text(0, VW - 116.0, 40.0, str(board.pours), TextStyle.Heading, white(0.95), Align.Center);
    text(0, VW - 116.0, 70.0, "moves", TextStyle.Tiny, white(0.7), Align.Center);

    draw_board(out);
    draw_focus(out);

    // Toolbar.
    let y: f32 = 872.0;
    let gap: f32 = 96.0;
    let x0 = VW * 0.5 - gap * 2.0;
    let enabled = won_at < 0.0;
    if round_button(out, 0, v2(x0, y), 32.0, Icon.Undo, "Undo", used.undo, enabled && history.len > 0) { do_undo(); }
    if round_button(out, 0, v2(x0 + gap, y), 32.0, Icon.Restart, "Restart", used.restart, enabled) { do_restart(); }
    if round_button(out, 0, v2(x0 + gap * 2.0, y), 32.0, Icon.Shuffle, "Shuffle", used.shuffle, enabled) { do_shuffle(); }
    if round_button(out, 0, v2(x0 + gap * 3.0, y), 32.0, Icon.Bottle, "Flask", used.extra, enabled) { do_extra_bottle(); }
    if round_button(out, 0, v2(x0 + gap * 4.0, y), 32.0, Icon.Hint, "Hint", used.hint, enabled) { do_hint(); }
    if shuffling { thinking(out, v2(x0 + gap * 2.0, y), 32.0); }
    if hint_thinking { thinking(out, v2(x0 + gap * 4.0, y), 32.0); }

    if now < message_until {
        // Long ones wrap, growing up from the toolbar.
        let a = clamp((message_until - now) * 2.0, 0.0, 1.0) as f32;
        let wrap: f32 = 460.0;
        let w = min(wrap * 0.5 + 20.0, text_width(TextStyle.Small, message) * 0.5 + 20.0);
        let h = text_block(0, 0.0, 0.0, wrap, message, TextStyle.Small, white(a), Align.Center, false);
        let lh = line_height(TextStyle.Small);
        let c = v2(VW * 0.5, 800.0 - (h - lh) * 0.5);
        rect(out, c, v2(w, h * 0.5 + 6.0), 17.0, float4 { 0.05, 0.03, 0.1, 0.85 * a });
        text_block(0, VW * 0.5, c.y - (h - lh) * 0.5, wrap, message, TextStyle.Small, white(a), Align.Center, true);
    }

    // Board taps, unless an overlay has the input: a short press pours, a
    // long one or a right-click shows the flask's card.
    if overlay == Overlay.None {
        let holding = gfx::mouse_down(gfx::MOUSE_LEFT) || script_hold;
        let steady = script_hold || length(pointer - press_pos) < 24.0;
        board_input(clicks[..], released, right_clicks[..], holding, steady);
        clicks.clear();
    }
}

// The flask drawn under a tap, with generous room at the sides and below
// but little above, where the next row's flask stands. Where two areas
// overlap (a lifted flask reaches into the row above), the flask whose
// body is nearest the tap wins.
fn flask_hit(c: float2) -> i64 {
    var hit = -1;
    var best: f32 = 0.0;
    for i in drawing {
        if i >= board.count { continue; }
        let half = slots[i].half;
        let center = slots[i].pos - v2(0.0, if i == selected { half.x * 1.2 } else { 0.0 });
        let top = center.y - half.y - half.x * 0.35;
        let bottom = center.y + half.y + half.x * 0.6;
        if abs(c.x - center.x) > half.x * 1.4 || c.y < top || c.y > bottom { continue; }
        // How far outside the body itself, in half widths.
        let dx = max(0.0, abs(c.x - center.x) - half.x);
        let dy = max(0.0, abs(c.y - center.y) - half.y);
        let d = (dx + dy) / half.x;
        if hit < 0 || d <= best { hit = i; best = d; }
    }
    hit
}

fn tools_summary() -> u8[>..] {
    var s: u8[>..] = [];
    fn add(n: i64, what: const u8[:]) {
        if n == 0 { return; }
        if s.len > 0 { s.append(", "); }
        format(s, what, " x", n);
    }
    add(used.undo, "Undo");
    add(used.restart, "Restart");
    add(used.shuffle, "Shuffle");
    add(used.extra, "Extra flask");
    add(used.hint, "Hint");
    if s.len == 0 { s.append("No tools used. Flawless!"); }
    s
}

fn draw_overlay(out: Inst[>..]&) {
    if overlay == Overlay.None { return; }
    let fade = clamp((now - overlay_t) * 4.0, 0.0, 1.0) as f32;
    rect(out, v2(VW * 0.5, VH * 0.5), v2(VW, VH), 0.0, float4 { 0.03, 0.02, 0.07, 0.6 * fade });
    if overlay == Overlay.Brewing {
        // The level is generated a slice a frame meanwhile, so this moves:
        // three bubbles swell in turn under the word.
        let c = v2(VW * 0.5, VH * 0.45);
        panel(out, c, v2(180.0, 60.0));
        text(1, c.x, c.y - 12.0, "Brewing", TextStyle.Heading, gold(1.0), Align.Center);
        for k in 3 {
            let swell = max(0.0, sin(now * 5.0 - k * 0.9)) as f32;
            glow(out, c + v2((k - 1) * 22.0, 26.0 - 5.0 * swell), v2(4.0 + 3.0 * swell, 4.0 + 3.0 * swell), 0.35,
                 gold(0.45 + 0.55 * swell));
        }
        clicks.clear();
        return;
    }
    if overlay == Overlay.Win {
        let c = v2(VW * 0.5, VH * 0.45);
        panel(out, c, v2(220.0, 210.0));
        text_shadowed(1, c.x, c.y - 160.0, "Brewed!", TextStyle.Title, gold(1.0), Align.Center);
        text(1, c.x, c.y - 100.0, level_title(), TextStyle.Label, white(0.9), Align.Center);
        text(1, c.x, c.y - 55.0, str(board.pours, if board.pours == 1 { " move" } else { " moves" }),
             TextStyle.Heading, white(1.0), Align.Center);
        text_wrapped(1, c.x, c.y - 10.0, 380.0, tools_summary(), TextStyle.Small, white(0.8));
        let next_label = if mode == PlayMode.Campaign { "Next Level" } else if mode == PlayMode.Seed { "Next Seed" } else { "Done" };
        if button(out, 1, c + v2(0.0, 70.0), v2(150.0, 28.0), next_label, float4 { 0.2, 0.55, 0.38, 1.0 }, true) {
            next_after_win();
        }
        if button(out, 1, c + v2(-78.0, 140.0), v2(70.0, 24.0), "Replay", float4 { 0.35, 0.25, 0.5, 1.0 }, true) {
            do_restart();
            used = Counters {};
        }
        if button(out, 1, c + v2(78.0, 140.0), v2(70.0, 24.0), "Home", float4 { 0.35, 0.25, 0.5, 1.0 }, true) {
            screen_id = Screen.Home;
            overlay = Overlay.None;
        }
    } else if overlay == Overlay.Lose {
        let c = v2(VW * 0.5, VH * 0.45);
        panel(out, c, v2(210.0, 170.0));
        let title = if dead_end_shown { "Dead End" } else { "No Moves Left" };
        let why = if dead_end_shown { "Pours are left, but none of them can win this board. Retry, or keep going with a tool." }
                  else { "Every flask is stuck. Retry the same board, or keep going with a tool." };
        text_shadowed(1, c.x, c.y - 120.0, title, TextStyle.Heading, gold(1.0), Align.Center);
        text_wrapped(1, c.x, c.y - 70.0, 360.0, why, TextStyle.Small, white(0.85));
        if button(out, 1, c + v2(0.0, 10.0), v2(140.0, 26.0), "Retry", float4 { 0.2, 0.55, 0.38, 1.0 }, true) {
            do_restart();
        }
        if button(out, 1, c + v2(-75.0, 75.0), v2(68.0, 24.0), "Undo", float4 { 0.35, 0.25, 0.5, 1.0 }, history.len > 0) {
            do_undo();
        }
        if button(out, 1, c + v2(75.0, 75.0), v2(68.0, 24.0), "+Flask", float4 { 0.35, 0.25, 0.5, 1.0 }, true) {
            do_extra_bottle();
        }
        if dead_end_shown {
            if button(out, 1, c + v2(-75.0, 132.0), v2(68.0, 22.0), "Home", float4 { 0.3, 0.22, 0.4, 1.0 }, true) {
                screen_id = Screen.Home;
                overlay = Overlay.None;
            }
            if button(out, 1, c + v2(75.0, 132.0), v2(68.0, 22.0), "Continue", float4 { 0.3, 0.22, 0.4, 1.0 }, true) {
                dead_end_waved = true;
                overlay = Overlay.None;
            }
        } else if button(out, 1, c + v2(0.0, 132.0), v2(68.0, 22.0), "Home", float4 { 0.3, 0.22, 0.4, 1.0 }, true) {
            screen_id = Screen.Home;
            overlay = Overlay.None;
        }
    } else if overlay == Overlay.Intro {
        draw_intro(out);
        clicks.clear();
    } else if overlay == Overlay.Grimoire {
        draw_grimoire(out);
    } else if overlay == Overlay.Reset {
        let c = v2(VW * 0.5, VH * 0.45);
        panel(out, c, v2(210.0, 120.0));
        text_shadowed(1, c.x, c.y - 70.0, "Reset progress?", TextStyle.Label, gold(1.0), Align.Center);
        text(1, c.x, c.y - 30.0, "You will start again at level 1.", TextStyle.Small, white(0.85), Align.Center);
        if button(out, 1, c + v2(-80.0, 50.0), v2(70.0, 24.0), "Reset", float4 { 0.7, 0.2, 0.25, 1.0 }, true) {
            save.level = 1;
            write_save(save);
            overlay = Overlay.None;
            say("Progress reset.", 2.0);
        }
        if button(out, 1, c + v2(80.0, 50.0), v2(70.0, 24.0), "Cancel", float4 { 0.35, 0.25, 0.5, 1.0 }, true) {
            overlay = Overlay.None;
        }
    }
    clicks.clear();
}

// The intro goes; the Grimoire's button pulses once after a tutorial's, so
// it is found.
// After a tutorial's, the flasks with its modifier light up on the board,
// its rule said under them, as when its Grimoire entry is tapped.
fn close_intro() {
    overlay = Overlay.None;
    if spec.is_tutorial || mode == PlayMode.Hand { pulse_book(); }
    if !spec.is_tutorial { return; }
    for e in grimoire(board) {
        if e.feature == spec.tutorial && e.flasks.len > 0 { focus_on(e.flasks[..], [], str(e.name, ": ", e.rule)); }
    }
}

fn toggle_row(out: Inst[>..]&, y: f32, label: const u8[:], on: bool) -> bool {
    text(0, 90.0, y, label, TextStyle.Body, white(0.92), Align.Left);
    let c = v2(VW - 110.0, y);
    let track = if on { float4 { 0.2, 0.6, 0.4, 1.0 } } else { float4 { 0.3, 0.27, 0.36, 1.0 } };
    rect(out, c, v2(34.0, 17.0), 17.0, track);
    let knob = c + v2(if on { 17.0 } else { -17.0 }, 0.0);
    rect(out, knob, v2(14.0, 14.0), 14.0, white(0.95));
    clicked(v2(VW * 0.5, y), v2(VW * 0.42, 22.0))
}

fn draw_settings(out: Inst[>..]&) {
    text_shadowed(0, VW * 0.5, 90.0, "Settings", TextStyle.Heading, gold(1.0), Align.Center);
    panel(out, v2(VW * 0.5, 330.0), v2(220.0, 170.0));
    if toggle_row(out, 190.0, "Sound", save.sound) {
        save.sound = !save.sound;
        sound_on = save.sound;
        write_save(save);
        play(Sfx.Tool);
    }
    if toggle_row(out, 240.0, "Music", save.music) {
        save.music = !save.music;
        music_on = save.music;
        write_save(save);
    }
    if toggle_row(out, 290.0, "Color-blind palette", save.color_safe) {
        save.color_safe = !save.color_safe;
        write_save(save);
    }
    text(0, VW * 0.5, 325.0, "adds a symbol to every color", TextStyle.Tiny, white(0.6), Align.Center);
    // A sample of the palette.
    for c in 1..15 {
        let p = v2(VW * 0.5 + (c - 7.5) * 26.0, 365.0);
        rect(out, p, v2(11.0, 11.0), 4.0, palette_color(c, save.color_safe));
        if save.color_safe {
            var s = inst(Shape.Symbol, p, v2(8.0, 8.0), white(1.0));
            s.p0 = float4 { c, 0.0, 0.0, 0.0 };
            out.push(s);
        }
    }
    if button(out, 0, v2(VW * 0.5, 440.0), v2(130.0, 26.0), "Reset Progress", float4 { 0.6, 0.2, 0.25, 1.0 }, true) {
        overlay = Overlay.Reset;
        overlay_t = now;
    }
    text(0, VW * 0.5, 580.0, str("Next level: ", save.level), TextStyle.Small, white(0.7), Align.Center);
    text(0, VW * 0.5, 610.0, str("Saved in ", save_dir), TextStyle.Tiny, white(0.45), Align.Center);
    text_wrapped(0, VW * 0.5, 660.0, 440.0,
                 "Keys: U undo, R restart, S shuffle, F extra flask, H hint, G grimoire, Esc back. Hold a flask (or right-click it) to read it.",
                 TextStyle.Tiny, white(0.55));
    if button(out, 0, v2(VW * 0.5, 850.0), v2(90.0, 26.0), "Back", float4 { 0.35, 0.25, 0.5, 1.0 }, true) {
        screen_id = Screen.Home;
    }
}

fn seed_value() -> u64 {
    if seed_text.len == 0 { return 0; }
    var v: u64 = 0;
    for ch in seed_text { v = v * 10 + (ch - '0'); }
    v
}

fn draw_seed(out: Inst[>..]&) {
    text_shadowed(0, VW * 0.5, 90.0, "Brew from a Seed", TextStyle.Heading, gold(1.0), Align.Center);
    panel(out, v2(VW * 0.5, 360.0), v2(220.0, 200.0));
    text(0, VW * 0.5, 210.0, "Seed (type digits)", TextStyle.Small, white(0.75), Align.Center);
    rect(out, v2(VW * 0.5, 255.0), v2(160.0, 26.0), 10.0, float4 { 0.06, 0.04, 0.1, 0.9 });
    frame_rect(out, v2(VW * 0.5, 255.0), v2(160.0, 26.0), 10.0, 1.5, gold(0.6));
    let caret = if (now * 2.0) as! i64 % 2 == 0 { "|" } else { "" };
    text(0, VW * 0.5, 255.0, str(seed_text, caret), TextStyle.Label, white(1.0), Align.Center);
    for e in gfx::events() {
        if e.kind == gfx::EVENT_TEXT && e.codepoint >= '0' && e.codepoint <= '9' && seed_text.len < 18 {
            seed_text.push(e.codepoint as u8);
        }
        if e.kind == gfx::EVENT_KEY && e.down && gfx::key_name(e.scancode) == "Backspace" && seed_text.len > 0 {
            seed_text.pop();
        }
    }
    if button(out, 0, v2(VW * 0.5, 310.0), v2(90.0, 20.0), "Random", float4 { 0.35, 0.25, 0.5, 1.0 }, true) {
        seed_text.clear();
        format(seed_text, random_seed() % 1000000);
    }
    text(0, VW * 0.5, 365.0, "Shaped like level", TextStyle.Small, white(0.75), Align.Center);
    text(0, VW * 0.5, 405.0, str(save.seed_like), TextStyle.Heading, white(1.0), Align.Center);
    let d = difficulty_of(save.seed_like);
    badge_pill(out, 0, v2(VW * 0.5, 440.0), difficulty_name(d), difficulty_color(d));
    if button(out, 0, v2(VW * 0.5 - 95.0, 405.0), v2(26.0, 20.0), "-", float4 { 0.3, 0.22, 0.4, 1.0 }, save.seed_like > 1) {
        save.seed_like = max(1, save.seed_like - 1);
    }
    if button(out, 0, v2(VW * 0.5 + 95.0, 405.0), v2(26.0, 20.0), "+", float4 { 0.3, 0.22, 0.4, 1.0 }, true) {
        save.seed_like = min(999, save.seed_like + 1);
    }
    if button(out, 0, v2(VW * 0.5 - 150.0, 405.0), v2(26.0, 20.0), "-10", float4 { 0.3, 0.22, 0.4, 1.0 }, save.seed_like > 10) {
        save.seed_like = max(1, save.seed_like - 10);
    }
    if button(out, 0, v2(VW * 0.5 + 150.0, 405.0), v2(26.0, 20.0), "+10", float4 { 0.3, 0.22, 0.4, 1.0 }, true) {
        save.seed_like = min(999, save.seed_like + 10);
    }
    text_wrapped(0, VW * 0.5, 475.0, 400.0,
                 "The same seed and level always brew the same board.", TextStyle.Tiny, white(0.55));
    if button(out, 0, v2(VW * 0.5, 530.0), v2(120.0, 28.0), "Brew", float4 { 0.2, 0.55, 0.38, 1.0 }, seed_text.len > 0) {
        save.last_seed = seed_value() as! i64;
        write_save(save);
        start_seed(seed_value(), save.seed_like);
    }
    if button(out, 0, v2(VW * 0.5, 850.0), v2(90.0, 26.0), "Back", float4 { 0.35, 0.25, 0.5, 1.0 }, true) {
        write_save(save);
        screen_id = Screen.Home;
    }
}



fn handle_keys() {
    if gfx::key_pressed("Escape") {
        if overlay == Overlay.Intro { close_intro(); }
        else if overlay == Overlay.Reset || overlay == Overlay.Grimoire { overlay = Overlay.None; }
        else if screen_id == Screen.Play && card_flask >= 0 { card_flask = -1; }
        else if screen_id != Screen.Home { screen_id = Screen.Home; overlay = Overlay.None; finish_animations(); }
        else { gfx::quit(); }
    }
    if screen_id != Screen.Play || pending_load || varying { return; }
    let ctrl = gfx::key_down("Left Ctrl") || gfx::key_down("Right Ctrl");
    if overlay == Overlay.Win && (gfx::key_pressed("N") || gfx::key_pressed("Return")) { next_after_win(); return; }
    if overlay == Overlay.Intro && (gfx::key_pressed("Return") || gfx::key_pressed("Space")) { close_intro(); return; }
    if won_at >= 0.0 { return; }
    if gfx::key_pressed("U") || (ctrl && gfx::key_pressed("Z")) || gfx::key_pressed("Backspace") { do_undo(); }
    if gfx::key_pressed("R") { do_restart(); }
    if overlay != Overlay.None && overlay != Overlay.Lose { return; }
    if gfx::key_pressed("S") { do_shuffle(); }
    if gfx::key_pressed("F") { do_extra_bottle(); }
    if gfx::key_pressed("H") { do_hint(); }
}

// --- the frame -------------------------------------------------------------------------

fn fit_canvas() {
    screen_px = gfx::screen_size();
    let w: f32 = max(1, screen_px.x);
    let h: f32 = max(1, screen_px.y);
    scale = min(w / VW, h / VH);
    offset = v2((w - VW * scale) * 0.5, (h - VH * scale) * 0.5);
    set_text_scale(scale, offset);
}

// Turns canvas units into pixels, in place.
fn to_screen(insts: Inst[:]) {
    for &i in insts { scale_inst(i, scale, offset); }
}

fn gather_input() {
    clicks.clear();
    right_clicks.clear();
    released = false;
    let m = gfx::mouse_pos();
    pointer = v2((m.x - offset.x) / scale, (m.y - offset.y) / scale);
    for e in gfx::events() {
        if e.kind != gfx::EVENT_MOUSE_BUTTON { continue; }
        let p = v2((e.x - offset.x) / scale, (e.y - offset.y) / scale);
        if e.down && e.button == gfx::MOUSE_LEFT && clicks.len < 16 { clicks.push(p); }
        if !e.down && e.button == gfx::MOUSE_LEFT { released = true; }
        if e.down && e.button == gfx::MOUSE_RIGHT && right_clicks.len < 16 { right_clicks.push(p); }
    }
}

fn draw_frame(dt: f32) {
    var base: Inst[>..] = [];
    var top: Inst[>..] = [];
    var ink: Inst[>..] = [];
    motion.clear();
    let theme = current_theme();
    look.light = scene_light(theme, now);
    // The room (scene.goose); no clicks while the ink moves between screens.
    draw_scene(base, theme);
    if screen_id == Screen.Play {
        update_back_shelf(shown);
        draw_back_shelf(base);
    }
    if transition_busy() { clicks.clear(); }
    begin_text(0, screen_px);
    begin_text(1, screen_px);
    // Overlays take the clicks first.
    if screen_id == Screen.Play { draw_overlay(top); }
    if screen_id == Screen.Home { draw_home(base); }
    else if screen_id == Screen.Play { draw_play(base); }
    else if screen_id == Screen.Settings { draw_settings(base); }
    else if screen_id == Screen.Seed { draw_seed(base); }
    else if screen_id == Screen.Map { draw_map(base); }
    if screen_id != Screen.Play { draw_overlay(top); }
    // A held flask's card, over the board.
    if screen_id == Screen.Play && overlay == Overlay.None { draw_card(top); }
    draw_drops(top);
    draw_finale(top);
    draw_particles(top);
    draw_transition(ink);
    to_screen(base);
    to_screen(motion);
    to_screen(top);
    to_screen(ink);
    look.screen = float4 { screen_px.x, screen_px.y, (now % 1000.0) as f32, if save.color_safe { 1.0 } else { 0.0 } };
    fill_palette(look, save.color_safe);
    flush_layer(board_layer, base, look, true);
    end_text(0);
    if motion.len > 0 { flush_layer(motion_layer, motion, look, false); }
    flush_layer(overlay_layer, top, look, false);
    end_text(1);
    if ink.len > 0 { flush_layer(ink_layer, ink, look, false); }
}

// Whether this frame has anything moving or waiting on input soon.
// The room whose music plays: the level in play's, else the player's next.
fn music_room_now() -> i64 {
    var n = save.level;
    if screen_id == Screen.Play && (mode == PlayMode.Campaign || pending_load) { n = level_number; }
    else if screen_id == Screen.Play && mode == PlayMode.Seed { n = play_like; }
    let c = chapter_info(chapter_of(n));
    music_room(n, c.theme, c.first)
}

fn lively() -> bool {
    if pending_load || any_pouring() || forces_lively() || taps.len > 0 || clicks.len > 0 { return true; }
    if screen_id == Screen.Play && (shuffling || !board_search.done || guides_lively()) { return true; }
    let d = gfx::mouse_delta();
    if d.x != 0.0 || d.y != 0.0 || gfx::mouse_down(gfx::MOUSE_LEFT) { return true; }
    if now - overlay_t < (if overlay == Overlay.Intro { 1.8 } else { 0.6 }) || now < message_until || now < hint_until || autoplay { return true; }
    if won_at >= 0.0 && now - won_at < 1.5 { return true; }
    for p in particles { if p.life > 0.0 { return true; } }
    for i in MAX_BOTTLES {
        if now < shake_until[i] || now - complete_at[i] < 1.3 { return true; }
    }
    // Music being made gets a slice every frame.
    fx_lively() || music_making
}

fn env_or(name: const u8[:], fallback: const u8[:], out: u8[>..]&) {
    out.clear();
    if !env(name, out) || out.len == 0 {
        out.clear();
        out.append(fallback);
    }
}

fn main() {
    var frames = -1;
    var size_w: i64 = -1;
    var size_h: i64 = -1;
    var shot: u8[>..] = [];
    var start_level = -1;
    var start_seed_value: i64 = -1;
    var like = 20;
    var start_hand_level = -1;
    var shots_from = -1;
    var shots_every = 1;
    var clicks_script: Scripted[>..] = [];
    let argv = args();
    var a = 1;
    while a < argv.len {
        let opt = argv[a];
        let has_value = a + 1 < argv.len;
        if opt == "--frames" && has_value { let n, ok = parse_int(argv[a + 1]); if ok { frames = n; } a++; }
        else if opt == "--screenshot" && has_value { shot.append(argv[a + 1]); a++; }
        else if opt == "--level" && has_value { let n, ok = parse_int(argv[a + 1]); if ok { start_level = n; } a++; }
        else if opt == "--seed" && has_value { let n, ok = parse_int(argv[a + 1]); if ok { start_seed_value = n; } a++; }
        else if opt == "--like" && has_value { let n, ok = parse_int(argv[a + 1]); if ok { like = n; } a++; }
        else if opt == "--hand" && has_value { let n, ok = parse_int(argv[a + 1]); if ok { start_hand_level = n; } a++; }
        else if opt == "--shots" && a + 2 < argv.len {
            let f, okf = parse_int(argv[a + 1]);
            let k, okk = parse_int(argv[a + 2]);
            if okf && okk { shots_from = f; shots_every = max(1, k); }
            a += 2;
        }
        else if opt == "--autoplay" { autoplay = true; }
        else if opt == "--export-music" && has_value { exit(if export_music(argv[a + 1]) { 0 } else { 1 }); }
        else if (opt == "--click" || opt == "--hold") && a + 2 < argv.len {
            let x, okx = parse_int(argv[a + 1]);
            let y, oky = parse_int(argv[a + 2]);
            if okx && oky { clicks_script.push(Scripted { pos: v2(x, y), hold: opt == "--hold" }); }
            a += 2;
        }
        else if opt == "--size" && a + 2 < argv.len {
            let w, okw = parse_int(argv[a + 1]);
            let h, okh = parse_int(argv[a + 2]);
            if okw && okh { size_w = w; size_h = h; }
            a += 2;
        }
        else if opt == "--help" {
            print("""
                alchemists-sort [--level N] [--seed S [--like L]] [--hand K] [--autoplay]
                  --level N      play campaign level N
                  --seed S       play the board brewed from seed S, shaped like level L (default 20)
                  --hand K       play built-in hand-made level K (0 to 24; levels.goose)
                  --autoplay     let the hint solver play
                  --size W H     open the window W x H (it remembers the size it is left at)
                  --click X Y    (testing) click at canvas point X, Y; one every 20 frames after frame 10
                  --hold X Y     (testing) press there and keep holding, in the same turn as the clicks
                  --shots F K    (testing) with --screenshot P, also save P-<frame>.png every K frames from frame F
                  --export-music DIR   write each room's music loop to DIR as a WAV file
                """);
            return;
        }
        else { write_stderr(str("unknown option: ", opt, " (try --help)\n")); exit(2); }
        a++;
    }
    env_or("ALCHEMIST_SORT_DATA", "data", data_dir);
    env_or("ALCHEMIST_SORT_FONTS", str(data_dir, "/fonts"), font_dir);
    save = load_save();
    sound_on = save.sound;
    music_on = save.music;

    // The window opens as it was last left (or as --size asks); screenshots
    // and tests keep the canvas's own size so they stay comparable.
    var open_w: i64 = 540;
    var open_h: i64 = 960;
    if size_w > 0 && size_h > 0 { open_w = clamp(size_w, 270, 8192); open_h = clamp(size_h, 480, 8192); }
    else if frames < 0 { open_w = save.window_w; open_h = save.window_h; }
    guard gfx::open("Alchemist's Sort", open_w, open_h, gfx::WINDOW_RESIZABLE) else {
        write_stderr(str("could not open a window: ", gfx::error(), "\n"));
        exit(1);
    }
    let open_px_w: i64 = gfx::screen_size().x;
    if !init_draw() { abort(str("could not make the pipeline: ", gfx::error())); }
    if !init_text(font_dir) { abort(str("could not load fonts: ", ui::error())); }
    if frames < 0 { init_sounds(); init_music(); }
    rand = rng { random_seed() };
    fit_canvas();
    if start_hand_level >= 0 { start_hand(start_hand_level); }
    else if start_seed_value >= 0 { start_seed(start_seed_value as! u64, like); }
    else if start_level > 0 { start_campaign(start_level); }

    var drawn = 0;
    var last = gfx::time();
    begin_transitions();
    while gfx::frame() {
        now = gfx::time();
        // Scripted runs keep a steady clock, so a screenshot shows the same moment.
        if frames >= 0 { now = 10.0 + drawn / 60.0; }
        let dt = clamp(now - last, 0.0, 0.1) as f32;
        last = now;
        fit_canvas();
        gather_input();
        // Scripted clicks for testing, one every 20 frames after the first
        // 10: a click is let go at once, a hold stays down until the next.
        if drawn >= 10 && (drawn - 10) % 20 == 0 && (drawn - 10) / 20 < clicks_script.len {
            let s = clicks_script[(drawn - 10) / 20];
            clicks.push(s.pos);
            script_hold = s.hold;
            if !s.hold { released = true; }
        }
        if pending_load && !brewing && drawn > 0 { do_pending_load(); }
        step_jobs();
        step_music(music_room_now(), dt);
        handle_keys();
        if screen_id == Screen.Play && !pending_load && !varying { update_play(dt); }
        update_particles(dt);
        update_fx(dt);
        draw_frame(dt);
        update_transition();
        drawn++;
        if shots_from >= 0 && shot.len > 0 && drawn >= shots_from && (drawn - shots_from) % shots_every == 0 {
            gfx::screenshot(str(shot, "-", drawn, ".png"));
        }
        // When nothing but the idle life moves (bubbles, drifting surfaces,
        // flames), draw thirty frames a second instead of sixty: smooth for
        // slow motion, and with software rendering every frame costs real CPU.
        if frames < 0 && !lively() {
            let spent = (gfx::time() - now) * 1000.0;
            if spent < IDLE_FRAME_MS { sleep_ms((IDLE_FRAME_MS - spent) as i64); }
        }
        if drawn == frames { break; }
    }
    if shot.len > 0 {
        if !gfx::screenshot(shot) { write_stderr(str("screenshot failed: ", gfx::error(), "\n")); }
    }
    // Remember the window's size, in the display's units (on a
    // high-density display the screen has more pixels than that).
    if frames < 0 {
        let px = gfx::screen_size();
        let density = max(1.0, open_px_w / (open_w as f64));
        let w = (px.x / density + 0.5) as i64;
        let h = (px.y / density + 0.5) as i64;
        if w >= 270 && h >= 480 && (w != save.window_w || h != save.window_h) {
            save.window_w = w;
            save.window_h = h;
            write_save(save);
        }
    }
    close_sounds();
    ui::destroy(contexts[0]);
    ui::destroy(contexts[1]);
    gfx::close();
}
