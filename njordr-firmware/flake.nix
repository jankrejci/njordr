{
  description = "ESP32-S3 Rust development environment - complete setup";

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

        # Use stable Rust toolchain for IDE support
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
        };

        # Script to patch ESP binaries on NixOS
        patchEspBinaries = pkgs.writeShellScriptBin "patch-esp-binaries" ''
          # Check if we're on NixOS by looking for /etc/NIXOS or if standard linker is missing
          if [ -f /etc/NIXOS ] || [ ! -f /lib64/ld-linux-x86-64.so.2 ]; then
            echo "🔧 Patching ESP toolchain binaries for NixOS..."
            
            # Find and patch ALL ELF binaries (not just executable ones)
            find "$RUSTUP_HOME/toolchains/esp" -type f | while read -r file; do
              if file "$file" 2>/dev/null | grep -q 'ELF'; then
                echo "Patching $(basename "$file")..."
                ${pkgs.patchelf}/bin/patchelf \
                  --set-interpreter "$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)" \
                  "$file" 2>/dev/null || true
                  
                ${pkgs.patchelf}/bin/patchelf \
                  --set-rpath "${pkgs.lib.makeLibraryPath [
                    pkgs.stdenv.cc.cc.lib
                    pkgs.glibc
                    pkgs.zlib
                    pkgs.libxml2
                    pkgs.openssl
                    pkgs.libffi
                  ]}:$RUSTUP_HOME/toolchains/esp/lib:$(dirname "$file")" \
                  "$file" 2>/dev/null || true
              fi
            done
            echo "✅ Patching complete!"
          else
            echo "📦 Running on non-NixOS system - no patching needed"
          fi
        '';

      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Rust toolchain and tools
            rustToolchain

            # ESP32 development tools (all from nixpkgs)
            espup
            espflash
            cargo-espflash
            probe-rs-tools

            # Patching tool for NixOS
            patchelf
            patchEspBinaries

            # System dependencies
            pkg-config
            libudev-zero
            perl # Needed for espup

            # Libraries needed for ESP toolchain compatibility
            stdenv.cc.cc.lib
            glibc
            zlib
            libxml2
            openssl
            libffi

            # Development tools
            minicom
            picocom
            usbutils
          ];

          # NixOS dynamic linking support
          NIX_LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
            pkgs.stdenv.cc.cc.lib
            pkgs.glibc
            pkgs.zlib
            pkgs.libxml2
            pkgs.openssl
            pkgs.libffi
          ];
          NIX_LD = "${pkgs.glibc}/lib/ld-linux-x86-64.so.2";

          # Rust analyzer configuration
          RUST_ANALYZER_SERVER_PATH = "${rustToolchain}/bin/rust-analyzer";

          # libclang path for bindgen
          LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";

          shellHook = ''
            echo "🦀 ESP32-S3 Rust Development Environment"
            echo "========================================"
            
            # Set up local toolchain directories
            export RUSTUP_HOME="$PWD/.rustup"
            export CARGO_HOME="$PWD/.cargo"
            mkdir -p "$RUSTUP_HOME" "$CARGO_HOME"
            
            # Toolchain paths
            XTENSA_GCC_PATH="$RUSTUP_HOME/toolchains/esp/xtensa-esp-elf/esp-14.2.0_20240906/xtensa-esp-elf/bin"
            LIBCLANG_TOOLCHAIN_PATH="$RUSTUP_HOME/toolchains/esp/xtensa-esp32-elf-clang/esp-19.1.2_20250225/esp-clang/lib"
            
            # Install ESP toolchain if not present
            if [ ! -d "$XTENSA_GCC_PATH" ] || [ ! -d "$LIBCLANG_TOOLCHAIN_PATH" ]; then
              echo "📦 Installing ESP32-S3 Xtensa toolchain..."
              # This needs to be compatible with rust_ci.yml
              espup install --targets esp32s3 --toolchain-version 1.88.0 || true
              echo "✅ ESP toolchain installation complete"
              
              # Patch binaries on NixOS only
              patch-esp-binaries
            fi
            
            # Configure environment for ESP development
            export PATH="$XTENSA_GCC_PATH:$PATH"
            export PATH="$RUSTUP_HOME/toolchains/esp/bin:$PATH"
            export PATH="$CARGO_HOME/bin:$PATH"
            
            # Override libclang to use ESP version when available
            if [ -d "$LIBCLANG_TOOLCHAIN_PATH" ]; then
              export LIBCLANG_PATH="$LIBCLANG_TOOLCHAIN_PATH"
            fi
           
            echo ""
            echo "🚀 Ready for ESP32-S3 development!"
            echo ""
            echo "💡 Usage:"
            echo "   • cargo build --release              # Build project"
            echo "   • cargo run --release                # Build and flash"
            echo "   • espflash monitor                   # Monitor serial output"
            echo "   • probe-rs run --chip esp32s3        # Debug with probe-rs"
            echo ""
            echo "🔧 Development setup:"
            echo "   • ESP toolchain: $RUSTUP_HOME/toolchains/esp/"
            echo "   • Xtensa GCC: $XTENSA_GCC_PATH"
            echo "   • libclang: $LIBCLANG_TOOLCHAIN_PATH"
            echo ""
            echo "📋 Next steps:"
            echo "   1. Ensure your Cargo.toml has ESP32-S3 dependencies"
            echo "   2. Use 'cargo run --release' for build and flash workflow"
            echo "   3. Check that rust-toolchain.toml specifies 'esp' channel"
            echo ""
          '';
        };
      });
}
