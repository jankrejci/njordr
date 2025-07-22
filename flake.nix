{
  description = "ESP32-S3 Rust development environment for ultrasonic anemometer";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        # Use stable Rust toolchain (ESP toolchain will be managed by espup)
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
        };

      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Rust toolchain
            rustToolchain
            cargo-generate

            # ESP tools
            espup
            espflash

            # Build tools (minimal set)
            gcc
            pkg-config
            openssl
            libudev-zero

            # Debugging and flashing tools
            probe-rs-tools

            # Development tools
            minicom
            picocom

            # For USB device access
            usbutils
          ];

          shellHook = ''
            echo "🦀 ESP32-S3 Rust Development Environment (no_std)"
            echo "=============================================="

            # Create local .rustup directory for toolchains
            export RUSTUP_HOME="$PWD/.rustup"
            export CARGO_HOME="$PWD/.cargo"
            mkdir -p "$RUSTUP_HOME" "$CARGO_HOME"

            # Set up Xtensa toolchain paths
            XTENSA_GCC_PATH="$RUSTUP_HOME/toolchains/esp/xtensa-esp-elf/esp-14.2.0_20240906/xtensa-esp-elf/bin"
            LIBCLANG_TOOLCHAIN_PATH="$RUSTUP_HOME/toolchains/esp/xtensa-esp32-elf-clang/esp-19.1.2_20250225/esp-clang/lib"

            # Check if toolchains exist, if not install them
            if [ ! -d "$XTENSA_GCC_PATH" ] || [ ! -d "$LIBCLANG_TOOLCHAIN_PATH" ]; then
              echo "📦 Installing Xtensa toolchains locally..."
              espup install --targets esp32s3
            fi

            # Export toolchain paths
            export PATH="$XTENSA_GCC_PATH:$PATH"
            export LIBCLANG_PATH="$LIBCLANG_TOOLCHAIN_PATH"

            # Set up ESP Rust toolchain
            export PATH="$RUSTUP_HOME/toolchains/esp/bin:$PATH"
            
            # Add cargo to PATH
            export PATH="$CARGO_HOME/bin:$PATH"

            echo ""
            echo "🚀 Ready for ESP32-S3 no_std development!"
            echo "   • Use 'cargo run --release' to build and flash"
            echo "   • Use 'espflash monitor' to view serial output"
            echo "   • Use 'probe-rs run' for debugging with probe-rs"
            echo ""
            echo "🔧 Toolchain paths:"
            echo "   • Xtensa GCC: $XTENSA_GCC_PATH"
            echo "   • libclang: $LIBCLANG_TOOLCHAIN_PATH"
            echo "   • ESP Rust: $RUSTUP_HOME/toolchains/esp/bin"
            echo ""
          '';

          # Environment variables

          # Fix for libclang (fallback to system)
          LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";

          # Rust configuration
          RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";

          # Rust-analyzer configuration
          RUST_ANALYZER_SERVER_PATH = "${rustToolchain}/bin/rust-analyzer";
          RUSTUP_TOOLCHAIN = "stable";
        };
      });
}
