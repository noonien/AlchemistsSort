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

// A shuffle as a job that runs a slice at a time, as the game wants: it tries
// deal after deal, each searched by the solver, until one can be won.
struct ShuffleJob {
    board: Board,           // the board as it was
    trial: Board,           // the deal being searched; the result, once found
    colors: u8[..MAX_BOTTLES * MAX_CAP],
    r: rng,
    tries: i64 = 0,         // deals left to try
    budget: i64 = 0,
    searching: bool = false,
    done: bool = true,
    found: bool = false,
    search: Search,
}

fn shuffle_begin(board: Board, r: rng, tries: i64, budget: i64) -> ShuffleJob {
    var job = ShuffleJob { board: board, trial: board, colors: [], r: r, tries: tries, budget: budget,
                           done: false, search: Search {}, .. };
    for i in board.count {
        let b = board.bottles[i];
        for k in b.n as i64 { if shuffle_slot(b, k) { job.colors.push(b.seg[k]); } }
    }
    if job.colors.len < 2 { job.done = true; }
    job
}

// Works on the shuffle for about `nodes` search positions (each deal counts
// as one). True once it is done: `job.found` says whether `job.trial` is a
// deal that can be won.
fn shuffle_step(job: ShuffleJob&, nodes: i64) -> bool {
    var left = max(1, nodes);
    while !job.done && left > 0 {
        if job.searching {
            let before = job.search.stats.expanded;
            let over = search_step(job.search, left);
            left -= max(1, job.search.stats.expanded - before);
            if !over { continue; }
            job.searching = false;
            job.found = job.search.stats.solved;
            job.done = job.found || job.tries == 0;
            job.search = Search {};
            continue;
        }
        left--;
        if job.tries == 0 {
            job.done = true;
            break;
        }
        job.tries--;
        shuffle(job.colors, job.r);
        job.trial = job.board;
        var at = 0;
        for i in job.trial.count {
            var b .= job.trial.bottles[i];
            for k in b.n as i64 {
                if shuffle_slot(b, k) {
                    b.seg[k] = job.colors[at];
                    at++;
                }
            }
        }
        // Bottles the deal happened to complete are sealed as usual.
        for i in job.trial.count { let d, l = seal_if_complete(job.trial, i); }
        if is_won(job.trial) { continue; }
        job.search = search_begin(job.trial, job.budget);
        job.searching = true;
    }
    job.done
}

// Re-deals the visible liquid among the same slots, keeping every bottle's
// height, and keeps the first deal the solver can win. False (and the board
// unchanged) when none of `tries` deals could be won.
fn shuffle_board(board: Board&, r: rng&, tries: i64, budget: i64) -> bool {
    var job = shuffle_begin(board, r, tries, budget);
    while !shuffle_step(job, 1 << 30) {}
    r = job.r;
    if job.found { board = job.trial; }
    job.found
}

// A good next move from the solver, or false when it finds no way to win.
fn hint_move(board: Board, budget: i64) -> Move, bool {
    var path: Move[>..] = [];
    let s = solve(board, budget, path);
    if !s.solved || path.len == 0 { return Move { -1, -1 }, false; }
    return path[0], true;
}
