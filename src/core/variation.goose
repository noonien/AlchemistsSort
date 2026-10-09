// Each new attempt at a level is a slight variant of it, so its hidden
// layers can't be learned by heart: the colors are permuted, and what lies
// under smoke and inside sealed and shrouded flasks is dealt again among
// those hidden places. Everything visible, every modifier and every key
// stay where they are. A reshuffle is kept only when it can still be won,
// scores within 15% of the level, and every modifier still does something;
// else the attempt is the recolor alone. The first attempt is the level
// itself. docs/generation.md has the design.

import std;
import .board;
import .solver;
import .difficulty;

let VARY_TRIES = 6;         // reshuffles tried for an attempt
let VARY_BUDGET = 6000;     // solver positions per measure
let VARY_SHARE = 0.15;      // how far a variant's score may stray

// Whether color c keeps its place in a recolor: gold, quicksilver and the
// Drop, emerald where a vine waits on it, and any color `named` in words
// the player reads about the level (a hand-made level's hint).
fn fixed_color(board: Board, c: i64, named: const u8[:]) -> bool {
    if c > MAX_COLORS { return true; }
    if c == EMERALD && feature_on(board, Feature.Vine) { return true; }
    let name = COLOR_NAMES[c];
    for at in 0..named.len - name.len + 1 {
        var same = true;
        for k in name.len {
            var x = named[at + k];
            if x >= 'A' && x <= 'Z' { x = x + 32; }
            var y = name[k];
            if y >= 'A' && y <= 'Z' { y = y + 32; }
            if x != y { same = false; break; }
        }
        if same { return true; }
    }
    false
}

// The board with its dyes permuted. Whatever names a color (a seal's key,
// a curtain's badge, a vow already taken) moves with it.
fn recolor(board: Board, named: const u8[:], r: rng&) -> Board {
    var present: bool[MAX_LIQUID + 1] = [false; MAX_LIQUID + 1];
    for i in board.count { for k in board.bottles[i].n as i64 { present[board.bottles[i].seg[k]] = true; } }
    var free: i64[..MAX_COLORS] = [];
    for c in 1..MAX_COLORS + 1 { if present[c] && !fixed_color(board, c, named) { free.push(c); } }
    var to = free;
    shuffle(to[..], r);
    var map: u8[MAX_LIQUID + 1] = [0; MAX_LIQUID + 1];
    for c in MAX_LIQUID + 1 { map[c] = c as u8; }
    for c, k in free { map[c] = to[k] as u8; }
    var b = board;
    for i in b.count {
        var x .= b.bottles[i];
        for k in x.n as i64 { x.seg[k] = map[x.seg[k]]; }
        x.key = map[x.key];
        x.badge = map[x.badge];
        x.vow = map[x.vow];
    }
    b
}

// Whether segment k of flask i is hidden and may be dealt again: under
// smoke, or in a sealed or shrouded flask; not a key's segment, not
// quicksilver (it sinks) nor the Drop, not in a vow flask (its color is
// its vow) or a flask that is done.
fn hidden_slot(board: Board, i: i64, k: i64) -> bool {
    let b = board.bottles[i];
    if k >= b.n || b.done || b.body == Body.Vow || b.behind || b.cover == Cover.Curtain { return false; }
    if (b.keyed as i64 >> k) & 1 != 0 { return false; }
    let c: i64 = b.seg[k];
    if c == QUICKSILVER || c == DROP { return false; }
    b.cover == Cover.Seal || b.cover == Cover.Shroud || murky(b, k)
}

// The hidden layers dealt again among their places.
fn reshuffle_hidden(board: Board, r: rng&) -> Board {
    var b = board;
    var colors: u8[..MAX_BOTTLES * MAX_CAP] = [];
    for i in b.count { for k in b.bottles[i].n as i64 { if hidden_slot(b, i, k) { colors.push(b.bottles[i].seg[k]); } } }
    shuffle(colors[..], r);
    var at = 0;
    for i in b.count {
        for k in b.bottles[i].n as i64 {
            if hidden_slot(board, i, k) {
                b.bottles[i].seg[k] = colors[at];
                at++;
            }
        }
    }
    b
}

// A variant in the making, a slice at a time: the level is measured, then
// reshuffles are tried until one passes.
struct VariantJob {
    level: Board,           // the level as made
    recolored: Board,       // this attempt's recolor: the fallback
    trial: Board,           // the reshuffle being measured
    result: Board,          // once done
    r: rng = rng { 1 },
    score: f64 = 0.0,       // the level's score (without traps)
    measured: bool = false, // `score` is known
    tries: i64 = 0,         // reshuffles left
    reshuffled: bool = false,   // the result is a reshuffle, not the recolor alone
    done: bool = false,
    job: MeasureJob,
}

// The variant for attempt `attempt` (0, the first, is the level itself) of
// the level `board`, drawn from `seed`; colors `named` in its hint stay.
fn variant_begin(board: Board, seed: u64, attempt: i64, named: const u8[:]) -> VariantJob {
    var job = VariantJob { level: board, recolored: board, trial: board, result: board,
                           job: MeasureJob { start: board, search: Search {} }, .. };
    if attempt <= 0 {
        job.done = true;
        return job;
    }
    job.r = rng { hash(seed ^ (attempt as u64 * 0x9E3779B97F4A7C15)) + 3 };
    job.recolored = recolor(board, named, job.r);
    job.result = job.recolored;
    // Nothing hidden to deal again: the recolor is the variant.
    var hidden = 0;
    for i in board.count { for k in board.bottles[i].n as i64 { if hidden_slot(board, i, k) { hidden++; } } }
    if hidden < 2 {
        job.done = true;
        return job;
    }
    job.tries = VARY_TRIES;
    job.job = measure_begin(board, VARY_BUDGET);
    job
}

// Whether the reshuffle `b` measured as `m` keeps the level as it is.
fn variant_ok(job: VariantJob&, m: Measure) -> bool {
    if !m.solved { return false; }
    if abs(base_score(m) - job.score) > VARY_SHARE * abs(job.score) { return false; }
    let f, unused = unused_feature(uses_of(job.trial, job.job.path[..]));
    !unused
}

// The next reshuffle worth measuring, or false when the tries ran out.
fn next_trial(job: VariantJob&) -> bool {
    while job.tries > 0 {
        job.tries--;
        var t = reshuffle_hidden(job.recolored, job.r);
        seal_complete(t);
        var fine = validate(t).len == 0 && !is_won(t);
        for i in t.count { if t.bottles[i].done != job.recolored.bottles[i].done { fine = false; } }
        if !fine { continue; }
        job.trial = t;
        job.job = measure_begin(t, VARY_BUDGET);
        return true;
    }
    false
}

// Works for about `nodes` positions. True once `job.result` is the
// attempt's board.
fn variant_step(job: VariantJob&, nodes: i64) -> bool {
    var left = max(1, nodes);
    while !job.done && left > 0 {
        let before = job.job.spent;
        let over = measure_step(job.job, left);
        left -= max(1, job.job.spent - before);
        if !over { continue; }
        if !job.measured {
            // The level itself, to compare with.
            job.measured = true;
            job.score = base_score(job.job.m);
            if !job.job.m.solved || !next_trial(job) { job.done = true; }
            continue;
        }
        if variant_ok(job, job.job.m) {
            job.result = job.trial;
            job.reshuffled = true;
            job.done = true;
            continue;
        }
        if !next_trial(job) { job.done = true; }
    }
    if job.done { job.job.search = Search {}; }
    job.done
}

// The board for attempt `attempt` at the level `board`, all at once.
fn variant(board: Board, seed: u64, attempt: i64, named: const u8[:]) -> Board {
    var job = variant_begin(board, seed, attempt, named);
    while !variant_step(job, 1 << 30) {}
    job.result
}
