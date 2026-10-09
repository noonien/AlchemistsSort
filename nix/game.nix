# Alchemist's Sort, compiled to native code: Goose writes C, the C compiler
# builds it against the gfx, ui and audio layers. The fonts and the music
# go in share/, and the wrapper points the game at them.
{ lib, stdenv, goose, src, cinzel, makeWrapper }:

let
  data = "share/alchemists-sort";
in
stdenv.mkDerivation {
  pname = "alchemists-sort";
  version = "1.0";
  inherit src;

  nativeBuildInputs = [ goose makeWrapper ];

  buildPhase = ''
    runHook preBuild
    goose --emit-runtime runtime.c
    goose -O2 --include src/c/stream.h -o game.c src/main.goose
    $CC -O2 -c runtime.c -o runtime.o
    $CC -O2 -DALCH_STREAM_SDL game.c runtime.o -o alchemists-sort \
      @$(goose --ui-link cc) @$(goose --gfx-link cc) @$(goose --audio-link cc) -lm -pthread
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/libexec $out/${data}/fonts $out/${data}/music
    cp assets/music/*.ogg $out/${data}/music/
    cp alchemists-sort $out/libexec/
    cp ${cinzel}/share/fonts/truetype/Cinzel-Bold.ttf $out/${data}/fonts/
    cp ${goose.source}/third_party/nuklear/extra_font/Raleway-Bold.ttf $out/${data}/fonts/
    makeWrapper $out/libexec/alchemists-sort $out/bin/alchemists-sort \
      --run ${lib.escapeShellArg goose.runtimeEnv} \
      --set-default ALCHEMIST_SORT_DATA $out/${data}
    runHook postInstall
  '';

  passthru.fonts = "${placeholder "out"}/${data}/fonts";

  meta = {
    description = "A calm potion-sorting puzzle: no ads, no timers, just the puzzle";
    license = lib.licenses.mit;
    mainProgram = "alchemists-sort";
  };
}
