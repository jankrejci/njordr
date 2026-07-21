# Headless KiCad DRC/ERC gates for the vetroplach PCB boards.
#
# Both boards reference the shared local library in `pcb/components/`, the
# `vetroplach.pretty` footprints and the `vetroplach.kicad_sym` symbols,
# through `${KIPRJMOD}/../components`, so each gate stages the board
# directory and the components directory side by side in a writable work
# tree, exactly mirroring the repo layout, before invoking kicad-cli.
{ pkgs }:
let
  # Resolve KiCad's stock symbol/footprint libraries for the headless
  # DRC/ERC checks. Without a global library table the CLI cannot find
  # the standard libraries the boards reference, such as Connector_*,
  # MountingHole, power, and Device, and both ERC and the DRC parity check
  # degrade to a flood of spurious "configuration does not include
  # library X" warnings. The full `kicad` package ships those libraries
  # and its wrapper exports the KICAD*_{FOOTPRINT,SYMBOL}_DIR that the
  # stock tables in KICAD*_TEMPLATE_DIR reference. We copy those tables
  # into the per-version config dir the CLI reads. KiCad names the dir
  # `<major>.0`; a cp failure on a version bump surfaces loudly here.
  kicadMajor = "10";
  kicadLibTableSetup = ''
    export HOME=$(mktemp -d)
    eval "$(grep '^export KICAD${kicadMajor}_TEMPLATE_DIR=' "$(command -v kicad-cli)")"
    cfg="$HOME/.config/kicad/${kicadMajor}.0"
    mkdir -p "$cfg"
    cp "$KICAD${kicadMajor}_TEMPLATE_DIR"/fp-lib-table "$cfg/"
    cp "$KICAD${kicadMajor}_TEMPLATE_DIR"/sym-lib-table "$cfg/"
  '';

  # Stage one board plus the shared components library into a writable
  # work tree that mirrors the repo's pcb/ level, so
  # `${KIPRJMOD}/../components` resolves and KiCad reads the board's
  # reviewed exclusions from its .kicad_pro exactly as it does
  # interactively.
  stageBoard = board: ''
    work=$(mktemp -d)
    mkdir -p "$work/pcb/${board}" "$work/pcb/components"
    cp -r ${../pcb + "/${board}"}/. "$work/pcb/${board}"/
    cp -r ${../pcb/components}/. "$work/pcb/components"/
    chmod -R +w "$work"
  '';

  # DRC gate. `--schematic-parity` compares the PCB footprints against the
  # schematic symbols so library or symbol drift cannot slip through.
  # `--severity-error --exit-code-violations` fails the build on any
  # error-severity violation; warnings are intentionally not gated while
  # the first-iteration boards still carry benign silkscreen-overlap and
  # footprint-filter warnings, which mirrors warnings_as_errors:false in
  # jlcpcb.kibot.yaml. Tighten to --severity-warning once those are
  # resolved.
  drc =
    board:
    pkgs.runCommand "drc-${board}"
      {
        nativeBuildInputs = [ pkgs.kicad ];
      }
      ''
        ${kicadLibTableSetup}
        ${stageBoard board}
        kicad-cli pcb drc \
          --schematic-parity \
          --severity-error \
          --exit-code-violations \
          --format json \
          --output $out \
          "$work/pcb/${board}/${board}.kicad_pcb"
      '';

  # ERC gate. With the stock symbol libraries resolved, ERC checks the
  # actual schematic for power-input, no-connect, and pin conflicts.
  # Same error-only severity policy as the DRC gate above.
  erc =
    board:
    pkgs.runCommand "erc-${board}"
      {
        nativeBuildInputs = [ pkgs.kicad ];
      }
      ''
        ${kicadLibTableSetup}
        ${stageBoard board}
        kicad-cli sch erc \
          --severity-error \
          --exit-code-violations \
          --format json \
          --output $out \
          "$work/pcb/${board}/${board}.kicad_sch"
      '';

  boards = [
    "sensor-board"
    "vetroplach-board"
  ];
in
{
  checks = builtins.listToAttrs (
    builtins.concatMap (board: [
      {
        name = "drc-${board}";
        value = drc board;
      }
      {
        name = "erc-${board}";
        value = erc board;
      }
    ]) boards
  );
}
