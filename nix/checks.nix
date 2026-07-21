# Per-crate firmware gates plus the repo-wide formatting checks. The
# firmware is a single #![no_main] esp32s3 binary, so — as in any
# build-std=core esp tree — crane's buildDepsOnly cannot pre-build a
# linkable dependency bag: it stubs a dummy main the esp crt0 cannot
# link against. Clippy therefore reuses a check-only dependency bag and
# the release build rebuilds its dependency closure. The KiCad DRC/ERC
# gates are merged in from nix/kicad.nix.
{
  pkgs,
  espCraneLib,
  firmwareSrc,
  espCargoVendorDir,
  espRustSrcPath,
  xtensaEspToolchain,
  kicadChecks,
}:
let
  # Restrict the nixfmt input to the .nix files themselves so the
  # check's hash does not churn on unrelated trees such as .git or
  # local build outputs.
  root = pkgs.lib.fileset.toSource {
    root = ../.;
    fileset = pkgs.lib.fileset.fileFilter (file: file.hasExt "nix") ../.;
  };
  target = "xtensa-esp32s3-none-elf";

  # Attrs common to every Xtensa crane invocation: the firmware source,
  # the vendored build-std deps, the target and build-std flags, the
  # sysroot sources for -Z build-std, and the Xtensa GCC the target
  # spec names as its linker driver.
  espCommon = {
    src = firmwareSrc;
    cargoVendorDir = espCargoVendorDir;
    cargoExtraArgs = "--target ${target} -Z build-std=core";
    doInstallCargoArtifacts = false;
    RUST_SRC_PATH = espRustSrcPath;
    nativeBuildInputs = [ xtensaEspToolchain ];
  };

  # Check-only dependency bag: dependencies are `cargo check`ed, never
  # linked, so the no_main firmware bin does not fail the crt0 link.
  espArtifacts = espCraneLib.buildDepsOnly (
    espCommon
    // {
      doCheck = false;
      cargoBuildCommand = "true";
      cargoCheckCommand = "cargo check";
    }
  );
in
kicadChecks
// {
  # Formatting gate over the firmware crate.
  fmt = espCraneLib.cargoFmt {
    src = firmwareSrc;
    doInstallCargoArtifacts = false;
  };

  # Clippy over the firmware and its examples, warnings-as-errors.
  # `--all-targets` would include the test harness, which cannot build
  # on a no_std build-std=core target that lacks the `test` crate, so
  # the bin and example targets are named explicitly.
  clippy-firmware = espCraneLib.cargoClippy (
    espCommon
    // {
      cargoArtifacts = espArtifacts;
      cargoClippyExtraArgs = "--bins --examples -- -D warnings";
    }
  );

  # Release build of the firmware. There is no dependency bag to reuse,
  # as the module header explains; rebuilds the closure each time.
  build-firmware = espCraneLib.cargoBuild (
    espCommon
    // {
      cargoArtifacts = null;
      cargoBuildCommand = "cargo build --release";
    }
  );

  # nixfmt over every .nix file, matching `nix fmt`.
  nixfmt =
    pkgs.runCommand "nixfmt-check"
      {
        nativeBuildInputs = [ pkgs.nixfmt ];
      }
      ''
        find ${root} -name '*.nix' -print0 | xargs -0 nixfmt --check
        touch $out
      '';
}
