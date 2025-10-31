# Piezo Driver

The Njordr driver uses a half-bridge configuration with LC resonance to boost 20V up to ~100Vpp at the transducer. Same transducer works for both transmit and receive.

## Circuit Design

### Half-Bridge with Resonant Tank

Two N-channel MOSFETs switch a node between +20V and ground. The switching drives an inductor that forms a resonant tank with the transducer's capacitance. At resonance (40kHz), the LC circuit naturally amplifies voltage - no transformer or high-voltage supply needed.

Bootstrap capacitor lets the high-side MOSFET work with a single supply. It charges when the low-side switch is on, then provides gate drive voltage when needed.

## Signal Path

**Transmit**: Gate driver alternates the MOSFETs at 40kHz. First few cycles ramp up amplitude, then full power transmission. Current sense resistor in the return path monitors what's happening.

**Receive**: After transmit burst stops, same transducer picks up echoes. AC coupling cap blocks DC and passes the signal to external processing. The coupling cap needs to handle the full drive voltage swing.

## Why This Design

**Compared to single transistor**: Would need >100V supply and still wouldn't drive efficiently. Not practical.

**Compared to MAX232**: [QingStation](https://github.com/majianjia/QingStation/blob/main/doc/anemometer.md#driver-design) tried this clever hack using RS-232 chips to get ±10V from 3V. Problem is the charge pump creates noise that messes with the sensitive receive circuit. Works but not ideal for precision timing.

**Compared to transformer**: [DL1GLH design](https://www.dl1glh.de/ultrasonic-anemometer.html) uses transformers for voltage boost and impedance matching. Works great but transformers are bulky and expensive. The resonant inductor does similar voltage boost without the hassle.

## Notes

The 40kHz frequency is a sweet spot - transducers are cheap and common, air attenuation isn't too bad, wavelength gives decent resolution, and microcontrollers can handle the timing easily.

Resonant Q factor matters: higher Q means more voltage gain but longer ring-down. The inductor value balances fast response with good amplitude.
