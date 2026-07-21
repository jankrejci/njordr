{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  makeWrapper,
  python3,
  kicad,
  imagemagick,
  ghostscript,
  librsvg,
  kiauto,
}:
let
  pythonEnv = python3.withPackages (
    ps: with ps; [
      colorama
      lark
      markdown2
      qrcodegen
      requests
      xlsxwriter
      pyyaml
      wxpython
      xvfbwrapper
      lxml
      mistune
    ]
  );
  pythonPath = lib.concatStringsSep ":" [
    "${pythonEnv}/${python3.sitePackages}"
    "${kiauto}/${python3.sitePackages}"
    "${kicad.base}/${python3.sitePackages}"
  ];
  runtimePath = lib.makeBinPath [
    kicad.base
    imagemagick
    ghostscript
    librsvg
    kiauto
  ];
  # kicad carries library packages separately from the base binary.
  symbolDir = "${kicad.libraries.symbols}/share/kicad/symbols";
  footprintDir = "${kicad.libraries.footprints}/share/kicad/footprints";
  # The KICAD<major>_* env-var names must track the wrapped kicad version,
  # so derive the major from the package instead of hardcoding it.
  kicadMajor = lib.versions.major kicad.base.version;
in
stdenv.mkDerivation rec {
  pname = "kibot";
  version = "1.9.0";

  src = fetchurl {
    url = "https://github.com/INTI-CMNB/KiBot/releases/download/v${version}/kibot_${version}-1_all.deb";
    hash = "sha256-isA6WuGykW+iO3uWFV/FwbsGy60vzzyQEOFXf3/DgtE=";
  };

  nativeBuildInputs = [
    dpkg
    makeWrapper
  ];

  unpackPhase = "dpkg-deb -x $src .";

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/${python3.sitePackages} $out/share $out/share/kicad/template
    cp -r usr/bin/* $out/bin/
    cp -r usr/lib/python3/dist-packages/kibot $out/${python3.sitePackages}/
    cp -r usr/lib/python3/dist-packages/kibot-${version}.egg-info $out/${python3.sitePackages}/
    cp -r usr/share/kibot $out/share/

    # shutil.copy2 preserves the read-only mode bits from Nix store files onto the
    # temp-dir copy, which kibot then tries to overwrite. Replace with copyfile,
    # which copies only content without preserving mode, followed by an explicit
    # chmod so the dest is writable.
    substituteInPlace $out/${python3.sitePackages}/kibot/kicad/config.py \
      --replace-fail 'from shutil import copy2' \
                     'import os as _os; from shutil import copy2, copyfile as _copyfile' \
      --replace-fail 'copy2(fname, dest)' '_copyfile(fname, dest); _os.chmod(dest, 0o644)'

    # Python 3.14 removed the deprecated ast.Num and ast.Str aliases, but the
    # vendored mcpyrate still probes them in fallback branches for pre-3.8
    # syntax trees. Evaluating the attribute alone raises AttributeError, so
    # neutralize the dead branches.
    substituteInPlace $out/${python3.sitePackages}/kibot/mcpyrate/unparser.py \
      --replace-fail '(isinstance(v, ast.Num) and isinstance(v.n, int))' \
                     'False' \
      --replace-fail 'elif type(v) is ast.Str:  # up to Python 3.7' \
                     'elif False:  # ast.Str was removed in Python 3.14'
    substituteInPlace $out/${python3.sitePackages}/kibot/mcpyrate/multiphase.py \
      --replace-fail 'elif type(arg) is ast.Num:  # TODO: Python 3.8: remove ast.Num' \
                     'elif False:  # ast.Num was removed in Python 3.14' \
      --replace-fail 'elif type(macroarg) is ast.Num:  # TODO: Python 3.8: remove ast.Num' \
                     'elif False:  # ast.Num was removed in Python 3.14'
    substituteInPlace $out/${python3.sitePackages}/kibot/mcpyrate/debug.py \
      --replace-fail 'elif type(arg) is ast.Str:  # up to Python 3.7' \
                     'elif False:  # ast.Str was removed in Python 3.14'

    # Python 3.14 also removed the Constant.s accessor property, which the
    # document macro uses to read and write the docstring Constant. The
    # property mapped straight to Constant.value, so substitute the real
    # attribute.
    substituteInPlace $out/${python3.sitePackages}/kibot/macros.py \
      --replace-fail '.format(value.s)' '.format(value.value)' \
      --replace-fail 's.value.s.rstrip()' 's.value.value.rstrip()' \
      --replace-fail 'help_str.s = ' 'help_str.value = ' \
      --replace-fail 'Constant(s=reg_name)' 'Constant(value=reg_name)'

    # Merge sym-lib-table and fp-lib-table into one template dir so kibot
    # can resolve both symbol and footprint library tables from a single path.
    cp ${kicad.libraries.symbols}/share/kicad/template/sym-lib-table $out/share/kicad/template/
    cp ${kicad.libraries.footprints}/share/kicad/template/fp-lib-table $out/share/kicad/template/

    # kibot looks for resources at <module_dir>/resources/<name>, falling back
    # to /usr/share/kibot/<name>. Neither path works in Nix without this symlink.
    ln -s $out/share/kibot $out/${python3.sitePackages}/kibot/resources

    sed -i "1s|.*|#!${pythonEnv}/bin/python3|" $out/bin/*
    for bin in $out/bin/*; do
      wrapProgram "$bin" \
        --prefix PYTHONPATH : "$out/${python3.sitePackages}:${pythonPath}" \
        --prefix PATH : "${runtimePath}" \
        --set "KICAD${kicadMajor}_SYMBOL_DIR" "${symbolDir}" \
        --set "KICAD${kicadMajor}_FOOTPRINT_DIR" "${footprintDir}" \
        --set "KICAD${kicadMajor}_TEMPLATE_DIR" "$out/share/kicad/template"
    done
    runHook postInstall
  '';

  meta = {
    description = "KiCad automation for ERC, DRC, gerber, BoM, and position outputs";
    homepage = "https://github.com/INTI-CMNB/KiBot";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
