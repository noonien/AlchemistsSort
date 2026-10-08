// Every level that ships with the game, built in: the campaign's tutorials
// and a few examples. There are no level files; a new level is written here.
//
// A level is a name, a difficulty, a hint shown when it starts, and its
// flasks left to right, rows filling as the shelf allows:
//
//     level(23, "First Frost", Difficulty.Normal, "Ice melts after enough pours.", [
//         flask("RRGB"),                          // liquid, bottom to top
//         flask("GGBR").under_murk(3),            // the lowest three under smoke
//         flask("BRGG").rime(4),                  // ice, melting in four pours
//         flask("YY").seal('Y'),                  // a seal that Y breaks
//         flask("VV").tall(6).hourglass(3),       // six tall, flipping every three pours
//         flask("").brazier(),
//         flask(""),
//     ])
//
// The number is the campaign level it stands in for, 0 for an example. The
// letters (COLOR_LETTERS below) are R O Y L G C B V K N W S T A for the dyes,
// Q quicksilver, U gold and * the Philosopher's Drop. Parts chain
// onto a flask: bodies .vow_flask() .siphon() .hourglass(every) .athanor()
// .moonpetal(); covers .seal(key) .rime(pours) .shroud() .vine(); fixtures
// .brazier() .lantern() .catalyst() .root(every); .twin_of(index) on both twins
// and .tall(height). A salamander goes in with `.salamander(index)` on the
// level. Every one of them is checked and solved by the tests.

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
fn murk_below(n: i64) -> u8 { ((1 << clamp(n, 0, MAX_CAP)) - 1) as u8 }

struct HandMade {
    number: i64,        // the campaign level it is, or 0
    info: LevelInfo,
    board: Board,
}

// --- building them ------------------------------------------------------------------

fn flask(liquid: const u8[:]) -> Bottle {
    var b = Bottle { seg: [0; 8], .. };
    for ch in liquid {
        let c = color_of_letter(ch);
        assert(c > 0 && b.n < MAX_CAP);
        b.seg[b.n] = c as u8;
        b.n++;
    }
    b
}

fn under_murk(b: Bottle, lowest: i64) -> Bottle { var x = b; x.murk = murk_below(lowest); x }
fn tall(b: Bottle, height: i64) -> Bottle { var x = b; x.cap = height as u8; x }
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
fn twin_of(b: Bottle, other: i64) -> Bottle { var x = b; x.twin = other as i8; x }

fn level(number: i64, name: const u8[:], difficulty: Difficulty, hint: const u8[:],
         bottles: const Bottle[:]) -> HandMade {
    var h = HandMade { number: number, info: LevelInfo { name: [], hint: [], difficulty: difficulty },
                       board: Board { .. } };
    h.info.name.append(name[..min(48, name.len)]);
    h.info.hint.append(hint[..min(200, hint.len)]);
    for b in bottles { push_bottle(h.board, b); }
    h.board.colors = color_count(h.board);
    h
}

fn salamander(h: HandMade, at: i64) -> HandMade { var x = h; x.board.salamander = at; x }

// --- the levels -------------------------------------------------------------------------

let HAND_MADE_COUNT = 11;

// Hand-made level `k`, 0 <= k < HAND_MADE_COUNT, settled and ready to play.
fn hand_made(k: i64) -> HandMade {
    var h = match k {
        0 => level(1, "First Pour", Difficulty.Normal,
                   "Tap a flask, then tap another to pour. Liquid only lands on the same color or in an empty flask. Fill every flask with a single color.",
                   [flask("RRGB"), flask("GGBR"), flask("BBRG"), flask(""), flask("")]),
        1 => level(4, "Murk", Difficulty.Normal,
                   "Smoke hides the lower layers until the liquid above them has been poured away.",
                   [flask("GBRY").under_murk(3), flask("YRBG").under_murk(3), flask("RGYB"), flask("BYGR"), flask(""),
                    flask("")]),
        2 => level(8, "Split Color", Difficulty.Normal,
                   "Violet is split between two flasks: a pair on top of one, a pair at the bottom of the other. Bring them back together.",
                   [flask("RRVV"), flask("VVGG"), flask("GBRB"), flask("BGBR"), flask(""), flask("")]),
        3 => level(13, "Vow Flask", Difficulty.Normal,
                   "The vow flask takes whatever color you pour into it first, and from then on only that color. It must end up full.",
                   [flask("RGBY"), flask("GYRB"), flask("BRYG"), flask("YBGR"), flask("").vow_flask(), flask("")]),
        4 => level(17, "Shroud", Difficulty.Normal,
                   "A shroud hides a flask until light reaches it. Complete the flask with the lantern, and its light lifts the shroud next door.",
                   [flask("RRGB"), flask("YBGY").lantern(), flask("GBYG").shroud(), flask("BRYR"), flask(""),
                    flask("")]),
        5 => level(21, "Rime", Difficulty.Normal,
                   "Ice keeps a flask shut until enough pours have been made anywhere on the table. The number counts down with every pour.",
                   [flask("RGBY"), flask("YBRG"), flask("GRYB").rime(5), flask("BYGR"), flask(""), flask("")]),
        6 => level(26, "Seal", Difficulty.Normal,
                   "A wax seal breaks when you pour exactly its color onto it, and the liquid lands inside. What it holds stays a mystery until then.",
                   [flask("RGBY"), flask("YBRG"), flask("GBY").seal('Y'), flask("RRGB"), flask("Y"), flask("")]),
        7 => level(46, "Tall Flask", Difficulty.Normal,
                   "The tall flask holds more than four layers. Violet comes in six here, enough to fill it. Otherwise it's an ordinary flask.",
                   [flask("RGBV"), flask("VBRG"), flask("GVRB"), flask("BRGV"), flask("VV").tall(6), flask("")]),
        8 => level(0, "Heat and Light", Difficulty.Normal,
                   "The brazier warms its neighbors whenever you pour into it, the lantern lights when its flask is done, and the athanor turns quicksilver to gold. Twin flasks share what overflows.",
                   [flask("RRRB"), flask("").brazier(), flask("BBBR").rime(5), flask("GGGY").shroud(),
                    flask("YYYG").lantern(),
                    flask("QU").siphon(), flask("").athanor(), flask("UU").twin_of(8), flask("").twin_of(7),
                    flask("")]),
        9 => salamander(level(0, "Time and Growth", Difficulty.Normal,
                   "The hourglass turns over every four pours, the vine creeps every five until emerald withers it, the salamander hops to every flask you pour from, and the Drop fits any color.",
                   [flask("RRGB").hourglass(4), flask("GGBR"), flask("BBRG"), flask("").root(5), flask(""),
                    flask("YY*").catalyst(), flask("Y").moonpetal(), flask("").lantern(), flask("")]), 1),
        _ => level(0, "Apothecary Sampler", Difficulty.SuperHard,
                   "A bit of everything: murk, ice, a seal, a shroud by its lantern and a vow flask.",
                   [flask("RGBY").under_murk(3), flask("VKYR").under_murk(2), flask("GVBK").rime(6),
                    flask("YBVG").lantern(), flask("BYGR").shroud(), flask("KRV").seal('V'), flask("K"),
                    flask("").vow_flask(), flask("")]),
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
