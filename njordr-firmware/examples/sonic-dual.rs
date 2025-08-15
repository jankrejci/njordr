#![no_std]
#![no_main]

use defmt::info;
use embassy_executor::Spawner;
use embassy_time::{Duration, Timer};
use esp_hal::{
    self,
    clock::CpuClock,
    rmt::{Rmt, TxChannelConfig, TxChannelCreator},
    time::{self, Rate},
    timer::systimer::SystemTimer,
};
use panic_rtt_target as _;

#[path = "../src/sonic.rs"]
mod sonic;
use sonic::{Sonic, SonicMode};

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

    info!("Initializing dual ultrasonic system: TX sensor + RX sensor");

    let rmt = Rmt::new(peripherals.RMT, Rate::from_mhz(80))
        .unwrap()
        .into_async();

    let mut sensor_a: Sonic<0> = Sonic::new(
        rmt.channel0
            .configure_tx(
                peripherals.GPIO4,
                TxChannelConfig::default().with_clk_divider(1),
            )
            .unwrap(),
        peripherals.GPIO37,
        peripherals.GPIO41,
    );
    let mut sensor_b: Sonic<1> = Sonic::new(
        rmt.channel1
            .configure_tx(
                peripherals.GPIO5,
                TxChannelConfig::default().with_clk_divider(1),
            )
            .unwrap(),
        peripherals.GPIO36,
        peripherals.GPIO40,
    );
    let mut sensor_c: Sonic<2> = Sonic::new(
        rmt.channel2
            .configure_tx(
                peripherals.GPIO6,
                TxChannelConfig::default().with_clk_divider(1),
            )
            .unwrap(),
        peripherals.GPIO35,
        peripherals.GPIO39,
    );

    sensor_a.set_mode(SonicMode::Receive);
    sensor_b.set_mode(SonicMode::Disabled);
    sensor_c.set_mode(SonicMode::Transmit);
    const FREQUENCY: f32 = 39000.0;
    loop {
        info!(
            "=== TX sensor: Triggering {} kHz burst ===",
            FREQUENCY / 1000.0
        );
        sensor_c.set_frequency(FREQUENCY, 0.5);
        sensor_c.transmit_burst().await.unwrap();
        Timer::after(Duration::from_millis(1000)).await;
    }
}
