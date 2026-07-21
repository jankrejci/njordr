# ESP32-S3 build universe: the pinned esp-rs Xtensa Rust toolchain, the
# crosstool-NG Xtensa GCC it links through, the crane instance built on
# them, and the vendored dependency set for the build-std=core firmware
# build.
{
  pkgs,
  crane,
}:
rec {
  # Xtensa-LX7 Rust toolchain for the ESP32-S3. Upstream rustc does not
  # ship xtensa-esp32s3-none-elf; esp-rs publishes pre-built artifacts at
  # github.com/esp-rs/rust-build. Running espup inside a Nix build is
  # non-deterministic, so the flake fetches the release tarballs directly
  # with pinned hashes. The version matches the espup toolchain the
  # project built with before the flake existed.
  #
  # When bumping espToolchainVersion:
  #   nix-prefetch-url <rust tarball url>
  #   nix-prefetch-url <rust-src tarball url>
  #   nix hash convert --to sri --hash-algo sha256 <each base32>
  # The --unpack flag is intentionally omitted; fetchurl verifies the
  # compressed tarball directly. Retest both the flake checks and the
  # devshell in the same commit.
  espToolchainVersion = "1.88.0.0";

  espToolchain = pkgs.stdenv.mkDerivation {
    pname = "esp-rust-xtensa";
    version = espToolchainVersion;

    srcs = [
      (pkgs.fetchurl {
        url = "https://github.com/esp-rs/rust-build/releases/download/v${espToolchainVersion}/rust-${espToolchainVersion}-x86_64-unknown-linux-gnu.tar.xz";
        hash = "sha256-dFNJFHSl9yiyRIFlHUPLzq+S9438q+fLiCxr8h/uBQU=";
      })
      (pkgs.fetchurl {
        url = "https://github.com/esp-rs/rust-build/releases/download/v${espToolchainVersion}/rust-src-${espToolchainVersion}.tar.xz";
        hash = "sha256-m35u//UHO7uFtQ5mn/mVhNuJ1PCsuljgkD3Rmv3uuaE=";
      })
    ];

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [
      pkgs.stdenv.cc.cc
      pkgs.zlib
    ];

    sourceRoot = ".";
    dontStrip = true;

    # The rust and rust-src tarballs each unpack to their own top-level
    # directory carrying an install.sh; the directory name tracks the
    # upstream nightly, so discover it rather than hard-coding it.
    installPhase = ''
      runHook preInstall
      for dir in */; do
        if [ -x "$dir/install.sh" ]; then
          patchShebangs "$dir/install.sh"
          "$dir/install.sh" --destdir=$out --prefix="" --disable-ldconfig
        fi
      done
      runHook postInstall
    '';
  };

  # Xtensa GCC toolchain. The esp-rs rustc's xtensa-esp32s3-none-elf
  # target spec names `xtensa-esp32s3-elf-gcc` as its linker driver, so
  # every release build needs it on PATH even though the crate has no C
  # dependencies. Nixpkgs doesn't ship it, and the rustup-managed copy
  # from `espup` is invisible inside the flake check sandbox. Hashes
  # paired with the URL; bump both when upgrading to a newer
  # espressif/crosstool-NG release.
  xtensaEspToolchain = pkgs.stdenv.mkDerivation {
    pname = "xtensa-esp-elf";
    version = "15.2.0_20250920";

    src = pkgs.fetchurl {
      url = "https://github.com/espressif/crosstool-NG/releases/download/esp-15.2.0_20250920/xtensa-esp-elf-15.2.0_20250920-x86_64-linux-gnu.tar.xz";
      hash = "sha256-49d60UVEgUUnu+ei0PeexFkqTiM5LFHHOIwOaGtqaXc=";
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [
      pkgs.stdenv.cc.cc
      pkgs.zlib
    ];

    sourceRoot = "xtensa-esp-elf";
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r . "$out"
      runHook postInstall
    '';
  };

  espCraneLib = (crane.mkLib pkgs).overrideToolchain espToolchain;

  # build-std=core pulls sysroot crates like core and compiler_builtins
  # that carry their own Cargo.lock outside our tree. Vendor both our
  # lock and the toolchain's library lock so the sandboxed Xtensa checks
  # resolve every dependency without network access.
  espCargoVendorDir = espCraneLib.vendorMultipleCargoDeps {
    cargoLockList = [
      ../firmware/vetroplach/Cargo.lock
      "${espToolchain}/lib/rustlib/src/rust/library/Cargo.lock"
    ];
  };

  # rust-src for -Z build-std, shared by the crane checks and the esp
  # devshell so cargo and rust-analyzer both resolve the sysroot sources.
  espRustSrcPath = "${espToolchain}/lib/rustlib/src/rust/library";
}
