use defmt::debug;
use esp_hal::{
    gpio::{Level, Output, OutputConfig, OutputPin},
    rmt::{Channel, ConstChannelAccess, Error as RmtError, PulseCode, Tx, TxChannelAsync},
    Async,
};

const NUM_PULSES: usize = 3;

pub struct Sonic<const CHANNEL: u8> {
    tx_channel: Channel<Async, ConstChannelAccess<Tx, CHANNEL>>,
    tx_en_pin: Output<'static>,
    rx_en_pin: Output<'static>,
    burst_data: [u32; NUM_PULSES + 1],
}

impl<const CHANNEL: u8> Sonic<CHANNEL> {
    pub fn new<TxEn: OutputPin + 'static, RxEn: OutputPin + 'static>(
        tx_channel: Channel<Async, ConstChannelAccess<Tx, CHANNEL>>,
        tx_en_pin: TxEn,
        rx_en_pin: RxEn,
    ) -> Self {
        let tx_en_pin = Output::new(tx_en_pin, Level::Low, OutputConfig::default());
        let rx_en_pin = Output::new(rx_en_pin, Level::Low, OutputConfig::default());

        let pulse = PulseCode::new(Level::High, 1000, Level::Low, 1000);
        debug!("Pulse: {:08X}", pulse);
        let mut burst_data = [pulse; NUM_PULSES + 1];
        burst_data[NUM_PULSES] = PulseCode::empty();

        Self {
            tx_channel,
            tx_en_pin,
            rx_en_pin,
            burst_data,
        }
    }

    pub fn set_frequency(&mut self, frequency: f32, duty: f32) {
        // Base clock ticks at 40 MHz, e.g. 25 ns per tick. It takes 1000 ticks
        // to generate 25 us pulse needed for 40 kHz signal
        const FREQUENCY_PULSE_RATIO: f32 = 20.0;
        let num_pulses = frequency / FREQUENCY_PULSE_RATIO;
        let num_high_pulses = (num_pulses * duty) as u16;
        let num_low_pulses = num_pulses as u16 - num_high_pulses;
        let pulse = PulseCode::new(Level::High, num_high_pulses, Level::Low, num_low_pulses);
        debug!("Pulse: {:08X}", pulse);

        self.burst_data = [pulse; NUM_PULSES + 1];
        // End marker
        self.burst_data[NUM_PULSES] = PulseCode::empty();
    }

    pub fn set_mode(&mut self, mode: SonicMode) {
        match mode {
            SonicMode::Transmit => {
                self.tx_en_pin.set_high();
                self.rx_en_pin.set_low();
            }
            SonicMode::Receive => {
                self.tx_en_pin.set_low();
                self.rx_en_pin.set_high();
            }
            SonicMode::Disabled => {
                self.tx_en_pin.set_low();
                self.rx_en_pin.set_low();
            }
        }
    }

    pub async fn transmit_burst(&mut self) -> Result<(), RmtError> {
        self.tx_channel.transmit(&self.burst_data).await
    }
}

#[derive(Clone, Copy)]
pub enum SonicMode {
    Transmit,
    Receive,
    Disabled,
}
