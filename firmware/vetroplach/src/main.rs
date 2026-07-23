#![no_std]
#![no_main]

pub mod sonic;

use defmt::debug;
use embassy_executor::Spawner;
use embassy_time::{Duration, Timer};
use esp_hal::timer::systimer::SystemTimer;
use esp_hal::{
    self,
    clock::CpuClock,
    mcpwm::{operator::PwmPinConfig, timer::PwmWorkingMode, McPwm, PeripheralClockConfig},
    time::Rate,
};
use panic_rtt_target as _;

#[esp_hal_embassy::main]
async fn main(_spawner: Spawner) {
    rtt_target::rtt_init_defmt!();

    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    let timer0 = SystemTimer::new(peripherals.SYSTIMER);
    esp_hal_embassy::init(timer0.alarm0);

    debug!("Embassy initialized!");

    let pin = peripherals.GPIO2;

    let clock_cfg = PeripheralClockConfig::with_frequency(Rate::from_mhz(40))
        .expect("BUG: Failed to configure clock");

    let mut mcpwm = McPwm::new(peripherals.MCPWM0, clock_cfg);

    // connect operator0 to timer0
    mcpwm.operator0.set_timer(&mcpwm.timer0);
    // connect operator0 to pin
    let mut pwm_pin = mcpwm
        .operator0
        .with_pin_a(pin, PwmPinConfig::UP_ACTIVE_HIGH);

    // start timer with timestamp values in the range of 0..=99 and a frequency
    // of 40 kHz
    let timer_clock_cfg = clock_cfg
        .timer_clock_with_frequency(99, PwmWorkingMode::Increase, Rate::from_khz(40))
        .expect("BUG: Failed to configure timer");

    mcpwm.timer0.start(timer_clock_cfg);

    const PWM_BURST_DURATION: Duration = Duration::from_millis(1);
    const PWM_BURST_PERIOD: Duration = Duration::from_millis(100);

    loop {
        // pin will be high 50% of the time
        pwm_pin.set_timestamp(50);
        Timer::after(PWM_BURST_DURATION).await;
        pwm_pin.set_timestamp(0);
        Timer::after(PWM_BURST_PERIOD).await;
    }
}
