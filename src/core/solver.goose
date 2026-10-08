// A solver for any board, every modifier included: weighted A* over positions,
// with a visited set and a node budget. It sees through murk, seals
// and shrouds -- it is the level designer's check that a board
// can be won, and the hint tool's source of a good next move.

import std;
import dictionary;
import .board;

struct Move { from: i64, to: i64 }

// A position the search reached, in 32 bytes. Its board isn't kept: it is
// the parent's with one more pour, and is replayed when needed (board_at).
struct SolveNode {
    hash: u64,
    heap: i64 = 0,      // the open queue's entry in this slot (see Search)
    parent: i32,
    chain: i32 = -1,    // the next node in this one's chain of the seen set
    bucket: i32 = -1,   // the first node of the seen set's chain for this slot
    from: i8,
    to: i8,
}

// Boards of recently expanded positions, kept for replaying their children.
let BOARD_CACHE = 128;

// The most positions one search stores: a few per position it may expand,
// and never more than fit (at 32 bytes each, with room to spare) in one of
// the browser build's 16 MB data stacks.
let NODES_PER_BUDGET = 4;
let MAX_NODES = 400000;

struct SolveStats {
    solved: bool = false,
    exhausted: bool = false,// every reachable position was tried: no win exists
    expanded: i64 = 0,      // positions taken off the queue
    length: i64 = 0,        // moves in the solution found
}

// A search in progress; see search_begin and search_step. One made with
// `Search {}` is finished and found nothing.
struct Search {
    stats: SolveStats = SolveStats {},
    budget: i64 = 0,
    room: i64 = 0,          // the most nodes it may store; when full, it gives up
    done: bool = true,
    goal: i64 = -1,         // the winning node, once found
    queued: i64 = 0,        // the open queue's entries, in nodes[..queued].heap
    buckets: i64 = 0,       // the seen set's chains, headed in nodes[..buckets].bucket
    root: Board = Board { .. },
    cached: i32[BOARD_CACHE] = [-1; BOARD_CACHE],   // node k's board is in slot k % BOARD_CACHE
    depth: i32[BOARD_CACHE] = [0; BOARD_CACHE],     //   and its pours from the root
    cache: Board[BOARD_CACHE] = [Board { .. }; BOARD_CACHE],
    nodes: SolveNode[>..<] = [],    // grow-shrink, so a job can start a new search in place
}

// How far a position looks from solved: a run boundary costs one (the Drop
// fits anywhere and makes none), as does each murky segment, each cover
// still standing, an unfilled vow and quicksilver an athanor has yet to turn.
fn heuristic(board: Board) -> i64 {
    var h = 0;
    let athanor = has_body(board, Body.Athanor);
    for i in board.count {
        let b = board.bottles[i];
        if b.n > 0 {
            h += 1;
            var last = 0;
            for k in b.n as i64 {
                let c: i64 = b.seg[k];
                if c == DROP { continue; }
                if last != 0 && c != last { h += 1; }
                last = c;
                if athanor && c == QUICKSILVER { h += 1; }
            }
            if b.n < b.cap { h += 1; }
        }
        for k in b.n as i64 { if murky(b, k) { h += 1; } }
        if covered(b) { h += 2; }
        if b.body == Body.Vow && b.n < b.cap { h += 1; }
    }
    max(0, h - board.colors)
}

// An empty bottle anything can be poured into with nothing else happening;
// on a board where places don't matter, those of one height are alike.
fn plain_empty(b: Bottle) -> bool {
    b.n == 0 && b.body == Body.Plain && !covered(b) && b.fixture == Fixture.None && b.twin < 0 && !b.done
}

// Something counts pours made anywhere, so a pour that only moves liquid
// around still changes the position: ice, an hourglass, a vine.
fn ticking(board: Board) -> bool {
    for j in board.count {
        let b = board.bottles[j];
        if b.cover == Cover.Rime { return true; }
        if b.body == Body.Hourglass && b.flip_every > 0 && !b.done { return true; }
        if b.fixture == Fixture.VineRoot { return true; }
    }
    false
}

// Pours worth trying from `board`, without ones that cannot lead anywhere new.
// Leaving none out that could matter keeps a search that runs dry a proof
// that the board cannot be won.
fn useful_moves(board: Board, out: Move[>..]&) {
    var first_empty: i64[MAX_CAP + 1] = [-1; MAX_CAP + 1];     // by height
    // Where neighbors matter (heat, light, vines, twins, the salamander), no
    // two empty flasks are alike; where pours are counted, no pour is idle.
    let place = positional(board);
    let live = place || ticking(board);
    for j in board.count {
        let b = board.bottles[j];
        if !place && plain_empty(b) && first_empty[b.cap] < 0 { first_empty[b.cap] = j; }
    }
    for i in board.count {
        let src = board.bottles[i];
        if !can_pour_from(src) { continue; }
        // Moving a whole bottle to an empty one as tall only swaps the two,
        // unless a pour has effects of its own or the source is more than a
        // plain flask (a vow keeps its color, a siphon is a siphon...).
        let whole = !live && src.murk == 0 && is_uniform(src) && src.body == Body.Plain;
        for j in board.count {
            if i == j || !can_pour(board, i, j) { continue; }
            let dst = board.bottles[j];
            if !place && plain_empty(dst) {
                if j != first_empty[dst.cap] { continue; }  // every empty bottle this tall is the same
                if whole && dst.cap == src.cap { continue; } // moving a whole bottle changes nothing
            }
            out.push(Move { i, j });
        }
    }
}

// --- the search, a slice at a time -----------------------------------------------
//
// A Search holds all of the A* state, so the game can run it a few hundred
// positions a frame. A Goose struct owns at most one growable array, so the
// nodes carry the other two tables too: slot k's `heap` is the k-th entry of
// the open queue (which never holds more entries than there are nodes), and
// slot k's `bucket` heads the k-th chain of the set of positions seen (which
// keeps no more chains than nodes).
//
// A node holds no board, which would be twenty times its size: most nodes
// are never expanded. A node's board is its parent's after one pour, and
// every parent was expanded, so expanding one replays the pours from the
// nearest ancestor whose board is still cached, usually just its parent.

// Queue entries are `priority << 32 | node`, all distinct, so the order the
// positions come off depends only on what was pushed.
fn queue_push(s: Search&, key: i64) {
    var i = s.queued;
    s.queued++;
    while i > 0 {
        let p = (i - 1) / 2;
        let up = s.nodes[p].heap;
        if key >= up { break; }
        s.nodes[i].heap = up;
        i = p;
    }
    s.nodes[i].heap = key;
}

fn queue_pop(s: Search&) -> i64 {
    let first = s.nodes[0].heap;
    s.queued--;
    let n = s.queued;
    if n == 0 { return first; }
    let key = s.nodes[n].heap;
    var i = 0;
    loop {
        var c = 2 * i + 1;
        if c >= n { break; }
        if c + 1 < n && s.nodes[c + 1].heap < s.nodes[c].heap { c++; }
        let down = s.nodes[c].heap;
        if key <= down { break; }
        s.nodes[i].heap = down;
        i = c;
    }
    s.nodes[i].heap = key;
    first
}

fn chain_of(s: Search&, h: u64) -> i64 { (hash(h) & ((s.buckets - 1) as u64)) as i64 }

fn seen(s: Search&, h: u64) -> bool {
    var k: i64 = s.nodes[chain_of(s, h)].bucket;
    while k >= 0 {
        if s.nodes[k].hash == h { return true; }
        k = s.nodes[k].chain;
    }
    false
}

fn link(s: Search&, id: i64) {
    let c = chain_of(s, s.nodes[id].hash);
    s.nodes[id].chain = s.nodes[c].bucket;
    s.nodes[c].bucket = id as i32;
}

// Adds a position to the tree and to the set seen. When there are twice as
// many nodes as chains, the chains double and every node is linked anew.
fn add_node(s: Search&, h: u64, parent: i64, m: Move) -> i64 {
    s.nodes.push(SolveNode { hash: h, parent: parent as i32, from: m.from as i8, to: m.to as i8, .. });
    let id = s.nodes.len - 1;
    if s.nodes.len < 2 * s.buckets {
        link(s, id);
        return id;
    }
    s.buckets *= 2;
    for c in s.buckets { s.nodes[c].bucket = -1; }
    for k in s.nodes.len { link(s, k); }
    id
}

// Node `n`'s board and its pours from the root: the nearest ancestor's
// board that is at hand, and the pours from there, each board on the way
// cached for its other children.
fn board_at(s: Search&, n: i64, trail: i64[>..<]&) -> Board, i64 {
    trail.clear();
    var at = n;
    while at > 0 && s.cached[at % BOARD_CACHE] != at {
        trail.push(at);
        at = s.nodes[at].parent;
    }
    var b = if at == 0 { s.root } else { s.cache[at % BOARD_CACHE] };
    var g: i64 = if at == 0 { 0 } else { s.depth[at % BOARD_CACHE] };
    while trail.len > 0 {
        let k = trail.pop();
        let r = pour(b, s.nodes[k].from, s.nodes[k].to);
        g++;
        let slot = k % BOARD_CACHE;
        s.cached[slot] = k as i32;
        s.depth[slot] = g as i32;
        s.cache[slot] = b;
    }
    return b, g;
}

// A search for a way to win from `start` that gives up after `budget`
// positions. Nothing is searched until search_step.
fn search_begin(start: Board, budget: i64) -> Search {
    var s = Search { budget: budget, room: min(MAX_NODES, budget * NODES_PER_BUDGET + 4096), done: false,
                     root: start, .. };
    if is_won(start) {
        s.stats.solved = true;
        s.done = true;
        return s;
    }
    s.buckets = 1;
    let root = add_node(s, board_hash(start), -1, Move { -1, -1 });
    queue_push(s, (heuristic(start) << 32) | root);
    s
}

// Takes up to `nodes` more positions off the queue (at least one). True once
// the search is over: solved, every position tried, or the budget (or the
// room for positions) spent.
fn search_step(s: Search&, nodes: i64) -> bool {
    var moves: Move[>..] = [];
    var trail: i64[>..<] = [];
    var left = max(1, nodes);
    while !s.done && left > 0 && s.queued > 0 {
        left--;
        let at = queue_pop(s) & 0xffffffff;
        s.stats.expanded++;
        if s.stats.expanded > s.budget { break; }
        let here, depth = board_at(s, at, trail);
        let g = depth + 1;
        moves.clear();
        useful_moves(here, moves);
        for m in moves {
            var next = here;
            let r = pour(next, m.from, m.to);
            if !r.ok { continue; }
            let h = board_hash(next);
            if seen(s, h) { continue; }
            if s.nodes.len >= s.room {
                // As good as out of budget: nothing is proven.
                s.done = true;
                break;
            }
            let id = add_node(s, h, at, m);
            if is_won(next) {
                s.goal = id;
                s.stats.solved = true;
                s.stats.length = g;
                s.done = true;
                break;
            }
            queue_push(s, ((g + 4 * heuristic(next)) << 32) | id);
        }
    }
    if !s.done && (s.queued == 0 || s.stats.expanded > s.budget) {
        s.stats.exhausted = s.queued == 0 && s.stats.expanded <= s.budget;
        s.done = true;
    }
    s.done
}

// The moves of the solution found, if any.
fn search_path(s: Search&, path: Move[>..]&) {
    path.clear();
    if s.goal < 0 { return; }
    var at: i64 = s.goal;
    while s.nodes[at].parent >= 0 {
        path.push(Move { s.nodes[at].from, s.nodes[at].to });
        at = s.nodes[at].parent;
    }
    reverse(path);
}

// The first move of the solution found; false when there is none, or the
// board was won to begin with.
fn search_first_move(s: Search&) -> Move, bool {
    if s.goal < 0 { return Move { -1, -1 }, false; }
    var at: i64 = s.goal;
    while s.nodes[at].parent > 0 { at = s.nodes[at].parent; }
    return Move { s.nodes[at].from, s.nodes[at].to }, true;
}

// Searches for a way to win from `start`, giving up after `budget` positions.
// The moves of the solution found go into `path`.
fn solve(start: Board, budget: i64, path: Move[>..]&) -> SolveStats {
    var s = search_begin(start, budget);
    while !search_step(s, budget + 1) {}
    search_path(s, path);
    s.stats
}

// Whether `board` is proven to have no way to win, searching at most
// `budget` positions; false when it can be won or the search ran out first.
fn dead_end(board: Board, budget: i64) -> bool {
    var path: Move[>..] = [];
    solve(board, budget, path).exhausted
}

// Few pours left and no empty bottle to work with: where boards go dead, and
// where proving it takes little search. Cheap enough to ask after every pour.
fn cornered(board: Board) -> bool {
    var pours = 0;
    for i in board.count {
        if plain_empty(board.bottles[i]) { return false; }
        for j in board.count { if can_pour(board, i, j) { pours++; } }
    }
    pours <= 2
}

fn solvable(start: Board, budget: i64) -> bool {
    var path: Move[>..] = [];
    solve(start, budget, path).solved
}
