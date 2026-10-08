// The puzzle's rules: bottles, pours and obstacles. Nothing here knows
// about drawing, input or files; the game, the solver, the generator and the
// tests all run the same code.
//
// A bottle holds up to `cap` segments, bottom first: CAP, or more for a long
// flask. Colors are 1..MAX_COLORS; 0 is "no liquid". An obstacle is a bottle
// `kind` plus an `active` flag: while active it changes what the bottle
// accepts and shows, and once removed (thawed, popped, unwrapped...) the
// bottle is an ordinary one.

import std;

let CAP = 4;            // an ordinary flask, and how much there is of most colors
let MAX_CAP = 8;        // the tallest long flask
let MAX_BOTTLES = 24;
let MAX_COLORS = 14;

// What stands on or around a bottle. Any kind but Plain and Mystery is an
// obstacle while the bottle is `active`, and an ordinary bottle after.
enum Kind {
    Plain,
    Mystery,    // accepts only the first color poured in; must end full
    Cloak,      // hidden and inert until a bottle of color `key` is completed
    Frozen,     // inert until `timer` more pours have been made anywhere
    Cork,       // accepts only color `key`, which pops it; contents hidden
    Vault,      // the same rule as Cork, drawn as a padlock
    Curtain,    // not on the board until at least `key` bottles are empty
    Gift,       // pops on any pour, which lands on whatever is underneath
}

let ALL_KINDS: const Kind[8] = [Kind.Plain, Kind.Mystery, Kind.Cloak, Kind.Frozen, Kind.Cork,
                                Kind.Vault, Kind.Curtain, Kind.Gift];

fn kind_index(k: Kind) -> i64 {
    match k {
        Plain => 0, Mystery => 1, Cloak => 2, Frozen => 3, Cork => 4, Vault => 5, Curtain => 6,
        Gift => 7,
    }
}

struct Bottle {
    seg: u8[8],         // bottom to top; only the first `n` mean anything
    n: u8 = 0,
    cap: u8 = 4,        // segments it holds: CAP, or more for a long flask
    hidden: u8 = 0,     // the lowest `hidden` segments show as "?"
    kind: Kind = Kind.Plain,
    key: u8 = 0,        // see the kinds above
    timer: u8 = 0,      // Kind.Frozen: pours left before it thaws
    active: bool = false,
    done: bool = false, // completed and sealed
}

struct Board {
    bottles: Bottle[MAX_BOTTLES],
    count: i64 = 0,     // bottles in use
    colors: i64 = 0,    // distinct colors in the level
    pours: i64 = 0,     // successful pours so far
}

// What a pour did, for the game to animate and the tests to check.
struct PourResult {
    ok: bool = false,
    color: i64 = 0,
    amount: i64 = 0,        // segments that moved (0 when only a cork or box popped)
    popped: bool = false,   // the destination's cork, padlock or gift box came off
    completed: bool = false,// the destination is now complete
    thawed: i64 = 0,        // bottles whose ice melted
    revealed: i64 = 0,      // cloaks lifted
    opened: i64 = 0,        // curtains opened
}

// --- reading a bottle ----------------------------------------------------------

fn size(b: Bottle) -> i64 { b.n }

fn top(b: Bottle) -> i64 {
    if b.n == 0 { return 0; }
    b.seg[b.n - 1]
}

// The contiguous run of the top color, counting visible segments only.
fn top_run(b: Bottle) -> i64 {
    let n: i64 = b.n;
    if n == 0 { return 0; }
    let c = b.seg[n - 1];
    var i = n - 1;
    var run = 0;
    while i >= 0 && i >= b.hidden && b.seg[i] == c {
        run++;
        i--;
    }
    run
}

fn is_complete(b: Bottle) -> bool {
    if b.n != b.cap || b.seg[0] == 0 { return false; }
    is_uniform(b)
}

// Every segment one color (or none at all).
fn is_uniform(b: Bottle) -> bool {
    for i in 1..b.n as i64 { if b.seg[i] != b.seg[0] { return false; } }
    true
}

fn is_blocker(kind: Kind) -> bool {
    match kind {
        Plain, Mystery => false,
        Cloak, Frozen, Cork, Vault, Curtain, Gift => true,
    }
}

// An obstacle that is still in effect.
fn blocked(b: Bottle) -> bool { b.active && is_blocker(b.kind) }

// Hidden from view entirely: under a cloth, curtain, cork, padlock or box.
fn contents_hidden(b: Bottle) -> bool {
    if !b.active { return false; }
    match b.kind {
        Plain, Mystery, Frozen => false,
        Cloak, Curtain, Cork, Vault, Gift => true,
    }
}

// On the board: a closed curtain has no bottle in front of it yet.
fn on_board(b: Bottle) -> bool { !(b.kind == Kind.Curtain && b.active) }

fn can_pour_from(b: Bottle) -> bool { b.n > 0 && !b.done && !blocked(b) }

// Whether a pour of `color` is accepted (it may still move nothing, when it
// only pops a cork or a box over a bottle with no room).
fn accepts(b: Bottle, color: i64) -> bool {
    if b.done || color == 0 { return false; }
    if b.active {
        match b.kind {
            Cork, Vault => { return color == b.key; },
            Gift => { return true; },
            Cloak, Frozen, Curtain => { return false; },
            Plain, Mystery => {},
        }
    }
    if b.n >= b.cap { return false; }
    if b.kind == Kind.Mystery && b.key != 0 && b.key != color { return false; }
    b.n == 0 || top(b) == color
}

fn can_pour(board: Board, from: i64, to: i64) -> bool {
    if from == to || from < 0 || to < 0 || from >= board.count || to >= board.count { return false; }
    let src = board.bottles[from];
    if !can_pour_from(src) { return false; }
    accepts(board.bottles[to], top(src))
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

// Adds an empty bottle, as the extra-bottle tool does. False when full up.
fn add_empty_bottle(board: Board&) -> bool {
    if board.count >= MAX_BOTTLES { return false; }
    push_bottle(board, Bottle { seg: [0; 8], .. });
    true
}

// --- pouring --------------------------------------------------------------------

fn empty_on_board(board: Board) -> i64 {
    var e = 0;
    for i in board.count {
        let b = board.bottles[i];
        if b.n == 0 && on_board(b) && !b.done { e++; }
    }
    e
}

// Lifts the cloaks waiting on `color`.
fn reveal_cloaks(board: Board&, color: i64) -> i64 {
    var lifted = 0;
    for i in board.count {
        var b .= board.bottles[i];
        if b.kind == Kind.Cloak && b.active && b.key == color {
            b.active = false;
            lifted++;
        }
    }
    lifted
}

// Seals a bottle that has become complete, and lifts the cloaks of its color.
fn seal_if_complete(board: Board&, i: i64) -> bool, i64 {
    var b .= board.bottles[i];
    if b.done || blocked(b) || !is_complete(b) { return false, 0; }
    b.done = true;
    b.hidden = 0;
    let c: i64 = b.seg[0];
    return true, reveal_cloaks(board, c);
}

// Opens every curtain whose condition holds; opening one can satisfy another.
fn open_curtains(board: Board&) -> i64 {
    var opened = 0;
    loop {
        let empties = empty_on_board(board);
        var any = false;
        for i in board.count {
            var b .= board.bottles[i];
            if b.kind == Kind.Curtain && b.active && empties >= b.key {
                b.active = false;
                opened++;
                any = true;
            }
        }
        if !any { break; }
    }
    opened
}

// Pours from bottle `from` into bottle `to`, following every rule. The board
// is unchanged when the pour is not allowed (`ok` false).
fn pour(board: Board&, from: i64, to: i64) -> PourResult {
    var r = PourResult {};
    if !can_pour(board, from, to) { return r; }
    r.ok = true;
    var src .= board.bottles[from];
    var dst .= board.bottles[to];
    let color = top(src);
    let run = top_run(src);
    r.color = color;

    var lands = true;
    if dst.active && (dst.kind == Kind.Cork || dst.kind == Kind.Vault) {
        dst.active = false;
        r.popped = true;
        lands = dst.n == 0 || top(dst) == color;
    } else if dst.active && dst.kind == Kind.Gift {
        dst.active = false;
        r.popped = true;      // the box takes any color, whatever lies under it
    }
    let room: i64 = dst.cap - dst.n;
    let amount = if lands { min(run, room) } else { 0 };
    for k in amount {
        dst.seg[dst.n] = color as u8;
        dst.n++;
        src.n--;
        src.seg[src.n] = 0;
    }
    r.amount = amount;
    // The new top of the source is visible now.
    if src.n == 0 { src.hidden = 0; }
    else if src.hidden >= src.n { src.hidden = src.n - 1; }
    if dst.kind == Kind.Mystery && dst.key == 0 && amount > 0 { dst.key = color as u8; }

    board.pours++;
    for i in board.count {
        var b .= board.bottles[i];
        if b.kind == Kind.Frozen && b.active {
            if b.timer > 0 { b.timer--; }
            if b.timer == 0 {
                b.active = false;
                r.thawed++;
            }
        }
    }
    let done, lifted = seal_if_complete(board, to);
    r.completed = done;
    r.revealed += lifted;
    // A thaw or a lifted cloak can uncover a bottle that was already complete.
    for i in board.count {
        let d2, l2 = seal_if_complete(board, i);
        r.revealed += l2;
    }
    r.opened = open_curtains(board);
    if r.opened > 0 {
        for i in board.count {
            let d3, l3 = seal_if_complete(board, i);
            r.revealed += l3;
        }
    }
    r
}

// --- the end of a level ---------------------------------------------------------

fn is_won(board: Board) -> bool {
    for i in board.count {
        let b = board.bottles[i];
        if b.kind == Kind.Curtain && b.active && b.n == 0 { continue; }
        if b.kind == Kind.Mystery {
            if !is_complete(b) { return false; }
            continue;
        }
        if b.n == 0 { continue; }
        if !is_complete(b) { return false; }
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

// Seals bottles that start complete and opens curtains that start satisfied;
// a level is passed through this once after it is built or loaded.
fn settle(board: Board&) {
    for i in board.count {
        var b .= board.bottles[i];
        if b.hidden >= b.n { b.hidden = if b.n > 0 { b.n - 1 } else { 0 }; }
        if b.kind == Kind.Mystery { b.active = true; }
        if b.kind == Kind.Frozen && b.timer == 0 { b.active = false; }
    }
    for i in board.count { let d, l = seal_if_complete(board, i); }
    if open_curtains(board) > 0 {
        for i in board.count { let d, l = seal_if_complete(board, i); }
    }
}

// --- structural checks, for loaded and generated levels ---------------------

// Empty when the board is well formed, else what is wrong with it.
fn validate(board: Board) -> u8[>..] {
    var tally: i64[MAX_COLORS + 1] = [0; MAX_COLORS + 1];
    if board.count < 2 { return str("a level needs at least two bottles"); }
    for i in board.count {
        let b = board.bottles[i];
        if b.cap < CAP || b.cap > MAX_CAP { return str("bottle ", i + 1, " is not ", CAP, " to ", MAX_CAP, " tall"); }
        if b.n > b.cap { return str("bottle ", i + 1, " holds more than ", b.cap); }
        for k in b.n as i64 {
            let c: i64 = b.seg[k];
            if c < 1 || c > MAX_COLORS { return str("bottle ", i + 1, " has an unknown color"); }
            tally[c]++;
        }
        if (b.kind == Kind.Cork || b.kind == Kind.Vault || b.kind == Kind.Cloak) && (b.key < 1 || b.key > MAX_COLORS) {
            return str("bottle ", i + 1, " needs a key color");
        }
    }
    var colors = 0;
    var long_used: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
    for c in 1..MAX_COLORS + 1 {
        if tally[c] == 0 { continue; }
        colors++;
        if tally[c] == CAP { continue; }
        // A color with more is there to fill a long flask of its own.
        var fits = false;
        for i in board.count {
            if !long_used[i] && board.bottles[i].cap == tally[c] {
                long_used[i] = true;
                fits = true;
                break;
            }
        }
        if !fits { return str("color ", c, " has ", tally[c], " segments, not ", CAP, " or a long flask's height"); }
    }
    if colors == 0 { return str("a level needs some liquid"); }
    str("")
}

// The distinct colors on the board.
fn color_count(board: Board) -> i64 {
    var seen: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
    var colors = 0;
    for i in board.count {
        let b = board.bottles[i];
        for k in b.n as i64 {
            let c: i64 = b.seg[k];
            if !seen[c] { seen[c] = true; colors++; }
        }
    }
    colors
}

// A 64-bit fingerprint of a position for the solver's visited set. Bottles
// that differ only in where they stand hash alike, since swapping two of
// them changes nothing about what can be done.
fn board_hash(board: Board) -> u64 {
    var h: u64 = 0;
    for i in board.count {
        let b = board.bottles[i];
        var x: u64 = 1469598103934665603;
        for k in b.n as i64 { x = (x ^ b.seg[k]) * 1099511628211; }
        x = (x ^ (b.n as u64 << 8) ^ (b.cap as u64 << 40)) * 1099511628211;
        x = (x ^ (b.hidden as u64 << 12)) * 1099511628211;
        x = (x ^ (kind_index(b.kind) as u64 << 16)) * 1099511628211;
        x = (x ^ (b.key as u64 << 20)) * 1099511628211;
        x = (x ^ (b.timer as u64 << 28)) * 1099511628211;
        if b.active { x = (x ^ 0x5bd1e995) * 1099511628211; }
        h = h + hash(x);
    }
    h
}
