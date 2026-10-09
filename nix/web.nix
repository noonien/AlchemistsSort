# Alchemist's Sort for the browser: the same C that Goose writes for the
# native build, compiled to WebAssembly with Emscripten. Goose's own ui and
# audio layers build unchanged against SDL3's Emscripten port (Goose's
# vendored copy); its gfx layer is replaced by web/gfx_web.c, on WebGL 2,
# since SDL_GPU has no web backend. web/shaders.py turns the shaders the
# game embeds into GLSL ES. Progress is kept in the browser's IndexedDB.
#
# The result is a static folder: host it anywhere, or `nix run .#web`.
{ lib, stdenv, callPackage, goose, src, cinzel, emscripten, python3, spirv-cross }:

let
  gs = goose.source;
  sdl = callPackage ./sdl-web.nix { inherit goose; };
  # Room for each Goose data stack (see web/runtime_web.c). The tests pass
  # with 4 MB; a browser commits only the pages a stack touches.
  stackReserve = "(16ull<<20)";
in
stdenv.mkDerivation {
  pname = "alchemists-sort-web";
  version = "1.0";
  inherit src;

  nativeBuildInputs = [ goose emscripten python3 spirv-cross ];

  configurePhase = ''
    runHook preConfigure
    export HOME=$TMPDIR
    # Emscripten writes the system libraries it builds into its cache.
    export EM_CACHE=$TMPDIR/emcache
    cp -r ${emscripten}/share/emscripten/cache $EM_CACHE
    chmod -R u+w $EM_CACHE
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    # The game, as C, and its shaders as GLSL ES.
    goose --emit-runtime runtime.c
    goose -O2 --include src/c/ogg.h -o game.c src/main.goose
    python3 web/shaders.py game.c shaders_web.c spirv-cross

    defs='-DGS_STACK_RESERVE=${stackReserve}'
    emcc -O2 $defs -Dmmap=gs_web_mmap -Dmprotect=gs_web_mprotect -Dmunmap=gs_web_munmap \
      -c runtime.c -o runtime.o
    emcc -O2 $defs -c game.c -o game.o
    emcc -O2 -c web/runtime_web.c -o runtime_web.o
    emcc -O2 -I${sdl}/include -I${gs}/src/gfx -Iweb -c web/gfx_web.c -o gfx_web.o
    emcc -O2 -Iweb -c shaders_web.c -o shaders_web.o
    emcc -O2 -I${sdl}/include -I${gs}/src/audio -c ${gs}/src/audio/audio.c -o audio.o
    for f in ${gs}/src/ui/*.c; do
      emcc -O2 -I${gs}/src/ui -I${gs}/third_party/nuklear -c $f -o ui_$(basename $f .c).o
    done

    mkdir -p site/data/fonts site/data/samples
    cp samples/*.ogg samples/bank.txt site/data/samples/
    cp ${cinzel}/share/fonts/truetype/Cinzel-Bold.ttf site/data/fonts/
    cp ${gs}/third_party/nuklear/extra_font/Raleway-Bold.ttf site/data/fonts/
    chmod -R u+w site

    # Asyncify lets gfx::frame() hand the browser control between frames
    # without restructuring the game's main loop.
    mkdir -p out
    emcc -O2 *.o ${sdl}/lib/libSDL3.a -o out/index.html \
      -sASYNCIFY -sASYNCIFY_STACK_SIZE=1048576 -sSTACK_SIZE=8388608 \
      -sALLOW_MEMORY_GROWTH -sMAXIMUM_MEMORY=4GB -sINITIAL_MEMORY=67108864 \
      -sMIN_WEBGL_VERSION=2 -sMAX_WEBGL_VERSION=2 -sENVIRONMENT=web \
      -sFORCE_FILESYSTEM -lidbfs.js --pre-js web/pre.js --shell-file web/shell.html \
      --preload-file site/data@/data

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp out/index.html out/index.js out/index.wasm out/index.data $out/
    runHook postInstall
  '';

  passthru = { inherit sdl; };

  meta = {
    description = "Alchemist's Sort, built for web browsers";
    license = lib.licenses.mit;
  };
}
