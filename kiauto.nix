{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  makeWrapper,
  autoPatchelfHook,
  python3,
  kicad,
  imagemagick,
  xdotool,
  xclip,
  xvfb-run,
  libxslt,
}:
let
  # This scaffolding deliberately parallels kibot.nix instead of sharing
  # a helper. The python package sets and PATH tools are disjoint, and
  # kibot additionally wraps its binaries with KICAD environment
  # variables, so a shared function would take every field as an
  # argument and abstract nothing.
  pythonEnv = python3.withPackages (
    ps: with ps; [
      psutil
      xvfbwrapper
    ]
  );
  pythonPath = lib.concatStringsSep ":" [
    "${pythonEnv}/${python3.sitePackages}"
    "${kicad.base}/${python3.sitePackages}"
  ];
  runtimePath = lib.makeBinPath [
    kicad.base
    imagemagick
    xdotool
    xclip
    xvfb-run
    libxslt
  ];
in
stdenv.mkDerivation rec {
  pname = "kiauto";
  version = "2.3.8";

  src = fetchurl {
    url = "https://github.com/INTI-CMNB/KiAuto/releases/download/v${version}/kiauto_${version}-1_all.deb";
    hash = "sha256-w7Dm6Mzc+DXGYUhVlkLeW90jH/s28GBjTHXOTEIX0c8=";
  };

  nativeBuildInputs = [
    dpkg
    makeWrapper
    autoPatchelfHook
  ];

  unpackPhase = "dpkg-deb -x $src .";

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/${python3.sitePackages}
    cp -r usr/bin/* $out/bin/
    cp -r usr/lib/python3/dist-packages/kiauto $out/${python3.sitePackages}/
    cp -r usr/lib/python3/dist-packages/kiauto-${version}.egg-info $out/${python3.sitePackages}/
    sed -i "1s|.*|#!${pythonEnv}/bin/python3|" $out/bin/*
    for bin in $out/bin/*; do
      wrapProgram "$bin" \
        --prefix PYTHONPATH : "$out/${python3.sitePackages}:${pythonPath}" \
        --prefix PATH : "${runtimePath}"
    done
    runHook postInstall
  '';

  meta = {
    description = "KiCad UI automation for eeschema and pcbnew";
    homepage = "https://github.com/INTI-CMNB/KiAuto";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
