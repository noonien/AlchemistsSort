# Generating levels

A level is generated from a **recipe**: a handful of parameters that say
what the level is made of and how hard it should be. The generator deals
boards from the recipe, measures each one with the solver, and keeps the
first that is **in the difficulty band** and where **every modifier
matters**. Any number of levels can come from one recipe: the seed picks
the deal. The code: `Recipe`, `deal` and `GenJob` in
`src/core/generator.goose`; the measures, the use tests and the focus
check in `src/core/difficulty.goose`; the campaign's recipes in
`src/core/campaign.goose`; retry variants in `src/core/variation.goose`.

## The recipe

| Parameter | Meaning |
|---|---|
| `colors` | how many colors (3–12) |
| `spares` | empty flasks beyond the colors (0–3); fewer is harder. A vow flask is one of them |
| `partial` | segments moved off full flasks into the spares at the deal |
| `smoke` | how many layers start under smoke |
| `tall`, `tall_rows` | tall flasks (0–1) and how many rows each spans (2–3) |
| `mods` | each modifier wanted, with a count (e.g. brazier 1, rime 2), by `feature_index` |
| `focus` (`focused`) | the modifier the level is about (the newest one), which must be **required** |
| `band_lo`, `band_hi` | the difficulty band: the score it should land in (see below) |
| `thaw`, `flip_every`, `vine_every`, `athanor_quicksilver` | the modifiers' own numbers |
| `budget` | solver positions per deal (6000) |

The campaign turns a level number into a recipe (`plan_level`):

- **Colors** ramp over the whole campaign: 3 for level 2, then
  `4 + (n - 1) / 22` (4 → 8), 6–7 in the Great Work; Hard +1, Super Hard +2.
- **Spares**: 2. A Hard level has one fewer while it has five colors or
  fewer (with more, one spare is seldom enough to win at all). A vow flask
  is the only spare while there are five colors or fewer, so the level
  needs it; with more, it stands beside one plain spare.
- **Smoke**: `1 + colors / 3 + (0–2)` layers, +2 on Hard, +3 on Super Hard.
- **Modifiers** by chapter, as in revamp.md's "What a generated level
  uses": the newest modifier in every level until the next tutorial, the
  chapter's other ones now and then, one or two from earlier chapters
  weighted toward the forces that meet this chapter's; three or four from
  everything in the Great Work. A brazier or a salamander brings ice if
  nothing else is there to heat; a catalyst brings a lantern and an
  hourglass if it has fewer than two things to set off. Ice lasts 5–8 pours
  where heat can help (3–6 elsewhere), one more on Hard.
- **Focus**: the newest modifier, in chapters 1–6 (the Great Work has none).
- **Band**: see "Bands" below.

Generation is deterministic: the deal, the traps' playouts and every
choice come from the seed and the attempt number, and the scores use only
the four operations (no libm), so every build picks the same board.

## Measuring a deal

The solver plays every candidate. From its solution and its search:

- **length**: pours in the solution found.
- **effort**: positions the solver expanded to find it, as log2.
- **parking**: pours into an empty flask that is poured from again before
  it is done: moves that only make room.
- **traps**: of 6 short random playouts from the start (6 random pours
  among the solver's moves), how many end where the board is lost: no pour
  left, or a 150-position search proves it can't be won. Only boards
  already close to stuck can be proven so cheaply, which is what a trap is.
- **freedom**: the average number of pours worth trying along the solution.
- **hidden** (added): the average number of layers out of sight along the
  solution (under smoke, or in a sealed, shrouded or curtained flask or
  behind a shut door). The solver sees everything, so without this the
  score couldn't tell smoke, or a lantern that clears it, from nothing.

`score = 1·length + 3·log2(effort) + 2·parking + 2·traps − 0.5·freedom + 1·hidden`

(the weights are `W_*` in difficulty.goose). Plain boards score about 6 a
color: 4 colors ~22, 6 ~35, 8 ~48, and one spare fewer adds ~8–10.

A deal is too easy below the band and too hard above it (or when the
solver can't solve it within its budget). The generator tries up to 12
deals (or 30 000 solver positions) for one in the band, then keeps the
closest valid one. A deal is valid when it can be won, every modifier on
it matters, and its focus is required. When deals keep failing, the recipe
eases: after 24 deals (or 40 000 positions) the focus need not be
required, after 48 (70 000) only the focus and what it needs stay, after
72 (100 000) a color goes; after 100 a plain three-color board is the
fallback (never reached in the campaign).

## Bands

The band's middle is `24 + 0.33·n` for level n in the chapters (25 at
level 4, 54 at 89) and 50 in the Great Work. Normal levels take
`middle − 6 … middle + 8`, Hard `middle + 8 … middle + 24`, Super Hard
`middle + 14 … middle + 34`. Levels 1 and 2 take what comes.

Over levels 1–120 (94 generated), 83 land in their band; the rest keep the
closest deal: a few Hard levels whose deals stay below (25 above), the
catalyst levels 87, 88 and 93 (a catalyst dealt to fire early makes them
easier), and a handful more. Chapter by chapter the Normal levels average
about 27, 34, 37, 42, 48, 49 (Great Work ~50), and the Hard ones 40, 50,
50, 59, 66, 54: 5–18 above. The tests print the full table.

## Every modifier must matter

A modifier that does nothing is never placed. Each one has a placement
rule (where it can go so it can act) and a **use test** on the solver's
solution (what must happen along it). Modifiers that act on others are
placed first, then what they act on beside them. Where a modifier sits on
flasks, *every* one of its flasks must pass.

| Modifier | Placed so that | The solution must |
|---|---|---|
| Smoke | covers layers that aren't the top; a lantern's neighbors get theirs first, deep | uncover at least half its layers (not just clear them by completing their flask) |
| Seal | over room the board needs (a spare first), its key a color buried everywhere else (its own top when that's buried), beside a cold brazier first | break it (key, Drop or heat) |
| Vow | in place of a spare | pour into it |
| Tall flask | — | fill it |
| Rime | on a flask with liquid, 3+ pours, beside a brazier with nothing to heat first | pour from or into it after it thaws |
| Brazier | on a flask pours go to (an empty spare first), beside something ice or a seal can cover; removed if nothing to heat ends up beside it | thaw, soften or burn something with its heat (its own pours or a catalyst's) |
| Quicksilver | — | sink under another color at least once, or be turned to gold |
| Siphon | its bottom run differs from its top | pour from its tap while its bottom differs from its top |
| Keys & doors | a door before 1–2 dealt flasks with liquid and an empty one; the key buried 1–3 layers deep in a flask in play, with no cover | free each key, and pour from or into a flask behind each door after it opens |
| Curtain | on a flask with liquid, its badge a color neither it nor another curtain holds | open it, then pour from or into it |
| Lantern | on a flask that can be completed, beside flasks smoke can hide (or a shroud), or anywhere a moonpetal waits; dealt one color under its top, with one more of it on top elsewhere, so it lights early | light, and its light clears smoke or lifts a shroud still there; or a moonpetal takes liquid after it lights |
| Shroud | beside a lantern | lift it, then pour from or into it |
| Hourglass | it holds at least two colors | flip while that changes its top |
| Vine | beside flasks it can grow over (near a brazier's, if there is one) | spread at least once, or be withered |
| Salamander | on a flask in play with liquid, where ice, a seal or a vine is on the board | warm ice, a seal or a tendril |
| Moonpetal | dealt one color under its top, so it has to take more | take liquid (only possible once a lantern is lit) |
| Athanor | quicksilver is on the board (part of the gold) | turn quicksilver to gold |
| Drop | — | be used (it ends up completing a flask in any win) |
| Catalyst | where there are two things at least to set off; dealt one color under its top | fire, setting off at least two effects (a flip, a light, heat that finds ice, a seal or a tendril) |

Nothing goes on the flasks behind a door: no body, cover, fixture or
smoke, and no salamander.

The level's **focus** modifier must also be **required**: with it taken
out (`without_feature`: a seal with no wax, ice already melted, a brazier
with no fire, doors left open, a lantern gone, an empty vow flask shut,
quicksilver an ordinary dye, the gold already made, ...), the board must
be unwinnable (or not solved within the budget), or score clearly
differently: by at least 2 points or 10% (`FOCUS_MIN`, `FOCUS_SHARE`).
An obstacle taken out makes the board easier; a helper (brazier, lantern,
catalyst, the vow's spare) taken out makes it harder. A tall flask can't
be taken out without changing its color's count, so it is exempt. In the
campaign only level 87 (a catalyst level) ends up with its focus check
dropped by the easing.

## Retrying a level

Each attempt at a level after the first (a restart, a retry after a dead
end, a replay, a later visit in the same session) is a slight **variant**
of it, so the hidden layers can't be learned by heart. The first attempt
is the level as made.

1. **Recolor**: the level's dyes are permuted. Seal keys, curtain badges
   and a vow already taken move with the color they name; the tall flask's
   color moves with it. Emerald stays emerald on vine levels; gold,
   quicksilver and the Drop never change; and a hand-made level keeps the
   colors its hint names.
2. **Reshuffle the hidden**: the layers under smoke and the contents of
   sealed and shrouded flasks are dealt again among those hidden places.
   Everything visible, every modifier and every key (and its segment) stay
   where they are; quicksilver and the Drop stay put.
3. **Check**: the variant must be valid, solvable, score (without the
   traps) within ±15% of the level, and keep every modifier's use test.
   Up to 6 reshuffles are tried; if none passes, the attempt is the recolor
   alone (the same puzzle, so nothing to check).

About three quarters of attempts get a reshuffle. A variant takes a few
milliseconds typically and up to ~0.35 s natively; the game makes it a
slice a frame like generation, under the Brewing overlay when it takes
more than a frame. Undo and the hint work on the variant as on any board.

## Timing

Generating any campaign level takes 7 ms natively at the median, 50 ms at
the 90th percentile and 0.5 s at worst (level 100); the tests' TinyCC
build is about 3× slower and prints its times.
