# Interactive development shells.
#
# `default` is the ESP32-S3 firmware shell: the pinned pure Xtensa
# toolchain on PATH, plus probe-rs and espflash for local flashing.
# There is no espup and no runtime binary patching; the toolchain is
# already patchelf'd into the Nix store by nix/esp.nix. `pcb` is the
# KiCad shell for board work and running kibot by hand.
{
  pkgs,
  esp,
  kibot,
  kiauto,
}:
{
  default = pkgs.mkShell {
    buildInputs = [
      esp.espToolchain
      # Linker driver named by the rustc xtensa target spec.
      esp.xtensaEspToolchain
    ]
    ++ (with pkgs; [
      probe-rs-tools
      espflash
      cargo-binutils
      cargo-bloat
      cargo-machete
      # Automatic fixup commits for the documented fixup workflow.
      git-absorb
      gitlint
      # Serial monitors.
      minicom
      picocom
      usbutils
      pkg-config
      libudev-zero
    ]);

    # rust-src for -Z build-std and rust-analyzer; the toolchain ships a
    # matching rust-analyzer so no separate host toolchain is needed.
    RUST_SRC_PATH = esp.espRustSrcPath;

    shellHook = ''
      echo "vetroplach ESP32-S3 firmware shell"
      echo "  cargo build --release          # from firmware/vetroplach/"
      echo "  cargo run --release            # build and flash via probe-rs"
      echo "  cargo run --release --example sonic-dual"
    '';
  };

  pcb = pkgs.mkShell {
    buildInputs = [
      pkgs.kicad
      kibot
      kiauto
    ];
    shellHook = ''
      echo "vetroplach PCB shell (KiCad + kibot)"
      echo "  nix run .#kibot -- -c jlcpcb.kibot.yaml -b pcb/<board>/<board>.kicad_pcb -e pcb/<board>/<board>.kicad_sch -d fab/<board>/"
    '';
  };
}
