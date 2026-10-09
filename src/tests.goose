// Unit tests for the rules, every modifier and how they meet, the solver,
// the generator and the shipped levels. Run with `nix flake check`, or
// `goose --include src/c/ogg.h src/tests.goose`.

import std;
import os;
import core.board;
import core.solver;
import core.generator;
import core.levels;
import core.tools;
import core.campaign;
import core.explain;
import core.difficulty;
import core.variation;
import app.shaders;
import app.tracks;
import app.save;

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

// A board from bottles written as level letters, bottom to top.
fn board_of(rows: const u8[:][:]) -> Board {
    var board = Board { .. };
    for row in rows { push_bottle(board, flask(row)); }
    board.colors = color_count(board);
    board
}

// The same, all in one row of the grid, so flask i's neighbors are i - 1 and i + 1.
fn row_of(rows: const u8[:][:]) -> Board {
    var board = board_of(rows);
    board.cols = MAX_BOTTLES;
    place_grid(board);
    board
}

fn letters(b: Bottle) -> u8[..MAX_CAP] {
    var s: u8[..MAX_CAP] = [];
    for k in b.n as i64 { s.push(letter_of_color(b.seg[k])); }
    s
}

fn has_event(r: PourResult, kind: EventKind, bottle: i64) -> bool {
    for e in r.events { if e.kind == kind && e.bottle == bottle { return true; } }
    false
}

// Where the first event of a kind is in the list, or -1.
fn event_at(r: PourResult, kind: EventKind) -> i64 {
    for e, i in r.events { if e.kind == kind { return i; } }
    -1
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
    check(has_event(r, EventKind.Completed, 0), "with an event");
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

fn test_grid() {
    test("the grid and neighbors");
    check(tall_cap(2) == 9 && tall_cap(3) == 14 && rows_of(CAP) == 1 && rows_of(9) == 2 && rows_of(14) == 3,
          "a tall flask's rows");
    var b = board_of(["RRRR", "GGGG", "", "", "", "", "", "", "", ""]);
    settle(b);
    check(b.cols == grid_columns(b) && b.rows * b.cols >= b.count, "settle places the flasks");
    for i in b.count {
        check(flask_at(b, b.row[i], b.col[i]) == i, str("flask ", i, " has a cell of its own"));
    }
    let l = neighbors(b, 0);
    check(l.len == 1 && l[0] == 1 && b.row[0] == 0 && b.col[0] == 0, "the first flask has one neighbor");
    let cols = b.cols;
    let rows = b.rows;
    var cells: i64[MAX_BOTTLES] = [0; MAX_BOTTLES];
    for i in b.count { cells[i] = b.row[i] * 100 + b.col[i]; }
    for k in 6 { add_empty_bottle(b); }
    check(b.cols == cols && b.rows >= rows, "extra flasks never change the columns");
    var kept = true;
    for i in 10 { if b.row[i] * 100 + b.col[i] != cells[i] { kept = false; } }
    check(kept, "nor move the flasks there");
    for i in b.count { check(flask_at(b, b.row[i], b.col[i]) == i, str("extra flask ", i, " has a cell")); }

    test("a tall flask's neighbors");
    // Three ordinary flasks either side of a three-row tall one in the middle.
    var t = board_of(["RRRR", "GGGG", "BBBB", "YYYY", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]);
    var tall = Bottle { cap: tall_cap(3) as u8, .. };
    push_bottle(t, tall);
    t.cols = 3;
    settle(t);
    let ti = t.count - 1;
    check(t.col[ti] == 1 && t.row[ti] == 0 && t.rows >= 3, "it stands in the middle column from the top");
    let around = neighbors(t, ti);
    check(around.len == 6, str("it has a neighbor either side on each of its rows: ", around.len));
    for j in around { check(are_neighbors(t, j, ti), "and is theirs"); }
    check(!are_neighbors(t, 0, 2), "the flasks either side of it are not neighbors");
    let corner = neighbors(t, 0);
    check(corner.len == 1 && corner[0] == ti, "the flask beside it has only it");

    test("grid columns");
    var small = board_of(["RRGB", "GGBR", "BBRG", "", ""]);
    settle(small);
    check(small.cols == 5 && small.rows == 1, str("five flasks stand in a row: ", small.cols));
    var many = board_of(["RRRR", "GGGG", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]);
    settle(many);
    check(many.cols >= 4 && many.rows >= 3, "many flasks take several rows");
}

// --- the chapter 1 modifiers --------------------------------------------------------

fn test_murk() {
    test("murk");
    var b = board_of(["RGBB", "B", "", "RGRG"]);
    b.bottles[0].murk = murk_below(3);
    check(top_run(b.bottles[0]) == 1, "only the visible top moves");
    var r = pour(b, 0, 1);
    check(r.ok && r.amount == 1, "one blue moves although two are blue");
    check(b.bottles[0].murk == 3 && has_event(r, EventKind.MurkCleared, 0), "the next segment clears");
    r = pour(b, 0, 1);
    check(r.ok && r.amount == 1 && b.bottles[0].murk == 1, "the second blue, then the green shows");
    r = pour(b, 0, 2);
    check(b.bottles[0].murk == 0, "the last segment is visible");
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

fn test_vow() {
    test("vow flask");
    var b = board_of(["RRGG", "GGRR", "", ""]);
    b.bottles[2].body = Body.Vow;
    settle(b);
    var r = pour(b, 0, 2);
    check(r.ok && b.bottles[2].vow == color_of_letter('G'), "takes the first color");
    check(has_event(r, EventKind.Vowed, 2), "with an event");
    check(!pour(b, 1, 2).ok, "rejects another color");
    check(pour(b, 0, 3).ok, "reds into the spare");
    check(pour(b, 1, 3).ok, "red into the spare");
    r = pour(b, 1, 2);
    check(r.ok && !has_event(r, EventKind.Vowed, 2), "green into the vow flask, already vowed");
    check(is_won(b) && b.bottles[2].done, "won once the vow flask is full");

    test("a vow need not be used");
    b = board_of(["RRRR", "GGGG", ""]);
    b.bottles[2].body = Body.Vow;
    settle(b);
    check(is_won(b) && !is_lost(b), "an empty vow flask at the end is a win");
    check(!can_pour(b, 0, 2), "sealed bottles cannot fill it");
    b = board_of(["RRRR", "GG", "GG"]);
    b.bottles[2].body = Body.Vow;
    settle(b);
    check(!is_won(b), "a vow flask partly filled is not done");
    check(pour(b, 1, 2).ok && is_won(b), "until it is full");

    test("the Drop does not set a vow");
    b = board_of(["G*", "", "GGG"]);
    b.bottles[1].body = Body.Vow;
    settle(b);
    check(pour(b, 0, 1).ok && b.bottles[1].vow == 0, "the Drop goes in, no vow yet");
    check(pour(b, 0, 1).ok && b.bottles[1].vow == color_of_letter('G'), "then green sets it");
}

fn test_seal() {
    test("seal");
    var b = board_of(["RRGG", "YY", "BY", "BBYY", "R", "GB"]);
    b.bottles[1].cover = Cover.Seal;
    b.bottles[1].key = color_of_letter('Y') as u8;
    settle(b);
    check(contents_hidden(b.bottles[1]), "contents hidden under it");
    check(!can_pour(b, 1, 4), "cannot pour out of it");
    check(!can_pour(b, 0, 1), "the wrong color is rejected");
    let r = pour(b, 2, 1);
    check(r.ok && r.popped && r.amount == 1 && has_event(r, EventKind.SealBroken, 1), "the key breaks it and lands");
    check(letters(b.bottles[1]) == "YYY" && !covered(b.bottles[1]), "contents after");

    test("seal breaks even without room");
    b = board_of(["RRYY", "GGBB", "Y", "BGRG", ""]);
    b.bottles[1].cover = Cover.Seal;
    b.bottles[1].key = color_of_letter('Y') as u8;
    settle(b);
    let r2 = pour(b, 2, 1);
    check(r2.ok && r2.popped && r2.amount == 0, "breaks, nothing lands");
    check(letters(b.bottles[2]) == "Y", "the yellow stays where it was");

    test("the Drop breaks any seal");
    b = board_of(["RR*", "GGB", ""]);
    b.bottles[1].cover = Cover.Seal;
    b.bottles[1].key = color_of_letter('Y') as u8;
    let r3 = pour(b, 0, 1);
    check(r3.ok && r3.popped && r3.amount == 1 && letters(b.bottles[1]) == "GGB*", "and lands on anything");
}

fn test_tall() {
    test("tall flask");
    var b = board_of(["RRGG", "GGRR", "RR", ""]);
    b.bottles[2].cap = 6;
    check(validate(b).len == 0, "a color as tall as a tall flask is valid");
    b.bottles[2].cap = 5;
    check(validate(b).len > 0, "but must match its height");
    b.bottles[2].cap = 6;
    settle(b);
    check(is_complete(board_of(["RRRR"]).bottles[0]), "an ordinary flask is complete at four");
    var r = pour(b, 1, 2);
    check(r.ok && r.amount == 2 && b.bottles[2].n == 4 && !b.bottles[2].done, "four is not full in a tall flask");
    check(!can_pour_from(b.bottles[2]) && !can_pour(b, 2, 3), "nothing comes out of it");
    r = pour(b, 0, 1);
    r = pour(b, 0, 2);
    check(r.amount == 2 && b.bottles[2].done && is_won(b), "complete at its height");
    var path: Move[>..] = [];
    var c = board_of(["RRGG", "GGRR", "RR", ""]);
    c.bottles[2].cap = 6;
    settle(c);
    check(solve(c, 20000, path).solved, "the solver fills it");
    c.bottles[2].cover = Cover.Seal;
    c.bottles[2].key = 1;
    check(validate(c).len == 0, "and it can carry a cover");

    test("a tall flask holds only its color");
    fn tall_board(tall: const u8[:]) -> Board {
        var x = board_of(["RRGG", "GGRR", tall, "", "BBBB"]);
        x.bottles[2].cap = 6;
        x
    }
    check(validate(tall_board("RR")).len == 0, "its own color");
    check(validate(tall_board("RG")).len > 0, "no other color, which could never leave");
    check(validate(tall_board("")).len > 0, "it starts with some of its color");
    var m = tall_board("RR");
    m.bottles[2].murk = 1;
    check(validate(m).len > 0, "no smoke");
    m = tall_board("RR");
    m.bottles[2] = siphon(m.bottles[2]);
    check(validate(m).len > 0, "not a siphon");
    m = tall_board("RR");
    m.bottles[2] = hourglass(m.bottles[2], 3);
    check(validate(m).len > 0, "nor an hourglass");
    m = tall_board("RR");
    m.bottles[2] = seal(m.bottles[2], 'G');
    check(validate(m).len == 0, "a seal over it is fine");
    var o = board_of(["RRGQ", "GGRQ", "RRR", "QQ", "G", ""]);
    o.bottles[2].cap = 6;
    settle(o);
    check(validate(o).len == 0 && !can_pour(o, 3, 2) && can_pour(o, 3, 5), "quicksilver doesn't sink into another color's");
    var q = board_of(["QQ", "GGGG", "QQ", "", "QQQQQ"]);
    q.bottles[4].cap = 9;
    settle(q);
    check(validate(q).len == 0 && can_pour(q, 0, 4), "but quicksilver can be its color");
    var dr = board_of(["RRR*", "GGGG", "RR", ""]);
    dr.bottles[2].cap = 6;
    check(validate(dr).len > 0, "the Drop never goes in, so its color isn't the short one");
    var dd = board_of(["RRRR", "GG*", "G", "RR", ""]);
    dd.bottles[3].cap = 6;
    settle(dd);
    check(validate(dd).len == 0 && !can_pour(dd, 1, 3) && !dd.bottles[0].done, "and the Drop isn't taken");

    test("a tall flask's color in an ordinary flask");
    var d = board_of(["RRR", "GGGR", "G", ""]);
    push_bottle(d, tall_flask('R', 2));
    d.colors = color_count(d);
    settle(d);
    check(validate(d).len == 0 && d.bottles[4].cap == 9, "nine reds for a two-row flask");
    r = pour(d, 1, 0);
    check(r.ok && d.bottles[0].n == 4 && !d.bottles[0].done && !r.completed, "four reds are not done while the tall flask needs more");
    check(can_pour(d, 0, 4) && !can_pour(d, 1, 4), "and pour on into it, and nothing else does");
    check(solve(d, 20000, path).solved, "the solver fills it");
}

// --- chapter 2: rime, braziers, quicksilver -------------------------------------------

fn test_rime() {
    test("rime");
    var b = board_of(["RG", "", "GR", "", "RRGG"]);
    b.bottles[2].cover = Cover.Rime;
    b.bottles[2].thaw = 2;
    settle(b);
    check(covered(b.bottles[2]), "starts frozen");
    check(!can_pour(b, 2, 1) && !can_pour(b, 0, 2), "inert while frozen");
    var r = pour(b, 0, 1);
    check(r.ok && b.bottles[2].thaw == 1 && covered(b.bottles[2]), "one pour off the count");
    r = pour(b, 0, 3);
    check(r.thawed == 1 && !covered(b.bottles[2]) && has_event(r, EventKind.Thawed, 2), "thaws on the last pour");
    check(can_pour(b, 2, 3), "pours once thawed");
}

fn test_heat() {
    test("brazier heat");
    // A seal, the brazier, then ice, all neighbors.
    var b = row_of(["BB", "", "GG", "", "RR"]);
    b.bottles[0].cover = Cover.Seal;
    b.bottles[0].key = color_of_letter('Y') as u8;
    b.bottles[1].fixture = Fixture.Brazier;
    b.bottles[2].cover = Cover.Rime;
    b.bottles[2].thaw = 6;
    var r = pour(b, 4, 1);
    check(r.ok && b.bottles[2].thaw == 4, "the pour and the heat both melt the ice");
    check(b.bottles[0].cover == Cover.Seal && b.bottles[0].soft == 1, "the seal softens");
    check(has_event(r, EventKind.HeatPulse, 0) && has_event(r, EventKind.SealSoftened, 0), "events");
    r = pour(b, 1, 3);
    check(b.bottles[2].thaw == 3 && b.bottles[0].soft == 1, "pouring out of a brazier sends no heat");
    r = pour(b, 3, 1);
    check(!covered(b.bottles[0]) && b.bottles[0].soft == 0 && has_event(r, EventKind.SealBroken, 0),
          "the second pulse breaks the seal");
    check(letters(b.bottles[0]) == "BB", "with nothing landing in it");
    check(b.bottles[2].thaw == 1, "ice: one per pour and one per pulse");
    r = pour(b, 1, 3);
    check(!covered(b.bottles[2]) && r.thawed == 1, "and gone at zero");

    test("heat burns vine tendrils, not the root");
    b = row_of(["R", "", "B", "RR"]);
    b.bottles[0].cover = Cover.Vine;
    b.bottles[1].fixture = Fixture.Brazier;
    b.bottles[2].fixture = Fixture.VineRoot;
    b.bottles[2].spread_every = 9;
    r = pour(b, 3, 1);
    check(!covered(b.bottles[0]) && has_event(r, EventKind.TendrilBurned, 0), "the tendril burns");
    check(b.bottles[2].fixture == Fixture.VineRoot, "the root stands");
}

fn test_quicksilver() {
    test("quicksilver sinks");
    var b = board_of(["Q", "RG", "", "QQ", "R"]);
    b.bottles[1].murk = 1;
    check(can_pour(b, 0, 1), "goes onto any top");
    var r = pour(b, 0, 1);
    check(r.ok && letters(b.bottles[1]) == "QRG", "below everything");
    check(b.bottles[1].murk == 2, "the murk moves up with the red, the silver is in view");
    r = pour(b, 3, 1);
    check(r.amount == 1 && letters(b.bottles[1]) == "QQRG", "above other quicksilver");
    check(!can_pour(b, 4, 3), "other liquid still needs a matching top");
    check(is_complete(flask("QQQQ")), "a flask of quicksilver is complete");

    test("siphon");
    b = board_of(["RRGB", "", "QRR", "B"]);
    b.bottles[0].body = Body.Siphon;
    check(pour_color(b.bottles[0]) == color_of_letter('R') && pour_run(b.bottles[0]) == 2, "pours its bottom run");
    r = pour(b, 0, 1);
    check(r.amount == 2 && letters(b.bottles[0]) == "GB" && letters(b.bottles[1]) == "RR", "from the tap");
    check(pour(b, 3, 0).ok && letters(b.bottles[0]) == "GBB", "and takes in on top");

    test("quicksilver into a siphon comes out first");
    b = board_of(["Q", "RRG", ""]);
    b.bottles[1].body = Body.Siphon;
    pour(b, 0, 1);
    check(letters(b.bottles[1]) == "QRRG", "sinks to the tap");
    r = pour(b, 1, 2);
    check(r.color == QUICKSILVER && letters(b.bottles[2]) == "Q" && letters(b.bottles[1]) == "RRG", "out first");

    test("athanor");
    b = board_of(["QQ", "", "UU", "R", "Q"]);
    b.bottles[1].body = Body.Athanor;
    r = pour(b, 0, 1);
    check(r.amount == 2 && letters(b.bottles[1]) == "UU" && has_event(r, EventKind.Transmuted, 1), "turns into gold");
    check(pour(b, 2, 1).ok && b.bottles[1].done, "gold on gold completes it");
    b = board_of(["Q", "R", "QQUU"]);
    b.bottles[1].body = Body.Athanor;
    check(!can_pour(b, 0, 1), "no quicksilver on another color");
    check(validate(b).len > 0, "an athanor level's quicksilver and gold make one set");
    var w = board_of(["QQQQ", "UUUU", ""]);
    w.bottles[2].body = Body.Athanor;
    settle(w);
    check(!w.bottles[0].done && !is_won(w), "unturned quicksilver never wins with an athanor");
}

// --- chapter 3: keys, doors and curtains -----------------------------------------------

// A board of these flasks, its doors numbered as a level's are, settled.
fn doors_board(bottles: const Bottle[:]) -> Board {
    var b = level(1, "test", Difficulty.Normal, "test", bottles).board;
    settle(b);
    b
}

fn has_door_event(r: PourResult, kind: EventKind, door: i64) -> bool {
    for e in r.events { if e.kind == kind && e.door == door { return true; } }
    false
}

fn test_keys() {
    let brass = KeyColor.Brass;
    let silver = KeyColor.Silver;
    test("a key comes free on top and opens its door");
    var b = doors_board([flask("GRRB").key_at(1, brass), flask("B"), flask("G").behind_door(brass),
                         flask("").behind_door(brass), flask("RR")]);
    check(b.door_count == 1 && b.doors[0].color == brass && !b.doors[0].open, "one brass door, shut");
    check(b.bottles[2].behind && b.bottles[3].behind && !b.bottles[0].behind, "its flasks are behind it");
    check(b.row[2] == b.row[3] && b.col[3] == b.col[2] + 1, "side by side in one row");
    check(!can_pour(b, 1, 3) && !can_pour(b, 2, 1) && !can_pour_from(b.bottles[2]), "shut: nothing in or out");
    check(contents_hidden(b.bottles[2]), "and out of sight");
    var r = pour(b, 4, 0);
    check(!r.ok, "the key's flask pours like any other");
    r = pour(b, 0, 1);
    check(r.ok && b.bottles[0].key_color == KeyColor.None && b.bottles[0].keyed == 0, "the key is free");
    check(has_door_event(r, EventKind.KeyFreed, 0) && has_event(r, EventKind.KeyFreed, 0), "with an event");
    check(has_door_event(r, EventKind.DoorOpened, 0) && has_event(r, EventKind.DoorOpened, 2) &&
          event_at(r, EventKind.KeyFreed) < event_at(r, EventKind.DoorOpened), "then the door opens");
    check(b.doors[0].open && !b.bottles[2].behind && !b.bottles[3].behind, "for good");
    check(can_pour(b, 4, 0) && can_pour(b, 2, 3), "and its flasks join the board");

    test("a key's whole layer must be on top");
    b = doors_board([flask("RRRB").key_at(0, brass), flask("B"), flask("").behind_door(brass), flask("").behind_door(brass)]);
    check(layers_over_key(b.bottles[0]) == 1, "one layer over it");
    r = pour(b, 0, 1);
    check(b.doors[0].open, "the run it sits low in is the top layer now");

    test("smoke hides a key");
    b = doors_board([flask("GRRB").key_at(1, brass).under_murk(3), flask("B"), flask(""), flask("").behind_door(brass),
                     flask("").behind_door(brass)]);
    pour(b, 0, 1);
    check(!b.doors[0].open && b.bottles[0].key_color == brass, "a key under smoke stays put");
    r = pour(b, 0, 2);
    check(r.amount == 1 && b.doors[0].open, "free once its layer clears on top");

    test("the key moves with its layer");
    b = doors_board([flask("RGB").key_at(0, brass), flask("Q"), flask("").behind_door(brass), flask("").behind_door(brass)]);
    pour(b, 1, 0);
    check(letters(b.bottles[0]) == "QRGB" && key_segment(b.bottles[0]) == 1, "quicksilver sinks under it, lifting it");
    check(!b.doors[0].open, "still buried");
    b = doors_board([flask("RGGB").key_at(0, brass).hourglass(1), flask("Y"), flask(""), flask("").behind_door(brass),
                     flask("").behind_door(brass)]);
    r = pour(b, 1, 2);
    check(has_event(r, EventKind.Flipped, 0) && event_at(r, EventKind.Flipped) < event_at(r, EventKind.KeyFreed) &&
          b.doors[0].open, "a flip brings it to the top");
    b = doors_board([flask("RGB").key_at(0, brass).siphon(), flask(""), flask("").behind_door(brass), flask("").behind_door(brass)]);
    r = pour(b, 0, 1);
    check(r.ok && letters(b.bottles[1]) == "R" && b.doors[0].open, "a siphon's tap lets it out, which frees it");
    b = doors_board([flask("RGB").key_at(1, brass).siphon(), flask(""), flask("").behind_door(brass), flask("").behind_door(brass)]);
    pour(b, 0, 1);
    check(key_segment(b.bottles[0]) == 0 && !b.doors[0].open, "the tap shifts it down");

    test("behind a shut door nothing reaches");
    b = doors_board([flask("GRRB").key_at(1, brass), flask("").brazier(), flask("RG").rime(3).behind_door(brass),
                     flask("GB").behind_door(brass), flask("B")]);
    b.cols = MAX_BOTTLES;
    place_grid(b);
    pour(b, 4, 1);
    check(b.bottles[2].cover == Cover.Rime && b.bottles[2].thaw == 3, "no heat, and no pours counted");
    check(!has_move(doors_board([flask("RG").key_at(0, brass), flask("GR"), flask("").behind_door(brass),
                                 flask("").behind_door(brass)])), "its empty flasks are no move");

    test("liquid behind a shut door blocks the win");
    b = doors_board([flask("RRRR").key_at(0, brass), flask("G").behind_door(brass), flask("").behind_door(brass)]);
    check(b.doors[0].open && !b.bottles[1].behind, "a key on top at the start opens its door at once");
    b = board_of(["RRRR", "", ""]);
    b.doors[0] = Door { color: brass };
    b.door_count = 1;
    b.bottles[1].door = 0;
    b.bottles[2].door = 0;
    settle(b);
    check(b.bottles[1].behind && is_won(b), "empty flasks behind it don't");
    b.bottles[1] = flask("G");
    b.bottles[1].door = 0;
    b.bottles[1].behind = true;
    check(!is_won(b), "liquid does");

    test("a curtain opens when its color is completed");
    b = row_of(["RRR", "R", "GGBB", "", "BBGG"]);
    b.bottles[2] = flask("GGBB").curtain('R');
    settle(b);
    check(!can_pour_from(b.bottles[2]) && !can_pour(b, 3, 2) && contents_hidden(b.bottles[2]), "hidden and shut");
    r = pour(b, 1, 0);
    check(b.bottles[0].done && b.bottles[2].cover == Cover.None && has_event(r, EventKind.CurtainOpened, 2), "it opens");
    check(event_at(r, EventKind.Completed) < event_at(r, EventKind.CurtainOpened), "after the completion");
    b = board_of(["RRRR", "GG", "GG"]);
    b.bottles[1] = flask("GG").curtain('R');
    settle(b);
    check(b.bottles[1].cover == Cover.None, "settle opens one whose color starts complete");
    b = board_of(["GGGG", "BB", "BB"]);
    b.bottles[0] = flask("GGGG").curtain('B');
    settle(b);
    check(!is_won(b) && !b.bottles[0].done, "liquid behind a curtain isn't sorted yet");

    test("keys, doors and curtains are validated");
    fn bad(bottles: const Bottle[:], what: const u8[:]) {
        var x = level(1, "test", Difficulty.Normal, "test", bottles).board;
        check(validate(x).len > 0, what);
    }
    fn good(bottles: const Bottle[:], what: const u8[:]) {
        var x = level(1, "test", Difficulty.Normal, "test", bottles).board;
        let err = validate(x);
        check(err.len == 0, str(what, ": ", err));
    }
    good([flask("RRGG").key_at(1, brass), flask("GGRR"), flask("").behind_door(brass), flask("").behind_door(brass)], "a key and its door");
    bad([flask("RRGG").key_at(2, brass), flask("GGRR"), flask("").behind_door(brass), flask("").behind_door(brass)], "a key on top");
    bad([flask("RRGG").key_at(1, brass), flask("GGRR"), flask(""), flask("")], "a key with no door");
    bad([flask("RRGG"), flask("GGRR"), flask("").behind_door(brass), flask("").behind_door(brass)], "a door with no key");
    bad([flask("RRGG").key_at(1, brass), flask("GGRR").key_at(1, brass), flask("").behind_door(brass),
         flask("").behind_door(brass)], "two keys for one door");
    bad([flask("RRGG").key_at(1, brass), flask("GGRR"), flask("").behind_door(brass), flask("")], "a door before one flask");
    bad([flask("RRGG").key_at(1, brass), flask("").behind_door(brass), flask(""), flask("").behind_door(brass)],
        "a door's flasks side by side");
    bad([flask("RRGG").key_at(1, brass), flask("GGRR"), flask("").behind_door(brass), flask("").behind_door(brass),
         flask("").behind_door(brass), flask("").behind_door(brass)], "at most three behind a door");
    bad([flask("RRGG").key_at(1, brass).behind_door(brass), flask("GGRR").behind_door(brass), flask(""), flask("")],
        "a key behind its own door");
    bad([flask("RRGG").key_at(1, brass), flask("GGRR"), tall_flask('B', 2).behind_door(brass), flask("BBBB").behind_door(brass)],
        "no tall flask behind a door");
    good([flask("RRGG").key_at(1, brass).behind_door(silver), flask("").behind_door(silver), flask("GGRR").key_at(1, silver),
          flask("").behind_door(brass), flask("").behind_door(brass)], "a key behind another door");
    bad([flask("RRGG").key_at(1, brass).behind_door(silver), flask("GGRR").behind_door(silver),
         flask("BBRR").key_at(1, silver).behind_door(brass), flask("RRBB").behind_door(brass), flask("BG"), flask("BG")],
        "keys locked behind each other's doors");
    good([flask("RRGG"), flask("GGRR").curtain('B'), flask("BB"), flask("BB")], "a curtain");
    bad([flask("RRGG"), flask("GGRB").curtain('B'), flask("BBB"), flask("R")], "a curtain hiding some of its color");
    bad([flask("RRGG"), flask("GGRR").curtain('Y'), flask("")], "a curtain's color on the board");
    bad([flask("RRGG").curtain('B'), flask("GGRR"), flask("BBYY").curtain('R'), flask("YYBB")], "curtains waiting on each other");
    var x = level(1, "test", Difficulty.Normal, "test", [flask("RRGG").key_at(1, brass), flask("GGRR"), flask("").behind_door(brass),
                                                         flask("").behind_door(brass)]).board;
    x.salamander = 2;
    check(validate(x).len > 0, "no salamander behind a door");

    test("the solver opens doors and curtains");
    var path: Move[>..] = [];
    b = doors_board([flask("RRGB").key_at(1, brass), flask("GBRB"), flask("BGG").key_at(0, silver), flask(""),
                     flask("R").behind_door(brass), flask("").behind_door(brass), flask("").behind_door(silver),
                     flask("").behind_door(silver)]);
    check(validate(b).len == 0 && solve(b, 100000, path).solved, "two doors");
    b = doors_board([flask("RRGB").key_at(1, brass), flask("GBRB"), flask("YRBG"), flask(""), flask(""),
                     flask("YG").curtain('B').behind_door(brass), flask("YY").behind_door(brass)]);
    check(validate(b).len == 0 && solve(b, 100000, path).solved, "a curtain behind a door");

    test("the grid keeps a door's flasks together");
    b = doors_board([flask("RRGG").key_at(1, brass), flask("GGRR"), flask("").behind_door(brass), flask("").behind_door(brass),
                     flask(""), flask("")]);
    b.cols = 3;
    place_grid(b);
    check(b.row[2] == b.row[3] && b.col[3] == b.col[2] + 1 && validate(b).len == 0, "never split across rows");
}

// --- chapter 4: lanterns, shrouds, hourglasses -------------------------------------------

fn test_light() {
    test("lantern lights, shroud lifts, murk clears");
    var b = row_of(["RRRB", "BBB", "GGGG", "R", ""]);
    b.bottles[0].murk = murk_below(2);
    b.bottles[1].fixture = Fixture.Lantern;
    b.bottles[2].cover = Cover.Shroud;
    settle(b);
    check(validate(b).len == 0, "a shroud next to a lantern");
    check(contents_hidden(b.bottles[2]) && !b.bottles[2].done, "hidden, not sealed");
    check(!can_pour(b, 2, 3) && !can_pour(b, 0, 2), "inert while shrouded");
    let r = pour(b, 0, 1);
    check(r.completed && b.bottles[1].lit && has_event(r, EventKind.Lit, 1), "completing it lights the lantern");
    check(r.revealed == 1 && !covered(b.bottles[2]) && b.bottles[2].done, "the shroud lifts on a complete flask");
    check(b.bottles[0].murk == 0, "the murk next door clears");
    check(event_at(r, EventKind.Lit) < event_at(r, EventKind.ShroudLifted), "light first, then what it reaches");

    test("a shroud needs a lantern");
    var v = row_of(["RRRR", "GGGG", "", ""]);
    v.bottles[2].cover = Cover.Shroud;
    check(validate(v).len > 0, "none next to it");

    test("moonpetal");
    b = row_of(["RRR", "R", "BBB", "B", ""]);
    b.bottles[1].body = Body.Moonpetal;
    b.bottles[2].fixture = Fixture.Lantern;
    settle(b);
    check(!can_pour(b, 0, 1) && !can_pour(b, 4, 1), "takes nothing in the dark");
    check(can_pour(b, 1, 0), "but pours out");
    pour(b, 3, 2);
    check(b.bottles[2].lit && can_pour(b, 0, 1), "takes liquid once a lantern is lit");
}

fn test_hourglass() {
    test("hourglass flips with its murk");
    var b = board_of(["RRGB", "Y", "", "YY"]);
    b.bottles[0].body = Body.Hourglass;
    b.bottles[0].flip_every = 2;
    b.bottles[0].murk = murk_below(3);
    settle(b);
    var r = pour(b, 1, 2);
    check(letters(b.bottles[0]) == "RRGB" && b.bottles[0].flip_count == 1, "counts a pour");
    r = pour(b, 3, 2);
    check(has_event(r, EventKind.Flipped, 0) && letters(b.bottles[0]) == "BGRR", "turns over");
    check(b.bottles[0].murk == 6 && b.bottles[0].flip_count == 0, "murk turns with it; the new top clears");

    test("hourglass with quicksilver");
    b = board_of(["QRGB", "Y", "", "YY"]);
    b.bottles[0].body = Body.Hourglass;
    b.bottles[0].flip_every = 1;
    pour(b, 1, 2);
    check(letters(b.bottles[0]) == "QBGR", "the silver runs back down");

    test("a covered hourglass waits");
    b = board_of(["RRGB", "Y", "", "YY"]);
    b.bottles[0].body = Body.Hourglass;
    b.bottles[0].flip_every = 1;
    b.bottles[0].cover = Cover.Rime;
    b.bottles[0].thaw = 5;
    pour(b, 1, 2);
    check(letters(b.bottles[0]) == "RRGB" && b.bottles[0].flip_count == 0, "no count, no flip");
}

// --- chapter 5: vines, the salamander -------------------------------------------------------

fn test_vine() {
    test("vine spreads in order");
    var b = row_of(["RR", "BB", "", "YY", "", "GG"]);
    b.bottles[2].fixture = Fixture.VineRoot;
    b.bottles[2].spread_every = 2;
    pour(b, 0, 4);
    var r = pour(b, 4, 0);
    check(b.bottles[1].cover == Cover.Vine && has_event(r, EventKind.VineSpread, 1), "the lowest neighbor first");
    check(!covered(b.bottles[3]), "one tendril at a time");
    pour(b, 3, 4);
    r = pour(b, 4, 3);
    check(b.bottles[0].cover == Cover.Vine, "then on from the tendril, lowest first");
    check(!can_pour(b, 0, 4) && !can_pour(b, 3, 1), "tendrils cover their flasks");

    test("emerald withers the vine");
    r = pour(b, 5, 2);
    check(r.ok && has_event(r, EventKind.VineWithered, 2), "emerald into the root");
    check(!covered(b.bottles[0]) && !covered(b.bottles[1]) && b.bottles[2].fixture == Fixture.None, "all gone");
}

fn test_salamander() {
    test("salamander");
    var b = row_of(["RG", "R", "R", ""]);
    b.bottles[0].cover = Cover.Rime;
    b.bottles[0].thaw = 9;
    b.salamander = 2;
    check(!can_pour(b, 1, 2), "nothing goes in under it");
    check(can_pour(b, 2, 3), "pouring out is fine");
    let r = pour(b, 1, 3);
    check(b.salamander == 1 && has_event(r, EventKind.SalamanderHop, 1), "it hops to the source");
    check(b.bottles[0].thaw == 7, "and its heat reaches the neighbors");
    check(event_at(r, EventKind.SalamanderHop) < event_at(r, EventKind.HeatPulse), "hop, then heat");
    check(!can_pour(b, 2, 1), "the new perch takes nothing in");
}

// --- chapter 6: the athanor's level, the Drop, catalysts -----------------------------------

fn test_drop() {
    test("Philosopher's Drop");
    check(is_complete(flask("RRR*")) && is_complete(flask("R*RR")) && !is_complete(flask("RR*G")),
          "counts as any color");
    check(top_run(flask("RR*")) == 1 && top_run(flask("R*RR")) == 2, "never joins a run");
    var b = board_of(["G*", "GG", ""]);
    check(can_pour(b, 1, 0), "anything goes onto it");
    let r = pour(b, 1, 0);
    check(r.amount == 2 && b.bottles[0].done, "and it completes a flask");
    check(validate(board_of(["RRR*", "GGGG", ""])).len == 0, "one color a segment short");
    check(validate(board_of(["RRRR", "GGGG", "*"])).len > 0, "but only then");
    check(validate(board_of(["RRR*", "GGG*", ""])).len > 0, "and one Drop at most");
    var t = board_of(["RRRR", "GG*", "GG"]);
    t.bottles[2].cap = 5;
    check(validate(t).len > 0, "but never a tall flask's color: the Drop can't go in there");
}

fn test_catalyst() {
    test("catalyst fires everything");
    var b = row_of(["BBB", "B", "", "GG", "RYG", "Y", ""]);
    b.bottles[0].fixture = Fixture.Catalyst;
    b.bottles[2].fixture = Fixture.Brazier;
    b.bottles[3].cover = Cover.Rime;
    b.bottles[3].thaw = 9;
    b.bottles[4].body = Body.Hourglass;
    b.bottles[4].flip_every = 9;
    b.bottles[6].fixture = Fixture.Lantern;
    let r = pour(b, 1, 0);
    check(b.bottles[0].spent && has_event(r, EventKind.CatalystFired, 0), "fires on completion");
    check(event_at(r, EventKind.Completed) < event_at(r, EventKind.CatalystFired), "after completing");
    check(b.bottles[3].thaw == 7, "braziers heat their neighbors");
    check(letters(b.bottles[4]) == "GYR", "hourglasses flip");
    check(b.bottles[6].lit, "lanterns light");
}

fn test_validate() {
    test("validate");
    var b = board_of(["RRRR", "GGGG", "", ""]);
    b.bottles[0].body = Body.Siphon;
    b.bottles[0].murk = 1;
    check(validate(b).len > 0, "no murk on a siphon");
    b = board_of(["RRRR", "UUUU", ""]);
    b.bottles[2].body = Body.Athanor;
    check(validate(b).len > 0, "an athanor needs quicksilver");
    b = board_of(["RRRR", "QUUU", ""]);
    b.bottles[2].body = Body.Athanor;
    check(validate(b).len == 0, "quicksilver and gold, one set");
    b = board_of(["RRRR", "GGGG", ""]);
    b.bottles[2].cover = Cover.Vine;
    check(validate(b).len > 0, "tendrils need a root");
    b = board_of(["RRRR", "GGGG", ""]);
    b.bottles[0].body = Body.Hourglass;
    check(validate(b).len > 0, "an hourglass needs its flip count");
    b = board_of(["RRRR", "GGGG", ""]);
    b.salamander = 5;
    check(validate(b).len > 0, "the salamander on the board");
}

fn test_hash() {
    test("board hash");
    let a = board_of(["RRGG", "GGRR", ""]);
    let s = board_of(["GGRR", "RRGG", ""]);
    check(board_hash(a) == board_hash(s), "places don't matter on a plain board");
    var x = a;
    var y = s;
    x.bottles[2].fixture = Fixture.Brazier;
    y.bottles[2].fixture = Fixture.Brazier;
    check(board_hash(x) != board_hash(y), "but do next to a brazier");
    var t = a;
    t.bottles[0].cover = Cover.Rime;
    t.bottles[0].thaw = 3;
    var u = t;
    u.bottles[0].thaw = 2;
    check(board_hash(t) != board_hash(u), "timers count");
    var m = a;
    m.salamander = 0;
    var n = a;
    n.salamander = 1;
    check(board_hash(m) != board_hash(n), "and the salamander's perch");
    let k = doors_board([flask("RRGB").key_at(1, KeyColor.Brass), flask("GBRB"), flask("").behind_door(KeyColor.Brass),
                         flask("").behind_door(KeyColor.Brass)]);
    var k2 = k;
    k2.bottles[0].keyed = 1;
    check(board_hash(k) != board_hash(k2), "where a key is");
    var k3 = k;
    k3.doors[0].open = true;
    k3.bottles[2].behind = false;
    k3.bottles[3].behind = false;
    check(board_hash(k) != board_hash(k3), "and whether its door is open");
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
    check(cornered(pointless) && !cornered(b), "cornered: few pours and no empty flask");
    let big = generate(level_spec(59).recipe, level_spec(59).seed).board;
    check(!dead_end(big, 10), "running out of budget proves nothing");
    // The only way on is a pour that just moves a bottle, to melt the ice.
    var ice = board_of(["RR", "", "RR"]);
    ice.bottles[2].cover = Cover.Rime;
    ice.bottles[2].thaw = 1;
    settle(ice);
    check(solve(ice, 1000, path).solved, "pours that only count down the ice are tried");
    // Or to move the salamander off the flask that needs filling.
    var hot = board_of(["RR", "", "RR"]);
    hot.salamander = 0;
    settle(hot);
    check(solve(hot, 1000, path).solved, "pours that only move the salamander are tried");
}

// The game runs the solver, the generator and shuffle a slice a frame; they
// must end where the blocking calls do.
fn test_resumable() {
    test("resumable search");
    var boards: Board[>..] = [];
    boards.push(board_of(["RGBR", "GBRG", "BRGB", "", ""]));
    boards.push(board_of(["RGRG", "GRGR"]));
    boards.push(board_of(["RGRG", "GRG"]));
    boards.push(generate(level_spec(59).recipe, level_spec(59).seed).board);
    boards.push(generate(level_spec(44).recipe, level_spec(44).seed).board);
    var path: Move[>..] = [];
    var stepped: Move[>..] = [];
    for b in boards {
        for budget in [5, 300, 50000] {
            let s = solve(b, budget, path);
            var search = search_begin(b, budget);
            var slices = 0;
            while !search_step(search, 3) { slices++; }
            search_path(search, stepped);
            let t = search.stats;
            check(t.solved == s.solved && t.exhausted == s.exhausted && t.expanded == s.expanded &&
                  t.length == s.length, "the same stats, a few positions at a time");
            var same = stepped.len == path.len;
            for m, i in path { if same && (m.from != stepped[i].from || m.to != stepped[i].to) { same = false; } }
            check(same, "the same path");
            let first, ok = search_first_move(search);
            check(ok == (path.len > 0) && (!ok || (first.from == path[0].from && first.to == path[0].to)),
                  "the same first move");
            check(s.expanded <= 3 || slices >= (s.expanded - 1) / 3, "three positions a slice");
        }
    }
    let p = level_spec(70).recipe;
    var job = gen_begin(p, 1234);
    while !gen_step(job, 10) {}
    let g = generate(p, 1234);
    check(board_hash(job.result.board) == board_hash(g.board) && job.result.attempts == g.attempts,
          "generation in slices brews the same board");
    var sb = board_of(["RGBY", "GBYR", "BYRG", "YRGB", "", ""]);
    var r = rng { 9 };
    var sj = shuffle_begin(sb, r, 30, 20000);
    while !shuffle_step(sj, 4) {}
    check(shuffle_board(sb, r, 30, 20000) && sj.found && board_hash(sj.trial) == board_hash(sb),
          "shuffle in slices deals the same board");
}

// A board that can never be won, with a salamander so that no two empty
// flasks are alike: positions multiply faster than the search can expand
// them. Its stored positions stay bounded, and nothing is proven.
fn test_search_memory() {
    test("search memory");
    var b = board_of(["RGYO", "GYOL", "YOLK", "OLKC", "LKCG", "KCGY", "CRRL", "BBGR", "BKY", "", "", "", "", "", ""]);
    b.salamander = 3;
    var s = search_begin(b, 200000);
    while !search_step(s, 1000) {}
    check(!s.stats.solved && !s.stats.exhausted, "a board that can't be won isn't won, nor proven lost when cut short");
    check(s.nodes.len <= s.room && s.room <= MAX_NODES, "the positions stored stay within the room");
}

fn test_generator() {
    test("generator");
    for seed in 1..6 {
        let g = generate(Recipe { colors: 5, spares: 2, partial: 2 }, seed as u64);
        check(g.m.solved, "generated levels are solvable");
        check(validate(g.board).len == 0, "and well formed");
        check(g.board.colors == 5, "with the colors asked for");
    }
    let a = generate(Recipe { colors: 6, spares: 2 }, 99);
    let b = generate(Recipe { colors: 6, spares: 2 }, 99);
    check(board_hash(a.board) == board_hash(b.board), "the same seed gives the same board");
    var path: Move[>..] = [];
    var p = Recipe { colors: 6, spares: 2, smoke: 3 };
    want(p, Feature.Rime, 1);
    want(p, Feature.Seal, 1);
    want(p, Feature.Vow, 1);
    let o = generate(p, 7);
    check(o.m.solved && solve(o.board, 100000, path).solved, "modifiers stay solvable");

    // Each modifier, alone or with what it needs, for a few seeds: it is on
    // the board and the solution uses it.
    for which in 16 {
        var q = Recipe { colors: 5, spares: 2 };
        var name = "";
        match which {
            0 => { q.smoke = 4; name = "murk"; },
            1 => { want(q, Feature.Seal, 2); name = "seal"; },
            2 => { want(q, Feature.Vow, 1); q.spares = 1; name = "vow"; },
            3 => { q.tall = 1; q.tall_rows = 2; name = "tall"; },
            4 => { want(q, Feature.Rime, 1); want(q, Feature.Brazier, 1); q.thaw = 5; name = "brazier"; },
            5 => { want(q, Feature.Quicksilver, 1); name = "quicksilver"; },
            6 => { want(q, Feature.Siphon, 1); name = "siphon"; },
            7 => { want(q, Feature.Keys, 2); name = "doors"; },
            8 => { want(q, Feature.Shroud, 1); q.smoke = 2; name = "shroud"; },
            9 => { want(q, Feature.Hourglass, 1); q.smoke = 2; name = "hourglass"; },
            10 => { want(q, Feature.Vine, 1); name = "vine"; },
            11 => { want(q, Feature.Salamander, 1); want(q, Feature.Rime, 1); q.thaw = 5; name = "salamander"; },
            12 => { want(q, Feature.Moonpetal, 1); name = "moonpetal"; },
            13 => { want(q, Feature.Athanor, 1); name = "athanor"; },
            14 => { want(q, Feature.Curtain, 1); name = "curtain"; },
            _ => {
                want(q, Feature.Drop, 1);
                want(q, Feature.Catalyst, 1);
                want(q, Feature.Lantern, 1);
                want(q, Feature.Hourglass, 1);
                q.smoke = 3;
                name = "drop and catalyst";
            },
        }
        for seed in 1..4 {
            let g = generate(q, seed as u64 * 31);
            check(g.m.solved && g.attempts <= MAX_ATTEMPTS && validate(g.board).len == 0, str(name, " is generated"));
            check(has_modifier(g.board, which), str(name, " is on the board, seed ", seed));
            let s = solve(g.board, 100000, path);
            check(s.solved, str(name, " can be won"));
            let f, unused = unused_feature(uses_of(g.board, path[..]));
            check(!unused, str(name, ": every modifier does something, seed ", seed, " (", feature_name(f), ")"));
        }
        let x = generate(q, 5);
        let y = generate(q, 5);
        check(board_hash(x.board) == board_hash(y.board), str(name, ": the same seed gives the same board"));
    }

    test("recipes");
    for n in [4, 23, 57, 97] {
        let s1 = level_spec(n);
        let s2 = level_spec(n);
        check(s1.recipe.colors == s2.recipe.colors && s1.recipe.smoke == s2.recipe.smoke && s1.recipe.mods == s2.recipe.mods &&
              s1.recipe.band_lo == s2.recipe.band_lo && s1.recipe.focused == s2.recipe.focused, "a level's recipe is the same every time");
    }
    var narrow = Recipe { colors: 5, spares: 2, band_lo: 1000.0, band_hi: 2000.0 };
    let far = generate(narrow, 3);
    check(far.m.solved && !far.in_band && far.attempts <= BAND_ATTEMPTS + 1, "a band out of reach keeps the closest deal");
    narrow.band_lo = -1e9;
    let near = generate(narrow, 3);
    check(near.in_band && near.attempts == near.valid_at, "a band within reach takes the first valid deal in it");
}

// Whether the generator's test case `which` put its modifier on the board.
fn has_modifier(board: Board, which: i64) -> bool {
    var tally: i64[MAX_LIQUID + 1] = [0; MAX_LIQUID + 1];
    for i in board.count { for k in board.bottles[i].n as i64 { tally[board.bottles[i].seg[k]]++; } }
    for i in board.count {
        let b = board.bottles[i];
        var by_ice = false;
        for j in neighbors(board, i) { if board.bottles[j].cover == Cover.Rime { by_ice = true; } }
        let ok = match which {
            0 => b.murk != 0,
            1 => b.cover == Cover.Seal,
            2 => b.body == Body.Vow,
            3 => b.cap > CAP,
            4 => b.fixture == Fixture.Brazier && by_ice,
            5 => tally[QUICKSILVER] == CAP,
            6 => b.body == Body.Siphon,
            7 => board.door_count == 2 && b.key_color != KeyColor.None && layers_over_key(b) > 0 && layers_over_key(b) <= 3,
            8 => b.cover == Cover.Shroud,
            9 => b.body == Body.Hourglass,
            10 => b.fixture == Fixture.VineRoot && tally[EMERALD] > 0,
            11 => board.salamander >= 0,
            12 => b.body == Body.Moonpetal,
            13 => b.body == Body.Athanor && tally[QUICKSILVER] > 0,
            14 => b.cover == Cover.Curtain && !has_color(b, b.badge),
            _ => tally[DROP] == 1 && b.fixture == Fixture.Catalyst,
        };
        if ok { return true; }
    }
    false
}

// --- tools ------------------------------------------------------------------------

fn test_tools() {
    test("shuffle");
    var b = board_of(["RGBY", "GBYR", "BYRG", "YRGB", "", ""]);
    b.bottles[0].murk = murk_below(2);
    b.bottles[3].cover = Cover.Rime;
    b.bottles[3].thaw = 5;
    settle(b);
    let before = b;
    var r = rng { 42 };
    check(shuffle_board(b, r, 30, 20000), "finds a solvable deal");
    check(validate(b).len == 0 && color_count(b) == 4, "the same liquid");
    check(b.bottles[0].seg[0] == before.bottles[0].seg[0] &&
          b.bottles[0].seg[1] == before.bottles[0].seg[1], "murky layers stay put");
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
    check(chapter_count() == 7 && chapter_info(6).last < 0, "six chapters, then the endless Great Work");
    for c in 6 {
        let ch = chapter_info(c);
        check(ch.first == c * 15 + 1 && ch.last == ch.first + 14, "fifteen levels a chapter");
        check(chapter_of(ch.first) == c && chapter_of(ch.last) == c, "a chapter's levels are its own");
        check(level_spec(ch.first + 4).difficulty == Difficulty.Hard &&
              level_spec(ch.first + 9).difficulty == Difficulty.Hard, "Hard at 5 and 10");
        let fin = level_spec(ch.last);
        check(fin.is_finale && fin.hand_made && fin.difficulty == Difficulty.SuperHard,
              str(ch.name, " ends in a hand-made Super Hard finale"));
        check(chapter_features(c).len >= 2, "every chapter brings modifiers");
    }
    check(chapter_of(91) == 6 && chapter_of(500) == 6, "the Great Work goes on");
    check(!level_spec(105).hand_made && level_spec(105).difficulty == Difficulty.SuperHard, "and keeps the rhythm");
    var last = 0;
    for f in ALL_FEATURES {
        let n = tutorial_level(f);
        check(n > last, "modifiers come in order");
        last = n;
        let s = level_spec(n);
        check(s.is_tutorial && s.tutorial == f && s.hand_made && s.difficulty == Difficulty.Normal && n % 5 != 0,
              str(feature_name(f), " has its tutorial"));
        let h, found = campaign_hand_made(n);
        check(found && feature_on(h.board, f), str(feature_name(f), "'s tutorial uses it"));
    }
    check(level_spec(1).hand_made && level_spec(2).mods.len == 0 && level_spec(2).recipe.smoke == 0,
          "levels 1 and 2 are plain");
    check(level_spec(4).recipe.colors <= level_spec(44).recipe.colors &&
          level_spec(44).recipe.colors <= level_spec(89).recipe.colors, "colors ramp up");
}

// Every level from 1 to 120: the hand-made ones are there, and the rest are
// generated solvable, quickly, with what the ramp asks for, in their band
// (or as close as the deals came), every modifier doing something and the
// level's focus required.
fn test_generated_levels() {
    test("generated levels");
    let t0 = clock();
    var worst = 0.0;
    var worst_level = 0;
    var misses: i64[>..] = [];
    var unfocused: i64[>..] = [];
    var generated = 0;
    print("  level  colors spares  score  length parking traps  band        modifiers");
    for n in 1..121 {
        let spec = level_spec(n);
        if spec.hand_made {
            let h, found = campaign_hand_made(n);
            check(found && h.number == n, str("level ", n, " is built in"));
            continue;
        }
        check(!spec.is_tutorial && !spec.is_finale, str("level ", n, ": tutorials and finales are hand-made"));
        let t = clock();
        let g = generate(spec.recipe, spec.seed);
        let dt = clock() - t;
        generated++;
        if dt > worst {
            worst = dt;
            worst_level = n;
        }
        let p = spec.recipe;
        var mods: u8[>..] = [];
        for f in spec.mods { format(mods, feature_name(f), if contains(spec.mods, f) && p.focused && p.focus == f { "* " } else { " " }); }
        print("  ", n, if n < 10 { "    " } else if n < 100 { "   " } else { "  " }, difficulty_name(spec.difficulty)[..1], "  ",
              p.colors, "      ", p.spares, "      ", (g.m.score * 10.0) as i64 / 10.0, "   ", g.m.length, "     ", g.m.parking,
              "      ", g.m.traps, "     ", p.band_lo as i64, "-", p.band_hi as i64, if g.in_band { "   " } else { " x " }, mods);
        if !g.in_band { misses.push(n); }
        check(g.m.solved && validate(g.board).len == 0, str("level ", n, " is solvable and well formed"));
        // Six deals were enough when a deal only had to be solvable; now
        // every modifier must matter and the focus be required, so more
        // fail (cheaply: most fail the solve early or a use test). The
        // first valid deal comes within 40, before the easing drops the
        // focus check, and the band takes a few more at most.
        check(g.valid_at <= 40, str("level ", n, " brews in a few attempts (", g.valid_at, ")"));
        check(g.attempts <= max(BAND_ATTEMPTS, g.valid_at + 1), str("level ", n, " stops looking for its band in time"));
        check(g.board.count <= 18, str("level ", n, " fits the screen"));
        var path: Move[>..] = [];
        check(solve(g.board, p.budget, path).solved, str("level ", n, " can be won"));
        let f, unused = unused_feature(uses_of(g.board, path[..]));
        check(!unused, str("level ", n, ": its ", feature_name(f), " does something"));
        if p.focused && !requires(g.board, p.focus, p.budget) { unfocused.push(n); }
        for f in spec.mods {
            check(introduced(f, n), str("level ", n, ": ", feature_name(f), " only after its tutorial"));
            check(feature_on(g.board, f), str("level ", n, " has its ", feature_name(f)));
        }
        let newest, any = newest_feature(n);
        check(!any || contains(spec.mods, newest), str("level ", n, " uses the newest modifier"));
        check(!any || n >= GREAT_WORK || (p.focused && p.focus == newest), str("level ", n, " is about the newest modifier"));
        check(!tall_level(n) || feature_on(g.board, Feature.Tall), str("level ", n, " has a tall flask"));
        check(n < 3 || feature_on(g.board, Feature.Murk), str("level ", n, " has murk"));
        let ch = chapter_of(n);
        var earlier = 0;
        for f in spec.mods { if f != Feature.Tall && chapter_of(tutorial_level(f)) < ch { earlier++; } }
        if ch > 0 && ch < 6 && chapter_position(n) <= 2 {
            var only_earlier = true;
            for f in spec.mods { if chapter_of(tutorial_level(f)) >= ch { only_earlier = false; } }
            check(only_earlier && earlier >= 2, str("level ", n, " warms up with two earlier modifiers"));
        } else if ch > 0 && ch < 6 && !tall_level(n) {
            let want_n = if spec.difficulty == Difficulty.Normal { 1 } else { 2 };
            check(earlier >= want_n, str("level ", n, " uses earlier chapters' modifiers"));
        } else if ch == 6 {
            var drawn = 0;
            for f in spec.mods { if f != Feature.Tall { drawn++; } }
            check(drawn >= 3, str("level ", n, " draws three or four modifiers"));
        }
    }
    print("  levels 1-120 generated in ", clock() - t0, "s, slowest ", worst_level, " at ", worst, "s");
    print("  ", generated - misses.len, " of ", generated, " in their band; closest kept for ", misses);
    print("  focus not required (dropped after many deals): ", unfocused);
    check(misses.len * 5 <= generated, "most levels land in their band");
    check(unfocused.len * 10 <= generated, "almost every level's focus is required");
    // Difficulty ramps: chapter by chapter, Normal levels' scores climb, and
    // Hard ones sit above the Normal ones of their chapter.
    var last_normal = 0.0;
    for c in 6 {
        let ch = chapter_info(c);
        var normal = 0.0;
        var normals = 0;
        var hard = 0.0;
        var hards = 0;
        for n in ch.first..ch.last + 1 {
            let spec = level_spec(n);
            if spec.hand_made { continue; }
            let m = generate(spec.recipe, spec.seed).m;
            if spec.difficulty == Difficulty.Normal { normal += m.score; normals++; } else { hard += m.score; hards++; }
        }
        normal /= max(1, normals);
        hard /= max(1, hards);
        check(hard > normal + 3.0, str(ch.name, ": Hard levels are clearly harder (", hard, " vs ", normal, ")"));
        if c < 5 { check(normal > last_normal, str(ch.name, ": Normal levels ramp up (", normal, ")")); }
        last_normal = normal;
    }
    var job = gen_begin(level_spec(97).recipe, level_spec(97).seed);
    while !gen_step(job, 10) {}
    check(board_hash(job.result.board) == board_hash(generate(level_spec(97).recipe, level_spec(97).seed).board),
          "a level is the same board every time");
}

// --- difficulty and variants ---------------------------------------------------------

fn test_difficulty() {
    test("measuring");
    check(log2_of(1) == 0.0 && log2_of(2) == 1.0 && log2_of(8) == 3.0 && log2_of(12) == 3.5, "log2, by halves");
    let easy = board_of(["RRRG", "GGGR", "", ""]);
    let hard = board_of(["RGBY", "GBYR", "BYRG", "YRGB", "", ""]);
    let me = measure(easy, 20000, 1);
    let mh = measure(hard, 20000, 1);
    check(me.solved && mh.solved && mh.score > me.score + 5.0, "more colors, more to do: a higher score");
    let mh2 = measure(hard, 20000, 1);
    check(mh2.score == mh.score && mh2.traps == mh.traps, "the same board measures the same");
    var smoky = hard;
    smoky.bottles[0].murk = murk_below(3);
    settle(smoky);
    check(measure(smoky, 20000, 1).hidden > mh.hidden, "smoke counts as hidden");
    check(mh.freedom > 0.0 && mh.length > 0, "freedom and length");
    let dead = board_of(["RGRG", "GRGR"]);
    check(!measure(dead, 1000, 1).solved, "a dead board doesn't measure as solved");

    test("use tests");
    // A seal the solution breaks; one it never needs to.
    var b = board_of(["RGB", "GBRR", "BRG", "BG", ""]);
    b.bottles[0].cover = Cover.Seal;
    b.bottles[0].key = 7;
    settle(b);
    var path: Move[>..] = [];
    check(solve(b, 20000, path).solved, "the sealed board can be won");
    let u = uses_of(b, path[..]);
    check(u.on[feature_index(Feature.Seal)] && u.used[feature_index(Feature.Seal)], "a seal the solution breaks is used");
    var lamp = board_of(["RRRG", "GGG", "BBBB", "R", ""]);
    lamp.bottles[2] = lantern(lamp.bottles[2]);
    settle(lamp);
    check(solve(lamp, 20000, path).solved, "a lantern that lights at the start");
    let ul = uses_of(lamp, path[..]);
    check(ul.on[feature_index(Feature.Lantern)] && !ul.used[feature_index(Feature.Lantern)], "a lantern with nothing to light does nothing");
    let f, unused = unused_feature(ul);
    check(unused && f == Feature.Lantern, "and is the one named");

    test("focus");
    let h, found = campaign_hand_made(36);
    let open = without_feature(h.board, Feature.Keys);
    var shut = false;
    for i in open.count { if open.bottles[i].behind || open.bottles[i].key_color != KeyColor.None { shut = true; } }
    check(!shut, "without its keys, every door stands open");
    let v, vfound = campaign_hand_made(11);
    check(requires(v.board, Feature.Vow, 100000), "level 11 needs its vow flask");
}

// Whether `b` is `a` with its colors permuted (one to one) wherever `keep`
// says, and every modifier, key and smoke as it was.
fn same_but_colors(a: Board, b: Board, hidden_ok: bool) -> bool {
    if a.count != b.count || a.door_count != b.door_count || a.salamander != b.salamander { return false; }
    var map: i64[MAX_LIQUID + 1] = [0; MAX_LIQUID + 1];
    var back: i64[MAX_LIQUID + 1] = [0; MAX_LIQUID + 1];
    for i in a.count {
        let x = a.bottles[i];
        let y = b.bottles[i];
        if x.n != y.n || x.cap != y.cap || x.murk != y.murk || x.cover != y.cover || x.body != y.body ||
           x.fixture != y.fixture || x.keyed != y.keyed || x.key_color != y.key_color || x.door != y.door ||
           x.thaw != y.thaw || x.flip_every != y.flip_every || x.spread_every != y.spread_every { return false; }
        for k in x.n as i64 {
            if hidden_ok && hidden_slot(a, i, k) { continue; }
            let c: i64 = x.seg[k];
            let d: i64 = y.seg[k];
            if map[c] == 0 && back[d] == 0 { map[c] = d; back[d] = c; }
            if map[c] != d || back[d] != c { return false; }
        }
    }
    true
}

fn test_variants() {
    test("variants");
    let t0 = clock();
    var worst = 0.0;
    var reshuffled = 0;
    var total = 0;
    for n in [4, 7, 19, 23, 38, 47, 53, 62, 67, 74, 82, 89, 99, 105, 3, 6, 36, 51, 63] {
        let spec = level_spec(n);
        var board = Board { .. };
        var named: u8[>..] = [];
        if spec.hand_made {
            let h, found = campaign_hand_made(n);
            board = h.board;
            named.append(h.info.hint);
        } else {
            board = generate(spec.recipe, spec.seed).board;
        }
        let first = variant(board, spec.seed, 0, named[..]);
        check(board_hash(first) == board_hash(board), str("level ", n, ": the first attempt is the level itself"));
        let base = base_score(measure(board, VARY_BUDGET, 1));
        for attempt in 1..4 {
            let t = clock();
            var job = variant_begin(board, spec.seed, attempt, named[..]);
            while !variant_step(job, 1000) {}
            worst = max(worst, clock() - t);
            let v = job.result;
            total++;
            if job.reshuffled { reshuffled++; }
            check(board_hash(v) == board_hash(variant(board, spec.seed, attempt, named[..])), "a variant is the same every time");
            check(validate(v).len == 0, str("level ", n, " attempt ", attempt, ": well formed"));
            check(same_but_colors(board, v, true), str("level ", n, " attempt ", attempt, ": the visible layers and modifiers stay"));
            check(job.reshuffled || same_but_colors(board, v, false), "the fallback is the recolor alone");
            var path: Move[>..] = [];
            let s = solve(v, VARY_BUDGET, path);
            check(s.solved, str("level ", n, " attempt ", attempt, ": it can be won"));
            let m = measure(v, VARY_BUDGET, 1);
            check(abs(base_score(m) - base) <= VARY_SHARE * abs(base) + 0.001, str("level ", n, " attempt ", attempt, ": as hard (", base_score(m), " vs ", base, ")"));
            let f, unused = unused_feature(uses_of(v, path[..]));
            check(!unused, str("level ", n, " attempt ", attempt, ": its ", feature_name(f), " still does something"));
            if spec.hand_made {
                // Colors the hint names stay.
                for c in 1..MAX_COLORS + 1 {
                    if !fixed_color(board, c, named[..]) { continue; }
                    for i in board.count {
                        for k in board.bottles[i].n as i64 {
                            if board.bottles[i].seg[k] == c && !hidden_slot(board, i, k) {
                                check(v.bottles[i].seg[k] == c, str("level ", n, ": ", COLOR_NAMES[c], " is named, so it stays"));
                            }
                        }
                    }
                }
            }
        }
    }
    var differ = 0;
    let b19 = generate(level_spec(19).recipe, level_spec(19).seed).board;
    for a in 1..5 { if board_hash(variant(b19, level_spec(19).seed, a, "")) != board_hash(b19) { differ++; } }
    check(differ == 4, "every later attempt differs from the level");
    print("  ", total, " variants, ", reshuffled, " reshuffled, slowest ", worst, "s, all in ", clock() - t0, "s");
}

// Old saves kept the next level from before the chapters.
fn test_saves() {
    test("old saves");
    check(migrated_level(1) == 1 && migrated_level(15) == 1 && migrated_level(16) == 16 &&
          migrated_level(50) == 46 && migrated_level(90) == 76 && migrated_level(91) == 91 &&
          migrated_level(400) == 91 && migrated_level(0) == 1, "to the start of the chapter that holds it");
    for n in 1..200 {
        let m = migrated_level(n);
        check(m <= n && chapter_info(chapter_of(m)).first == m && migrated_level(m) == m,
              "a chapter's first level, at or before the old one");
    }
}

// --- enum tables -------------------------------------------------------------------

fn test_tables() {
    test("enum tables");
    for x, i in ALL_BODIES { check(body_index(x) == i, "ALL_BODIES is in index order"); }
    for x, i in ALL_COVERS { check(cover_index(x) == i, "ALL_COVERS is in index order"); }
    for x, i in ALL_FIXTURES { check(fixture_index(x) == i, "ALL_FIXTURES is in index order"); }
    for s, i in ALL_SHAPES {
        check(shape_index(s) == i, "ALL_SHAPES is in index order");
        check(find(FRAGMENT_SHADER, str("#define ", shape_define(s), " ", i, "\n")) >= 0,
              str("the shader numbers ", shape_define(s), " ", i));
    }
    for s in ALL_SHAPES {
        check(shader_program_of(shape_define(s)) == program_define(shape_program(s)),
              str("the shader draws ", shape_define(s), " in the program draw.goose gives it"));
    }
    for c, i in ALL_ICONS {
        check(icon_index(c) == i, "ALL_ICONS is in index order");
        check(find(FRAGMENT_SHADER, str("#define ", icon_define(c), " ", i, "\n")) >= 0,
              str("the shader numbers ", icon_define(c), " ", i));
    }
    check(color_of_letter('Q') == QUICKSILVER && color_of_letter('U') == GOLD && color_of_letter('*') == DROP,
          "the special liquids' letters");
}

// The program a shape's branch of the fragment shader is in: the
// #ifdef PROGRAM_... still open where main() tests for it ("" for none).
fn shader_program_of(define: const u8[:]) -> const u8[:] {
    let main = find(FRAGMENT_SHADER, "void main()");
    let at = find(FRAGMENT_SHADER, str("(kind == ", define, ")"));
    if main < 0 || at < main { return "?"; }
    let before = FRAGMENT_SHADER[main..at];
    let open = rfind(before, "#ifdef ");
    if open < 0 || rfind(before, "#endif") > open { return ""; }
    let name = before[open + 7..];
    name[..find(name, "\n")]
}

// --- shipped levels -------------------------------------------------------------------

// What a solution set off, pour by pour.
struct PathFacts {
    seen: bool[19] = [false; 19],   // by event kind
    heat_ice: bool = false,         // heat reached a flask under ice
    heat_seal: bool = false,        // a seal broken by heat
    drop_key: bool = false,         // the Drop broke a seal
    siphon_quicksilver: bool = false,   // quicksilver came out of a siphon's tap
    into_moonpetal: bool = false,
}

fn kind_index(k: EventKind) -> i64 {
    match k {
        SealBroken => 0, SealSoftened => 1, Thawed => 2, HeatPulse => 3, Lit => 4, ShroudLifted => 5,
        MurkCleared => 6, Flipped => 7, VineSpread => 8, VineWithered => 9, TendrilBurned => 10,
        SalamanderHop => 11, Transmuted => 12, CatalystFired => 13, Completed => 14, Vowed => 15, KeyFreed => 16,
        DoorOpened => 17, CurtainOpened => 18,
    }
}

fn path_facts(start: Board, path: Move[:]) -> PathFacts {
    var f = PathFacts {};
    var b = start;
    for m in path {
        let before = b;
        let src = b.bottles[m.from];
        let dst = b.bottles[m.to];
        let r = pour(b, m.from, m.to);
        if r.popped && r.color == DROP { f.drop_key = true; }
        if src.body == Body.Siphon && r.color == QUICKSILVER { f.siphon_quicksilver = true; }
        if dst.body == Body.Moonpetal && r.amount > 0 { f.into_moonpetal = true; }
        for e in r.events {
            f.seen[kind_index(e.kind)] = true;
            if e.kind == EventKind.HeatPulse && before.bottles[e.bottle].cover == Cover.Rime { f.heat_ice = true; }
            if e.kind == EventKind.SealBroken && e.from >= 0 && b.bottles[e.from].fixture == Fixture.Brazier {
                f.heat_seal = true;
            }
        }
    }
    f
}

// What each hand-made level is there to show, on the way to winning it.
fn shows(number: i64, f: PathFacts) -> bool {
    fn saw(k: EventKind) -> bool { f.seen[kind_index(k)] }
    match number {
        6 => saw(EventKind.SealBroken),
        11 => saw(EventKind.Vowed),
        18 => saw(EventKind.Thawed),
        21 => f.heat_ice,
        36 => saw(EventKind.KeyFreed) && saw(EventKind.DoorOpened),
        41 => saw(EventKind.CurtainOpened),
        48 => saw(EventKind.Lit),
        51 => saw(EventKind.ShroudLifted),
        56 => saw(EventKind.Flipped),
        63 => saw(EventKind.VineSpread) && saw(EventKind.VineWithered),
        66 => saw(EventKind.SalamanderHop) && f.heat_ice,
        71 => saw(EventKind.Lit) && f.into_moonpetal,
        78 => saw(EventKind.Transmuted),
        86 => saw(EventKind.CatalystFired) && saw(EventKind.Flipped) && saw(EventKind.Lit),
        // The finales: the interactions are the point.
        15 => saw(EventKind.SealBroken) && saw(EventKind.Vowed),
        30 => f.heat_ice && f.heat_seal,
        45 => f.siphon_quicksilver && saw(EventKind.DoorOpened),
        60 => saw(EventKind.Lit) && saw(EventKind.ShroudLifted) && saw(EventKind.Flipped),
        75 => saw(EventKind.TendrilBurned) && saw(EventKind.VineWithered) && saw(EventKind.Lit) && f.into_moonpetal,
        90 => f.drop_key && saw(EventKind.CatalystFired) && saw(EventKind.Transmuted) && saw(EventKind.ShroudLifted) &&
              saw(EventKind.Flipped) && f.heat_ice,
        _ => true,
    }
}

// The level without the modifier it teaches, where it cannot be won without
// it: quicksilver as an ordinary color, a siphon or an hourglass made plain,
// the vow flask shut (an empty vow need not be used,
// so it is there to be the spare the level needs).
fn without_lesson(number: i64, board: Board) -> Board, bool {
    var b = board;
    var any = false;
    for i in b.count {
        var x .= b.bottles[i];
        if number == 26 { for k in x.n as i64 { if x.seg[k] == QUICKSILVER { x.seg[k] = 6; any = true; } } }
        if number == 33 && x.body == Body.Siphon { x.body = Body.Plain; any = true; }
        if number == 56 && x.body == Body.Hourglass { x.body = Body.Plain; any = true; }
        if (number == 11 || number == 15) && x.body == Body.Vow { x.done = true; any = true; }
        // Without its key, the door stays shut for good.
        if (number == 36 || number == 45) && x.key_color != KeyColor.None { x.key_color = KeyColor.None; x.keyed = 0; any = true; }
    }
    return b, any;
}

// Every hand-made level is well formed, can be won without a huge search,
// and its solution uses what the level is there to show.
fn test_levels() {
    test("shipped levels");
    var numbers: i64[>..] = [];
    for k in HAND_MADE_COUNT {
        let h = hand_made(k);
        let name = h.info.name;
        let err = validate(h.board);
        check(err.len == 0, str(name, ": ", err));
        check(h.info.hint.len > 0 && h.info.name.len > 0, str(name, " has a name and a hint"));
        check(h.board.rows > 0 && !is_won(h.board), str(name, " is settled and not yet won"));
        check(h.number > 0 && !contains(numbers, h.number), str(name, " has a level number of its own"));
        numbers.push(h.number);
        let back, found = campaign_hand_made(h.number);
        check(found && back.info.name == name, str(name, " is found by its number"));
        var moves: Move[>..] = [];
        let s = solve(h.board, 100000, moves);
        check(s.solved && s.expanded <= 30000, str(name, " can be won"));
        check(shows(h.number, path_facts(h.board, moves)), str(name, ": the solution uses what it teaches"));
        let f, unused = unused_feature(uses_of(h.board, moves[..]));
        check(!unused, str(name, ": its ", feature_name(f), " does something"));
        if h.number == 86 { check(requires(h.board, Feature.Catalyst, 100000), "the catalyst is required"); }
        let plain, any = without_lesson(h.number, h.board);
        if any { check(solve(plain, 100000, moves).exhausted, str(name, " cannot be won without it")); }
    }
}

// --- music ------------------------------------------------------------------------

// --- the board in words ---------------------------------------------------------------------

fn card_says(c: Card, words: const u8[:]) -> bool {
    for l in c.lines { if find(l.text[..], words) >= 0 { return true; } }
    false
}

fn blocked_says(c: Card, words: const u8[:]) -> bool {
    for l in c.lines { if l.kind == LineKind.Blocked && find(l.text[..], words) >= 0 { return true; } }
    false
}

fn related_to(c: Card, j: i64, tie: Tie, acts: bool) -> bool {
    for r in c.related { if r.flask == j && r.tie == tie && r.acts == acts { return true; } }
    false
}

fn entry_of(es: const Entry[:], f: Feature) -> i64 {
    for e, k in es { if e.feature == f { return k; } }
    -1
}

fn effect_says(es: const Entry[:], f: Feature, words: const u8[:]) -> i64 {
    let k = entry_of(es, f);
    if k < 0 { return -1; }
    for x, n in es[k].effects { if find(x.text[..], words) >= 0 { return n; } }
    -1
}

fn test_explain() {
    test("a flask's card: heat");
    var b = row_of(["RGB", "", "GBR", "YY"]);
    b.bottles[0] = rime(b.bottles[0], 3);
    b.bottles[1] = brazier(b.bottles[1]);
    b.bottles[2] = seal(b.bottles[2], 'R');
    var c = explain_flask(b, 0);
    check(find(c.title[..], "Rime") >= 0, "its name");
    check(card_says(c, "Frozen: thaws in 3 pours") && card_says(c, "each pour into the Brazier on its right melts one more"),
          "ice, and the brazier that melts it");
    check(blocked_says(c, "Can't pour in or out until it thaws"), "blocked both ways");
    check(related_to(c, 1, Tie.Heat, false) && c.related.len == 1, "tied to the brazier");
    c = explain_flask(b, 2);
    check(card_says(c, "Sealed with Ruby wax: pour Ruby onto it, or heat it twice"), "the seal's key and heat");
    check(blocked_says(c, "Can't pour from it until the seal breaks") && blocked_says(c, "only Ruby can go on"), "what goes on a seal");
    check(related_to(c, 1, Tie.Heat, false), "tied to the brazier");
    c = explain_flask(b, 1);
    check(card_says(c, "Brazier: each pour into it warms") && card_says(c, "the ice on its left and the seal on its right"),
          "the brazier names what it warms");
    check(related_to(c, 0, Tie.Heat, true) && related_to(c, 2, Tie.Heat, true), "and points at both");
    check(blocked_says(c, "Can't pour from it: it's empty"), "an empty flask");
    c = explain_flask(b, 3);
    check(card_says(c, "Holds 2 of 4") && c.related.len == 0, "a plain flask");

    test("a flask's card: light");
    b = row_of(["RRR", "GBYG", "BB"]);
    b.bottles[0] = lantern(b.bottles[0]);
    b.bottles[1] = shroud(b.bottles[1]);
    b.bottles[2] = moonpetal(b.bottles[2]);
    c = explain_flask(b, 1);
    check(card_says(c, "Shrouded: hidden until the Lantern on its left lights"), "the shroud waits on its lantern");
    check(related_to(c, 0, Tie.Light, false), "tied to the lantern");
    c = explain_flask(b, 0);
    check(card_says(c, "lights when this flask is completed, and lifts the Shroud on its right"), "the lantern");
    check(related_to(c, 1, Tie.Light, true) && related_to(c, 2, Tie.Light, true), "it lights the shroud and the moonpetal");
    c = explain_flask(b, 2);
    check(card_says(c, "Moonpetal: closed until a lantern is lit") && blocked_says(c, "Can't pour into it until a lantern is lit"),
          "the moonpetal");

    test("a flask's card: keys, doors, curtains");
    b = doors_board([flask("GRRB").key_at(1, KeyColor.Brass), flask("B"), flask("G").behind_door(KeyColor.Brass),
                     flask("").behind_door(KeyColor.Brass), flask("RRBB").curtain('G'), flask("GRGB").key_at(0, KeyColor.Silver),
                     flask("").behind_door(KeyColor.Silver), flask("").behind_door(KeyColor.Silver)]);
    c = explain_flask(b, 0);
    check(card_says(c, "Brass key: buried under 1 layer; clear it to unlock the brass door.") && find(c.title[..], "Key") >= 0,
          "a key's card");
    check(related_to(c, 2, Tie.Key, true) && related_to(c, 3, Tie.Key, true), "tied to what its door hides");
    check(card_says(explain_flask(b, 5), "Silver key: buried under 3 layers; clear them"), "deeper");
    c = explain_flask(b, 2);
    check(card_says(c, "Behind the brass door: opens when the brass key reaches the top of its flask.") &&
          related_to(c, 0, Tie.Key, false), "behind a door");
    check(blocked_says(c, "Can't pour in or out until the brass door opens"), "shut both ways");
    check(refusal(b, -1, 2) == "Behind the brass door: opens when the brass key reaches the top of its flask." &&
          refusal(b, 1, 3) == refusal(b, -1, 3), "refusals");
    c = explain_flask(b, 4);
    check(card_says(c, "Curtain: opens when an Emerald flask is completed."), "a curtain");
    check(blocked_says(c, "Can't pour in or out until the curtain opens") && find(c.title[..], "Curtain") >= 0, "shut");
    var es = grimoire(b);
    check(effect_says(es[..], Feature.Keys, "Brass key: opens the brass door when its layer reaches the top.") >= 0 &&
          effect_says(es[..], Feature.Curtain, "Curtain: opens when") >= 0, "the grimoire");

    test("a flask's card: hourglass, siphon, vow, tall");
    b = row_of(["GGR", "", "RBB", "B", "GG"]);
    b.bottles[2] = hourglass(b.bottles[2], 3);
    b.bottles[2].flip_count = 1;
    b.bottles[3] = siphon(b.bottles[3]);
    b.bottles[4] = vow_flask(b.bottles[4]);
    settle(b);
    c = explain_flask(b, 2);
    check(card_says(c, "Hourglass: flips in 2 pours"), "the hourglass counts down");
    check(card_says(c, "When it flips, Ruby comes to the top"), "and what comes up");
    c = explain_flask(b, 3);
    check(card_says(c, "Siphon: pours from the tap at its base. Next out: 1 Sapphire"), "the siphon's tap");
    c = explain_flask(b, 4);
    check(card_says(c, "Vow Flask: sworn to Emerald"), "a vow");
    let tall = hand_made(3).board;
    var t = -1;
    for i in tall.count { if tall.bottles[i].cap > CAP { t = i; } }
    check(card_says(explain_flask(tall, t), "Tall Flask: holds 9. Only Violet goes in, and nothing comes out"), "the tall flask's color");
    check(refusal(tall, -1, t) == "Nothing comes out of a tall flask. It only takes Violet.", "tapping it first");
    var f0 = -1;
    for i in tall.count { if can_pour(tall, i, 5) && pour_color(tall.bottles[i]) != color_of_letter('V') { f0 = i; } }
    check(f0 >= 0 && refusal(tall, f0, t) == "This tall flask only takes Violet.", "pouring another color in");

    test("a flask's card: vine");
    b = row_of(["R", "GG", "B", "RRBB", ""]);
    b.bottles[1] = root(b.bottles[1], 4);
    b.bottles[2] = vine(b.bottles[2]);
    c = explain_flask(b, 1);
    check(card_says(c, "Vine root: spreads in 4 pours. Pour Emerald in to wither the vine"), "the root");
    check(related_to(c, 2, Tie.Vine, true) && related_to(c, 0, Tie.Vine, true), "its tendril, and where it grows next");
    check(card_says(c, "Next it grows over the flask on its left"), "it names the next flask");
    c = explain_flask(b, 2);
    check(card_says(c, "Overgrown by the vine") && related_to(c, 1, Tie.Vine, false), "a tendril, tied to its root");
    c = explain_flask(b, 0);
    check(card_says(c, "The vine grows over it next, in 4 pours"), "the next to go under");

    test("a flask's card: salamander");
    b = row_of(["RG", "R", "R", "", "B"]);
    b.bottles[0] = rime(b.bottles[0], 9);
    b.bottles[4] = seal(b.bottles[4], 'G');
    b.salamander = 2;
    c = explain_flask(b, 2);
    check(card_says(c, "Salamander here: nothing can be poured in. It hops to the flask you pour from"), "the perch");
    check(blocked_says(c, "Can't pour into it while the Salamander sits on it"), "blocked in");
    check(related_to(c, 0, Tie.Salamander, true) && related_to(c, 4, Tie.Salamander, true) && c.related.len == 2,
          "it points at what its heat changes");
    c = explain_flask(b, 0);
    check(card_says(c, "the Salamander landing beside it") && related_to(c, 2, Tie.Salamander, false), "the ice knows it");
    c = explain_flask(b, 3);
    check(blocked_says(c, "Can't pour from it: it's empty"), "empty");
    b.bottles[3] = flask("RRRB");
    check(blocked_says(explain_flask(b, 3), "Can't pour into it: it's full"), "full");

    test("refusals");
    b = row_of(["RG", "R", "BB", "BBBB", "G", ""]);
    b.bottles[0] = rime(b.bottles[0], 2);
    b.salamander = 4;
    check(find(refusal(b, -1, 0)[..], "Frozen: thaws in 2 pours") == 0, "tapping ice");
    check(refusal(b, -1, 1).len == 0 && refusal(b, 1, 2) == "The colors must match.", "colors");
    check(refusal(b, 2, 3) == "That flask is full.", "full");
    check(find(refusal(b, 1, 4)[..], "The Salamander is on that flask") == 0, "the salamander");
    check(refusal(b, 2, 1) == "The colors must match." && refusal(b, 1, 1).len == 0, "and no reason for a pour that goes");
    check(refusal(b, 1, 5).len == 0, "a legal pour");

    test("every modifier has its words");
    for f in ALL_FEATURES {
        let h, found = campaign_hand_made(tutorial_level(f));
        let es = grimoire(h.board);
        let k = entry_of(es[..], f);
        check(k >= 0 && es[k].rule.len > 10 && es[k].flasks.len > 0 && es[k].name.len > 0,
              str(feature_name(f), " is in its tutorial's grimoire"));
        if k < 0 { continue; }
        for i in es[k].flasks {
            let cc = explain_flask(h.board, i);
            check(cc.title.len > 0 && cc.lines.len > 0, str(feature_name(f), ": its flask has a card"));
        }
    }

    test("the grimoire: what meets what");
    b = row_of(["RGB", "", "GBR", "YY", "QQ", "RRB"]);
    b.bottles[0] = rime(b.bottles[0], 3);
    b.bottles[1] = brazier(b.bottles[1]);
    b.bottles[2] = seal(b.bottles[2], 'R');
    b.bottles[5] = siphon(b.bottles[5]);
    es = grimoire(b);
    check(entry_of(es[..], Feature.Rime) >= 0 && entry_of(es[..], Feature.Seal) >= 0 && entry_of(es[..], Feature.Brazier) >= 0 &&
          entry_of(es[..], Feature.Quicksilver) >= 0 && entry_of(es[..], Feature.Siphon) >= 0 && es.len == 5,
          "only what is on the board");
    let bz = entry_of(es[..], Feature.Brazier);
    let n = effect_says(es[..], Feature.Brazier, "melts the ice beside it, and softens the seal beside it");
    check(n >= 0, "the brazier's heat");
    if n >= 0 {
        let x = es[bz].effects[n];
        check(x.flasks.len == 3 && contains(x.flasks[..], 0) && contains(x.flasks[..], 1) && contains(x.flasks[..], 2),
              "and its flasks");
        check(x.pairs.len == 2 && x.pairs[0].a == 1, "tied from the brazier");
    }
    check(effect_says(es[..], Feature.Quicksilver, "sinks to a siphon's tap") >= 0, "quicksilver in a siphon");
    check(effect_says(es[..], Feature.Brazier, "vine") < 0, "no vine where there is none");
    b = row_of(["RRR", "GBYG", "BB", ""]);
    b.bottles[0] = lantern(b.bottles[0]);
    b.bottles[1] = shroud(b.bottles[1]);
    b.bottles[3] = moonpetal(b.bottles[3]);
    es = grimoire(b);
    check(effect_says(es[..], Feature.Lantern, "lifts the shroud beside it") >= 0, "the lantern lifts the shroud");
    check(effect_says(es[..], Feature.Moonpetal, "opens once a lantern is lit") >= 0, "the moonpetal waits");
    for k in [9, 13, 17, 21, 25] {
        let h = hand_made(k);
        es = grimoire(h.board);
        var any = 0;
        for e in es { any += e.effects.len; for x in e.effects { check(x.flasks.len > 0 && x.text.len > 0, str("effects name flasks: ", x.text)); } }
        check(es.len >= 3 && any > 0, str(h.info.name, ": a finale's grimoire"));
    }
}

fn db(x: f64) -> f64 { 20.0 * log10(max(x, 1e-9)) }

// Every track decodes, a chunk at a time as the player reads it, whole and
// stereo at the mixer's rate; fades in from silence and out to it; and
// sits at the same level as the others.
fn test_music() {
    test("music");
    var chunk: f32[8192] = [0.0; 8192];
    var lo = 0.0;
    var hi = -200.0;
    for t in MUSIC_TRACKS {
        var bytes: u8[>..] = [];
        let path = str("assets/music/", track_name(t), ".ogg");
        check(read_file(path, bytes), str(path, " is there"));
        let d = dec_open(bytes);
        check(d >= 0 && dec_rate(d) == TRACK_RATE && dec_channels(d) == 2, str(path, " is stereo Ogg Vorbis at ", TRACK_RATE, " Hz"));
        let frames = dec_frames(d);
        check(frames > 180 * TRACK_RATE && frames < 240 * TRACK_RATE, str(path, " is the whole track: ", frames / TRACK_RATE, " s"));
        var got = 0;
        var sum = 0.0;
        var peak = 0.0;
        var start = 0.0;
        var end_sum = 0.0;
        loop {
            let n = dec_read(d, chunk);
            if n == 0 { break; }
            for i in 2 * n {
                let v = chunk[i] as f64;
                let frame = got + i / 2;
                sum += v * v;
                peak = max(peak, abs(v));
                if frame < TRACK_RATE / 200 { start = max(start, abs(v)); }
                if frame >= frames - TRACK_RATE / 10 { end_sum += v * v; }
            }
            got += n;
        }
        dec_close(d);
        let rms = db(sqrt(sum / (2 * got)));
        lo = min(lo, rms);
        hi = max(hi, rms);
        check(got == frames, str(path, " decodes to its length: ", got, " of ", frames));
        check(peak < 0.95 && rms > -26.0 && rms < -16.0, str(path, ": level ", rms, " dB, peak ", peak));
        check(start < 0.02, str(path, " fades in: ", start));
        check(db(sqrt(end_sum / (TRACK_RATE / 5))) < -40.0, str(path, " fades out to silence"));
    }
    check(hi - lo < 3.0, str("the tracks are equally loud, within ", hi - lo, " dB"));
    check(music_gain(0) == 0.0 && abs(music_gain(100) - 1.0) < 1e-9 && music_gain(MUSIC_DEFAULT) > 0.5 && music_gain(MUSIC_DEFAULT) < 0.6,
          "the volume's ends and its first place");
    var even = true;
    for p in 1..101 { if music_gain(p) <= music_gain(p - 1) { even = false; } }
    check(even, "the louder the slider, the louder the music");
    check(music_room(95, 6, 91) == 0 && music_room(106, 6, 91) == 1 && music_room(20, 1, 16) == 1, "rooms for the music");
    check(track_name(TITLE_TRACK) == "title_screen", "the title theme");
}

// A save written and read back is the same; the music's switch keeps the
// volume while it is off, and one from before the switch that turned the
// music off with a volume of 0 reads as switched off.
fn test_save_text() {
    test("saves");
    var s = Save { level: 37, sound: false, music: false, music_volume: 64, color_safe: true, seed_like: 55, last_seed: 99, window_w: 800, window_h: 1200 };
    let back = parse_save(save_text(s));
    check(back.level == 37 && !back.sound && !back.music && back.music_volume == 64 && back.color_safe && back.seed_like == 55 &&
          back.last_seed == 99 && back.window_w == 800 && back.window_h == 1200, "a save reads back as it was written");
    check(Save {}.music && Save {}.music_volume == MUSIC_DEFAULT, "a new save has the music on, at the first place");
    let on = parse_save("version=2\nlevel=5\nmusic=1\n");
    check(on.music && on.music_volume == MUSIC_DEFAULT, "an old save's music is on, at the first place");
    let off = parse_save("version=2\nlevel=5\nmusic=0\n");
    check(!off.music && off.music_volume == MUSIC_DEFAULT, "an old save's music off stays off");
    let zero = parse_save("version=2\nmusic_volume=0\n");
    check(!zero.music && zero.music_volume == MUSIC_DEFAULT, "a volume of 0 from before the switch is the switch off");
    check(parse_save("version=2\nlevel=5\n").music && parse_save("version=2\nlevel=5\n").music_volume == MUSIC_DEFAULT &&
          parse_save("").music_volume == MUSIC_DEFAULT, "a save without it gets the first place");
    check(parse_save("version=2\nmusic_volume=250\n").music_volume == 100, "the volume is kept in range");
}

fn main() {
    test_levels();
    test_pour_rules();
    test_grid();
    test_murk();
    test_split();
    test_vow();
    test_seal();
    test_tall();
    test_rime();
    test_heat();
    test_quicksilver();
    test_keys();
    test_light();
    test_hourglass();
    test_vine();
    test_salamander();
    test_drop();
    test_catalyst();
    test_validate();
    test_hash();
    test_undo_snapshot();
    test_solver();
    test_resumable();
    test_search_memory();
    test_generator();
    test_tools();
    test_campaign();
    test_generated_levels();
    test_difficulty();
    test_variants();
    test_saves();
    test_tables();
    test_explain();
    test_music();
    test_save_text();
    print(checks - failures, "/", checks, " checks passed");
    if failures > 0 { exit(1); }
}
