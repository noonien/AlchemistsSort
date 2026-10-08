# The unit tests (rules, every obstacle, solver, generator, level format and
# every shipped level), compiled natively and run in the build sandbox.
{ stdenv, goose, src }:

stdenv.mkDerivation {
  name = "alchemists-sort-tests";
  inherit src;
  nativeBuildInputs = [ goose ];
  buildPhase = ''
    goose --emit-runtime runtime.c
    goose -O2 -o tests.c src/tests.goose
    $CC -O2 tests.c runtime.c -o tests -lm -pthread
    ALCHEMIST_SORT_DATA=data ./tests
  '';
  installPhase = "touch $out";
}
