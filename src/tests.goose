// Unit tests for the rules, the obstacles, the solver, the generator and the
// level format. Run with `nix flake check`, or `goose src/tests.goose`.

import std;
import os;
import core.board;
import core.solver;
import core.generator;
import core.level_io;
import core.tools;
import core.campaign;
import app.shaders;

var failures = 0;
var checks = 0;
var current: u8[..64];

fn check(ok: bool, what: const u8[:]) {
    checks++;
    if !ok {
        failures++;
        print("  FAIL [", current, "] ", what);
    }
}

fn test(name: const u8[:]) {
    current.clear();
    current.append(name[..min(64, name.len)]);
}

// A board from bottles written as level-file letters, bottom to top.
fn board_of(rows: const u8[:][:]) -> Board {
    var board = Board { .. };
    for row in rows {
        var b = Bottle { seg: [0; 8], .. };
        for ch in row {
            let c = color_of_letter(ch);
            assert(c > 0);
            b.seg[b.n] = c as u8;
            b.n++;
        }
        push_bottle(board, b);
    }
    board.colors = color_count(board);
    board
}

fn letters(b: Bottle) -> u8[..4] {
    var s: u8[..4] = [];
    for k in b.n as i64 { s.push(letter_of_color(b.seg[k])); }
    s
}

// --- pour rules ------------------------------------------------------------------

fn test_pour_rules() {
    test("pour moves the top run");
    var b = board_of(["RRGG", "BG", ""]);
    var r = pour(b, 0, 1);
    check(r.ok && r.amount == 2, "two greens fit on a green top");
    check(letters(b.bottles[0]) == "RR" && letters(b.bottles[1]) == "BGGG", "contents after");

    test("pour only what fits");
    b = board_of(["RGGG", "BBG", ""]);
    r = pour(b, 0, 1);
    check(r.ok && r.amount == 1, "one green fits");
    check(letters(b.bottles[0]) == "RGG" && letters(b.bottles[1]) == "BBGG", "the rest stays");

    test("mismatched top is rejected");
    b = board_of(["RRGG", "BBR", ""]);
    r = pour(b, 0, 1);
    check(!r.ok, "green onto red");
    check(letters(b.bottles[0]) == "RRGG" && b.pours == 0, "board unchanged");

    test("full bottle rejects everything");
    b = board_of(["RRGG", "BBGG", ""]);
    check(!pour(b, 0, 1).ok, "full bottle with the same top");

    test("empty accepts any color");
    b = board_of(["RRGB", "", "RGGB"]);
    r = pour(b, 0, 1);
    check(r.ok && r.amount == 1 && letters(b.bottles[1]) == "B", "into an empty bottle");

    test("cannot pour from empty or into itself");
    b = board_of(["", "RRGB"]);
    check(!pour(b, 0, 1).ok, "from empty");
    check(!pour(b, 1, 1).ok, "into itself");
    check(!pour(b, 1, 7).ok && !pour(b, -1, 0).ok, "out of range");

    test("completing seals the bottle");
    b = board_of(["RRR", "GR", "GGG"]);
    r = pour(b, 1, 0);
    check(r.ok && r.completed && b.bottles[0].done, "four reds seal");
    check(!pour(b, 0, 1).ok, "a sealed bottle cannot be poured from");

    test("win and loss");
    b = board_of(["RRRR", "GGGG", ""]);
    settle(b);
    check(is_won(b), "sorted board is won");
    b = board_of(["RGRG", "GRGR"]);
    check(is_lost(b) && !is_won(b), "no legal move is a loss");
    b = board_of(["RRGG", "GGRR", ""]);
    check(!is_lost(b), "a spare bottle means a move");

    test("pour count");
    b = board_of(["RG", "G", ""]);
    pour(b, 0, 1);
    check(b.pours == 1, "a pour counts");
    pour(b, 0, 0);
    check(b.pours == 1, "a rejected pour does not");
}

// --- obstacles --------------------------------------------------------------------

fn test_hidden() {
    test("hidden layers");
    var b = board_of(["RGBB", "B", "", "RGRG"]);
    b.bottles[0].hidden = 3;
    check(top_run(b.bottles[0]) == 1, "only the visible top moves");
    var r = pour(b, 0, 1);
    check(r.ok && r.amount == 1, "one blue moves although two are blue");
    check(b.bottles[0].hidden == 2, "the next segment is exposed");
    r = pour(b, 0, 1);
    check(r.ok && r.amount == 1 && b.bottles[0].hidden == 1, "the second blue, then the green shows");
    r = pour(b, 0, 2);
    check(b.bottles[0].hidden == 0, "the last segment is visible");
}

fn test_split() {
    test("split color reunites");
    var b = board_of(["GGRR", "RRBB", "BBGG", ""]);
    check(pour(b, 0, 3).ok, "red off the top");
    check(pour(b, 2, 0).ok, "green onto green");
    check(b.bottles[0].done, "green complete");
    check(pour(b, 1, 2).ok && pour(b, 1, 3).ok, "blues then reds");
    check(is_won(b), "all reunited");
}

fn test_mystery() {
    test("mystery bottle");
    var b = board_of(["RRGG", "GGRR", "", ""]);
    b.bottles[2].kind = Kind.Mystery;
    settle(b);
    var r = pour(b, 0, 2);
    check(r.ok && b.bottles[2].key == color_of_letter('G'), "takes the first color");
    check(!pour(b, 1, 2).ok, "rejects another color");
    check(pour(b, 0, 3).ok, "reds into the spare");
    check(pour(b, 1, 3).ok && pour(b, 1, 2).ok, "red, then green into the mystery bottle");
    check(is_won(b) && b.bottles[2].done, "won once the mystery bottle is full");

    test("mystery must end full");
    b = board_of(["RRRR", "GGGG", ""]);
    b.bottles[2].kind = Kind.Mystery;
    settle(b);
    check(!is_won(b), "an empty mystery bottle blocks the win");
    check(!can_pour(b, 0, 2), "sealed bottles cannot fill it");
}

fn test_cloak() {
    test("cloaked bottle");
    var b = board_of(["RRRB", "BBBR", "GGGG", "", ""]);
    b.bottles[2].kind = Kind.Cloak;
    b.bottles[2].key = color_of_letter('R') as u8;
    b.bottles[2].active = true;
    settle(b);
    check(contents_hidden(b.bottles[2]) && !b.bottles[2].done, "hidden, not sealed");
    check(!can_pour(b, 2, 3) && !can_pour(b, 0, 2), "inert while cloaked");
    pour(b, 0, 3);
    let r = pour(b, 1, 0);
    check(r.ok && r.completed && r.revealed == 1, "completing red lifts the cloth");
    check(!b.bottles[2].active && b.bottles[2].done, "revealed, and already complete");

    test("cloth waits for its own color");
    b = board_of(["GGGB", "BBB", "RRRR", "", ""]);
    b.bottles[2].kind = Kind.Cloak;
    b.bottles[2].key = color_of_letter('R') as u8;
    b.bottles[2].active = true;
    settle(b);
    pour(b, 0, 1);
    check(b.bottles[1].done && b.bottles[2].active, "completing blue leaves a red cloth");
}

fn test_frozen() {
    test("frozen bottle");
    var b = board_of(["RG", "", "GR", "", "RRGG"]);
    b.bottles[2].kind = Kind.Frozen;
    b.bottles[2].timer = 2;
    b.bottles[2].active = true;
    settle(b);
    check(b.bottles[2].active, "starts frozen");
    check(!can_pour(b, 2, 1) && !can_pour(b, 0, 2), "inert while frozen");
    var r = pour(b, 0, 1);
    check(r.ok && b.bottles[2].timer == 1 && b.bottles[2].active, "one pour off the count");
    r = pour(b, 0, 3);
    check(r.thawed == 1 && !b.bottles[2].active, "thaws on the last pour");
    check(can_pour(b, 2, 3), "pours once thawed");
}

fn test_cork(kind: Kind, name: const u8[:]) {
    test(name);
    var b = board_of(["RRGG", "YY", "BY", "BBYY", "R", "GB"]);
    b.bottles[1].kind = kind;
    b.bottles[1].key = color_of_letter('Y') as u8;
    b.bottles[1].active = true;
    settle(b);
    check(contents_hidden(b.bottles[1]), "contents hidden under it");
    check(!can_pour(b, 1, 4), "cannot pour out of it");
    check(!can_pour(b, 0, 1), "the wrong color is rejected");
    let r = pour(b, 2, 1);
    check(r.ok && r.popped && r.amount == 1, "the key color pops it and lands");
    check(letters(b.bottles[1]) == "YYY" && !b.bottles[1].active, "contents after");
    check(can_pour(b, 1, 3) || can_pour(b, 3, 1), "an ordinary bottle now");

    test(str(name, " pops even without room"));
    b = board_of(["RRYY", "GGBB", "Y", "BGRG", ""]);
    b.bottles[1].kind = kind;
    b.bottles[1].key = color_of_letter('Y') as u8;
    b.bottles[1].active = true;
    settle(b);
    let r2 = pour(b, 2, 1);
    check(r2.ok && r2.popped && r2.amount == 0, "pops, nothing lands");
    check(letters(b.bottles[2]) == "Y", "the yellow stays where it was");
}

fn test_vault_chain() {
    test("chained vaults");
    // The second vault's key, violet, is locked inside the first.
    var b = board_of(["RVV", "RRV", "VYYY", "", "RY"]);
    b.bottles[0].kind = Kind.Vault;
    b.bottles[0].key = color_of_letter('Y') as u8;
    b.bottles[0].active = true;
    b.bottles[1].kind = Kind.Vault;
    b.bottles[1].key = color_of_letter('V') as u8;
    b.bottles[1].active = true;
    settle(b);
    check(validate(b).len == 0, "well formed");
    check(!can_pour(b, 2, 1), "yellow does not open the violet padlock");
    let r = pour(b, 2, 0);
    check(r.popped && r.amount == 0, "yellow opens the first vault, but cannot land on violet");
    check(!b.bottles[0].active && b.bottles[1].active, "first vault open, second still locked");
    let r2 = pour(b, 0, 1);
    check(r2.popped && r2.amount == 1, "violet from the first vault opens the second");
    var path: Move[>..] = [];
    check(solve(b, 20000, path).solved, "the chain can be finished");
}

fn test_curtain() {
    test("curtain");
    var b = board_of(["RRG", "GGRR", "BBBB", "G"]);
    b.bottles[2].kind = Kind.Curtain;
    b.bottles[2].key = 1;
    b.bottles[2].active = true;
    settle(b);
    check(b.bottles[2].active && !on_board(b.bottles[2]), "closed while no bottle is empty");
    check(!can_pour(b, 0, 2), "nothing goes behind a curtain");
    let r = pour(b, 3, 0);
    check(r.ok && r.opened == 1 && !b.bottles[2].active, "an empty bottle opens it");
    check(b.bottles[2].done, "the bottle behind it was complete");
    check(pour(b, 0, 3).ok && pour(b, 1, 0).ok && pour(b, 1, 3).ok, "sort the rest");
    check(is_won(b), "won");
}

fn test_gift() {
    test("gift box");
    var b = board_of(["RRGB", "BG", "", "GRBR"]);
    b.bottles[1].kind = Kind.Gift;
    b.bottles[1].active = true;
    settle(b);
    check(contents_hidden(b.bottles[1]) && !can_pour(b, 1, 2), "wrapped and inert");
    let r = pour(b, 0, 1);
    check(r.ok && r.popped && r.amount == 1, "any color pops it");
    check(letters(b.bottles[1]) == "BGB", "the pour lands on a different top");
    check(!b.bottles[1].active, "unwrapped");
}

fn test_long() {
    test("long flask");
    var b = board_of(["RRGG", "GGRR", "RR", ""]);
    b.bottles[2].cap = 6;
    check(validate(b).len == 0, "a color as tall as a long flask is valid");
    b.bottles[2].cap = 5;
    check(validate(b).len > 0, "but must match its height");
    b.bottles[2].cap = 6;
    settle(b);
    check(is_complete(board_of(["RRRR"]).bottles[0]), "an ordinary flask is complete at four");
    var r = pour(b, 1, 2);
    check(r.ok && r.amount == 2 && b.bottles[2].n == 4 && !b.bottles[2].done, "four is not full in a long flask");
    check(can_pour(b, 2, 3), "it pours like any flask");
    r = pour(b, 0, 1);
    r = pour(b, 0, 2);
    check(r.amount == 2 && b.bottles[2].done && is_won(b), "complete at its height");
    var text: u8[>..] = [];
    write_level(b, LevelInfo { name: [], hint: [] }, text);
    var back = Board { .. };
    var info = LevelInfo { name: [], hint: [] };
    check(parse_level(text, back, info).len == 0 && back.bottles[2].cap == 6, "its height is saved");
    var path: Move[>..] = [];
    var c = board_of(["RRGG", "GGRR", "RR", ""]);
    c.bottles[2].cap = 6;
    settle(c);
    check(solve(c, 20000, path).solved, "the solver fills it");
    c.bottles[2].kind = Kind.Cork;
    c.bottles[2].key = 1;
    c.bottles[2].active = true;
    check(validate(c).len == 0, "and it can carry an obstacle");

    var p = GenParams { colors: 5, long: 1, long_height: 7, cork: 1 };
    let g = generate(p, 7);
    var tall = 0;
    for i in g.board.count { if g.board.bottles[i].cap == 7 { tall++; } }
    check(g.stats.solved && tall == 1 && validate(g.board).len == 0, "generated with a long flask");
}

fn test_undo_snapshot() {
    test("boards copy as values");
    var b = board_of(["RG", "", "GR"]);
    let before = b;
    pour(b, 0, 1);
    check(letters(before.bottles[0]) == "RG" && letters(b.bottles[0]) == "R", "a snapshot is independent");
}

// --- solver and generator -----------------------------------------------------------

fn test_solver() {
    test("solver");
    var b = board_of(["RGBR", "GBRG", "BRGB", "", ""]);
    var path: Move[>..] = [];
    let s = solve(b, 50000, path);
    check(s.solved && path.len > 0, "solves a three-color board");
    var replay = b;
    for m in path { check(pour(replay, m.from, m.to).ok, "every move in the path is legal"); }
    check(is_won(replay), "the path wins");
    let stuck = board_of(["RGRG", "GRGR"]);
    check(!solve(stuck, 1000, path).solved, "a dead board has no solution");
    check(dead_end(stuck, 1000), "and the search proves it");
    check(!dead_end(b, 50000), "a board that can be won is no dead end");
    let pointless = board_of(["RGRG", "GRG"]);
    check(has_move(pointless) && dead_end(pointless, 1000), "a dead end can still have pours");
    check(cornered(pointless) && !cornered(b), "the game only searches when cornered");
    let big = generate(level_spec(60).params, level_spec(60).seed).board;
    check(!dead_end(big, 10), "running out of budget proves nothing");
    // The only way on is a pour that just moves a bottle, to melt the ice.
    var ice = board_of(["RR", "", "RR"]);
    ice.bottles[2].kind = Kind.Frozen;
    ice.bottles[2].timer = 1;
    ice.bottles[2].active = true;
    settle(ice);
    check(solve(ice, 1000, path).solved, "pours that only count down the ice are tried");
}

fn test_generator() {
    test("generator");
    for seed in 1..6 {
        let g = generate(GenParams { colors: 5, empties: 2, partial: 2 }, seed as u64);
        check(g.stats.solved, "generated levels are solvable");
        check(validate(g.board).len == 0, "and well formed");
        check(g.board.colors == 5, "with the colors asked for");
    }
    let a = generate(GenParams { colors: 6, empties: 2 }, 99);
    let b = generate(GenParams { colors: 6, empties: 2 }, 99);
    check(board_hash(a.board) == board_hash(b.board), "the same seed gives the same board");
    var path: Move[>..] = [];
    let p = GenParams { colors: 6, empties: 2, hidden: 2, frozen: 1, cork: 1, gift: 1 };
    let o = generate(p, 7);
    check(o.stats.solved && solve(o.board, 100000, path).solved, "obstacles stay solvable");
    var kinds: bool[8] = [false; 8];
    for i in o.board.count { kinds[kind_index(o.board.bottles[i].kind)] = true; }
    check(kinds[kind_index(Kind.Frozen)] && kinds[kind_index(Kind.Cork)] && kinds[kind_index(Kind.Gift)],
          "the obstacles asked for are there");
    let c = generate(GenParams { colors: 6, empties: 2, curtain: 1 }, 5);
    var has_curtain = false;
    for i in c.board.count { if c.board.bottles[i].kind == Kind.Curtain && c.board.bottles[i].active { has_curtain = true; } }
    check(c.stats.solved && has_curtain, "a curtain level that can be won");
}

// --- tools ------------------------------------------------------------------------

fn test_tools() {
    test("shuffle");
    var b = board_of(["RGBY", "GBYR", "BYRG", "YRGB", "", ""]);
    b.bottles[0].hidden = 2;
    b.bottles[3].kind = Kind.Frozen;
    b.bottles[3].timer = 5;
    b.bottles[3].active = true;
    settle(b);
    let before = b;
    var r = rng { 42 };
    check(shuffle_board(b, r, 30, 20000), "finds a solvable deal");
    check(validate(b).len == 0 && color_count(b) == 4, "the same liquid");
    check(b.bottles[0].seg[0] == before.bottles[0].seg[0] &&
          b.bottles[0].seg[1] == before.bottles[0].seg[1], "hidden layers stay put");
    check(letters(b.bottles[3]) == letters(before.bottles[3]), "a frozen bottle is left alone");
    for i in b.count { check(b.bottles[i].n == before.bottles[i].n, "every height kept"); }
    var path: Move[>..] = [];
    check(solve(b, 20000, path).solved, "and it can be won");

    test("hint");
    let h = board_of(["RGRG", "GRGR", "", ""]);
    let m, ok = hint_move(h, 20000);
    check(ok && can_pour(h, m.from, m.to), "a legal first move");
    let dead = board_of(["RGRG", "GRGR"]);
    let m2, ok2 = hint_move(dead, 2000);
    check(!ok2, "no hint on a dead board");
}

// --- campaign -----------------------------------------------------------------------

fn test_campaign() {
    test("campaign");
    check(level_spec(1).file == "01_first_pour", "level one is the first tutorial");
    for f in ALL_FEATURES {
        let s = level_spec(tutorial_level(f));
        check(s.is_tutorial && s.tutorial == f && s.file.len > 0 && s.difficulty == Difficulty.Normal,
              "tutorial levels");
        check(!introduced(f, tutorial_level(f) - 1), "nothing used before its tutorial");
    }
    check(level_spec(15).difficulty == Difficulty.Hard && level_spec(30).difficulty == Difficulty.SuperHard,
          "tags");
    check(level_spec(23).params.colors <= level_spec(70).params.colors, "colors ramp up");
    for n in 2..13 {
        let p = level_spec(n).params;
        check(p.cork + p.vault + p.gift + p.frozen + p.cloak + p.curtain == 0 || n >= 13,
              "no mechanical obstacle before the mystery tutorial");
    }
    let t0 = clock();
    var worst = 0.0;
    var worst_level = 0;
    for n in 2..61 {
        let spec = level_spec(n);
        if spec.file.len > 0 { continue; }
        let t = clock();
        let g = generate(spec.params, spec.seed);
        let dt = clock() - t;
        if dt > worst { worst = dt; worst_level = n; }
        check(g.stats.solved, str("level ", n, " is solvable"));
        check(g.board.count <= 18, "fits the screen");
    }
    print("  campaign: levels 2-60 generated in ", clock() - t0, "s, slowest ", worst_level,
          " at ", worst, "s");
}

// --- enum tables -------------------------------------------------------------------

fn test_tables() {
    test("enum tables");
    for k, i in ALL_KINDS { check(kind_index(k) == i, "ALL_KINDS is in index order"); }
    for s, i in ALL_SHAPES {
        check(shape_index(s) == i, "ALL_SHAPES is in index order");
        check(find(FRAGMENT_SHADER, str("#define ", shape_define(s), " ", i, "\n")) >= 0,
              str("the shader numbers ", shape_define(s), " ", i));
    }
    for c, i in ALL_ICONS {
        check(icon_index(c) == i, "ALL_ICONS is in index order");
        check(find(FRAGMENT_SHADER, str("#define ", icon_define(c), " ", i, "\n")) >= 0,
              str("the shader numbers ", icon_define(c), " ", i));
    }
}

// --- level format -------------------------------------------------------------------

fn test_level_io() {
    test("level format");
    let text = """
        {
          "name": "Sample",
          "difficulty": "hard",
          "hint": "Try it.",
          "future": { "nested": [1, 2, {"x": "y"}] },
          "bottles": [
            "RRGB",
            { "liquid": "GGBR", "hidden": 3 },
            { "kind": "cork", "liquid": "BB", "key": "B" },
            { "kind": "frozen", "liquid": "RG", "thaw": 4 },
            { "kind": "mystery", "liquid": "" },
            ""
          ]
        }
        """;
    var board = Board { .. };
    var info = LevelInfo { name: [], hint: [] };
    let err = parse_level(text, board, info);
    check(err.len == 0, str("parses: ", err));
    check(info.name == "Sample" && info.difficulty == Difficulty.Hard && info.hint == "Try it.", "header fields");
    check(board.count == 6 && board.colors == 3, "six bottles, three colors");
    check(board.bottles[1].hidden == 3 && board.bottles[2].kind == Kind.Cork, "bottle fields");
    check(board.bottles[3].timer == 4 && board.bottles[3].active, "frozen with its count");
    var out: u8[>..] = [];
    write_level(board, info, out);
    var again = Board { .. };
    var info2 = LevelInfo { name: [], hint: [] };
    check(parse_level(out, again, info2).len == 0, "what it writes reads back");
    check(board_hash(again) == board_hash(board), "the same board");

    test("level format errors");
    check(parse_level("{ \"bottles\": [\"RRRRR\"] }", board, info).len > 0, "five segments");
    check(parse_level("{ \"bottles\": [\"RRG\", \"GGR\"] }", board, info).len > 0, "uneven colors");
    check(parse_level("{ \"bottles\": [\"QQQQ\"] }", board, info).len > 0, "unknown color");
    check(parse_level("{ \"bottles\": [", board, info).len > 0, "truncated");
}

fn check_level_file(path: const u8[:], name: const u8[:]) {
    var text: u8[>..] = [];
    check(read_file(path, text), str("reads ", path));
    var b = Board { .. };
    var info = LevelInfo { name: [], hint: [] };
    let err = parse_level(text, b, info);
    check(err.len == 0, str(name, ": ", err));
    if err.len > 0 { return; }
    check(info.hint.len > 0, str(name, " has a hint"));
    var moves: Move[>..] = [];
    check(solve(b, 200000, moves).solved, str(name, " can be won"));
}

// Every level file shipped in data/levels is well formed and can be won.
fn test_level_files() {
    test("shipped level files");
    var dir: u8[>..] = [];
    if !env("ALCHEMIST_SORT_DATA", dir) || dir.len == 0 { dir.clear(); dir.append("data"); }
    var found = 0;
    for sub in ["tutorial", "examples"] {
        let d = str(dir, "/levels/", sub);
        var names: u8[>..] = [];
        if !list_dir(d, names) { continue; }
        each_split(names, '\n') {
            if ends_with(it, ".json") {
                found++;
                check_level_file(str(d, "/", it), it);
            }
        };
    }
    check(found >= 11, str("found the level files (", found, ") in ", dir));
}

fn main() {
    test_level_files();
    test_pour_rules();
    test_hidden();
    test_split();
    test_mystery();
    test_cloak();
    test_frozen();
    test_cork(Kind.Cork, "corked bottle");
    test_cork(Kind.Vault, "locked vault");
    test_vault_chain();
    test_curtain();
    test_gift();
    test_long();
    test_undo_snapshot();
    test_solver();
    test_generator();
    test_level_io();
    test_tools();
    test_campaign();
    test_tables();
    print(checks - failures, "/", checks, " checks passed");
    if failures > 0 { exit(1); }
}
