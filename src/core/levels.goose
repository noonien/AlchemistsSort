// Every level that ships with the game, built in: the campaign's tutorials,
// one for each modifier, and the six chapter finales. There are no level
// files; a new level is written here.
//
// A level is its campaign number, a name, a difficulty, a hint shown when
// it starts, and its flasks in order, placed in the grid by place_grid
// (tall flasks first, the rest row by row):
//
//     level(23, "First Frost", Difficulty.Normal, "Ice melts after enough pours.", [
//         flask("RRGB"),                          // liquid, bottom to top
//         flask("GGBR").under_murk(3),            // the lowest three under smoke
//         flask("BRGG").rime(4),                  // ice, melting in four pours
//         flask("YY").seal('Y'),                  // a seal that Y breaks
//         tall_flask('V', 2).lantern(),           // two rows tall, holding its extra violet
//         flask("GRBY").key_at(1, KeyColor.Brass),    // a brass key in its second layer
//         flask("R").behind_door(KeyColor.Brass), // two flasks behind the brass door
//         flask("").behind_door(KeyColor.Brass),
//         flask("BBG").curtain('R'),              // hidden until a Ruby flask is completed
//         flask("").brazier(),
//         flask(""),
//     ])
//
// The letters (COLOR_LETTERS below) are R O Y L G C B V K N W S T A for the
// dyes, Q quicksilver, U gold and * the Philosopher's Drop. Parts chain
// onto a flask: bodies .vow_flask() .siphon() .hourglass(every) .athanor()
// .moonpetal(); covers .seal(key) .rime(pours) .shroud() .vine()
// .curtain(color); fixtures .brazier() .lantern() .catalyst() .root(every).
// A key goes in a layer with .key_at(layer, metal) (layers count from the
// bottom, from 0), under a layer of another color; the flasks behind a door
// of that metal get .behind_door(metal), 2 or 3 of them, one after another
// (they stand side by side in one row). Each metal has one key and one
// door. A tall flask is made with tall_flask(color, rows), which holds the
// share of its color beyond an ordinary flask's; only that color goes in,
// and nothing comes out. A salamander goes in with
// `.salamander(index)` on the level, and `.columns(n)` holds the grid to n
// columns where the level needs rows that long. Every one of them is
// checked and solved by the tests.

import std;
import .board;

// Liquid letters, by number: the dyes, then quicksilver, gold and the Drop.
let COLOR_LETTERS = " ROYLGCBVKNWSTAQU*";
enum Difficulty { Normal, Hard, SuperHard }

fn difficulty_name(d: Difficulty) -> const u8[:] {
    match d { Normal => "Normal", Hard => "Hard", SuperHard => "Super Hard" }
}

struct LevelInfo {
    name: u8[..48],
    hint: u8[..200],
    difficulty: Difficulty = Difficulty.Normal,
}

fn color_of_letter(ch: u8) -> i64 {
    var up = ch;
    if up >= 'a' && up <= 'z' { up = up - 32; }
    for c in 1..COLOR_LETTERS.len {
        if COLOR_LETTERS[c] == up { return c; }
    }
    -1
}

fn letter_of_color(c: i64) -> u8 {
    if c < 1 || c >= COLOR_LETTERS.len { return '?'; }
    COLOR_LETTERS[c]
}

// Murk over the lowest `n` segments.
fn murk_below(n: i64) -> u16 { ((1 << clamp(n, 0, MAX_CAP)) - 1) as u16 }

struct HandMade {
    number: i64,        // the campaign level it is
    info: LevelInfo,
    board: Board,
}

// --- building them ------------------------------------------------------------------

fn flask(liquid: const u8[:]) -> Bottle {
    var b = Bottle { .. };
    for ch in liquid {
        let c = color_of_letter(ch);
        assert(c > 0 && b.n < MAX_CAP);
        b.seg[b.n] = c as u8;
        b.n++;
    }
    b
}

fn under_murk(b: Bottle, lowest: i64) -> Bottle { var x = b; x.murk = murk_below(lowest); x }
// A Tall Flask over `rows` rows (see tall_cap), already holding the share of
// `color` beyond CAP; the level has CAP more of it, like any other color.
fn tall_flask(color: u8, rows: i64) -> Bottle {
    var b = Bottle { .. };
    b.cap = tall_cap(rows) as u8;
    for k in b.cap - CAP { b.seg[k] = color_of_letter(color) as u8; }
    b.n = b.cap - CAP;
    b
}
fn vow_flask(b: Bottle) -> Bottle { var x = b; x.body = Body.Vow; x }
fn siphon(b: Bottle) -> Bottle { var x = b; x.body = Body.Siphon; x }
fn hourglass(b: Bottle, every: i64) -> Bottle {
    var x = b;
    x.body = Body.Hourglass;
    x.flip_every = every as u8;
    x
}
fn athanor(b: Bottle) -> Bottle { var x = b; x.body = Body.Athanor; x }
fn moonpetal(b: Bottle) -> Bottle { var x = b; x.body = Body.Moonpetal; x }
fn seal(b: Bottle, key: u8) -> Bottle {
    var x = b;
    x.cover = Cover.Seal;
    x.key = color_of_letter(key) as u8;
    x
}
fn rime(b: Bottle, pours: i64) -> Bottle {
    var x = b;
    x.cover = Cover.Rime;
    x.thaw = pours as u8;
    x
}
fn shroud(b: Bottle) -> Bottle { var x = b; x.cover = Cover.Shroud; x }
fn vine(b: Bottle) -> Bottle { var x = b; x.cover = Cover.Vine; x }
fn brazier(b: Bottle) -> Bottle { var x = b; x.fixture = Fixture.Brazier; x }
fn lantern(b: Bottle) -> Bottle { var x = b; x.fixture = Fixture.Lantern; x }
fn catalyst(b: Bottle) -> Bottle { var x = b; x.fixture = Fixture.Catalyst; x }
fn root(b: Bottle, every: i64) -> Bottle {
    var x = b;
    x.fixture = Fixture.VineRoot;
    x.spread_every = every as u8;
    x
}
fn curtain(b: Bottle, color: u8) -> Bottle {
    var x = b;
    x.cover = Cover.Curtain;
    x.badge = color_of_letter(color) as u8;
    x
}
fn key_at(b: Bottle, layer: i64, metal: KeyColor) -> Bottle {
    var x = b;
    x.keyed = (1 << layer) as u16;
    x.key_color = metal;
    x
}
// Behind the door of `metal`; level() numbers the doors.
fn behind_door(b: Bottle, metal: KeyColor) -> Bottle { var x = b; x.door = (key_index(metal) - 1) as i8; x }

fn level(number: i64, name: const u8[:], difficulty: Difficulty, hint: const u8[:],
         bottles: const Bottle[:]) -> HandMade {
    var h = HandMade { number: number, info: LevelInfo { name: [], hint: [], difficulty: difficulty },
                       board: Board { .. } };
    h.info.name.append(name[..min(48, name.len)]);
    h.info.hint.append(hint[..min(200, hint.len)]);
    for b in bottles { push_bottle(h.board, b); }
    // The doors, in the order their flasks come: behind_door marked each
    // flask with its door's metal.
    var number: i64[3] = [-1; 3];
    for i in h.board.count {
        var b .= h.board.bottles[i];
        if b.door < 0 { continue; }
        let m: i64 = b.door;
        if number[m] < 0 {
            number[m] = h.board.door_count;
            h.board.doors[h.board.door_count] = Door { color: KEY_COLORS[m] };
            h.board.door_count++;
        }
        b.door = number[m] as i8;
    }
    h.board.colors = color_count(h.board);
    h
}

fn salamander(h: HandMade, at: i64) -> HandMade { var x = h; x.board.salamander = at; x }
// The grid's columns, where the level needs its flasks in rows that long.
fn columns(h: HandMade, n: i64) -> HandMade { var x = h; x.board.cols = n; x }

// --- the levels -------------------------------------------------------------------------

let HAND_MADE_COUNT = 26;

// Hand-made level `k`, 0 <= k < HAND_MADE_COUNT, settled and ready to play.
fn hand_made(k: i64) -> HandMade {
    var h = match k {
        // The Apothecary.
        0 => level(1, "First Pour", Difficulty.Normal,
                   "Tap a flask, then tap another to pour. Liquid only lands on the same color or in an empty flask. Fill every flask with a single color.",
                   [flask("RRGB"), flask("GGBR"), flask("BBRG"), flask(""), flask("")]),
        1 => level(3, "Smoke in the Glass", Difficulty.Normal,
                   "Smoke hides the lower layers until the liquid above them has been poured away.",
                   [flask("GBRY").under_murk(3), flask("YRBG").under_murk(3), flask("RGYB"), flask("BYGR"), flask(""),
                    flask("")]),
        2 => level(6, "Sealing Wax", Difficulty.Normal,
                   "A wax seal breaks when you pour exactly its color onto it, and the liquid lands inside. What it holds stays a mystery until then.",
                   [flask("RGBY"), flask("YBRG"), flask("GBY").seal('Y'), flask("RRGB"), flask("Y"), flask("")]),
        3 => level(8, "A Taller Flask", Difficulty.Normal,
                   "The tall flask holds nine layers, all violet. It comes with some in it; only violet goes in, and nothing comes out. The four other violets fill it.",
                   [flask("RGBV"), flask("VBRG"), flask("GVRB"), flask("BRGV"), tall_flask('V', 2), flask("")]),
        4 => level(11, "The Vow", Difficulty.Normal,
                   "The vow flask takes whatever color you pour into it first, and from then on only that color. Here it is the only empty flask.",
                   [flask("RGBY"), flask("GYRB"), flask("BRYG"), flask("YBGR"), flask("").vow_flask()]),
        5 => level(15, "The Apprentice's Exam", Difficulty.SuperHard,
                   "Smoke, a seal, a vow and a tall flask: choose the vow's color with care.",
                   [flask("YVYV").under_murk(3), flask("RBRB").under_murk(2), flask("YGOG"), flask("OBOB").seal('Y'),
                    flask("GGVR").under_murk(2), tall_flask('V', 2), flask("").vow_flask(), flask("RYVO")]),
        // The Frost Cellar.
        6 => level(18, "First Frost", Difficulty.Normal,
                   "Ice keeps a flask shut until enough pours have been made anywhere on the table. The number counts down with every pour.",
                   [flask("RGBY"), flask("YBRG"), flask("GRYB").rime(5), flask("BYGR"), flask(""), flask("")]),
        7 => level(21, "The Brazier", Difficulty.Normal,
                   "Every pour into the brazier's flask warms the flasks beside it: their ice melts one pour sooner.",
                   [flask("GBR").rime(7), flask("").brazier(), flask("RBG").rime(7), flask("BRGG"), flask("RB"), flask("")]),
        8 => level(26, "Quicksilver", Difficulty.Normal,
                   "Quicksilver can be poured onto any color, and it sinks to the bottom, below everything but other quicksilver.",
                   [flask("QQ"), flask("QRR"), flask("QBB"), flask("BBRR")]),
        9 => level(30, "The Frost Cellar", Difficulty.SuperHard,
                   "Two braziers, a frozen pair and a seal only quicksilver or heat can break.",
                   [flask("YCQQ").rime(12), flask("").brazier(), flask("QRBY").rime(12), flask("").brazier(),
                    flask("OBCO").seal('Q'), flask("QCYC"), flask("RRBB"), flask("ROYO"), flask("")]),
        // The Glassworks.
        10 => level(33, "The Siphon", Difficulty.Normal,
                    "A siphon pours from the tap at its base: the bottom layer comes out first. It is filled from the top like any flask.",
                    [flask("RBBB").siphon(), flask("RRR"), flask("GGGB"), flask("G")]),
        11 => level(36, "Keys and Doors", Difficulty.Normal,
                    "A brass key lies in the ruby layer. Pour off what covers it and it comes free: it opens the brass door, and the flasks behind join the board.",
                    [flask("GRRB").key_at(1, KeyColor.Brass), flask("RGBG"), flask("BRG"),
                     flask("B").behind_door(KeyColor.Brass), flask("").behind_door(KeyColor.Brass)]),
        12 => level(41, "The Curtain", Difficulty.Normal,
                    "A curtain opens once a flask of the color on its badge is complete. Finish the ruby first, then sort what it hid.",
                    [flask("RRRB"), flask("GBGR"), flask("BGBG").curtain('R'), flask(""), flask("")]),
        13 => level(45, "The Glassblower's Bench", Difficulty.SuperHard,
                    "Siphons pour from their taps and the tall flask takes only quicksilver. The brass key lies in the amber: free it to reach the flasks behind the door.",
                    [flask("YBRG").siphon(), flask("GBYQ"), flask("QBR"), tall_flask('Q', 2),
                     flask("QOOR").key_at(1, KeyColor.Brass), flask("QG").siphon(), flask("YOGY"),
                     flask("OBR").behind_door(KeyColor.Brass), flask("").behind_door(KeyColor.Brass)]),
        // The Observatory.
        14 => level(48, "Lamplight", Difficulty.Normal,
                    "Complete the lantern's flask and it lights for good. Its light clears the smoke from its own flask and the flasks beside it.",
                    [flask(""), flask("BGBG").under_murk(3), flask("RRR").lantern(), flask("GBGB").under_murk(3), flask("R")]),
        15 => level(51, "The Shroud", Difficulty.Normal,
                    "A shroud hides a flask until light reaches it. Complete the flask with the lantern, and its light lifts the shroud next door.",
                    [flask("RRGB"), flask("YBGY").lantern(), flask("GBYG").shroud(), flask("BRYR"), flask(""), flask("")]),
        16 => level(56, "The Hourglass", Difficulty.Normal,
                    "The hourglass turns over after the number of pours on it, made anywhere: what was at the bottom comes to the top.",
                    [flask("RBB").hourglass(1), flask("RRR"), flask("GGBB"), flask("GG")]),
        17 => level(60, "The Orrery", Difficulty.SuperHard,
                    "A lantern, a shroud and a turning hourglass: light the way, and time the turn.",
                    [flask("GRCB").under_murk(3), flask("YGQ").lantern(), flask("RCBY").shroud(), flask("QBYR").hourglass(3),
                     flask(""), flask("QGBC").under_murk(2), flask("GCY"), flask("QR"), flask("")]),
        // The Greenhouse.
        18 => level(63, "Creeping Vine", Difficulty.Normal,
                    "Every few pours the vine grows over a flask next to it, shutting it. Pour emerald into its root and the whole vine withers.",
                    [flask("GRB"), flask("GBR"), flask("GG").root(3), flask("RRBB"), flask("")]),
        19 => salamander(level(66, "The Salamander", Difficulty.Normal,
                    "Nothing can be poured into the salamander's flask. After each pour it hops onto the flask you poured from, and its heat melts ice there and next door.",
                    [flask("RGB").rime(6), flask("BRG"), flask("GBR").rime(6), flask("RGB"), flask(""), flask("")]), 1),
        20 => level(71, "Moonpetal", Difficulty.Normal,
                    "The moonpetal takes liquid only while a lantern is lit. Pouring out of it is always fine.",
                    [flask("RR").moonpetal(), flask("BBB").lantern(), flask("GRB"), flask("RGG"), flask("G"), flask("")]),
        21 => salamander(level(75, "The Moonlit Greenhouse", Difficulty.SuperHard,
                    "The vine creeps, the salamander burns its tendrils, and the moonpetal waits for the lantern.",
                    [flask("GROB"), flask("YOBB"), flask("OR").root(3), flask("RYY").moonpetal(), flask("GY").lantern(),
                     flask("OGG"), flask("RB"), flask(""), flask("")]), 5).columns(5),
        // The Athanor.
        22 => level(78, "The Athanor", Difficulty.Normal,
                    "The athanor turns quicksilver poured into it into gold. Every drop of quicksilver has to become gold.",
                    [flask("").athanor(), flask("QRR"), flask("QBB"), flask("BBUU"), flask("RR")]),
        23 => level(81, "The Philosopher's Drop", Difficulty.Normal,
                    "The Drop fits any color: pour it anywhere, pour anything onto it, and it counts as whichever color fills its flask.",
                    [flask("GR*"), flask("BRB"), flask("GBGR"), flask("BG"), flask("")]),
        24 => level(86, "The Catalyst", Difficulty.Normal,
                    "Complete the catalyst's flask and it sets everything off: every brazier heats, every hourglass turns over and every lantern lights.",
                    [flask("RBBB").hourglass(9), flask("YYY").catalyst(), flask("GBGG").under_murk(3), flask("RRR").lantern(), flask("GY")]),
        _ => level(90, "The Great Athanor", Difficulty.SuperHard,
                   "Everything at once: fire the catalyst, feed the furnace quicksilver, and keep the Drop for the seal.",
                   [flask("").athanor(), flask("QCY"), flask("CYR").seal('K'), flask("").brazier(), flask("KUR").rime(10),
                    flask("RBC"), flask("YRY").catalyst(), flask("QBK").hourglass(9), flask("BU*"), flask("K").shroud(),
                    flask("KC").lantern(), flask("")]).columns(6),
    };
    settle(h.board);
    h
}

// The hand-made level for campaign level `number`, if there is one.
fn campaign_hand_made(number: i64) -> HandMade, bool {
    for k in HAND_MADE_COUNT {
        let h = hand_made(k);
        if h.number == number && number > 0 { return h, true; }
    }
    return hand_made(0), false;
}
