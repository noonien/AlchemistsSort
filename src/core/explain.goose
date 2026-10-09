// The board in words: what each modifier on a level does and how they meet
// (the Grimoire), what one flask is and why it can't pour right now (a
// flask's card, and the message a refused pour shows), and what a pour
// would set off. Nothing here draws; the game shows these, the tests read
// them. Every sentence a player reads about the rules comes from here.

import std;
import .board;
import .campaign;

// How two flasks are tied.
enum Tie {
    Heat,       // a brazier's or the salamander's heat
    Light,      // a lantern's light, or a moonpetal waiting on one
    Key,        // a key and the door it opens
    Vine,       // a vine's root, its tendrils and where it grows next
    Salamander, // the salamander's perch
    Catalyst,   // what a catalyst sets off
    Flow,       // where quicksilver goes, a seal's key, the Drop
}

let ALL_TIES: const Tie[7] = [Tie.Heat, Tie.Light, Tie.Key, Tie.Vine, Tie.Salamander, Tie.Catalyst, Tie.Flow];

fn tie_index(t: Tie) -> i64 {
    match t { Heat => 0, Light => 1, Key => 2, Vine => 3, Salamander => 4, Catalyst => 5, Flow => 6 }
}

let TEXT_CAP = 160;

// --- a flask's card ---------------------------------------------------------------------

enum LineKind {
    State,      // what it is and how it stands
    Blocked,    // what it can't do now, and what would change that
}

struct Line { kind: LineKind = LineKind.State, text: u8[..160] = [] }

// Another flask tied to this one: `acts` when this one acts on it, else it
// acts on this one.
struct Related { flask: i64 = -1, tie: Tie = Tie.Heat, acts: bool = true }

struct Card {
    flask: i64 = -1,
    title: u8[..80] = [],       // what it is: its parts' names
    lines: Line[..10] = [],
    related: Related[..24] = [],
}

// --- the Grimoire ----------------------------------------------------------------------------

struct Pair { a: i64 = -1, b: i64 = -1, tie: Tie = Tie.Heat }

// One way a modifier meets another on this board, and the flasks it involves.
struct Effect {
    text: u8[..160] = [],
    flasks: i64[..MAX_BOTTLES] = [],
    pairs: Pair[..16] = [],
}

// A modifier on the board: its rule, the flasks that have it, and what it
// does to the others here.
struct Entry {
    feature: Feature = Feature.Murk,
    name: u8[..40] = [],
    rule: u8[..160] = [],
    flasks: i64[..MAX_BOTTLES] = [],
    effects: Effect[..6] = [],
}

// --- words -------------------------------------------------------------------------------

fn color_name(c: i64) -> const u8[:] { COLOR_NAMES[clamp(c, 0, COLOR_NAMES.len - 1)] }

// "a Ruby", "an Amber".
fn a_color(c: i64) -> u8[>..] {
    let name = color_name(c);
    let vowel = name.len > 0 && (name[0] == 'A' || name[0] == 'E' || name[0] == 'I' || name[0] == 'O' || name[0] == 'U');
    str(if vowel { "an " } else { "a " }, name)
}

fn pours_left(n: i64) -> u8[>..] { str(n, if n == 1 { " pour" } else { " pours" }) }

fn put(dst: u8[..160]&, s: const u8[:]) {
    dst.clear();
    dst.append(s[..min(TEXT_CAP, s.len)]);
}

fn capitalized(s: const u8[:]) -> u8[>..] {
    var out = str(s);
    if out.len > 0 && out[0] >= 'a' && out[0] <= 'z' { out[0] = out[0] - 32; }
    out
}

// The board with its flasks in the grid, for left and right.
fn placed(board: Board) -> Board {
    var b = board;
    if b.rows == 0 { place_grid(b); }
    b
}

// Where flask j stands from flask i: "on its left", "on its right", or
// "beside it" (a tall flask).
fn side_of(board: Board, i: i64, j: i64) -> const u8[:] {
    let bd = placed(board);
    if rows_of(bd.bottles[i].cap) == 1 && rows_of(bd.bottles[j].cap) == 1 {
        if bd.col[j] < bd.col[i] { return "on its left"; }
        if bd.col[j] > bd.col[i] { return "on its right"; }
    }
    "beside it"
}

// "the Brazier on its left", or "a Brazier beside it" when there are two.
fn which_one(board: Board, i: i64, ones: const i64[:], what: const u8[:]) -> u8[>..] {
    if ones.len == 1 { return str("the ", what, " ", side_of(board, i, ones[0])); }
    str("the ", what, "s beside it")
}

fn has_liquid(b: Bottle, c: i64) -> bool {
    for k in b.n as i64 { if b.seg[k] == c { return true; } }
    false
}

fn any_liquid(board: Board, c: i64) -> bool {
    for i in board.count { if has_liquid(board.bottles[i], c) { return true; } }
    false
}

fn murk_count(b: Bottle) -> i64 {
    var n = 0;
    for k in b.n as i64 { if murky(b, k) { n++; } }
    n
}

// Covers heat changes: ice, wax and vine.
fn heat_takes(b: Bottle) -> bool {
    !b.done && (b.cover == Cover.Rime || b.cover == Cover.Seal || b.cover == Cover.Vine)
}

// The flasks beside `i` with a fixture.
fn beside_with(board: Board, i: i64, f: Fixture) -> i64[..6] {
    var out: i64[..6] = [];
    for j in neighbors(board, i) { if board.bottles[j].fixture == f { out.push(j); } }
    out
}

// The flask a creeping vine at `root` grows over next, or -1: its spread
// tried on a copy.
fn next_tendril(board: Board, root: i64) -> i64 {
    var b = board;
    var r = PourResult {};
    spread(b, root, r);
    for e in r.events { if e.kind == EventKind.VineSpread { return e.bottle; } }
    -1
}

fn vine_root(board: Board) -> i64 {
    for i in board.count { if board.bottles[i].fixture == Fixture.VineRoot { return i; } }
    -1
}

// "brass", for a sentence.
fn metal(k: KeyColor) -> u8[>..] {
    var s = str(key_name(k));
    if s.len > 0 { s[0] = s[0] + 32; }
    s
}

// The flask holding the key to door d, or -1.
fn key_flask(board: Board, d: i64) -> i64 {
    if d < 0 || d >= board.door_count { return -1; }
    for i in board.count { if board.bottles[i].key_color == board.doors[d].color { return i; } }
    -1
}

fn behind_door_of(board: Board, d: i64) -> i64[..MAX_BOTTLES] {
    var out: i64[..MAX_BOTTLES] = [];
    for i in board.count { if board.bottles[i].door == d { out.push(i); } }
    out
}

// What a shut door means for flask `i` and what opens it.
fn door_reason(board: Board, i: i64) -> u8[>..] {
    let d: i64 = board.bottles[i].door;
    let m = metal(board.doors[d].color);
    str("Behind the ", m, " door: opens when the ", m, " key reaches the top of its flask.")
}

// Where a flask's key is, in words.
fn key_words(b: Bottle) -> u8[>..] {
    let m = metal(b.key_color);
    let k = key_segment(b);
    let tap = if b.body == Body.Siphon { ", or let it out of the tap" } else { "" };
    if k >= 0 && murky(b, k) {
        return str(capitalized(m), " key: hidden in the smoke; it comes free when its layer reaches the top", tap, ".");
    }
    let n = layers_over_key(b);
    str(capitalized(m), " key: buried under ", n, if n == 1 { " layer" } else { " layers" },
        "; clear ", if n == 1 { "it" } else { "them" }, tap, " to unlock the ", m, " door.")
}

// --- why it can't pour -------------------------------------------------------------------

// What a cover means for flask `i` and what takes it away, as a sentence.
// Empty when it has none.
fn cover_reason(board: Board, i: i64) -> u8[>..] {
    let b = board.bottles[i];
    let heat = beside_with(board, i, Fixture.Brazier);
    // Heat that reaches it: "the Brazier on its left", or the salamander.
    var by: u8[>..] = [];
    if heat.len > 0 { by.append(str("each pour into ", which_one(board, i, heat, "Brazier"))); }
    if board.salamander >= 0 {
        if by.len > 0 { by.append(", or "); }
        by.append("the Salamander landing beside it");
    }
    match b.cover {
        Rime => {
            let t: i64 = b.thaw;
            if by.len > 0 { return str("Frozen: thaws in ", pours_left(t), ". Sooner with heat: ", by, " melts one more."); }
            str("Frozen: thaws in ", pours_left(t), " made anywhere.")
        },
        Seal => {
            let key = color_name(b.key);
            let drop = if any_liquid(board, DROP) { " (or the Drop)" } else { "" };
            if b.soft > 0 { return str("Sealed with ", key, " wax, softened: pour ", key, drop, " onto it, or heat it once more."); }
            if by.len > 0 { return str("Sealed with ", key, " wax: pour ", key, drop, " onto it, or heat it twice. Heat comes from ", by, "."); }
            str("Sealed with ", key, " wax: pour ", key, drop, " onto it, or heat it twice.")
        },
        Shroud => {
            let lamps = beside_with(board, i, Fixture.Lantern);
            var s = if lamps.len > 0 { str("Shrouded: hidden until ", which_one(board, i, lamps, "Lantern"), " lights. Complete its flask.") }
                    else { str("Shrouded: hidden until a lantern's light reaches it.") };
            for c in board.count {
                let x = board.bottles[c];
                if x.fixture == Fixture.Catalyst && !x.spent { s.append(" The Catalyst lights every lantern too."); break; }
            }
            s
        },
        Vine => {
            if by.len > 0 { return str("Overgrown by the vine: heat burns it away (", by, "), or pour Emerald into the root to wither the vine."); }
            str("Overgrown by the vine: heat burns it away, or pour Emerald into the root to wither the vine.")
        },
        Curtain => str("Curtain: opens when ", a_color(b.badge), " flask is completed."),
        None => str(""),
    }
}

// A cover's short "until": what has to happen first.
fn cover_until(b: Bottle) -> const u8[:] {
    match b.cover {
        Rime => "until it thaws",
        Seal => "until the seal breaks",
        Shroud => "until light lifts the shroud",
        Vine => "until the vine is gone",
        Curtain => "until the curtain opens",
        None => "",
    }
}

// Why a pour from flask `from` (or a first tap, when `from` is -1) into `to`
// is turned away, as the message a refused tap shows; empty when it would
// go, or when there is nothing to say (an empty flask tapped first).
fn refusal(board: Board, from: i64, to: i64) -> u8[>..] {
    let b = board.bottles[to];
    if from < 0 || from == to {
        if b.done { return str("That flask is complete and sealed."); }
        if b.behind { return door_reason(board, to); }
        if covered(b) { return cover_reason(board, to); }
        if b.cap > CAP { return str("Nothing comes out of a tall flask. It only takes ", color_name(tall_color(b)), "."); }
        return str("");
    }
    let color = pour_color(board.bottles[from]);
    if can_pour(board, from, to) { return str(""); }
    if b.done { return str("That flask is complete and sealed."); }
    if b.behind { return door_reason(board, to); }
    if covered(b) { return cover_reason(board, to); }
    if to == board.salamander { return str("The Salamander is on that flask: nothing goes in until it hops off."); }
    if b.body == Body.Moonpetal && !any_lantern_lit(board) { return str("A Moonpetal takes liquid only once a lantern is lit."); }
    if b.n >= b.cap { return str("That flask is full."); }
    if b.cap > CAP { return str("This tall flask only takes ", color_name(tall_color(b)), "."); }
    if b.body == Body.Vow && b.vow != 0 && color != b.vow && color != DROP {
        return str("This Vow Flask only takes ", color_name(b.vow), ".");
    }
    if b.body == Body.Athanor && color == QUICKSILVER {
        return str("The Athanor turns quicksilver to gold only onto gold, or when empty.");
    }
    str("The colors must match.")
}

// --- a flask's card ------------------------------------------------------------------------

// What flask `i` is, how it stands, why it can't pour now and what would
// change that, and the flasks tied to it.
fn explain_flask(board_in: Board, i: i64) -> Card {
    let board = placed(board_in);
    var card = Card { flask: i };
    if i < 0 || i >= board.count { return card; }
    let b = board.bottles[i];
    fn line(kind: LineKind, s: const u8[:]) {
        if card.lines.len >= card.lines.cap { return; }
        var l = Line { kind: kind };
        put(l.text, s);
        card.lines.push(l);
    }
    fn relate(j: i64, tie: Tie, acts: bool) {
        if j < 0 || j == i || card.related.len >= card.related.cap { return; }
        for r in card.related { if r.flask == j && r.tie == tie { return; } }
        card.related.push(Related { flask: j, tie: tie, acts: acts });
    }
    fn name(s: const u8[:]) {
        if card.title.len + s.len + 3 > card.title.cap { return; }
        if card.title.len > 0 { card.title.append(" · "); }
        card.title.append(s);
    }

    // What it is.
    match b.body {
        Vow => name("Vow Flask"), Siphon => name("Siphon"), Hourglass => name("Hourglass"),
        Athanor => name("Athanor"), Moonpetal => name("Moonpetal"), Plain => {},
    }
    if b.cap > CAP { name("Tall Flask"); }
    match b.cover {
        Seal => name("Seal"), Rime => name("Rime"), Shroud => name("Shroud"), Vine => name("Vine"),
        Curtain => name("Curtain"), None => {},
    }
    match b.fixture {
        Brazier => name("Brazier"), Lantern => name("Lantern"), Catalyst => name("Catalyst"),
        VineRoot => name("Vine Root"), None => {},
    }
    if b.behind { name("Behind a Door"); }
    if b.key_color != KeyColor.None && !contents_hidden(b) { name("Key"); }
    if i == board.salamander { name("Salamander"); }
    if b.murk != 0 && !contents_hidden(b) { name("Smoke"); }
    if card.title.len == 0 { name(if b.done { "Complete" } else { "Flask" }); }

    if b.done { line(LineKind.State, "Complete and sealed: nothing more to do here."); }

    // A shut door before it, and the key that opens it.
    if b.behind {
        line(LineKind.State, door_reason(board, i));
        relate(key_flask(board, b.door), Tie.Key, false);
        for j in behind_door_of(board, b.door) { relate(j, Tie.Key, true); }
    }

    // Its cover, and what warms or lights it.
    if b.cover != Cover.None && !b.done {
        line(LineKind.State, cover_reason(board, i));
        if heat_takes(b) {
            for j in beside_with(board, i, Fixture.Brazier) { relate(j, Tie.Heat, false); }
            if board.salamander >= 0 { relate(board.salamander, Tie.Salamander, false); }
        }
        if b.cover == Cover.Shroud {
            for j in beside_with(board, i, Fixture.Lantern) { relate(j, Tie.Light, false); }
        }
        if b.cover == Cover.Vine {
            let root = vine_root(board);
            relate(root, Tie.Vine, false);
        }
    }
    if i == board.salamander {
        line(LineKind.State, "Salamander here: nothing can be poured in. It hops to the flask you pour from and warms it and the flasks beside it.");
        for j in board.count { if heat_takes(board.bottles[j]) { relate(j, Tie.Salamander, true); } }
    }

    // Its body.
    match b.body {
        Vow => {
            if b.done {} else if b.vow != 0 {
                line(LineKind.State, str("Vow Flask: sworn to ", color_name(b.vow), ". It takes only that."));
            } else {
                line(LineKind.State, "Vow Flask: takes the first color poured in, then only that. It can stay empty.");
            }
        },
        Siphon => if !b.done {
            if b.n > 0 && !covered(b) {
                line(LineKind.State, str("Siphon: pours from the tap at its base. Next out: ", pour_run(b), " ",
                                         color_name(pour_color(b)), "."));
            } else {
                line(LineKind.State, "Siphon: pours from the tap at its base, bottom layer first.");
            }
        },
        Hourglass => if !b.done {
            let left: i64 = b.flip_every - b.flip_count;
            if covered(b) { line(LineKind.State, "Hourglass: held still while covered; it counts no pours until it's free."); }
            else {
                line(LineKind.State, str("Hourglass: flips in ", pours_left(left), ", made anywhere."));
                // What comes up, when it is in plain view.
                if b.n > 1 && !murky(b, 0) && !has_liquid(b, QUICKSILVER) && b.seg[0] != b.seg[b.n - 1] {
                    line(LineKind.State, str("When it flips, ", color_name(b.seg[0]), " comes to the top."));
                }
            }
        },
        Athanor => if !b.done {
            line(LineKind.State, "Athanor: quicksilver poured in turns to gold, onto gold or when it's empty.");
            for j in board.count { if j != i && has_liquid(board.bottles[j], QUICKSILVER) { relate(j, Tie.Flow, false); } }
        },
        Moonpetal => if !b.done {
            if any_lantern_lit(board) { line(LineKind.State, "Moonpetal: open, now that a lantern is lit."); }
            else { line(LineKind.State, "Moonpetal: closed until a lantern is lit."); }
            for j in board.count { if board.bottles[j].fixture == Fixture.Lantern { relate(j, Tie.Light, false); } }
        },
        Plain => {},
    }
    if b.cap > CAP && !b.done {
        line(LineKind.State, str("Tall Flask: holds ", b.cap, ". Only ", color_name(tall_color(b)), " goes in, and nothing comes out."));
    }

    // What stands by it.
    match b.fixture {
        Brazier => {
            var hit: u8[>..] = [];
            for j in neighbors(board, i) {
                let x = board.bottles[j];
                relate(j, Tie.Heat, true);
                if !heat_takes(x) { continue; }
                let what = match x.cover { Rime => "the ice", Seal => "the seal", Vine => "the vine", Shroud, Curtain, None => "" };
                if hit.len > 0 { hit.append(" and "); }
                hit.append(str(what, " ", side_of(board, i, j)));
            }
            if hit.len > 0 { line(LineKind.State, str("Brazier: each pour into it warms the flasks beside it: ", hit, ".")); }
            else { line(LineKind.State, "Brazier: each pour into it warms the flasks beside it."); }
        },
        Lantern => {
            if b.lit { line(LineKind.State, "Lantern: lit. Its light reaches the flasks beside it."); }
            else {
                var lifts: u8[>..] = [];
                for j in neighbors(board, i) {
                    let x = board.bottles[j];
                    if x.cover == Cover.Shroud { lifts.append(str(if lifts.len > 0 { " and " } else { "" }, "the Shroud ", side_of(board, i, j))); }
                }
                if lifts.len > 0 { line(LineKind.State, str("Lantern: lights when this flask is completed, and lifts ", lifts, ".")); }
                else { line(LineKind.State, "Lantern: lights when this flask is completed; its light clears smoke beside it."); }
            }
            for j in neighbors(board, i) {
                let x = board.bottles[j];
                if x.cover == Cover.Shroud || x.murk != 0 { relate(j, Tie.Light, true); }
            }
            for j in board.count { if board.bottles[j].body == Body.Moonpetal { relate(j, Tie.Light, true); } }
        },
        Catalyst => {
            if b.spent { line(LineKind.State, "Catalyst: spent."); }
            else {
                var what: u8[>..] = [];
                fn add(f: bool, s: const u8[:]) {
                    if !f { return; }
                    if what.len > 0 { what.append(", "); }
                    what.append(s);
                }
                var braziers = false;
                var glasses = false;
                var lanterns = false;
                for j in board.count {
                    let x = board.bottles[j];
                    if x.fixture == Fixture.Brazier { braziers = true; relate(j, Tie.Catalyst, true); }
                    if can_flip(x) { glasses = true; relate(j, Tie.Catalyst, true); }
                    if x.fixture == Fixture.Lantern && !x.lit { lanterns = true; relate(j, Tie.Catalyst, true); }
                }
                add(braziers, "every brazier warms");
                add(glasses, "every hourglass flips");
                add(lanterns, "every lantern lights");
                if what.len > 0 { line(LineKind.State, str("Catalyst: when this flask is completed, ", what, ".")); }
                else { line(LineKind.State, "Catalyst: goes off when this flask is completed."); }
            }
        },
        VineRoot => {
            let left: i64 = b.spread_every - b.spread_count;
            line(LineKind.State, str("Vine root: spreads in ", pours_left(left), ". Pour Emerald in to wither the vine."));
            for j in board.count { if board.bottles[j].cover == Cover.Vine { relate(j, Tie.Vine, true); } }
            let next = next_tendril(board, i);
            if next >= 0 {
                let spot = if are_neighbors(board, i, next) { side_of(board, i, next) } else { "beside a tendril" };
                line(LineKind.State, str("Next it grows over the flask ", spot, "."));
            }
            relate(next, Tie.Vine, true);
        },
        None => {},
    }
    if b.cover == Cover.Vine { for j in board.count { if board.bottles[j].cover == Cover.Vine { relate(j, Tie.Vine, true); } } }
    let root = vine_root(board);
    if root >= 0 && b.cover == Cover.None && !b.done && next_tendril(board, root) == i {
        let left: i64 = board.bottles[root].spread_every - board.bottles[root].spread_count;
        line(LineKind.State, str("The vine grows over it next, in ", pours_left(left), "."));
        relate(root, Tie.Vine, false);
    }

    // Its key, and the door it opens.
    if b.key_color != KeyColor.None && !contents_hidden(b) {
        line(LineKind.State, key_words(b));
        for j in behind_door_of(board, door_of(board, b.key_color)) { relate(j, Tie.Key, true); }
    }

    // What is in it.
    let hidden = contents_hidden(b);
    if !hidden && !b.done {
        let m = murk_count(b);
        if m > 0 {
            var lantern = false;
            for j in beside_with(board, i, Fixture.Lantern) {
                if !board.bottles[j].lit { relate(j, Tie.Light, false); lantern = true; }
            }
            if b.fixture == Fixture.Lantern && !b.lit { lantern = true; }
            line(LineKind.State, str(m, if m == 1 { " layer is" } else { " layers are" },
                                     " hidden in smoke; each clears when it reaches the top",
                                     if lantern { ", and all of it clears when the lantern lights." } else { "." }));
        }
        if has_liquid(b, QUICKSILVER) {
            if has_body(board, Body.Athanor) { line(LineKind.State, "Quicksilver: it sinks, and must all become gold in the Athanor."); }
            else { line(LineKind.State, "Quicksilver: it sinks below other liquids."); }
            for j in board.count { if board.bottles[j].body == Body.Athanor { relate(j, Tie.Flow, true); } }
        }
        if has_liquid(b, DROP) { line(LineKind.State, "The Philosopher's Drop: a wild layer that counts as any color."); }
        if card.lines.len == 0 {
            if b.n == 0 { line(LineKind.State, "Empty: takes any color."); }
            else { line(LineKind.State, str("Holds ", b.n, " of ", b.cap, ".")); }
        }
    }

    // What it can't do now.
    if !b.done {
        var from_why: u8[>..] = [];
        var into_why: u8[>..] = [];
        if b.behind { from_why.append(str("until the ", metal(board.doors[b.door].color), " door opens")); }
        else if covered(b) { from_why.append(cover_until(b)); }
        else if b.n == 0 { from_why.append(": it's empty"); }
        if b.behind { into_why.append(from_why); }
        else if b.cover == Cover.Seal {
            into_why.append(str(": only ", color_name(b.key), if any_liquid(board, DROP) { " or the Drop" } else { "" },
                                " can go on, and it breaks the seal"));
        }
        else if covered(b) { into_why.append(cover_until(b)); }
        else if i == board.salamander { into_why.append("while the Salamander sits on it"); }
        else if b.body == Body.Moonpetal && !any_lantern_lit(board) { into_why.append("until a lantern is lit"); }
        else if b.n >= b.cap { into_why.append(": it's full"); }
        fn spaced(s: const u8[:]) -> u8[>..] { if s.len > 0 && s[0] == ':' { str(s) } else { str(" ", s) } }
        if from_why.len > 0 && from_why == into_why {
            line(LineKind.Blocked, str("Can't pour in or out", spaced(from_why), "."));
        } else {
            if from_why.len > 0 { line(LineKind.Blocked, str("Can't pour from it", spaced(from_why), ".")); }
            if into_why.len > 0 { line(LineKind.Blocked, str("Can't pour into it", spaced(into_why), ".")); }
        }
    }
    card
}

// --- the Grimoire ------------------------------------------------------------------------------

fn rule_of(f: Feature) -> const u8[:] {
    match f {
        Murk => "Smoke hides layers. Each clears when it reaches the top, or when a lit lantern's light reaches its flask.",
        Seal => "Wax hides what's inside. Pour its color onto it to break it; two warmings break it too.",
        Tall => "Holds more than four, all of its own color: only that color goes in, and nothing comes out.",
        Vow => "Takes the first color poured in, then only that. It can stay empty.",
        Rime => "Ice keeps a flask shut. Its number counts down with every pour, made anywhere; at 0 it thaws.",
        Brazier => "Each pour into its flask warms the flasks beside it.",
        Quicksilver => "Pours onto any color, and sinks to the bottom.",
        Siphon => "Pours from the tap at its base: the bottom layer comes out first.",
        Keys => "A key sits in a layer. When that layer reaches the top, the key comes free and opens the door of its metal; the flasks behind join the board.",
        Curtain => "Hides a flask and keeps it shut until a flask of the color on its badge is completed.",
        Lantern => "Lights when its flask is completed. Its light reaches the flasks beside it.",
        Shroud => "Hides a flask and keeps it shut until a lantern beside it lights.",
        Hourglass => "Turns over after the pours on its dial, made anywhere.",
        Vine => "Every few pours it grows over a flask next to it, shutting it.",
        Salamander => "Nothing goes into its flask. After each pour it hops to the flask you poured from.",
        Moonpetal => "Takes liquid only while a lantern is lit.",
        Athanor => "Turns quicksilver poured into it into gold.",
        Drop => "A wild layer: it goes on any color, takes any color, and counts as any color.",
        Catalyst => "When its flask is completed, it sets off every brazier, hourglass and lantern.",
    }
}

// Whether flask i has feature f.
fn flask_has(board: Board, i: i64, f: Feature) -> bool {
    let b = board.bottles[i];
    match f {
        Murk => b.murk != 0,
        Seal => b.cover == Cover.Seal,
        Tall => b.cap > CAP,
        Vow => b.body == Body.Vow,
        Rime => b.cover == Cover.Rime,
        Brazier => b.fixture == Fixture.Brazier,
        Quicksilver => has_liquid(b, QUICKSILVER) || (b.body == Body.Athanor && has_liquid(b, GOLD)),
        Siphon => b.body == Body.Siphon,
        Keys => b.key_color != KeyColor.None || b.behind,
        Curtain => b.cover == Cover.Curtain,
        Lantern => b.fixture == Fixture.Lantern,
        Shroud => b.cover == Cover.Shroud,
        Hourglass => b.body == Body.Hourglass,
        Vine => b.fixture == Fixture.VineRoot || b.cover == Cover.Vine,
        Salamander => i == board.salamander,
        Moonpetal => b.body == Body.Moonpetal,
        Athanor => b.body == Body.Athanor,
        Drop => has_liquid(b, DROP),
        Catalyst => b.fixture == Fixture.Catalyst,
    }
}

// The modifiers on this board, in the order the campaign brings them in,
// each with its rule and only the ways it meets the others here.
fn grimoire(board_in: Board) -> Entry[..19] {
    let board = placed(board_in);
    var out: Entry[..19] = [];
    for f in ALL_FEATURES {
        var e = Entry { feature: f };
        for i in board.count { if flask_has(board, i, f) { e.flasks.push(i); } }
        if e.flasks.len == 0 { continue; }
        let name = if f == Feature.Quicksilver && has_body(board, Body.Athanor) { "Quicksilver and Gold" } else { feature_name(f) };
        e.name.append(name);
        put(e.rule, rule_of(f));
        out.push(e);
    }
    // Adds an effect to feature f's entry: the same words twice become one
    // effect with both sets of flasks.
    fn effect(f: Feature, text: const u8[:], pairs: const Pair[:]) {
        for &e in out {
            if e.feature != f { continue; }
            var at = -1;
            for x, k in e.effects { if x.text[..] == text { at = k; } }
            if at < 0 {
                if e.effects.len >= e.effects.cap { return; }
                var x = Effect {};
                put(x.text, text);
                e.effects.push(x);
                at = e.effects.len - 1;
            }
            var x .= e.effects[at];
            for p in pairs {
                if x.pairs.len < x.pairs.cap { x.pairs.push(p); }
                for j in [p.a, p.b] { if j >= 0 && !contains(x.flasks[..], j) { x.flasks.push(j); } }
            }
        }
    }
    let root = vine_root(board);
    var drop_at = -1;
    for i in board.count { if has_liquid(board.bottles[i], DROP) { drop_at = i; } }

    for i in board.count {
        let b = board.bottles[i];
        // A brazier's heat on the covers beside it.
        if b.fixture == Fixture.Brazier {
            var pairs: Pair[..6] = [];
            var ice = false;
            var wax = false;
            var vine = false;
            var reach = false;
            for j in neighbors(board, i) {
                let x = board.bottles[j];
                if heat_takes(x) { pairs.push(Pair { a: i, b: j, tie: Tie.Heat }); }
                if x.done { continue; }
                if x.cover == Cover.Rime { ice = true; }
                if x.cover == Cover.Seal { wax = true; }
                if x.cover == Cover.Vine { vine = true; }
                if root >= 0 && j != root && x.cover == Cover.None { reach = true; }
            }
            var s = str("Brazier: each pour into it");
            var parts = 0;
            fn also(w: const u8[:]) {
                s.append(if parts == 0 { " " } else { ", and " });
                s.append(w);
                parts++;
            }
            if ice { also("melts the ice beside it"); }
            if wax { also("softens the seal beside it"); }
            if vine { also("burns the vine beside it"); }
            else if reach { also("burns the vine if it creeps beside it"); }
            if parts > 0 {
                s.append(".");
                effect(Feature.Brazier, s, pairs);
            }
        }
        // A lantern's light.
        if b.fixture == Fixture.Lantern && !b.lit {
            var pairs: Pair[..8] = [];
            var shroud = false;
            var smoke = false;
            var reach: i64[..7] = [i];
            for j in neighbors(board, i) { reach.push(j); }
            for j in reach {
                let x = board.bottles[j];
                if x.cover == Cover.Shroud { shroud = true; pairs.push(Pair { a: i, b: j, tie: Tie.Light }); }
                else if x.murk != 0 && x.cover != Cover.Seal { smoke = true; pairs.push(Pair { a: i, b: j, tie: Tie.Light }); }
            }
            if shroud && smoke { effect(Feature.Lantern, "Lantern: when its flask is completed, it lifts the shroud beside it and clears the smoke around it.", pairs); }
            else if shroud { effect(Feature.Lantern, "Lantern: when its flask is completed, it lifts the shroud beside it.", pairs); }
            else if smoke { effect(Feature.Lantern, "Lantern: when its flask is completed, it clears the smoke around it.", pairs); }
            for j in board.count {
                if board.bottles[j].body == Body.Moonpetal {
                    effect(Feature.Moonpetal, "Moonpetal: opens once a lantern is lit.", [Pair { a: i, b: j, tie: Tie.Light }]);
                }
            }
        }
        // A catalyst sets everything off.
        if b.fixture == Fixture.Catalyst && !b.spent {
            var pairs: Pair[..16] = [];
            var braziers = false;
            var glasses = false;
            var lanterns = false;
            for j in board.count {
                let x = board.bottles[j];
                if x.fixture == Fixture.Brazier { braziers = true; if pairs.len < pairs.cap { pairs.push(Pair { a: i, b: j, tie: Tie.Catalyst }); } }
                if can_flip(x) { glasses = true; if pairs.len < pairs.cap { pairs.push(Pair { a: i, b: j, tie: Tie.Catalyst }); } }
                if x.fixture == Fixture.Lantern && !x.lit { lanterns = true; if pairs.len < pairs.cap { pairs.push(Pair { a: i, b: j, tie: Tie.Catalyst }); } }
            }
            var what: u8[>..] = [];
            fn add(f: bool, s: const u8[:]) {
                if !f { return; }
                if what.len > 0 { what.append(", "); }
                what.append(s);
            }
            add(braziers, "every brazier warms its neighbors");
            add(glasses, "every hourglass flips");
            add(lanterns, "every lantern lights");
            if what.len > 0 { effect(Feature.Catalyst, str("Catalyst: when its flask is completed, ", what, "."), pairs); }
        }
        // A key and its door, and what moves its layer.
        if b.key_color != KeyColor.None {
            let m = metal(b.key_color);
            var pairs: Pair[..4] = [];
            for j in behind_door_of(board, door_of(board, b.key_color)) { pairs.push(Pair { a: i, b: j, tie: Tie.Key }); }
            effect(Feature.Keys, str(capitalized(m), " key: opens the ", m, " door when its layer reaches the top."), pairs);
            let here: Pair[1] = [Pair { a: i, b: i, tie: Tie.Key }];
            if b.body == Body.Siphon { effect(Feature.Keys, "Keys: a siphon's tap frees a key it lets out of the bottom.", here); }
            if b.body == Body.Hourglass { effect(Feature.Keys, "Keys: an hourglass's flip can bring a key's layer to the top.", here); }
            if b.cover != Cover.None && b.cover != Cover.Vine { effect(Feature.Keys, "Keys: a key under a cover stays put until the cover is gone.", here); }
            if any_liquid(board, QUICKSILVER) && b.body != Body.Athanor {
                effect(Feature.Quicksilver, "Quicksilver: sinking under a key's layer lifts it, never over it.", here);
            }
        }
        // A curtain waits on its color.
        if b.cover == Cover.Curtain {
            var pairs: Pair[..16] = [Pair { a: i, b: i, tie: Tie.Flow }];
            for j in board.count { if j != i && has_liquid(board.bottles[j], b.badge) && pairs.len < pairs.cap { pairs.push(Pair { a: j, b: i, tie: Tie.Flow }); } }
            effect(Feature.Curtain, str("Curtain: opens when ", a_color(b.badge), " flask is completed."), pairs);
        }
        // The vine.
        if b.fixture == Fixture.VineRoot {
            let next = next_tendril(board, i);
            let left: i64 = b.spread_every - b.spread_count;
            if next >= 0 {
                // From the root or the tendril it grows from.
                var src = i;
                for k in neighbors(board, next) { if board.bottles[k].cover == Cover.Vine { src = k; } }
                for k in neighbors(board, next) { if k == i { src = i; } }
                effect(Feature.Vine, str("Creeping Vine: in ", pours_left(left), " it grows over the next flask."),
                       [Pair { a: src, b: next, tie: Tie.Vine }]);
            }
            if b.cover == Cover.Rime {
                effect(Feature.Vine, "Creeping Vine: its root is frozen, so no Emerald until it thaws.", [Pair { a: i, b: i, tie: Tie.Vine }]);
            } else {
                var pairs: Pair[..16] = [Pair { a: i, b: i, tie: Tie.Vine }];
                for j in board.count { if board.bottles[j].cover == Cover.Vine && pairs.len < pairs.cap { pairs.push(Pair { a: i, b: j, tie: Tie.Vine }); } }
                effect(Feature.Vine, "Creeping Vine: pour Emerald into the root to wither the whole vine.", pairs);
            }
        }
        // An hourglass meets smoke, ice and quicksilver.
        if b.body == Body.Hourglass && !b.done {
            if b.cover == Cover.Rime { effect(Feature.Hourglass, "Hourglass: frozen, it counts no pours until it thaws.", [Pair { a: i, b: i, tie: Tie.Heat }]); }
            if b.murk != 0 { effect(Feature.Hourglass, "Hourglass: a flip brings its smoky layers to the top, where they clear.", [Pair { a: i, b: i, tie: Tie.Light }]); }
            if any_liquid(board, QUICKSILVER) { effect(Feature.Quicksilver, "Quicksilver: sinks back to the bottom when an hourglass flips.", [Pair { a: i, b: i, tie: Tie.Flow }]); }
        }
        // Quicksilver's way through a siphon and an athanor.
        if b.body == Body.Siphon && any_liquid(board, QUICKSILVER) {
            effect(Feature.Quicksilver, "Quicksilver: sinks to a siphon's tap, so it comes out first.", [Pair { a: i, b: i, tie: Tie.Flow }]);
        }
        if b.body == Body.Athanor {
            var pairs: Pair[..16] = [];
            for j in board.count { if j != i && has_liquid(board.bottles[j], QUICKSILVER) && pairs.len < pairs.cap { pairs.push(Pair { a: j, b: i, tie: Tie.Flow }); } }
            if pairs.len > 0 { effect(Feature.Quicksilver, "Quicksilver: turns to gold in the Athanor; all of it must.", pairs); }
        }
        // A seal keyed to quicksilver, and the Drop on a seal or a vow.
        if b.cover == Cover.Seal && !b.done {
            if b.key == QUICKSILVER { effect(Feature.Quicksilver, "Quicksilver: it's the key to a seal here.", [Pair { a: i, b: i, tie: Tie.Flow }]); }
            if drop_at >= 0 { effect(Feature.Drop, "The Drop: breaks any seal it's poured onto.", [Pair { a: drop_at, b: i, tie: Tie.Flow }]); }
        }
        if b.body == Body.Vow && b.vow == 0 && drop_at >= 0 {
            effect(Feature.Drop, "The Drop: goes into a vow flask without choosing its color.", [Pair { a: drop_at, b: i, tie: Tie.Flow }]);
        }
    }
    // The salamander's heat wherever it lands.
    if board.salamander >= 0 {
        var pairs: Pair[..16] = [];
        var ice = false;
        var wax = false;
        var vine = root >= 0;
        if root >= 0 { pairs.push(Pair { a: board.salamander, b: root, tie: Tie.Salamander }); }
        for j in board.count {
            let x = board.bottles[j];
            if !heat_takes(x) { continue; }
            if pairs.len < pairs.cap { pairs.push(Pair { a: board.salamander, b: j, tie: Tie.Salamander }); }
            if x.cover == Cover.Rime { ice = true; }
            if x.cover == Cover.Seal { wax = true; }
            if x.cover == Cover.Vine { vine = true; }
        }
        var what: u8[>..] = [];
        fn add(f: bool, s: const u8[:]) {
            if !f { return; }
            if what.len > 0 { what.append(", "); }
            what.append(s);
        }
        add(ice, "melts ice");
        add(wax, "softens seals");
        add(vine, "burns vines");
        if what.len > 0 { effect(Feature.Salamander, str("Salamander: where it lands, its heat ", what, " on that flask and beside it."), pairs); }
    }
    out
}
