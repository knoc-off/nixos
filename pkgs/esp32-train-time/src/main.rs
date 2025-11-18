#![no_std]
#![no_main]

use embassy_executor::Spawner;
use embassy_net::{Config, Runner, Stack, StackResources};
use embassy_time::{Duration, Timer};
use esp_backtrace as _;
use esp_hal::gpio::{Level, Output, OutputConfig};
use esp_radio::wifi::{
    self, AuthMethod, ClientConfig, ModeConfig, WifiController, WifiDevice, WifiEvent,
};
use static_cell::StaticCell;

// WiFi credentials - change these!
const SSID: &str = "YOUR_WIFI_SSID";
const PASSWORD: &str = "YOUR_WIFI_PASSWORD";

// MQTT broker - change to your Home Assistant IP
const MQTT_HOST: &str = "192.168.1.100";
const MQTT_PORT: u16 = 1883;
const MQTT_TOPIC: &str = "esp32/display";

macro_rules! mk_static {
    ($t:ty,$val:expr) => {{
        static STATIC_CELL: StaticCell<$t> = StaticCell::new();
        STATIC_CELL.uninit().write($val)
    }};
}

#[esp_rtos::main]
async fn main(spawner: Spawner) {
    esp_println::println!("ESP32-C3 Train Time Display starting!");

    let config = esp_hal::Config::default();
    let peripherals = esp_hal::init(config);

    // Status LED on GPIO8
    let mut led = Output::new(peripherals.GPIO8, Level::Low, OutputConfig::default());

    // Initialize radio
    let controller = mk_static!(esp_radio::Controller<'_>, esp_radio::init().unwrap());

    // Create WiFi interface
    let wifi_config = wifi::Config::default();
    let (wifi_controller, interfaces) =
        wifi::new(controller, peripherals.WIFI, wifi_config).unwrap();

    let wifi_interface = interfaces.sta;

    // Network stack configuration
    let net_config = Config::dhcpv4(Default::default());

    let seed = 1234u64; // TODO: use RNG for proper seed

    let (stack, runner) = embassy_net::new(
        wifi_interface,
        net_config,
        mk_static!(StackResources<3>, StackResources::<3>::new()),
        seed,
    );

    let stack = mk_static!(Stack<'_>, stack);

    spawner.spawn(connection(wifi_controller)).ok();
    spawner.spawn(net_task(runner)).ok();

    // Wait for WiFi connection
    esp_println::println!("Waiting for WiFi...");
    loop {
        if stack.is_link_up() {
            break;
        }
        led.toggle();
        Timer::after(Duration::from_millis(500)).await;
    }

    // Wait for IP address
    esp_println::println!("Waiting for IP address...");
    loop {
        if let Some(config) = stack.config_v4() {
            esp_println::println!("Got IP: {}", config.address);
            break;
        }
        Timer::after(Duration::from_millis(500)).await;
    }

    led.set_high();
    esp_println::println!("WiFi connected!");

    // Main display loop
    // TODO: Add MQTT client and LCD driver here
    loop {
        esp_println::println!("Display ready - waiting for MQTT messages on topic: {}", MQTT_TOPIC);
        led.toggle();
        Timer::after(Duration::from_secs(2)).await;
    }
}

#[embassy_executor::task]
async fn connection(mut controller: WifiController<'static>) {
    esp_println::println!("Connecting to WiFi: {}", SSID);

    loop {
        if controller.is_connected().unwrap_or(false) {
            controller.wait_for_event(WifiEvent::StaDisconnected).await;
            esp_println::println!("WiFi disconnected!");
            Timer::after(Duration::from_millis(5000)).await;
        }

        if !matches!(controller.is_started(), Ok(true)) {
            let client_config = ClientConfig::default()
                .with_ssid(SSID.try_into().unwrap())
                .with_password(PASSWORD.try_into().unwrap())
                .with_auth_method(AuthMethod::Wpa2Personal);

            controller.set_config(&ModeConfig::Client(client_config)).unwrap();
            esp_println::println!("Starting WiFi...");
            controller.start_async().await.unwrap();
            esp_println::println!("WiFi started!");
        }

        esp_println::println!("Attempting to connect...");
        match controller.connect_async().await {
            Ok(_) => esp_println::println!("WiFi connected!"),
            Err(e) => {
                esp_println::println!("Failed to connect: {:?}", e);
                Timer::after(Duration::from_millis(5000)).await;
            }
        }
    }
}

#[embassy_executor::task]
async fn net_task(mut runner: Runner<'static, WifiDevice<'static>>) {
    runner.run().await
}
