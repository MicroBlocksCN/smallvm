/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// ioPrims.cpp - Microblocks IO primitives and hardware dependent functions
// John Maloney, April 2017

#include <Arduino.h>
#include <stdio.h>
#include <stdlib.h>

#ifdef __ZEPHYR__
#include <zephyr/random/random.h>
#endif

#include "mem.h"
#include "interp.h"

#if !defined(ARDUINO_API_VERSION)
  // typedef PinMode as int for use on platforms that do not use the Arduino Core API
  typedef int PinMode;
  typedef int PinStatus;
#endif

#if defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO)
	// Redefine serial port mapping for Samw25x to use "Target USB" port
	// The default "Debug USB" port fails to accept long scripts.
	#undef Serial
	#define Serial SerialUSB
#endif

static void initPins(void); // forward reference
static void initRandomSeed(void); // forward reference
static void stopRF(); // forward reference

// Timing Functions and Hardware Initialization

#if defined(NRF51) || defined(NRF52)

#define USE_NRF5x_CLOCK true

// Both NIMBLE and the Nordic Softdevice BLE systems use Timer0.
// MicroBlocks only supports BLE on the nRF52, we use TIMER1 on nRF52.
// Use TIMER0 on the nRF51, since that is the only 32-bit timer on the nRF51.
#if defined(NRF52)
  #define MB_TIMER NRF_TIMER1
  #define MB_TIMER_IRQn TIMER1_IRQn
  #define MB_TIMER_IRQHandler TIMER1_IRQHandler
#else
  #define MB_TIMER NRF_TIMER0
  #define MB_TIMER_IRQn TIMER0_IRQn
  #define MB_TIMER_IRQHandler TIMER0_IRQHandler
#endif

static void initClock_NRF5x() {
	MB_TIMER->TASKS_SHUTDOWN = true;
	MB_TIMER->MODE = 0; // timer (not counter) mode
	MB_TIMER->BITMODE = 3; // 32-bit
	MB_TIMER->PRESCALER = 4; // 1 MHz (16 MHz / 2^4)
	MB_TIMER->TASKS_START = true;
}

uint32 microsecs() {
	MB_TIMER->TASKS_CAPTURE[0] = true;
	return MB_TIMER->CC[0];
}

uint32 millisecs() {
	// Note: The divide operation makes this slower than microsecs(), so use microsecs()
	// when high-performance is needed. The millisecond clock is effectively only 22 bits
	// so, like the microseconds clock, it wraps around every 72 minutes.

	return microsecs() / 1000;
}

#else // not NRF5x

uint32 microsecs() { return (uint32) micros(); }
uint32 millisecs() { return (uint32) millis(); }

#endif

static uint32 microsecondHighBits = 0;
static uint32 lastMicrosecs = 0;

uint64 totalMicrosecs() {
	// Returns a 64-bit integer containing microseconds since start.

	return ((uint64) microsecondHighBits << 32) | microsecs();
}

void handleMicosecondClockWrap() {
	// Increment microsecondHighBits if the microsecond clock has wrapped since the last
	// time this function was called.

	uint32 now = microsecs();
	if (lastMicrosecs > now) microsecondHighBits++; // clock wrapped
	lastMicrosecs = now;
}

// Hardware Initialization

	#if (defined(ARDUINO_SAMD_ZERO) || defined(ARDUINO_SAM_ZERO)) && defined(SERIAL_PORT_USBVIRTUAL)
		#undef Serial
		#define Serial SERIAL_PORT_USBVIRTUAL
	#endif

void hardwareInit() {
	Serial.begin(115200);
	#ifdef USE_NRF5x_CLOCK
		initClock_NRF5x();
	#endif
	#if defined(ARDUINO_BBC_MICROBIT_V2) || defined(CALLIOPE_V3)
		// Use synthesized LF clock to free up pin the speaker pin (P0.00)
		NRF_CLOCK->LFCLKSRC = CLOCK_LFCLKSRC_SRC_Synth;
		NRF_CLOCK->TASKS_LFCLKSTART = 1;

		// Disable NFC by writing NRF_UICR->NFCPINS to free up pin 8 (P0.10)
		// (this change does not take effect until the next hard reset)
		if (NRF_UICR->NFCPINS & 1) {
			NRF_NVMC->CONFIG = NVMC_CONFIG_WEN_Wen; // enable Flash write
			while (NRF_NVMC->READY == NVMC_READY_READY_Busy) {}
			NRF_UICR->NFCPINS = 0xFFFFFFFE;
			NRF_NVMC->CONFIG = 0; // disable Flash write
		}
	#endif
	initPins();
	initRandomSeed();
	turnOffInternalNeoPixels();
	#ifdef ARDUINO_NRF52840_CLUE
		turnOffInternalNeoPixels(); // must be done twice on the Clue. Why? Haven't got a clue!
	#endif
	#if defined(ARDUINO_CITILAB_ED1)
		dacWrite(26, 0); // prevents serial TX noise on buzzer
		touchSetCycles(0x800, 0x900);
		writeI2CReg(0x20, 0, 0); // initialize IO expander
	#endif
	tftInit();
	tftClear();
	#if defined(DATABOT)
		int yellow = 14864128;
		setAllNeoPixels(-1, 3, yellow);
	#endif
	#if defined(ARDUINO_Mbits) || defined(ARDUINO_M5Atom_Matrix_ESP32)
		mbDisplayColor = (190 << 16); // red (not full brightness)
	#endif
	#if defined(XRP)
		delay(20); // allow ButtonA pin to settle before starting interpreter loop
	#endif
	#if defined(COCUBE)
        #include "soc/rtc_cntl_reg.h"  // for brownout control
        WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0); // disable brownout detector
		cocubeSensorInit();
	#endif
}

// General Purpose I/O Pins

#define BUTTON_PRESSED LOW

#if defined(ARDUINO_SAMD_MKR1000) || defined(ARDUINO_SAMD_MKRWIFI1010) || \
	defined(ARDUINO_SAMD_MKRZERO) || defined(ARDUINO_SAMD_MKRFox1200) || \
	defined(ARDUINO_SAMD_MKRGSM1400) || defined(ARDUINO_SAMD_MKRWAN1300)
		#define ARDUINO_SAMD_MKR
#endif

#if defined(ARDUINO_SAM_DUE)

	#define BOARD_TYPE "Due"
	#define DIGITAL_PINS 54
	#define ANALOG_PINS 14
	#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS)
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, DAC0, DAC1};

#elif defined(ARDUINO_NRF52_PRIMO)
	// Special pins: USER1_BUTTON (22->34) and BUZZER (23->35)

	#define BOARD_TYPE "Primo"
	#define DIGITAL_PINS 24
	#define ANALOG_PINS 6
	#define TOTAL_PINS DIGITAL_PINS
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5};
	#define PIN_BUTTON_A 34
		
#elif defined(ARDUINO_BBC_MICROBIT)

	#define BOARD_TYPE "micro:bit"
	#define DIGITAL_PINS 29
	#define ANALOG_PINS 6
	#define TOTAL_PINS DIGITAL_PINS
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5};

	// See variant.cpp in variants/BBCMicrobit folder for a detailed pin map.
	// Pins 0-20 are for micro:bit pads and edge connector
	//	(but pin numbers 17-18 correspond to 3.3 volt pads, not actual I/O pins)
	// Pins 21-22: RX, TX (for USB Serial?)
	// Pins 23-28: COL4, COL5, COL6, ROW1, ROW2, ROW3
	// Button A: pin 5
	// Button B: pin 11
	// Analog pins: The micro:bit does not have dedicated analog input pins;
	// the analog pins are aliases for digital pins 0-4 and 10.

#elif defined(ARDUINO_BBC_MICROBIT_V2)

	#define BOARD_TYPE "micro:bit v2"
	#define DIGITAL_PINS 29
	#define ANALOG_PINS 7
	#define TOTAL_PINS DIGITAL_PINS
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5, A6};
	#define DEFAULT_TONE_PIN 27

#elif defined(ARDUINO_CALLIOPE_MINI)

	#define BOARD_TYPE "Calliope"
	#define DIGITAL_PINS 27
	#define ANALOG_PINS 8
	#define TOTAL_PINS DIGITAL_PINS
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5, A6, A7};
	#define DEFAULT_TONE_PIN 25

	// See variant.cpp in variants/Calliope folder for a detailed pin map.
	// Pins 0-19 are for the large pads and 26 pin connector
	// Button A: pin 20
	// Button B: pin 22
	// Motor/Speaker: pins 23-25
	// NeoPixel: pin 26
	// Analog pins:
	//	A0 - microphone
	//	A1, A2 - pads 1 and 2
	//	A3, A4, A5 - connector pins 4, 5, and 6
	//	A6, A7 - connector pins 17, 18 and Grove connector 2

#elif defined(CALLIOPE_V3)

	#define BOARD_TYPE "Calliope v3"
	#define DIGITAL_PINS 36
	#define ANALOG_PINS 8
	#define TOTAL_PINS 41
	#define USE_DIGITAL_PIN_MAP true
	static const int analogPin[8] = {0, 1, 2, 18, 4, 10, 16, 29}; // variant.h pin 3 is wrong
	static const char digitalPin[36] = {
		 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,
		10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
		20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
		35, 36, 37, 38, 39, 40};
		// Pin 30 - RGB NeoPixels
		// Pin 31 - MOTOR_MODE
		// Pin 32 - M0_DIR
		// Pin 33 - M0_SPEED
		// Pin 34 - M1_DIR
		// Pin 35 - M1_SPEED
	#define DEFAULT_TONE_PIN 27

#elif defined(ARDUINO_SINOBIT)

	#define BOARD_TYPE "sino:bit"
	#define DIGITAL_PINS 29
	#define ANALOG_PINS 6
	#define TOTAL_PINS DIGITAL_PINS
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5};

	// See variant.cpp in variants/Sinbit folder for a detailed pin map.
	// Pins 0-19 are for the large pads and 26 pin connector
	//	(but pin numbers 17-18 correspond to 3.3 volt pads, not actual I/O pins)
	// Pins 21-22: RX, TX (for USB Serial?)
	// Pins 23-28: COL4, COL5, COL6, ROW1, ROW2, ROW3
	// Button A: pin 5
	// Button B: pin 11
	// Analog pins: The sino:bit does not have dedicated analog input pins;
	// the analog pins are aliases for digital pins 0-4 and 10.

#elif defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS)
	// Note: This case muse come before the ARDUINO_SAMD_ZERO case.
	// Note: Pin count does not include pins 36-38, the USB serial pins

	#define BOARD_TYPE "CircuitPlayground"
	#define DIGITAL_PINS 16
	#define ANALOG_PINS 11
	#define TOTAL_PINS 27
	#define USE_DIGITAL_PIN_MAP true
	static const int analogPin[11] = {A0, A1, A2, A3, A4, A5, A6, A7, A8, A9, A10};
		// A0-A7 Pads on board
		// A8 - light sensor
		// A9 - temperature sensor
	static const char digitalPin[16] = {12, 6, 9, 10, 3, 2, 0, 1, 4, 5, 7, 26, 25, 13, 8, 11};
		// Pins 0-7 Pads on board
		// Pin 8 - button A
		// Pin 9 - button B
		// Pin 10 - slide switch
		// Pin 11 - IR receiver
		// Pin 12 - IR transmitter
		// Pin 13 - red LED
		// Pin 14 - neopixels
		// Pin 15 - speaker disable
	#define PIN_BUTTON_A 4
	#define PIN_BUTTON_B 5
	#undef BUTTON_PRESSED
	#define BUTTON_PRESSED HIGH

#elif defined(ARDUINO_NRF52840_CIRCUITPLAY)

	#define BOARD_TYPE "CircuitPlayground Bluefruit"
	#define DIGITAL_PINS 14
	#define ANALOG_PINS 10
	#define TOTAL_PINS 14
	#define USE_DIGITAL_PIN_MAP true
	static const int analogPin[10] = {A0, A1, A2, A3, A4, A5, A6, A7, A8, A9};
		// A0-A7 Pads on board
		// A8 - light sensor
		// A9 - temperature sensor
	static const char digitalPin[14] = {12, 6, 9, 10, 3, 2, 0, 1, 4, 5, 7, 8, 13, 13};
		// Pins 0-7 Pads on board
		// Pin 8 - button A
		// Pin 9 - button B
		// Pin 10 - slide switch
		// Pin 11 - neopixels
		// Pin 12 - red LED
		// Pin 13 - red LED (duplicate, to match label on board)
	#define PIN_LED 13
	#define PIN_BUTTON_A 4
	#define PIN_BUTTON_B 5
	#undef BUTTON_PRESSED
	#define BUTTON_PRESSED HIGH

#elif defined(ARDUINO_NRF52840_CLUE)

	#define BOARD_TYPE "Clue"
	#define DIGITAL_PINS 23
	#define ANALOG_PINS 8
	#define TOTAL_PINS 48
	#define USE_DIGITAL_PIN_MAP true
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5, A6, A7};
	static const char digitalPin[23] = {
		// Pins 0-20 Edge connector pins (except 17 & 18)
		// Pin 17 - red LED (internal; not on edge connector)
		// Pin 18 - NeoPixel (internal; not on edge connector)
		// Pin 21 - speaker (internal pin 46)
		// Pin 22 - white LED (internal pin 43)
		0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
		11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
		46, 43};
	#define PIN_LED 17
	#define PIN_BUTTON_A 5
	#define PIN_BUTTON_B 11
	#define DEFAULT_TONE_PIN 21

	// Clue i2c sensors:
	// 28 - LIS3MDL magnetometer
	// 57 - APDS9960 light & gesture
	// 68 - SHT31-D temp & humidity
	// 106 - LSM6DS accelerometer & gyroscope
	// 119 - BMP280 remperature & air pressure

#elif defined(ARDUINO_NRF52840_FEATHER)
	#define BOARD_TYPE "Feather nRF52840 Express"
	#define DIGITAL_PINS 20
	#define ANALOG_PINS 6
	#define TOTAL_PINS 20
	#define PIN_LED 3
	#define DEFAULT_TONE_PIN 2
	static const int analogPin[6] = {A0, A1, A2, A3, A4, A5};
	// Note: pins 0 and 1 are reserved for primary UART

#elif defined(ARDUINO_TEENSY31)
	#define BOARD_TYPE "Teensy 3.1"
	#define DIGITAL_PINS 24
	#define ANALOG_PINS 10
	#define TOTAL_PINS 34
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5, A6, A7, A8, A9};
	#define PIN_LED 13

#elif defined(ARDUINO_TEENSY40)
	// placeholder; not tested
	#define BOARD_TYPE "Teensy 4.0"
	#define DIGITAL_PINS 24
	#define ANALOG_PINS 10
	#define TOTAL_PINS 34
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5, A6, A7, A8, A9};
	#define PIN_LED 13

#elif defined(ARDUINO_TEENSY41)
	// placeholder; not tested
	#define BOARD_TYPE "Teensy 4.1"
	#define DIGITAL_PINS 24
	#define ANALOG_PINS 10
	#define TOTAL_PINS 34
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5, A6, A7, A8, A9};
	#define PIN_LED 13

#elif defined(ADAFRUIT_GEMMA_M0)

	#define BOARD_TYPE "Gemma M0"
	#define DIGITAL_PINS 5
	#define ANALOG_PINS 3
	#define TOTAL_PINS 14
	static const int analogPin[] = {A0, A1, A2};

#elif defined(ADAFRUIT_ITSYBITSY_M0)

	#define BOARD_TYPE "Itsy Bitsy M0"
	#define DIGITAL_PINS 28
	#define ANALOG_PINS 12
	#define TOTAL_PINS 42
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11};

#elif defined(ADAFRUIT_TRINKET_M0)

	#define BOARD_TYPE "Trinket M0"
	#define DIGITAL_PINS 7
	#define ANALOG_PINS 5
	#define TOTAL_PINS 19
	static const int analogPin[] = {A0, A1, A2, A3, A4};

#elif defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO)
	// Note: The VM for this board can only be built with PlatformIO.
	// Note: This case must come before the ARDUINO_SAMD_MKR case when using PlatformIO.

	#define BOARD_TYPE "SAMW25_XPRO"
	#define DIGITAL_PINS 18
	#define ANALOG_PINS 3
	#define TOTAL_PINS DIGITAL_PINS
	#define INVERT_USER_LED true
	#define PIN_BUTTON_A 13 // PB10, pin13 in PlatformIO
	static const int analogPin[] = {A0, A1, A2};
	static const char reservedPin[TOTAL_PINS] = {
		0, 0, 0, 0, 1, 1, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0};

#elif defined(ARDUINO_SAMD_MKR)

	#define BOARD_TYPE "MKR Series"
	#define DIGITAL_PINS 15
	#define ANALOG_PINS 7
	#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS)
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5, A6};

#elif defined(MAKERPORT_V2) // must come before Zero

	#define BOARD_TYPE "MakerPort V2"
	#define DIGITAL_PINS 26
	#define ANALOG_PINS 9
	#define TOTAL_PINS 26
	static const int analogPin[] = {0, 1, 2, 3, 4, 5, 6, 13, 14};

#elif defined(MAKERPORT_V3) // must come before Zero

	#define BOARD_TYPE "MakerPort V3"
	#define DIGITAL_PINS 28
	#define ANALOG_PINS 9
	#define TOTAL_PINS 28
	static const int analogPin[] = {0, 1, 2, 3, 4, 5, 6, 13, 15};

#elif defined(MAKERPORT) // must come before Zero

	#define BOARD_TYPE "MakerPort"
	#define DIGITAL_PINS 22
	#define ANALOG_PINS 9
	#define TOTAL_PINS 22
	static const int analogPin[] = {0, 1, 2, 3, 4, 5, 6, 13, 14};

#elif defined(ADAFRUIT_METRO_M0_EXPRESS) // must come before Zero

	#define BOARD_TYPE "Metro M0"
	#define DIGITAL_PINS 20
	#define ANALOG_PINS 6
	#define TOTAL_PINS 20
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5};

#elif defined(ARDUINO_SAMD_ZERO)

	#define BOARD_TYPE "Zero"
	#define DIGITAL_PINS 14
	#define ANALOG_PINS 6
	#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS)
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5};

#elif defined(ARDUINO_SAM_ZERO)

	#define BOARD_TYPE "M0"
	#define DIGITAL_PINS 24
	#define ANALOG_PINS 6
	#define TOTAL_PINS (DIGITAL_PINS + ANALOG_PINS)
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5};

#elif defined(ESP8266) || defined(ARDUINO_ESP8266_WEMOS_D1MINI)

	#define BOARD_TYPE "ESP8266"
	#define DIGITAL_PINS 9
	#define ANALOG_PINS 1
	#define TOTAL_PINS 18 // A0 is pin 17
	#define USE_DIGITAL_PIN_MAP true
	static const int analogPin[] = {A0};
	static const char digitalPin[9] = {16, 5, 4, 0, 2, 14, 12, 13, 15};
	#define PIN_LED LED_BUILTIN
	#define PIN_BUTTON_A 0
	#define INVERT_USER_LED true

#elif defined(ARDUINO_CITILAB_ED1)

	#define BOARD_TYPE "Citilab ED1"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 4
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	static const char reservedPin[TOTAL_PINS] = {
		1, 1, 0, 1, 0, 0, 1, 1, 1, 1,
		1, 1, 0, 0, 0, 0, 1, 1, 1, 1,
		1, 1, 1, 1, 1, 0, 0, 0, 1, 1,
		1, 1, 0, 1, 0, 0, 0, 0, 0, 0};
	#define PIN_LED 0
	#define PIN_BUTTON_A 15
	#define PIN_BUTTON_B 14
	#define DEFAULT_TONE_PIN 26
	static const char ed1AnalogPinMap[4] = { 36, 37, 38, 39 };
	static const char ed1DigitalPinMap[4] = { 12, 25, 32, 26 };
	#define CAP_THRESHOLD 16
	static const char buttonsPins[6] = { 2, 4, 13, 14, 15, 27 };
	static int buttonIndex = 0;
	int buttonReadings[6] = {
		CAP_THRESHOLD + 1, CAP_THRESHOLD, CAP_THRESHOLD,
		CAP_THRESHOLD, CAP_THRESHOLD, CAP_THRESHOLD };

#elif defined(ARDUINO_M5Stack_Core_ESP32) || defined(ARDUINO_M5STACK_FIRE)
	#if defined(ARDUINO_M5STACK_FIRE)
		#define BOARD_TYPE "M5Stack-Core"	
	#else
		#define BOARD_TYPE "M5Stack-Core"
	#endif
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define PIN_BUTTON_A 39
	#define PIN_BUTTON_B 38
	#define DEFAULT_TONE_PIN 25
	#ifdef LED_BUILTIN
		#define PIN_LED LED_BUILTIN
	#else
		#define PIN_LED 2
	#endif
	#ifdef KEY_BUILTIN
		#define PIN_BUTTON_A KEY_BUILTIN
	#endif
	static const char reservedPin[TOTAL_PINS] = {
		0, 1, 0, 1, 0, 0, 1, 1, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 0, 0, 0,
		1, 0, 0, 0, 1, 0, 0, 0, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 0, 0, 0};

#elif defined(ARDUINO_M5Stick_Plus) || defined(ARDUINO_M5Stick_C2)
	#define BOARD_TYPE "M5StickC+"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define PIN_BUTTON_A 37
	#define PIN_BUTTON_B 39
	#define DEFAULT_TONE_PIN 2
	#if defined(ARDUINO_M5Stick_Plus)
	#define PIN_LED 10
	#define INVERT_USER_LED true
	#else
	#define PIN_LED 19
	#endif
	
	static const char reservedPin[TOTAL_PINS] = {
		0, 1, 0, 1, 1, 1, 1, 1, 1, 0,
		0, 1, 1, 1, 1, 1, 1, 1, 1, 1,
		1, 1, 1, 1, 1, 0, 0, 1, 1, 1,
		1, 1, 0, 0, 1, 1, 0, 0, 1, 0};

#elif defined(ARDUINO_M5Stick_C)
	#define BOARD_TYPE "M5StickC"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define PIN_BUTTON_A 37
	#define PIN_BUTTON_B 39
	#define DEFAULT_TONE_PIN 26
	#define PIN_LED 10
	#define INVERT_USER_LED true
	static const char reservedPin[TOTAL_PINS] = {
		0, 1, 1, 1, 1, 1, 1, 1, 1, 0,
		0, 1, 1, 1, 1, 1, 1, 1, 1, 1,
		1, 1, 1, 1, 1, 1, 0, 1, 1, 1,
		1, 1, 0, 0, 1, 1, 0, 0, 1, 0};

#elif defined(ARDUINO_M5CoreInk)
	#define BOARD_TYPE "M5CoreInk"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define PIN_BUTTON_A 37
	#define PIN_BUTTON_B 39
	#define DEFAULT_TONE_PIN 2
	#define PIN_LED 10
	#define INVERT_USER_LED true
	static const char reservedPin[TOTAL_PINS] = {
		0, 1, 1, 1, 1, 1, 1, 1, 1, 0,
		0, 1, 1, 1, 1, 1, 1, 1, 1, 1,
		1, 1, 1, 1, 1, 1, 0, 1, 1, 1,
		1, 1, 0, 0, 0, 1, 0, 0, 1, 0};

#elif defined(ARDUINO_M5Atom_Matrix_ESP32)

	#define BOARD_TYPE "M5Atom-Matrix"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define PIN_BUTTON_A 39
	static const char reservedPin[TOTAL_PINS] = {
		1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
		1, 1, 0, 1, 1, 1, 1, 1, 1, 0,
		1, 0, 0, 0, 1, 0, 0, 0, 1, 1,
		1, 1, 0, 0, 1, 1, 1, 1, 1, 0};

#elif defined(ARDUINO_M5Atom_Lite_ESP32)

	#define BOARD_TYPE "M5Atom-Lite"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	#define PIN_LED 27
	static const int analogPin[] = {};
	#define PIN_BUTTON_A 39
	static const char reservedPin[TOTAL_PINS] = {
		1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
		1, 1, 0, 1, 1, 1, 1, 1, 1, 0,
		1, 0, 0, 0, 1, 0, 0, 0, 1, 1,
		1, 1, 0, 0, 1, 1, 1, 1, 1, 0};

#elif defined(ARDUINO_M5STACK_Core2)
	#define BOARD_TYPE "M5StackCore2"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define DEFAULT_TONE_PIN 2
	static const char reservedPin[TOTAL_PINS] = {
		0, 1, 0, 1, 0, 0, 1, 1, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 0, 0, 0,
		1, 0, 0, 0, 1, 0, 0, 0, 1, 0,
		1, 1, 0, 0, 0, 0, 0, 0, 0, 0};

#elif defined(COCUBE)
	#define BOARD_TYPE "COCUBE"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define DEFAULT_TONE_PIN 4
	#define PIN_LED -1
	#define DEFAULT_BATTERY_PIN 34
	#define DEFAULT_L1_PIN 9
	#define DEFAULT_L2_PIN 10
	#define DEFAULT_R1_PIN 26
	#define DEFAULT_R2_PIN 25
	#define PIN_BUTTON_A 38
	#define PIN_BUTTON_B 37
	static const char reservedPin[TOTAL_PINS] = {
		0, 1, 0, 1, 0, 1, 1, 1, 1, 0,
		0, 1, 1, 0, 0, 1, 1, 1, 0, 0,
		1, 0, 0, 0, 1, 0, 0, 0, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 0, 0, 0};
		
#elif defined(ARDUINO_ESP32_PICO)
	#define BOARD_TYPE "ESP32-Pico-D4"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define DEFAULT_TONE_PIN 2
	#define PIN_LED 13
	static const char reservedPin[TOTAL_PINS] = {
		0, 1, 0, 1, 0, 1, 1, 1, 1, 0,
		0, 1, 1, 0, 0, 1, 1, 1, 0, 0,
		1, 1, 1, 0, 1, 0, 0, 0, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 0, 0, 0};

#elif defined(ARDUINO_Mbits)
	#define BOARD_TYPE "Mbits"
	#define PIN_BUTTON_A 36
	#define PIN_BUTTON_B 39
	#define DIGITAL_PINS 22
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	#define USE_DIGITAL_PIN_MAP true
	static const int analogPin[] = {};
	static const char digitalPin[22] = {
		26, 32, 25, 13, 27, 36, 5, 12, 4, 34,
		14, 39, 15, 18, 19, 23, 2, 255, 255, 21,
		22, 33}; // edge connector pins 17 & 18 are not used
	#define DEFAULT_TONE_PIN 21
	static const char reservedPin[TOTAL_PINS] = {
		0, 1, 0, 1, 0, 1, 1, 1, 1, 0,
		1, 1, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 1, 1, 0,
		0, 0, 0, 0, 0, 1, 1, 0, 1, 1};

#elif defined(TTGO_DISPLAY)
	#define BOARD_TYPE "TTGO_DISPLAY"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define PIN_LED 4 // display backlight
	#define PIN_BUTTON_A 0
	#define PIN_BUTTON_B 35
	static const char reservedPin[TOTAL_PINS] = {
		0, 1, 0, 1, 0, 0, 1, 1, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 0, 0, 0,
		1, 0, 0, 0, 1, 0, 0, 0, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 1, 1, 0};

#elif defined(ARDUINO_Labplus_mPython)
	#if defined(MATRIXBIT)
		#define BOARD_TYPE "Matrix Bit"	
	#elif defined(QIANKUN)
		#define BOARD_TYPE "QIAN KUN"	
	#else
		#define BOARD_TYPE "handpy"
	#endif
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define PIN_LED 12
	#define PIN_BUTTON_A 0
	#define PIN_BUTTON_B 2
	#define DEFAULT_TONE_PIN 16
	#undef BUTTON_PRESSED
	#define BUTTON_PRESSED HIGH
	static const char reservedPin[TOTAL_PINS] = {
		0, 1, 0, 1, 0, 0, 1, 1, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 0, 0, 0,
		1, 0, 0, 0, 1, 0, 0, 0, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 1, 1, 0};

#elif defined(COCOROBO)
	#define BOARD_TYPE "cocorobo"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define PIN_LED 14
	#define PIN_BUTTON_A 34
	#define PIN_BUTTON_B 35
	#define DEFAULT_TONE_PIN 26
	static const char reservedPin[TOTAL_PINS] = {
		0, 1, 0, 1, 0, 0, 1, 1, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 0, 0, 0,
		1, 0, 0, 0, 1, 0, 0, 0, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 1, 1, 0};
		
#elif defined(M5STAMP)
	#define BOARD_TYPE "M5STAMP"
	#define DIGITAL_PINS 22
	#define ANALOG_PINS 8
	#define TOTAL_PINS 22
	static const int analogPin[] = {};
	#define PIN_LED 2
	#define PIN_BUTTON_A 3
	static const char reservedPin[TOTAL_PINS] = {
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 1, 1, 1, 1, 1, 1, 1, 1, 1,
		1, 1};

#elif defined(DATABOT)
	#define BOARD_TYPE "Databot"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	// databot does not have a user LED; map it to unused pin 12
	#define PIN_LED 12
	#define DEFAULT_TONE_PIN 32
	static const char reservedPin[TOTAL_PINS] = {
		0, 1, 0, 1, 0, 0, 1, 1, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 0, 0, 0,
		1, 1, 1, 0, 1, 0, 0, 0, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 1, 1, 0};
	

#elif defined(ESP32_S2)
	#define BOARD_TYPE "ESP32-S2"
	#define DIGITAL_PINS 48
	#define ANALOG_PINS 20
	#define TOTAL_PINS 48
	static const int analogPin[] = {};
	#ifdef LED_BUILTIN
		#define PIN_LED LED_BUILTIN
	#elif !defined(PIN_LED)
		#define PIN_LED -1
	#endif
	#if !defined(PIN_BUTTON_A)
		#if defined(KEY_BUILTIN)
			#define PIN_BUTTON_A KEY_BUILTIN
		#else
			#define PIN_BUTTON_A 0
		#endif
	#endif
	// See https://docs.espressif.com/projects/esp-idf/en/stable/esp32s2/hw-reference/esp32s2/user-guide-saola-1-v1.2.html
	// strapping pins 0 (Boot), 45 (VSPI), 46 (LOG)
	// USB pins: 19 (USB D-), 20 (USB D+)
	static const char reservedPin[TOTAL_PINS] = {
		1, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
		1, 1, 1, 1, 1, 1, 0, 1, 1, 1,
		1, 1, 1, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0};

#elif defined(FUTURE_LITE)
	#define BOARD_TYPE "FUTURE-LITE"
	#define DIGITAL_PINS 49
	#define ANALOG_PINS 20
	#define TOTAL_PINS 49
	static const int analogPin[] = {};
	#define PIN_LED 10
	#define PIN_BUTTON_A 15
	#define PIN_BUTTON_B 16
	#define DEFAULT_TONE_PIN 8
	#undef BUTTON_PRESSED
	#define BUTTON_PRESSED HIGH
	// See https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/api-reference/peripherals/gpio.html
	// strapping pins 0 (Boot), 3 (JTAG), 45 (VSPI), 46 (LOG)
	// SPI (26-32); also 33-37 on boards with Octal SPI Flash PSRAM
	// USB pins: 19 (USB D-), 20 (USB D+)
	// also possibly: 39-42 (JTAG pins)
	static const char reservedPin[TOTAL_PINS] = {
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 1, 1, 1, 1, 1, 1, 1, 1,
		1, 1, 1, 1, 1, 0, 0, 0, 0, 0,
		0, 0, 0, 1, 1, 0, 0, 0, 0};

#elif defined(M5_ATOMS3LITE)
	#define BOARD_TYPE "M5-AtomS3Lite"
	#define DIGITAL_PINS 49
	#define ANALOG_PINS 20
	#define TOTAL_PINS 49
	static const int analogPin[] = {};
	#define PIN_LED 35
	#define PIN_BUTTON_A 42

	static const char reservedPin[TOTAL_PINS] = {
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 1, 1, 1, 1, 1, 1, 1, 1,
		1, 1, 1, 1, 1, 0, 0, 0, 0, 0,
		0, 0, 0, 1, 1, 0, 0, 0, 0};

#elif defined(M5_CARDPUTER)
	#define BOARD_TYPE "M5-CARDPUTER"
	#define DIGITAL_PINS 49
	#define ANALOG_PINS 20
	#define TOTAL_PINS 49
	static const int analogPin[] = {};
	#ifdef LED_BUILTIN
		#define PIN_LED LED_BUILTIN
	#elif !defined(PIN_LED)
		#define PIN_LED -1
	#endif
	#if !defined(PIN_BUTTON_A)
		#if defined(KEY_BUILTIN)
			#define PIN_BUTTON_A KEY_BUILTIN
		#else
			#define PIN_BUTTON_A 0
		#endif
	#endif
	static const char reservedPin[TOTAL_PINS] = {
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 1, 1, 1, 1, 1, 1, 1, 1,
		1, 1, 1, 1, 1, 0, 0, 0, 0, 0,
		0, 0, 0, 1, 1, 0, 0, 0, 0};

#elif defined(M5_DIN_METER)
	#define BOARD_TYPE "M5_DIN_METER"
	#define DIGITAL_PINS 49
	#define ANALOG_PINS 20
	#define TOTAL_PINS 49
	static const int analogPin[] = {};
	#define DEFAULT_TONE_PIN 3
	#ifdef LED_BUILTIN
		#define PIN_LED LED_BUILTIN
	#elif !defined(PIN_LED)
		#define PIN_LED -1
	#endif
	#define PIN_BUTTON_A 42
	#undef BUTTON_PRESSED
	#define BUTTON_PRESSED HIGH
	static const char reservedPin[TOTAL_PINS] = {
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 1, 1, 1, 1, 1, 1, 1, 1,
		1, 1, 1, 1, 1, 0, 0, 0, 0, 0,
		0, 0, 0, 1, 1, 0, 0, 0, 0};

#elif defined(ARDUINO_M5STACK_CORES3)
	#define BOARD_TYPE "M5-CoreS3"
	#define DIGITAL_PINS 49
	#define ANALOG_PINS 20
	#define TOTAL_PINS 49
	static const int analogPin[] = {};
	#ifdef LED_BUILTIN
		#define PIN_LED LED_BUILTIN
	#elif !defined(PIN_LED)
		#define PIN_LED -1
	#endif
	#if !defined(PIN_BUTTON_A)
		#if defined(KEY_BUILTIN)
			#define PIN_BUTTON_A KEY_BUILTIN
		#else
			#define PIN_BUTTON_A 0
		#endif
	#endif
	// See https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/api-reference/peripherals/gpio.html
	// strapping pins 0 (Boot), 3 (JTAG), 45 (VSPI), 46 (LOG)
	// SPI (26-32); also 33-37 on boards with Octal SPI Flash PSRAM
	// USB pins: 19 (USB D-), 20 (USB D+)
	// also possibly: 39-42 (JTAG pins)
	static const char reservedPin[TOTAL_PINS] = {
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 1, 1, 1, 1, 1, 1, 1, 1,
		1, 1, 1, 1, 1, 0, 0, 0, 0, 0,
		0, 0, 0, 1, 1, 0, 0, 0, 0};

#elif defined(ESP32_S3)
	#define BOARD_TYPE "ESP32-S3"
	#define DIGITAL_PINS 49
	#define ANALOG_PINS 20
	#define TOTAL_PINS 49
	static const int analogPin[] = {};
	#ifdef LED_BUILTIN
		#define PIN_LED LED_BUILTIN
	#elif !defined(PIN_LED)
		#define PIN_LED -1
	#endif
	#if !defined(PIN_BUTTON_A)
		#if defined(KEY_BUILTIN)
			#define PIN_BUTTON_A KEY_BUILTIN
		#else
			#define PIN_BUTTON_A 0
		#endif
	#endif
	// See https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/api-reference/peripherals/gpio.html
	// strapping pins 0 (Boot), 3 (JTAG), 45 (VSPI), 46 (LOG)
	// SPI (26-32); also 33-37 on boards with Octal SPI Flash PSRAM
	// USB pins: 19 (USB D-), 20 (USB D+)
	// also possibly: 39-42 (JTAG pins)
	static const char reservedPin[TOTAL_PINS] = {
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 1, 1, 1, 1, 1, 1, 1, 1,
		1, 1, 1, 1, 1, 0, 0, 0, 0, 0,
		0, 0, 0, 1, 1, 0, 0, 0, 0};

#elif defined(AIRM2MC3)
	#define BOARD_TYPE "airm2m_core_esp32c3"
	#define DIGITAL_PINS 22
	#define ANALOG_PINS 5
	#define TOTAL_PINS 22
	static const int analogPin[] = {0, 1, 2, 3, 4};
	#define PIN_LED 12
	#define PIN_BUTTON_A 9
	static const char reservedPin[TOTAL_PINS] = {
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 1, 1, 1, 1, 0, 0,
		1, 1};

#elif defined(ESP32_C3)
	#define BOARD_TYPE "ESP32-C3"
	#define DIGITAL_PINS 20
	#define ANALOG_PINS 6
	#define TOTAL_PINS 20
	static const int analogPin[] = {};
	#ifdef LED_BUILTIN
		#define PIN_LED LED_BUILTIN
	#elif !defined(PIN_LED)
		#define PIN_LED -1
	#endif
	#if !defined(PIN_BUTTON_A)
		#if defined(KEY_BUILTIN)
			#define PIN_BUTTON_A KEY_BUILTIN
		#else
			#define PIN_BUTTON_A 0
		#endif
	#endif
	static const char reservedPin[TOTAL_PINS] = {
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 1, 1, 1, 1, 1, 1, 1, 0, 0};

#elif defined(CONFIG_IDF_TARGET_ESP32S3)
	#define BOARD_TYPE "ESP32-S3"
	#define DIGITAL_PINS 49
	#define ANALOG_PINS 20
	#define TOTAL_PINS 49
	static const int analogPin[] = {};
	#ifdef BUILTIN_LED
		#define PIN_LED BUILTIN_LED
	#else
		#define PIN_LED 2
	#endif
	#if !defined(PIN_BUTTON_A)
		#if defined(KEY_BUILTIN)
			#define PIN_BUTTON_A KEY_BUILTIN
		#else
			#define PIN_BUTTON_A 0
		#endif
	#endif
	// See https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/api-reference/peripherals/gpio.html
	// strapping pins 0 (Boot), 3 (JTAG), 45 (VSPI), 46 (LOG)
	// SPI (26-32); also 33-37 on boards with Octal SPI Flash PSRAM
	// USB pins: 19 (USB D-), 20 (USB D+)
	// also possibly: 39-42 (JTAG pins)
	static const char reservedPin[TOTAL_PINS] = {
		1, 0, 1, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
		1, 0, 0, 0, 0, 0, 1, 1, 1, 1,
		1, 1, 1, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 1, 1, 0, 0};

#elif defined(HALOCODE)
	#define BOARD_TYPE "Halocode"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define PIN_BUTTON_A 26
	#define PIN_LED 0
	static const char reservedPin[TOTAL_PINS] = {
		0, 1, 0, 1, 0, 0, 1, 1, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 0, 0, 0,
		1, 0, 0, 0, 1, 0, 0, 0, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 0, 0, 0};
		
#elif defined(MINGBAI)
	#define BOARD_TYPE "mingbai"
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#define PIN_LED 13
	#define PIN_BUTTON_A 35
	#define PIN_BUTTON_B 36
	#define DEFAULT_TONE_PIN 32
	static const char reservedPin[TOTAL_PINS] = {
		0, 1, 0, 1, 0, 0, 1, 1, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 0, 0, 0,
		1, 0, 0, 0, 1, 0, 0, 0, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 1, 1, 0};

#elif defined(ARDUINO_ARCH_ESP32)
	#ifdef ARDUINO_IOT_BUS
		#define BOARD_TYPE "IOT-BUS"
		#define PIN_BUTTON_A 15
		#define PIN_BUTTON_B 14
	#else
		#define BOARD_TYPE "ESP32"
	#endif
	#define DIGITAL_PINS 40
	#define ANALOG_PINS 16
	#define TOTAL_PINS 40
	static const int analogPin[] = {};
	#ifdef LED_BUILTIN
		#define PIN_LED LED_BUILTIN
	#else
		#define PIN_LED 2
	#endif
	#if !defined(PIN_BUTTON_A)
		#if defined(KEY_BUILTIN)
			#define PIN_BUTTON_A KEY_BUILTIN
		#else
			#define PIN_BUTTON_A 0
		#endif
	#endif
	static const char reservedPin[TOTAL_PINS] = {
		0, 1, 0, 1, 0, 0, 1, 1, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 0, 0, 0,
		1, 0, 0, 0, 1, 0, 0, 0, 1, 1,
		1, 1, 0, 0, 0, 0, 0, 1, 1, 0};

#elif defined(TTGO_RP2040) // must come before ARDUINO_ARCH_RP2040

	#define BOARD_TYPE "TTGO RP2040"
	#define DIGITAL_PINS 30
	#define ANALOG_PINS 4
	#define TOTAL_PINS DIGITAL_PINS
	static const int analogPin[] = {A0, A1, A2, A3};
	#define PIN_BUTTON_A 6
	#define PIN_BUTTON_B 7
	static const char reservedPin[TOTAL_PINS] = {
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 1, 1, 1, 0, 0, 0, 0};

#elif defined(PICO_ED) // must come before ARDUINO_ARCH_RP2040

	#define BOARD_TYPE "Pico:ed"
	#define DIGITAL_PINS 21
	#define ANALOG_PINS 4
	#define TOTAL_PINS 30
	#define DEFAULT_TONE_PIN 17 // maps to speaker pin
	#define PIN_BUTTON_A 20
	#define PIN_BUTTON_B 21
	#define USE_DIGITAL_PIN_MAP true
	static const int analogPin[] = {26, 27, 28, 29};
	static char digitalPin[TOTAL_PINS] = {
		26, 27, 28, 29,  4,  5,  6,  7,  8, 9,
		10, 11, 12, 13, 14, 15, 16,  0, 25, 19, // change pin 17 from 0 to 3 for pico-ed v2
		18, 99, 99, 99, 99, 99, 99, 99, 99, 99}; // Note: pins 26-29 are accessed as pins 0-3 (99 means unused)
	static const char reservedPin[TOTAL_PINS] = {
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

	void setPicoEdSpeakerPin(int pin) { digitalPin[17] = pin; }

#elif defined(WUKONG2040) // must come before ARDUINO_ARCH_RP2040

	#define BOARD_TYPE "Wukong2040"
	#define DIGITAL_PINS 29
	#define ANALOG_PINS 3
	#define TOTAL_PINS DIGITAL_PINS
	#define PIN_BUTTON_A 18
	#define PIN_BUTTON_B 19
	#define DEFAULT_TONE_PIN 9
	static const int analogPin[] = {26, 27, 28};
	static const char reservedPin[TOTAL_PINS] = {
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 1, 1, 1, 0, 0, 0};

#elif defined(ARDUINO_ARCH_RP2040)

	#define BOARD_TYPE "RP2040"
	#define DIGITAL_PINS 29
	#define ANALOG_PINS 4
	#define TOTAL_PINS DIGITAL_PINS
	static const int analogPin[] = {A0, A1, A2, A3};
	#if defined(PICO_ED)
		#define PIN_BUTTON_A 20
		#define PIN_BUTTON_B 21
		#define DEFAULT_TONE_PIN 0 // speaker pin on Pico-ed v1 board
		static const char reservedPin[TOTAL_PINS] = {
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
			0, 0, 0, 0, 0, 0, 0, 0, 0};
	#else
		#if defined(XRP)
			#undef BOARD_TYPE
			#define BOARD_TYPE "RP2040 XRP"
			#define PIN_BUTTON_A 22
		#elif defined(GIZMO_MECHATRONICS)
			#undef BOARD_TYPE
			#define BOARD_TYPE "RP2040 Gizmo"
		#endif
		#define DEFAULT_TONE_PIN 20 // speaker pin on PicoBricks board
		static const char reservedPin[TOTAL_PINS] = {
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
			0, 0, 0, 1, 1, 1, 0, 0, 0};
	#endif

#elif defined(CONFIG_BOARD_BEAGLECONNECT_FREEDOM)
	#define BOARD_TYPE "BeagleConnect Freedom"
	#define DIGITAL_PINS 24
	#define ANALOG_PINS 6
	#define TOTAL_PINS 24
	static const int analogPin[] = {A0, A1, A2, A3, A4, A5};
	#define PIN_LED LED_BUILTIN

#else // unknown board

	#define BOARD_TYPE "Unknown Board"
	#define DIGITAL_PINS 0
	#define ANALOG_PINS 0
	#define TOTAL_PINS 0
	static const int analogPin[] = {};
	#define PIN_LED 0

#endif

// Board Type

const char * boardType() { return BOARD_TYPE; }

// Pin Modes

// The current pin input/output mode is recorded in the currentMode[] array to
// avoid calling pinMode() unless mode has actually changed. (This speeds up pin I/O.)

#define MODE_NOT_SET (-1)
static char currentMode[TOTAL_PINS];
static char pwmRunning[TOTAL_PINS];

#define SET_MODE(pin, newMode) { \
	if ((newMode) != currentMode[pin]) { \
		pinMode((pin), (PinMode) (newMode)); \
		currentMode[pin] = newMode; \
	} \
}

// Check for reserved pin on boards that define a reservedPin array
#define RESERVED(pin) (((pin) < 0) || ((pin) >= TOTAL_PINS) || (reservedPin[(pin)]))

int pinCount() { return TOTAL_PINS; }

void setPinMode(int pin, int newMode) {
	// Function to set pin modes from other modules. (The SET_MODE macro is local to this file.)

	SET_MODE(pin, newMode);
}

static void initPins(void) {
	// Initialize currentMode to MODE_NOT_SET (neither INPUT nor OUTPUT)
	// to force the pin's mode to be set on first use.

	#if defined(NRF52)
		// Use 8-bit PWM resolution on NRF52 to improve quaility of audio output.
		// With 8-bit samples, the PWM sampling rate is 16 MHz / 256 = 62500 samples/sec,
		// allowing a 0.1 to 0.33 uF capacitor to be used as a simple low-pass filter.
		// The analog write primitve takes a 10-bit value, as it does on all MicroBlocks boards,
		// but on NRF52 only the 8 most signifcant bits are used.
		analogWriteResolution(8);
	#elif !defined(ESP8266) && !defined(ARDUINO_ARCH_ESP32) && !defined(__ZEPHYR__)
		analogWriteResolution(10); // 0-1023; low-order bits ignored on boards with lower resolution
	#endif

	for (int i = 0; i < TOTAL_PINS; i++) {
		currentMode[i] = MODE_NOT_SET;
	}

	#if defined(XRP)
		// Fixes the problem with "when ButtonA" scripts being trigged on startup
		// on Russell's XRP board. It's not clear why this works.
		setPinMode(PIN_BUTTON_A, INPUT);
	#endif

	#ifdef ARDUINO_NRF52_PRIMO
		pinMode(USER1_BUTTON, INPUT);
		pinMode(BUZZER, OUTPUT);
	#endif

	#ifdef ARDUINO_CITILAB_ED1
		// set up buttons
		pinMode(2, INPUT_PULLUP); // ←
		pinMode(4, INPUT_PULLUP); // ↑
		pinMode(13, INPUT_PULLUP); // ↓
		pinMode(14, INPUT_PULLUP); // X
		pinMode(15, INPUT_PULLUP); // OK
		pinMode(27, INPUT_PULLUP); // →
	#endif
	
	#ifdef COCOROBO
		// trun off led
		pinMode(5, OUTPUT); // 
		pinMode(14, OUTPUT); // 
		pinMode(15, OUTPUT); // 
	#endif

	#ifdef COCUBE
		pinMode(DEFAULT_BATTERY_PIN, INPUT); // BATTERY PIN
		pinMode(DEFAULT_L1_PIN, OUTPUT); // L1 PIN
		pinMode(DEFAULT_L2_PIN, OUTPUT); // L2 PIN
		pinMode(DEFAULT_R1_PIN, OUTPUT); // L3 PIN
		pinMode(DEFAULT_R2_PIN, OUTPUT); // L4 PIN
		pinMode(PIN_BUTTON_A, INPUT_PULLUP); // BUTTON A
		pinMode(PIN_BUTTON_B, INPUT_PULLUP); // BUTTON B
	#endif
}

#if !defined(ARDUINO_SAM_DUE) && !defined(ESP8266)
  #define HAS_INPUT_PULLDOWN true
#endif

void turnOffPins() {
	for (int pin = 0; pin < TOTAL_PINS; pin++) {
		int turnOffPin = ((OUTPUT == currentMode[pin]) || (INPUT_PULLUP == currentMode[pin]));
		#if defined(HAS_INPUT_PULLDOWN)
			if (INPUT_PULLDOWN == currentMode[pin]) turnOffPin = true;
		#endif
		if (turnOffPin) SET_MODE(pin, INPUT);
	}
}

int mapDigitalPinNum(int pinNum) {
	#if defined(USE_DIGITAL_PIN_MAP)
		if ((0 <= pinNum) && (pinNum < DIGITAL_PINS)) return digitalPin[pinNum];
	#endif
	#if defined(ARDUINO_CITILAB_ED1)
		if ((100 <= pinNum) && (pinNum <= 139)) {
			return pinNum - 100; // allows access to unmapped IO pins 0-39 as 100-139
		} else if ((1 <= pinNum) && (pinNum <= 4)) {
			return ed1DigitalPinMap[pinNum - 1];
		}
	#endif
	#if defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO) || defined(ARDUINO_ARCH_ESP32) ||  defined(ARDUINO_ARCH_RP2040)
		if (RESERVED(pinNum)) return -1;
	#endif
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return -1; // out of range
	return pinNum;
}

static int inputModeFor(OBJ pullArg) {
	// Return the input mode (INPUT, INPUT_PULLUP, INPUT_PULLDOWN) for the given argument.
	// If the argument is a boolean: true -> INPUT_PULLUP, false -> INPUT
	// If the argument is a string: "up" -> INPUT_PULLUP, "down" -> INPUT_PULLDOWN, other -> INPUT

	int argType = objType(pullArg);
	if (BooleanType == argType) {
		return (pullArg == trueObj) ? INPUT_PULLUP : INPUT;
	} else if (StringType == argType) {
		char *s = obj2str(pullArg);
		if (strcmp("up", s) == 0) return INPUT_PULLUP;
		#if defined(HAS_INPUT_PULLDOWN)
			if (strcmp("down", s) == 0) return INPUT_PULLDOWN;
		#endif
	}
	return INPUT;
}

#if defined(ARDUINO_BBC_MICROBIT_V2) || defined(CALLIOPE_V3)

static void setHighDrive(int pin) {
	if ((pin < 0) || (pin >= PINS_COUNT)) return;
	pin = g_ADigitalPinMap[pin];
	NRF_GPIO_Type* port = (NRF_GPIO_Type*) ((pin < 32) ? 0x50000000 : 0x50000300);
	port->PIN_CNF[pin & 0x1F] |= (3 << 8); // high drive 1 and 0
}

#endif

// Pin IO Primitives

OBJ primAnalogPins(OBJ *args) { return int2obj(ANALOG_PINS); }

OBJ primDigitalPins(OBJ *args) { return int2obj(DIGITAL_PINS); }

OBJ primAnalogRead(int argCount, OBJ *args) {
	if (!isInt(args[0])) { fail(needsIntegerError); return int2obj(0); }
	int pinNum = obj2int(args[0]);

	#if defined(ARDUINO_BBC_MICROBIT)
		if (10 == pinNum) pinNum = 5; // map pin 10 to A5
	#elif defined(ARDUINO_BBC_MICROBIT_V2)
		if (6 == pinNum) return int2obj(readAnalogMicrophone()); // A6
		if (10 == pinNum) pinNum = 5; // map pin 10 to A5
		if (29 == pinNum) return int2obj(readAnalogMicrophone());
	#elif defined(ARDUINO_CALLIOPE_MINI)
		if (0 == pinNum) return int2obj(readAnalogMicrophone());
	#elif defined(CALLIOPE_V3)
		if (10 == pinNum) pinNum = 5; // map pin 10 to A5
		if (16 == pinNum) pinNum = 6; // map pin 16 to A6
		if (18 == pinNum) pinNum = 3; // map pin 18 to A3
		if (29 == pinNum) return int2obj(readAnalogMicrophone());
	#endif
	#ifdef ARDUINO_CITILAB_ED1
		if ((100 <= pinNum) && (pinNum <= 139)) {
			pinNum = pinNum - 100; // allows access to unmapped IO pins 0-39 as 100-139
		} else if ((1 <= pinNum) && (pinNum <= 4)) {
			pinNum = ed1AnalogPinMap[pinNum - 1];
		}
	#endif
	#ifdef ARDUINO_ARCH_ESP32
		#ifdef ARDUINO_Mbits
			if ((0 <= pinNum) && (pinNum <= 20) && (pinNum != 17) && (pinNum != 18)) {
				pinNum = digitalPin[pinNum]; // map edge connector pin number to ESP32 pin number
			}
		#endif
		// use the ESP32 pin number directly (if not reserved)
		if (RESERVED(pinNum)) return int2obj(0);
		SET_MODE(pinNum, INPUT);
		return int2obj(analogRead(pinNum) >> 2); // convert from 12-bit to 10-bit resolution
	#elif defined(ARDUINO_SAM_ZERO) // M0
		if ((pinNum == 14) || (pinNum == 15) ||
			((18 <= pinNum) && (pinNum <= 23))) return int2obj(0);
	#endif
	#if defined(ARDUINO_ARCH_RP2040) && !defined(PICO_ED)
		if ((pinNum < 26) || (pinNum > 29)) return int2obj(0);
		pinNum -= 26; // map pins 26-29 to A0-A3
	#endif
	#if defined(MAKERPORT) || defined(MAKERPORT_V2)
		if (13 == pinNum) pinNum = 7; // map pin 13 to A7
		if (14 == pinNum) pinNum = 8; // map pin 14 to A8
	#endif
	#if defined(MAKERPORT_V3)
		if (13 == pinNum) pinNum = 7; // map pin 13 to A7
		if (15 == pinNum) pinNum = 8; // map pin 15 to A8
	#endif

	if ((pinNum < 0) || (pinNum >= ANALOG_PINS)) return int2obj(0);
	int pin = analogPin[pinNum];
	int mode = (argCount > 1) ? inputModeFor(args[1]) : INPUT;
	SET_MODE(pin, mode);
	return int2obj(analogRead(pin));
}

#if defined(ESP32)

	#define MAX_ESP32_CHANNELS 16
	int esp32Channels[MAX_ESP32_CHANNELS];

	int pinAttached(int pin) {
		// Note: channel 0 is used by Tone
		if (!pin) return 0;
		for (int i = 1; i < MAX_ESP32_CHANNELS; i++) {
			if (esp32Channels[i] == pin) return i;
		}
		return 0; // not attached
	}

	void analogAttach(int pin) {
		int esp32Channel = 1;
		// Note: Do not use channels 0-1 or 8-9; those use timer0, which is used by Tone.
		while ((esp32Channel < MAX_ESP32_CHANNELS) && ((esp32Channels[esp32Channel] > 0) || ((esp32Channel & 7) <= 1))) {
			esp32Channel++;
		}
		if (esp32Channel < MAX_ESP32_CHANNELS) {
			ledcSetup(esp32Channel, 100, 10); // 100Hz, 10 bits (same clock rate as servos)
			ledcAttachPin(pin, esp32Channel);
			esp32Channels[esp32Channel] = pin;
		}
	}

	void pinDetach(int pin) {
		int esp32Channel = pinAttached(pin);
		if (esp32Channel > 0) {
			ledcWrite(esp32Channel, 0);
			ledcDetachPin(pin);
			esp32Channels[esp32Channel] = 0;
		}
	}

#endif

void primAnalogWrite(OBJ *args) {
	if (!isInt(args[0]) || !isInt(args[1])) { fail(needsIntegerError); return; }
	int pinNum = obj2int(args[0]);
	#if defined(ADAFRUIT_ITSYBITSY_M0)
		if (pinNum > 25) return;
	#elif defined(ADAFRUIT_TRINKET_M0)
		if (pinNum > 4) return;
	#elif defined(ARDUINO_ARCH_ESP32) || defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO) || defined(ARDUINO_ARCH_RP2040)
		#if defined(ARDUINO_CITILAB_ED1)
			if ((100 <= pinNum) && (pinNum <= 139)) {
				pinNum = pinNum - 100; // allows access to unmapped IO pins 0-39 as 100-139
			} else if ((1 <= pinNum) && (pinNum <= 4)) {
				pinNum = ed1DigitalPinMap[pinNum - 1];
			}
		#endif
		#ifdef ARDUINO_Mbits
			if ((0 <= pinNum) && (pinNum <= 20) && (pinNum != 17) && (pinNum != 18)) {
				pinNum = digitalPin[pinNum]; // map edge connector pin number to ESP32 pin number
			}
		#endif
		if (RESERVED(pinNum)) return;
	#elif defined(ARDUINO_SAM_DUE) || defined(ARDUINO_NRF52840_FEATHER)
		if (pinNum < 2) return;
	#elif defined(ARDUINO_SAM_ZERO) // M0
		if ((pinNum == 14) || (pinNum == 15) ||
			((18 <= pinNum) && (pinNum <= 23))) return;
	#elif defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS)
		if (0 == pinNum) {
			pinNum = PIN_DAC0;
		} else if ((1 <= pinNum) && (pinNum < DIGITAL_PINS)) {
			pinNum = digitalPin[pinNum];
		} else {
			return;
		}
	#elif defined(USE_DIGITAL_PIN_MAP)
		if ((0 <= pinNum) && (pinNum < DIGITAL_PINS)) {
			pinNum = digitalPin[pinNum];
		} else {
			return;
		}
	#endif
	int value = obj2int(args[1]);
	if (value < 0) value = 0;
	if (value > 1023) value = 1023;
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return;
	#if defined(ARDUINO_ARCH_SAMD) && defined(PIN_DAC0)
		#if defined(ADAFRUIT_GEMMA_M0)
			if (1 == pinNum) pinNum = PIN_DAC0; // pin 1 is DAC on Gemma M0
		#else
			if (0 == pinNum) pinNum = PIN_DAC0; // pin 0 is DAC on most SAMD boards
		#endif
		if (PIN_DAC0 == pinNum) {
			SET_MODE(pinNum, INPUT);
		} else {
			SET_MODE(pinNum, OUTPUT);
		}
	#else
		int modeChanged = (OUTPUT != currentMode[pinNum]);
		(void) (modeChanged); // reference var to suppress compiler warning

		SET_MODE(pinNum, OUTPUT);
		#if defined(ARDUINO_BBC_MICROBIT_V2) || defined(CALLIOPE_V3)
			if ((27 == pinNum) && modeChanged) setHighDrive(pinNum); // use high drive for speaker
		#endif
	#endif

	#if defined(ESP32)
	  #if !defined(ESP32_S3) && !defined(ESP32_C3) && !defined(COCUBE)
		if ((25 == pinNum) || (26 == pinNum)) { // ESP32 and ESP32-S2 DAC pins
			dacWrite(pinNum, (value >> 2)); // convert 10-bit to 8-bit value for ESP32 DAC
			return;
		}
	  #endif
		if (value == 0) {
			pinDetach(pinNum);
		} else {
			if (!pinAttached(pinNum)) analogAttach(pinNum);
			int esp32Channel = pinAttached(pinNum);
			if (esp32Channel) ledcWrite(esp32Channel, value);
		}
	#else
		#ifdef NRF52
			// On NRF52, wait until last PWM cycle is finished before writing a new value.
			// Prevents a tight loop writing audio samples from exceeding the PWM sample rate.
			NRF_PWM_Type* pwm = NRF_PWM0;
			if (pwm->EVENTS_SEQSTARTED[0]) {
				while (!pwm->EVENTS_PWMPERIODEND) /* wait */;
				pwm->EVENTS_PWMPERIODEND = 0;
			}
			value = (value >> 2); // On NRF52, use only the top 8-bits of the 10-bit value
		#endif

		analogWrite(pinNum, value); // sets the PWM duty cycle on a digital pin
	#endif
	if (OUTPUT == currentMode[pinNum]) { // using PWM, not DAC
		pwmRunning[pinNum] = true;
	}
}

OBJ primDigitalRead(int argCount, OBJ *args) {
	if (!isInt(args[0])) { fail(needsIntegerError); return int2obj(0); }
	int pinNum = obj2int(args[0]);
	#if defined(ADAFRUIT_ITSYBITSY_M0)
		if (pinNum > 25) return falseObj;
	#elif defined(ADAFRUIT_TRINKET_M0)
		if (pinNum > 4) return falseObj;
	#elif defined(ARDUINO_NRF52_PRIMO)
		if (22 == pinNum) return (LOW == digitalRead(USER1_BUTTON)) ? trueObj : falseObj;
		if (23 == pinNum) return falseObj;
	#elif defined(ARDUINO_SAM_DUE) || defined(ARDUINO_NRF52840_FEATHER)
		if (pinNum < 2) return falseObj;
	#elif defined(ARDUINO_SAM_ZERO) // M0
		if ((pinNum == 14) || (pinNum == 15) ||
			((18 <= pinNum) && (pinNum <= 23))) return falseObj;
	#elif defined(USE_DIGITAL_PIN_MAP)
		if ((0 <= pinNum) && (pinNum < DIGITAL_PINS)) {
			pinNum = digitalPin[pinNum];
		} else {
			return falseObj;
		}
	#elif defined(ARDUINO_CITILAB_ED1)
		if ((100 <= pinNum) && (pinNum <= 139)) {
			pinNum = pinNum - 100; // allows access to unmapped IO pins 0-39 as 100-139
		} else if ((1 <= pinNum) && (pinNum <= 4)) {
			pinNum = ed1DigitalPinMap[pinNum - 1];
		}
		if (pinNum == 2 || pinNum == 4 || pinNum == 13 ||
			pinNum == 14 || pinNum == 15 || pinNum == 27) {
			// Do not reset pin mode, it should remain INPUT_PULLUP as set in initPins.
			// These buttons are reversed, too.
			return (HIGH == digitalRead(pinNum)) ? falseObj : trueObj;
		}
		if (RESERVED(pinNum)) return falseObj;
	#elif defined(ARDUINO_ARCH_ESP32) || defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO) || defined(ARDUINO_ARCH_RP2040)
		if (RESERVED(pinNum)) return falseObj;
	#endif
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return falseObj;
	int mode = (argCount > 1) ? inputModeFor(args[1]) : INPUT;
	#if defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS) || defined(ARDUINO_NRF52840_CIRCUITPLAY)
		if (7 == pinNum) mode = INPUT_PULLUP; // slide switch
	#endif
	SET_MODE(pinNum, mode);
	return (HIGH == digitalRead(pinNum)) ? trueObj : falseObj;
}

void primDigitalWrite(OBJ *args) {
	if (!isInt(args[0])) { fail(needsIntegerError); return; }
	int pinNum = obj2int(args[0]);
	int flag = (trueObj == args[1]);
	primDigitalSet(pinNum, flag);
}

void primDigitalSet(int pinNum, int flag) {
	// This supports a compiler optimization. If the arguments of a digitalWrite
	// are compile-time constants, the compiler can generate a digitalSet or digitalClear
	// instruction, thus saving the cost of pushing the pin number and boolean.
	// (This can make a difference in time-sensitives applications like sound generation.)
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return;
	#if defined(ADAFRUIT_ITSYBITSY_M0)
		// Map pins 26 & 27 to the DotStar LED (internal pins 41 and 40)
		if (pinNum == 26) pinNum = 41; // DotStar data
		else if (pinNum == 27) pinNum = 40; // DotStar clock
		else if (pinNum > 27) return;
	#elif defined(ADAFRUIT_TRINKET_M0)
		// Map pins 5 & 6 to the DotStar LED (internal pins 7 and 8)
		if (pinNum == 5) pinNum = 7;
		else if (pinNum == 6) pinNum = 8;
		else if (pinNum > 6) return;
	#elif defined(ARDUINO_NRF52_PRIMO)
		if (22 == pinNum) return;
		if (23 == pinNum) { digitalWrite(BUZZER, (flag ? HIGH : LOW)); return; }
	#elif defined(USE_DIGITAL_PIN_MAP)
		if ((0 <= pinNum) && (pinNum < DIGITAL_PINS)) {
			pinNum = digitalPin[pinNum];
		} else {
			return;
		}
	#elif defined(ARDUINO_CITILAB_ED1)
		if ((100 <= pinNum) && (pinNum <= 139)) {
			pinNum = pinNum - 100; // allows access to unmapped IO pins 0-39 as 100-139
		} else if ((1 <= pinNum) && (pinNum <= 4)) {
			pinNum = ed1DigitalPinMap[pinNum - 1];
		}
		if (RESERVED(pinNum)) return;
	#elif defined(ARDUINO_ARCH_ESP32) || defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO) || defined(ARDUINO_ARCH_RP2040)
		if (RESERVED(pinNum)) return;
	#elif defined(ARDUINO_SAM_DUE) || defined(ARDUINO_NRF52840_FEATHER)
		if (pinNum < 2) return;
	#elif defined(ARDUINO_SAM_ZERO) // M0
		if ((pinNum == 14) || (pinNum == 15) ||
			((18 <= pinNum) && (pinNum <= 23))) return;
	#endif
	SET_MODE(pinNum, OUTPUT);

	#if defined(ARDUINO_BBC_MICROBIT_V2) || defined(CALLIOPE_V3)
		if (28 == pinNum) {
			stopPWM();
			setHighDrive(pinNum); // use high drive for microphone
		}
	#endif

	#if defined(ESP32)
		// stop PWM so we can do a normal digitalWrite
		if (pwmRunning[pinNum]) {
			pinDetach(pinNum);
			pwmRunning[pinNum] = false;
		}
	#endif

	if (pwmRunning[pinNum]) {
		analogWrite(pinNum, (flag ? 1023 : 0));
	} else {
		digitalWrite(pinNum, (flag ? HIGH : LOW));
	}
}

// User LED

void primSetUserLED(OBJ *args) {
	#if defined(HAS_LED_MATRIX)
		// Special case: Plot or unplot one LED in the LED matrix.
		OBJ coords[2] = { int2obj(3), int2obj(1) };
		if (trueObj == args[0]) {
			primMBPlot(2, coords);
		} else {
			primMBUnplot(2, coords);
		}
	#elif defined(ARDUINO_CITILAB_ED1) || defined(ARDUINO_M5Stack_Core_ESP32) || defined(ARDUINO_M5STACK_FIRE) || \
		defined(ARDUINO_M5STACK_Core2) || defined(TTGO_DISPLAY) || defined(M5_CARDPUTER) || \
		defined(FUTURE_LITE) || defined(COCUBE)
			tftSetHugePixel(3, 1, (trueObj == args[0]));
	#else
		if (PIN_LED < 0) return; // board does not have a user LED
		if (PIN_LED < TOTAL_PINS) {
			SET_MODE(PIN_LED, OUTPUT);
		} else {
			pinMode(PIN_LED, OUTPUT);
		}
		int output = (trueObj == args[0]) ? HIGH : LOW;
		#ifdef INVERT_USER_LED
			output = !output;
		#endif
		#if defined(M5STAMP) || defined(M5_ATOMS3LITE)
			int color = (output == HIGH) ? 255 : 0; // blue when on
			setAllNeoPixels(PIN_LED, 1, color);
		#else
			digitalWrite(PIN_LED, (PinStatus) output);
		#endif
	#endif
}

// User Buttons

OBJ primButtonA(OBJ *args) {
	#if defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS) || defined(ARDUINO_NRF52840_CIRCUITPLAY)
		// Momentarily set button pin low before reading (simulates a pull-down resistor)
		primDigitalSet(8, false); // use index in digitalPins array
	#endif
	#ifdef PIN_BUTTON_A
		#if defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO)
			SET_MODE(PIN_BUTTON_A, INPUT_PULLUP);
		#elif defined(ARDUINO_CITILAB_ED1)
			int value = touchRead(buttonsPins[buttonIndex]);

			if (value < CAP_THRESHOLD) {
				if (buttonReadings[buttonIndex] > 0) {
					buttonReadings[buttonIndex]--;
				}
				if ((value == 0) && (buttonReadings[buttonIndex] > CAP_THRESHOLD)) {
					buttonReadings[buttonIndex] = CAP_THRESHOLD;
				}
			} else {
				buttonReadings[buttonIndex] = CAP_THRESHOLD + 2; // try 3 times
			}
			buttonIndex = (buttonIndex + 1) % 6;
			return (buttonReadings[4] < CAP_THRESHOLD) ? trueObj : falseObj;
		#elif defined(HALOCODE)
			SET_MODE(PIN_BUTTON_A, INPUT);			
		#elif defined(ARDUINO_NRF52840_CLUE) || defined(ARDUINO_ARCH_ESP32) || \
			  defined(ESP8266) || defined(M5STAMP)
			SET_MODE(PIN_BUTTON_A, INPUT_PULLUP);
		#else
			SET_MODE(PIN_BUTTON_A, INPUT);
		#endif
		return (BUTTON_PRESSED == digitalRead(PIN_BUTTON_A)) ? trueObj : falseObj;
	#else
		return falseObj;
	#endif
}

OBJ primButtonB(OBJ *args) {
	#if defined(ARDUINO_SAMD_CIRCUITPLAYGROUND_EXPRESS) || defined(ARDUINO_NRF52840_CIRCUITPLAY)
		// Momentarily set button pin low before reading (simulates a pull-down resistor)
		primDigitalSet(9, false); // use index in digitalPins array
	#endif
	#ifdef PIN_BUTTON_B
		#if defined(ARDUINO_CITILAB_ED1)
			return (buttonReadings[3] < CAP_THRESHOLD) ? trueObj : falseObj;
		#elif defined(ARDUINO_NRF52840_CLUE)|| defined(FUTURE_LITE)
			SET_MODE(PIN_BUTTON_B, INPUT_PULLUP);
		#else
			SET_MODE(PIN_BUTTON_B, INPUT);
		#endif
		return (BUTTON_PRESSED == digitalRead(PIN_BUTTON_B)) ? trueObj : falseObj;
	#else
		return falseObj;
	#endif
}

// Random number generator seed

static void initRandomSeed() {
	// Initialize the random number generator with a random seed when started (if possible).

	#if defined(ESP8266)
		randomSeed(RANDOM_REG32);
	#elif defined(ARDUINO_ARCH_ESP32)
		randomSeed(esp_random());
	#elif defined(NRF51) || defined(NRF52)
		#define RNG_BASE 0x4000D000
		#define RNG_START (RNG_BASE)
		#define RNG_STOP (RNG_BASE + 4)
		#define RNG_VALRDY (RNG_BASE + 0x100)
		#define RNG_VALUE (RNG_BASE + 0x508)
		uint32 seed = 0;
		*((int *) RNG_START) = true; // start random number generation
		for (int i = 0; i < 4; i++) {
			while (!*((volatile int *) RNG_VALRDY)) /* wait */;
			seed = (seed << 8) | *((volatile int *) RNG_VALUE);
			*((volatile int *) RNG_VALRDY) = 0;
		}
		*((int *) RNG_STOP) = true; // end random number generation
		randomSeed(seed);
	#elif defined(__ZEPHYR__)
		unsigned long seed;
		sys_rand_get(&seed, sizeof(seed));
		randomSeed(seed);
	#else
		uint32 seed = 0;
		for (int i = 0; i < ANALOG_PINS; i++) {
			int p = analogPin[i];
			pinMode(p, INPUT);
			seed = (seed << 1) ^ analogRead(p);
		}
		randomSeed(seed);
	#endif
}

// Stop PWM

void stopPWM() {
	// Stop hardware PWM. Only implemented on nRF52 boards for now.
	// Unfortunately, the Arduino API doesn't include a way to stop PWM on a pin once it has
	// been started so we'd need to modify the Arduino library code or implement our own
	// version of analogWrite() to reset their internal PWM data structures. Instead, this
	// function simply turns off the PWM hardare on nRF52 boards.

	// Stop squareWave generation, too.
	stopRF();

	#if defined(NRF52)
		NRF_PWM0->TASKS_STOP = 1;
		NRF_PWM1->TASKS_STOP = 1;
		NRF_PWM2->TASKS_STOP = 1;
		NRF_PWM0->ENABLE = 0;
		NRF_PWM1->ENABLE = 0;
		NRF_PWM2->ENABLE = 0;
	#endif
}

// Servo and Tone

#if defined(NRF51) || defined(NRF52)

// NRF5 Servo State

#define MAX_SERVOS 8
#define UNUSED 255

static int servoIndex = 0;
static char servoPinHigh = false;
static char servoPin[MAX_SERVOS] = {UNUSED, UNUSED, UNUSED, UNUSED, UNUSED, UNUSED, UNUSED, UNUSED};
static unsigned short servoPulseWidth[MAX_SERVOS] = {1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500};

// NRF5 Tone State

static int tonePin = -1;
static unsigned short toneHalfPeriod = 1000;
static char tonePinState = 0;
static char servoToneTimerStarted = 0;

static void startServoToneTimer() {
	// enable timer interrupts
	NVIC_EnableIRQ(MB_TIMER_IRQn);

	// get current timer value
 	MB_TIMER->TASKS_CAPTURE[0] = true;
 	uint32_t wakeTime = MB_TIMER->CC[0];

	// set initial wake times a few (at least 2) usecs in the future to kick things off
	MB_TIMER->CC[2] = wakeTime + 5;
	MB_TIMER->CC[3] = wakeTime + 5;

	// enable interrrupts on CC[2] and CC[3]
	MB_TIMER->INTENSET = TIMER_INTENSET_COMPARE2_Msk | TIMER_INTENSET_COMPARE3_Msk;

	servoToneTimerStarted = true;
}

extern "C" void MB_TIMER_IRQHandler() {
	if (MB_TIMER->EVENTS_COMPARE[2]) { // tone waveform generator (CC[2])
		uint32_t wakeTime = MB_TIMER->CC[2];
		MB_TIMER->EVENTS_COMPARE[2] = 0; // clear interrupt
		if (tonePin >= 0) {
			tonePinState = !tonePinState;
			digitalWrite(tonePin, tonePinState);
			MB_TIMER->CC[2] = (wakeTime + toneHalfPeriod); // next wake time
		}
	}

	if (MB_TIMER->EVENTS_COMPARE[3]) { // servo waveform generator (CC[3])
		uint32_t wakeTime = MB_TIMER->CC[3] + 12;
		MB_TIMER->EVENTS_COMPARE[3] = 0; // clear interrupt

		if (servoPinHigh && (0 <= servoIndex) && (servoIndex < MAX_SERVOS)) {
			digitalWrite(servoPin[servoIndex], LOW); // end the current servo pulse
		}

		// find the next active servo
		servoIndex = (servoIndex + 1) % MAX_SERVOS;
		while ((servoIndex < MAX_SERVOS) && (UNUSED == servoPin[servoIndex])) {
			servoIndex++;
		}

		if (servoIndex < MAX_SERVOS) { // start servo pulse for servoIndex
			digitalWrite(servoPin[servoIndex], HIGH);
			servoPinHigh = true;
			MB_TIMER->CC[3] = (wakeTime + servoPulseWidth[servoIndex]);
		} else { // idle until next set of pulses
			servoIndex = -1;
			servoPinHigh = false;
			MB_TIMER->CC[3] = (wakeTime + 18000);
		}
	}
}

void stopServos() {
	for (int i = 0; i < MAX_SERVOS; i++) {
		servoPin[i] = UNUSED;
		servoPulseWidth[i] = 1500;
	}
	servoPinHigh = false;
	servoIndex = 0;
}

static void nrfDetachServo(int pin) {
	for (int i = 0; i < MAX_SERVOS; i++) {
		if (pin == servoPin[i]) {
			servoPulseWidth[i] = 1500;
			servoPin[i] = UNUSED;
		}
	}
}

static void setServo(int pin, int usecs) {
	if (!servoToneTimerStarted) startServoToneTimer();

	if (usecs <= 0) { // turn off servo
		nrfDetachServo(pin);
		return;
	}

	for (int i = 0; i < MAX_SERVOS; i++) {
		if (pin == servoPin[i]) { // update the pulse width for the given pin
			servoPulseWidth[i] = usecs;
			return;
		}
	}

	for (int i = 0; i < MAX_SERVOS; i++) {
		if (UNUSED == servoPin[i]) { // found unused servo entry
			servoPin[i] = pin;
			servoPulseWidth[i] = usecs;
			return;
		}
	}
}

#elif defined(ESP32)

static int attachServo(int pin) {
	// Note: Do not use channels 0-1 or 8-9; those use timer0, which is used by Tone.
	for (int i = 1; i < MAX_ESP32_CHANNELS; i++) {
		if ((0 == esp32Channels[i]) && ((i & 7) > 1)) { // free channel
			ledcSetup(i, 100, 10); // 100Hz, 10 bits
			ledcAttachPin(pin, i);
			esp32Channels[i] = pin;
			return i;
		}
	}
	return 0;
}

static void setServo(int pin, int usecs) {
	if (usecs <= 0) {
		pinDetach(pin);
	} else {
		int esp32Channel = pinAttached(pin);
		if (!esp32Channel) esp32Channel = attachServo(pin);
		if (esp32Channel > 0) {
			ledcWrite(esp32Channel, usecs * 1024 / 10000);
		}
	}
}

void stopServos() {
	for (int i = 1; i < MAX_ESP32_CHANNELS; i++) {
		int pin = esp32Channels[i];
		if (pin) pinDetach(pin);
	}
}

#elif ARDUINO_ARCH_MBED

#include <mbed.h>

#define MAX_SERVOS 8
#define UNUSED 255

static char servoPin[MAX_SERVOS] = {UNUSED, UNUSED, UNUSED, UNUSED, UNUSED, UNUSED, UNUSED, UNUSED};
static unsigned short servoPulseWidth[MAX_SERVOS] = {1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500};

mbed::Timeout servoTimeout; // calls servoTick when timeout expires
static int servoIndex = 0;
static char servoPinHigh = false;
static char servoToneTimerStarted = 0;

static void servoTick() {
	if (servoPinHigh && (0 <= servoIndex) && (servoIndex < MAX_SERVOS)) {
		digitalWrite(servoPin[servoIndex], LOW); // end the current servo pulse
	}

	// find the next active servo
	servoIndex = (servoIndex + 1) % MAX_SERVOS;
	while ((servoIndex < MAX_SERVOS) && (UNUSED == servoPin[servoIndex])) {
		servoIndex++;
	}

	if (servoIndex < MAX_SERVOS) { // start servo pulse for servoIndex
		digitalWrite(servoPin[servoIndex], HIGH);
		servoPinHigh = true;
		servoTimeout.attach(&servoTick, (std::chrono::microseconds) servoPulseWidth[servoIndex]);
	} else { // idle until next set of pulses
		servoIndex = -1;
		servoPinHigh = false;
		servoTimeout.attach(&servoTick, (std::chrono::microseconds) 18000);
	}
}

void stopServos() {
	for (int i = 0; i < MAX_SERVOS; i++) {
		servoPin[i] = UNUSED;
		servoPulseWidth[i] = 1500;
	}
	servoPinHigh = false;
	servoIndex = 0;
}

static void setServo(int pin, int usecs) {
	if (!servoToneTimerStarted) {
		// start servoTick callbacks
		servoIndex = -1;
		servoTimeout.attach(&servoTick, (std::chrono::microseconds) 100);
		servoToneTimerStarted = true;
	}

	if (usecs <= 0) { // turn off servo
		for (int i = 0; i < MAX_SERVOS; i++) {
			if (pin == servoPin[i]) {
				servoPulseWidth[i] = 1500;
				servoPin[i] = UNUSED;
			}
		}
		return;
	}

	for (int i = 0; i < MAX_SERVOS; i++) {
		if (pin == servoPin[i]) { // update the pulse width for the given pin
			servoPulseWidth[i] = usecs;
			return;
		}
	}

	for (int i = 0; i < MAX_SERVOS; i++) {
		if (UNUSED == servoPin[i]) { // found unused servo entry
			servoPin[i] = pin;
			servoPulseWidth[i] = usecs;
			return;
		}
	}
}

#elif defined(__ZEPHYR__)

static void setServo(int pin, int usecs) {}

void stopServos() {}

#else // use Arduino Servo library

#include <Servo.h>
Servo servo[TOTAL_PINS];

static void setServo(int pin, int usecs) {
	int servoIndex = pin;

	#if defined(MAKERPORT) || defined(MAKERPORT_V2) || defined(MAKERPORT_V3)
		// The MakerPort (SAM D21) can use only the first 12 servo channels.
		// Map pins 7-18 to those channels.
		// Makerport V1/V2 servo capable pins: 7-12, 14, 16-17
		// Makerport V3 servo capable pins: 7-12, 14-16
		servoIndex -= 7;
		if (servoIndex < 0) return;
	#endif

	if (usecs <= 0) {
		if (servo[servoIndex].attached()) servo[servoIndex].detach();
	} else {
		if (!servo[servoIndex].attached()) {
			// allow a wide range of pulse widths
			servo[servoIndex].attach(pin, 500, 2900); // On SAMD21, max must be <= 2911
		}
		servo[servoIndex].writeMicroseconds(usecs);
	}
}

void stopServos() {
	for (int pin = 0; pin < TOTAL_PINS; pin++) {
		if (servo[pin].attached()) servo[pin].detach();
	}
}

#endif // servos

// Tone Generation

#if defined(NRF51) || defined(NRF52)

static void setTone(int pin, int frequency) {
	tonePin = pin;
	toneHalfPeriod = 500000 / frequency;
	if (!servoToneTimerStarted) {
		startServoToneTimer();
	}
	MB_TIMER->TASKS_CAPTURE[2] = true;
	MB_TIMER->CC[2] = (MB_TIMER->CC[2] + toneHalfPeriod); // set next wakeup time
}

void stopTone() { tonePin = -1; }

#elif defined(ESP32)

int tonePin = -1;

static void initESP32Tone(int pin) {
	if ((pin == tonePin) || (pin < 0)) return;
	if (tonePin < 0) {
		int f = ledcSetup(0, 15000, 12); // do setup on first call
	} else {
		ledcWrite(0, 0); // stop current tone, if any
		ledcDetachPin(tonePin);
	}
	tonePin = pin;
}

static void setTone(int pin, int frequency) {
	if (pin != tonePin) stopTone();
	initESP32Tone(pin);
	if (tonePin >= 0) {
		ledcAttachPin(tonePin, 0);
		ledcWriteTone(0, frequency);
	}
}

static void initDAC(int pin, int sampleRate); // forward reference

void stopTone() {
	initDAC(255, 0); // disable buffered DAC output
	if (tonePin >= 0) {
		ledcWrite(0, 0);
		ledcDetachPin(tonePin);
	}
}

#elif defined(ARDUINO_SAM_DUE)

// the Due does not have Tone functions

static void setTone(int pin, int frequency) { }
void stopTone() { }

#else // use Arduino Tone functions

int tonePin = -1;

static void setTone(int pin, int frequency) {
	if (pin != tonePin) stopTone();
	tonePin = pin;
	if (frequency < 46) {
		// Lowest frequency on SAMD21 is 46 Hz
		stopTone();
		return;
	}
	tone(tonePin, frequency);
}

void stopTone() {
	if (tonePin >= 0) {
		#if defined(ARDUINO_SAMD_ZERO)
			// workaround for intermittent Tone library lockup when generating 38k IR Remote signal
			NVIC_DisableIRQ(TC5_IRQn);
			NVIC_ClearPendingIRQ(TC5_IRQn);
		#endif
		noTone(tonePin);
		SET_MODE(tonePin, INPUT);
	}
	tonePin = -1;
}

#endif // tone

// DAC (digital to analog converter) Support

#if defined(ESP32) && !defined(ESP32_S3) && !defined(ESP32_C3)

#include "driver/dac_common.h"

// DAC ring buffer. Size must be a power of 2 <= 256.
#define DAC_BUF_SIZE 128
#define DAC_BUF_MASK (DAC_BUF_SIZE - 1)
static uint8 ringBuf[DAC_BUF_SIZE];

static volatile uint8 readPtr = 0;
static volatile uint8 writePtr = 0;
static volatile uint8 lastValue = 0;
static volatile uint8 dacChannel = 255; // DAC not initialized

static hw_timer_t *timer = NULL;
static portMUX_TYPE timerMux = portMUX_INITIALIZER_UNLOCKED;

static void IRAM_ATTR onTimer() {
	int value;
	portENTER_CRITICAL_ISR(&timerMux);
		if (readPtr != writePtr) {
			value = ringBuf[readPtr++];
			readPtr &= DAC_BUF_MASK;
		} else {
			// if no data use last sample value to avoid a click
			value = lastValue;
		}
	portEXIT_CRITICAL_ISR(&timerMux);
	if (dacChannel <= 2) dac_output_voltage((dac_channel_t) dacChannel, value);
	lastValue = value;
}

static void initDAC(int pin, int sampleRate) {
	// Set the DAC pin and sample rate.

	#if defined(ARDUINO_CITILAB_ED1)
		// On ED1 board pins 2 and 4 are aliases for ESP32 pins 25 and 26
		if (2 == pin) pin = 25;
		if (4 == pin) pin = 26;
	#endif
	if ((25 == pin) || (26 == pin)) {
		pinMode(pin, ANALOG);
		dacChannel = (uint8_t) (pin - 25);
		dac_cw_generator_disable();
		dac_output_enable((dac_channel_t) dacChannel);
	} else { // disable DAC output if pin is not a DAC pin (i.e. pin 25 or 26)
		if (timer) timerStop(timer);
		dacChannel = 255;
		return;
	}

	if (sampleRate <= 0) sampleRate = 1;
	if (sampleRate > 48000) sampleRate = 48000; // ESP32 crashs at higher sample rates
	sampleRate = 1.020 * sampleRate; // fine tune (based on John's M5Stack Grey)

	if (!timer) { // initialize timer on first use
		timer = timerBegin(1, 2, true);
		timerAttachInterrupt(timer, &onTimer, true);
		timerAlarmWrite(timer, (40000000 / sampleRate), true);
		timerAlarmEnable(timer);
	} else {
		timerAlarmWrite(timer, (40000000 / sampleRate), true);
		timerStart(timer); // may have been stopped
	}
}

static inline int writeDAC(int sample) {
	// If there's room, add the given sample to the DAC ring buffer and return 1.
	// Otherwise return 0.

	if (dacChannel > 1) return 0; // DAC is not initialized
	if (((writePtr + 1) & DAC_BUF_MASK) == readPtr) return 0; // buffer is full

	if (sample < 0) sample = 0;
	if (sample > 255) sample = 255;
	portENTER_CRITICAL(&timerMux);
		ringBuf[writePtr++] = sample;
		writePtr &= DAC_BUF_MASK;
	portEXIT_CRITICAL(&timerMux);
	return 1;
}

#elif defined(ARDUINO_ARCH_RP2040) && defined(ARDUINO_ARCH_MBED)

#include "pinDefinitions.h"

mbed::PwmOut *dacPWM = NULL;

static void initDAC(int pin, int sampleRate) {
	if (dacPWM) { // delete old PWM instance
		delete dacPWM;
		dacPWM = NULL;
	}

	if ((pin < 0) || (pin >= TOTAL_PINS)) return; // pin out of range

	mbed::PwmOut *oldPWM = digitalPinToPwm(pin);
	if (oldPWM) delete oldPWM; // delete old PWM instance for pin, if any

	dacPWM = new mbed::PwmOut(digitalPinToPinName(pin));
	digitalPinToPwm(pin) = dacPWM;

	if (sampleRate < 500) sampleRate = 500;
	if (sampleRate > 125000) sampleRate = 125000;
	dacPWM->period_us(1000000 / sampleRate);
}

static int writeDAC(int sample) {
	if (sample < 0) sample = 0;
	if (sample > 255) sample = 255;
	if (dacPWM) dacPWM->write(sample / 255.0);
	return true;
}

#else

static void initDAC(int pin, int sampleRate) { }
static int writeDAC(int sample) { return 0; }

#endif

// Tone Primitives

#ifndef DEFAULT_TONE_PIN
	#define DEFAULT_TONE_PIN 0
#endif

OBJ primHasTone(int argCount, OBJ *args) {
	#if defined(ARDUINO_SAM_DUE)
		return falseObj;
	#else
		return trueObj;
	#endif
}

OBJ primPlayTone(int argCount, OBJ *args) {
	// playTone <pin> <freq>
	// If freq > 0, generate a 50% duty cycle square wave of the given frequency
	// on the given pin. If freq <= 0 stop generating the square wave.
	// Return true on success, false if primitive is not supported.

	OBJ pinArg = args[0];
	OBJ freqArg = args[1];
	if (!isInt(pinArg) || !isInt(freqArg)) return falseObj;
	int pin = obj2int(pinArg);
	#if defined(ARDUINO_CITILAB_ED1)
		if ((100 <= pin) && (pin <= 139)) {
			pin = pin - 100; // allows access to unmapped IO pins 0-39 as 100-139
		} else if ((1 <= pin) && (pin <= 4)) {
			pin = ed1DigitalPinMap[pin - 1];
		} else {
			pin = DEFAULT_TONE_PIN;
		}
	#else
		if ((pin < 0) || (pin >= DIGITAL_PINS)) pin = DEFAULT_TONE_PIN;
	#endif

	#if defined(USE_DIGITAL_PIN_MAP)
		pin = digitalPin[pin];
	#endif

	#if defined(ARDUINO_ARCH_ESP32) || defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO) || defined(ARDUINO_ARCH_RP2040)
		if (RESERVED(pin)) return falseObj;
	#elif defined(ARDUINO_SAM_DUE) || defined(ARDUINO_NRF52840_FEATHER)
		if (pin < 2) return falseObj;
	#endif

	SET_MODE(pin, OUTPUT);
	int frequency = obj2int(freqArg);
	if ((frequency < 16) || (frequency > 100000)) {
		stopTone();
		digitalWrite(pin, LOW);
	} else {
		setTone(pin, frequency);
	}
	return trueObj;
}

OBJ primHasServo(int argCount, OBJ *args) {
	#if defined(__ZEPHYR__)
		return falseObj;
	#else
		return trueObj;
	#endif
}

OBJ primSetServo(int argCount, OBJ *args) {
	// setServo <pin> <usecs>
	// If usecs > 0, generate a servo control signal with the given pulse width
	// on the given pin. If usecs <= 0 stop generating the servo signal.
	// Return true on success, false if primitive is not supported.

	OBJ pinArg = args[0];
	OBJ usecsArg = args[1];
	if (!isInt(pinArg) || !isInt(usecsArg)) return falseObj;
	int pin = obj2int(pinArg);
	if ((pin < 0) || (pin >= DIGITAL_PINS)) return falseObj;
	#if defined(USE_DIGITAL_PIN_MAP)
		pin = digitalPin[pin];
	#elif defined(ARDUINO_CITILAB_ED1)
		if ((100 <= pin) && (pin <= 139)) {
			pin = pin - 100; // allows access to unmapped IO pins 0-39 as 100-139
		} else if ((1 <= pin) && (pin <= 4)) {
			pin = ed1DigitalPinMap[pin - 1];
		}
	#endif
	#if defined(ARDUINO_ARCH_ESP32) || defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO) || defined(ARDUINO_ARCH_RP2040)
		if (RESERVED(pin)) return falseObj;
	#endif
	int usecs = obj2int(usecsArg);
	if (usecs > 5000) { usecs = 5000; } // maximum pulse width is 5000 usecs
	SET_MODE(pin, OUTPUT);
	setServo(pin, usecs);
	return trueObj;
}

OBJ primDACInit(int argCount, OBJ *args) {
	// Initialize the DAC pin and (optional) sample rate. If the pin is not a DAC pin (pins
	// 25 or 26 on an ESP32) then disable the DAC. The sample rate defaults to 11025.

	if (argCount < 1) return fail(notEnoughArguments);
	if (!isInt(args[0])) return fail(needsIntegerError);
	int pin = obj2int(args[0]);
	int sampleRate = ((argCount > 1) && isInt(args[1])) ? obj2int(args[1]) : 11025;

	initDAC(pin, sampleRate);
	return falseObj;
}

OBJ primDACWrite(int argCount, OBJ *args) {
	// Write sound samples to the DAC output buffer and return the number of samples written.
	// The argument may be an integer representing a single sample or a ByteArray of samples
	// plus an optional starting index withing that buffer.

	if (argCount < 1) return fail(notEnoughArguments);
	OBJ arg0 = args[0];

	int count = 0;
	if (isInt(arg0)) {
		count = writeDAC(obj2int(arg0));
	} else if (IS_TYPE(arg0, ByteArrayType)) {
		uint8 *buf = (uint8 *) &FIELD(arg0, 0);
		int bufSize = BYTES(arg0);
		int startIndex = ((argCount > 1) && isInt(args[1])) ? obj2int(args[1]) - 1 : 0;
		if (startIndex < 0) startIndex = 0;
		if (startIndex > bufSize) startIndex = bufSize;
		for (int i = startIndex; i < bufSize; i++) {
			if (!writeDAC(buf[i])) break;
			count++;
		}
	}
	return int2obj(count);
}

// Software serial (output only)

#if !defined(__not_in_flash_func)
  #define __not_in_flash_func(funcName) funcName
#endif

static OBJ __not_in_flash_func(primSoftwareSerialWriteByte)(int argCount, OBJ *args) {
	// Write a byte to the given pin at the given baudrate using software serial.

	if (argCount < 3) return fail(notEnoughArguments);
	int byte = evalInt(args[0]);
	int pinNum = evalInt(args[1]);
	int baud = evalInt(args[2]);
	int bitTime = 1000000 / baud;

	// adjust the bitTime for slower cpu's
	#if defined(ARDUINO_ARCH_SAMD)
		bitTime -= 3;
	#elif defined(NRF51) || defined(ESP8266) || defined(ARDUINO_SAM_DUE) || defined(RP2040_PHILHOWER)
		bitTime -= 2;
	#else
		bitTime -= 1;
	#endif

	pinNum = mapDigitalPinNum(pinNum);
	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return falseObj;
	SET_MODE(pinNum, OUTPUT);

	#if defined(ARDUINO_ARCH_SAMD)
		// Clear PINCFG register in case pin was previously used for hardware serial
		// Arduino pinMode() should do this but does not.
		#define PORT_BASE 0x41004400
		int ulPort = g_APinDescription[pinNum].ulPort;
		int ulPin = g_APinDescription[pinNum].ulPin;
		volatile uint8_t *cnf = (uint8_t *) (PORT_BASE + (0x80 * ulPort) + 0x40 + ulPin);
		*cnf = *cnf & 0xFFFFFFFE; // turn off the PMUXEN bit (bit 0)
	#endif

	#if defined(RP2040_PHILHOWER)
		// improves timing stability on RP2040
		digitalWrite(pinNum, HIGH);
		delayMicroseconds(bitTime);
	#endif

	// start bit
	digitalWrite(pinNum, LOW);
	delayMicroseconds(bitTime);

	// eight data bits, LSB first
	digitalWrite(pinNum, (byte & 1) ? HIGH : LOW);
	delayMicroseconds(bitTime);
	digitalWrite(pinNum, (byte & 2) ? HIGH : LOW);
	delayMicroseconds(bitTime);
	digitalWrite(pinNum, (byte & 4) ? HIGH : LOW);
	delayMicroseconds(bitTime);
	digitalWrite(pinNum, (byte & 8) ? HIGH : LOW);
	delayMicroseconds(bitTime);
	digitalWrite(pinNum, (byte & 16) ? HIGH : LOW);
	delayMicroseconds(bitTime);
	digitalWrite(pinNum, (byte & 32) ? HIGH : LOW);
	delayMicroseconds(bitTime);
	digitalWrite(pinNum, (byte & 64) ? HIGH : LOW);
	delayMicroseconds(bitTime);
	digitalWrite(pinNum, (byte & 128) ? HIGH : LOW);
	delayMicroseconds(bitTime);

	// stop bit
	digitalWrite(pinNum, HIGH);
	delayMicroseconds(bitTime);

	return falseObj;
}

// Experimental RF Square Wave Generator (nRF51 and nRF52 only)

#if (defined(NRF51) || defined(NRF52))

// Note: NimBLE uses PPI channels CH4, CH5 and optionally CH17, CH18, CH19
// so don't mess with those. (See ble_phy.c in NimBLE source code.)

static void stopRF() {
	NRF_PPI->CHENCLR = PPI_CHENSET_CH0_Msk;
	NRF_GPIOTE->CONFIG[0] = 0;
}

static int startRF(int pin, int frequency) {
	if (frequency < 1) {
		NRF_PPI->CHENCLR = PPI_CHENSET_CH0_Msk; // pause RF output
		return true;
	}
 	int count = ((80000000 / frequency) + 5) / 10; // rounded
 	if (count > 65535) count = 65535;

	int nRFPin = g_ADigitalPinMap[pin]; // get internal pin number

	// use GPIOTE to toggle pin 2 (micro:bit v2 P0)
	NRF_GPIOTE->CONFIG[0] =
		GPIOTE_CONFIG_MODE_Task << GPIOTE_CONFIG_MODE_Pos |
		GPIOTE_CONFIG_POLARITY_Toggle << GPIOTE_CONFIG_POLARITY_Pos |
		nRFPin << GPIOTE_CONFIG_PSEL_Pos |
		GPIOTE_CONFIG_OUTINIT_Low << GPIOTE_CONFIG_OUTINIT_Pos;

	// configure PPI
	NRF_PPI->CH[0].EEP = (uint32_t) &NRF_TIMER2->EVENTS_COMPARE[0];
	NRF_PPI->CH[0].TEP = (uint32_t) &NRF_GPIOTE->TASKS_OUT[0];
	NRF_PPI->CHENSET = PPI_CHENSET_CH0_Msk;

	// configure and start the timer
	NRF_TIMER2->TASKS_SHUTDOWN;
	NRF_TIMER2->PRESCALER = 0;
	NRF_TIMER2->CC[0] = count; // CC[0] determines the output frequency
	NRF_TIMER2->SHORTS = TIMER_SHORTS_COMPARE0_CLEAR_Msk;
	NRF_TIMER2->TASKS_START = 1;
	return true;
}

#elif defined(ESP32_ORIGINAL)

#include "driver/ledc.h"

#define SQUARE_WAVE_CHANNEL LEDC_CHANNEL_7
#define SQUARE_WAVE_TIMER LEDC_TIMER_3

int squareWavePin = -1;
ledc_timer_config_t squareWave_timer;
ledc_channel_config_t squareWave_channel;

static void stopRF() {
	// Stop RF output on current pin, if any,

	if (squareWavePin > 0) {
		ledc_timer_pause(LEDC_HIGH_SPEED_MODE, SQUARE_WAVE_TIMER);
		ledcDetachPin(squareWavePin);
		SET_MODE(squareWavePin, INPUT);
	}
}

static int startRF(int pin, int frequency) {
	if (frequency < 1) {
		if (squareWavePin >= 0) {
			ledc_timer_pause(LEDC_HIGH_SPEED_MODE, SQUARE_WAVE_TIMER);
		}
		return true;
	}
	if (frequency < 500) frequency = 500; // ESP32 crashes if freq < 500

	if (pin != squareWavePin) {
		stopRF();

		// setup timer
		squareWave_timer.speed_mode			= LEDC_HIGH_SPEED_MODE;
		squareWave_timer.duty_resolution	= LEDC_TIMER_1_BIT;
		squareWave_timer.timer_num			= SQUARE_WAVE_TIMER;
		squareWave_timer.freq_hz			= frequency;
		ledc_timer_config(&squareWave_timer);

		// setup channel
		squareWave_channel.channel		= SQUARE_WAVE_CHANNEL;
		squareWave_channel.duty			= 1;
		squareWave_channel.gpio_num		= pin;
		squareWave_channel.speed_mode	= LEDC_HIGH_SPEED_MODE;
		squareWave_channel.timer_sel	= SQUARE_WAVE_TIMER;
		ledc_channel_config(&squareWave_channel);
		squareWavePin = pin;
	}
	ledc_set_freq(LEDC_HIGH_SPEED_MODE, SQUARE_WAVE_TIMER, frequency);
	ledc_timer_resume(LEDC_HIGH_SPEED_MODE, SQUARE_WAVE_TIMER);
	return true;
}

#elif defined(RP2040_PHILHOWER)

#include <hardware/pwm.h>

int rfPin = -1;

static int startRF(int pin, int freq) {
	// Use PWM to generate a square wave at frequencies from 10 Hz to ~30 MHz.
	int analogScale = 2; // 1 bit

	if ((pin < 0) || (pin > 29) || (freq <= 0)) {
		stopRF();
		return true; // RF is supported
	}

	if (rfPin < 0) analogWrite(pin, 512); // initialze PWM for all pins before setting up RF
	rfPin = pin;

	// adjust analogScale to achieve lower periods (inspired by wiring_analog.cpp)
	while (((clock_get_hz(clk_sys) / (float) (analogScale * freq)) > 255.0) && (analogScale < 0xFFFF)) {
		analogScale *= 2;
		if (analogScale > 0xFFFF) analogScale = 0xFFFF;
	}

	pwm_config c = pwm_get_default_config();
	pwm_config_set_clkdiv(&c, (float) clock_get_hz(clk_sys) / (freq * analogScale));
	pwm_config_set_wrap(&c, analogScale - 1);
	pwm_init(pwm_gpio_to_slice_num(rfPin), &c, true);
    gpio_set_function(rfPin, GPIO_FUNC_PWM);
    pwm_set_gpio_level(rfPin, analogScale / 2);
    return true;
}

static void stopRF() {
	if (rfPin >= 0) {
		pwm_set_enabled(pwm_gpio_to_slice_num(rfPin), false);
    	gpio_set_function(rfPin, GPIO_FUNC_SIO);
		SET_MODE(rfPin, INPUT);
	}
	rfPin = -1;
}

#else

static int startRF(int pin, int frequency) { return false; }
static void stopRF() {}

#endif

static OBJ primSquareWave(int argCount, OBJ *args) {
	// If freq > 0, generate a 50% duty cycle square wave of the given frequency
	// on the given pin. If freq <= 0 stop generating the square wave.
	// Return true on success, false if primitive is not supported.

	OBJ freqArg = args[0];
	OBJ pinArg = (argCount > 1) ? args[1] : zeroObj; // default to pin 0
	if (!isInt(freqArg) || !isInt(pinArg)) return falseObj;

	int frequency = obj2int(freqArg);
	if (frequency <= 0) {
		startRF(0, 0); // pause RF, ignoring pin number
		return falseObj;
	}

	int pinNum = mapDigitalPinNum(obj2int(pinArg));

	#if defined(ARDUINO_ARCH_ESP32) || defined(ARDUINO_SAMD_ATMEL_SAMW25_XPRO) || defined(ARDUINO_ARCH_RP2040)
		if (RESERVED(pinNum)) return falseObj;
	#elif defined(ARDUINO_SAM_DUE) || defined(ARDUINO_NRF52840_FEATHER)
		if (pinNum < 2) return falseObj;
	#endif

	if ((pinNum < 0) || (pinNum >= TOTAL_PINS)) return falseObj;
	SET_MODE(pinNum, OUTPUT);

	int isSupported = startRF(pinNum, frequency);
	return isSupported ? trueObj : falseObj;
}

// forward to primitives that don't take argCount

static OBJ primSetUserLED2(int argCount, OBJ *args) { primSetUserLED(args); return falseObj; }
static OBJ primAnalogWrite2(int argCount, OBJ *args) { primAnalogWrite(args); return falseObj; }
static OBJ primDigitalWrite2(int argCount, OBJ *args) { primDigitalWrite(args); return falseObj; }

static PrimEntry entries[] = {
	{"hasTone", primHasTone},
	{"playTone", primPlayTone},
	{"hasServo", primHasServo},
	{"setServo", primSetServo},
	{"dacInit", primDACInit},
	{"dacWrite", primDACWrite},
	{"softWriteByte", primSoftwareSerialWriteByte},
    {"squareWave", primSquareWave},
	{"setUserLED", primSetUserLED2},
	{"analogRead", primAnalogRead},
	{"analogWrite", primAnalogWrite2},
	{"digitalRead", primDigitalRead},
	{"digitalWrite", primDigitalWrite2},
};

void addIOPrims() {
	addPrimitiveSet(IOPrims, "io", sizeof(entries) / sizeof(PrimEntry), entries);
}
