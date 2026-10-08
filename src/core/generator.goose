// Levels from a seed. A deal is random -- every segment of every color
// shuffled into bottles of chosen fill heights -- then dressed with the
// modifiers asked for, placed where they matter, and kept only when the
// solver wins it. The same parameters and seed always give the same board.

import std;
import .board;
import .solver;

struct GenParams {
    colors: i64 = 3,
    empties: i64 = 2,       // spare bottles beyond the colors
    partial: i64 = 0,       // segments moved off full bottles into the spares
    murk: i64 = 0,          // bottles whose lower layers start under smoke
    split: bool = false,    // one color dealt as two pairs in two bottles
    vow: i64 = 0,           // empty vow flasks
    seal: i64 = 0,
    rime: i64 = 0,
    tall: i64 = 0,          // tall flasks, each with one color dealt to fill it
    tall_height: i64 = 6,   // their height, CAP + 1 to MAX_CAP
    brazier: i64 = 0,       // next to something heat changes, where there is one
    quicksilver: bool = false,  // one color is quicksilver
    siphon: i64 = 0,
    twins: i64 = 0,         // pairs of neighbors joined by a tube
    lantern: i64 = 0,       // besides those shrouds and moonpetals bring
    shroud: i64 = 0,        // each next to a lantern
    hourglass: i64 = 0,
    flip_every: i64 = 3,
    vine: bool = false,     // a creeping vine (and emerald among the colors, to wither it)
    vine_every: i64 = 4,
    salamander: bool = false,
    moonpetal: i64 = 0,     // on flasks with liquid; brings a lantern
    athanor: bool = false,  // an empty athanor, and one color is gold partly dealt as quicksilver
    athanor_quicksilver: i64 = 2,   // how much of the gold starts as quicksilver
    drop: bool = false,     // one segment is the Philosopher's Drop
    catalyst: i64 = 0,      // only where there is a brazier, hourglass or lantern to set off
    budget: i64 = 40000,    // solver positions per attempt
}

struct GenResult {
    board: Board,
    stats: SolveStats,
    attempts: i64 = 0,
}

fn modifier_count(p: GenParams) -> i64 {
    var n = p.vow + p.seal + p.rime + p.brazier + p.siphon + p.twins + p.lantern + p.shroud + p.hourglass +
            p.moonpetal + p.catalyst;
    for on in [p.quicksilver, p.vine, p.salamander, p.athanor, p.drop] { if on { n++; } }
    n
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

// Whether a neighbor of `i` is marked in `near`.
fn next_to(board: Board, i: i64, near: const bool[:]) -> bool {
    let l, r = neighbors(board, i);
    (l >= 0 && near[l]) || (r >= 0 && near[r])
}

// Puts a fixture on a random flask with `ok` set and no fixture yet.
fn place_fixture(board: Board&, r: rng&, ok: bool[:], f: Fixture) -> i64 {
    for i in board.count { if board.bottles[i].fixture != Fixture.None { ok[i] = false; } }
    let i = pick(r, ok[..board.count]);
    if i >= 0 { board.bottles[i].fixture = f; }
    i
}

// One random deal with modifiers, before any check that it can be won.
fn deal(p: GenParams, r: rng&) -> Board {
    var board = Board { .. };
    let colors = clamp(p.colors, 1, MAX_COLORS);
    board.colors = colors;
    let talls = clamp(p.tall, 0, colors);
    let extra = p.vow + (if p.athanor { 1 } else { 0 });
    let bottles = min(colors + p.empties, MAX_BOTTLES - extra - talls);
    // What each dealt color is poured as: a dye, or quicksilver, or the
    // athanor's gold. A vine wants emerald on the board to wither it.
    var liquid: i64[MAX_COLORS + 1] = [0; MAX_COLORS + 1];
    for c in 1..colors + 1 { liquid[c] = c; }
    var gold_color = -1;
    if p.vine && colors < EMERALD { liquid[colors] = EMERALD; }
    if p.athanor { gold_color = 1 + r.rand_int(colors); liquid[gold_color] = GOLD; }
    else if p.quicksilver { liquid[1 + r.rand_int(colors)] = QUICKSILVER; }
    var special: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
    for c in 1..colors + 1 { special[c] = liquid[c] == GOLD || liquid[c] == QUICKSILVER; }

    // Fill heights: full bottles, then the spares; `partial` segments move
    // from the top of full bottles to the spares, one at a time. Seals want
    // a bottle with room under them.
    var heights: i64[MAX_BOTTLES] = [0; MAX_BOTTLES];
    for i in colors { heights[i] = CAP; }
    let partial = max(p.partial, p.seal);
    for k in partial {
        var from_ok: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
        var to_ok: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
        for i in bottles {
            from_ok[i] = heights[i] > 2 && i < colors;
            to_ok[i] = i >= colors && heights[i] < CAP - 1;
        }
        let f = pick(r, from_ok[..bottles]);
        let t = pick(r, to_ok[..bottles]);
        if f < 0 || t < 0 { break; }
        heights[f]--;
        heights[t]++;
    }
    // A tall flask comes with the extra share of its color already in it;
    // the color's other CAP segments are in the deal like any other's.
    let tall = clamp(p.tall_height, CAP + 1, MAX_CAP);
    var tall_color: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
    for k in talls {
        var free: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
        for c in 1..colors + 1 { free[c] = !tall_color[c] && !special[c]; }
        let c = pick(r, free[..colors + 1]);
        if c < 0 { break; }
        tall_color[c] = true;
    }
    // The Drop stands in for one segment of an ordinary color.
    var drop_color = -1;
    if p.drop {
        var ok: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
        for c in 1..colors + 1 { ok[c] = !special[c]; }
        drop_color = pick(r, ok[..colors + 1]);
    }
    var segs: u8[>..] = [];
    for c in 1..colors + 1 {
        for k in CAP {
            var s = liquid[c];
            if c == gold_color && k < clamp(p.athanor_quicksilver, 1, CAP) { s = QUICKSILVER; }
            if c == drop_color && k == 0 { s = DROP; }
            segs.push(s as u8);
        }
    }
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
    for c in 1..colors + 1 {
        if !tall_color[c] { continue; }
        var b = Bottle { seg: [0; 8], cap: tall as u8, .. };
        for s in tall - CAP { b.seg[s] = liquid[c] as u8; }
        b.n = (tall - CAP) as u8;
        push_bottle(board, b);
    }
    for k in p.vow {
        var b = Bottle { seg: [0; 8], .. };
        b.body = Body.Vow;
        push_bottle(board, b);
    }
    if p.athanor {
        var b = Bottle { seg: [0; 8], .. };
        b.body = Body.Athanor;
        push_bottle(board, b);
    }
    // Every bottle is on the shelf now, so neighbors are known.
    board.per_row = shelf_per_row(board.count, tallest_cap(board));
    let count = board.count;

    var ok: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
    var near: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
    if p.split && colors >= 2 {
        for i in count { ok[i] = board.bottles[i].n == CAP && board.bottles[i].cap == CAP; }
        let a = pick(r, ok[..count]);
        if a >= 0 {
            ok[a] = false;
            let b = pick(r, ok[..count]);
            var plain: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
            for c in 1..colors + 1 { plain[c] = !special[c]; }
            let c = pick(r, plain[..colors + 1]);
            if b >= 0 && c > 0 { split_color(board, liquid[c], a, b); }
        }
    }
    // Bodies, on flasks with liquid.
    fn plain_with_liquid() {
        for i in count {
            let b = board.bottles[i];
            ok[i] = b.n > 0 && b.body == Body.Plain;
        }
    }
    for k in p.siphon {
        plain_with_liquid();
        let i = pick(r, ok[..count]);
        if i < 0 { break; }
        board.bottles[i].body = Body.Siphon;
    }
    for k in p.hourglass {
        plain_with_liquid();
        let i = pick(r, ok[..count]);
        if i < 0 { break; }
        board.bottles[i].body = Body.Hourglass;
        board.bottles[i].flip_every = clamp(p.flip_every, 1, 9) as u8;
    }
    for k in p.moonpetal {
        plain_with_liquid();
        let i = pick(r, ok[..count]);
        if i < 0 { break; }
        board.bottles[i].body = Body.Moonpetal;
    }
    // Murk, the background of most levels; never on a siphon.
    for k in p.murk {
        for i in count {
            let b = board.bottles[i];
            ok[i] = b.n > 1 && b.body != Body.Siphon && b.murk == 0;
        }
        let i = pick(r, ok[..count]);
        if i < 0 { break; }
        let n: i64 = board.bottles[i].n;
        board.bottles[i].murk = ((1 << (n - 1)) - 1) as u8;
    }
    // Twins: neighbors, at least one with room for an overflow to matter.
    for k in p.twins {
        for i in count {
            let a = board.bottles[i];
            let l, right = neighbors(board, i);
            ok[i] = right >= 0 && a.twin < 0 && board.bottles[right].twin < 0 &&
                    (a.n < a.cap || board.bottles[right].n < board.bottles[right].cap);
        }
        let i = pick(r, ok[..count]);
        if i < 0 { break; }
        board.bottles[i].twin = (i + 1) as i8;
        board.bottles[i + 1].twin = i as i8;
    }
    // Shrouds, each next to a lantern on a flask with liquid to complete.
    for k in p.shroud {
        for i in count { near[i] = board.bottles[i].fixture == Fixture.Lantern ||
                                   (board.bottles[i].fixture == Fixture.None && board.bottles[i].n > 0 &&
                                    !covered(board.bottles[i])); }
        for i in count { ok[i] = board.bottles[i].n > 0 && !covered(board.bottles[i]) && next_to(board, i, near); }
        let i = pick(r, ok[..count]);
        if i < 0 { break; }
        board.bottles[i].cover = Cover.Shroud;
        let l, right = neighbors(board, i);
        if (l >= 0 && board.bottles[l].fixture == Fixture.Lantern) ||
           (right >= 0 && board.bottles[right].fixture == Fixture.Lantern) { continue; }
        for j in count { ok[j] = (j == l || j == right) && near[j] && !covered(board.bottles[j]); }
        place_fixture(board, r, ok, Fixture.Lantern);
    }
    // Other lanterns, preferably where their light clears murk.
    let lanterns = max(p.lantern, if p.moonpetal > 0 { 1 } else { 0 });
    var have = 0;
    for i in count { if board.bottles[i].fixture == Fixture.Lantern { have++; } }
    for k in max(0, lanterns - have) {
        for i in count { near[i] = board.bottles[i].murk != 0; }
        var any = false;
        for i in count {
            ok[i] = board.bottles[i].n > 0 && board.bottles[i].fixture == Fixture.None && next_to(board, i, near);
            if ok[i] { any = true; }
        }
        if !any { for i in count { ok[i] = board.bottles[i].n > 0; } }
        if place_fixture(board, r, ok, Fixture.Lantern) < 0 { break; }
    }
    for k in p.rime {
        for i in count { ok[i] = board.bottles[i].n > 0 && !covered(board.bottles[i]); }
        let i = pick(r, ok[..count]);
        if i < 0 { break; }
        board.bottles[i].cover = Cover.Rime;
        board.bottles[i].thaw = (3 + r.rand_int(5)) as u8;
    }
    for k in p.seal {
        // Prefer a bottle with room, so the key color lands inside.
        var any_roomy = false;
        for i in count {
            let b = board.bottles[i];
            ok[i] = b.n > 0 && !covered(b) && b.n < b.cap && top(b) != DROP;
            if ok[i] { any_roomy = true; }
        }
        if !any_roomy { for i in count { ok[i] = board.bottles[i].n > 0 && !covered(board.bottles[i]); } }
        let i = pick(r, ok[..count]);
        if i < 0 { break; }
        var b .= board.bottles[i];
        var key = top(b);
        if b.n >= b.cap || key == DROP { key = liquid[1 + r.rand_int(colors)]; }
        b.cover = Cover.Seal;
        b.key = key as u8;
    }
    // A creeping vine, with neighbors to grow over.
    if p.vine {
        for i in count {
            let l, right = neighbors(board, i);
            ok[i] = l >= 0 || right >= 0;
        }
        let i = place_fixture(board, r, ok, Fixture.VineRoot);
        if i >= 0 { board.bottles[i].spread_every = clamp(p.vine_every, 1, 9) as u8; }
    }
    // Braziers stand next to what heat changes: ice, seals, the vine.
    for k in p.brazier {
        var any = false;
        for i in count {
            let b = board.bottles[i];
            near[i] = b.cover == Cover.Rime || b.cover == Cover.Seal || b.fixture == Fixture.VineRoot;
        }
        for i in count {
            ok[i] = next_to(board, i, near) && board.bottles[i].fixture == Fixture.None;
            if ok[i] { any = true; }
        }
        if !any { for i in count { ok[i] = true; } }
        if place_fixture(board, r, ok, Fixture.Brazier) < 0 { break; }
    }
    var targets = false;
    for i in count {
        let b = board.bottles[i];
        if b.fixture == Fixture.Brazier || b.fixture == Fixture.Lantern || b.body == Body.Hourglass { targets = true; }
    }
    for k in p.catalyst {
        if !targets { break; }
        for i in count { ok[i] = board.bottles[i].n > 0; }
        if place_fixture(board, r, ok, Fixture.Catalyst) < 0 { break; }
    }
    if p.salamander {
        for i in count { ok[i] = board.bottles[i].n > 0 && !covered(board.bottles[i]); }
        board.salamander = pick(r, ok[..count]);
    }
    settle(board);
    board
}

// No bottle may start complete, and the level should not be half done.
fn deal_ok(board: Board) -> bool {
    for i in board.count {
        let b = board.bottles[i];
        if b.done || (b.n == b.cap && is_uniform(b)) { return false; }
    }
    validate(board).len == 0 && !is_won(board)
}

// What attempt `attempt` deals with: after many failures, ease off, with
// fewer modifiers, then fewer colors.
fn attempt_params(p: GenParams, attempt: i64) -> GenParams {
    var plain = p;
    if attempt >= 200 {
        plain.murk = 0;
        plain.shroud = 0;
        plain.rime = 0;
        plain.vine = false;
    }
    if attempt >= 300 {
        plain = GenParams { colors: max(3, p.colors - 1), empties: 2, tall: p.tall, tall_height: p.tall_height };
    }
    plain
}

// Generation as a job that runs a slice at a time, so the game can keep
// drawing while it brews. Each attempt deals a board and searches it.
struct GenJob {
    params: GenParams,
    seed: u64,
    attempt: i64 = 0,
    dealt: Board,           // the deal being searched, while `search` runs
    searching: bool = false,
    done: bool = false,
    result: GenResult,      // once done
    search: Search,
}

fn gen_begin(p: GenParams, seed: u64) -> GenJob {
    GenJob { params: p, seed: seed, dealt: Board { .. }, result: GenResult { board: Board { .. }, stats: SolveStats {} },
             search: Search {}, .. }
}

// Works on the job for about `nodes` search positions (each deal counts as
// one). True once it is done and `job.result` holds the board.
fn gen_step(job: GenJob&, nodes: i64) -> bool {
    var left = max(1, nodes);
    while !job.done && left > 0 {
        if job.searching {
            let before = job.search.stats.expanded;
            let over = search_step(job.search, left);
            left -= max(1, job.search.stats.expanded - before);
            if !over { continue; }
            job.searching = false;
            if job.search.stats.solved {
                job.result = GenResult { board: job.dealt, stats: job.search.stats, attempts: job.attempt + 1 };
                job.done = true;
            }
            job.search = Search {};
            job.attempt++;
            continue;
        }
        left--;
        if job.attempt >= 400 {
            // Practically unreachable: three colors with two spares always solve.
            var r = rng { job.seed };
            let board = deal(GenParams { colors: 3, empties: 2 }, r);
            job.result = GenResult { board: board, stats: SolveStats {}, attempts: 401 };
            job.done = true;
            break;
        }
        var r = rng { job.seed * 0x9E3779B97F4A7C15 + (job.attempt as u64) * 0xD1B54A32D192ED03 + 17 };
        job.dealt = deal(attempt_params(job.params, job.attempt), r);
        if !deal_ok(job.dealt) {
            job.attempt++;
            continue;
        }
        job.search = search_begin(job.dealt, job.params.budget);
        job.searching = true;
    }
    job.done
}

fn generate(p: GenParams, seed: u64) -> GenResult {
    var job = gen_begin(p, seed);
    while !gen_step(job, 1 << 30) {}
    job.result
}
