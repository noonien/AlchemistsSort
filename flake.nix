{
  description = "Alchemist's Sort: a calm potion-sorting puzzle written in Goose";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # The Goose compiler and its vendored SDL3 / TinyCC / Nuklear / Box3D
    # submodules. `nix flake update goose-src` moves to the latest commit.
    goose-src = {
      url = "git+https://github.com/aardappel/goose?submodules=1&shallow=1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, goose-src }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});

      # What the builds read: a change anywhere else (the README, CI) rebuilds
      # nothing.
      src = nixpkgs.lib.fileset.toSource {
        root = ./.;
        fileset = nixpkgs.lib.fileset.unions [ ./src ./data ./web ];
      };
    in {
      packages = forAll (system: pkgs:
        let
          goose = pkgs.callPackage ./nix/goose.nix { src = goose-src; };
          # The compiler alone: enough to emit C, for the tests and the web build.
          goose-compiler = pkgs.callPackage ./nix/goose.nix { src = goose-src; minimal = true; };
          game = pkgs.callPackage ./nix/game.nix { inherit goose src; };
          web = pkgs.callPackage ./nix/web.nix { goose = goose-compiler; inherit src; };
        in {
          inherit goose goose-compiler game web;
          default = game;
        });

      apps = forAll (system: pkgs: {
        default = { type = "app"; program = "${self.packages.${system}.game}/bin/alchemists-sort"; };
        goose = { type = "app"; program = "${self.packages.${system}.goose}/bin/goose"; };
        # The browser build, served at http://localhost:8000.
        web = {
          type = "app";
          program = "${pkgs.writeShellScript "serve-alchemists-sort" ''
            echo "Alchemist's Sort: http://localhost:8000"
            exec ${pkgs.python3}/bin/python3 -m http.server 8000 --directory ${self.packages.${system}.web}
          ''}";
        };
      });

      checks = forAll (system: pkgs: {
        tests = pkgs.callPackage ./nix/tests.nix { goose = self.packages.${system}.goose-compiler; inherit src; };
      });

      # `nix develop`, then `goose src/main.goose` runs the game from source
      # (in-process, no build step) and `goose src/tests.goose` the tests.
      devShells = forAll (system: pkgs: {
        default = pkgs.mkShell {
          packages = [ self.packages.${system}.goose ];
          shellHook = self.packages.${system}.goose.runtimeEnv + ''
            export ALCHEMIST_SORT_DATA="$PWD/data"
            export ALCHEMIST_SORT_FONTS="${self.packages.${system}.game}/share/alchemists-sort/fonts"
          '';
        };
      });
    };
}
