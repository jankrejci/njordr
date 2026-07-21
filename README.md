# vetroplach

An ultrasonic anemometer: KiCad PCB designs and ESP32-S3 firmware.

## Layout

- `firmware/vetroplach/` — ESP32-S3 firmware (Rust, esp-hal + Embassy)
- `pcb/vetroplach-board/` — main controller board
- `pcb/sensor-board/` — environmental sensor board
- `pcb/components/` — shared KiCad symbol and footprint library
- `nix/` — flake modules: toolchain, checks, dev shells
- `docs/` — design notes and simulations

## Prerequisites

Everything builds through [Nix](https://nixos.org/download/) flakes; no
manual rustup, espup, or KiCad setup is needed. Flashing uses
`probe-rs`; complete the
[probe setup](https://probe.rs/docs/getting-started/probe-setup/#linux-udev-rules),
especially the udev rules on Linux.

## Firmware

Enter the dev shell (pins the Xtensa toolchain, probe-rs, espflash) and
build from the crate directory:

```bash
nix develop
cd firmware/vetroplach
cargo build --release
```

Build and flash:

```bash
cargo run --release
```

Or run an example:

```bash
cargo run --release --example sonic-dual
```

## PCB

DRC/ERC gates and fabrication outputs run through the flake:

```bash
nix develop .#pcb    # KiCad + kibot shell
nix run .#kibot -- -c jlcpcb.kibot.yaml \
  -b pcb/vetroplach-board/vetroplach-board.kicad_pcb \
  -e pcb/vetroplach-board/vetroplach-board.kicad_sch \
  -d fab/vetroplach-board/
```

## Checks

CI runs the flake checks; the same commands work locally:

```bash
nix build .#ci-format    # cargo fmt + nixfmt
nix build .#ci-clippy    # firmware clippy
nix build .#ci-check     # firmware release build, PCB DRC/ERC
nix flake check          # everything
```
