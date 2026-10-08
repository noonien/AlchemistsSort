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
    in {
      packages = forAll (system: pkgs:
        let
          goose = pkgs.callPackage ./nix/goose.nix { src = goose-src; };
          game = pkgs.callPackage ./nix/game.nix { inherit goose; src = self; };
        in {
          inherit goose game;
          default = game;
        });

      apps = forAll (system: pkgs: {
        default = { type = "app"; program = "${self.packages.${system}.game}/bin/alchemists-sort"; };
        goose = { type = "app"; program = "${self.packages.${system}.goose}/bin/goose"; };
      });

      checks = forAll (system: pkgs: {
        tests = pkgs.callPackage ./nix/tests.nix { goose = self.packages.${system}.goose; src = self; };
      });

      devShells = forAll (system: pkgs: {
        default = pkgs.mkShell {
          packages = [ self.packages.${system}.goose pkgs.python3 pkgs.gcc ];
          shellHook = self.packages.${system}.goose.runtimeEnv;
        };
      });
    };
}
