# The vetroplach firmware + PCB workspace flake.
#
# Why: the ESP32-S3 firmware needs an Xtensa Rust toolchain that is not
# in nixpkgs, and the boards need headless KiCad DRC/ERC gates. This
# flake pins both so a clean checkout builds and gates without manual
# rustup, espup, or KiCad setup.
#
# What: the outputs wire the pinned esp toolchain, the firmware and PCB
# checks, the CI stage groups, and the interactive dev shells together.
# Each block imports a nix/ module; see nix/esp.nix for the
# toolchain, nix/checks.nix for the gates, and nix/shells.nix for the
# `nix develop` / `nix develop .#pcb` entry points.
{
  description = "vetroplach ESP32-S3 firmware and PCB workspace";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      crane,
    }:
    # x86_64-linux only: the esp-rs Xtensa toolchain is a prebuilt
    # x86_64 tarball, so the per-system checks and shells cannot work
    # elsewhere.
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        # ESP32-S3 build universe: the pinned Xtensa Rust toolchain, its
        # crane instance, and the vendored build-std deps. See nix/esp.nix.
        esp = import ./nix/esp.nix {
          inherit pkgs crane;
        };

        # Cleaned firmware source. Crane's default filter keeps
        # Cargo.toml/lock and .rs files; the firmware also needs
        # .cargo/config.toml, which holds the target, build-std, and
        # linker rustflags.
        firmwareSrc = pkgs.lib.cleanSourceWith {
          src = ./firmware/vetroplach;
          filter =
            path: type:
            (builtins.match ".*/\\.cargo/config\\.toml$" path != null)
            || (esp.espCraneLib.filterCargoSources path type);
          name = "vetroplach-source";
        };

        # Headless KiCad DRC/ERC gates for both boards. See nix/kicad.nix.
        kicad = import ./nix/kicad.nix { inherit pkgs; };

        # KiCad automation for the PCB fabrication outputs, `nix run
        # .#kibot`. DRC and ERC are gated separately by the kicad-cli
        # checks; kibot only generates fab artifacts.
        kiauto = pkgs.callPackage ./kiauto.nix { };
        kibot = pkgs.callPackage ./kibot.nix { inherit kiauto; };
      in
      {
        # Per-crate firmware gates, formatting, and the PCB DRC/ERC gates.
        # See nix/checks.nix.
        checks = import ./nix/checks.nix {
          inherit (esp)
            espCraneLib
            espCargoVendorDir
            espRustSrcPath
            xtensaEspToolchain
            ;
          inherit pkgs firmwareSrc;
          kicadChecks = kicad.checks;
        };

        # Interactive development shells; see nix/shells.nix.
        devShells = import ./nix/shells.nix {
          inherit
            pkgs
            esp
            kibot
            kiauto
            ;
        };

        packages = {
          inherit kibot kiauto;
        }
        # CI stage groups partitioning `checks`; see nix/ci.nix.
        // (import ./nix/ci.nix {
          inherit pkgs;
          checks = self.checks.${system};
        });

        # `nix fmt` entry point, matching the nixfmt check.
        formatter = pkgs.nixfmt-tree;
      }
    );
}
