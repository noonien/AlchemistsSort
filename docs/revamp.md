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

## The grid and neighbors

There are no shelves. Flasks stand in a **grid** of columns and rows on the
room's background. A **Tall Flask** takes one column and spans **2 or 3
rows**, with segments the same size as everywhere else, so it holds what
fits: `tall_cap(2) = 9`, `tall_cap(3) = 14` (4 per row, plus the gap
between rows). As before, one color comes in exactly that many segments to
fill it.

The core owns the grid: `settle()` places every flask in a cell (row,
column, rows spanned) from a pure function of the board, which the layout
code uses to draw. The column count is the one that shows the flasks
largest on the board area (near ties go to the fewest empty cells, then the
most columns). Tall flasks stand from the top row in the middle column (or
the edges, with an even column count); the other flasks fill the rows in
order, the last row's cells from the middle out. A hand-made level may hold
the grid to a column count (`.columns(n)`) where its idea needs rows that
long. Adding an extra flask never moves the others; it takes the free cell
of the last row nearest the middle, or starts a new row. **Neighbors** of a flask are the flasks directly left
and right of it in the same row. A tall flask is a neighbor on every row it
spans, so it can have up to 2 × rows neighbors.

## The bottle model

A bottle has independent parts, so modifiers combine (a frozen hourglass, a
key under smoke, a tall flask on a brazier, ...):

| Part | Values |
|---|---|
| `seg`, `n`, `cap` | the liquid, bottom first; `cap` 4, or 9 or 14 for a **Tall Flask** spanning 2 or 3 rows |
| `murk: u16` | bitmask, one bit per segment: hidden under smoke (was `hidden` count) |
| **body** (one) | `Plain`, `Vow`, `Siphon`, `Hourglass`, `Athanor`, `Moonpetal` |
| **cover** (at most one; blocks pours in and out unless said otherwise) | `None`, `Seal` (key color, heat count), `Rime` (timer), `Shroud`, `Vine` (a tendril), `Curtain` (`badge`: the color that opens it) |
| **fixture** (at most one) | `None`, `Brazier`, `Lantern` (lit flag), `Catalyst` (spent flag), `VineRoot` (spread timer, every N) |
| `keyed: u16`, `key_color` | the key buried in it (at most one): bit k set when segment k holds it, moved with the segments exactly like `murk`; `key_color` its metal (`Brass`, `Silver`, `Copper`), `None` once freed |
| `door`, `behind` | the door it stands behind (-1 none), and whether that door is still shut (kept by `settle` and the door opening) |
| body data | `key` for Vow; `flip_every` and a counter for Hourglass |
| `done` | completed and sealed (unchanged) |

Board-level state: `salamander` (flask index, -1 when none), the grid placement,
`pours`, and the doors: `doors: Door[3]` (`Door { color, open }`) and
`door_count`.

Special liquids (letters in the level format):
- **Quicksilver** `Q`: a liquid that sinks.
- **Gold** `U`: an ordinary color, but in Athanor levels some of it starts
  as quicksilver.
- **Philosopher's Drop** `*`: one wild segment.

## Rules, modifier by modifier

**Smoke** (`murk` in the code). A smoky segment hides its color. It clears
when it becomes the top segment of its flask, or when light reaches its
flask. (This is today's hidden layers rule.)

**Seal** (wax seal, was Cork). Contents hidden while sealed. Pouring its key
color, or the Drop, onto it breaks the seal and the liquid lands inside if it
fits. **Heat**: each heat pulse softens it, and the second pulse breaks it
with no liquid landing.

**Vow Flask** (was Mystery). Takes the first color poured in, then only that
color. It doesn't have to be used: like any flask it counts toward the win
only once it holds liquid, so an empty vow flask at the end is just an empty
flask, and one partly filled isn't done. The Drop is accepted and doesn't set
the vow.

**Tall Flask**. Spans 2 or 3 grid rows; `cap` 9 or 14. The level has one color with `cap` segments to
fill it. Recurring from level 8 onward (see the campaign). **Nothing ever
comes out of a tall flask**: it is never the source of a pour. So it is
for its color alone, and that color is known from the start: the flask
starts with some of it and nothing else (no other liquid, no Drop, no
smoke; validated), its glass is tinted with it, and it **takes only that
color** (the Drop and quicksilver of another color are refused too; a tall
athanor takes quicksilver only when its color is gold). A siphon's tap or
an hourglass's flip would do nothing there, so a tall flask is never a
siphon or an hourglass (validated), and the generator puts no body or
vine root on one. Since the color can only end in the tall flask, an
ordinary flask full of it is never complete (nor sealed): its liquid still
has to be poured on.

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

**Keys and Doors** (`keyed`/`key_color`, `door`). A key sits in one liquid
layer of a flask. It **comes free the moment its layer is the top layer of
its flask**: nothing of another color (nor the Drop) lies over its segment,
and its segment is out of the smoke. That happens however the layer gets
there: pouring off what lay over it, an hourglass's flip, light clearing
the smoke. A siphon's tap that lets the keyed segment out of the bottom
frees it too. The key moves with its segment whenever the stack shifts
(quicksilver sinking under it, a flip, a tap draining). Keys come in three
metals, Brass, Silver and Copper; each **opens the door of its metal**, so
a level has at most three doors, each with exactly one key. A **door**
stands before **2 or 3 neighboring flasks in one grid row**. While it is
shut those flasks are **out of play**: hidden, nothing poured from or into
them, and nothing reaches them (no heat, no light, no vine; their ice,
hourglass and vine root count no pours; nothing there completes). They may
hold liquid, which then has to be sorted after the door opens: liquid
behind a shut door means the level isn't won; empty flasks behind one
don't stand in the way. When its key comes free the door **opens for
good** and its flasks join the board. A key under a cover stays put until
the cover is gone (nothing moves under one), and smoke hides a key: it is
drawn only when its layer is in view.

**Curtain** (cover, `badge`). A drape with a color badge. The flask is
hidden and inert until **a flask of the badge color is completed**
(anywhere, a tall flask included); then the curtain opens for good. Liquid
behind a curtain isn't sorted yet, so it blocks the win. Heat and light
don't touch it. A curtain whose color is already complete at the start
opens at `settle`.

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
`CAP - 1` real segments in the level. It never goes into a tall flask
(which takes only its own color), so the short color is never a tall
flask's.

**Catalyst** (fixture). When its flask is completed (once): every Brazier
sends a heat pulse, every Hourglass flips, every Lantern lights.

### Order of effects in one pour

1. Legality: the source can pour (has liquid, not done, no cover, not
   behind a shut door, not a tall flask). The destination accepts the
   color (not behind a shut door, no cover except Seal/key rules, no
   salamander, body rules, a tall flask's color, room, top match). Siphon
   sources pour their bottom run.
2. Move the liquid: seal break, quicksilver sinking, athanor
   transmutation. Keys and murk move with their segments.
3. Clear murk on the new tops.
4. `pours++`. Then, in order: Rime timers (one per pour), Hourglass counters
   and flips, Vine spread timers and spreading.
5. Heat pulses from a Brazier destination. Vine wither if emerald went into
   the root.
6. The Salamander hops to the source, then its heat pulse.
7. Completion: seal completed flasks. Lanterns on completed flasks light.
   Catalysts fire. Curtains whose color has been completed open. Keys
   whose layer is on top (or that a tap let out) come free, and their
   doors open. Repeat until nothing changes, since light or heat can
   uncover a flask that's already complete, and an opened door or curtain
   can show one. (So a key freed by a pour, a flip or light opens its door
   within that same pour.)

### Details settled during implementation

- **Keys and doors:** the "layer" is the run of the key's color it sits in,
  so a key low in a run comes free once that whole run is on top (it is
  never poured out while buried: a pour takes only the top run). Validated:
  a key's layer can't start on top (its door would open at once), each key
  has exactly one door of its metal and each door exactly one key, a
  door's flasks are 2 or 3 in a row side by side (consecutive in the
  level's order; `place_grid` keeps such a group together in one row,
  leaving a cell empty rather than splitting it), never tall flasks, and
  the salamander never sits behind one. A key may lie behind another door
  (a chain) or under a curtain, but never behind its own door, and what
  opens a door or a curtain is never shut away behind it (no cycles).
- **Curtain:** validated: its color is on the board and not inside it (it
  couldn't be completed while the curtain hides some), and no two curtains
  (or a curtain and a door) wait on each other. The solver catches the
  rest.
- **Seal:** heat breaks it on the second pulse. Any break (key, Drop or
  heat) lets liquid in only if it fits by the normal rules. A seal's key is
  never the Drop.
- **Vine:** at most one root per level. Withering needs emerald poured into
  the root, even if nothing lands. A rimed root can't take emerald until it
  thaws.
- **Hourglass:** a rime that melts on a pour lets its hourglass count that
  same pour. A catalyst flip doesn't reset the hourglass's counter. An empty
  hourglass still flips.
- **Athanor:** it accepts quicksilver when empty or with gold or the Drop on
  top. With an Athanor on the board, a flask of quicksilver never completes.
  A vow can take quicksilver as its color.
- **Light** clears murk and lifts shrouds once, when the lantern lights.
- **Drop:** one color has one segment fewer to make room for it, so a level
  with the Drop but no color one short is invalid.
- **Vow:** a vow flask that starts with liquid is vowed to that liquid's
  color. Since an empty vow need not be used, a level puts it where the
  board needs it: the generator deals it in place of one of the spare
  flasks, and in levels 11 and 15 it is the spare without which the level
  can't be won.

`PourResult` keeps its fields and gains an **event list** (a fixed array,
e.g. up to 32) of `Event { kind, bottle, from, door }`. The game animates
the events in order. Kinds: `SealBroken`, `SealSoftened`, `Thawed`,
`HeatPulse`, `Lit`, `ShroudLifted`, `MurkCleared`, `Flipped`, `VineSpread`,
`VineWithered`, `TendrilBurned`, `SalamanderHop`, `Transmuted`,
`CatalystFired`, `Completed`, `Vowed` (a vow flask took its color),
`KeyFreed` (`bottle`: the key's flask, `door`: the door it opens),
`DoorOpened` (`door`, `bottle`: its first flask, `from`: the key's flask),
`CurtainOpened` (`bottle`: the curtain's flask, `from`: the completed flask
of its color).

## Explaining the board

Every sentence the game says about the rules comes from
`src/core/explain.goose`, which draws nothing and is unit-tested:

- `grimoire(board)`: the modifiers on the board, in campaign order, each
  with its one-sentence rule, its flasks, and only the ways it meets the
  others *on this board* ("Brazier: each pour into it melts the ice beside
  it, and softens the seal beside it"), each with the flasks and the pairs
  of flasks it ties (heat, light, key, vine, salamander, catalyst, flow).
- `explain_flask(board, i)`: a flask's card: its parts' names, how it
  stands in plain words ("Frozen: thaws in 3 pours. Sooner with heat: each
  pour into the Brazier on its left melts one more."), what it can't do now
  and what would change that, and the flasks tied to it.
- `refusal(board, from, to)`: the message a refused tap shows.
The game shows them two ways: the **Grimoire** (the book in the level's
header; tapping a line lights its flasks and ties on the board for a few
seconds, and the book pulses once after a tutorial's panel) and a **flask's
card** (press and hold, or right-click; it sits where it covers least of
the flasks it is about). A selected flask shows nothing extra on the
others: working out where a pour can go is left to the player. Taps act
the moment the flask is pressed; a press held still also shows the card.

## Built-in levels

Every level is built into the game. There are no level files, no JSON, and
no player-made levels: the My Levels screen, `--file` and the `E` export are
gone. Hand-made levels (tutorials and finales) are a table in
`src/core/levels.goose`, written with compact constructors close to how a
level reads: liquid strings bottom to top (`"RRGB"`; `Q` quicksilver, `U`
gold, `*` the Drop) plus the bottle's body, cover, fixture, murk, height,
key (`.key_at(layer, metal)`) and door (`.behind_door(metal)`), and
`.curtain(color)`. The campaign looks hand-made levels up by number; every other level is
generated from its seed. The tests solve every level in the table.

## Campaign: six chapters, then the Great Work

15 levels per chapter. Within a chapter, positions 5 and 10 are **Hard** and
15 is the **finale** (Super Hard, hand-made, a showcase of the chapter's
combos). Tutorials are hand-made and never land on a multiple of 5.

| Ch | Name | Levels | New (tutorial level) | Scene theme |
|---|---|---|---|---|
| 1 | The Apothecary | 1–15 | Smoke (3), Seal (6), Tall Flask (8), Vow (11) | warm wood, jars, candles |
| 2 | The Frost Cellar | 16–30 | Rime (18), Brazier (21), Quicksilver (26) | cold stone, icicles, embers |
| 3 | The Glassworks | 31–45 | Siphon (33), Keys and Doors (36), Curtain (41) | furnace glow, glass tubes |
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
  flow → Quicksilver/Tall; keys → Murk/Quicksilver; curtain → Tall/Vow;
  flip → Murk/Quicksilver/Keys; transmutation → Quicksilver; catalyst →
  Brazier/Hourglass/Lantern). Never everything at once.
- **Warm-up** (positions 1–2 of chapters 2+): only earlier modifiers, 2 of
  them.
- **Tall Flask**: levels `n >= 9` with `n % 4 == 0` get one (but not
  tutorials or finales).
- Murk is the background noise of every level from 3 on: some murk is
  common, more on Hard.
- **Dependencies** the generator respects: a Shroud needs a neighboring
  Lantern. A Moonpetal needs a Lantern on the board. An Athanor needs
  quicksilver. A Catalyst needs a Brazier, an Hourglass or a Lantern. A
  door stands before one or two dealt flasks and one extra empty one, side
  by side in a row, and its key is buried (under at least one layer of
  another color) in a flask in plain play. A curtain's color is one that
  neither it nor another curtain holds. A Brazier stands next to something
  heat affects, or there is a Salamander.

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
- **Perspective:** the play area is a tabletop seen from above at an angle,
  themed per chapter, with the room visible beyond its back edge. Flasks are
  drawn as cylinders in that view (elliptical rim, liquid surface and color
  edges, cylinder shading, a soft shadow on the table). Grid columns are
  slightly staggered for depth (alternate columns stand a little nearer).
  Rows are drawn with a gap between one row's feet and the next row's rims,
  and every part stays within its own column: what stands at a flask's foot
  (a brazier's bowl, roots, the hearth) fits in that gap and is drawn over
  the flasks, so every flask's rim and liquid stay in view. A tall flask
  stands on the table with its last row, its glass tinted with its color. A lantern hangs over its
  rim from a shepherd's crook rising from behind the flask, as large as the space up to the liquid of
  the flask above allows; unlit, its dark panes glimmer, and lit, it warms its flask and its
  neighbors. A siphon isn't tipped to pour: it is held with its tap
  over the target and its bottom run drains. The rules don't change, and
  taps hit the drawn flask (the front one where two overlap).
- **Continuous colors:** adjacent segments of the same color are one band
  with no line between them; only a change of color shows an edge.
- **In levels:** flasks drop into place one after another at start;
  idle liquid drifts and bubbles now and then; slosh on lift, pour and
  refusal (A1); the stream arcs under gravity with a splash and a ripple
  (A2); completion drops a stopper in and slides a label on (A5); every
  force has a visible effect (heat shimmer, light beams, the flip, the
  salamander's hop, vines growing and burning, the athanor's gold flash,
  the catalyst's rune burst, a freed key flying to its door's keyhole, the
  door lifting away, a curtain drawn up). A key is drawn in its layer
  through the liquid; a shut door is a plank door with a keyhole of its
  key's metal over its flasks' cells, and a curtain a drape with its
  color's badge. Heat and light are shown going only to flasks
  they change. A tipped flask's liquid stays level and leaves over the lip;
  an hourglass turns over on its pivots and its liquid falls back down.
  Whatever moves (a flask being poured from, an hourglass turning, the
  forces) is drawn over the board's words, so labels stay in view.
