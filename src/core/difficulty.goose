// How hard a board is, and whether every modifier on it matters. The
// generator measures each deal here and keeps one in its recipe's band
// whose modifiers all do something on the way to the win; the tests hold
// the campaign and the hand-made levels to the same checks. The solver sees
// through smoke and covers, so the score adds what a player can't see.
// docs/generation.md is the design it follows.

import std;
import .board;
import .solver;

// The modifiers, in the order the campaign introduces them.
enum Feature {
    Murk, Seal, Tall, Vow,              // The Apothecary
    Rime, Brazier, Quicksilver,         // The Frost Cellar
    Siphon, Keys, Curtain,              // The Glassworks
    Lantern, Shroud, Hourglass,         // The Observatory
    Vine, Salamander, Moonpetal,        // The Greenhouse
    Athanor, Drop, Catalyst,            // The Athanor
}

let FEATURES = 19;

let ALL_FEATURES: const Feature[19] = [
    Feature.Murk, Feature.Seal, Feature.Tall, Feature.Vow, Feature.Rime, Feature.Brazier, Feature.Quicksilver,
    Feature.Siphon, Feature.Keys, Feature.Curtain, Feature.Lantern, Feature.Shroud, Feature.Hourglass,
    Feature.Vine, Feature.Salamander, Feature.Moonpetal, Feature.Athanor, Feature.Drop, Feature.Catalyst,
];

fn feature_index(f: Feature) -> i64 {
    match f {
        Murk => 0, Seal => 1, Tall => 2, Vow => 3, Rime => 4, Brazier => 5, Quicksilver => 6, Siphon => 7,
        Keys => 8, Curtain => 9, Lantern => 10, Shroud => 11, Hourglass => 12, Vine => 13, Salamander => 14,
        Moonpetal => 15, Athanor => 16, Drop => 17, Catalyst => 18,
    }
}

fn feature_name(f: Feature) -> const u8[:] {
    match f {
        Murk => "Smoke", Seal => "Seal", Tall => "Tall Flask", Vow => "Vow Flask", Rime => "Rime",
        Brazier => "Brazier", Quicksilver => "Quicksilver", Siphon => "Siphon", Keys => "Keys and Doors",
        Curtain => "Curtain",
        Lantern => "Lantern", Shroud => "Shroud", Hourglass => "Hourglass", Vine => "Creeping Vine",
        Salamander => "Salamander", Moonpetal => "Moonpetal", Athanor => "Athanor",
        Drop => "Philosopher's Drop", Catalyst => "Catalyst",
    }
}

// How many of `f` are on the board: flasks that have it, doors, or 1 for
// the salamander, quicksilver and the Drop.
fn feature_count(board: Board, f: Feature) -> i64 {
    if f == Feature.Salamander { return if board.salamander >= 0 { 1 } else { 0 }; }
    if f == Feature.Keys { return board.door_count; }
    var n = 0;
    for i in board.count {
        let b = board.bottles[i];
        let on = match f {
            Murk => b.murk != 0,
            Seal => b.cover == Cover.Seal,
            Tall => b.cap > CAP,
            Vow => b.body == Body.Vow,
            Rime => b.cover == Cover.Rime,
            Brazier => b.fixture == Fixture.Brazier,
            Quicksilver => has_liquid_of(b, QUICKSILVER),
            Drop => has_liquid_of(b, DROP),
            Siphon => b.body == Body.Siphon,
            Keys, Salamander => false,
            Curtain => b.cover == Cover.Curtain,
            Lantern => b.fixture == Fixture.Lantern,
            Shroud => b.cover == Cover.Shroud,
            Hourglass => b.body == Body.Hourglass,
            Vine => b.fixture == Fixture.VineRoot,
            Moonpetal => b.body == Body.Moonpetal,
            Athanor => b.body == Body.Athanor,
            Catalyst => b.fixture == Fixture.Catalyst,
        };
        if on { n++; }
    }
    if (f == Feature.Quicksilver || f == Feature.Drop) && n > 0 { n = 1; }
    n
}

// Whether `f` is on the board.
fn feature_on(board: Board, f: Feature) -> bool {
    if f == Feature.Keys {
        for i in board.count { if board.bottles[i].key_color != KeyColor.None || board.bottles[i].behind { return true; } }
        return false;
    }
    feature_count(board, f) > 0
}

// --- measuring a board ------------------------------------------------------------------
//
// The solver plays the board; its solution and its search give the
// measures, and a weighted sum of them is the score. The weights live here
// and nowhere else; docs/generation.md has the numbers they were tuned to.

let W_LENGTH = 1.0;     // per pour in the solution
let W_EFFORT = 3.0;     // per doubling of the positions searched
let W_PARKING = 2.0;    // per pour that only makes room
let W_TRAPS = 2.0;      // per random start that ends in a dead end
let W_FREEDOM = 0.5;    // per legal pour, on average, along the solution (taken off)
let W_HIDDEN = 1.0;     // per layer hidden, on average, along the solution

// Traps: a few short random playouts from the start, each searched briefly
// for a proof that it can't be won.
let TRAP_PLAYOUTS = 6;
let TRAP_POURS = 6;
let TRAP_BUDGET = 150;

// The longest solution kept.
let MAX_PATH = 256;

struct Measure {
    solved: bool = false,
    exhausted: bool = false,// proven that it can't be won
    length: i64 = 0,        // pours in the solution found
    effort: i64 = 0,        // positions the solver expanded
    parking: i64 = 0,       // pours into an empty flask that is poured from again before it's done
    traps: i64 = 0,         // playouts that ended where the board can't be won
    freedom: f64 = 0.0,     // pours worth trying, on average, along the solution
    hidden: f64 = 0.0,      // layers out of sight, on average, along the solution
    score: f64 = 0.0,
}

// log2 with the fraction taken linearly between powers of two: only the
// four operations, so every build agrees to the last bit.
fn log2_of(x: i64) -> f64 {
    if x <= 1 { return 0.0; }
    let k = 63 - clz(x as u64);
    let p = 1 << k;
    k + (x - p) / (p as f64)
}

// The score without the traps (which only the full measure plays out).
fn base_score(m: Measure) -> f64 {
    W_LENGTH * m.length + W_EFFORT * log2_of(m.effort) + W_PARKING * m.parking - W_FREEDOM * m.freedom +
        W_HIDDEN * m.hidden
}

fn score_of(m: Measure) -> f64 { base_score(m) + W_TRAPS * m.traps }

// Layers a player can't see: under smoke, or in a flask that is sealed,
// shrouded, curtained or behind a shut door.
fn hidden_layers(board: Board) -> i64 {
    var n = 0;
    for i in board.count {
        let b = board.bottles[i];
        if contents_hidden(b) { n += b.n; } else { n += popcount(b.murk); }
    }
    n
}

// The measures that come from the solution itself: its length, parking,
// freedom and what stays hidden along it.
fn path_measure(m: Measure&, start: Board, path: const Move[:]) {
    m.length = path.len;
    var b = start;
    var moves: Move[>..] = [];
    var choices = 0;
    var hidden = hidden_layers(b);
    for m0, t in path {
        moves.clear();
        useful_moves(b, moves);
        choices += moves.len;
        let parked = b.bottles[m0.to].n == 0;
        let r = pour(b, m0.from, m0.to);
        hidden += hidden_layers(b);
        if !parked || b.bottles[m0.to].done { continue; }
        // Parked if something leaves it again before it is done.
        for later in path[t + 1..] {
            if later.from == m0.to { m.parking++; break; }
        }
    }
    let states = path.len + 1;
    m.freedom = if path.len > 0 { choices / (path.len as f64) } else { 0.0 };
    m.hidden = hidden / (states as f64);
}

// One short random playout from the start; the board it ends on.
fn playout(start: Board, r: rng&) -> Board {
    var b = start;
    var moves: Move[>..] = [];
    for k in TRAP_POURS {
        if is_won(b) { break; }
        moves.clear();
        useful_moves(b, moves);
        if moves.len == 0 { break; }
        let m = moves[r.rand_int(moves.len)];
        let res = pour(b, m.from, m.to);
    }
    b
}

// A measure in progress, a slice at a time like a search: the solve, then
// (once measure_traps asks) the trap playouts.
struct MeasureJob {
    start: Board,
    m: Measure = Measure {},
    path: Move[..256] = [],
    r: rng = rng { 1 },
    solving: bool = false,
    traps_left: i64 = 0,
    trapping: bool = false,    // `search` is on a playout's end
    done: bool = true,
    spent: i64 = 0,         // positions expanded, the traps' too
    search: Search,
}

fn measure_begin(board: Board, budget: i64) -> MeasureJob {
    MeasureJob { start: board, solving: true, done: false, search: search_begin(board, budget), .. }
}

// After the solve, plays `playouts` traps from `seed`.
fn measure_traps(job: MeasureJob&, playouts: i64, seed: u64) {
    if !job.m.solved { return; }
    job.r = rng { seed };
    job.traps_left = playouts;
    job.done = playouts <= 0;
}

// Works for about `nodes` positions. True when it is done: when the solve
// is over (see `m.solved`), and again after the traps.
fn measure_step(job: MeasureJob&, nodes: i64) -> bool {
    var left = max(1, nodes);
    while !job.done && left > 0 {
        if job.solving {
            let before = job.search.stats.expanded;
            let over = search_step(job.search, left);
            let spent = max(1, job.search.stats.expanded - before);
            left -= spent;
            job.spent += spent;
            if !over { continue; }
            job.solving = false;
            let s = job.search.stats;
            job.m.solved = s.solved && s.length <= MAX_PATH;
            job.m.exhausted = s.exhausted;
            job.m.effort = s.expanded;
            if job.m.solved {
                var path: Move[>..] = [];
                search_path(job.search, path);
                job.path.clear();
                for m in path { job.path.push(m); }
                path_measure(job.m, job.start, job.path[..]);
            }
            job.m.score = score_of(job.m);
            job.search = Search {};
            job.done = true;
        } else if job.trapping {
            let before = job.search.stats.expanded;
            let over = search_step(job.search, left);
            let spent = max(1, job.search.stats.expanded - before);
            left -= spent;
            job.spent += spent;
            if !over { continue; }
            job.trapping = false;
            if job.search.stats.exhausted { job.m.traps++; }
            job.search = Search {};
        } else if job.traps_left > 0 {
            left--;
            job.spent++;
            job.traps_left--;
            let end = playout(job.start, job.r);
            if is_won(end) { continue; }
            if !has_move(end) {
                job.m.traps++;
                continue;
            }
            job.search = search_begin(end, TRAP_BUDGET);
            job.trapping = true;
        } else {
            job.m.score = score_of(job.m);
            job.done = true;
        }
    }
    job.done
}

// The whole measure at once, traps included: for the tests and tools.
fn measure(board: Board, budget: i64, seed: u64) -> Measure {
    var job = measure_begin(board, budget);
    while !measure_step(job, 1 << 30) {}
    measure_traps(job, TRAP_PLAYOUTS, seed);
    while !measure_step(job, 1 << 30) {}
    job.m
}

// --- every modifier must matter --------------------------------------------------------
//
// Each modifier on the board has a use test on the solution: what has to
// happen along it for the modifier to have done something. A board fails
// when any one modifier (any one flask's, for those on flasks) does nothing.

struct Uses {
    on: bool[19] = [false; 19],     // by feature_index: on the board
    used: bool[19] = [false; 19],   //   and every one of them did something
}

fn heat_target(c: Cover) -> bool { c == Cover.Rime || c == Cover.Seal || c == Cover.Vine }

// Replays `path` from `start` and sees what each modifier did.
fn uses_of(start: Board, path: const Move[:]) -> Uses {
    var u = Uses {};
    for f in ALL_FEATURES { u.on[feature_index(f)] = feature_on(start, f); }
    // What each flask's modifier did; a flask without it never needs to.
    var ok: bool[19][MAX_BOTTLES] = [[false; 19]; MAX_BOTTLES];
    var opened: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];  // its ice, shroud or curtain is gone
    var lit_at: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
    var door_open: bool[MAX_DOORS] = [false; MAX_DOORS];
    var door_used: bool[MAX_DOORS] = [false; MAX_DOORS];
    var smoke = 0;
    for i in start.count { smoke += popcount(start.bottles[i].murk); }
    var uncovered = 0;
    var tall_done = false;
    var b = start;
    for m in path {
        let before = b;
        let src = before.bottles[m.from];
        let dst = before.bottles[m.to];
        let r = pour(b, m.from, m.to);
        if !r.ok { break; }
        let into = r.amount > 0;
        // A flask once opened, poured from or into.
        for i in [m.from, m.to] {
            if i == m.to && !into { continue; }
            if opened[i] {
                ok[i][feature_index(Feature.Rime)] = true;
                ok[i][feature_index(Feature.Shroud)] = true;
                ok[i][feature_index(Feature.Curtain)] = true;
            }
            let d: i64 = start.bottles[i].door;
            if d >= 0 && door_open[d] { door_used[d] = true; }
        }
        if src.body == Body.Siphon && src.seg[0] != top(src) { ok[m.from][feature_index(Feature.Siphon)] = true; }
        if dst.body == Body.Moonpetal && into {
            ok[m.to][feature_index(Feature.Moonpetal)] = true;
            for i in b.count { if lit_at[i] { ok[i][feature_index(Feature.Lantern)] = true; } }
        }
        if r.color == QUICKSILVER && into && dst.body != Body.Athanor {
            var other = false;
            for k in dst.n as i64 { if dst.seg[k] != QUICKSILVER { other = true; } }
            if other { u.used[feature_index(Feature.Quicksilver)] = true; }
        }
        for i in b.count {
            let gone = popcount(before.bottles[i].murk) - popcount(b.bottles[i].murk);
            if gone > 0 && !b.bottles[i].done { uncovered += gone; }
        }
        // What the pour set off, in order: the pour and a brazier's heat,
        // then the salamander's, then a catalyst's.
        var phase = 0;
        var lit_now = -1;
        var catalyst_at = -1;
        var effects = 0;
        for e, at in r.events {
            let i: i64 = e.bottle;
            match e.kind {
                SealBroken => { if i >= 0 { ok[i][feature_index(Feature.Seal)] = true; } },
                SealSoftened => {},
                Vowed => { ok[i][feature_index(Feature.Vow)] = true; },
                Thawed, ShroudLifted, CurtainOpened => { opened[i] = true; },
                HeatPulse => {
                    // It found ice, a seal or a tendril (one may have grown
                    // in this same pour, and burns at once).
                    var hit = heat_target(before.bottles[i].cover);
                    if at + 1 < r.events.len {
                        let x = r.events[at + 1];
                        if x.bottle == e.bottle && (x.kind == EventKind.TendrilBurned || x.kind == EventKind.Thawed ||
                                                    x.kind == EventKind.SealSoftened || x.kind == EventKind.SealBroken) {
                            hit = true;
                        }
                    }
                    if hit {
                        if phase == 1 { u.used[feature_index(Feature.Salamander)] = true; }
                        else if e.from >= 0 { ok[e.from][feature_index(Feature.Brazier)] = true; }
                        if phase == 2 { effects++; }
                    }
                },
                Lit => {
                    lit_now = i;
                    lit_at[i] = true;
                    if phase == 2 { effects++; }
                },
                MurkCleared => {},
                Flipped => {
                    if phase == 2 { effects++; }
                    if top(before.bottles[i]) != top(b.bottles[i]) && !b.bottles[i].done {
                        ok[i][feature_index(Feature.Hourglass)] = true;
                    }
                },
                VineSpread, VineWithered => { u.used[feature_index(Feature.Vine)] = true; },
                TendrilBurned => {},
                SalamanderHop => { phase = 1; },
                Transmuted => {
                    // Quicksilver an athanor turns to gold has done its part.
                    u.used[feature_index(Feature.Athanor)] = true;
                    u.used[feature_index(Feature.Quicksilver)] = true;
                },
                CatalystFired => {
                    phase = 2;
                    catalyst_at = i;
                },
                Completed => { if b.bottles[i].cap > CAP { tall_done = true; } },
                KeyFreed => {},
                DoorOpened => { if e.door >= 0 { door_open[e.door] = true; } },
            }
            // Light that uncovers what was still hidden.
            if (e.kind == EventKind.MurkCleared || e.kind == EventKind.ShroudLifted) && e.from >= 0 &&
               before.bottles[e.from].fixture == Fixture.Lantern {
                ok[e.from][feature_index(Feature.Lantern)] = true;
            }
        }
        if catalyst_at >= 0 && effects >= 2 { ok[catalyst_at][feature_index(Feature.Catalyst)] = true; }
    }
    let won = is_won(b);
    // Per flask: every flask with the modifier did something with it.
    for f in [Feature.Seal, Feature.Vow, Feature.Rime, Feature.Brazier, Feature.Siphon, Feature.Curtain,
              Feature.Lantern, Feature.Shroud, Feature.Hourglass, Feature.Moonpetal, Feature.Catalyst] {
        let k = feature_index(f);
        if !u.on[k] { continue; }
        var all = true;
        for i in start.count { if flask_has_feature(start, i, f) && !ok[i][k] { all = false; } }
        u.used[k] = all;
    }
    // Smoke: at least half its layers come to light before their flask is done.
    u.used[feature_index(Feature.Murk)] = smoke > 0 && uncovered * 2 >= smoke;
    u.used[feature_index(Feature.Tall)] = tall_done;
    var doors = true;
    for d in start.door_count { if !door_used[d] { doors = false; } }
    u.used[feature_index(Feature.Keys)] = doors && start.door_count > 0;
    // The Drop ends up completing a flask whenever the board is won.
    u.used[feature_index(Feature.Drop)] = won;
    u
}

fn flask_has_feature(board: Board, i: i64, f: Feature) -> bool {
    let b = board.bottles[i];
    match f {
        Seal => b.cover == Cover.Seal,
        Vow => b.body == Body.Vow,
        Rime => b.cover == Cover.Rime,
        Brazier => b.fixture == Fixture.Brazier,
        Siphon => b.body == Body.Siphon,
        Curtain => b.cover == Cover.Curtain,
        Lantern => b.fixture == Fixture.Lantern,
        Shroud => b.cover == Cover.Shroud,
        Hourglass => b.body == Body.Hourglass,
        Moonpetal => b.body == Body.Moonpetal,
        Catalyst => b.fixture == Fixture.Catalyst,
        _ => false,
    }
}

// The first modifier on the board that did nothing, or false when every
// one did.
fn unused_feature(u: Uses) -> Feature, bool {
    for f in ALL_FEATURES {
        let k = feature_index(f);
        if u.on[k] && !u.used[k] { return f, true; }
    }
    return Feature.Murk, false;
}

// --- the focus is required ------------------------------------------------------------
//
// The modifier a level is about must be required: taken out, the board
// can't be won, or plays clearly differently (an obstacle gone makes it
// easier, a helper gone harder).

let FOCUS_MIN = 2.0;        // the least change in score that counts
let FOCUS_SHARE = 0.1;     //   or this share of the score, if more

// Whether `f` can be taken out to see if it is required. A tall flask
// can't be taken out without changing its color's count.
fn neutral_exists(f: Feature) -> bool { f != Feature.Tall }

// The board with `f` taken out: a seal with no wax, ice already melted, a
// brazier with no fire, doors left open, a lantern gone, an empty vow flask
// shut (it is the spare the level needs), and so on.
fn without_feature(board: Board, f: Feature) -> Board {
    var b = board;
    var unused_dye = 0;
    if f == Feature.Quicksilver {
        var seen: bool[MAX_LIQUID + 1] = [false; MAX_LIQUID + 1];
        for i in b.count { for k in b.bottles[i].n as i64 { seen[b.bottles[i].seg[k]] = true; } }
        for c in 1..MAX_COLORS + 1 { if !seen[c] && unused_dye == 0 { unused_dye = c; } }
    }
    if f == Feature.Salamander { b.salamander = -1; }
    if f == Feature.Keys { for d in b.door_count { b.doors[d].open = true; } }
    for i in b.count {
        var x .= b.bottles[i];
        match f {
            Murk => { x.murk = 0; },
            Seal => { if x.cover == Cover.Seal { x.cover = Cover.None; } },
            Rime => { if x.cover == Cover.Rime { x.cover = Cover.None; } },
            Shroud => { if x.cover == Cover.Shroud { x.cover = Cover.None; } },
            Curtain => { if x.cover == Cover.Curtain { x.cover = Cover.None; } },
            Vow => { if x.body == Body.Vow && x.n == 0 { x.done = true; } },
            Siphon => { if x.body == Body.Siphon { x.body = Body.Plain; } },
            Hourglass => { if x.body == Body.Hourglass { x.body = Body.Plain; } },
            Moonpetal => { if x.body == Body.Moonpetal { x.body = Body.Plain; } },
            Brazier => { if x.fixture == Fixture.Brazier { x.fixture = Fixture.None; } },
            Lantern => { if x.fixture == Fixture.Lantern { x.fixture = Fixture.None; } },
            Catalyst => { if x.fixture == Fixture.Catalyst { x.fixture = Fixture.None; } },
            Vine => {
                if x.cover == Cover.Vine { x.cover = Cover.None; }
                if x.fixture == Fixture.VineRoot { x.fixture = Fixture.None; x.spread_every = 0; }
            },
            Keys => {
                x.behind = false;
                x.key_color = KeyColor.None;
                x.keyed = 0;
            },
            Quicksilver => { for k in x.n as i64 { if x.seg[k] == QUICKSILVER { x.seg[k] = unused_dye as u8; } } },
            Athanor => {
                // The gold already made, in a plain flask.
                if x.body == Body.Athanor { x.body = Body.Plain; }
                for k in x.n as i64 { if x.seg[k] == QUICKSILVER { x.seg[k] = GOLD; } }
            },
            Drop => {},
            Salamander, Tall => {},
        }
    }
    if f == Feature.Drop {
        // The Drop becomes the segment its color is short of.
        var tally: i64[MAX_LIQUID + 1] = [0; MAX_LIQUID + 1];
        for i in b.count { for k in b.bottles[i].n as i64 { tally[b.bottles[i].seg[k]]++; } }
        var short = 0;
        for c in 1..DROP { if tally[c] == CAP - 1 { short = c; } }
        for i in b.count {
            var x .= b.bottles[i];
            for k in x.n as i64 { if x.seg[k] == DROP && short > 0 { x.seg[k] = short as u8; } }
        }
    }
    seal_complete(b);
    b
}

// Whether a focus that scored `with` is required, given the measure of the
// board without it.
fn focus_required(with: f64, without: Measure) -> bool {
    if !without.solved { return true; }    // can't be won, or not within the search: clearly harder
    abs(base_score(without) - with) >= max(FOCUS_MIN, FOCUS_SHARE * abs(with))
}

// The whole check at once, for the tests: `f` is required on `board`.
fn requires(board: Board, f: Feature, budget: i64) -> bool {
    if !neutral_exists(f) { return true; }
    var job = measure_begin(board, budget);
    while !measure_step(job, 1 << 30) {}
    var nj = measure_begin(without_feature(board, f), budget);
    while !measure_step(nj, 1 << 30) {}
    focus_required(base_score(job.m), nj.m)
}
