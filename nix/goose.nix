# The Goose compiler, built from the pinned source with its vendored SDL3,
# TinyCC, Nuklear and Box3D, and installed as a relocatable tree:
#
#   lib/goose/goose            the compiler (finds stdlib/ next to itself)
#   lib/goose/stdlib/          the standard library
#   lib/goose/tcclib/          TinyCC's runtime, for in-process (JIT) runs
#   lib/goose/{gfx,ui,audio,physics}/   link-cc.rsp + the static archives
#   bin/goose                  wrapper that sets up SDL's runtime libraries
#
# SDL is built static with its system dependencies loaded at runtime, so the
# wrapper puts X11/Wayland/audio/Vulkan on LD_LIBRARY_PATH. The Vulkan driver
# is the system's: on NixOS, hardware.graphics.enable provides it.
#
# `minimal = true` builds the compiler alone, without SDL, the in-process
# backend or the gfx/ui/audio/physics modules. It emits the same C, which is
# all the tests and the web build need, and builds in a fraction of the time.
{ minimal ? false, lib, stdenv, src, cmake, ninja, pkg-config, python3, makeWrapper
, glibc, libx11, libxext, libxcursor, libxi, libxfixes, libxrandr, libxrender
, libxscrnsaver, libxtst, libxcb, xorgproto, libxkbcommon, wayland, wayland-scanner, wayland-protocols, libdecor
, libpulseaudio, alsa-lib, pipewire, vulkan-loader, vulkan-headers, systemdLibs, dbus
}:

let
  runtimeLibs = [
    libx11 libxext libxcursor libxi libxfixes libxrandr libxrender libxscrnsaver libxtst
    libxkbcommon wayland libdecor
    libpulseaudio alsa-lib pipewire vulkan-loader systemdLibs dbus
  ];
  # Shell snippet shared by the wrapper and the dev shell.
  runtimeEnv = ''
    export LD_LIBRARY_PATH="${lib.makeLibraryPath runtimeLibs}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';
in
stdenv.mkDerivation {
  pname = if minimal then "goose-compiler" else "goose";
  version = "unstable-${src.lastModifiedDate or "0"}";
  inherit src;

  nativeBuildInputs = [ cmake ninja pkg-config python3 makeWrapper ]
    ++ lib.optional (!minimal) wayland-scanner;
  buildInputs = lib.optionals (!minimal)
    (runtimeLibs ++ [ libxcb xorgproto wayland-protocols vulkan-headers ]);

  # TinyCC's defaults look for the C library under /usr, which NixOS lacks.
  postPatch = ''
    substituteInPlace cmake/libtcc.cmake --replace-fail \
      '#define CONFIG_TCC_BCHECK 0' \
      '#define CONFIG_TCC_BCHECK 0
    #define CONFIG_TCC_SYSINCLUDEPATHS \"{B}/include:${lib.getDev glibc}/include\"
    #define CONFIG_TCC_LIBPATHS \"{B}:${glibc}/lib\"
    #define CONFIG_TCC_CRTPREFIX \"${glibc}/lib\"
    #define CONFIG_TCC_ELFINTERP \"${stdenv.cc.bintools.dynamicLinker}\"'
  '';

  cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ] ++ lib.optionals minimal [
    "-DGOOSE_LIBTCC=OFF" "-DGOOSE_GFX=OFF" "-DGOOSE_AUDIO=OFF" "-DGOOSE_PHYSICS=OFF" "-DGOOSE_UI=OFF"
  ];

  # Generated link files name archives inside the build tree; they are copied
  # next to the installed compiler and rewritten to point there.
  installPhase = ''
    runHook preInstall
    dest=$out/lib/goose
    mkdir -p $dest $out/bin
    cp goose $dest/
    cp -r ../stdlib $dest/stdlib
    [ -d tcclib ] && cp -r tcclib $dest/tcclib
    for m in gfx ui audio physics; do
      rsp=$(find . -path "./$m/*" -name link-cc.rsp | head -n1)
      [ -n "$rsp" ] || continue
      mkdir -p $dest/$m
      for a in $(grep -oE '[^ "]+\.a' "$rsp"); do
        cp "$a" $dest/$m/
      done
      sed -E "s#[^ \"]*/([^/ \"]+\.a)#$dest/$m/\1#g" "$rsp" > $dest/$m/link-cc.rsp
    done
    makeWrapper $dest/goose $out/bin/goose ${lib.optionalString (!minimal) "--run ${lib.escapeShellArg runtimeEnv}"}
    runHook postInstall
  '';

  passthru = { inherit runtimeEnv runtimeLibs; source = src; };

  meta = {
    description = "A memory-safe systems language with no heap allocator";
    homepage = "https://github.com/aardappel/goose";
    license = lib.licenses.asl20;
    mainProgram = "goose";
  };
}
