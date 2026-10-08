// The puzzle's rules: bottles, pours and every modifier. Nothing here knows
// about drawing, input or files; the game, the solver, the generator and the
// tests all run the same code. docs/revamp.md is the design it follows.
//
// A bottle holds up to `cap` segments, bottom first: CAP, or more for a tall
// flask. Liquids are 1..MAX_LIQUID; 0 is "no liquid". A bottle has parts that
// combine freely: a body (what kind of flask it is), at most one cover over
// it, at most one fixture by it, and maybe a twin it is joined to. Modifiers
// reach each other through a few forces: heat, light, flow, flip, growth and
// transmutation.

import std;

let CAP = 4;            // an ordinary flask, and how much there is of most colors
let MAX_CAP = 8;        // the tallest flask
let MAX_BOTTLES = 24;
let MAX_COLORS = 14;    // the dyes, 1..MAX_COLORS
let QUICKSILVER = 15;   // a liquid that sinks
let GOLD = 16;          // an ordinary color, and what an athanor makes of quicksilver
let DROP = 17;          // the Philosopher's Drop: one wild segment
let MAX_LIQUID = 17;
let EMERALD = 5;        // the color that withers a creeping vine
let MAX_EVENTS = 32;

// What kind of flask it is.
enum Body {
    Plain,
    Vow,        // takes the first color poured in, then only that; must end full
    Siphon,     // pours its bottom run, from a tap at the base
    Hourglass,  // flips over every `flip_every` pours made anywhere
    Athanor,    // turns quicksilver poured in into gold
    Moonpetal,  // takes liquid only while some lantern is lit
}

// What lies over it. Every cover blocks pours in and out, but a seal can be
// broken by a pour.
enum Cover {
    None,
    Seal,       // contents hidden; breaks for color `key` or the Drop, or after two heat pulses
    Rime,       // ice: melts after `thaw` more pours, or sooner with heat
    Shroud,     // hidden and inert until light reaches it
    Vine,       // a tendril of a creeping vine; heat burns it
}

// What stands by it.
enum Fixture {
    None,
    Brazier,    // a pour into this flask sends heat to its neighbors
    Lantern,    // lights for good when this flask is completed
    Catalyst,   // when this flask is completed: every brazier, hourglass and lantern goes off
    VineRoot,   // a creeping vine that spreads every `spread_every` pours
}

let ALL_BODIES: const Body[6] = [Body.Plain, Body.Vow, Body.Siphon, Body.Hourglass, Body.Athanor,
                                 Body.Moonpetal];
let ALL_COVERS: const Cover[5] = [Cover.None, Cover.Seal, Cover.Rime, Cover.Shroud, Cover.Vine];
let ALL_FIXTURES: const Fixture[5] = [Fixture.None, Fixture.Brazier, Fixture.Lantern, Fixture.Catalyst,
                                      Fixture.VineRoot];

fn body_index(b: Body) -> i64 {
    match b { Plain => 0, Vow => 1, Siphon => 2, Hourglass => 3, Athanor => 4, Moonpetal => 5 }
}

fn cover_index(c: Cover) -> i64 {
    match c { None => 0, Seal => 1, Rime => 2, Shroud => 3, Vine => 4 }
}

fn fixture_index(f: Fixture) -> i64 {
    match f { None => 0, Brazier => 1, Lantern => 2, Catalyst => 3, VineRoot => 4 }
}

struct Bottle {
    seg: u8[8],             // bottom to top; only the first `n` mean anything
    n: u8 = 0,
    cap: u8 = 4,            // segments it holds: CAP, or more for a tall flask
    murk: u8 = 0,           // bit k: segment k shows as smoke
    body: Body = Body.Plain,
    vow: u8 = 0,            // Vow: the color it took, once one is poured in
    flip_every: u8 = 0,     // Hourglass: pours between flips
    flip_count: u8 = 0,     //   and those counted toward the next one
    cover: Cover = Cover.None,
    key: u8 = 0,            // Seal: the color that breaks it
    soft: u8 = 0,           // Seal: heat pulses taken; the second breaks it
    thaw: u8 = 0,           // Rime: pours left before it melts
    fixture: Fixture = Fixture.None,
    lit: bool = false,      // Lantern
    spent: bool = false,    // Catalyst
    spread_every: u8 = 0,   // VineRoot: pours between spreads
    spread_count: u8 = 0,   //   and those counted toward the next one
    twin: i8 = -1,          // the neighbor it is joined to by a tube
    done: bool = false,     // completed and sealed
}

struct Board {
    bottles: Bottle[MAX_BOTTLES],
    count: i64 = 0,         // bottles in use
    colors: i64 = 0,        // flasks the level fills: its distinct colors
    pours: i64 = 0,         // successful pours so far
    per_row: i64 = 0,       // flasks on a shelf row, fixed once the board is settled
    salamander: i64 = -1,   // the flask the salamander sits on, or -1
}

// Things a pour set off, in order, for the game to animate. `bottle` is the
// flask it happened to; `from` where it came from (the heat's source, the
// flask that overflowed, the salamander's last perch...) or -1.
enum EventKind {
    SealBroken, SealSoftened, Thawed, HeatPulse, Lit, ShroudLifted, MurkCleared, Flipped, VineSpread,
    VineWithered, TendrilBurned, SalamanderHop, Transmuted, Overflowed, CatalystFired, Completed,
}

struct Event { kind: EventKind, bottle: i8 = -1, from: i8 = -1 }

// What a pour did, for the game to animate and the tests to check.
struct PourResult {
    ok: bool = false,
    color: i64 = 0,
    amount: i64 = 0,        // segments that landed in the destination (0 when only a seal broke)
    overflow: i64 = 0,      // segments that went on into its twin
    popped: bool = false,   // the destination's seal broke
    completed: bool = false,// the destination is now complete
    thawed: i64 = 0,        // bottles whose ice melted
    revealed: i64 = 0,      // shrouds lifted
    events: Event[..32] = [],
}

fn note(r: PourResult&, kind: EventKind, bottle: i64, from: i64) {
    if r.events.len < MAX_EVENTS { r.events.push(Event { kind, bottle as i8, from as i8 }); }
}

// --- reading a bottle ----------------------------------------------------------

fn size(b: Bottle) -> i64 { b.n }

fn top(b: Bottle) -> i64 {
    if b.n == 0 { return 0; }
    b.seg[b.n - 1]
}

fn murky(b: Bottle, k: i64) -> bool { (b.murk as i64 >> k) & 1 != 0 }

// The contiguous run of the top color, counting visible segments only. The
// Drop never joins a run.
fn top_run(b: Bottle) -> i64 {
    let n: i64 = b.n;
    if n == 0 { return 0; }
    let c = b.seg[n - 1];
    if c == DROP { return 1; }
    var i = n - 1;
    var run = 0;
    while i >= 0 && !murky(b, i) && b.seg[i] == c {
        run++;
        i--;
    }
    run
}

// The run a siphon's tap lets out: equal segments from the bottom up.
fn bottom_run(b: Bottle) -> i64 {
    if b.n == 0 { return 0; }
    let c = b.seg[0];
    if c == DROP { return 1; }
    var run = 0;
    while run < b.n && !murky(b, run) && b.seg[run] == c { run++; }
    run
}

// The color and amount a pour from this bottle would try to move.
fn pour_color(b: Bottle) -> i64 {
    if b.n == 0 { return 0; }
    if b.body == Body.Siphon { b.seg[0] } else { top(b) }
}

fn pour_run(b: Bottle) -> i64 { if b.body == Body.Siphon { bottom_run(b) } else { top_run(b) } }

// The color a full flask is made of, the Drop standing in for any; 0 when it
// is not one color.
fn flask_color(b: Bottle) -> i64 {
    var c = 0;
    for k in b.n as i64 {
        let s: i64 = b.seg[k];
        if s == DROP { continue; }
        if c == 0 { c = s; } else if s != c { return 0; }
    }
    c
}

fn is_complete(b: Bottle) -> bool { b.n == b.cap && flask_color(b) != 0 }

// Every segment one color (or none at all).
fn is_uniform(b: Bottle) -> bool {
    for i in 1..b.n as i64 { if b.seg[i] != b.seg[0] { return false; } }
    true
}

fn covered(b: Bottle) -> bool { b.cover != Cover.None }

// Hidden from view entirely: under a seal or a shroud.
fn contents_hidden(b: Bottle) -> bool { b.cover == Cover.Seal || b.cover == Cover.Shroud }

fn can_pour_from(b: Bottle) -> bool { b.n > 0 && !b.done && !covered(b) }

fn has_body(board: Board, body: Body) -> bool {
    for i in board.count { if board.bottles[i].body == body { return true; } }
    false
}

fn any_lantern_lit(board: Board) -> bool {
    for i in board.count {
        let b = board.bottles[i];
        if b.fixture == Fixture.Lantern && b.lit { return true; }
    }
    false
}

// --- shelves and neighbors -------------------------------------------------------

fn tallest_cap(board: Board) -> i64 {
    var t = CAP;
    for i in board.count { t = max(t, board.bottles[i].cap); }
    t
}

// How many flasks stand on a shelf row: the row count that lets them be
// drawn largest on the game's board area (510 by 670 units, a flask 0.68
// wide per unit of its half width). The layout uses it too, so the rules'
// neighbors are the ones on screen.
fn shelf_per_row(count: i64, tallest: i64) -> i64 {
    let n = max(1, count);
    let rise = (tallest - CAP) * 1.26;      // in half widths
    var best_rows = 1;
    var best_hx = 0.0;
    for rows in 1..6 {
        let per = (n + rows - 1) / rows;
        let hx_w = 510.0 / per * 0.34;
        let hx_h = (670.0 / rows - 34.0) / (7.6 + rise);
        let hx = min(min(hx_w, hx_h), 30.0);
        if hx > best_hx + 0.5 {
            best_hx = hx;
            best_rows = rows;
        }
    }
    (n + best_rows - 1) / best_rows
}

fn row_length(board: Board) -> i64 {
    if board.per_row > 0 { board.per_row } else { shelf_per_row(board.count, tallest_cap(board)) }
}

// The flasks either side of `i` on its shelf row, or -1.
fn neighbors(board: Board, i: i64) -> i64, i64 {
    let per = row_length(board);
    let left = if i > 0 && i % per != 0 { i - 1 } else { -1 };
    let right = if i + 1 < board.count && (i + 1) % per != 0 { i + 1 } else { -1 };
    return left, right;
}

fn are_neighbors(board: Board, a: i64, b: i64) -> bool {
    let l, r = neighbors(board, a);
    b >= 0 && (b == l || b == r)
}

// --- what goes where ---------------------------------------------------------------

// Whether flask `j`, cover aside, would take `color` on what it holds if it
// had room: body rules, the salamander and the top match.
fn fits(board: Board, j: i64, color: i64) -> bool {
    let b = board.bottles[j];
    if b.done || color == 0 || j == board.salamander { return false; }
    if b.body == Body.Moonpetal && !any_lantern_lit(board) { return false; }
    if color == DROP { return true; }
    if b.body == Body.Vow && b.vow != 0 && b.vow != color { return false; }
    if color == QUICKSILVER {
        // It sinks, so the top does not matter, except to a furnace that
        // has to put gold on gold.
        if b.body == Body.Athanor { return b.n == 0 || top(b) == GOLD || top(b) == DROP; }
        return true;
    }
    b.n == 0 || top(b) == color || top(b) == DROP
}

fn takes(board: Board, j: i64, color: i64) -> bool {
    board.bottles[j].n < board.bottles[j].cap && fits(board, j, color)
}

// Whether a pour of `color` is accepted (it may still move nothing, when it
// only breaks a seal over a bottle it does not fit in).
fn accepts(board: Board, j: i64, color: i64) -> bool {
    let b = board.bottles[j];
    match b.cover {
        None => takes(board, j, color),
        Seal => !b.done && j != board.salamander && color != 0 && (color == b.key || color == DROP),
        Rime, Shroud, Vine => false,
    }
}

fn can_pour(board: Board, from: i64, to: i64) -> bool {
    if from == to || from < 0 || to < 0 || from >= board.count || to >= board.count { return false; }
    let src = board.bottles[from];
    if !can_pour_from(src) { return false; }
    accepts(board, to, pour_color(src))
}

// --- making bottles -------------------------------------------------------------

fn bottle(colors: const i64[:]) -> Bottle {
    assert(colors.len <= CAP);
    var b = Bottle { seg: [0; 8], .. };
    for c, i in colors { b.seg[i] = c as u8; }
    b.n = colors.len as u8;
    b
}

fn push_bottle(board: Board&, b: Bottle) -> i64 {
    assert(board.count < MAX_BOTTLES);
    board.bottles[board.count] = b;
    board.count++;
    board.count - 1
}

// Adds an empty bottle, as the extra-bottle tool does. False when full up. It
// joins the last row or starts a new one; the rows stay as they were.
fn add_empty_bottle(board: Board&) -> bool {
    if board.count >= MAX_BOTTLES { return false; }
    if board.per_row == 0 { board.per_row = row_length(board); }
    push_bottle(board, Bottle { seg: [0; 8], .. });
    true
}

// --- moving liquid ----------------------------------------------------------------

// Takes one segment off a flask's pouring end: the top, or a siphon's tap.
fn take_one(b: Bottle&) -> i64 {
    let n: i64 = b.n;
    if b.body == Body.Siphon {
        let c: i64 = b.seg[0];
        for k in 1..n { b.seg[k - 1] = b.seg[k]; }
        b.seg[n - 1] = 0;
        b.n--;
        b.murk = b.murk >> 1;
        return c;
    }
    let c: i64 = b.seg[n - 1];
    b.seg[n - 1] = 0;
    b.n--;
    b.murk = ((b.murk as i64) & ((1 << (n - 1)) - 1)) as u8;
    c
}

// Puts one segment in: quicksilver sinks below everything but quicksilver,
// carrying the murk of what it slides under up with it; the rest lands on top.
fn put_one(b: Bottle&, c: i64) {
    let n: i64 = b.n;
    if c == QUICKSILVER {
        var at = 0;
        while at < n && b.seg[at] == QUICKSILVER { at++; }
        var k = n;
        while k > at {
            b.seg[k] = b.seg[k - 1];
            k--;
        }
        b.seg[at] = c as u8;
        let m: i64 = b.murk;
        b.murk = ((m & ((1 << at) - 1)) | ((m >> at) << (at + 1))) as u8;
    } else {
        b.seg[n] = c as u8;
    }
    b.n++;
}

// Settles quicksilver to the bottom, keeping the order of everything else.
fn sink_quicksilver(b: Bottle&) {
    var seg: u8[8] = [0; 8];
    var murk = 0;
    var at = 0;
    for pass in 2 {
        for k in b.n as i64 {
            if (b.seg[k] == QUICKSILVER) != (pass == 0) { continue; }
            seg[at] = b.seg[k];
            if murky(b, k) { murk |= 1 << at; }
            at++;
        }
    }
    b.seg = seg;
    b.murk = murk as u8;
}

// One segment from `from` into `to`, with what happens as it lands.
fn move_one(board: Board&, from: i64, to: i64, r: PourResult&) {
    let c = take_one(board.bottles[from]);
    var dst .= board.bottles[to];
    if c == QUICKSILVER && dst.body == Body.Athanor {
        put_one(dst, GOLD);
        note(r, EventKind.Transmuted, to, from);
        return;
    }
    put_one(dst, c);
    if dst.body == Body.Vow && dst.vow == 0 && c != DROP { dst.vow = c as u8; }
}

// The top segment of every flask is in plain view.
fn clear_top_murk(board: Board&, i: i64, r: PourResult&) {
    var b .= board.bottles[i];
    let n: i64 = b.n;
    let keep = if n == 0 { 0 } else { (b.murk as i64) & ((1 << (n - 1)) - 1) };
    if keep != b.murk {
        b.murk = keep as u8;
        if n > 0 { note(r, EventKind.MurkCleared, i, -1); }
    }
}

// --- the forces --------------------------------------------------------------------

// A heat pulse on flask `i`: ice melts a pour's worth, a seal softens (and
// breaks the second time), a vine tendril burns.
fn heat(board: Board&, i: i64, source: i64, r: PourResult&) {
    if i < 0 { return; }
    note(r, EventKind.HeatPulse, i, source);
    var b .= board.bottles[i];
    match b.cover {
        Rime => {
            if b.thaw > 0 { b.thaw--; }
            if b.thaw == 0 {
                b.cover = Cover.None;
                r.thawed++;
                note(r, EventKind.Thawed, i, source);
            }
        },
        Seal => {
            b.soft++;
            if b.soft >= 2 {
                b.cover = Cover.None;
                b.soft = 0;
                note(r, EventKind.SealBroken, i, source);
            } else {
                note(r, EventKind.SealSoftened, i, source);
            }
        },
        Vine => {
            b.cover = Cover.None;
            note(r, EventKind.TendrilBurned, i, source);
        },
        None, Shroud => {},
    }
}

// Heat to a flask's neighbors, and to itself when `own` is set.
fn heat_around(board: Board&, i: i64, own: bool, r: PourResult&) {
    let left, right = neighbors(board, i);
    if own { heat(board, i, i, r); }
    heat(board, left, i, r);
    heat(board, right, i, r);
}

// Light from a lantern at `i` reaches it and its neighbors: murk clears and
// shrouds lift.
fn shine(board: Board&, i: i64, r: PourResult&) {
    let left, right = neighbors(board, i);
    let reach: i64[3] = [left, i, right];
    for j in reach {
        if j < 0 { continue; }
        var b .= board.bottles[j];
        if b.murk != 0 {
            b.murk = 0;
            note(r, EventKind.MurkCleared, j, i);
        }
        if b.cover == Cover.Shroud {
            b.cover = Cover.None;
            r.revealed++;
            note(r, EventKind.ShroudLifted, j, i);
        }
    }
}

fn light_lantern(board: Board&, i: i64, r: PourResult&) {
    var b .= board.bottles[i];
    if b.fixture != Fixture.Lantern || b.lit { return; }
    b.lit = true;
    note(r, EventKind.Lit, i, -1);
    shine(board, i, r);
}

// An hourglass turns over: the stack reverses with its murk, quicksilver
// runs back down, and the new top is in view.
fn flip(board: Board&, i: i64, r: PourResult&) {
    var b .= board.bottles[i];
    let n: i64 = b.n;
    var seg = b.seg;
    var murk = 0;
    for k in n {
        seg[k] = b.seg[n - 1 - k];
        if murky(b, n - 1 - k) { murk |= 1 << k; }
    }
    b.seg = seg;
    b.murk = murk as u8;
    sink_quicksilver(b);
    note(r, EventKind.Flipped, i, -1);
    clear_top_murk(board, i, r);
}

fn can_flip(b: Bottle) -> bool { b.body == Body.Hourglass && !b.done && !covered(b) }

// A creeping vine grows a tendril over the lowest-numbered flask next to its
// root or a tendril that is not done, not covered and not the root.
fn spread(board: Board&, root: i64, r: PourResult&) {
    for j in board.count {
        let b = board.bottles[j];
        if j == root || b.done || covered(b) { continue; }
        let left, right = neighbors(board, j);
        var next_to = false;
        for k in [left, right] {
            if k < 0 { continue; }
            if k == root || board.bottles[k].cover == Cover.Vine { next_to = true; }
        }
        if next_to {
            board.bottles[j].cover = Cover.Vine;
            note(r, EventKind.VineSpread, j, root);
            return;
        }
    }
}

fn wither(board: Board&, root: i64, r: PourResult&) {
    for i in board.count { if board.bottles[i].cover == Cover.Vine { board.bottles[i].cover = Cover.None; } }
    var b .= board.bottles[root];
    b.fixture = Fixture.None;
    b.spread_every = 0;
    b.spread_count = 0;
    note(r, EventKind.VineWithered, root, -1);
}

// Everything that counts pours made anywhere, in order: ice, hourglasses,
// vines.
fn tick(board: Board&, r: PourResult&) {
    for i in board.count {
        var b .= board.bottles[i];
        if b.cover != Cover.Rime { continue; }
        if b.thaw > 0 { b.thaw--; }
        if b.thaw == 0 {
            b.cover = Cover.None;
            r.thawed++;
            note(r, EventKind.Thawed, i, -1);
        }
    }
    for i in board.count {
        var b .= board.bottles[i];
        if !can_flip(b) || b.flip_every == 0 { continue; }
        b.flip_count++;
        if b.flip_count >= b.flip_every {
            b.flip_count = 0;
            flip(board, i, r);
        }
    }
    for i in board.count {
        var b .= board.bottles[i];
        if b.fixture != Fixture.VineRoot || b.spread_every == 0 { continue; }
        b.spread_count++;
        if b.spread_count >= b.spread_every {
            b.spread_count = 0;
            spread(board, i, r);
        }
    }
}

// --- completing flasks --------------------------------------------------------------

// Complete for the rules: in a level with an athanor, quicksilver is gold
// still to be made and never completes a flask.
fn complete_on(board: Board, i: i64) -> bool {
    let b = board.bottles[i];
    if !is_complete(b) { return false; }
    flask_color(b) != QUICKSILVER || !has_body(board, Body.Athanor)
}

fn seal_if_complete(board: Board&, i: i64, r: PourResult&) -> bool {
    let b = board.bottles[i];
    if b.done || covered(b) || !complete_on(board, i) { return false; }
    board.bottles[i].done = true;
    board.bottles[i].murk = 0;
    note(r, EventKind.Completed, i, -1);
    true
}

fn fire_catalyst(board: Board&, i: i64, r: PourResult&) {
    board.bottles[i].spent = true;
    note(r, EventKind.CatalystFired, i, -1);
    for j in board.count { if board.bottles[j].fixture == Fixture.Brazier { heat_around(board, j, false, r); } }
    for j in board.count { if can_flip(board.bottles[j]) { flip(board, j, r); } }
    for j in board.count { light_lantern(board, j, r); }
}

// Seals complete flasks and sets off their lanterns and catalysts, until
// nothing changes: light or heat can uncover a flask that is already complete.
fn complete_flasks(board: Board&, to: i64, r: PourResult&) {
    loop {
        var changed = false;
        for i in board.count {
            if seal_if_complete(board, i, r) {
                changed = true;
                if i == to { r.completed = true; }
            }
        }
        for i in board.count {
            let b = board.bottles[i];
            if !b.done { continue; }
            if b.fixture == Fixture.Lantern && !b.lit {
                light_lantern(board, i, r);
                changed = true;
            }
            if b.fixture == Fixture.Catalyst && !b.spent {
                fire_catalyst(board, i, r);
                changed = true;
            }
        }
        if !changed { break; }
    }
}

// --- pouring --------------------------------------------------------------------

// Pours from bottle `from` into bottle `to`, following every rule, in the
// order of docs/revamp.md. The board is unchanged when the pour is not
// allowed (`ok` false).
fn pour(board: Board&, from: i64, to: i64) -> PourResult {
    var r = PourResult {};
    if !can_pour(board, from, to) { return r; }
    r.ok = true;
    let color = pour_color(board.bottles[from]);
    let run = pour_run(board.bottles[from]);
    r.color = color;

    // The liquid moves: through a seal, sinking, transmuted, overflowing.
    if board.bottles[to].cover == Cover.Seal {
        board.bottles[to].cover = Cover.None;
        board.bottles[to].soft = 0;
        r.popped = true;
        note(r, EventKind.SealBroken, to, from);
    }
    var amount = 0;
    while amount < run && takes(board, to, color) {
        move_one(board, from, to, r);
        amount++;
    }
    r.amount = amount;
    // What would have landed but found no room goes on through the tube.
    let tw: i64 = board.bottles[to].twin;
    if amount < run && tw >= 0 && tw != from && fits(board, to, color) && !covered(board.bottles[tw]) {
        var spill = 0;
        while amount + spill < run && takes(board, tw, color) {
            move_one(board, from, tw, r);
            spill++;
        }
        r.overflow = spill;
        if spill > 0 { note(r, EventKind.Overflowed, tw, to); }
    }
    for i in board.count { clear_top_murk(board, i, r); }

    board.pours++;
    tick(board, r);

    let dst = board.bottles[to];
    if dst.fixture == Fixture.Brazier { heat_around(board, to, false, r); }
    if dst.fixture == Fixture.VineRoot && color == EMERALD { wither(board, to, r); }

    if board.salamander >= 0 {
        let was = board.salamander;
        board.salamander = from;
        note(r, EventKind.SalamanderHop, from, was);
        heat_around(board, from, true, r);
    }

    complete_flasks(board, to, r);
    r
}

// --- the end of a level ---------------------------------------------------------

fn is_won(board: Board) -> bool {
    for i in board.count {
        let b = board.bottles[i];
        if b.n == 0 && b.body != Body.Vow { continue; }
        if !complete_on(board, i) { return false; }
    }
    true
}

fn has_move(board: Board) -> bool {
    for i in board.count {
        for j in board.count { if can_pour(board, i, j) { return true; } }
    }
    false
}

fn is_lost(board: Board) -> bool { !is_won(board) && !has_move(board) }

// Brings a built or loaded level into a consistent start: fixes the shelf
// rows, settles quicksilver, clears murk off the tops, and seals what starts
// complete (lighting lanterns and so on). A level is passed through this once.
fn settle(board: Board&) {
    if board.per_row == 0 { board.per_row = row_length(board); }
    var r = PourResult {};
    for i in board.count {
        var b .= board.bottles[i];
        let n: i64 = b.n;
        b.murk = ((b.murk as i64) & ((1 << n) - 1)) as u8;
        sink_quicksilver(b);
        if b.body == Body.Vow && b.vow == 0 { b.vow = flask_color(b) as u8; }
        if b.cover == Cover.Rime && b.thaw == 0 { b.cover = Cover.None; }
        if b.cover == Cover.Seal && b.soft >= 2 { b.cover = Cover.None; }
        clear_top_murk(board, i, r);
    }
    for i in board.count { if board.bottles[i].lit { shine(board, i, r); } }
    complete_flasks(board, -1, r);
}

// Seals whatever is complete now, as after a shuffle.
fn seal_complete(board: Board&) {
    var r = PourResult {};
    complete_flasks(board, -1, r);
}

// --- structural checks, for loaded and generated levels ---------------------

// Empty when the board is well formed, else what is wrong with it.
fn validate(board: Board) -> u8[>..] {
    var tally: i64[MAX_LIQUID + 1] = [0; MAX_LIQUID + 1];
    if board.count < 2 { return str("a level needs at least two bottles"); }
    if board.salamander >= board.count { return str("the salamander sits on a bottle that is not there"); }
    var roots = 0;
    var vines = 0;
    for i in board.count {
        let b = board.bottles[i];
        if b.cap < CAP || b.cap > MAX_CAP { return str("bottle ", i + 1, " is not ", CAP, " to ", MAX_CAP, " tall"); }
        if b.n > b.cap { return str("bottle ", i + 1, " holds more than ", b.cap); }
        for k in b.n as i64 {
            let c: i64 = b.seg[k];
            if c < 1 || c > MAX_LIQUID { return str("bottle ", i + 1, " has an unknown color"); }
            tally[c]++;
        }
        if b.cover == Cover.Seal && (b.key < 1 || b.key >= DROP) {
            return str("bottle ", i + 1, " needs a key color for its seal");
        }
        if b.body == Body.Hourglass && b.flip_every == 0 { return str("bottle ", i + 1, " needs a flip count"); }
        if b.body == Body.Siphon && b.murk != 0 { return str("bottle ", i + 1, ": a siphon cannot hold murk"); }
        if b.fixture == Fixture.VineRoot {
            roots++;
            if b.spread_every == 0 { return str("bottle ", i + 1, " needs a spread count"); }
        }
        if b.cover == Cover.Vine { vines++; }
        if b.cover == Cover.Shroud {
            let l, r = neighbors(board, i);
            var lantern = false;
            for k in [l, r] { if k >= 0 && board.bottles[k].fixture == Fixture.Lantern { lantern = true; } }
            if !lantern { return str("bottle ", i + 1, ": a shroud needs a lantern next to it"); }
        }
        if b.twin >= 0 {
            let t: i64 = b.twin;
            if t >= board.count || board.bottles[t].twin != i || !are_neighbors(board, i, t) {
                return str("bottle ", i + 1, ": twins are neighbors joined to each other");
            }
        }
    }
    if roots > 1 { return str("a level has at most one creeping vine"); }
    if vines > 0 && roots == 0 { return str("vine tendrils need a root"); }
    if tally[DROP] > 1 { return str("a level has at most one Philosopher's Drop"); }
    if has_body(board, Body.Athanor) {
        // Quicksilver is gold still to be made: the two are one color.
        if tally[QUICKSILVER] == 0 { return str("an athanor needs quicksilver"); }
        tally[GOLD] += tally[QUICKSILVER];
        tally[QUICKSILVER] = 0;
    }
    // Every color fills ordinary flasks or a tall one of its own; with the
    // Drop, one color is a segment short.
    var tall_used: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
    var short: i64[>..] = [];
    var colors = 0;
    for c in 1..DROP {
        if tally[c] == 0 { continue; }
        colors++;
        if tally[c] == CAP { continue; }
        var fits = false;
        for i in board.count {
            if !tall_used[i] && board.bottles[i].cap == tally[c] {
                tall_used[i] = true;
                fits = true;
                break;
            }
        }
        if !fits { short.push(c); }
    }
    if colors == 0 { return str("a level needs some liquid"); }
    var drop_used = tally[DROP] == 0;
    for c in short {
        var fits = false;
        if !drop_used {
            if tally[c] + 1 == CAP { fits = true; }
            for i in board.count {
                if !fits && !tall_used[i] && board.bottles[i].cap == tally[c] + 1 {
                    tall_used[i] = true;
                    fits = true;
                }
            }
        }
        if !fits { return str("color ", c, " has ", tally[c], " segments, not ", CAP, " or a tall flask's height"); }
        drop_used = true;
    }
    // A color of CAP with the Drop fills a flask one taller.
    for i in board.count {
        if !drop_used && !tall_used[i] && board.bottles[i].cap == CAP + 1 { drop_used = true; }
    }
    if !drop_used { return str("the Philosopher's Drop stands in for a missing segment, and none is missing"); }
    str("")
}

// The colors the level fills, counting quicksilver as gold when there is an
// athanor to make it so.
fn color_count(board: Board) -> i64 {
    var seen: bool[MAX_LIQUID + 1] = [false; MAX_LIQUID + 1];
    let athanor = has_body(board, Body.Athanor);
    var colors = 0;
    for i in board.count {
        let b = board.bottles[i];
        for k in b.n as i64 {
            var c: i64 = b.seg[k];
            if c == DROP { continue; }
            if athanor && c == QUICKSILVER { c = GOLD; }
            if !seen[c] { seen[c] = true; colors++; }
        }
    }
    colors
}

fn bit(x: bool) -> u64 { if x { 1 } else { 0 } }

// Whether where a flask stands matters: anything that reaches its neighbors.
fn positional(board: Board) -> bool {
    if board.salamander >= 0 { return true; }
    for i in board.count {
        let b = board.bottles[i];
        if b.fixture != Fixture.None || b.twin >= 0 || b.cover == Cover.Vine { return true; }
    }
    false
}

// A 64-bit fingerprint of a position for the solver's visited set, covering
// everything that affects play. Bottles that differ only in where they stand
// hash alike, since swapping two of them changes nothing -- unless neighbors
// matter on this board, when the place is part of the hash.
fn board_hash(board: Board) -> u64 {
    let place = positional(board);
    var h: u64 = if place { hash(board.salamander as u64 + 77) } else { 0 };
    for i in board.count {
        let b = board.bottles[i];
        var x: u64 = 1469598103934665603;
        for k in b.n as i64 { x = (x ^ b.seg[k]) * 1099511628211; }
        let a: u64 = b.n | (b.cap as u64 << 4) | (b.murk as u64 << 8) |
                     (body_index(b.body) as u64 << 16) | (b.vow as u64 << 20) |
                     (b.flip_every as u64 << 28) | (b.flip_count as u64 << 36) |
                     (cover_index(b.cover) as u64 << 44) | (b.key as u64 << 48) | (b.soft as u64 << 56);
        let c: u64 = b.thaw | (fixture_index(b.fixture) as u64 << 8) | (b.spread_every as u64 << 12) |
                     (b.spread_count as u64 << 20) | ((b.twin as i64 + 1) as u64 << 28) |
                     (bit(b.lit) << 36) | (bit(b.spent) << 37) | (bit(b.done) << 38);
        x = (x ^ a) * 1099511628211;
        x = (x ^ c) * 1099511628211;
        if place { x = (x ^ (i as u64 << 40)) * 1099511628211; }
        h = h + hash(x);
    }
    h
}
