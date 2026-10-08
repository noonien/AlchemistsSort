// Unit tests for the rules, every modifier and how they meet, the solver,
// the generator and the shipped levels. Run with `nix flake check`, or
// `goose src/tests.goose`.

import std;
import os;
import core.board;
import core.solver;
import core.generator;
import core.levels;
import core.tools;
import core.campaign;
import app.shaders;
import app.tunes;

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

// The same, all on one shelf row, so flask i's neighbors are i - 1 and i + 1.
fn row_of(rows: const u8[:][:]) -> Board {
    var board = board_of(rows);
    board.per_row = MAX_BOTTLES;
    board
}

fn letters(b: Bottle) -> u8[..8] {
    var s: u8[..8] = [];
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

fn test_shelves() {
    test("shelves and neighbors");
    check(shelf_per_row(6, CAP) == 3 && shelf_per_row(9, CAP) == 5, "the layout's rows");
    var b = board_of(["RRRR", "GGGG", "", "", "", "", "", "", "", ""]);
    settle(b);
    let per = b.per_row;
    check(per == shelf_per_row(10, CAP), "settle fixes the row length");
    let l, r = neighbors(b, per - 1);
    check(l == per - 2 && r == -1, "the end of a row has no right neighbor");
    let l2, r2 = neighbors(b, per);
    check(l2 == -1 && r2 == per + 1, "the start of the next row has no left one");
    let l3, r3 = neighbors(b, 0);
    check(l3 == -1 && r3 == 1, "the first flask");
    for k in 6 { add_empty_bottle(b); }
    check(b.per_row == per, "extra flasks never change the rows");
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
    check(!pour(b, 1, 2).ok, "rejects another color");
    check(pour(b, 0, 3).ok, "reds into the spare");
    check(pour(b, 1, 3).ok && pour(b, 1, 2).ok, "red, then green into the vow flask");
    check(is_won(b) && b.bottles[2].done, "won once the vow flask is full");

    test("vow must end full");
    b = board_of(["RRRR", "GGGG", ""]);
    b.bottles[2].body = Body.Vow;
    settle(b);
    check(!is_won(b), "an empty vow flask blocks the win");
    check(!can_pour(b, 0, 2), "sealed bottles cannot fill it");

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
    check(can_pour(b, 2, 3), "it pours like any flask");
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

// --- chapter 3: siphons and twins --------------------------------------------------------

fn test_twins() {
    test("twin overflow");
    var b = row_of(["RRR", "BRR", "", "G"]);
    b.bottles[1].twin = 2;
    b.bottles[2].twin = 1;
    var r = pour(b, 0, 1);
    check(r.amount == 1 && r.overflow == 2 && letters(b.bottles[2]) == "RR", "the rest goes through the tube");
    check(has_event(r, EventKind.Overflowed, 2), "with an event");
    check(b.bottles[0].n == 0, "all of it moved");

    test("rime blocks the overflow");
    b = row_of(["RRR", "BRR", "", "G"]);
    b.bottles[1].twin = 2;
    b.bottles[2].twin = 1;
    b.bottles[2].cover = Cover.Rime;
    b.bottles[2].thaw = 5;
    r = pour(b, 0, 1);
    check(r.amount == 1 && r.overflow == 0 && letters(b.bottles[0]) == "RR", "no overflow into ice");

    test("twins must be neighbors");
    var v = board_of(["RRRR", "GGGG", "", ""]);
    v.per_row = 2;
    v.bottles[1].twin = 2;
    v.bottles[2].twin = 1;
    check(validate(v).len > 0, "not across rows");
    v.bottles[1].twin = 0;
    v.bottles[2].twin = -1;
    v.bottles[0].twin = 1;
    check(validate(v).len == 0, "side by side");
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
    t.bottles[1].cap = 5;
    check(validate(t).len == 0, "a tall color can be the short one");
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
    let big = generate(level_spec(60).params, level_spec(60).seed).board;
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
    boards.push(generate(level_spec(60).params, level_spec(60).seed).board);
    boards.push(generate(level_spec(45).params, level_spec(45).seed).board);
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
    let p = level_spec(70).params;
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
        let g = generate(GenParams { colors: 5, empties: 2, partial: 2 }, seed as u64);
        check(g.stats.solved, "generated levels are solvable");
        check(validate(g.board).len == 0, "and well formed");
        check(g.board.colors == 5, "with the colors asked for");
    }
    let a = generate(GenParams { colors: 6, empties: 2 }, 99);
    let b = generate(GenParams { colors: 6, empties: 2 }, 99);
    check(board_hash(a.board) == board_hash(b.board), "the same seed gives the same board");
    var path: Move[>..] = [];
    let p = GenParams { colors: 6, empties: 2, murk: 2, rime: 1, seal: 1, vow: 1 };
    let o = generate(p, 7);
    check(o.stats.solved && solve(o.board, 100000, path).solved, "modifiers stay solvable");

    // Each modifier, alone or with what it needs, for a few seeds.
    for which in 15 {
        var q = GenParams { colors: 5, empties: 2 };
        var name = "";
        match which {
            0 => { q.murk = 3; name = "murk"; },
            1 => { q.seal = 2; name = "seal"; },
            2 => { q.vow = 1; name = "vow"; },
            3 => { q.tall = 1; q.tall_height = 6; name = "tall"; },
            4 => { q.rime = 1; q.brazier = 1; name = "brazier"; },
            5 => { q.quicksilver = true; name = "quicksilver"; },
            6 => { q.siphon = 1; name = "siphon"; },
            7 => { q.twins = 1; name = "twins"; },
            8 => { q.shroud = 1; q.murk = 2; name = "shroud"; },
            9 => { q.hourglass = 1; q.murk = 2; name = "hourglass"; },
            10 => { q.vine = true; q.brazier = 1; name = "vine"; },
            11 => { q.salamander = true; q.rime = 1; name = "salamander"; },
            12 => { q.moonpetal = 1; name = "moonpetal"; },
            13 => { q.athanor = true; name = "athanor"; },
            _ => { q.drop = true; q.catalyst = 1; q.lantern = 1; name = "drop and catalyst"; },
        }
        for seed in 1..4 {
            let g = generate(q, seed as u64 * 31);
            check(g.stats.solved && g.attempts <= 400 && validate(g.board).len == 0, str(name, " is generated"));
            check(has_modifier(g.board, which), str(name, " is on the board, seed ", seed));
            check(solve(g.board, 100000, path).solved, str(name, " can be won"));
        }
        let x = generate(q, 5);
        let y = generate(q, 5);
        check(board_hash(x.board) == board_hash(y.board), str(name, ": the same seed gives the same board"));
    }
}

// Whether the generator's test case `which` put its modifier on the board.
fn has_modifier(board: Board, which: i64) -> bool {
    var tally: i64[MAX_LIQUID + 1] = [0; MAX_LIQUID + 1];
    for i in board.count { for k in board.bottles[i].n as i64 { tally[board.bottles[i].seg[k]]++; } }
    for i in board.count {
        let b = board.bottles[i];
        let l, r = neighbors(board, i);
        let ok = match which {
            0 => b.murk != 0,
            1 => b.cover == Cover.Seal,
            2 => b.body == Body.Vow,
            3 => b.cap > CAP,
            4 => b.fixture == Fixture.Brazier && ((l >= 0 && board.bottles[l].cover == Cover.Rime) ||
                                                  (r >= 0 && board.bottles[r].cover == Cover.Rime)),
            5 => tally[QUICKSILVER] == CAP,
            6 => b.body == Body.Siphon,
            7 => b.twin >= 0 && are_neighbors(board, i, b.twin),
            8 => b.cover == Cover.Shroud,
            9 => b.body == Body.Hourglass,
            10 => b.fixture == Fixture.VineRoot && tally[EMERALD] > 0,
            11 => board.salamander >= 0,
            12 => b.body == Body.Moonpetal,
            13 => b.body == Body.Athanor && tally[QUICKSILVER] > 0,
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
    check(level_spec(1).hand_made, "level one is hand-made");
    for f in ALL_FEATURES {
        let s = level_spec(tutorial_level(f));
        check(s.is_tutorial && s.tutorial == f && s.hand_made && s.difficulty == Difficulty.Normal,
              "tutorial levels");
        check(!introduced(f, tutorial_level(f) - 1), "nothing used before its tutorial");
    }
    check(level_spec(15).difficulty == Difficulty.Hard && level_spec(30).difficulty == Difficulty.SuperHard,
          "tags");
    check(level_spec(23).params.colors <= level_spec(70).params.colors, "colors ramp up");
    for n in 2..13 {
        let p = level_spec(n).params;
        check(p.seal + p.rime + p.shroud + p.vow == 0, "no mechanical modifier before the vow tutorial");
    }
    let t0 = clock();
    var worst = 0.0;
    var worst_level = 0;
    for n in 2..61 {
        let spec = level_spec(n);
        if spec.hand_made { continue; }
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
    for x, i in ALL_BODIES { check(body_index(x) == i, "ALL_BODIES is in index order"); }
    for x, i in ALL_COVERS { check(cover_index(x) == i, "ALL_COVERS is in index order"); }
    for x, i in ALL_FIXTURES { check(fixture_index(x) == i, "ALL_FIXTURES is in index order"); }
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
    check(color_of_letter('Q') == QUICKSILVER && color_of_letter('U') == GOLD && color_of_letter('*') == DROP,
          "the special liquids' letters");
}

// --- shipped levels -------------------------------------------------------------------

// Every hand-made level is well formed and can be won.
fn test_levels() {
    test("shipped levels");
    for k in HAND_MADE_COUNT {
        let h = hand_made(k);
        let name = h.info.name;
        let err = validate(h.board);
        check(err.len == 0, str(name, ": ", err));
        check(h.info.hint.len > 0, str(name, " has a hint"));
        check(h.board.per_row > 0 && !is_won(h.board), str(name, " is settled and not yet won"));
        var moves: Move[>..] = [];
        check(solve(h.board, 200000, moves).solved, str(name, " can be won"));
        if h.number > 0 {
            let back, found = campaign_hand_made(h.number);
            check(found && back.info.name == name, str(name, " is found by its number"));
        }
    }
}

// --- music ------------------------------------------------------------------------

// A short loop (four bars of each of two rooms): its end runs on into its
// start, and it stays under full scale.
fn test_music() {
    test("music");
    var notes: Note[>..] = [];
    var pcm: f32[>..] = [];
    for room in [0, 5] {
        var job = tune_begin(room, 4, notes, pcm);
        while !tune_step(job, notes, pcm, 1.0) {}
        check(pcm.len == job.period && notes.len > 0, "a whole loop is made");
        var peak = 0.0;
        var step = 0.0;
        for v, i in pcm {
            peak = max(peak, abs(v as f64));
            if i > 0 { step = max(step, abs(v - pcm[i - 1])); }
        }
        let last = pcm.len - 1;
        let wrap = abs(pcm[0] - pcm[last]) as f64;
        let bend = abs((pcm[0] - pcm[last]) - (pcm[last] - pcm[last - 1])) as f64;
        check(peak > 0.05 && peak < 0.9, str("the peak is under 0.9: ", peak));
        check(wrap <= step && bend < 0.01, str("the loop point is smooth: ", wrap, " ", bend));
    }
    check(music_room(95, 6, 91) == 0 && music_room(106, 6, 91) == 1 && music_room(20, 1, 16) == 1, "rooms for the music");
}

fn main() {
    test_levels();
    test_pour_rules();
    test_shelves();
    test_murk();
    test_split();
    test_vow();
    test_seal();
    test_tall();
    test_rime();
    test_heat();
    test_quicksilver();
    test_twins();
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
    test_tables();
    test_music();
    print(checks - failures, "/", checks, " checks passed");
    if failures > 0 { exit(1); }
}
