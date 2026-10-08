// The player's tools that need more than a pour: shuffle and hint. (Undo,
// restart and the extra bottle are bookkeeping in the game itself.)

import std;
import .board;
import .solver;

// Visible liquid that a shuffle may move: in bottles with no obstacle on
// them, not sealed, not a mystery bottle (whose color is fixed once chosen),
// and above any "?" layers.
fn shuffle_slot(b: Bottle, k: i64) -> bool {
    !b.done && !blocked(b) && b.kind != Kind.Mystery && k >= b.hidden && k < b.n
}

// Re-deals the visible liquid among the same slots, keeping every bottle's
// height, and keeps the first deal the solver can win. False (and the board
// unchanged) when none of `tries` deals could be won.
fn shuffle_board(board: Board&, r: rng&, tries: i64, budget: i64) -> bool {
    var colors: u8[>..] = [];
    for i in board.count {
        let b = board.bottles[i];
        for k in b.n as i64 { if shuffle_slot(b, k) { colors.push(b.seg[k]); } }
    }
    if colors.len < 2 { return false; }
    var path: Move[>..] = [];
    for t in tries {
        shuffle(colors, r);
        var trial = board;
        var at = 0;
        for i in trial.count {
            var b .= trial.bottles[i];
            for k in b.n as i64 {
                if shuffle_slot(b, k) {
                    b.seg[k] = colors[at];
                    at++;
                }
            }
        }
        // Bottles the deal happened to complete are sealed as usual.
        for i in trial.count { let d, l = seal_if_complete(trial, i); }
        if is_won(trial) { continue; }
        if solve(trial, budget, path).solved {
            board = trial;
            return true;
        }
    }
    false
}

// A good next move from the solver, or false when it finds no way to win.
fn hint_move(board: Board, budget: i64) -> Move, bool {
    var path: Move[>..] = [];
    let s = solve(board, budget, path);
    if !s.solved || path.len == 0 { return Move { -1, -1 }, false; }
    return path[0], true;
}
