// The puzzle's rules: bottles, pours and every modifier. Nothing here knows
// about drawing, input or files; the game, the solver, the generator and the
// tests all run the same code. docs/revamp.md is the design it follows.
//
// A bottle holds up to `cap` segments, bottom first: CAP, or more for a tall
// flask. Liquids are 1..MAX_LIQUID; 0 is "no liquid". A bottle has parts that
// combine freely: a body (what kind of flask it is), at most one cover over
// it, at most one fixture by it, maybe a key buried in one of its layers,
// and maybe a door it stands behind. Modifiers reach each other through a
// few forces: heat, light, flow, flip, growth and transmutation.

import std;

let CAP = 4;            // an ordinary flask, and how much there is of most colors
let MAX_CAP = 14;       // the tallest flask: three rows of the grid
let MAX_BOTTLES = 24;
let MAX_COLORS = 14;    // the dyes, 1..MAX_COLORS
let QUICKSILVER = 15;   // a liquid that sinks
let GOLD = 16;          // an ordinary color, and what an athanor makes of quicksilver
let DROP = 17;          // the Philosopher's Drop: one wild segment
let MAX_LIQUID = 17;
let EMERALD = 5;        // the color that withers a creeping vine
let MAX_EVENTS = 32;
let MAX_DOORS = 3;

// The liquids' names, by number.
let COLOR_NAMES: const u8[:][18] = ["", "Ruby", "Amber", "Sun", "Lime", "Emerald", "Sky", "Sapphire",
                                    "Violet", "Rose", "Umber", "Pearl", "Slate", "Teal", "Olive",
                                    "Quicksilver", "Gold", "Philosopher's Drop"];

// What kind of flask it is.
enum Body {
    Plain,
    Vow,        // takes the first color poured in, then only that
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
    Curtain,    // hidden and inert until a flask of color `badge` is completed
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
let ALL_COVERS: const Cover[6] = [Cover.None, Cover.Seal, Cover.Rime, Cover.Shroud, Cover.Vine, Cover.Curtain];
let ALL_FIXTURES: const Fixture[5] = [Fixture.None, Fixture.Brazier, Fixture.Lantern, Fixture.Catalyst,
                                      Fixture.VineRoot];

fn body_index(b: Body) -> i64 {
    match b { Plain => 0, Vow => 1, Siphon => 2, Hourglass => 3, Athanor => 4, Moonpetal => 5 }
}

fn cover_index(c: Cover) -> i64 {
    match c { None => 0, Seal => 1, Rime => 2, Shroud => 3, Vine => 4, Curtain => 5 }
}

fn fixture_index(f: Fixture) -> i64 {
    match f { None => 0, Brazier => 1, Lantern => 2, Catalyst => 3, VineRoot => 4 }
}

// The metals keys come in. Each key opens the door of its metal, so a level
// has at most one door, and one key, of each.
enum KeyColor { None, Brass, Silver, Copper }

let KEY_COLORS: const KeyColor[3] = [KeyColor.Brass, KeyColor.Silver, KeyColor.Copper];

fn key_index(k: KeyColor) -> i64 { match k { None => 0, Brass => 1, Silver => 2, Copper => 3 } }

fn key_name(k: KeyColor) -> const u8[:] { match k { None => "", Brass => "Brass", Silver => "Silver", Copper => "Copper" } }

// A door in front of a few neighbors in one row of the grid: while it is
// shut they are out of play. Its key's freeing opens it for good.
struct Door { color: KeyColor = KeyColor.None, open: bool = false }

struct Bottle {
    seg: u8[MAX_CAP] = [0; MAX_CAP],   // bottom to top; only the first `n` mean anything
    n: u8 = 0,
    cap: u8 = 4,            // segments it holds: CAP, or more for a tall flask
    murk: u16 = 0,          // bit k: segment k shows as smoke
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
    badge: u8 = 0,          // Curtain: the color whose completion opens it
    keyed: u16 = 0,         // bit k: segment k holds the flask's key (one at most)
    key_color: KeyColor = KeyColor.None,    // that key's metal, until it is freed
    door: i8 = -1,          // the door it stands behind, or -1
    behind: bool = false,   // that door is shut (kept by settle and open_door)
    done: bool = false,     // completed and sealed
}

struct Board {
    bottles: Bottle[MAX_BOTTLES],
    count: i64 = 0,         // bottles in use
    colors: i64 = 0,        // flasks the level fills: its distinct colors
    pours: i64 = 0,         // successful pours so far
    salamander: i64 = -1,   // the flask the salamander sits on, or -1
    doors: Door[MAX_DOORS] = [Door {}; MAX_DOORS],
    door_count: i64 = 0,
    // The grid the flasks stand in (see place_grid): its columns, fixed
    // once placed, the rows in use (0 until placed), and each flask's cell,
    // the top row of a tall flask.
    cols: i64 = 0,
    rows: i64 = 0,
    row: i8[MAX_BOTTLES] = [-1; MAX_BOTTLES],
    col: i8[MAX_BOTTLES] = [-1; MAX_BOTTLES],
}

// Things a pour set off, in order, for the game to animate. `bottle` is the
// flask it happened to; `from` where it came from (the heat's source, the
// salamander's last perch, the key that opened a door...) or -1; `door`
// the door a key opens (KeyFreed) or that opened (DoorOpened, whose
// `bottle` is the first flask behind it).
enum EventKind {
    SealBroken, SealSoftened, Thawed, HeatPulse, Lit, ShroudLifted, MurkCleared, Flipped, VineSpread,
    VineWithered, TendrilBurned, SalamanderHop, Transmuted, CatalystFired, Completed, Vowed,
    KeyFreed, DoorOpened, CurtainOpened,
}

struct Event { kind: EventKind, bottle: i8 = -1, from: i8 = -1, door: i8 = -1 }

// What a pour did, for the game to animate and the tests to check.
struct PourResult {
    ok: bool = false,
    color: i64 = 0,
    amount: i64 = 0,        // segments that landed in the destination (0 when only a seal broke)
    popped: bool = false,   // the destination's seal broke
    completed: bool = false,// the destination is now complete
    thawed: i64 = 0,        // bottles whose ice melted
    revealed: i64 = 0,      // shrouds lifted
    events: Event[..32] = [],
}

fn note(r: PourResult&, kind: EventKind, bottle: i64, from: i64) {
    if r.events.len < MAX_EVENTS { r.events.push(Event { kind, bottle as i8, from as i8, -1 }); }
}

fn note_door(r: PourResult&, kind: EventKind, bottle: i64, from: i64, door: i64) {
    if r.events.len < MAX_EVENTS { r.events.push(Event { kind, bottle as i8, from as i8, door as i8 }); }
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

// Hidden from view entirely: under a seal, a shroud or a curtain, or
// behind a shut door.
fn contents_hidden(b: Bottle) -> bool {
    b.cover == Cover.Seal || b.cover == Cover.Shroud || b.cover == Cover.Curtain || b.behind
}

// Nothing ever comes out of a tall flask, nor out of one behind a shut door.
fn can_pour_from(b: Bottle) -> bool { b.n > 0 && !b.done && !covered(b) && !b.behind && b.cap <= CAP }

// The segment holding the flask's key, or -1 (none, or a tap let it out).
fn key_segment(b: Bottle) -> i64 {
    for k in b.n as i64 { if (b.keyed as i64 >> k) & 1 != 0 { return k; } }
    -1
}

// The layers still over a key: the runs of one color above its own.
fn layers_over_key(b: Bottle) -> i64 {
    let k = key_segment(b);
    if k < 0 { return 0; }
    var layers = 0;
    var last = b.seg[k];
    for j in k + 1..b.n as i64 {
        if b.seg[j] != last || b.seg[j] == DROP { layers++; }
        last = b.seg[j];
    }
    layers
}

// Whether a flask's key comes free: its layer is the top one, out of the
// smoke, or a siphon's tap has let it out of the bottom.
fn key_loose(b: Bottle) -> bool {
    if b.key_color == KeyColor.None { return false; }
    let k = key_segment(b);
    if k < 0 { return true; }
    !murky(b, k) && layers_over_key(b) == 0
}

// The one color a tall flask takes: what it holds, since it starts with
// some of its color and nothing else ever goes in (see validate). 0 for an
// ordinary flask.
fn tall_color(b: Bottle) -> i64 { if b.cap > CAP && b.n > 0 { b.seg[0] } else { 0 } }

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

// --- the grid and neighbors ---------------------------------------------------------
//
// Flasks stand in a grid of columns and rows. A tall flask takes one column
// over `rows_of(cap)` rows from the top, with segments the size of an
// ordinary flask's, so a row is five segments high: four, and the gap to
// the next row. The other flasks fill the rows in order, the last row's
// from the middle out. The game draws the grid as placed here, so the rules'
// neighbors are the ones on screen.

// The grid as drawn, in a flask's half width: the board area (canvas
// units), a column's width, a segment's height, what an ordinary flask has
// beyond its four segments (rim, bottom, room at the top), how far alternate
// columns are set back, and the largest half width. The layout uses these
// too, so the grid chosen here is the one that fits the screen best.
let GRID_W = 520.0;
let GRID_H = 690.0;
let COLUMN_STEP = 2.45;
let SEGMENT = 0.95;
let FLASK_EXTRA = 1.05;
let STAGGER = 1.6;
let MAX_UNIT = 40.0;

fn rows_of(cap: i64) -> i64 { max(1, (cap + 5) / 5) }

// The half width that fits `rows` rows of `cols` columns in the board area.
fn grid_unit(cols: i64, rows: i64) -> f64 {
    let w = max(1, cols) * COLUMN_STEP;
    let h = (max(1, rows) - 1) * 5.0 * SEGMENT + CAP * SEGMENT + FLASK_EXTRA + (if cols > 1 { STAGGER } else { 0.0 });
    min(min(GRID_W / w, GRID_H / h), MAX_UNIT)
}

// The columns tall flasks stand in, best first: the middle when there is
// one, else the edges.
fn tall_column(cols: i64, k: i64) -> i64 {
    let mid = cols / 2;
    let order: i64[3] = if cols % 2 == 1 { [mid, 0, cols - 1] } else { [0, cols - 1, mid] };
    if k < 3 { order[k] } else { k % cols }
}

// How many flasks from plain[at] on go together: the flasks behind one door
// stand side by side in one row, in order.
fn unit_at(board: Board, plain: const i64[:], at: i64) -> i64 {
    let d: i64 = board.bottles[plain[at]].door;
    if d < 0 { return 1; }
    var g = 1;
    while at + g < plain.len && board.bottles[plain[at + g]].door == d { g++; }
    g
}

// Puts the flasks in `cells` (columns of row r, left to right) in order
// from plain[next], each door's flasks in neighboring columns, skipping a
// cell where they don't fit. When `whole`, all the rest must fit, or
// nothing is placed. The new `next`.
fn fill_row(board: Board&, plain: const i64[:], next: i64, r: i64, cells: const i64[:], whole: bool) -> i64 {
    var at = next;
    var ci = 0;
    var rows: i8[MAX_BOTTLES] = board.row;
    var cols: i8[MAX_BOTTLES] = board.col;
    while at < plain.len && ci < cells.len {
        var g = unit_at(board, plain, at);
        if g > board.cols { g = 1; }        // can never stand together; validate says so
        let fits = ci + g <= cells.len && cells[ci + g - 1] - cells[ci] == g - 1;
        if !fits {
            if whole { return next; }
            ci++;
            continue;
        }
        for k in g {
            rows[plain[at + k]] = r as i8;
            cols[plain[at + k]] = cells[ci + k] as i8;
        }
        at += g;
        ci += g;
    }
    if whole && at < plain.len { return next; }
    board.row = rows;
    board.col = cols;
    at
}

// Puts every flask in a cell of a grid of `cols` columns: tall ones first,
// in their columns from the top row, then the rest row by row, left to
// right in order; the last row's from the middle out when they fit there.
fn pack_grid(board: Board&, cols: i64) {
    board.cols = cols;
    for i in MAX_BOTTLES {
        board.row[i] = -1;
        board.col[i] = -1;
    }
    var talls = 0;
    var plain: i64[..MAX_BOTTLES] = [];
    for i in board.count {
        if rows_of(board.bottles[i].cap) > 1 && talls < cols {
            board.row[i] = 0;
            board.col[i] = tall_column(cols, talls) as i8;
            talls++;
        } else {
            plain.push(i);
        }
    }
    var next = 0;
    var r = 0;
    loop {
        var free: i64[..MAX_BOTTLES] = [];
        for c in cols { if flask_at(board, r, c) < 0 { free.push(c); } }
        let tall_here = free.len < cols;
        if next >= plain.len && !tall_here { break; }
        let left = plain.len - next;
        var placed = next;
        if left > 0 && left < free.len {
            // The last row: the cells nearest the middle, then left to right.
            var take: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
            for k in left {
                var best = -1;
                var best_d = 1e9;
                for c in free {
                    let d = abs(c - (cols - 1) * 0.5);
                    if !take[c] && d < best_d - 0.01 {
                        best = c;
                        best_d = d;
                    }
                }
                take[best] = true;
            }
            var cells: i64[..MAX_BOTTLES] = [];
            for c in cols { if take[c] { cells.push(c); } }
            placed = fill_row(board, plain[..], next, r, cells[..], true);
        }
        if placed == next && left > 0 { placed = fill_row(board, plain[..], next, r, free[..], false); }
        next = placed;
        r++;
    }
    board.rows = max(r, 1);
}

// The rows `cols` columns need for the board's flasks, and the cells left
// empty.
fn grid_rows(board: Board, cols: i64) -> i64, i64 {
    var b = board;
    pack_grid(b, cols);
    var used = 0;
    for i in b.count { used += rows_of(b.bottles[i].cap); }
    return b.rows, b.rows * cols - used;
}

// The most flasks that stand together behind one door.
fn widest_door(board: Board) -> i64 {
    var most = 1;
    for d in board.door_count {
        var n = 0;
        for i in board.count { if board.bottles[i].door == d { n++; } }
        most = max(most, n);
    }
    most
}

// The column count that shows the flasks largest; among near ties, the one
// with the fewest empty cells, then the most columns.
fn grid_columns(board: Board) -> i64 {
    var best = 1;
    var best_unit = 0.0;
    var best_empty = 0;
    var cols = 8;
    let widest = widest_door(board);
    while cols >= 1 {
        var talls = 0;
        for i in board.count { if board.bottles[i].cap > CAP { talls++; } }
        if talls <= cols && cols >= widest {
            let rows, empty = grid_rows(board, cols);
            let u = grid_unit(cols, rows);
            if u > best_unit + 0.5 || (u > best_unit - 0.5 && empty < best_empty) {
                best = cols;
                best_unit = max(u, best_unit);
                best_empty = empty;
            }
        }
        cols--;
    }
    best
}

// Whether flask j stands in cell (row, col).
fn in_cell(board: Board, j: i64, row: i64, col: i64) -> bool {
    let r: i64 = board.row[j];
    board.col[j] == col && row >= r && row < r + rows_of(board.bottles[j].cap)
}

fn flask_at(board: Board, row: i64, col: i64) -> i64 {
    if col < 0 || col >= board.cols { return -1; }
    for j in board.count { if in_cell(board, j, row, col) { return j; } }
    -1
}

// The free cell of `row` nearest the middle (the left one of two), or -1.
fn middle_free(board: Board, row: i64) -> i64 {
    var best = -1;
    var best_d = 1e9;
    for c in board.cols {
        if flask_at(board, row, c) >= 0 { continue; }
        let d = abs(c - (board.cols - 1) * 0.5);
        if d < best_d - 0.01 {
            best = c;
            best_d = d;
        }
    }
    best
}

// Puts every flask in a cell (pack_grid). The columns stay as they are when
// already chosen.
fn place_grid(board: Board&) {
    if board.cols <= 0 { board.cols = grid_columns(board); }
    pack_grid(board, board.cols);
}

// The flasks directly left and right of flask `i` in each row it stands in:
// a tall flask is a neighbor on every row it spans. Left ones first, top
// down, each flask once.
fn neighbors(board: Board, i: i64) -> i64[..6] {
    if board.rows == 0 {
        // Not placed yet: where it would be.
        var placed = board;
        place_grid(placed);
        return neighbors_in(placed, i);
    }
    neighbors_in(board, i)
}

fn neighbors_in(board: Board, i: i64) -> i64[..6] {
    var out: i64[..6] = [];
    if i < 0 || i >= board.count { return out; }
    let r0: i64 = board.row[i];
    let c: i64 = board.col[i];
    for side in [-1, 1] {
        for r in r0..r0 + rows_of(board.bottles[i].cap) {
            let j = flask_at(board, r, c + side);
            if j >= 0 && !contains(out, j) { out.push(j); }
        }
    }
    out
}

fn are_neighbors(board: Board, a: i64, b: i64) -> bool { b >= 0 && contains(neighbors(board, a), b) }

// --- what goes where ---------------------------------------------------------------

// Whether flask `j`, cover aside, would take `color` on what it holds if it
// had room: body rules, the salamander and the top match.
fn fits(board: Board, j: i64, color: i64) -> bool {
    let b = board.bottles[j];
    if b.done || color == 0 || j == board.salamander { return false; }
    if b.body == Body.Moonpetal && !any_lantern_lit(board) { return false; }
    if b.cap > CAP {
        // Only its own color, since nothing comes out again; an athanor's
        // quicksilver lands as gold.
        let lands = if color == QUICKSILVER && b.body == Body.Athanor { GOLD } else { color };
        return lands == tall_color(b);
    }
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
    if b.behind { return false; }
    match b.cover {
        None => takes(board, j, color),
        Seal => !b.done && j != board.salamander && color != 0 && (color == b.key || color == DROP),
        Rime, Shroud, Vine, Curtain => false,
    }
}

fn can_pour(board: Board, from: i64, to: i64) -> bool {
    if from == to || from < 0 || to < 0 || from >= board.count || to >= board.count { return false; }
    let src = board.bottles[from];
    if !can_pour_from(src) { return false; }
    accepts(board, to, pour_color(src))
}

// --- making bottles -------------------------------------------------------------

// The height of a Tall Flask that spans `rows` rows of the grid, with
// segments the size of an ordinary flask's: 9 for two rows, 14 for three
// (four a row, and one for each gap between rows). Everything that makes a
// tall flask asks this for its height.
fn tall_cap(rows: i64) -> i64 { CAP * rows + rows - 1 }

fn bottle(colors: const i64[:]) -> Bottle {
    assert(colors.len <= CAP);
    var b = Bottle { .. };
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
// takes the free cell of the last row nearest the middle, or starts a row;
// the other flasks stay where they are.
fn add_empty_bottle(board: Board&) -> bool {
    if board.count >= MAX_BOTTLES { return false; }
    if board.rows == 0 { place_grid(board); }
    let i = push_bottle(board, Bottle { .. });
    var c = middle_free(board, board.rows - 1);
    if c < 0 {
        board.rows++;
        c = middle_free(board, board.rows - 1);
    }
    board.row[i] = (board.rows - 1) as i8;
    board.col[i] = c as i8;
    true
}

// --- moving liquid ----------------------------------------------------------------

// Segment bits (murk, the key) with bit `at` opened up, the ones above it
// moved up one.
fn bits_open(m: u16, at: i64) -> u16 {
    let x: i64 = m;
    ((x & ((1 << at) - 1)) | ((x >> at) << (at + 1))) as u16
}

// Takes one segment off a flask's pouring end: the top, or a siphon's tap.
// A key going out of the tap leaves the flask (and so comes free).
fn take_one(b: Bottle&) -> i64 {
    let n: i64 = b.n;
    if b.body == Body.Siphon {
        let c: i64 = b.seg[0];
        for k in 1..n { b.seg[k - 1] = b.seg[k]; }
        b.seg[n - 1] = 0;
        b.n--;
        b.murk = b.murk >> 1;
        b.keyed = b.keyed >> 1;
        return c;
    }
    let c: i64 = b.seg[n - 1];
    b.seg[n - 1] = 0;
    b.n--;
    b.murk = ((b.murk as i64) & ((1 << (n - 1)) - 1)) as u16;
    b.keyed = ((b.keyed as i64) & ((1 << (n - 1)) - 1)) as u16;
    c
}

// Puts one segment in: quicksilver sinks below everything but quicksilver,
// carrying the murk and the key of what it slides under up with it; the
// rest lands on top.
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
        b.murk = bits_open(b.murk, at);
        b.keyed = bits_open(b.keyed, at);
    } else {
        b.seg[n] = c as u8;
    }
    b.n++;
}

// Settles quicksilver to the bottom, keeping the order of everything else.
fn sink_quicksilver(b: Bottle&) {
    var seg: u8[MAX_CAP] = [0; MAX_CAP];
    var murk = 0;
    var keyed = 0;
    var at = 0;
    for pass in 2 {
        for k in b.n as i64 {
            if (b.seg[k] == QUICKSILVER) != (pass == 0) { continue; }
            seg[at] = b.seg[k];
            if murky(b, k) { murk |= 1 << at; }
            if (b.keyed as i64 >> k) & 1 != 0 { keyed |= 1 << at; }
            at++;
        }
    }
    b.seg = seg;
    b.murk = murk as u16;
    b.keyed = keyed as u16;
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
    if dst.body == Body.Vow && dst.vow == 0 && c != DROP {
        dst.vow = c as u8;
        note(r, EventKind.Vowed, to, from);
    }
}

// The top segment of every flask is in plain view.
fn clear_top_murk(board: Board&, i: i64, r: PourResult&) {
    var b .= board.bottles[i];
    let n: i64 = b.n;
    let keep = if n == 0 { 0 } else { (b.murk as i64) & ((1 << (n - 1)) - 1) };
    if keep != b.murk {
        b.murk = keep as u16;
        if n > 0 { note(r, EventKind.MurkCleared, i, -1); }
    }
}

// --- the forces --------------------------------------------------------------------

// A heat pulse on flask `i`: ice melts a pour's worth, a seal softens (and
// breaks the second time), a vine tendril burns.
fn heat(board: Board&, i: i64, source: i64, r: PourResult&) {
    if i < 0 || board.bottles[i].behind { return; }
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
        None, Shroud, Curtain => {},
    }
}

// Heat to a flask's neighbors, and to itself when `own` is set.
fn heat_around(board: Board&, i: i64, own: bool, r: PourResult&) {
    if own { heat(board, i, i, r); }
    for j in neighbors(board, i) { heat(board, j, i, r); }
}

// Light from a lantern at `i` reaches it and its neighbors: murk clears and
// shrouds lift. Nothing behind a shut door sees it.
fn shine(board: Board&, i: i64, r: PourResult&) {
    var reach: i64[..7] = [i];
    for j in neighbors(board, i) { reach.push(j); }
    for j in reach {
        var b .= board.bottles[j];
        if b.behind { continue; }
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

// An hourglass turns over: the stack reverses with its murk and its key,
// quicksilver runs back down, and the new top is in view.
fn flip(board: Board&, i: i64, r: PourResult&) {
    var b .= board.bottles[i];
    let n: i64 = b.n;
    var seg = b.seg;
    var murk = 0;
    var keyed = 0;
    for k in n {
        seg[k] = b.seg[n - 1 - k];
        if murky(b, n - 1 - k) { murk |= 1 << k; }
        if (b.keyed as i64 >> (n - 1 - k)) & 1 != 0 { keyed |= 1 << k; }
    }
    b.seg = seg;
    b.murk = murk as u16;
    b.keyed = keyed as u16;
    sink_quicksilver(b);
    note(r, EventKind.Flipped, i, -1);
    clear_top_murk(board, i, r);
}

fn can_flip(b: Bottle) -> bool { b.body == Body.Hourglass && !b.done && !covered(b) && !b.behind }

// A creeping vine grows a tendril over the lowest-numbered flask next to its
// root or a tendril that is not done, not covered and not the root.
fn spread(board: Board&, root: i64, r: PourResult&) {
    for j in board.count {
        let b = board.bottles[j];
        if j == root || b.done || covered(b) || b.behind { continue; }
        var next_to = false;
        for k in neighbors(board, j) {
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
// vines. Behind a shut door nothing counts.
fn tick(board: Board&, r: PourResult&) {
    for i in board.count {
        var b .= board.bottles[i];
        if b.cover != Cover.Rime || b.behind { continue; }
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
        if b.fixture != Fixture.VineRoot || b.spread_every == 0 || b.behind { continue; }
        b.spread_count++;
        if b.spread_count >= b.spread_every {
            b.spread_count = 0;
            spread(board, i, r);
        }
    }
}

// --- completing flasks --------------------------------------------------------------

// Complete for the rules: in a level with an athanor, quicksilver is gold
// still to be made and never completes a flask; and an ordinary flask full of
// a tall flask's color is never done, since the tall flask needs it all.
fn complete_on(board: Board, i: i64) -> bool {
    let b = board.bottles[i];
    if !is_complete(b) { return false; }
    let c = flask_color(b);
    if c == QUICKSILVER && has_body(board, Body.Athanor) { return false; }
    if b.cap > CAP { return true; }
    for j in board.count { if tall_color(board.bottles[j]) == c { return false; } }
    true
}

fn seal_if_complete(board: Board&, i: i64, r: PourResult&) -> bool {
    let b = board.bottles[i];
    if b.done || covered(b) || b.behind || !complete_on(board, i) { return false; }
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

// A completed flask of color `c`, or -1.
fn completed_of(board: Board, c: i64) -> i64 {
    for i in board.count {
        let b = board.bottles[i];
        if b.done && flask_color(b) == c { return i; }
    }
    -1
}

// Curtains whose color has been completed open for good (not behind a shut
// door, where nothing reaches).
fn open_curtains(board: Board&, r: PourResult&) -> bool {
    var changed = false;
    for i in board.count {
        let b = board.bottles[i];
        if b.cover != Cover.Curtain || b.behind { continue; }
        let by = completed_of(board, b.badge);
        if by < 0 { continue; }
        board.bottles[i].cover = Cover.None;
        note(r, EventKind.CurtainOpened, i, by);
        changed = true;
    }
    changed
}

fn door_of(board: Board, color: KeyColor) -> i64 {
    for d in board.door_count { if board.doors[d].color == color { return d; } }
    -1
}

// The first flask behind door d, or -1.
fn first_behind(board: Board, d: i64) -> i64 {
    for i in board.count { if board.bottles[i].door == d { return i; } }
    -1
}

// Door d opens for good, freed by the key in flask `by`: the flasks behind
// it join the board.
fn open_door(board: Board&, d: i64, by: i64, r: PourResult&) {
    board.doors[d].open = true;
    for i in board.count { if board.bottles[i].door == d { board.bottles[i].behind = false; } }
    note_door(r, EventKind.DoorOpened, first_behind(board, d), by, d);
}

// Keys whose layer is on top (or that a tap let out) come free and open
// their doors.
fn free_keys(board: Board&, r: PourResult&) -> bool {
    var changed = false;
    for i in board.count {
        var b .= board.bottles[i];
        if !key_loose(b) { continue; }
        let color = b.key_color;
        b.key_color = KeyColor.None;
        b.keyed = 0;
        let d = door_of(board, color);
        note_door(r, EventKind.KeyFreed, i, -1, d);
        if d >= 0 && !board.doors[d].open { open_door(board, d, i, r); }
        changed = true;
    }
    changed
}

// Seals complete flasks and sets off their lanterns and catalysts, opens
// the curtains of colors completed, frees the keys that are on top and
// opens their doors, until nothing changes: light or heat can uncover a
// flask that is already complete, and a door or a curtain can open on one.
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
        if open_curtains(board, r) { changed = true; }
        if free_keys(board, r) { changed = true; }
        if !changed { break; }
    }
}

// --- pouring --------------------------------------------------------------------

// Pours from bottle `from` into bottle `to`, following every rule, in the
// order of docs/revamp.md: the liquid moves (through a seal, sinking,
// transmuted), murk clears off the tops, the pour is counted (ice,
// hourglasses, vines), a brazier heats and emerald withers the vine, the
// salamander hops, and last the completion round: flasks complete, then
// what that sets off (lanterns, catalysts), curtains of completed colors
// open, and keys on top (or let out of a tap) come free and open their
// doors, until nothing changes. The board is unchanged when the pour is not
// allowed (`ok` false).
fn pour(board: Board&, from: i64, to: i64) -> PourResult {
    var r = PourResult {};
    if !can_pour(board, from, to) { return r; }
    r.ok = true;
    let color = pour_color(board.bottles[from]);
    let run = pour_run(board.bottles[from]);
    r.color = color;

    // The liquid moves: through a seal, sinking, transmuted.
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

// Every flask holding liquid is complete. Liquid still behind a shut door
// or a curtain has yet to be sorted.
fn is_won(board: Board) -> bool {
    for i in board.count {
        let b = board.bottles[i];
        if b.done || b.n == 0 { continue; }
        if b.behind || b.cover == Cover.Curtain || !complete_on(board, i) { return false; }
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

// Brings a built or loaded level into a consistent start: places the flasks
// in the grid, shuts the doors, settles quicksilver, clears murk off the
// tops, and seals what starts complete (lighting lanterns, opening curtains
// of colors already complete, and so on). A level is passed through this
// once.
fn settle(board: Board&) {
    if board.rows == 0 { place_grid(board); }
    var r = PourResult {};
    for i in board.count {
        var b .= board.bottles[i];
        let n: i64 = b.n;
        let d: i64 = b.door;
        b.behind = d >= 0 && d < board.door_count && !board.doors[d].open;
        b.murk = ((b.murk as i64) & ((1 << n) - 1)) as u16;
        b.keyed = ((b.keyed as i64) & ((1 << n) - 1)) as u16;
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
        if b.cap > CAP {
            // Nothing comes out of a tall flask, so it holds only its own
            // color, in plain view, from the start; a tap or a flip would do
            // nothing there.
            if b.n == 0 { return str("bottle ", i + 1, ": a tall flask starts with some of its color"); }
            if !is_uniform(b) || b.seg[0] == DROP || b.murk != 0 {
                return str("bottle ", i + 1, ": a tall flask holds only its own color, and no smoke");
            }
            if b.body == Body.Siphon || b.body == Body.Hourglass {
                return str("bottle ", i + 1, ": a tall flask cannot be a siphon or an hourglass");
            }
        }
        if b.fixture == Fixture.VineRoot {
            roots++;
            if b.spread_every == 0 { return str("bottle ", i + 1, " needs a spread count"); }
        }
        if b.cover == Cover.Vine { vines++; }
        if b.cover == Cover.Shroud {
            var lantern = false;
            for k in neighbors(board, i) { if board.bottles[k].fixture == Fixture.Lantern { lantern = true; } }
            if !lantern { return str("bottle ", i + 1, ": a shroud needs a lantern next to it"); }
        }
        if b.cover == Cover.Curtain {
            let c: i64 = b.badge;
            if c < 1 || c >= DROP { return str("bottle ", i + 1, " needs a color for its curtain"); }
            if has_liquid_of(b, c) { return str("bottle ", i + 1, ": a curtain's color can't be completed while it hides some"); }
        }
        let err = key_error(board, i);
        if err.len > 0 { return err; }
    }
    let doors_err = door_error(board);
    if doors_err.len > 0 { return doors_err; }
    if roots > 1 { return str("a level has at most one creeping vine"); }
    if vines > 0 && roots == 0 { return str("vine tendrils need a root"); }
    if tally[DROP] > 1 { return str("a level has at most one Philosopher's Drop"); }
    if has_body(board, Body.Athanor) {
        // Quicksilver is gold still to be made: the two are one color.
        if tally[QUICKSILVER] == 0 { return str("an athanor needs quicksilver"); }
        tally[GOLD] += tally[QUICKSILVER];
        tally[QUICKSILVER] = 0;
    }
    // A tall flask's color fills it exactly (the Drop never goes in), and
    // every other color fills an ordinary flask; with the Drop, one of them
    // is a segment short.
    var tall: bool[MAX_LIQUID + 1] = [false; MAX_LIQUID + 1];
    for i in board.count {
        let c = tall_color(board.bottles[i]);
        if c == 0 { continue; }
        if tall[c] { return str("two tall flasks of one color"); }
        if tally[c] != board.bottles[i].cap {
            return str("bottle ", i + 1, ": a tall flask needs exactly ", board.bottles[i].cap, " of its color");
        }
        tall[c] = true;
    }
    var colors = 0;
    var drop_used = tally[DROP] == 0;
    for c in 1..DROP {
        if tally[c] == 0 { continue; }
        colors++;
        if tall[c] || tally[c] == CAP { continue; }
        if drop_used || tally[c] + 1 != CAP {
            return str("color ", c, " has ", tally[c], " segments, not ", CAP, " or a tall flask's height");
        }
        drop_used = true;
    }
    if colors == 0 { return str("a level needs some liquid"); }
    for i in board.count {
        let b = board.bottles[i];
        if b.cover == Cover.Curtain && tally[b.badge] == 0 { return str("bottle ", i + 1, ": its curtain's color isn't on the board"); }
    }
    if !drop_used { return str("the Philosopher's Drop stands in for a missing segment, and none is missing"); }
    str("")
}

fn has_liquid_of(b: Bottle, c: i64) -> bool {
    for k in b.n as i64 { if b.seg[k] == c { return true; } }
    false
}

// What is wrong with flask i's key, or with its door, or "".
fn key_error(board: Board, i: i64) -> u8[>..] {
    let b = board.bottles[i];
    let d: i64 = b.door;
    if d < -1 || d >= board.door_count { return str("bottle ", i + 1, " stands behind a door that isn't there"); }
    if d >= 0 && b.cap > CAP { return str("bottle ", i + 1, ": a tall flask can't stand behind a door"); }
    if d >= 0 && i == board.salamander { return str("the salamander can't sit behind a door"); }
    if b.key_color == KeyColor.None {
        if b.keyed != 0 { return str("bottle ", i + 1, " has a key with no metal"); }
        return str("");
    }
    var bits = 0;
    for k in 16 { if (b.keyed as i64 >> k) & 1 != 0 { bits++; } }
    if bits != 1 || key_segment(b) < 0 { return str("bottle ", i + 1, ": a key sits in one of its layers"); }
    if layers_over_key(b) == 0 { return str("bottle ", i + 1, ": its key starts on top, so its door would open at once"); }
    let kd = door_of(board, b.key_color);
    if kd < 0 { return str("bottle ", i + 1, ": its ", key_name(b.key_color), " key has no door"); }
    if kd == d { return str("bottle ", i + 1, ": its key is behind its own door"); }
    str("")
}

// What is wrong with the doors, or "": each of its own metal, shut, with
// one key, and in front of 2 or 3 neighbors side by side in one row; and
// what opens a door or a curtain is never shut away behind it.
fn door_error(board: Board) -> u8[>..] {
    if board.door_count < 0 || board.door_count > MAX_DOORS { return str("a level has at most ", MAX_DOORS, " doors"); }
    var bd = board;
    if bd.rows == 0 { place_grid(bd); }
    for d in board.door_count {
        let door = board.doors[d];
        if door.color == KeyColor.None { return str("door ", d + 1, " needs a metal"); }
        for e in d { if board.doors[e].color == door.color { return str("two doors of ", key_name(door.color)); } }
        if door.open { return str("door ", d + 1, " is open from the start: its key lies on top"); }
        var keys = 0;
        for i in board.count { if board.bottles[i].key_color == door.color { keys++; } }
        if keys != 1 { return str("the ", key_name(door.color), " door needs one key, not ", keys); }
        var first = -1;
        var n = 0;
        for i in board.count {
            if board.bottles[i].door != d { continue; }
            if first < 0 { first = i; }
            if bd.row[i] != bd.row[first] || bd.col[i] != bd.col[first] + n {
                return str("door ", d + 1, ": its flasks stand side by side in one row");
            }
            n++;
        }
        if n < 2 || n > 3 { return str("door ", d + 1, " stands in front of 2 or 3 flasks"); }
    }
    // What a flask waits on before it is in play: its door's key, and every
    // flask holding its curtain's color. Then whatever can be reached.
    var ready: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
    loop {
        var changed = false;
        for i in board.count {
            if ready[i] { continue; }
            let b = board.bottles[i];
            var ok = true;
            if b.door >= 0 {
                for k in board.count {
                    if board.bottles[k].key_color == board.doors[b.door].color && !ready[k] { ok = false; }
                }
            }
            if b.cover == Cover.Curtain {
                for k in board.count {
                    if k != i && has_liquid_of(board.bottles[k], b.badge) && !ready[k] { ok = false; }
                }
            }
            if ok {
                ready[i] = true;
                changed = true;
            }
        }
        if !changed { break; }
    }
    for i in board.count {
        if !ready[i] { return str("bottle ", i + 1, ": what opens its door or curtain waits behind it"); }
    }
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
// Keys, doors and curtains don't: a door and its key are tied to flasks,
// not places, and the flasks behind a door are in its bottles' hash.
fn positional(board: Board) -> bool {
    if board.salamander >= 0 { return true; }
    for i in board.count {
        let b = board.bottles[i];
        if b.fixture != Fixture.None || b.cover == Cover.Vine { return true; }
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
    var open = 0;
    for d in board.door_count { if board.doors[d].open { open |= 1 << d; } }
    h = h + hash(open as u64 * 131 + 5);
    for i in board.count {
        let b = board.bottles[i];
        var x: u64 = 1469598103934665603;
        for k in b.n as i64 { x = (x ^ b.seg[k]) * 1099511628211; }
        let a: u64 = b.n | (b.cap as u64 << 4) | (b.murk as u64 << 8) |
                     (body_index(b.body) as u64 << 24) | (b.vow as u64 << 28) |
                     (b.flip_every as u64 << 34) | (b.flip_count as u64 << 40) |
                     (cover_index(b.cover) as u64 << 46) | (b.key as u64 << 50) | (b.soft as u64 << 56);
        let c: u64 = b.thaw | (fixture_index(b.fixture) as u64 << 8) | (b.spread_every as u64 << 12) |
                     (b.spread_count as u64 << 20) | ((b.door as i64 + 1) as u64 << 28) |
                     (bit(b.lit) << 36) | (bit(b.spent) << 37) | (bit(b.done) << 38) | (bit(b.behind) << 39) |
                     (key_index(b.key_color) as u64 << 40) | (b.badge as u64 << 42) | (b.keyed as u64 << 48);
        x = (x ^ a) * 1099511628211;
        x = (x ^ c) * 1099511628211;
        if place { x = (x ^ (i as u64 << 40)) * 1099511628211; }
        h = h + hash(x);
    }
    h
}
