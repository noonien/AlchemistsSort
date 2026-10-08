# The Revamp: chapters, forces, and a livelier game

This is the design the revamp implements. It replaces the old obstacle list
(hidden layers, split color, mystery, cloak, frozen, cork, vault, curtain,
gift, long) with modifiers that touch one another through a few shared
**forces**, introduced over six chapters.

## Principles

- Every modifier changes a *different* rule. No two are "shut until X" with a
  different X.
- Modifiers interact through forces: **heat, light, flow, flip, growth,
  transmutation**. A new chapter's forces always have a partner or counter
  among earlier modifiers, so levels mix old and new for a reason.
- Everything stays deterministic: the solver plays every rule exactly, the
  generator keeps only boards it can win, a seed always gives the same board.
- Calm game: no timers in seconds, no lives. Pour-count effects are fine;
  undo is free.

## Neighbors and shelves

Flasks stand on shelves in rows. **Neighbors** of flask `i` are `i - 1` and
`i + 1` when they stand on the same shelf row.

The core owns the row length: `Board.per_row` is set once when a board is
settled (`settle()`), from a pure function `shelf_per_row(count, tallest)`
that the layout code also uses (it is today's "best rows" search, moved into
the core). Adding an extra flask never changes `per_row`; extra flasks fill
the last row or start a new one. So neighbors never change mid-level.

## The bottle model

A bottle has independent parts, so modifiers combine (a frozen hourglass, a
sealed twin, a tall flask on a brazier, ...):

| Part | Values |
|---|---|
| `seg`, `n`, `cap` | the liquid, bottom first; `cap` 4, or 5..8 for a **Tall Flask** |
| `murk: u8` | bitmask, one bit per segment: hidden under smoke (was `hidden` count) |
| **body** (one) | `Plain`, `Vow`, `Siphon`, `Hourglass`, `Athanor`, `Moonpetal` |
| **cover** (at most one; blocks pours in and out unless said otherwise) | `None`, `Seal` (key color, heat count), `Rime` (timer), `Shroud`, `Vine` (a tendril) |
| **fixture** (at most one) | `None`, `Brazier`, `Lantern` (lit flag), `Catalyst` (spent flag), `VineRoot` (spread timer, every N) |
| `twin` | index of its twin flask, or -1 |
| body data | `key` for Vow; `flip_every` and a counter for Hourglass |
| `done` | completed and sealed (unchanged) |

Board-level state: `salamander` (flask index, -1 when none), `per_row`,
`pours`.

Special liquids (letters in the level format):
- **Quicksilver** `Q`: a liquid that sinks.
- **Gold** `U`: an ordinary color, but in Athanor levels some of it starts
  as quicksilver.
- **Philosopher's Drop** `*`: one wild segment.

## Rules, modifier by modifier

**Murk** (smoke over segments). A murky segment shows as smoke. It clears
when it becomes the top segment of its flask, or when light reaches its
flask. (This is today's hidden layers rule.)

**Seal** (wax seal, was Cork). Contents hidden while sealed. Pouring its key
color, or the Drop, onto it breaks the seal and the liquid lands inside if it
fits. **Heat**: each heat pulse softens it, and the second pulse breaks it
with no liquid landing.

**Vow Flask** (was Mystery). Takes the first color poured in, then only that
color. It must end full. The Drop is accepted and doesn't set the vow.

**Tall Flask**. `cap` 5 to 8. The level has one color with `cap` segments to
fill it. Recurring from level 8 onward (see the campaign).

**Rime** (ice, was Frozen). Covered. Thaws after N pours made anywhere
(timer -1 per pour). **Heat** takes one more off per pulse. When it reaches 0
the ice is gone.

**Brazier** (fixture). Each successful pour *into* a brazier flask sends one
**heat pulse** to each of its neighbors.

**Heat pulse** on a flask: Rime timer -1 (it thaws at 0). Seal softens (it
breaks at 2). A Vine tendril burns away. Nothing else.

**Quicksilver** `Q`. Can be poured into any flask that has room and accepts
liquid, whatever its top color is. It **sinks**: it is inserted below every
non-quicksilver segment, above any quicksilver already there. Murk bits
shift up with the segments it slides under, and the new silver segment is
visible. Liquid poured onto a flask follows the top-match rule as usual
(quicksilver is only on top when the flask holds nothing else). A flask of
all-quicksilver is complete like any color.

**Siphon** (body). Has a tap at the base: it pours its **bottom run** (the
run of equal segments from `seg[0]` up) instead of the top run. It receives
on top as normal. No murk on siphons. Quicksilver poured into a siphon sinks
straight to the tap, so it comes out first.

**Twin Flasks** (`twin`). Two neighboring flasks joined by a tube. When a
pour into one doesn't fit, the excess **overflows into the twin**, if the
twin would accept that color (no cover, not done, room, top match or empty,
no salamander, and its own body rules). One hop only. A covered twin
(Rime, Seal...) takes no overflow.

**Lantern** (fixture). When its flask is completed, the lantern **lights**
for good. Light reaches its neighbors and its own flask: it clears all murk
and lifts Shrouds there.

**Shroud** (cover, was Cloak). The flask is hidden and inert until **light**
reaches it. A Shroud always stands next to a Lantern (validated).

**Hourglass** (body). Every `flip_every` pours made anywhere, it **flips**:
the stack reverses (and the murk bits with it). Then quicksilver resettles to
the bottom, and the new top segment's murk clears. A covered hourglass (in
Rime, etc.) doesn't count pours and doesn't flip. A completed one doesn't
flip.

**Creeping Vine** (`VineRoot` fixture, `Vine` cover). Every N pours made
anywhere, the vine **spreads**: one new tendril covers the lowest-index flask
that neighbors the root or a tendril, is not done, has no cover and isn't
the root. Pouring **emerald** (`G`) into the root **withers the whole vine**
(every tendril gone, root fixture removed). A heat pulse burns the tendril it
hits; heat doesn't hurt the root.

**Salamander** (board token). A fire lizard sits on a flask's rim, so that
flask can't be poured *into*; pouring out of it is fine. After each
successful pour it **hops onto the flask the pour came from**, and on landing
sends a **heat pulse** to that flask and its neighbors.

**Moonpetal** (body). Accepts liquid only while **at least one Lantern is
lit**. Pouring out of it is always allowed.

**Athanor** (body). A furnace. **Quicksilver poured in turns into Gold**
(`U`). The Athanor accepts quicksilver when it has room and is empty or has
gold on top; it lands as gold, on top. Other colors follow the normal rules.
In a level with an Athanor, quicksilver + gold together make one set (4, or
`cap` for a tall gold), with at least one quicksilver. To win, all of it has
to become gold.

**Philosopher's Drop** `*` (at most one per level). A single wild segment.
It never joins a run (pouring it moves just itself). Any flask that accepts
liquid accepts it whatever its top, and anything may be poured onto it. It
breaks any Seal. It counts as any color for completion: a flask is complete
when it's full and every non-Drop segment is one color. That color then has
`cap - 1` real segments in the level.

**Catalyst** (fixture). When its flask is completed (once): every Brazier
sends a heat pulse, every Hourglass flips, every Lantern lights.

### Order of effects in one pour

1. Legality: the source can pour (has liquid, not done, no cover). The
   destination accepts the color (no cover except Seal/key rules, no
   salamander, body rules, room, top match). Siphon sources pour their
   bottom run.
2. Move the liquid: seal break, quicksilver sinking, athanor transmutation,
   twin overflow.
3. Clear murk on the new tops.
4. `pours++`. Then, in order: Rime timers (one per pour), Hourglass counters
   and flips, Vine spread timers and spreading.
5. Heat pulses from a Brazier destination. Vine wither if emerald went into
   the root.
6. The Salamander hops to the source, then its heat pulse.
7. Completion: seal completed flasks. Lanterns on completed flasks light.
   Catalysts fire. Repeat until nothing changes, since light or heat can
   uncover a flask that's already complete.

`PourResult` keeps its fields and gains an **event list** (a fixed array,
e.g. up to 32) of `Event { kind, bottle, from }`. The game animates the
events in order. Kinds: `SealBroken`, `SealSoftened`, `Thawed`, `HeatPulse`,
`Lit`, `ShroudLifted`, `MurkCleared`, `Flipped`, `VineSpread`,
`VineWithered`, `TendrilBurned`, `SalamanderHop`, `Transmuted`,
`Overflowed`, `CatalystFired`, `Completed`.

## Level format

Liquid letters as before, plus `Q` quicksilver, `U` gold, `*` the Drop.
Bottle objects:

```json
{ "liquid": "GGBR", "murk": 3, "height": 6,
  "body": "hourglass", "flip": 3,
  "cover": "rime", "thaw": 4,
  "fixture": "brazier",
  "twin": 5 }
```

- `body`: `plain` `vow` `siphon` `hourglass` (`flip`) `athanor` `moonpetal`
- `cover`: `seal` (`key`) `rime` (`thaw`) `shroud` `vine`
- `fixture`: `brazier` `lantern` `catalyst` `root` (`spread`)
- `murk`: how many of the lowest segments start murky (as `hidden` was)
- top level: `"salamander": <index>`

The old keys (`hidden`, `kind`: `mystery`/`frozen`/`cork`/`cloak`/
`vault`/`gift`/`curtain`) are still read where a mapping exists: hidden →
murk, mystery → vow, frozen → rime, cork/vault → seal, cloak → shroud.
`gift` and `curtain` are rejected with a clear message.

## Campaign: six chapters, then the Great Work

15 levels per chapter. Within a chapter, positions 5 and 10 are **Hard** and
15 is the **finale** (Super Hard, hand-made, a showcase of the chapter's
combos). Tutorials are hand-made and never land on a multiple of 5.

| Ch | Name | Levels | New (tutorial level) | Scene theme |
|---|---|---|---|---|
| 1 | The Apothecary | 1–15 | Murk (3), Seal (6), Tall Flask (8), Vow (11) | warm wood, jars, candles |
| 2 | The Frost Cellar | 16–30 | Rime (18), Brazier (21), Quicksilver (26) | cold stone, icicles, embers |
| 3 | The Glassworks | 31–45 | Siphon (33), Twin Flasks (36) | furnace glow, glass tubes |
| 4 | The Observatory | 46–60 | Lantern (48), Shroud (51), Hourglass (56) | night sky, brass, stars |
| 5 | The Greenhouse | 61–75 | Vine (63), Salamander (66), Moonpetal (71) | leaves, moonlight, mist |
| 6 | The Athanor | 76–90 | Athanor (78), Philosopher's Drop (81), Catalyst (86) | gold, red furnace, runes |
| — | The Great Work | 91+ | endless; 3–4 modifiers from everything | all of it, cycling |

Levels 1–2 are plain colors. They are the only plain levels.

**What a generated level uses:**
- Every modifier already introduced *in this chapter* is a candidate. The
  **newest one appears in every level** after its tutorial, until the next
  tutorial; after that it stays likely.
- Plus **1** (normal) or **2** (hard) modifiers from **earlier chapters**,
  weighted toward the previous chapter and toward modifiers that interact
  with this chapter's (heat → Rime/Seal/Vine; light → Murk/Shroud;
  flow → Quicksilver/Tall; flip → Murk/Quicksilver; transmutation →
  Quicksilver; catalyst → Brazier/Hourglass/Lantern). Never everything at
  once.
- **Warm-up** (positions 1–2 of chapters 2+): only earlier modifiers, 2 of
  them.
- **Tall Flask**: levels `n >= 9` with `n % 4 == 0` get one (but not
  tutorials or finales).
- Murk is the background noise of every level from 3 on: some murk is
  common, more on Hard.
- **Dependencies** the generator respects: a Shroud needs a neighboring
  Lantern. A Moonpetal needs a Lantern on the board. An Athanor needs
  quicksilver. A Catalyst needs a Brazier, an Hourglass or a Lantern. Twins
  are neighbors. A Brazier stands next to something heat affects, or there
  is a Salamander.

**Saves:** the old save holds `level` (the next level). It maps to the
first level of the new chapter that contains it (capped at 91), so a player
lands on a chapter start and sees its tutorials.

## The solver doesn't block a frame

The A* search is resumable: `search_begin(board, budget)` makes a `Search`,
and `search_step(search&, nodes)` expands up to `nodes` positions and
reports whether it is finished. The game calls it with a small per-frame
budget (about 4 ms of work), the same on desktop and in the browser. No
threads: the web build has no `SharedArrayBuffer` on GitHub Pages. The
blocking `solve()` stays for tests and tools, built on the same two
functions.

- **Hint:** the button shows a bubbling "thinking" state. The move is
  highlighted when the search finishes. Any pour or undo cancels it.
- **Dead-end check:** after each pour it runs in the background (it's no
  longer limited to the "cornered" case, with the budget spread across
  frames). Any change to the board cancels and restarts it.
- **Generation ("Brewing"):** the generator is resumable too, so the
  Brewing screen animates while it works.

## Presentation

- **Workbench scene (A8):** a per-chapter background (see the table) with
  candlelight flicker that tints the glass, drifting dust motes, and a shelf
  behind that fills with a lit bottle for each completed color.
- **Per-color personality (A9):** subtle, never confusable: sun sparkles,
  umber smoke, lime faint glow, sky shimmer, and so on. The color-blind
  symbols still win.
- **Win finale (A7):** the completed potions send streams of light into a
  central glyph that turns into the Philosopher's Stone.
- **Sound:** pour pitch rises as the destination fills (S1). Each color is a
  pentatonic note; a completed flask rings its note, and the win plays the
  chord of the level's colors (S2).
- **Menus:** a living title (a simmering flask, bubbles, steam), a
  **chapter map** (the six rooms along a winding path with level stones;
  the current one pulses; finished chapters light their potion), buttons
  that squash and spring back and glow on hover, and ink-swirl transitions
  between screens.
- **In levels:** flasks drop onto the shelf one after another at start;
  idle liquid drifts and bubbles now and then; slosh on lift, pour and
  refusal (A1); the stream arcs under gravity with a splash and a ripple
  (A2); completion drops a stopper in and slides a label on (A5); every
  force has a visible effect (heat shimmer, light beams, the flip, the
  salamander's hop, vines growing and burning, the athanor's gold flash,
  the catalyst's rune burst).
