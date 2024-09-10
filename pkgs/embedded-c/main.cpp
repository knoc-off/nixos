#include <Arduino.h>
#include "driver_max7219.h"

#define MAX7219_CLK_PIN  13  // SCK
#define MAX7219_MOSI_PIN 11  // MOSI
#define MAX7219_CS_PIN   10  // SS

max7219_handle_t max7219;

// Implementation of interface functions
uint8_t max7219_interface_spi_init(void) {
  pinMode(MAX7219_CLK_PIN, OUTPUT);
  pinMode(MAX7219_MOSI_PIN, OUTPUT);
  pinMode(MAX7219_CS_PIN, OUTPUT);
  digitalWrite(MAX7219_CS_PIN, HIGH);
  return 0;
}

uint8_t max7219_interface_spi_deinit(void) {
  return 0;
}

uint8_t max7219_interface_spi_write_cmd(uint8_t *buf, uint16_t len) {
  digitalWrite(MAX7219_CS_PIN, LOW);
  for (uint16_t i = 0; i < len; i++) {
    shiftOut(MAX7219_MOSI_PIN, MAX7219_CLK_PIN, MSBFIRST, buf[i]);
  }
  digitalWrite(MAX7219_CS_PIN, HIGH);
  return 0;
}

uint8_t max7219_interface_spi_write(uint8_t reg, uint8_t *buf, uint16_t len) {
  digitalWrite(MAX7219_CS_PIN, LOW);
  shiftOut(MAX7219_MOSI_PIN, MAX7219_CLK_PIN, MSBFIRST, reg);
  for (uint16_t i = 0; i < len; i++) {
    shiftOut(MAX7219_MOSI_PIN, MAX7219_CLK_PIN, MSBFIRST, buf[i]);
  }
  digitalWrite(MAX7219_CS_PIN, HIGH);
  return 0;
}

void max7219_interface_delay_ms(uint32_t ms) {
  delay(ms);
}

void max7219_interface_debug_print(const char *const fmt, ...) {
  char buf[256];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buf, sizeof(buf), fmt, args);
  va_end(args);
  Serial.print(buf);
}

// Rest of your code (setup, loop, etc.) remains the same


// Function prototypes (implementation remains the same)
uint8_t max7219_interface_spi_init(void);
uint8_t max7219_interface_spi_deinit(void);
uint8_t max7219_interface_spi_write_cmd(uint8_t *buf, uint16_t len);
uint8_t max7219_interface_spi_write(uint8_t reg, uint8_t *buf, uint16_t len);
void max7219_interface_delay_ms(uint32_t ms);
void max7219_interface_debug_print(const char *const fmt, ...);

void setup() {
  Serial.begin(115200);
  while (!Serial) {
    ; // wait for serial port to connect. Needed for native USB port only
  }
  Serial.println("Starting MAX7219 test...");

  // Initialize the MAX7219 handle
  DRIVER_MAX7219_LINK_INIT(&max7219, max7219_handle_t);
  DRIVER_MAX7219_LINK_SPI_INIT(&max7219, max7219_interface_spi_init);
  DRIVER_MAX7219_LINK_SPI_DEINIT(&max7219, max7219_interface_spi_deinit);
  DRIVER_MAX7219_LINK_SPI_WRITE(&max7219, max7219_interface_spi_write);
  DRIVER_MAX7219_LINK_SPI_WRITE_COMMAND(&max7219, max7219_interface_spi_write_cmd);
  DRIVER_MAX7219_LINK_DELAY_MS(&max7219, max7219_interface_delay_ms);
  DRIVER_MAX7219_LINK_DEBUG_PRINT(&max7219, max7219_interface_debug_print);

  // Initialize MAX7219
  if (max7219_init(&max7219) != 0) {
    Serial.println("MAX7219 init failed");
    while(1);
  }

  Serial.println("MAX7219 initialized.");

  // Configure MAX7219
  max7219_set_decode(&max7219, MAX7219_DECODE_CODEB_DIGITS_NONE);
  max7219_set_intensity(&max7219, MAX7219_INTENSITY_15_32);
  max7219_set_scan_limit(&max7219, MAX7219_SCAN_LIMIT_DIGIT_0_7);
  max7219_set_mode(&max7219, MAX7219_MODE_NORMAL);

  // Clear display
  for (int i = 1; i <= 8; i++) {
    max7219_set_display(&max7219, (max7219_digital_t)i, 0x00);
  }

  Serial.println("MAX7219 configuration complete.");
}

void setAllPixels(bool on) {
  uint8_t value = on ? 0xFF : 0x00;
  for (int i = 1; i <= 8; i++) {
    max7219_set_display(&max7219, (max7219_digital_t)i, value);
  }
  Serial.println(on ? "All pixels set ON" : "All pixels set OFF");
}

void loop() {
  setAllPixels(true);
  delay(1000);
  setAllPixels(false);
  delay(1000);

  // Additional debug output
  Serial.println("Loop completed");
}

