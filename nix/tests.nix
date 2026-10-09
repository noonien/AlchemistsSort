# The unit tests (rules, every modifier, solver, generator and every shipped
# level), compiled natively and run in the build sandbox.
{ stdenv, goose, src }:

stdenv.mkDerivation {
  name = "alchemists-sort-tests";
  inherit src;
  nativeBuildInputs = [ goose ];
  buildPhase = ''
    goose --emit-runtime runtime.c
    goose -O2 --include src/c/ogg.h -o tests.c src/tests.goose
    $CC -O2 tests.c runtime.c -o tests -lm -pthread
    ./tests
  '';
  installPhase = "touch $out";
}
