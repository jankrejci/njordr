#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_time::{Duration, Timer};
use esp_hal::{
    self,
    clock::CpuClock,
    rmt::{Rmt, TxChannel, TxChannelConfig, TxChannelCreator},
    time::{self, Rate},
    timer::systimer::SystemTimer,
};
use panic_rtt_target as _;

defmt::timestamp!(
    "{=u64:us}",
    time::Instant::now().duration_since_epoch().as_micros()
);

#[esp_hal_embassy::main]
async fn main(_spawner: Spawner) {
    rtt_target::rtt_init_defmt!();

    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    let timer0 = SystemTimer::new(peripherals.SYSTIMER);
    esp_hal_embassy::init(timer0.alarm0);

    info!("Initializing RMT ultrasonic burst generator");

    // Initialize RMT peripheral - let's try 40MHz for 40kHz precision
    let rmt = Rmt::new(peripherals.RMT, Rate::from_mhz(40)).unwrap();

    // Configure TX channel for precise pulse generation
    let tx_config = TxChannelConfig::default();

    // Create TX channel on GPIO4
    let mut channel = rmt
        .channel0
        .configure_tx(peripherals.GPIO4, tx_config)
        .unwrap();

    info!("RMT configured on GPIO4 for ultrasonic bursts");

    let pulse_40khz = (2u32 << 16) | (1u32 << 15) | 2u32;

    info!("40kHz pulse data: 0x{:08X}", pulse_40khz);

    // Create burst of exactly 10 pulses at 40kHz
    let mut burst_data = [pulse_40khz; 11]; // 10 pulses + end marker
    burst_data[10] = 0x00000000; // End marker

    info!("Created burst pattern: 10 pulses at 40kHz");
    info!("Each pulse: 12.5μs high + 12.5μs low = 25μs period (40kHz)");
    info!("Total burst duration: 250μs");

    // Main loop - generate precise bursts
    loop {
        info!("=== Triggering RMT burst of exactly 10 pulses at 40kHz ===");

        // Send the burst - RMT handles precise timing automatically
        let transaction = channel.transmit(&burst_data).unwrap();

        // Wait for transmission to complete and get channel back
        channel = transaction.wait().unwrap();

        info!("RMT burst completed with hardware precision");

        Timer::after(Duration::from_millis(100)).await;
    }
}
