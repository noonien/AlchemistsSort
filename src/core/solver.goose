// A solver for any board, obstacles included: weighted A* over positions,
// with a visited set and a node budget. It sees through "?" segments,
// cloths, corks and boxes -- it is the level designer's check that a board
// can be won, and the hint tool's source of a good next move.

import std;
import dictionary;
import .board;

struct Move { from: i64, to: i64 }

struct SolveNode { board: Board, parent: i32, from: i8, to: i8, g: i32 }

struct SolveStats {
    solved: bool = false,
    expanded: i64 = 0,      // positions taken off the queue
    length: i64 = 0,        // moves in the solution found
}

// How far a position looks from solved: a run boundary costs one, as does
// each hidden segment and each obstacle still standing.
fn heuristic(board: Board) -> i64 {
    var h = 0;
    for i in board.count {
        let b = board.bottles[i];
        if b.n > 0 {
            h += 1;
            for k in 1..b.n as i64 { if b.seg[k] != b.seg[k - 1] { h += 1; } }
            if b.n < CAP { h += 1; }
        }
        h += b.hidden;
        if blocked(b) { h += 2; }
        if b.kind == Kind.Mystery && b.n < CAP { h += 1; }
    }
    max(0, h - board.colors)
}

// An empty bottle anything can be poured into; all of these are alike.
fn plain_empty(b: Bottle) -> bool { b.n == 0 && b.kind != Kind.Mystery && !blocked(b) && !b.done }

// Pours worth trying from `board`, without ones that cannot lead anywhere new.
fn useful_moves(board: Board, out: Move[>..]&) {
    var first_empty = -1;
    for j in board.count {
        if plain_empty(board.bottles[j]) { first_empty = j; break; }
    }
    for i in board.count {
        let src = board.bottles[i];
        if !can_pour_from(src) { continue; }
        let whole = src.hidden == 0 && is_uniform(src);
        for j in board.count {
            if i == j || !can_pour(board, i, j) { continue; }
            let dst = board.bottles[j];
            if plain_empty(dst) {
                if j != first_empty { continue; }   // every empty bottle is the same
                if whole { continue; }               // moving a whole bottle changes nothing
            }
            out.push(Move { i, j });
        }
    }
}

// Searches for a way to win from `start`, giving up after `budget` positions.
// The moves of the solution found go into `path`.
fn solve(start: Board, budget: i64, path: Move[>..]&) -> SolveStats {
    var stats = SolveStats {};
    path.clear();
    if is_won(start) { stats.solved = true; return stats; }
    var nodes: SolveNode[>..] = [];
    var queue: i64[>..<] = [];
    var seen = dictionary<u64, bool> {};
    var moves: Move[>..] = [];
    nodes.push(SolveNode { board: start, parent: -1, from: -1, to: -1, g: 0 });
    seen.insert(board_hash(start), true);
    queue.heap_push(heuristic(start) << 32);
    var goal = -1;
    while queue.len > 0 && goal < 0 {
        let key = queue.heap_pop();
        let at = key & 0xffffffff;
        stats.expanded++;
        if stats.expanded > budget { break; }
        let here = nodes[at].board;
        let g: i64 = nodes[at].g + 1;
        moves.clear();
        useful_moves(here, moves);
        for m in moves {
            var next = here;
            let r = pour(next, m.from, m.to);
            if !r.ok { continue; }
            if !seen.insert(board_hash(next), true) { continue; }
            nodes.push(SolveNode { board: next, parent: at as i32, from: m.from as i8,
                                   to: m.to as i8, g: g as i32 });
            let id = nodes.len - 1;
            if is_won(next) { goal = id; break; }
            queue.heap_push(((g + 4 * heuristic(next)) << 32) | id);
        }
    }
    if goal < 0 { return stats; }
    var at = goal;
    while nodes[at].parent >= 0 {
        path.push(Move { nodes[at].from, nodes[at].to });
        at = nodes[at].parent;
    }
    reverse(path);
    stats.solved = true;
    stats.length = path.len;
    stats
}

fn solvable(start: Board, budget: i64) -> bool {
    var path: Move[>..] = [];
    solve(start, budget, path).solved
}
