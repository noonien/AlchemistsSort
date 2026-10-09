# Alchemist's Sort

A calm potion-sorting puzzle: pour layered liquids between flasks until each
flask holds one color. No ads, no purchases, no lives, no timers. It is written
in [Goose](https://github.com/aardappel/goose), and the whole toolchain comes
from this repo's Nix flake.

## Running

```sh
nix run                                   # play
nix run . -- --level 26                   # jump to a campaign level
nix run . -- --seed 4242 --like 30        # the board brewed from a seed
nix run . -- --hand 8                     # built-in hand-made level 8 of 0-25 (src/core/levels.goose)
nix run . -- --autoplay                   # watch the hint solver play
nix run . -- --size 900 1600              # a bigger window (it remembers the size you leave it)
nix run . -- --export-music out           # write each room's music loop to out/*.wav
nix flake check                           # unit tests
```

To work on the code, use the dev shell. Goose runs programs in-process with
its TinyCC backend, so there's no build step:

```sh
nix develop
goose src/main.goose                      # the game, from source
goose src/main.goose -- --level 12        # with arguments
goose src/tests.goose                     # the tests
```

`nix build` produces a native `-O2` build instead (`result/bin/alchemists-sort`).

**In the browser.** `nix build .#web` builds a static folder (`index.html`,
`.js`, `.wasm`, `.data`) you can host anywhere; `nix run .#web` serves it at
http://localhost:8000. It needs a browser with WebGL 2. Progress and settings
are saved in the browser's own storage, per site and per browser. Goose's C
output is compiled with Emscripten; `web/` holds the parts the browser needs
in place of the desktop ones, the main one a WebGL 2 version of Goose's gfx
layer (`web/gfx_web.c`).

Every push and pull request runs the tests and builds the browser version in
GitHub Actions (`.github/workflows/pages.yml`); a push to `main` publishes it
on GitHub Pages. CI keeps the Nix store in GitHub's Actions cache, so a
change to the game rebuilds only the game. The tests and the web build use
`goose-compiler`, the Goose compiler without SDL and its modules, which is all
they need and builds in about half the time.

**Graphics.** goose draws through SDL3's GPU API, which uses Vulkan on Linux,
so the desktop build needs a working Vulkan driver. On NixOS that means
`hardware.graphics.enable = true`. On other distributions, programs built with
Nix can't load the system's graphics drivers on their own; a wrapper such as
[nixGL](https://github.com/nix-community/nixGL) is the usual fix. The browser
version only needs WebGL 2.

## Playing

Tap a flask, then another, to pour. Only the top run of one color moves, and
only as much as fits. Liquid lands on the same color or in an empty flask. You
win when every flask holding liquid is full and holds a single color. If no
legal pour is left, or the few left can no longer win the board, you can
retry the same board, undo, or add a flask.

The tools are free and unlimited, and each level counts how often you used
them:

| Tool | Key | What it does |
|---|---|---|
| Undo | `U`, `Ctrl+Z` | Step back, all the way to the start |
| Restart | `R` | The same board, from the beginning |
| Shuffle | `S` | Re-deal the visible liquid, keeping the board solvable |
| Extra flask | `F` | One more empty flask, for this attempt |
| Hint | `H` | Highlight the solver's next move |

`Esc` goes back.

The book at the top right (or `G`) opens the **Grimoire**: the modifiers on
this level, each with its rule and the ways it meets the others here; tap a
line and its flasks light up on the board. **Press and hold** a flask (or
right-click it) to read it: what it is, how it stands, why it can't pour
right now and what would change that, with dotted lines to the flasks tied
to it.

The campaign is six chapters of 15 levels, then the endless Great Work.
In each chapter, levels 5 and 10 are **Hard** and 15 is a hand-made **Super
Hard** finale that combines the chapter's modifiers with earlier ones. Each
modifier is taught in its own hand-made tutorial, then shows up in every
level until the next tutorial, alongside one or two from earlier chapters.
Smoke is the background of every level from 3 on, and from level 12 every
fourth level has a Tall Flask, spanning two rows of the grid the flasks
stand in (three on Hard levels). A tall flask is for one color, tinted on its
glass: it comes with some of that color, takes only that color, and nothing
ever comes out of it. A Vow Flask takes the first color poured in, then
only that one; it doesn't have to be used, and left empty it doesn't stand
in the way of the win. A key buried in a layer comes free when that layer
reaches the top of its flask, and opens the door of its metal (brass,
silver or copper): the two or three flasks behind a door are out of play
until then. A curtain hides a flask until a flask of the color on its badge
is completed. The rules of every modifier, and how they meet
through heat, light, flow, flip, growth and transmutation, are in
[docs/revamp.md](docs/revamp.md).

| Chapter | Levels | New (tutorial level) |
|---|---|---|
| The Apothecary | 1–15 | Smoke (3), Seal (6), Tall Flask (8), Vow Flask (11) |
| The Frost Cellar | 16–30 | Rime (18), Brazier (21), Quicksilver (26) |
| The Glassworks | 31–45 | Siphon (33), Keys and Doors (36), Curtain (41) |
| The Observatory | 46–60 | Lantern (48), Shroud (51), Hourglass (56) |
| The Greenhouse | 61–75 | Creeping Vine (63), Salamander (66), Moonpetal (71) |
| The Athanor | 76–90 | Athanor (78), Philosopher's Drop (81), Catalyst (86) |
| The Great Work | 91+ | three or four modifiers from everything |

Settings has sound, a color-blind palette that adds a symbol to every color,
and a progress reset. Progress is saved in
`$XDG_DATA_HOME/alchemists-sort/save.txt`, or
`~/.local/share/alchemists-sort/save.txt` if `XDG_DATA_HOME` isn't set.

## Adding levels

Every shipped level is built in: the tutorials and examples are written in
Goose in `src/core/levels.goose`, in a compact form close to how a level
reads (`flask("GGBR").under_murk(3)`, `flask("BRGG").rime(4)`,
`flask("RGBY").key_at(1, KeyColor.Brass)`, ...); the
comment at the top of that file describes it. Generated levels come from
`src/core/campaign.goose` (what each level asks for) and
`src/core/generator.goose`, which deals a random board, adds the modifiers
and keeps the deal only if the solver can win it. A seed plus a level shape
always gives the same board. Every hand-made level is checked and solved by
the tests.

## Code layout

```
flake.nix               goose (pinned in flake.lock), the game, the tests, a dev shell
nix/goose.nix           goose + its vendored SDL3/TinyCC/Nuklear/Box3D, set up for NixOS
nix/game.nix            native build of the game, with its levels and fonts
nix/tests.nix           the unit tests, for `nix flake check`
src/core/               the rules, with no drawing or input
  board.goose           bottles, pours, every modifier, win and loss, the grid and neighbors
  solver.goose          weighted A*, used by the generator, shuffle and hints
  generator.goose       seeded level generation
  campaign.goose        level numbers, tutorials, difficulty ramp
  levels.goose          the hand-made levels, built in
  tools.goose           shuffle and hint
  explain.goose         the board in words: the Grimoire, a flask's card, refusals, pour previews
src/app/                rendering, text, sound, saving
  draw.goose            one instanced pipeline; all art is signed distance fields in its shader
  shaders.goose         that shader: every shape, the chapters' rooms and tables, each color's shimmer
  scene.goose           the workbench: rooms, the table, candlelight, motes, the back shelf
  fx.goose              slosh, droplets, stoppers and labels, ink between screens, the win's finale
  menus.goose           the title screen and the chapter map
  guide.goose           the Grimoire panel, a held flask's card, the pour marks
  sfx.goose             sounds synthesized at startup; each color is a pentatonic note
src/main.goose          screens, input, animation
src/tests.goose         unit tests
```

The art and sounds are original and procedural: shapes drawn in a shader and
tones synthesized at startup. The fonts are Cinzel (from nixpkgs) and
Raleway (from Nuklear's sources), both under the SIL Open Font License.

To move to a newer goose, run `nix flake update goose-src`. Goose is young,
so run `nix flake check` afterwards.

## License

MIT, see [LICENSE](LICENSE). The bundled fonts keep their own licenses: Cinzel
and Raleway are both under the SIL Open Font License.
