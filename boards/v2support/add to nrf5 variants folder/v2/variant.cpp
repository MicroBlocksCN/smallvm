/* Placeholder for V2
 * John Maloney
*/

#include "variant.h"

const uint32_t g_ADigitalPinMap[] = {
  // 0 - 4
  2,  // A0 - left pad
  3,  // A1 - middle pad
  4,  // A2 - right pad
  31, // A3, COL3
  28, // A4, COL1

  // 5 - 9
  14, // BTN A
  37, // COL4, P1.05
  11, // COL2
  10, // NFC2
  9,  // NFC1

  // 10-16
  30, // A5, COL5
  23, // BTN B
  12,
  17, // SCK
  1,  // MISO
  13, // MOSI
  34, // P1.02

  // 17 + 18
  (uint32_t)-1, // 3.3V
  (uint32_t)-1, // 3.3V

  // 19 + 20
  26, // SCL
  32, // SDA, P1.00

  // 21 - 25
  21, // ROW1
  22, // ROW2
  15, // ROW3
  24, // ROW4
  19, // ROW5

  // 26 - 30
  20, // RUN_MIC
  5,  // MIC_IN
  0,  // KL27_DAC
  16, // I2C_INT_SDA
  8,  // I2C_INT_SCL

  // 31 - 33
  25, // COMBINED_SENSOR_INT
  6,  // RX
  40, // TX, P1.08
};
