---
paths:
  - "firmware/vetroplach/**/*"
---

# Firmware Conventions

Implementation conventions for the ESP32-S3 firmware in
`firmware/vetroplach/`. These load only when working under that tree.

## Crate shape

- Binary-only `#![no_std]` / `#![no_main]` crate. There is no `lib.rs`;
  do not add one.
- Built on `esp-hal` (with its `unstable` feature enabled) plus
  `esp-hal-embassy`, `embassy-executor`, and `embassy-time`. Logging is
  `defmt` routed over RTT via `rtt-target`.

## Embedded Rust conventions

- Prefer simple, readable code over clever abstractions. Leverage the
  ownership system for memory safety without runtime cost.
- No dynamic allocation. Use static allocation; when a collection is
  needed, use `heapless`. Keep behavior deterministic.
- Use `defmt` for logging, never `println!`.
- Use `Result`/`Option` for error handling. Avoid panics on any path
  that ships; keep `unwrap`/`expect`/`panic!` out of steady-state code.
  Init-time configuration whose failure is a programming error may
  `expect` with a message prefixed `BUG:`, as `src/main.rs` does, and
  examples may `unwrap` freely.
- No busy-waiting or polling loops. Drive concurrency with Embassy
  async/await and hardware interrupts, and use Embassy `Signal` for
  interrupt-to-task communication. If polling is
  unavoidable, insert an Embassy timer delay so the CPU does not spin.
- Never use `unsafe`. If a solution seems to require it, the approach is
  wrong; there is a safe esp-hal/Embassy pattern.
- Avoid `PhantomData`: if a generic type is only used during
  construction, make it a method-level generic rather than a
  struct-level one.
- Keep interrupt handlers minimal and fast. Group related peripheral
  configuration and use descriptive names for hardware constants.

## Hardware-specific guidelines

- IO MUX vs GPIO Matrix: for high-frequency signals (>1 MHz) prefer
  direct IO MUX routing over the GPIO Matrix to reduce latency.
- Use internal signal routing where possible to eliminate external
  wiring.
- Configure appropriate drive strength for signal integrity, especially
  for PWM and high-speed digital signals.
- Power domains: mind VDD3P3_CPU vs VDD_SPI when using GPIO33-37 and
  GPIO47-48. On this board the bare ESP32-S3 pairs with a quad-SPI
  flash and no octal PSRAM, so GPIO33-37 stay in the VDD3P3_CPU domain
  and are free for the enable pins below.

## GPIO pin assignments

- The MCPWM operator output on GPIO2 generates the 40 kHz carrier in
  `src/main.rs`; this is the only pin the main binary drives.
- The remaining assignments exist only in the examples. In
  `examples/sonic-dual.rs`, RMT TX channels on GPIO4, GPIO5, GPIO6
  generate the ultrasonic burst, one channel per sensor, and each sensor
  has a transmit-enable and receive-enable pin pair: GPIO37/GPIO41,
  GPIO36/GPIO40, GPIO35/GPIO39 for the sensors on GPIO4, GPIO5, GPIO6
  respectively. `examples/sonic-rmt.rs` drives a single RMT TX channel
  on GPIO4. The `sonic` driver itself is pin-generic.

## Running examples on hardware

- `cargo run --release --example <name>` builds, flashes, and runs the
  example via probe-rs, streaming defmt/RTT output directly (for example
  `cargo run --release --example sonic-dual`).
- Examples may run indefinitely; press Ctrl+C to stop once you have
  observed the output.
