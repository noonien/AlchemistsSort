# Generating levels

A level is generated from a **recipe**: a handful of parameters that say
what the level is made of and how hard it should be. The generator deals
boards from the recipe, measures each one with the solver, and keeps the
first that is **in the difficulty band** and where **every modifier
matters**. Any number of levels can come from one recipe: the seed picks
the deal.

## The recipe

| Parameter | Meaning |
|---|---|
| `colors` | how many colors (3–12) |
| `spares` | empty flasks beyond the colors (0–3); fewer is harder |
| `partial` | segments moved off full flasks into the spares at the deal |
| `smoke` | how many layers start under smoke |
| `tall` | tall flasks (0–1) and how many rows each spans (2–3) |
| `modifiers` | each modifier wanted, with a count (e.g. brazier 1, rime 2) |
| `focus` | the modifier the level is about (usually the chapter's newest), which must be **required** |
| `band` | the difficulty band: a minimum and maximum score (see below) |

The campaign turns a level number into a recipe: colors ramp gently over
the whole campaign, Hard and Super Hard levels raise the band and take a
spare away, and the chapter decides the modifiers (as in revamp.md's
"What a generated level uses").

## Measuring a deal

The solver plays every candidate. From its solution and its search:

- **length**: pours in the solution found.
- **effort**: positions the solver expanded to find it (log scale): how
  much searching a solution takes.
- **parking**: pours in the solution into an empty flask that don't finish
  a color there: moves that only make room, which is where planning shows.
- **traps**: of a few short random playouts from the start (say 8 playouts
  of 6 random legal pours), how many end on a board the solver proves
  can't be won. A level that punishes careless pours has traps.
- **freedom**: the average number of legal pours along the solution; a
  board with many good pours everywhere is easy.

The **score** is a weighted sum (weights live in one place in the code and
are tuned against the campaign):
`score = a·length + b·log(effort) + c·parking + d·traps − e·freedom`.

A deal is too easy below the band and too hard above it (or when the
solver can't find a solution within its budget). The generator tries
deals until one lands in the band, and after a fixed number of attempts
keeps the closest valid one.

## Every modifier must matter

A modifier that does nothing is never placed. Each one has a placement
rule (where it can go so it can act) and a **use test** on the solver's
solution (what must happen along it):

| Modifier | Placed so that | The solution must |
|---|---|---|
| Smoke | covers layers that aren't the top | uncover at least `smoke` layers |
| Seal | its key color is reachable | break it |
| Vow | — | pour into it |
| Tall flask | — | fill it |
| Rime | thaw ≥ 3, and the flask holds something needed | need its contents after it thaws |
| Brazier | a neighbor has rime, a seal or a vine | thaw, soften or burn something with its heat |
| Quicksilver | — | sink under another color at least once |
| Siphon | its bottom run differs from its top | pour from its tap |
| Keys & doors | the key is buried 1–3 layers deep | free the key and use a flask behind the door |
| Curtain | its badge color can be completed without it | open it and use the flask |
| Lantern | a neighbor has smoke or a shroud, or there's a moonpetal | light it, and the light uncovers something still hidden |
| Shroud | a lantern is beside it | lift it and use the flask |
| Hourglass | it holds at least two colors | flip it while that changes its top |
| Vine | a neighbor can be overgrown | spread at least once, or be withered |
| Salamander | something its heat affects is on the board | warm something that matters |
| Moonpetal | a lantern is on the board | take liquid after the lantern lights |
| Athanor | quicksilver is on the board | turn quicksilver to gold |
| Drop | — | be used: break a seal or complete a flask |
| Catalyst | at least two things it would set off | fire, setting off at least two effects |

The level's **focus** modifier must also be **required**: with it taken
out (neutralized: a seal with no wax, a brazier with no fire, a door left
open...), the board must be unwinnable or score well below the band. That
makes the level about the modifier, not decorated with it.

## Retrying a level

Each attempt at a level (the first try, a restart, a retry after a dead
end, a replay from the map) is a slight **variant** of it, so the hidden
layers can't be learned by heart:

1. **Recolor**: the level's colors are permuted. Colors the rules name
   stay put: seal keys and curtain badges move with the color they name;
   emerald stays emerald on vine levels; gold, quicksilver and the Drop
   never change.
2. **Reshuffle the hidden**: the layers under smoke, and the contents of
   sealed and shrouded flasks, are re-dealt among those hidden places.
   Everything visible, every modifier and every key stays where it is.
3. **Check**: the variant must be solvable, score within ±15% of the
   original, and keep every modifier's use test. If no variant passes
   after a few tries, only the recolor is used.

Undo and the hint work on the variant as on any board. Hand-made levels
vary the same way, and fall back to recolor only when a reshuffle would
change what they teach.
