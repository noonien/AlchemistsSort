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
nix run . -- --file my_level.json         # a hand-made level
nix run . -- --autoplay                   # watch the hint solver play
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

`E` saves the current board to your levels folder as a level file. `Esc`
goes back.

Levels are numbered and get harder: more colors, more hidden layers, more
obstacles. Every 5th level is **Hard** and every 10th is **Super Hard**. Each
obstacle is introduced in its own tutorial level before it appears anywhere
else:

| Level | Obstacle | Rule |
|---|---|---|
| 4 | Hidden layers | Segments under the top show as `?` until uncovered |
| 8 | Split color | One color starts spread over two flasks |
| 13 | Mystery flask | Takes the first color poured in, then only that color; must end full |
| 17 | Cloaked flask | Hidden and shut until a flask of the badge's color is completed |
| 21 | Frozen flask | Shut until N more pours have been made anywhere |
| 26 | Corked flask | Pour the cork's color onto it to pop it; the liquid lands inside |
| 31 | Locked vault | Like a cork, with a padlock; one vault can hold the next one's key |
| 36 | Curtain | A hidden flask that appears once enough flasks stand empty |
| 41 | Gift box | Opens on any pour, which lands on the mixed flask inside |
| 46 | Long flask | A taller flask (5 to 8 layers); one color comes in enough to fill it |

Settings has sound, a color-blind palette that adds a symbol to every color,
and a progress reset. Progress is saved in
`$XDG_DATA_HOME/alchemists-sort/save.txt`, or
`~/.local/share/alchemists-sort/save.txt` if `XDG_DATA_HOME` isn't set.

## Adding levels

Levels are JSON. Put your own in `~/.local/share/alchemists-sort/levels/` and
they show up under **My Levels**. You can also play one directly with
`--file`.

```json
{
  "name": "First Frost",
  "difficulty": "hard",
  "hint": "Shown when the level starts.",
  "bottles": [
    "RRGB",
    { "liquid": "GGBR", "hidden": 3 },
    { "kind": "frozen", "liquid": "BRGG", "thaw": 4 },
    { "kind": "cork",   "liquid": "YY",   "key": "Y" },
    { "liquid": "VV", "height": 6 },
    "VVVV",
    ""
  ]
}
```

- **Liquid** is written bottom to top, one letter per segment, as many as the
  flask's height. `""` is an empty flask. Every color used must appear exactly
  4 times, or as many times as a long flask is tall, one color per long flask.
- **Colors:** `R` ruby, `O` amber, `Y` sun, `L` lime, `G` emerald, `C` sky,
  `B` sapphire, `V` violet, `K` rose, `N` umber, `W` pearl, `S` slate, `T`
  teal, `A` olive.
- **Kinds:** `plain` (the default), `mystery`, `cloak` (`key`), `frozen`
  (`thaw`), `cork` (`key`), `vault` (`key`), `curtain` (`empties`), `gift`.
- **`hidden`** is how many of the lowest segments start as `?`.
- **`height`** makes a long flask, 5 to 8 segments tall (4 by default). It
  works with any kind.
- **`difficulty`** is `normal`, `hard` or `super hard` and only sets the
  label.

The game checks a level's structure when it loads it. To check that a level
can actually be won, drop it into `data/levels/examples/` and run the tests:
every shipped level is solved as part of `nix flake check`.

The campaign's tutorials are in `data/levels/tutorial/`. A file
`data/levels/campaign/<n>.json` replaces generated level `n` with a hand-made
one. Generated levels come from `src/core/campaign.goose` (what each level
asks for) and `src/core/generator.goose`, which deals a random board, adds
the obstacles and keeps the deal only if the solver can win it. A seed plus
a level shape always gives the same board.

## Code layout

```
flake.nix               goose (pinned in flake.lock), the game, the tests, a dev shell
nix/goose.nix           goose + its vendored SDL3/TinyCC/Nuklear/Box3D, set up for NixOS
nix/game.nix            native build of the game, with its levels and fonts
nix/tests.nix           the unit tests, for `nix flake check`
src/core/               the rules, with no drawing or input
  board.goose           bottles, pours, every obstacle, win and loss
  solver.goose          weighted A*, used by the generator, shuffle and hints
  generator.goose       seeded level generation
  campaign.goose        level numbers, tutorials, difficulty ramp
  level_io.goose        the JSON level format, read and write
  tools.goose           shuffle and hint
src/app/                rendering, text, sound, saving
  draw.goose            one instanced pipeline; all art is signed distance fields in its shader
src/main.goose          screens, input, animation
src/tests.goose         unit tests
data/levels/            tutorial and example levels
```

The art and sounds are original and procedural: shapes drawn in a shader and
tones synthesized at startup. The fonts are Cinzel (from nixpkgs) and
Raleway (from Nuklear's sources), both under the SIL Open Font License.

To move to a newer goose, run `nix flake update goose-src`. Goose is young,
so run `nix flake check` afterwards.

## License

MIT, see [LICENSE](LICENSE). The bundled fonts keep their own licenses: Cinzel
and Raleway are both under the SIL Open Font License.
