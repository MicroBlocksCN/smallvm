# M5Stack StickS3

Build with `pio run -e m5stick-s3` (PlatformIO espressif32 6.12.0,
Arduino ESP32 2.0.17). In this isolated checkout the build uses
`PLATFORMIO_CORE_DIR="$PWD/.pio-core" pio run -e m5stick-s3`.

## Implemented

- Board identity `M5StickS3`, native USB CDC, BLE IDE, Wi-Fi, 8 MB QIO
  flash / 8 MB octal PSRAM. The existing MicroBlocks partition layout is
  retained, including its program-storage offsets; only 4 MB is partitioned.
- IDE recognizes BLE control and file-transfer capabilities.
- Buttons A/B: GPIO11/12, active low. No GPIO user LED or default buzzer.
- ST7789: landscape 240 x 135, inverted, controller offsets 52/40 and
  53/40 for opposite rotations. MOSI39, SCK40, DC45, CS41, reset21,
  backlight38 with the TFT 0–10 brightness block. LEDC channels 6/7 (timer3)
  are reserved for backlight; external PWM/servos use channels 2–5. LCD uses HSPI; external SPI uses FSPI.
- M5PM1 on internal Wire1 (SDA47/SCL48, address 0x6e): disables external
  boost, I2C idle sleep and watchdog; configures GPIO2 as push-pull output
  high to supply LCD L3B. Every read/modify/write aborts on I2C failure.
- BMI270 at 0x68 on Wire1, using SparkFun 1.0.3 and Bosch's configuration
  firmware: acceleration, tilt, range and die temperature primitives.
  Axes follow M5Unified: X=rawY, Y=-rawX, Z=rawZ. Default 1 g = 100;
  range arguments 1/2/4/8 preserve MicroBlocks scaling. Communication failures
  report the existing I2C transfer error. A later request can reinitialize the
  sensor (at most once per second), preserving the requested range.
- Grove I2C: SDA9/SCL10. I2C reassignment rejects reserved or identical pins. Hat UART RX44/TX43.
  Default Hat SPI: SCK5/MISO6/MOSI7; chip select is user controlled.
  SPI pin reassignment persists and rejects reserved GPIOs.
- Generic GPIO is restricted to Hat/Grove pins 1..10, 43 and 44. USB,
  flash/PSRAM, LCD, audio, buttons, IR and internal power/IMU pins are reserved.

## Power and limitations

External 5V stays in **input mode**. Grove and Hat EXT_5V are not powered
from the battery/USB by this firmware. IR TX/RX also depend on this rail.
Do not enable the boost while an external supply is connected to Grove or
EXT_5V: the manufacturer warns of a short circuit / device damage risk.
No automatic boost enable or public power-control block is added.

ES8311 microphone/speaker audio, built-in IR transmit/receive and explicit
PM1 battery/shutdown blocks are not implemented. The onboard IR receiver
requires RMT and cannot use the generic GPIO decoder. GPIO tone primitives
can drive an external buzzer on an available pin; the default tone is absent.
Screen orientation, sensor axes, USB/BLE, power behavior and all external
interfaces require hardware acceptance testing. Compilation is not evidence
of correct electrical operation. No device was flashed during development.

## Sources

- https://docs.m5stack.com/en/core/StickS3 (pin map and power warning)
- https://github.com/m5stack/M5Unified/blob/master/src/utility/power/M5PM1_Class.inl
  (register definitions and GPIO2's two-bit function field)
- https://github.com/m5stack/M5PM1/blob/1.0.7/src/M5PM1.cpp
- https://github.com/m5stack/M5GFX/blob/master/src/M5GFX.cpp
  (StickS3 LCD pins, offsets and SPI3 host)
- https://github.com/sparkfun/SparkFun_BMI270_Arduino_Library/tree/v1.0.3

## Host verification

Run `tests/sticks3/run.sh` with a C++11 compiler. The mocks exercise PM1
read/modify/write failures, IMU initialization and range/read failures,
retry timing (including clock wrap), axis/scale conversion, and backlight
brightness clamping/setup failure. On macOS/Linux the bundled GP runtime
also checks the actual IDE capability methods for StickS3, existing boards,
and an unknown board without opening a serial port or UI.

Build both `m5stick-s3` and `esp32-s3` for the board and compile regression.

## Hardware acceptance (not performed)

Check cold USB/battery boot and LCD edges/colors, both buttons, flat and
rotated tilt values and all four ranges, temperature, USB/BLE reconnect,
Grove I2C, Hat UART and simultaneous LCD/external SPI use. Measure external
5V input-mode behavior before connecting a powered accessory. Use the
side reset button's long press to enter download mode, as documented by M5Stack.
