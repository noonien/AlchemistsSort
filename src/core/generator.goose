// Levels from a seed. A deal is random -- every segment of every color
// shuffled into bottles of chosen fill heights -- then dressed with the
// obstacles asked for, and kept only when the solver wins it. The same
// parameters and seed always give the same board.

import std;
import .board;
import .solver;

struct GenParams {
    colors: i64 = 3,
    empties: i64 = 2,       // spare bottles beyond the colors
    partial: i64 = 0,       // segments moved off full bottles into the spares
    hidden: i64 = 0,        // bottles whose lower layers start as "?"
    split: bool = false,    // one color dealt as two pairs in two bottles
    mystery: i64 = 0,
    cloak: i64 = 0,
    frozen: i64 = 0,
    cork: i64 = 0,
    vault: i64 = 0,         // 2 chains them: one's key lies inside the other
    curtain: i64 = 0,
    gift: i64 = 0,
    long: i64 = 0,          // long flasks, each with one color dealt to fill it
    long_height: i64 = 6,   // their height, CAP + 1 to MAX_CAP
    budget: i64 = 40000,    // solver positions per attempt
}

struct GenResult {
    board: Board,
    stats: SolveStats,
    attempts: i64 = 0,
}

fn obstacle_count(p: GenParams) -> i64 {
    p.mystery + p.cloak + p.frozen + p.cork + p.vault + p.curtain + p.gift
}

// A random index among those with `ok` set, or -1.
fn pick(r: rng&, ok: const bool[:]) -> i64 {
    var n = 0;
    for x in ok { if x { n++; } }
    if n == 0 { return -1; }
    var k = r.rand_int(n);
    for x, i in ok {
        if x {
            if k == 0 { return i; }
            k--;
        }
    }
    -1
}

// Bottles that hold liquid, are plain so far, and are not the given one.
fn candidates(board: Board, taken: const bool[:], out: bool[:]) {
    for i in board.count {
        let b = board.bottles[i];
        out[i] = i < taken.len && !taken[i] && b.n > 0 && b.kind == Kind.Plain;
    }
}

fn has_color(b: Bottle, c: i64) -> bool {
    for k in b.n as i64 { if b.seg[k] == c { return true; } }
    false
}

// Arranges for color `x` to sit as the top pair of bottle `a` and the bottom
// pair of bottle `b`, by swapping segments.
fn split_color(board: Board&, x: i64, a: i64, b: i64) {
    let targets: i64[2][4] = [[a, 2], [a, 3], [b, 0], [b, 1]];
    for t in targets {
        if board.bottles[t[0]].seg[t[1]] == x { continue; }
        // Find an `x` that is not already on a target, and swap it in.
        var found = false;
        for i in board.count {
            if found { break; }
            for k in board.bottles[i].n as i64 {
                if board.bottles[i].seg[k] != x { continue; }
                var on_target = false;
                for u in targets { if u[0] == i && u[1] == k { on_target = true; } }
                if on_target { continue; }
                let other = board.bottles[t[0]].seg[t[1]];
                board.bottles[t[0]].seg[t[1]] = x as u8;
                board.bottles[i].seg[k] = other;
                found = true;
                break;
            }
        }
    }
}

// One random deal with obstacles, before any check that it can be won.
fn deal(p: GenParams, r: rng&) -> Board {
    var board = Board { .. };
    let colors = clamp(p.colors, 1, MAX_COLORS);
    board.colors = colors;
    let longs = clamp(p.long, 0, colors);
    let bottles = min(colors + p.empties, MAX_BOTTLES - p.mystery - longs);
    // Fill heights: full bottles, then the spares; `partial` segments move
    // from the top of full bottles to the spares, one at a time.
    var heights: i64[MAX_BOTTLES] = [0; MAX_BOTTLES];
    for i in colors { heights[i] = CAP; }
    // Corks, padlocks and gift boxes want a bottle with room under them. A
    // curtain wants every spare to start with something in it (see below).
    var partial = max(p.partial, p.cork + p.vault + p.gift);
    if p.curtain > 0 { partial = max(partial, p.empties * 2); }
    for k in partial {
        var from_ok: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
        var to_ok: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
        var lowest = CAP;
        for i in colors..bottles { lowest = min(lowest, heights[i]); }
        for i in bottles {
            from_ok[i] = heights[i] > 2 && i < colors;
            to_ok[i] = i >= colors && heights[i] < CAP - 1 && (p.curtain == 0 || heights[i] == lowest);
        }
        let f = pick(r, from_ok[..bottles]);
        let t = pick(r, to_ok[..bottles]);
        if f < 0 || t < 0 { break; }
        heights[f]--;
        heights[t]++;
    }
    var segs: u8[>..] = [];
    for c in 1..colors + 1 { for k in CAP { segs.push(c as u8); } }
    shuffle(segs, r);
    var at = 0;
    for i in bottles {
        var b = Bottle { seg: [0; 8], .. };
        for k in heights[i] {
            b.seg[k] = segs[at];
            at++;
        }
        b.n = heights[i] as u8;
        push_bottle(board, b);
    }
    // A long flask comes with the extra share of its color already in it;
    // the color's other CAP segments are in the deal like any other's.
    let tall = clamp(p.long_height, CAP + 1, MAX_CAP);
    var long_color: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
    for k in longs {
        var free: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
        for c in 1..colors + 1 { free[c] = !long_color[c]; }
        let c = pick(r, free[..colors + 1]);
        if c < 0 { break; }
        long_color[c] = true;
        var b = Bottle { seg: [0; 8], cap: tall as u8, .. };
        for s in tall - CAP { b.seg[s] = c as u8; }
        b.n = (tall - CAP) as u8;
        push_bottle(board, b);
    }

    var taken: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
    var ok: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
    if p.split && colors >= 2 {
        for i in board.count { ok[i] = board.bottles[i].n == CAP && board.bottles[i].cap == CAP; }
        let a = pick(r, ok[..board.count]);
        if a >= 0 {
            ok[a] = false;
            let b = pick(r, ok[..board.count]);
            if b >= 0 {
                split_color(board, 1 + r.rand_int(colors), a, b);
                taken[a] = true;
                taken[b] = true;
            }
        }
    }
    // Obstacles, each on its own bottle with liquid in it.
    for k in p.frozen {
        candidates(board, taken[..board.count], ok);
        let i = pick(r, ok[..board.count]);
        if i < 0 { break; }
        var b .= board.bottles[i];
        b.kind = Kind.Frozen;
        b.active = true;
        b.timer = (3 + r.rand_int(5)) as u8;
        taken[i] = true;
    }
    for k in p.cloak {
        candidates(board, taken[..board.count], ok);
        let i = pick(r, ok[..board.count]);
        if i < 0 { break; }
        // The key is a color this bottle does not hold.
        var keys: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
        for c in 1..colors + 1 { keys[c] = !has_color(board.bottles[i], c); }
        let key = pick(r, keys[..colors + 1]);
        if key < 0 { continue; }
        var b .= board.bottles[i];
        b.kind = Kind.Cloak;
        b.key = key as u8;
        b.active = true;
        taken[i] = true;
    }
    var vault_inside = -1;      // a color inside the first vault, the second one's key
    let locks = p.cork + p.vault;
    for k in locks {
        candidates(board, taken[..board.count], ok);
        // Prefer a bottle with room, so the key color lands inside.
        var roomy: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
        var any_roomy = false;
        for i in board.count {
            roomy[i] = ok[i] && board.bottles[i].n < board.bottles[i].cap;
            if roomy[i] { any_roomy = true; }
        }
        let i = if any_roomy { pick(r, roomy[..board.count]) } else { pick(r, ok[..board.count]) };
        if i < 0 { break; }
        let is_vault = k >= p.cork;
        var b .= board.bottles[i];
        var key = if b.n < b.cap { top(b) } else { 1 + r.rand_int(colors) };
        if is_vault && vault_inside > 0 { key = vault_inside; }
        b.kind = if is_vault { Kind.Vault } else { Kind.Cork };
        b.key = key as u8;
        b.active = true;
        if is_vault && vault_inside < 0 && p.vault >= 2 {
            // The next vault's key is a color locked in here.
            for s in b.n as i64 { if b.seg[s] != key { vault_inside = b.seg[s]; } }
        }
        taken[i] = true;
    }
    for k in p.gift {
        candidates(board, taken[..board.count], ok);
        for i in board.count { if board.bottles[i].n >= board.bottles[i].cap { ok[i] = false; } }
        let i = pick(r, ok[..board.count]);
        if i < 0 { break; }
        var b .= board.bottles[i];
        b.kind = Kind.Gift;
        b.active = true;
        taken[i] = true;
    }
    for k in p.curtain {
        candidates(board, taken[..board.count], ok);
        let i = pick(r, ok[..board.count]);
        if i < 0 { break; }
        var b .= board.bottles[i];
        b.kind = Kind.Curtain;
        b.active = true;
        taken[i] = true;
    }
    // A full flask behind a curtain hides a segment of most colors, so the
    // flasks in view can hold at most `empties - 1` empty at once: that is
    // what the curtain asks for. (deal_ok rejects deals that start with it.)
    for i in board.count {
        var b .= board.bottles[i];
        if b.kind == Kind.Curtain { b.key = max(1, p.empties - 1) as u8; }
    }
    for k in p.hidden {
        for i in board.count {
            let b = board.bottles[i];
            ok[i] = !taken[i] && b.n > 1 && b.kind == Kind.Plain && b.hidden == 0;
        }
        let i = pick(r, ok[..board.count]);
        if i < 0 { break; }
        var b .= board.bottles[i];
        b.hidden = b.n - 1;
    }
    for k in p.mystery {
        var b = Bottle { seg: [0; 8], .. };
        b.kind = Kind.Mystery;
        b.active = true;
        push_bottle(board, b);
    }
    settle(board);
    board
}

// No bottle may start complete, and the level should not be half done.
fn deal_ok(board: Board) -> bool {
    for i in board.count {
        let b = board.bottles[i];
        if b.done || (b.n == b.cap && is_uniform(b)) { return false; }
        if b.kind == Kind.Curtain && !b.active { return false; }   // opened before the first pour
    }
    validate(board).len == 0 && !is_won(board)
}

fn generate(p: GenParams, seed: u64) -> GenResult {
    var path: Move[>..] = [];
    var plain = p;
    for attempt in 400 {
        // After many failures, ease off: fewer obstacles, then fewer colors.
        if attempt == 200 {
            plain.hidden = 0;
            plain.cloak = 0;
            plain.frozen = 0;
            plain.curtain = 0;
        }
        if attempt == 300 {
            plain = GenParams { colors: max(3, p.colors - 1), empties: 2, long: p.long, long_height: p.long_height };
        }
        var r = rng { seed * 0x9E3779B97F4A7C15 + (attempt as u64) * 0xD1B54A32D192ED03 + 17 };
        let board = deal(plain, r);
        if !deal_ok(board) { continue; }
        let stats = solve(board, p.budget, path);
        if stats.solved { return GenResult { board: board, stats: stats, attempts: attempt + 1 }; }
    }
    // Practically unreachable: three colors with two spares always solve.
    var r = rng { seed };
    let board = deal(GenParams { colors: 3, empties: 2 }, r);
    GenResult { board: board, stats: SolveStats {}, attempts: 401 }
}
