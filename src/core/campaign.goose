// The numbered levels: six chapters of fifteen, then the endless Great Work.
// Which levels are hand-made (each modifier's tutorial and each chapter's
// finale, in levels.goose), how difficulty ramps, and what every other level
// asks the generator for. Level n is always the same board, since its seed
// comes from n. docs/revamp.md describes the plan this follows.

import std;
import .board;
import .generator;
import .difficulty;

import .levels;

// The level that teaches each one, in ALL_FEATURES order. None is a
// multiple of 5, which are the Hard levels and the finales.
let TUTORIAL_LEVELS: const i64[19] = [3, 6, 8, 11, 18, 21, 26, 33, 36, 41, 48, 51, 56, 63, 66, 71, 78, 81, 86];

fn tutorial_level(f: Feature) -> i64 { TUTORIAL_LEVELS[feature_index(f)] }

fn introduced(feature: Feature, level: i64) -> bool { level >= tutorial_level(feature) }

// --- chapters ------------------------------------------------------------------

// Six rooms of 15 levels each, then the endless Great Work. `theme` picks the
// workbench scene (0..5 the rooms; 6 the Great Work, which cycles through
// them). `last` is -1 for the Great Work, which never ends.
struct Chapter { name: const u8[:], first: i64, last: i64, theme: i64 }

let CHAPTER_LEVELS = 15;
let GREAT_WORK = 91;

let CHAPTERS: const Chapter[7] = [
    Chapter { name: "The Apothecary", first: 1, last: 15, theme: 0 },
    Chapter { name: "The Frost Cellar", first: 16, last: 30, theme: 1 },
    Chapter { name: "The Glassworks", first: 31, last: 45, theme: 2 },
    Chapter { name: "The Observatory", first: 46, last: 60, theme: 3 },
    Chapter { name: "The Greenhouse", first: 61, last: 75, theme: 4 },
    Chapter { name: "The Athanor", first: 76, last: 90, theme: 5 },
    Chapter { name: "The Great Work", first: 91, last: -1, theme: 6 },
];

fn chapter_count() -> i64 { CHAPTERS.len }

// The chapter (an index for chapter_info) that level n belongs to.
fn chapter_of(level: i64) -> i64 {
    for c, i in CHAPTERS {
        if c.last < 0 || level <= c.last { return i; }
    }
    CHAPTERS.len - 1
}

fn chapter_info(i: i64) -> Chapter { CHAPTERS[clamp(i, 0, CHAPTERS.len - 1)] }

// The modifiers a chapter introduces (none for the Great Work).
fn chapter_features(i: i64) -> Feature[..4] {
    var fs: Feature[..4] = [];
    for f in ALL_FEATURES {
        if CHAPTERS.len - 1 > i && chapter_of(tutorial_level(f)) == i { fs.push(f); }
    }
    fs
}

// Where level n stands in its chapter, 1 to 15; the Great Work counts in
// stretches of 15 too.
fn chapter_position(level: i64) -> i64 { (max(1, level) - 1) % CHAPTER_LEVELS + 1 }

fn is_finale(level: i64) -> bool { level < GREAT_WORK && chapter_position(level) == CHAPTER_LEVELS }

fn difficulty_of(level: i64) -> Difficulty {
    let pos = chapter_position(level);
    if pos == CHAPTER_LEVELS { return Difficulty.SuperHard; }
    if pos % 5 == 0 { return Difficulty.Hard; }
    Difficulty.Normal
}

// An old save's next level, from before the chapters: the first level of the
// chapter that holds it, so the player sees that chapter's tutorials.
fn migrated_level(old: i64) -> i64 { chapter_info(chapter_of(clamp(old, 1, GREAT_WORK))).first }

// --- what a generated level uses ------------------------------------------------

struct LevelSpec {
    number: i64,
    difficulty: Difficulty,
    chapter: i64 = 0,
    is_tutorial: bool = false,
    tutorial: Feature = Feature.Murk,       // the modifier it teaches, when is_tutorial
    is_finale: bool = false,
    hand_made: bool = false,    // the board is levels.goose's for this number
    mods: Feature[..8] = [],    // the modifiers a generated level asks for
    recipe: Recipe,
    seed: u64,
}

fn level_seed(level: i64) -> u64 { hash(level as u64 * 7919 + 0xA1C4E) }

// The modifier taught most recently before level n, which every level up to
// the next tutorial uses; false at the start and in the Great Work.
fn newest_feature(level: i64) -> Feature, bool {
    if level >= GREAT_WORK { return Feature.Murk, false; }
    var newest = Feature.Murk;
    var any = false;
    for f in ALL_FEATURES {
        if tutorial_level(f) < level {
            newest = f;
            any = true;
        }
    }
    return newest, any;
}

// Whether an earlier modifier `old` meets `new` through a force: heat on ice,
// seals and vines; light on murk and shrouds; flow with quicksilver and tall
// flasks; a key with what hides or shifts its layer; a curtain with what
// completes a color; the flip with murk, quicksilver and keys; the athanor
// with quicksilver; the catalyst with what it sets off; the Drop with what
// it fits.
fn meets(new: Feature, old: Feature) -> bool {
    match new {
        Brazier, Salamander => old == Feature.Rime || old == Feature.Seal || old == Feature.Vine,
        Rime => old == Feature.Seal,
        Lantern, Moonpetal => old == Feature.Murk || old == Feature.Shroud || old == Feature.Lantern,
        Shroud => old == Feature.Lantern,
        Quicksilver, Siphon => old == Feature.Quicksilver || old == Feature.Tall,
        Keys => old == Feature.Murk || old == Feature.Quicksilver,
        Curtain => old == Feature.Tall || old == Feature.Vow,
        Hourglass => old == Feature.Murk || old == Feature.Quicksilver || old == Feature.Keys,
        Vine => old == Feature.Brazier || old == Feature.Rime,
        Athanor => old == Feature.Quicksilver || old == Feature.Siphon,
        Catalyst => old == Feature.Brazier || old == Feature.Hourglass || old == Feature.Lantern,
        Drop => old == Feature.Seal || old == Feature.Vow,
        Murk, Seal, Tall, Vow => false,
    }
}


// A Tall Flask stands in every fourth level from 9 on.
fn tall_level(level: i64) -> bool { level >= 9 && level % 4 == 0 }

// Adds `f` to the recipe.
fn ask_for(p: Recipe&, f: Feature, hard: bool, r: rng&) {
    match f {
        Murk => { p.smoke = max(p.smoke, 2); },
        Tall => {
            p.tall = 1;
            p.tall_rows = if hard { 3 } else { 2 };
        },
        Seal, Rime, Keys => { want(p, f, if hard { 1 + r.rand_int(2) } else { 1 }); },
        Hourglass => {
            want(p, f, 1);
            p.flip_every = 3 + r.rand_int(3);
        },
        Vine => {
            want(p, f, 1);
            p.vine_every = 4 + r.rand_int(3);
        },
        Vow, Brazier, Quicksilver, Siphon, Curtain, Lantern, Shroud, Salamander, Moonpetal, Athanor, Drop,
        Catalyst => { want(p, f, 1); },
    }
}

// Picks one of `pool`, each as likely as its weight, and takes it out.
fn draw(pool: Feature[..19]&, weight: i64[..19]&, r: rng&) -> Feature, bool {
    var total = 0;
    for w in weight { total += w; }
    if total == 0 { return Feature.Murk, false; }
    var k = r.rand_int(total);
    for w, i in weight {
        if k < w {
            let f = pool[i];
            weight[i] = 0;
            return f, true;
        }
        k -= w;
    }
    return Feature.Murk, false;
}

// The difficulty band of level n: the score its board should land in. It
// rises over the campaign with the colors; Hard levels sit a step above
// the Normal ones around them, and Super Hard a step above that.
// Scores are a few points a color, plus what the modifiers and the deal
// add (see difficulty.goose); the band's middle climbs a third of a point a
// level through the chapters and holds in the Great Work. Levels 1 and 2
// take what comes.
fn band_middle(level: i64) -> f64 { if level >= GREAT_WORK { 50.0 } else { 24.0 + 0.33 * level } }

fn band_of(level: i64, difficulty: Difficulty) -> f64, f64 {
    if level <= 2 { return -1e9, 1e9; }
    let m = band_middle(level);
    if difficulty == Difficulty.SuperHard { return m + 14.0, m + 34.0; }
    if difficulty == Difficulty.Hard { return m + 8.0, m + 24.0; }
    return m - 6.0, m + 8.0;
}

// The modifiers level n uses, and its recipe, drawn from `seed` so a custom
// seed gives a board of the same flavor.
fn plan_level(level: i64, difficulty: Difficulty, seed: u64) -> Feature[..8], Recipe {
    var r = rng { seed ^ 0x5EED };
    var p = Recipe {};
    var mods: Feature[..8] = [];
    let hard = difficulty != Difficulty.Normal;
    let ch = chapter_of(level);
    let great = level >= GREAT_WORK;
    let pos = chapter_position(level);

    let newest, any_newest = newest_feature(level);
    let tall = level > 2 && (tall_level(level) || (any_newest && newest == Feature.Tall));

    // Colors ramp gently over the whole campaign, a step up on Hard levels.
    var colors = if level <= 2 { 3 } else { 4 + (level - 1) / 22 };
    if great { colors = 6 + r.rand_int(2); }
    colors += match difficulty { Normal => 0, Hard => 1, SuperHard => 2 };
    p.colors = clamp(colors, 3, if difficulty == Difficulty.SuperHard { 9 } else { 8 });
    // A Hard level has a spare fewer while it has few colors; with more,
    // one spare is seldom enough to win at all.
    p.spares = if hard && p.colors <= 5 { 1 } else { 2 };
    p.partial = r.rand_int(p.colors / 2 + 1);
    let lo, hi = band_of(level, difficulty);
    p.band_lo = lo;
    p.band_hi = hi;
    if level <= 2 { return mods, p; }

    // Smoke is the background of every level: some is common, more on Hard.
    p.smoke = 1 + p.colors / 3 + r.rand_int(3) + (match difficulty { Normal => 0, Hard => 2, SuperHard => 3 });

    if tall { mods.push(Feature.Tall); }
    if any_newest && !contains(mods, newest) { mods.push(newest); }

    if great {
        // The Great Work: three or four modifiers from everything.
        var pool: Feature[..19] = [];
        var weight: i64[..19] = [];
        for f in ALL_FEATURES {
            if f == Feature.Murk || f == Feature.Tall { continue; }
            pool.push(f);
            weight.push(1);
        }
        let wanted_mods = if hard { 4 } else { 3 };
        while mods.len < wanted_mods + (if tall { 1 } else { 0 }) {
            let f, ok = draw(pool, weight, r);
            if !ok { break; }
            mods.push(f);
        }
    } else {
        // This chapter's modifiers taught so far (the newest is already in);
        // the rest stay likely, never all at once.
        let here = chapter_features(ch);
        let warm_up = ch > 0 && pos <= 2;
        if !warm_up {
            let room = if hard { 3 } else { 2 };
            for f in here {
                if f == Feature.Murk || f == Feature.Tall || contains(mods, f) || !introduced(f, level) || tutorial_level(f) == level { continue; }
                if mods.len < room + (if tall { 1 } else { 0 }) && r.rand_int(2) == 0 { mods.push(f); }
            }
        }
        // And earlier chapters' modifiers: 1, or 2 on Hard levels and warm-ups,
        // weighted toward the last chapter and toward this chapter's forces.
        var earlier = if hard || warm_up { 2 } else { 1 };
        if tall && !warm_up { earlier--; }
        for m in mods { if chapter_of(tutorial_level(m)) < ch && m != Feature.Tall { earlier--; } }
        var pool: Feature[..19] = [];
        var weight: i64[..19] = [];
        for f in ALL_FEATURES {
            let fc = chapter_of(tutorial_level(f));
            if fc >= ch || f == Feature.Murk || f == Feature.Tall || contains(mods, f) { continue; }
            var w = 1;
            if fc == ch - 1 { w += 2; }
            for g in here {
                if (warm_up || introduced(g, level)) && meets(g, f) { w += 3; }
            }
            pool.push(f);
            weight.push(w);
        }
        while earlier > 0 {
            let f, ok = draw(pool, weight, r);
            if !ok { break; }
            mods.push(f);
            earlier--;
        }
    }

    // What some modifiers need: heat something to act on, a catalyst two
    // things to set off. (The generator brings a shroud's lantern, a
    // moonpetal's lantern and an athanor's quicksilver itself, and smoke is
    // always there for a lantern to clear.)
    let heated = contains(mods, Feature.Rime) || contains(mods, Feature.Seal) || contains(mods, Feature.Vine);
    if (contains(mods, Feature.Brazier) || contains(mods, Feature.Salamander)) && !heated && mods.len < 8 {
        mods.push(Feature.Rime);
    }
    if contains(mods, Feature.Catalyst) {
        var fires = 0;
        for f in [Feature.Brazier, Feature.Hourglass, Feature.Lantern, Feature.Shroud, Feature.Moonpetal] {
            if contains(mods, f) { fires++; }
        }
        if fires < 2 && !contains(mods, Feature.Lantern) && !contains(mods, Feature.Shroud) &&
           !contains(mods, Feature.Moonpetal) && mods.len < 8 {
            mods.push(Feature.Lantern);
            fires++;
        }
        if fires < 2 && !contains(mods, Feature.Hourglass) && mods.len < 8 { mods.push(Feature.Hourglass); }
    }

    for f in mods { ask_for(p, f, hard, r); }
    // A vow flask is the only spare while there are few colors, so the
    // level needs it; ice melts slower where heat can help.
    if wanted(p, Feature.Vow) > 0 { p.spares = if p.colors <= 5 { 1 } else { 2 }; }
    let hot = wanted(p, Feature.Brazier) > 0 || wanted(p, Feature.Salamander) > 0;
    p.thaw = (if hot { 5 } else { 3 }) + (if hard { 1 } else { 0 });
    // The level is about the newest modifier, while it is new.
    if any_newest && !great {
        p.focus = newest;
        p.focused = true;
    }
    return mods, p;
}

fn level_spec(level: i64) -> LevelSpec {
    let n = max(1, level);
    var spec = LevelSpec { number: n, difficulty: difficulty_of(n), chapter: chapter_of(n), recipe: Recipe {},
                           seed: level_seed(n) };
    spec.is_finale = is_finale(n);
    for f in ALL_FEATURES {
        if tutorial_level(f) == n {
            spec.is_tutorial = true;
            spec.tutorial = f;
        }
    }
    let h, made = campaign_hand_made(n);
    if made {
        spec.hand_made = true;
        spec.difficulty = h.info.difficulty;
        return spec;
    }
    let mods, p = plan_level(n, spec.difficulty, spec.seed);
    spec.mods = mods;
    spec.recipe = p;
    spec
}

// A board for a custom seed, shaped like level `like` (its colors and the
// kind of modifiers it would use).
fn seed_spec(seed: u64, like: i64) -> LevelSpec {
    let n = max(1, like);
    let d = difficulty_of(n);
    let mods, p = plan_level(n, d, seed);
    LevelSpec { number: n, difficulty: d, chapter: chapter_of(n), mods: mods, recipe: p, seed: seed }
}
