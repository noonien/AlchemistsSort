// Alchemist's Sort: sort the potions so every flask holds one color.
//
//   goose src/main.goose                       play (in-process)
//   goose src/main.goose -- --level 12         jump to a campaign level
//   goose src/main.goose -- --seed 99 --like 30
//   goose src/main.goose -- --file my.json     play a hand-made level
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
import core.level_io;
import core.tools;
import core.campaign;
import app.draw;
import app.shaders;
import app.palette;
import app.text;
import app.sfx;
import app.save;
import app.scene;
import app.fx;
import app.menus;

// The canvas everything is laid out on, scaled to fit the window.
let VW: f32 = 540.0;
let VH: f32 = 960.0;

enum Screen { Home, Play, Settings, Seed, Files, Map }

// What covers the board, if anything.
enum Overlay { None, Win, Lose, Intro, Reset, Brewing }

enum PlayMode { Campaign, Seed, File }

// Solver positions each use may search.
let HINT_BUDGET = 80000;        // the board's search: a hint, the dead-end check, autoplay
let SHUFFLE_BUDGET = 30000;     // each shuffled deal tried
let SHUFFLE_TRIES = 40;

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
var file_path: u8[..512];

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
var shelves: float4[6];        // x, y, half width, unused
var shelf_count = 0;
var pending_load = false;
var seed_text: u8[..20];
var file_list: u8[>..];
var file_scroll = 0;
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

// This frame's clicks, in canvas units, and the pointer.
var clicks: float2[..16];
var pointer = float2_0;

var board_layer = Layer { buffer: gfx::Buffer { 0 } };
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

// A flask's half size for a half width; every segment is as tall in any flask.
fn bottle_half(hx: f32, cap: i64) -> float2 { v2(hx, hx * (0.68 + 0.63 * cap)) }

// Places the flasks in rows on shelves, as large as fit the board area. Long
// flasks stand on the same shelf, rising higher.
fn layout(board: Board) {
    let n = board.count;
    var tallest = CAP;
    for i in n { tallest = max(tallest, board.bottles[i].cap); }
    let rise = (tallest - CAP) * 1.26;      // in half widths
    let top: f32 = 120.0;
    let bottom: f32 = 790.0;
    let width: f32 = 510.0;
    var best_rows = 1;
    var best_hx: f32 = 0.0;
    for rows in 1..6 {
        let per = (n + rows - 1) / rows;
        let hx_w = width / per * 0.34;
        let hx_h = ((bottom - top) / rows - 34.0) / (7.6 + rise);
        let hx = min(min(hx_w, hx_h), 30.0);
        if hx > best_hx + 0.5 {
            best_hx = hx;
            best_rows = rows;
        }
    }
    let hx = best_hx;
    let half = bottle_half(hx, CAP);
    let per = (n + best_rows - 1) / best_rows;
    let row_h = half.y * 2.0 + hx * (1.4 + rise) + 34.0;
    let total_h = row_h * best_rows;
    let y0 = top + ((bottom - top) - total_h) * 0.5 + hx * (1.4 + rise) + half.y;
    let cell = min(width / per, hx * 3.1);
    shelf_count = 0;
    var i = 0;
    for r in best_rows {
        let in_row = min(per, n - i);
        if in_row <= 0 { break; }
        let row_w = cell * in_row;
        let x0 = VW * 0.5 - row_w * 0.5 + cell * 0.5;
        let y = y0 + r * row_h;
        for k in in_row {
            let h = bottle_half(hx, board.bottles[i].cap);
            slots[i] = Slot { pos: v2(x0 + k * cell, y + half.y - h.y), half: h };
            i++;
        }
        if shelf_count < shelves.len {
            shelves[shelf_count] = float4 { VW * 0.5, y + half.y + 7.0, row_w * 0.5 + 18.0, 0.0 };
            shelf_count++;
        }
    }
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
    board_changed();
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

// Loads a level file; false (with a message) if it cannot be read.
fn load_file_level(path: const u8[:]) -> bool {
    var text: u8[>..] = [];
    if !read_file(path, text) {
        say(str("Cannot read ", path), 4.0);
        return false;
    }
    var b = Board { .. };
    let err = parse_level(text, b, info);
    if err.len > 0 {
        say(str("Level file: ", err), 6.0);
        write_stderr(str(path, ": ", err, "\n"));
        return false;
    }
    begin_board(b);
    true
}

fn generated_info(d: Difficulty) {
    info = LevelInfo { name: [], hint: [], difficulty: d };
}

fn load_campaign(n: i64) {
    mode = PlayMode.Campaign;
    level_number = max(1, n);
    spec = level_spec(level_number);
    let override_path = str(data_dir, "/levels/campaign/", level_number, ".json");
    if file_exists(override_path) && load_file_level(override_path) { return; }
    if spec.file.len > 0 {
        let path = str(data_dir, "/levels/tutorial/", spec.file, ".json");
        if load_file_level(path) {
            if spec.is_tutorial && info.hint.len == 0 {
                info.hint.append(feature_name(spec.tutorial));
            }
            return;
        }
    }
    brew_level();
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
    brew = gen_begin(spec.params, spec.seed);
    brewing = true;
    pending_load = true;
    overlay = Overlay.Brewing;
}

fn finish_brew() {
    brewing = false;
    pending_load = false;
    generated_info(spec.difficulty);
    begin_board(brew.result.board);
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

fn start_campaign(n: i64) { load_kind = PlayMode.Campaign; level_number = n; request_load(); }
fn start_seed(seed: u64, like: i64) { load_kind = PlayMode.Seed; play_seed = seed; play_like = like; request_load(); }
fn start_file(path: const u8[:]) {
    file_path.clear();
    file_path.append(path[..min(512, path.len)]);
    load_kind = PlayMode.File;
    request_load();
}

fn do_pending_load() {
    pending_load = false;
    overlay = Overlay.None;
    spec = LevelSpec { number: 0, difficulty: Difficulty.Normal, file: [], params: GenParams {}, seed: 0 };
    if load_kind == PlayMode.Campaign { load_campaign(level_number); }
    else if load_kind == PlayMode.Seed { load_seed(play_seed, play_like); }
    else {
        mode = PlayMode.File;
        if !load_file_level(file_path) { screen_id = Screen.Files; }
    }
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
}

fn refuse(i: i64, why: const u8[:]) {
    shake_until[i] = now + 0.35;
    slosh(i, 0.3);
    play(Sfx.Denied);
    if why.len > 0 { say(why, 2.2); }
}

fn why_blocked(b: Bottle) -> u8[>..] {
    if b.done { return str("That flask is complete and sealed."); }
    if !b.active { return str(""); }
    match b.kind {
        Frozen => str("Frozen: thaws after ", b.timer, if b.timer == 1 { " more pour." } else { " more pours." }),
        Cloak => str("Cloaked: complete a ", COLOR_NAMES[b.key], " flask to lift the cloth."),
        Cork => str("Corked: pour ", COLOR_NAMES[b.key], " onto the cork to pop it."),
        Vault => str("Locked: pour ", COLOR_NAMES[b.key], " onto the padlock to open it."),
        Gift => str("Wrapped: pour anything onto the box to open it."),
        Curtain => str("Behind the curtain: needs ", b.key, " empty flasks to open."),
        Plain, Mystery => str(""),
    }
}

fn start_pour(from: i64, to: i64) {
    let before = board;
    var after = board;
    let r = pour(after, from, to);
    if !r.ok { return; }
    history.push(before);
    board = after;
    for &a in pours {
        if a.active { continue; }
        a = PourAnim { active: true, from: from, to: to, t0: now, color: r.color, amount: r.amount,
                       src_before: before.bottles[from], src_after: after.bottles[from],
                       dst_before: before.bottles[to], dst_after: after.bottles[to],
                       popped: r.popped, effects_done: false };
        break;
    }
    // The pour sounds higher as the flask it fills gets fuller.
    let full = after.bottles[to].n as f64 / max(1, after.bottles[to].cap as i64);
    play_pitched(Sfx.Pour, 0.85 + 0.45 * full, 0.8);
    ripple_x[to] = if slots[from].pos.x <= slots[to].pos.x { 0.2 } else { -0.2 };
    if r.thawed > 0 { play(Sfx.Ice); }
    if r.revealed > 0 || r.opened > 0 { play(Sfx.Reveal); }
    // Effects for bottles that changed without being poured into.
    for i in board.count {
        if i == to { continue; }
        let was = before.bottles[i];
        let is = after.bottles[i];
        if was.active && !is.active {
            burst(slots[i].pos, 24, if was.kind == Kind.Frozen { float4 { 0.8, 0.95, 1.0, 1.0 } } else { gold(1.0) }, 160.0);
        }
        if !was.done && is.done { complete_at[i] = now; }
    }
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
        } else if b.n == 0 && !blocked(b) {
            refuse(i, "");
        } else {
            refuse(i, why_blocked(b));
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
    if can_pour_from(b) && !blocked(b) {
        selected = i;
        slosh(i, 0.18);
        play(Sfx.Select);
        return;
    }
    selected = -1;
    let reason = why_blocked(b);
    if reason.len > 0 { refuse(i, reason); }
    else if b.n >= b.cap { refuse(i, "That flask is full."); }
    else if b.kind == Kind.Mystery && b.key != 0 {
        refuse(i, str("This mystery flask only takes ", COLOR_NAMES[b.key], "."));
    } else { refuse(i, "The colors must match."); }
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

fn do_restart() {
    finish_animations();
    board = start_board;
    reset_play_state();
    used.restart++;
    overlay = Overlay.None;
    play(Sfx.Tool);
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
    if mode == PlayMode.Campaign { start_campaign(level_number + 1); }
    else if mode == PlayMode.Seed { start_seed(play_seed + 1, play_like); }
    else { screen_id = Screen.Files; overlay = Overlay.None; }
}

// --- per-frame update ---------------------------------------------------------------

// Advances the background jobs by about JOB_SLICE: the level being brewed,
// else a shuffle being dealt, else the board's search.
fn step_jobs() {
    if brewing && screen_id != Screen.Play {
        // Left before it was done.
        brewing = false;
        pending_load = false;
        overlay = Overlay.None;
    }
    let until = gfx::time() + JOB_SLICE;
    loop {
        if brewing {
            if gen_step(brew, JOB_NODES) { finish_brew(); }
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
            if a.popped {
                play(Sfx.Pop);
                burst(slots[a.to].pos - v2(0.0, slots[a.to].half.y * 0.6), 18, gold(1.0), 150.0);
            }
        }
        if t >= T_LIFT + T_POUR && a.dst_after.done && complete_at[a.to] < a.t0 {
            complete_at[a.to] = now;
            play_note(a.color, 0.6);
            burst(slots[a.to].pos, 30, palette_color(a.color, save.color_safe), 180.0);
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
    if any_pouring() { return; }
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

// The middle of liquid segment k, relative to the flask's center.
fn segment_center(half: float2, k: i64) -> float2 {
    let bottom = half.y - half.x * 0.16;
    let top = -half.y + half.x * 0.95 + half.x * 0.25;
    let seg = half.x * 1.26;
    v2(0.0, bottom - (k + 0.5) * seg)
}

fn liquid_inst(n: i64, b: Bottle, pos: float2, half: float2, angle: f32, fill: f32, hidden: f32, wave: f32) -> Inst {
    var i = inst(Shape.Liquid, pos, half, liquid_fx(n));
    // Two layers to a number: layer k, plus 16 times layer k + 4.
    fn pair(k: i64) -> f32 {
        let lo: i64 = b.seg[k];
        let hi: i64 = b.seg[k + 4];
        lo + 16 * hi
    }
    i.p0 = float4 { pair(0), pair(1), pair(2), pair(3) };
    i.p1 = float4 { fill, hidden, wave, b.cap };
    i.misc.y = angle;
    i
}

// One flask with its contents and whatever stands on or over it.
fn draw_flask(out: Inst[>..]&, i: i64, b: Bottle, pos: float2, half: float2, angle: f32, fill: f32,
              wave: f32, glow_amount: f32, glow_color: float4, overlays: bool) {
    if angle == 0.0 {
        glow(out, pos + v2(0.0, half.y * 0.98), v2(half.x * 1.3, half.x * 0.3), 0.9,
             float4 { 0.0, 0.0, 0.0, 0.45 });
    }
    var back = inst(Shape.FlaskBack, pos, half, float4 { 0.10, 0.08, 0.16, 0.6 });
    back.misc.y = angle;
    out.push(back);
    let covered = overlays && b.active && (b.kind == Kind.Cloak || b.kind == Kind.Curtain || b.kind == Kind.Gift);
    let fogged = overlays && b.active && (b.kind == Kind.Cork || b.kind == Kind.Vault);
    if !covered {
        let hidden: f32 = if fogged { b.cap } else { b.hidden };
        if fill > 0.0 { out.push(liquid_inst(i, b, pos, half, angle, fill, hidden, wave)); }
    }
    var glass = inst(Shape.Glass, pos, half, float4 { 0.86, 0.92, 1.0, 1.0 });
    glass.misc.y = angle;
    glass.misc.z = 18.0;
    glass.p0 = float4 { glow_amount, 0.0, 0.0, 0.0 };
    glass.p1 = glow_color;
    out.push(glass);
    if !overlays || angle != 0.0 { return; }

    let kind = b.kind;
    // Color-blind symbols on visible segments.
    if save.color_safe && !covered && !fogged {
        for k in b.n as i64 {
            if k < b.hidden { continue; }
            var s = inst(Shape.Symbol, pos + segment_center(half, k), v2(half.x * 0.42, half.x * 0.42), white(0.95));
            s.p0 = float4 { b.seg[k], 0.0, 0.0, 0.0 };
            out.push(s);
        }
    }
    if !covered && !fogged {
        for k in b.hidden as i64 {
            let c = pos + segment_center(half, k);
            text(0, c.x, c.y, "?", TextStyle.Label, white(0.8), Align.Center);
        }
    }
    let neck = pos - v2(0.0, half.y - half.x * 0.35);
    if kind == Kind.Mystery {
        let badge = pos - v2(0.0, half.y * 0.35);
        if b.key == 0 {
            text_shadowed(0, badge.x, badge.y, "?", TextStyle.Heading, gold(0.95), Align.Center);
        } else {
            ring(out, neck + v2(0.0, half.x * 0.9), half.x * 0.42, 3.0, gold(0.9));
            glow(out, neck + v2(0.0, half.x * 0.9), v2(half.x * 0.32, half.x * 0.32), 0.3,
                 palette_color(b.key, save.color_safe));
        }
    }
    if b.active {
        if kind == Kind.Frozen {
            var ice = inst(Shape.Ice, pos + v2(0.0, half.x * 0.1), half + v2(half.x * 0.25, half.x * 0.2),
                           white(1.0));
            ice.p0 = float4 { i * 3.7, 0.0, 0.0, 0.0 };
            out.push(ice);
            glow(out, pos, v2(half.x * 0.62, half.x * 0.62), 0.5, float4 { 0.1, 0.3, 0.5, 0.55 });
            text_shadowed(0, pos.x, pos.y, str(b.timer), TextStyle.Heading, white(1.0), Align.Center);
        } else if kind == Kind.Cloak {
            let c = palette_color(b.key, save.color_safe);
            let cloth_color = mix4(float4 { 0.36, 0.22, 0.45, 1.0 }, c, 0.35);
            out.push(inst(Shape.Cloth, pos + v2(0.0, half.x * 0.15), half + v2(half.x * 0.2, half.x * 0.15),
                          cloth_color));
            let badge = pos + v2(0.0, half.y * 0.15);
            glow(out, badge, v2(half.x * 0.55, half.x * 0.55), 0.25, float4 { 0.0, 0.0, 0.0, 0.5 });
            glow(out, badge, v2(half.x * 0.42, half.x * 0.42), 0.2, c);
            ring(out, badge, half.x * 0.48, 2.5, gold(0.9));
            if save.color_safe {
                var s = inst(Shape.Symbol, badge, v2(half.x * 0.3, half.x * 0.3), white(1.0));
                s.p0 = float4 { b.key, 0.0, 0.0, 0.0 };
                out.push(s);
            }
        } else if kind == Kind.Cork {
            var cork = inst(Shape.Cork, neck, v2(half.x * 0.62, half.x * 0.5), white(1.0));
            cork.p1 = palette_color(b.key, save.color_safe);
            out.push(cork);
            if save.color_safe {
                var s = inst(Shape.Symbol, neck, v2(half.x * 0.26, half.x * 0.26), white(1.0));
                s.p0 = float4 { b.key, 0.0, 0.0, 0.0 };
                out.push(s);
            }
        } else if kind == Kind.Vault {
            let c = palette_color(b.key, save.color_safe);
            var bar = inst(Shape.Rect, pos - v2(0.0, half.y * 0.05), v2(half.x * 1.08, half.x * 0.13),
                           float4 { 0.55, 0.55, 0.62, 1.0 });
            bar.p0 = float4 { 3.0, 0.0, 0.0, 0.0 };
            out.push(bar);
            out.push(inst(Shape.Padlock, pos + v2(0.0, half.y * 0.1), v2(half.x * 0.62, half.x * 0.72), c));
            if save.color_safe {
                var s = inst(Shape.Symbol, pos + v2(0.0, half.y * 0.18), v2(half.x * 0.24, half.x * 0.24), white(1.0));
                s.p0 = float4 { b.key, 0.0, 0.0, 0.0 };
                out.push(s);
            }
        } else if kind == Kind.Gift {
            var box = inst(Shape.Gift, pos + v2(0.0, half.y * 0.12), v2(half.x * 1.15, half.y * 0.8),
                           float4 { 0.55, 0.2, 0.42, 1.0 });
            box.p1 = gold(1.0);
            out.push(box);
        } else if kind == Kind.Curtain {
            var cur = inst(Shape.Curtain, pos, half + v2(half.x * 0.45, half.x * 0.2), float4 { 0.55, 0.12, 0.2, 1.0 });
            out.push(cur);
            glow(out, pos + v2(0.0, half.y * 0.25), v2(half.x * 0.7, half.x * 0.7), 0.4, float4 { 0.0, 0.0, 0.0, 0.5 });
            text_shadowed(0, pos.x, pos.y + half.y * 0.25, str(b.key), TextStyle.Heading, gold(1.0), Align.Center);
            text_shadowed(0, pos.x, pos.y + half.y * 0.25 + 24.0, "empty", TextStyle.Tiny, gold(0.9), Align.Center);
        }
    }
    if b.done { draw_completion(out, i, b, pos, half); }
}

fn draw_board(out: Inst[>..]&) {
    for k in shelf_count {
        let s = shelves[k];
        glow(out, v2(s.x, s.y + 16.0), v2(s.z * 1.02, 10.0), 0.9, float4 { 0.0, 0.0, 0.0, 0.4 });
        var plank = inst(Shape.Wood, v2(s.x, s.y), v2(s.z, 9.0), float4 { 0.45, 0.28, 0.16, 1.0 });
        plank.p0 = float4 { 3.0, 0.0, 0.0, 0.0 };
        out.push(plank);
    }
    // Flasks at rest first, then the ones moving, so those pass in front.
    var moving: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
    for a in pours { if a.active { moving[a.from] = true; } }
    for i in board.count {
        if moving[i] { continue; }
        var b = board.bottles[i];
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
                b = a.dst_after;
                let p = ease((t - T_LIFT) / T_POUR);
                fill = a.dst_before.n + (a.dst_after.n - a.dst_before.n) * p;
                if a.dst_before.active { fill = if a.amount == 0 { b.n } else { fill }; }
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
            gc = palette_color(b.seg[0], save.color_safe);
        }
        draw_flask(out, i, b, pos, slots[i].half, 0.0, fill, wave, g, gc, true);
        if (i == hint_from || i == hint_to) && now < hint_until {
            let label = if i == hint_from { "from" } else { "to" };
            text_shadowed(0, pos.x, pos.y - slots[i].half.y - 18.0, label, TextStyle.Small, white(0.95), Align.Center);
        }
    }
    for a in pours {
        if !a.active { continue; }
        draw_pouring(out, a);
    }
}

// The source of a pour: lifted over the target, tipped, emptied, put back.
fn draw_pouring(out: Inst[>..]&, a: PourAnim) {
    let half = slots[a.from].half;
    let home = slots[a.from].pos;
    let target = slots[a.to].pos;
    let thalf = slots[a.to].half;
    let side: f32 = if home.x <= target.x { 1.0 } else { -1.0 };
    let t = now - a.t0;
    let tilt_full: f32 = 1.25;
    let lip_target = v2(target.x - side * thalf.x * 0.15, target.y - thalf.y - half.x * 0.6);
    // The center that puts the tipped lip over the target's mouth.
    fn center_for(angle: f32) -> float2 {
        let s = sin(angle);
        let c = cos(angle);
        v2(lip_target.x - s * half.y, lip_target.y + c * half.y)
    }
    var pos = home;
    var angle: f32 = 0.0;
    var fill: f32 = a.src_before.n;
    var shown = a.src_before;
    var stream = false;
    var stream_a: f32 = 0.0;
    if t < T_LIFT {
        let k = ease(t / T_LIFT);
        angle = side * tilt_full * 0.55 * k;
        pos = lerp2(home - v2(0.0, half.x * 1.2), center_for(angle), k);
    } else if t < T_LIFT + T_POUR {
        let k = ease((t - T_LIFT) / T_POUR);
        angle = side * (tilt_full * 0.55 + tilt_full * 0.45 * k);
        pos = center_for(angle);
        fill = a.src_before.n - a.amount * k;
        stream = a.amount > 0;
        stream_a = min(1.0, min((t - T_LIFT) / 0.08, (T_LIFT + T_POUR - t) / 0.08)) as f32;
    } else {
        let k = ease((t - T_LIFT - T_POUR) / T_BACK);
        angle = side * tilt_full * (1.0 - k);
        pos = lerp2(center_for(side * tilt_full), home, k);
        shown = a.src_after;
        fill = shown.n;
    }
    if stream {
        // The stream leaves the lip moving forward and arcs down under
        // gravity, splashing where it lands.
        let lip = v2(pos.x + sin(angle) * half.y, pos.y - cos(angle) * half.y);
        let dst_fill = a.dst_after.n;
        let surface = target.y + segment_center(thalf, max(0, dst_fill - 1)).y - thalf.x * 0.6;
        let land = v2(target.x + side * thalf.x * 0.2, max(surface, lip.y + 6.0));
        let reach = ease((t - T_LIFT) / 0.12);
        let end = lerp2(lip, land, reach);
        let ctrl = v2(lip.x + (end.x - lip.x) * 0.8, lip.y + (end.y - lip.y) * 0.2);
        let color = palette_color(a.color, save.color_safe);
        curve(out, Shape.Stream, lip, ctrl, end, half.x * 0.16, a.from * 1.7, with_alpha(color, stream_a));
        glow(out, end, v2(half.x * 0.5, half.x * 0.2), 0.8, with_alpha(color, 0.5 * stream_a));
        if reach >= 1.0 && rand.rand_int(3) != 0 { splash(end, color, side); }
    }
    draw_flask(out, a.from, shown, pos, half, angle, fill, if stream { 0.6 } else { 0.0 }, 0.0, gold(1.0), false);
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
    if round_button(out, 0, v2(48.0, 52.0), 26.0, Icon.Home, "", 0, true) {
        screen_id = Screen.Home;
        finish_animations();
        play(Sfx.Tool);
    }
    text_shadowed(0, VW * 0.5, 40.0, level_title(), TextStyle.Heading, gold(1.0), Align.Center);
    let d = info.difficulty;
    badge_pill(out, 0, v2(VW * 0.5, 78.0), difficulty_name(d), difficulty_color(d));
    if mode == PlayMode.File && info.name.len > 0 {
        text(0, VW * 0.5, 100.0, "hand-made", TextStyle.Tiny, white(0.6), Align.Center);
    }
    text(0, VW - 44.0, 40.0, str(board.pours), TextStyle.Heading, white(0.95), Align.Center);
    text(0, VW - 44.0, 70.0, "moves", TextStyle.Tiny, white(0.7), Align.Center);

    draw_board(out);

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
        let a = clamp((message_until - now) * 2.0, 0.0, 1.0) as f32;
        let w = min(250.0, text_width(TextStyle.Small, message) * 0.5 + 20.0);
        rect(out, v2(VW * 0.5, 800.0), v2(w, 17.0), 17.0, float4 { 0.05, 0.03, 0.1, 0.8 * a });
        text(0, VW * 0.5, 800.0, message, TextStyle.Small, white(a), Align.Center);
    }

    // Board taps, unless an overlay has the input.
    if overlay == Overlay.None {
        for c in clicks {
            for i in board.count {
                let half = slots[i].half;
                let center = slots[i].pos - v2(0.0, if i == selected { half.x * 0.6 } else { 0.0 });
                if in_rect(c, center, half + v2(half.x * 0.4, half.x * 0.9)) {
                    taps.push(i);
                    break;
                }
            }
        }
        clicks.clear();
    }
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
        let c = v2(VW * 0.5, VH * 0.42);
        panel(out, c, v2(220.0, 150.0));
        let title = if spec.is_tutorial { str("New: ", feature_name(spec.tutorial)) }
                    else if info.name.len > 0 { str(info.name) } else { str(level_title()) };
        text_shadowed(1, c.x, c.y - 100.0, title, TextStyle.Label, gold(1.0), Align.Center);
        text_wrapped(1, c.x, c.y - 50.0, 380.0, info.hint, TextStyle.Body, white(0.92));
        if button(out, 1, c + v2(0.0, 105.0), v2(110.0, 26.0), "Got it", float4 { 0.2, 0.55, 0.38, 1.0 }, true) {
            overlay = Overlay.None;
        }
        clicks.clear();
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
    if toggle_row(out, 220.0, "Sound", save.sound) {
        save.sound = !save.sound;
        sound_on = save.sound;
        write_save(save);
        play(Sfx.Tool);
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
                 "Keys: U undo, R restart, S shuffle, F extra flask, H hint, E export board, Esc back.",
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

fn open_files() {
    file_list.clear();
    file_scroll = 0;
    let mine = user_levels_dir();
    let examples = str(data_dir, "/levels/examples");
    for which in 2 {
        let dir = if which == 0 { mine[..] } else { examples[..] };
        var names: u8[>..] = [];
        if !list_dir(dir, names) { continue; }
        each_split(names, '\n') {
            if ends_with(it, ".json") { format(file_list, dir, "/", it, "\n"); }
        };
    }
    screen_id = Screen.Files;
}

fn draw_files(out: Inst[>..]&) {
    text_shadowed(0, VW * 0.5, 90.0, "My Levels", TextStyle.Heading, gold(1.0), Align.Center);
    text_wrapped(0, VW * 0.5, 135.0, 460.0, str("Add .json level files to ", save_dir, "/levels"),
                 TextStyle.Tiny, white(0.6));
    var row = 0;
    var shown = 0;
    each_split(file_list, '\n') {
        if it.len > 0 && row >= file_scroll && shown < 11 {
            let y = 210.0 + shown * 52.0;
            let slash = rfind(it, "/");
            let name = if slash >= 0 { it[slash + 1..] } else { it };
            let is_example = find(it, "/levels/examples/") >= 0;
            if button(out, 0, v2(VW * 0.5, y), v2(210.0, 21.0), name,
                      if is_example { float4 { 0.28, 0.22, 0.38, 1.0 } } else { float4 { 0.25, 0.4, 0.45, 1.0 } }, true) {
                start_file(it);
            }
            shown++;
        }
        if it.len > 0 { row++; }
    };
    if row == 0 { text(0, VW * 0.5, 300.0, "No level files yet.", TextStyle.Small, white(0.7), Align.Center); }
    if file_scroll > 0 && button(out, 0, v2(VW * 0.5 - 70.0, 790.0), v2(50.0, 20.0), "Up", float4 { 0.3, 0.22, 0.4, 1.0 }, true) {
        file_scroll = max(0, file_scroll - 10);
    }
    if row > file_scroll + 11 && button(out, 0, v2(VW * 0.5 + 70.0, 790.0), v2(50.0, 20.0), "Down", float4 { 0.3, 0.22, 0.4, 1.0 }, true) {
        file_scroll += 10;
    }
    if now < message_until { text(0, VW * 0.5, 750.0, message, TextStyle.Small, white(0.85), Align.Center); }
    if button(out, 0, v2(VW * 0.5, 850.0), v2(90.0, 26.0), "Back", float4 { 0.35, 0.25, 0.5, 1.0 }, true) {
        screen_id = Screen.Home;
    }
}

// Saves the board as first dealt to the player's level folder.
fn export_board() {
    var out: u8[>..] = [];
    var meta = info;
    if meta.name.len == 0 {
        meta.name.clear();
        format(meta.name, level_title());
    }
    write_level(start_board, meta, out);
    let name = if mode == PlayMode.Seed { str("seed_", play_seed, "_like_", play_like, ".json") }
               else { str("level_", level_number, ".json") };
    let path = str(user_levels_dir(), "/", name);
    if write_file(path, out) { say(str("Saved ", name), 3.0); } else { say("Could not save the board.", 3.0); }
}

fn handle_keys() {
    if gfx::key_pressed("Escape") {
        if overlay == Overlay.Intro || overlay == Overlay.Reset { overlay = Overlay.None; }
        else if screen_id != Screen.Home { screen_id = Screen.Home; overlay = Overlay.None; finish_animations(); }
        else { gfx::quit(); }
    }
    if screen_id != Screen.Play || pending_load { return; }
    let ctrl = gfx::key_down("Left Ctrl") || gfx::key_down("Right Ctrl");
    if overlay == Overlay.Win && (gfx::key_pressed("N") || gfx::key_pressed("Return")) { next_after_win(); return; }
    if overlay == Overlay.Intro && (gfx::key_pressed("Return") || gfx::key_pressed("Space")) { overlay = Overlay.None; return; }
    if won_at >= 0.0 { return; }
    if gfx::key_pressed("U") || (ctrl && gfx::key_pressed("Z")) || gfx::key_pressed("Backspace") { do_undo(); }
    if gfx::key_pressed("R") { do_restart(); }
    if overlay != Overlay.None && overlay != Overlay.Lose { return; }
    if gfx::key_pressed("S") { do_shuffle(); }
    if gfx::key_pressed("F") { do_extra_bottle(); }
    if gfx::key_pressed("H") { do_hint(); }
    if gfx::key_pressed("E") { export_board(); }
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
    let m = gfx::mouse_pos();
    pointer = v2((m.x - offset.x) / scale, (m.y - offset.y) / scale);
    for e in gfx::events() {
        if e.kind == gfx::EVENT_MOUSE_BUTTON && e.down && e.button == gfx::MOUSE_LEFT && clicks.len < 16 {
            clicks.push(v2((e.x - offset.x) / scale, (e.y - offset.y) / scale));
        }
    }
}

fn draw_frame(dt: f32) {
    var base: Inst[>..] = [];
    var top: Inst[>..] = [];
    var ink: Inst[>..] = [];
    let theme = current_theme();
    look.light = scene_light(theme, now);
    // The room (scene.goose); no clicks while the ink moves between screens.
    draw_scene(base, theme);
    if screen_id == Screen.Play {
        update_back_shelf(board);
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
    else if screen_id == Screen.Files { draw_files(base); }
    else if screen_id == Screen.Map { draw_map(base); }
    if screen_id != Screen.Play { draw_overlay(top); }
    draw_drops(top);
    draw_finale(top);
    draw_particles(top);
    draw_transition(ink);
    to_screen(base);
    to_screen(top);
    to_screen(ink);
    look.screen = float4 { screen_px.x, screen_px.y, (now % 1000.0) as f32, if save.color_safe { 1.0 } else { 0.0 } };
    fill_palette(look, save.color_safe);
    flush_layer(board_layer, base, look, true);
    end_text(0);
    flush_layer(overlay_layer, top, look, false);
    end_text(1);
    if ink.len > 0 { flush_layer(ink_layer, ink, look, false); }
}

// Whether this frame has anything moving or waiting on input soon.
fn lively() -> bool {
    if pending_load || any_pouring() || taps.len > 0 || clicks.len > 0 { return true; }
    if screen_id == Screen.Play && (shuffling || !board_search.done) { return true; }
    let d = gfx::mouse_delta();
    if d.x != 0.0 || d.y != 0.0 || gfx::mouse_down(gfx::MOUSE_LEFT) { return true; }
    if now - overlay_t < 0.6 || now < message_until || now < hint_until || autoplay { return true; }
    if won_at >= 0.0 && now - won_at < 1.5 { return true; }
    for p in particles { if p.life > 0.0 { return true; } }
    for i in MAX_BOTTLES {
        if now < shake_until[i] || now - complete_at[i] < 1.3 { return true; }
    }
    fx_lively()
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
    var shot: u8[>..] = [];
    var start_level = -1;
    var start_seed_value: i64 = -1;
    var like = 20;
    var start_path: u8[>..] = [];
    var clicks_script: float2[>..] = [];
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
        else if opt == "--file" && has_value { start_path.append(argv[a + 1]); a++; }
        else if opt == "--autoplay" { autoplay = true; }
        else if opt == "--click" && a + 2 < argv.len {
            let x, okx = parse_int(argv[a + 1]);
            let y, oky = parse_int(argv[a + 2]);
            if okx && oky { clicks_script.push(v2(x, y)); }
            a += 2;
        }
        else if opt == "--help" {
            print("""
                alchemists-sort [--level N] [--seed S [--like L]] [--file level.json] [--autoplay]
                  --level N      play campaign level N
                  --seed S       play the board brewed from seed S, shaped like level L (default 20)
                  --file F       play a hand-made level file
                  --autoplay     let the hint solver play
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

    guard gfx::open("Alchemist's Sort", 540, 960, gfx::WINDOW_RESIZABLE) else {
        write_stderr(str("could not open a window: ", gfx::error(), "\n"));
        exit(1);
    }
    if !init_draw() { abort(str("could not make the pipeline: ", gfx::error())); }
    if !init_text(font_dir) { abort(str("could not load fonts: ", ui::error())); }
    if frames < 0 { init_sounds(); }
    rand = rng { random_seed() };
    fit_canvas();
    if start_path.len > 0 { start_file(start_path); }
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
        // Scripted clicks for testing, one every 20 frames after the first 10.
        if drawn >= 10 && (drawn - 10) % 20 == 0 && (drawn - 10) / 20 < clicks_script.len {
            clicks.push(clicks_script[(drawn - 10) / 20]);
        }
        if pending_load && !brewing && drawn > 0 { do_pending_load(); }
        step_jobs();
        handle_keys();
        if screen_id == Screen.Play && !pending_load { update_play(dt); }
        update_particles(dt);
        update_fx(dt);
        draw_frame(dt);
        update_transition();
        drawn++;
        // When nothing moves, draw a few frames a second instead of sixty:
        // with software rendering every frame costs real CPU.
        if frames < 0 && !lively() { sleep_ms(70); }
        if drawn == frames { break; }
    }
    if shot.len > 0 {
        if !gfx::screenshot(shot) { write_stderr(str("screenshot failed: ", gfx::error(), "\n")); }
    }
    close_sounds();
    ui::destroy(contexts[0]);
    ui::destroy(contexts[1]);
    gfx::close();
}
