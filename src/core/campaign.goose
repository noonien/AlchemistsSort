// The numbered levels: which are hand-made tutorials, how difficulty ramps,
// and the generator settings for every other level. Level n is always the
// same board, since its seed comes from n.

import std;
import .board;
import .generator;

import .levels;

// Modifier "features", in the order they are introduced.
enum Feature { Murk, Split, Vow, Shroud, Rime, Seal, Tall }

let ALL_FEATURES: const Feature[7] = [Feature.Murk, Feature.Split, Feature.Vow, Feature.Shroud, Feature.Rime,
                                      Feature.Seal, Feature.Tall];

// The level that teaches each feature (none is a multiple of 5, which are
// the Hard and Super Hard levels). Its board is in levels.goose.
fn tutorial_level(f: Feature) -> i64 {
    match f { Murk => 4, Split => 8, Vow => 13, Shroud => 17, Rime => 21, Seal => 26, Tall => 46 }
}

fn feature_name(f: Feature) -> const u8[:] {
    match f {
        Murk => "Murk", Split => "Split Color", Vow => "Vow Flask", Shroud => "Shroud", Rime => "Rime",
        Seal => "Seal", Tall => "Tall Flask",
    }
}

struct LevelSpec {
    number: i64,
    difficulty: Difficulty,
    is_tutorial: bool = false,
    tutorial: Feature = Feature.Murk,       // the feature it teaches, when is_tutorial
    hand_made: bool = false,    // the board is levels.goose's for this number
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
    if introduced(Feature.Murk, level) {
        p.murk = match difficulty {
            SuperHard => 3 + r.rand_int(3),
            Hard => 2 + r.rand_int(2),
            Normal => r.rand_int(3),
        };
        p.murk = min(p.murk, p.colors - 1);
    }
    p.split = introduced(Feature.Split, level) && r.rand_int(3) == 0;
    // Mechanical modifiers: none to two of those introduced so far, with the
    // newest one favored for the few levels after its tutorial.
    var pool: Feature[>..] = [];
    for f in ALL_FEATURES {
        if f == Feature.Murk || f == Feature.Split || !introduced(f, level) { continue; }
        pool.push(f);
        if level - tutorial_level(f) < 4 { pool.push(f); pool.push(f); }
    }
    var wanted = match difficulty {
        SuperHard => 2,
        Hard => 1,
        Normal => if r.rand_int(10) < 4 { 1 } else { 0 },
    };
    var chosen: Feature[..7] = [];
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
            Vow => { p.vow = 1; },
            Shroud => { p.shroud = 1 + r.rand_int(2); },
            Rime => { p.rime = 1 + r.rand_int(2); },
            Seal => { p.seal = 1 + r.rand_int(2); },
            Tall => {
                p.tall = 1;
                p.tall_height = CAP + 1 + r.rand_int(MAX_CAP - CAP);
            },
            Murk, Split => {},
        }
    }
    p.budget = 40000;
    p
}

fn level_spec(level: i64) -> LevelSpec {
    let n = max(1, level);
    var spec = LevelSpec { number: n, difficulty: difficulty_of(n), params: GenParams {}, seed: level_seed(n) };
    let h, made = campaign_hand_made(n);
    if made {
        spec.hand_made = true;
        spec.difficulty = h.info.difficulty;
    }
    for f in ALL_FEATURES {
        if tutorial_level(f) == n {
            spec.is_tutorial = true;
            spec.tutorial = f;
        }
    }
    spec.params = params_for(n, spec.difficulty, spec.seed);
    spec
}

// A board for a custom seed, shaped like level `like` (its colors and
// whichever modifiers are introduced by then).
fn seed_spec(seed: u64, like: i64) -> LevelSpec {
    let n = max(1, like);
    let d = difficulty_of(n);
    LevelSpec { number: n, difficulty: d, params: params_for(n, d, seed), seed: seed }
}
