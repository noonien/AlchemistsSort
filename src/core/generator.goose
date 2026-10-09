// Levels from a recipe and a seed. A deal is random -- every segment of
// every color shuffled into bottles of chosen fill heights -- then dressed
// with the modifiers asked for, each placed where it can act. The solver
// plays every deal: it is kept when it is in the recipe's difficulty band,
// every modifier on it does something on the way to the win, and the
// recipe's focus is required (difficulty.goose). The same recipe and seed
// always give the same board. docs/generation.md is the design.

import std;
import .board;
import .solver;
import .difficulty;

// What a level is made of, and how hard it should be.
struct Recipe {
    colors: i64 = 3,
    spares: i64 = 2,        // empty flasks beyond the colors; a vow flask is one of them
    partial: i64 = 0,       // segments moved off full flasks into the spares at the deal
    smoke: i64 = 0,         // layers that start under smoke
    tall: i64 = 0,          // tall flasks, each with one color dealt to fill it
    tall_rows: i64 = 2,     // the rows each spans: its height is tall_cap(tall_rows)
    mods: i64[19] = [0; 19],    // how many of each modifier, by feature_index (smoke and tall above)
    focus: Feature = Feature.Murk,  // the modifier the level is about, when `focused`
    focused: bool = false,
    band_lo: f64 = -1e9,    // the difficulty band: the score it should land in
    band_hi: f64 = 1e9,
    thaw: i64 = 3,          // the fewest pours ice takes to melt (up to three more)
    flip_every: i64 = 3,    // an hourglass's pours between flips
    vine_every: i64 = 4,    // a vine's pours between spreads
    athanor_quicksilver: i64 = 2,   // how much of the athanor's gold starts as quicksilver
    budget: i64 = 6000,     // solver positions per deal
}

fn wanted(p: Recipe, f: Feature) -> i64 { p.mods[feature_index(f)] }

fn want(p: Recipe&, f: Feature, n: i64) { p.mods[feature_index(f)] = n; }

fn modifier_count(p: Recipe) -> i64 {
    var n = 0;
    for m in p.mods { n += m; }
    n
}

struct GenResult {
    board: Board,
    m: Measure = Measure {},
    attempts: i64 = 0,      // deals tried
    valid_at: i64 = 0,      // the deal (counting from 1) that first passed every check but the band
    in_band: bool = false,
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

fn has_color(b: Bottle, c: i64) -> bool { has_liquid_of(b, c) }

// The segments a key can be buried in: under one to three layers of other
// colors, so it doesn't start free and isn't out of reach.
fn key_depths(b: Bottle) -> i64[..MAX_CAP] {
    var out: i64[..MAX_CAP] = [];
    for k in b.n as i64 {
        var x = b;
        x.keyed = (1 << k) as u16;
        let over = layers_over_key(x);
        if over >= 1 && over <= 3 { out.push(k); }
    }
    out
}

// Whether a neighbor of `i` is marked in `near`.
fn next_to(board: Board, i: i64, near: const bool[:]) -> bool {
    for j in neighbors(board, i) { if near[j] { return true; } }
    false
}

// Puts a fixture on a random flask with `ok` set and no fixture yet.
fn place_fixture(board: Board&, r: rng&, ok: bool[:], f: Fixture) -> i64 {
    for i in board.count { if board.bottles[i].fixture != Fixture.None { ok[i] = false; } }
    let i = pick(r, ok[..board.count]);
    if i >= 0 { board.bottles[i].fixture = f; }
    i
}

// The distinct liquids in a flask.
fn kinds(b: Bottle) -> i64 {
    var seen: bool[MAX_LIQUID + 1] = [false; MAX_LIQUID + 1];
    var n = 0;
    for k in b.n as i64 {
        if !seen[b.seg[k]] { seen[b.seg[k]] = true; n++; }
    }
    n
}

// An ordinary flask in plain play: not tall, not behind a door. Bodies,
// covers, fixtures and smoke only go on these (the generator keeps the
// flasks behind a door plain, and nothing comes out of a tall one).
fn in_play(b: Bottle) -> bool { b.cap == CAP && b.door < 0 }

// Where a lantern (or a catalyst) can stand and be dealt one color under
// its top: an ordinary flask in play with two layers or more and nothing
// on it yet.
fn lantern_spot(board: Board, i: i64) -> bool {
    let b = board.bottles[i];
    in_play(b) && b.n > 1 && !covered(b) && b.fixture == Fixture.None && b.body == Body.Plain &&
        b.key_color == KeyColor.None
}

// A flask that can give segments to another's arrangement: ordinary, plain,
// with nothing on it, and not `locked`.
fn donor(board: Board, j: i64, locked: const i64[:]) -> bool {
    let b = board.bottles[j];
    b.cap == CAP && b.body == Body.Plain && !covered(b) && b.key_color == KeyColor.None && !contains(locked, j)
}

// Deals flask i one color under its top layer, which is another color, and
// one more of that color on top of another flask, by swapping segments
// with donor flasks: it can be completed early, so what it sets off (a
// lantern's light, a catalyst) comes while it still matters.
fn one_color_under_top(board: Board&, i: i64, locked: const i64[:]) {
    let n: i64 = board.bottles[i].n;
    if n < 2 || board.bottles[i].key_color != KeyColor.None || covered(board.bottles[i]) { return; }
    var tally: i64[MAX_LIQUID + 1] = [0; MAX_LIQUID + 1];
    var here: i64[MAX_LIQUID + 1] = [0; MAX_LIQUID + 1];
    for j in board.count { for k in board.bottles[j].n as i64 { tally[board.bottles[j].seg[k]]++; } }
    for k in n - 1 { here[board.bottles[i].seg[k]]++; }
    var tall: bool[MAX_LIQUID + 1] = [false; MAX_LIQUID + 1];
    for j in board.count { tall[tall_color(board.bottles[j])] = true; }
    // The color: the one most of the flask is already, that has enough.
    var x = 0;
    for c in 1..MAX_LIQUID + 1 {
        if c == QUICKSILVER || c == DROP || tall[c] || tally[c] < n - 1 { continue; }
        if x == 0 || here[c] > here[x] { x = c; }
    }
    if x == 0 { return; }
    fn swap_in(k: i64, want_x: bool) -> bool {
        for j in board.count {
            if j != i && !donor(board, j, locked) { continue; }
            for kk in board.bottles[j].n as i64 {
                if j == i && kk != n - 1 { continue; }
                let c: i64 = board.bottles[j].seg[kk];
                if (c == x) != want_x || c == QUICKSILVER { continue; }
                board.bottles[j].seg[kk] = board.bottles[i].seg[k];
                board.bottles[i].seg[k] = c as u8;
                return true;
            }
        }
        false
    }
    for k in n - 1 { if board.bottles[i].seg[k] != x { swap_in(k, true); } }
    if board.bottles[i].seg[n - 1] == x { swap_in(n - 1, false); }
    // And one more of it on top of another flask, in reach.
    for j in board.count {
        let b = board.bottles[j];
        if j == i || !donor(board, j, locked) || b.n == 0 || top(b) == x || b.murk != 0 { continue; }
        for jj in board.count {
            if jj == i || jj == j || !donor(board, jj, locked) { continue; }
            for kk in board.bottles[jj].n as i64 {
                if board.bottles[jj].seg[kk] != x || (jj == j) { continue; }
                board.bottles[jj].seg[kk] = board.bottles[j].seg[b.n - 1];
                board.bottles[j].seg[b.n - 1] = x as u8;
                return;
            }
        }
    }
}

// One random deal with the modifiers, each placed where it can act, before
// any check that it can be won.
fn deal(p: Recipe, r: rng&) -> Board {
    var board = Board { .. };
    let colors = clamp(p.colors, 1, MAX_COLORS);
    board.colors = colors;
    let talls = clamp(p.tall, 0, colors);
    // A vow flask is one of the spares, not one more: an empty vow need not
    // be used, so it is there only when the board needs it.
    let vows = clamp(wanted(p, Feature.Vow), 0, max(0, p.spares));
    let doors = clamp(wanted(p, Feature.Keys), 0, MAX_DOORS);
    let athanor = wanted(p, Feature.Athanor) > 0;
    let extra = vows + doors + (if athanor { 1 } else { 0 });
    let bottles = min(colors + max(0, p.spares) - vows, MAX_BOTTLES - extra - talls);
    // What each dealt color is poured as: a dye, or quicksilver, or the
    // athanor's gold. A vine wants emerald on the board to wither it.
    var liquid: i64[MAX_COLORS + 1] = [0; MAX_COLORS + 1];
    for c in 1..colors + 1 { liquid[c] = c; }
    var gold_color = -1;
    if wanted(p, Feature.Vine) > 0 && colors < EMERALD { liquid[colors] = EMERALD; }
    var non_emerald: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
    for c in 1..colors + 1 { non_emerald[c] = liquid[c] != EMERALD || wanted(p, Feature.Vine) == 0; }
    if athanor {
        gold_color = pick(r, non_emerald[..colors + 1]);
        liquid[gold_color] = GOLD;
    } else if wanted(p, Feature.Quicksilver) > 0 {
        liquid[pick(r, non_emerald[..colors + 1])] = QUICKSILVER;
    }
    var special: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
    for c in 1..colors + 1 { special[c] = liquid[c] == GOLD || liquid[c] == QUICKSILVER; }

    // Fill heights: full bottles, then the spares; `partial` segments move
    // from the top of full bottles to the spares, one at a time. Seals want
    // a bottle with room under them.
    var heights: i64[MAX_BOTTLES] = [0; MAX_BOTTLES];
    for i in colors { heights[i] = CAP; }
    let partial = max(p.partial, wanted(p, Feature.Seal));
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
    let tall = tall_cap(clamp(p.tall_rows, 2, 3));
    var tall_color: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
    for k in talls {
        var free: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
        for c in 1..colors + 1 { free[c] = !tall_color[c] && !special[c] && non_emerald[c]; }
        let c = pick(r, free[..colors + 1]);
        if c < 0 { break; }
        tall_color[c] = true;
    }
    // The Drop stands in for one segment of an ordinary color, never a tall
    // flask's: it can't go in there.
    var drop_color = -1;
    if wanted(p, Feature.Drop) > 0 {
        var ok: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
        for c in 1..colors + 1 { ok[c] = !special[c] && !tall_color[c]; }
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
    var dealt: Bottle[..MAX_BOTTLES] = [];
    for i in bottles {
        var b = Bottle { .. };
        for k in heights[i] {
            b.seg[k] = segs[at];
            at++;
        }
        b.n = heights[i] as u8;
        dealt.push(b);
    }
    // Doors: each stands before one or two dealt flasks with liquid, side
    // by side, and an extra empty one after them; place_grid keeps them
    // together in a row.
    for d in doors {
        let g = 1 + r.rand_int(2);
        var ok: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
        for i in dealt.len {
            ok[i] = i + g <= dealt.len;
            for k in g {
                if i + k < dealt.len && (dealt[i + k].door >= 0 || dealt[i + k].n == 0) { ok[i] = false; }
            }
        }
        let s = pick(r, ok[..dealt.len]);
        if s < 0 { break; }
        for k in g { dealt[s + k].door = d as i8; }
        var e = Bottle { .. };
        e.door = d as i8;
        insert_at(dealt, s + g, e);
        board.doors[d] = Door { color: KEY_COLORS[d] };
        board.door_count = d + 1;
    }
    for b in dealt { push_bottle(board, b); }
    for c in 1..colors + 1 {
        if !tall_color[c] { continue; }
        var b = Bottle { cap: tall as u8, .. };
        for s in tall - CAP { b.seg[s] = liquid[c] as u8; }
        b.n = (tall - CAP) as u8;
        push_bottle(board, b);
    }
    for k in vows {
        var b = Bottle { .. };
        b.body = Body.Vow;
        push_bottle(board, b);
    }
    if athanor {
        var b = Bottle { .. };
        b.body = Body.Athanor;
        push_bottle(board, b);
    }
    // Every bottle is in the grid now, so neighbors are known.
    place_grid(board);
    let count = board.count;

    // The modifiers that act on others go down first, then what they act
    // on beside them: a lantern, then smoke and a shroud by it; a brazier,
    // then ice or a seal by it.
    var ok: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
    var near: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
    fn plain_with(i: i64) -> bool {
        let b = board.bottles[i];
        in_play(b) && b.body == Body.Plain && b.n > 0
    }
    // What a cover may go on: an ordinary flask in play with liquid, no
    // cover yet and no key (a cover would hide the key's layer).
    fn coverable(i: i64) -> bool {
        let b = board.bottles[i];
        in_play(b) && b.n > 0 && !covered(b) && b.key_color == KeyColor.None
    }
    fn smokable(i: i64) -> bool {
        let b = board.bottles[i];
        in_play(b) && b.n > 1 && b.body != Body.Siphon && b.murk == 0 && !covered(b) && b.fixture != Fixture.Lantern
    }
    // Lanterns: one beside each shroud, the others beside flasks smoke can
    // hide (or anywhere, where a moonpetal waits). A lantern's flask is
    // dealt one color under its top layer, so it lights while there is
    // still something for the light to find.
    let moonpetal = wanted(p, Feature.Moonpetal) > 0;
    let shrouds = wanted(p, Feature.Shroud);
    let lanterns = max(wanted(p, Feature.Lantern), if moonpetal { 1 } else { 0 });
    var lantern_at: i64[..MAX_BOTTLES] = [];
    for k in shrouds {
        for i in count { near[i] = board.bottles[i].fixture == Fixture.Lantern || lantern_spot(board, i); }
        for i in count { ok[i] = coverable(i) && next_to(board, i, near); }
        let i = pick(r, ok[..count]);
        if i < 0 { break; }
        board.bottles[i].cover = Cover.Shroud;
        var lit = false;
        for j in neighbors(board, i) { if board.bottles[j].fixture == Fixture.Lantern { lit = true; } }
        if lit { continue; }
        for j in count { ok[j] = are_neighbors(board, i, j) && lantern_spot(board, j); }
        let at = place_fixture(board, r, ok, Fixture.Lantern);
        if at >= 0 { lantern_at.push(at); }
    }
    for k in max(0, lanterns - lantern_at.len) {
        for i in count { near[i] = smokable(i); }
        for i in count { ok[i] = lantern_spot(board, i) && (next_to(board, i, near) || moonpetal); }
        let at = place_fixture(board, r, ok, Fixture.Lantern);
        if at < 0 { break; }
        lantern_at.push(at);
    }
    // (Where a moonpetal waits on the light, it comes in its own time.)
    if !moonpetal { for i in lantern_at { one_color_under_top(board, i, lantern_at[..]); } }
    // Bodies. A siphon whose tap lets out something other than its top; an
    // hourglass holding two colors at least, so a flip changes its top; a
    // moonpetal with room or more than one color, so it has to take liquid.
    for k in wanted(p, Feature.Siphon) {
        for i in count { ok[i] = plain_with(i) && board.bottles[i].seg[0] != top(board.bottles[i]); }
        let i = pick(r, ok[..count]);
        if i < 0 { break; }
        board.bottles[i].body = Body.Siphon;
    }
    for k in wanted(p, Feature.Hourglass) {
        for i in count { ok[i] = plain_with(i) && kinds(board.bottles[i]) >= 2; }
        let i = pick(r, ok[..count]);
        if i < 0 { break; }
        board.bottles[i].body = Body.Hourglass;
        board.bottles[i].flip_every = clamp(p.flip_every, 1, 9) as u8;
    }
    // A moonpetal is dealt one color under its top, so it has more of that
    // to take in once the light comes.
    for k in wanted(p, Feature.Moonpetal) {
        for i in count { ok[i] = lantern_spot(board, i); }
        let i = pick(r, ok[..count]);
        if i < 0 { break; }
        one_color_under_top(board, i, lantern_at[..]);
        board.bottles[i].body = Body.Moonpetal;
    }
    // Smoke, over the lower layers of flasks with two or more, until the
    // layers asked for are under it; never on a siphon. A lantern's
    // neighbors get theirs first, deep, so its light has something to find.
    var smoke_left = p.smoke;
    for i in lantern_at {
        for j in neighbors(board, i) {
            if smoke_left <= 0 || !smokable(j) { continue; }
            let n: i64 = board.bottles[j].n;
            let k = min(smoke_left, n - 1);
            board.bottles[j].murk = ((1 << k) - 1) as u16;
            smoke_left -= k;
        }
    }
    while smoke_left > 0 {
        for i in count { ok[i] = smokable(i); }
        let i = pick(r, ok[..count]);
        if i < 0 { break; }
        let n: i64 = board.bottles[i].n;
        let k = min(smoke_left, 1 + r.rand_int(n - 1));
        board.bottles[i].murk = ((1 << k) - 1) as u16;
        smoke_left -= k;
    }
    // Each door's key, in a flask in plain play, under one to three layers.
    for d in board.door_count {
        for i in count {
            let b = board.bottles[i];
            ok[i] = in_play(b) && !covered(b) && b.key_color == KeyColor.None && key_depths(b).len > 0;
        }
        let i = pick(r, ok[..count]);
        if i < 0 { break; }
        var b .= board.bottles[i];
        let depths = key_depths(b);
        let k = depths[r.rand_int(depths.len)];
        b.keyed = (1 << k) as u16;
        b.key_color = board.doors[d].color;
    }
    // Braziers, where pours go (an empty flask if one will do), beside
    // something ice or a seal can go on, or a vine can grow over.
    let vine = wanted(p, Feature.Vine) > 0;
    var brazier_at: i64[..MAX_BOTTLES] = [];
    for k in wanted(p, Feature.Brazier) {
        for i in count { near[i] = coverable(i) && board.bottles[i].body != Body.Vow; }
        var empty = false;
        for i in count {
            let b = board.bottles[i];
            ok[i] = b.door < 0 && !covered(b) && b.fixture == Fixture.None && b.n < b.cap && next_to(board, i, near);
            if ok[i] && b.n == 0 && b.body == Body.Plain { empty = true; }
        }
        if empty { for i in count { ok[i] = ok[i] && board.bottles[i].n == 0 && board.bottles[i].body == Body.Plain; } }
        let at = place_fixture(board, r, ok, Fixture.Brazier);
        if at < 0 { break; }
        brazier_at.push(at);
    }
    // Is flask i beside a brazier that has nothing to heat yet?
    fn by_cold_brazier(i: i64) -> bool {
        for j in brazier_at {
            if !are_neighbors(board, i, j) { continue; }
            var warms = false;
            for x in neighbors(board, j) { if heat_target(board.bottles[x].cover) { warms = true; } }
            if !warms { return true; }
        }
        false
    }
    // Ice over something still to sort, for three pours or more: beside a
    // brazier that has nothing to heat, if there is one.
    for k in wanted(p, Feature.Rime) {
        var hot = false;
        for i in count {
            ok[i] = coverable(i) && board.bottles[i].body != Body.Vow;
            near[i] = ok[i] && by_cold_brazier(i);
            if near[i] { hot = true; }
        }
        let i = pick(r, if hot { near[..count] } else { ok[..count] });
        if i < 0 { break; }
        board.bottles[i].cover = Cover.Rime;
        board.bottles[i].thaw = clamp(p.thaw + r.rand_int(4), 3, 12) as u8;
    }
    // Seals, over room the board needs -- a spare, or a flask with space --
    // broken by a color buried everywhere else, so the seal waits on some
    // digging: its own top color when that is buried (it lands inside).
    // Beside a cold brazier first.
    fn sealable(i: i64) -> bool {
        let b = board.bottles[i];
        in_play(b) && !covered(b) && b.key_color == KeyColor.None && b.body == Body.Plain && top(b) != DROP
    }
    for k in wanted(p, Feature.Seal) {
        var hot = false;
        var roomy = false;
        for i in count {
            let b = board.bottles[i];
            ok[i] = sealable(i) && b.n < b.cap;
            near[i] = ok[i] && by_cold_brazier(i);
            if near[i] { hot = true; }
            if ok[i] && b.n <= CAP - 2 { roomy = true; }
        }
        if hot { ok = near; }
        else if roomy { for i in count { ok[i] = ok[i] && board.bottles[i].n <= CAP - 2; } }
        var i = pick(r, ok[..count]);
        if i < 0 {
            // No room anywhere: a full flask (nothing lands when it breaks).
            for j in count {
                ok[j] = sealable(j);
                near[j] = ok[j] && by_cold_brazier(j);
            }
            i = pick(r, near[..count]);
            if i < 0 { i = pick(r, ok[..count]); }
            if i < 0 { break; }
        }
        var keys: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
        var outside: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
        var buried = false;
        for c in 1..colors + 1 {
            if tall_color[c] { continue; }
            var on_top = false;
            for j in count {
                let o = board.bottles[j];
                if j == i || o.cover == Cover.Seal || !has_color(o, liquid[c]) { continue; }
                outside[c] = true;
                if top(o) == liquid[c] { on_top = true; }
            }
            keys[c] = outside[c] && !on_top;
            if keys[c] { buried = true; }
        }
        if !buried { keys = outside; }
        var key = 0;
        let t = top(board.bottles[i]);
        for c in 1..colors + 1 { if keys[c] && liquid[c] == t { key = t; } }
        if key == 0 {
            let c = pick(r, keys[..colors + 1]);
            if c < 0 { break; }
            key = liquid[c];
        }
        var b .= board.bottles[i];
        b.cover = Cover.Seal;
        b.key = key as u8;
    }
    // Curtains, each opened by a color neither it nor another curtain holds.
    for k in wanted(p, Feature.Curtain) {
        for i in count { ok[i] = coverable(i) && board.bottles[i].body == Body.Plain; }
        let i = pick(r, ok[..count]);
        if i < 0 { break; }
        var free: bool[MAX_COLORS + 1] = [false; MAX_COLORS + 1];
        for c in 1..colors + 1 {
            let x = liquid[c];
            free[c] = x != QUICKSILVER || !athanor;
            for j in count {
                let b = board.bottles[j];
                if (j == i || b.cover == Cover.Curtain) && has_color(b, x) { free[c] = false; }
            }
        }
        let c = pick(r, free[..colors + 1]);
        if c < 0 { break; }
        board.bottles[i].cover = Cover.Curtain;
        board.bottles[i].badge = liquid[c] as u8;
    }
    // A creeping vine, next to flasks it can grow over: beside a brazier's
    // neighbors, where there is one, so the heat can burn what it grows.
    if vine {
        for i in count { near[i] = board.bottles[i].door < 0 && !covered(board.bottles[i]); }
        var hot = false;
        for i in count {
            ok[i] = in_play(board.bottles[i]) && !covered(board.bottles[i]) && next_to(board, i, near);
            var by: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
            for j in brazier_at { for x in neighbors(board, j) { by[x] = true; } }
            if ok[i] && next_to(board, i, by) && board.bottles[i].fixture == Fixture.None { hot = true; }
        }
        if hot {
            var by: bool[MAX_BOTTLES] = [false; MAX_BOTTLES];
            for j in brazier_at { for x in neighbors(board, j) { by[x] = true; } }
            for i in count { ok[i] = ok[i] && next_to(board, i, by); }
        }
        let i = place_fixture(board, r, ok, Fixture.VineRoot);
        if i >= 0 { board.bottles[i].spread_every = clamp(p.vine_every, 1, 9) as u8; }
    }
    // A brazier left with nothing to heat (and no vine to grow by it) goes.
    for j in brazier_at {
        var warms = vine;
        for x in neighbors(board, j) { if heat_target(board.bottles[x].cover) { warms = true; } }
        if !warms { board.bottles[j].fixture = Fixture.None; }
    }
    // A catalyst, where it has two things at least to set off.
    var targets = 0;
    for i in count {
        let b = board.bottles[i];
        if b.fixture == Fixture.Lantern || b.body == Body.Hourglass || b.fixture == Fixture.Brazier { targets++; }
    }
    for k in wanted(p, Feature.Catalyst) {
        if targets < 2 { break; }
        for i in count { ok[i] = lantern_spot(board, i); }
        let at = place_fixture(board, r, ok, Fixture.Catalyst);
        if at < 0 { break; }
        one_color_under_top(board, at, lantern_at[..]);
    }
    // The salamander, on a flask it can be poured off, where there is
    // something its heat changes.
    if wanted(p, Feature.Salamander) > 0 {
        var heats = false;
        for i in count { if heat_target(board.bottles[i].cover) || board.bottles[i].fixture == Fixture.VineRoot { heats = true; } }
        for i in count { ok[i] = heats && in_play(board.bottles[i]) && board.bottles[i].n > 0 && !covered(board.bottles[i]); }
        board.salamander = pick(r, ok[..count]);
    }
    settle(board);
    board
}

// Every modifier the recipe asks for is on the board.
fn has_all(board: Board, p: Recipe) -> bool {
    for f in ALL_FEATURES {
        if f == Feature.Murk || f == Feature.Tall { continue; }
        let n = wanted(p, f);
        if n > 0 && feature_count(board, f) < min(n, if f == Feature.Quicksilver || f == Feature.Drop { 1 } else { n }) {
            return false;
        }
    }
    if p.smoke > 0 && !feature_on(board, Feature.Murk) { return false; }
    if p.tall > 0 && feature_count(board, Feature.Tall) < p.tall { return false; }
    true
}

// No bottle may start complete, and the level should not be half done.
fn deal_ok(board: Board) -> bool {
    for i in board.count {
        let b = board.bottles[i];
        if b.done || (b.n == b.cap && is_uniform(b)) { return false; }
    }
    validate(board).len == 0 && !is_won(board)
}

// How far a score is from the band: 0 inside it.
fn band_distance(p: Recipe, score: f64) -> f64 {
    if score < p.band_lo { return p.band_lo - score; }
    if score > p.band_hi { return score - p.band_hi; }
    0.0
}

// Deals tried for a board in the band, and solver positions spent on them;
// after either, the closest valid one is kept.
let BAND_ATTEMPTS = 12;
let BAND_SPEND = 30000;
// Deals tried at all before the plainest fallback.
let MAX_ATTEMPTS = 100;

// What attempt `attempt` deals with, after `spent` solver positions: when
// deals keep failing, ease off: the focus need not be required, then only
// the focus and what it needs stay (and half the smoke), then a color goes.
fn attempt_recipe(p: Recipe, attempt: i64, spent: i64) -> Recipe {
    var q = p;
    if attempt >= 24 || spent >= 40000 { q.focused = false; }
    if attempt >= 48 || spent >= 70000 {
        q.smoke = q.smoke / 2;
        for f in ALL_FEATURES {
            if p.focused && f != p.focus && !needed_by(p.focus, f, p) { want(q, f, 0); }
        }
    }
    if attempt >= 72 || spent >= 100000 {
        q = Recipe { colors: max(3, p.colors - 1), spares: 2, tall: p.tall, tall_rows: p.tall_rows };
    }
    q
}

// Whether modifier `f` in recipe `p` is there for `focus`: heat's
// targets, what a catalyst sets off.
fn needed_by(focus: Feature, f: Feature, p: Recipe) -> bool {
    match focus {
        Brazier, Salamander => f == Feature.Rime || f == Feature.Seal || f == Feature.Vine,
        Catalyst => f == Feature.Lantern || f == Feature.Hourglass || f == Feature.Brazier || f == Feature.Rime,
        _ => false,
    }
}

// The search attempt `attempt` may make: the first few give up early, since
// a deal that is hard to search is more often one that cannot be won, and
// dealing again is cheaper; later ones search fully.
fn attempt_budget(budget: i64, attempt: i64) -> i64 { if attempt < 6 { budget / 3 } else { budget } }

// Generation as a job that runs a slice at a time, so the game can keep
// drawing while it brews. Each attempt deals a board, solves it, checks
// that its modifiers matter, plays the traps, and checks the focus.
enum GenStage { Deal, Solve, Traps, Focus }

struct GenJob {
    recipe: Recipe,
    current: Recipe = Recipe {},    // the recipe this attempt deals with
    seed: u64,
    attempt: i64 = 0,
    stage: GenStage = GenStage.Deal,
    dealt: Board,           // the deal being measured
    m: Measure = Measure {},// its measure, while the focus is checked
    best: GenResult,        // the closest valid deal so far, when has_best
    has_best: bool = false,
    best_distance: f64 = 1e18,
    valid_at: i64 = 0,
    spent: i64 = 0,         // solver positions expanded so far
    done: bool = false,
    result: GenResult,      // once done
    job: MeasureJob,
}

fn gen_begin(p: Recipe, seed: u64) -> GenJob {
    GenJob { recipe: p, seed: seed, dealt: Board { .. }, best: GenResult { board: Board { .. } },
             result: GenResult { board: Board { .. } }, job: MeasureJob { start: Board { .. }, search: Search {} }, .. }
}

// The deal passed every check; it is kept if it is in the band, else
// remembered if it is the closest yet.
fn gen_valid(job: GenJob&) {
    if job.valid_at == 0 { job.valid_at = job.attempt + 1; }
    let dist = band_distance(job.recipe, job.m.score);
    let g = GenResult { board: job.dealt, m: job.m, attempts: job.attempt + 1, valid_at: job.valid_at, in_band: dist == 0.0 };
    if dist == 0.0 {
        job.result = g;
        job.done = true;
        return;
    }
    if dist < job.best_distance {
        job.best = g;
        job.has_best = true;
        job.best_distance = dist;
    }
    gen_next(job);
}

fn gen_next(job: GenJob&) {
    job.attempt++;
    job.stage = GenStage.Deal;
    job.job.search = Search {};
}

// Works on the job for about `nodes` search positions (each deal counts as
// one). True once it is done and `job.result` holds the board.
fn gen_step(job: GenJob&, nodes: i64) -> bool {
    var left = max(1, nodes);
    while !job.done && left > 0 {
        match job.stage {
            Deal => {
                left--;
                if job.has_best && (job.attempt >= BAND_ATTEMPTS || job.spent >= BAND_SPEND) {
                    job.result = job.best;
                    job.result.attempts = job.attempt;
                    job.done = true;
                    break;
                }
                if job.attempt >= MAX_ATTEMPTS {
                    // Practically unreachable: three colors with two spares always solve.
                    var r = rng { job.seed };
                    let board = deal(Recipe { colors: 3, spares: 2 }, r);
                    job.result = GenResult { board: board, attempts: MAX_ATTEMPTS + 1 };
                    job.done = true;
                    break;
                }
                let p = attempt_recipe(job.recipe, job.attempt, job.spent);
                job.current = p;
                var r = rng { job.seed * 0x9E3779B97F4A7C15 + (job.attempt as u64) * 0xD1B54A32D192ED03 + 17 };
                job.dealt = deal(p, r);
                if !deal_ok(job.dealt) || !has_all(job.dealt, p) {
                    gen_next(job);
                    continue;
                }
                job.job = measure_begin(job.dealt, attempt_budget(p.budget, job.attempt));
                job.stage = GenStage.Solve;
            },
            Solve => {
                let before = job.job.spent;
                let over = measure_step(job.job, left);
                let spent = max(1, job.job.spent - before);
                left -= spent;
                job.spent += spent;
                if !over { continue; }
                if !job.job.m.solved {
                    gen_next(job);
                    continue;
                }
                let f, unused = unused_feature(uses_of(job.dealt, job.job.path[..]));
                if unused {
                    gen_next(job);
                    continue;
                }
                // The traps can't bring a deal into the band from above it,
                // nor closer than the best from below by more than they add.
                measure_traps(job.job, TRAP_PLAYOUTS, job.seed ^ (job.attempt as u64 * 0x2545F4914F6CDD1D));
                job.stage = GenStage.Traps;
            },
            Traps => {
                let before = job.job.spent;
                let over = measure_step(job.job, left);
                let spent = max(1, job.job.spent - before);
                left -= spent;
                job.spent += spent;
                if !over { continue; }
                job.m = job.job.m;
                let dist = band_distance(job.recipe, job.m.score);
                if dist > 0.0 && dist >= job.best_distance {
                    gen_next(job);
                    continue;
                }
                let p = job.current;
                if !p.focused || !neutral_exists(p.focus) {
                    gen_valid(job);
                    continue;
                }
                job.job = measure_begin(without_feature(job.dealt, p.focus), attempt_budget(p.budget, job.attempt));
                job.stage = GenStage.Focus;
            },
            Focus => {
                let before = job.job.spent;
                let over = measure_step(job.job, left);
                let spent = max(1, job.job.spent - before);
                left -= spent;
                job.spent += spent;
                if !over { continue; }
                if focus_required(base_score(job.m), job.job.m) { gen_valid(job); } else { gen_next(job); }
            },
        }
    }
    job.done
}

fn generate(p: Recipe, seed: u64) -> GenResult {
    var job = gen_begin(p, seed);
    while !gen_step(job, 1 << 30) {}
    job.result
}
