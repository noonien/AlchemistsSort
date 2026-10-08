# Goose's vendored SDL3, built for the browser with Emscripten: the window,
# input and audio of the web build. Its own derivation, since it depends only
# on the pinned Goose source and so stays cached while the game changes.
{ stdenv, goose, emscripten, cmake, ninja, python3 }:

stdenv.mkDerivation {
  pname = "sdl3-emscripten";
  version = goose.version;
  src = "${goose.source}/third_party/SDL";

  nativeBuildInputs = [ emscripten cmake ninja python3 ];

  dontUseCmakeConfigure = true;

  configurePhase = ''
    runHook preConfigure
    export HOME=$TMPDIR
    export EM_CACHE=$TMPDIR/emcache
    cp -r ${emscripten}/share/emscripten/cache $EM_CACHE
    chmod -R u+w $EM_CACHE
    emcmake cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF -DSDL_TEST_LIBRARY=OFF \
      -DSDL_EXAMPLES=OFF -DCMAKE_INSTALL_PREFIX=$out
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cmake --build build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cmake --install build
    runHook postInstall
  '';
}
