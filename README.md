# njordr-firmware

Firmware for an ultrasonic anemometer.

## Prerequisites

This project uses a `nix develop` environment, so you should have [Nix](https://nixos.org/download/#download-nix) installed on your computer.
Additionally, `probe-rs` is used for flashing and debugging.
Please ensure you have completed the [probe setup](https://probe.rs/docs/getting-started/probe-setup/#linux-udev-rules),
especially the udev rules if you're on Linux.

## Building

Enable the development environment:
```bash
nix develop
```

Build and run the project:
```bash
cargo run --release  
```

Or build and run an example:
```bash
cargo run --release --example pwm-source
```
