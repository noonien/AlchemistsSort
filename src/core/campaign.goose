// The numbered levels: which are hand-made tutorials, how difficulty ramps,
// and the generator settings for every other level. Level n is always the
// same board, since its seed comes from n.

import std;
import .board;
import .generator;
import .level_io;

// Obstacle "features", in the order they are introduced.
enum Feature { Hidden, Split, Mystery, Cloak, Frozen, Cork, Vault, Curtain, Gift, Long }

let ALL_FEATURES: const Feature[10] = [Feature.Hidden, Feature.Split, Feature.Mystery, Feature.Cloak,
                                       Feature.Frozen, Feature.Cork, Feature.Vault, Feature.Curtain,
                                       Feature.Gift, Feature.Long];

// The level that teaches each feature (none is a multiple of 5, which are
// the Hard and Super Hard levels).
fn tutorial_level(f: Feature) -> i64 {
    match f {
        Hidden => 4, Split => 8, Mystery => 13, Cloak => 17, Frozen => 21, Cork => 26, Vault => 31,
        Curtain => 36, Gift => 41, Long => 46,
    }
}

fn tutorial_file(f: Feature) -> const u8[:] {
    match f {
        Hidden => "04_hidden_layers", Split => "08_split_color", Mystery => "13_mystery_bottle",
        Cloak => "17_cloaked_bottle", Frozen => "21_frozen_bottle", Cork => "26_corked_bottle",
        Vault => "31_locked_vaults", Curtain => "36_curtain", Gift => "41_gift_box",
        Long => "46_long_flask",
    }
}

fn feature_name(f: Feature) -> const u8[:] {
    match f {
        Hidden => "Hidden Layers", Split => "Split Color", Mystery => "Mystery Flask",
        Cloak => "Cloaked Flask", Frozen => "Frozen Flask", Cork => "Corked Flask",
        Vault => "Locked Vault", Curtain => "Curtain", Gift => "Gift Box", Long => "Long Flask",
    }
}

struct LevelSpec {
    number: i64,
    difficulty: Difficulty,
    is_tutorial: bool = false,
    tutorial: Feature = Feature.Hidden,     // the feature it teaches, when is_tutorial
    file: u8[..48],             // a hand-made level to load, if any
    params: GenParams,
    seed: u64,
}

fn introduced(feature: Feature, level: i64) -> bool { level >= tutorial_level(feature) }

fn difficulty_of(level: i64) -> Difficulty {
    if level >= 10 && level % 10 == 0 { return Difficulty.SuperHard; }
    if level % 5 == 0 { return Difficulty.Hard; }
    Difficulty.Normal
}

fn level_seed(level: i64) -> u64 { hash(level as u64 * 7919 + 0xA1C4E) }

// Generator settings for a level of this number and difficulty, drawn from
// `seed` so a custom seed gives a board of the same flavor.
fn params_for(level: i64, difficulty: Difficulty, seed: u64) -> GenParams {
    var r = rng { seed ^ 0x5EED };
    var p = GenParams {};
    var colors = 3 + (level + 2) / 5;
    colors += match difficulty { Normal => 0, Hard => 1, SuperHard => 2 };
    p.colors = clamp(colors, 3, 12);
    p.empties = 2;
    p.partial = r.rand_int(p.colors / 2 + 1);
    if introduced(Feature.Hidden, level) {
        p.hidden = match difficulty {
            SuperHard => 3 + r.rand_int(3),
            Hard => 2 + r.rand_int(2),
            Normal => r.rand_int(3),
        };
        p.hidden = min(p.hidden, p.colors - 1);
    }
    p.split = introduced(Feature.Split, level) && r.rand_int(3) == 0;
    // Mechanical obstacles: none to two of those introduced so far, with the
    // newest one favored for the few levels after its tutorial.
    var pool: Feature[>..] = [];
    for f in ALL_FEATURES {
        if f == Feature.Hidden || f == Feature.Split || !introduced(f, level) { continue; }
        pool.push(f);
        if level - tutorial_level(f) < 4 { pool.push(f); pool.push(f); }
    }
    var wanted = match difficulty {
        SuperHard => 2,
        Hard => 1,
        Normal => if r.rand_int(10) < 4 { 1 } else { 0 },
    };
    var chosen: Feature[..10] = [];
    while wanted > 0 && pool.len > 0 {
        let f = pool[r.rand_int(pool.len)];
        if contains(chosen, f) {
            var all = true;
            for g in pool { if !contains(chosen, g) { all = false; } }
            if all { break; }
            continue;
        }
        chosen.push(f);
        wanted--;
    }
    for f in chosen {
        match f {
            Mystery => { p.mystery = 1; },
            Cloak => { p.cloak = 1 + r.rand_int(2); },
            Frozen => { p.frozen = 1 + r.rand_int(2); },
            Cork => { p.cork = 1 + r.rand_int(2); },
            Vault => { p.vault = 1 + r.rand_int(2); },
            Curtain => { p.curtain = 1; },
            Gift => { p.gift = 1 + r.rand_int(2); },
            Long => {
                p.long = 1;
                p.long_height = CAP + 1 + r.rand_int(MAX_CAP - CAP);
            },
            Hidden, Split => {},
        }
    }
    p.budget = 40000;
    p
}

fn level_spec(level: i64) -> LevelSpec {
    let n = max(1, level);
    var spec = LevelSpec { number: n, difficulty: difficulty_of(n), file: [], params: GenParams {},
                           seed: level_seed(n) };
    if n == 1 { spec.file.append("01_first_pour"); spec.difficulty = Difficulty.Normal; }
    for f in ALL_FEATURES {
        if tutorial_level(f) == n {
            spec.is_tutorial = true;
            spec.tutorial = f;
            spec.file.append(tutorial_file(f));
            spec.difficulty = Difficulty.Normal;
        }
    }
    spec.params = params_for(n, spec.difficulty, spec.seed);
    spec
}

// A board for a custom seed, shaped like level `like` (its colors and
// whichever obstacles are introduced by then).
fn seed_spec(seed: u64, like: i64) -> LevelSpec {
    let n = max(1, like);
    let d = difficulty_of(n);
    LevelSpec { number: n, difficulty: d, file: [], params: params_for(n, d, seed), seed: seed }
}
