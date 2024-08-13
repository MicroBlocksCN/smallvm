/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// tftPrims.cpp - Microblocks TFT screen primitives and touch screen input
// Bernat Romagosa, November 2018

#include <Arduino.h>
#include <SPI.h>
#include <Wire.h>
#include <stdio.h>
#include <stdlib.h>

#include "mem.h"
#include "interp.h"

int useTFT = false;
static int touchEnabled = false;
static int deferUpdates = false;

// Redefine this macro for displays that must explicitly push offscreen changes to the display
#define UPDATE_DISPLAY() { taskSleep(-1); } // yield after potentially slow TFT operations

#if defined(ARDUINO_CITILAB_ED1) || defined(ARDUINO_M5Stack_Core_ESP32) || defined(ARDUINO_M5STACK_FIRE) || \
	defined(ARDUINO_M5Stick_C) || defined(ARDUINO_ESP8266_WEMOS_D1MINI) || \
	defined(ARDUINO_NRF52840_CLUE) || defined(ARDUINO_IOT_BUS) || defined(SCOUT_MAKES_AZUL) || \
	defined(TTGO_RP2040) || defined(TTGO_DISPLAY) || defined(ARDUINO_M5STACK_Core2) || \
	defined(GAMEPAD_DISPLAY) || defined(PICO_ED) || defined(OLED_128_64) || defined(FUTURE_LITE) || \
	defined(TFT_TOUCH_SHIELD) || defined(OLED_1106) || defined(MINGBAI) || defined(M5_CARDPUTER) || defined(M5_DIN_METER) || \
	defined(COCUBE)

	#ifndef COCUBE
	#define BLACK 0
	#endif // !COCUBE

	// Optional TFT_ESPI code was added by John to study performance differences
	#define USE_TFT_ESPI false // true to use TFT_eSPI library, false to use AdaFruit GFX library
	#if USE_TFT_ESPI
		#include <TFT_eSPI.h>

		TFT_eSPI tft = TFT_eSPI();

		void tftInit() {
			tft.init();
			tft.setRotation(0);
			tftClear();
			// Turn on backlight on IoT-Bus
			pinMode(33, OUTPUT);
			digitalWrite(33, HIGH);
			useTFT = true;
		}

	#elif defined(ARDUINO_CITILAB_ED1)
		#include "Adafruit_GFX.h"
		#include "Adafruit_ST7735.h"

		#define TFT_CS	5
		#define TFT_DC	9
		#define TFT_RST	10
		#define TFT_WIDTH 128
		#define TFT_HEIGHT 128
		Adafruit_ST7735 tft = Adafruit_ST7735(TFT_CS, TFT_DC, TFT_RST);

		void tftInit() {
			tft.initR(INITR_144GREENTAB);
			tft.setRotation(0);
			tftClear();
			useTFT = true;
		}

	#elif defined(ARDUINO_ESP8266_WEMOS_D1MINI)
		#include "Adafruit_GFX.h"
		#include "Adafruit_ST7735.h"

		#define TFT_CS	D4
		#define TFT_DC	D3
		#define TFT_RST	-1
		#define TFT_WIDTH 128
		#define TFT_HEIGHT 128
		Adafruit_ST7735 tft = Adafruit_ST7735(TFT_CS, TFT_DC, TFT_RST);

		void tftInit() {
			tft.initR(INITR_144GREENTAB);
			tft.setRotation(1);
			tftClear();
			useTFT = true;
		}

	#elif defined(ARDUINO_M5Stack_Core_ESP32) || defined(ARDUINO_M5STACK_FIRE)
		#include "Adafruit_GFX.h"
		#include "Adafruit_ILI9341.h"
		#define TFT_CS	14
		#define TFT_DC	27
		#define TFT_RST	33
		#define TFT_WIDTH 320
		#define TFT_HEIGHT 240
		#define WHITE 0xFFFF
 		// ArUco Marker, 4x4, 0-white, 1-black
        const uint16_t aruco_tags[100] = {
            0X4ACD, 0XF065, 0XCCD2, 0X66B9, 0XAB61, 0X8632, 0X61D1, 0X3B0D, 0X0125, 0X30A9, 0X066E, 0XEE58, 0XF148,
            0XD5F0, 0XDB4E, 0XD9C1, 0XB99A, 0X99FF, 0X93A1, 0X8950, 0X7974, 0X4FD4, 0X332A, 0X227D, 0X01B8, 0X6B8E,
            0X531B, 0X5AAB, 0XDEDC, 0XCB90, 0XBBEA, 0XA84D, 0X6130, 0X0F34, 0XF751, 0XF6D6, 0XE78A, 0XFB00, 0XF209,
            0XE3A5, 0XE8E7, 0XD5D7, 0XCD73, 0XC74D, 0XDB17, 0XD114, 0XD2C0, 0XB49B, 0XAFD1, 0XAFEC, 0XAE6B, 0XAA97,
            0XA2BE, 0XA068, 0X97FE, 0X9798, 0XEDB,  0X9E16, 0X94ED, 0X901A, 0X9820, 0X81E4, 0X7F5F, 0X7CBB, 0X745D,
            0X6C85, 0X7B93, 0X7AD5, 0X7A63, 0X6376, 0X605E, 0X4483, 0X43FB, 0X49A4, 0X4037, 0X4854, 0X35E0, 0X369D,
            0X26A7, 0X2C2A, 0X3367, 0X385F, 0X3AC8, 0X16A2, 0X06DA, 0X0444, 0X11D5, 0X08B2, 0XCA8A, 0X7552, 0X89E8,
            0XF530, 0XF9B4, 0XD23E, 0XB627, 0XBC0B, 0XB0C9, 0XB02C, 0X961B, 0X8F38};
		const uint64_t april_tags[100] = {
            0x0004064a19651ff1, 0x0004064a53f425b6, 0x0004064a8e832b7b, 0x0004064ac9123140, 0x0004064b03a13705,
            0x0004064b3e303cca, 0x0004064b78bf428f, 0x0004064bb34e4854, 0x0004064beddd4e19, 0x0004064c286c53de,
            0x0004064c62fb59a3, 0x0004064c9d8a5f68, 0x0004064d12a86af2, 0x0004064d4d3770b7, 0x0004064dc2557c41,
            0x0004064dfce48206, 0x0004064e377387cb, 0x0004064e72028d90, 0x0004064eac919355, 0x0004064f21af9edf,
            0x0004064fd15cb02e, 0x000406500bebb5f3, 0x00040650467abbb8, 0x00040650bb98c742, 0x00040650f627cd07,
            0x000406516b45d891, 0x00040651a5d4de56, 0x000406521af2e9e0, 0x000406525581efa5, 0x00040653052f00f4,
            0x000406533fbe06b9, 0x000406537a4d0c7e, 0x00040653ef6b1808, 0x0004065429fa1dcd, 0x0004065464892392,
            0x000406549f182957, 0x00040654d9a72f1c, 0x00040655143634e1, 0x000406554ec53aa6, 0x000406558954406b,
            0x00040655c3e34630, 0x00040655fe724bf5, 0x000406567390577f, 0x00040656ae1f5d44, 0x00040657233d68ce,
            0x00040657985b7458, 0x00040657d2ea7a1d, 0x00040658480885a7, 0x00040658bd269131, 0x00040659e1f1ae0a,
            0x0004065a919ebf59, 0x0004065bb669dc32, 0x0004065bf0f8e1f7, 0x0004065cdb34f90b, 0x0004065d15c3fed0,
            0x0004065d50530495, 0x0004065e3a8f1ba9, 0x0004065eea3c2cf8, 0x0004066049964f96, 0x000406608425555b,
            0x00040660beb45b20, 0x0004066133d266aa, 0x00040661e37f77f9, 0x000406621e0e7dbe, 0x00040662932c8948,
            0x00040662cdbb8f0d, 0x00040663084a94d2, 0x0004066342d99a97, 0x000406637d68a05c, 0x00040663f286abe6,
            0x0004066467a4b770, 0x00040664a233bd35, 0x00040664dcc2c2fa, 0x000406651751c8bf, 0x0004066551e0ce84,
            0x00040666b13af122, 0x00040666ebc9f6e7, 0x0004066760e80271, 0x00040668109513c0, 0x000406684b241985,
            0x00040668fad12ad4, 0x000406696fef365e, 0x00040669aa7e3c23, 0x00040669e50d41e8, 0x0004066bb9857010,
            0x0004066bf41475d5, 0x0004066c6932815f, 0x0004066ca3c18724, 0x0004066d536e9873, 0x0004066dc88ca3fd,
            0x0004066e031ba9c2, 0x0004066eb2c8bb11, 0x000406704cb1e374, 0x00040670c1cfeefe, 0x00040670fc5ef4c3,
            0x0004067136edfa88, 0x00040671ac0c0612, 0x00040673bb1339ff, 0x000406746ac04b4e, 0x00040676b4568500};
        const int april_bit_x[52] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 3, 4, 5, 4, 9, 9, 9, 9, 9, 9, 9, 9, 9, 6, 6, 6, 5,
                               9, 8, 7, 6, 5, 4, 3, 2, 1, 6, 5, 4, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3, 4};
        const int april_bit_y[52] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3, 4, 0, 1, 2, 3, 4, 5, 6, 7, 8, 3, 4, 5, 4,
                               9, 9, 9, 9, 9, 9, 9, 9, 9, 6, 6, 6, 5, 9, 8, 7, 6, 5, 4, 3, 2, 1, 6, 5, 4, 5};

		Adafruit_ILI9341 tft = Adafruit_ILI9341(TFT_CS, TFT_DC, TFT_RST);
		void tftInit() {
			// test TFT_RST to see if we need to invert the display
			// (from https://github.com/m5stack/M5Stack/blob/master/src/utility/In_eSPI.cpp)
			pinMode(TFT_RST, INPUT_PULLDOWN);
			delay(1);
			bool invertFlag = digitalRead(TFT_RST);
			pinMode(TFT_RST, OUTPUT);

			tft.begin(40000000); // Run SPI at 80MHz/2
			tft.setRotation(1);
			tft.invertDisplay(invertFlag);

			uint8_t m = 0x08 | 0x04; // RGB pixel order, refresh LCD right to left
			tft.sendCommand(ILI9341_MADCTL, &m, 1);
			tftClear();
			// Turn on backlight:
			pinMode(32, OUTPUT);
			digitalWrite(32, HIGH);
			pinMode(12, OUTPUT); // fix xingjixiaofang  buzz
			digitalWrite(12, HIGH);
			useTFT = true;
		}
	#elif defined(ARDUINO_M5STACK_CORES3)
		#include "Adafruit_GFX.h"
		#include "Adafruit_ILI9341.h" //todo
		#define TFT_CS	14
		#define TFT_DC	27
		#define TFT_RST	33
		#define TFT_WIDTH 320
		#define TFT_HEIGHT 240

	#elif defined(M5_CARDPUTER)
		#include "Adafruit_GFX.h"	
		#include "Adafruit_ST7789.h"
		#define TFT_CS		37
		#define TFT_DC		34
		#define TFT_RST	33	
		#define TFT_MOSI 35
		#define TFT_SCLK 36
		#define TFT_BL 38
		#define TFT_WIDTH	240
		#define TFT_HEIGHT	135
		Adafruit_ST7789 tft = Adafruit_ST7789(TFT_CS, TFT_DC, TFT_MOSI, TFT_SCLK, TFT_RST);
		
		void tftInit() {
			tft.init(TFT_HEIGHT, TFT_WIDTH);
			// tft.setSPISpeed(40000000);
			tft.setRotation(3);
			// tft.invertDisplay(true); 
			// Turn on backlight
			pinMode(TFT_BL, OUTPUT);
			digitalWrite(TFT_BL, HIGH);
			tftClear();
			useTFT = true;
		}
	#elif defined(M5_DIN_METER)
		#include "Adafruit_GFX.h"	
		#include "Adafruit_ST7789.h"
		#define TFT_CS		7
		#define TFT_DC		4
		#define TFT_RST	8	
		#define TFT_MOSI 5
		#define TFT_SCLK 6
		#define TFT_BL 9
		#define TFT_WIDTH	240
		#define TFT_HEIGHT	135
		Adafruit_ST7789 tft = Adafruit_ST7789(TFT_CS, TFT_DC, TFT_MOSI, TFT_SCLK, TFT_RST);
		
		void tftInit() {
			tft.init(TFT_HEIGHT, TFT_WIDTH);
			// tft.setSPISpeed(40000000);
			tft.setRotation(1);
			// tft.invertDisplay(true); 
			// Turn on backlight
			pinMode(TFT_BL, OUTPUT);
			digitalWrite(TFT_BL, HIGH);
			tftClear();
			useTFT = true;
		}
	#elif defined(ARDUINO_M5Stick_C2)
		#include "Adafruit_GFX.h"
		#include "Adafruit_ST7789.h"

		#define TFT_MOSI 15
		#define TFT_SCLK 13
		#define TFT_CS		5
		#define TFT_DC		14
		#define TFT_RST		12
		#define TFT_BL 27

		#define TFT_WIDTH	240
		#define TFT_HEIGHT	135
		
		Adafruit_ST7789 tft = Adafruit_ST7789(TFT_CS, TFT_DC, TFT_MOSI, TFT_SCLK, TFT_RST);
		
		void tftInit() {
			//hold pin 4 set to high to power on
			pinMode(4, OUTPUT);
			digitalWrite(4, HIGH);
			tft.init(TFT_HEIGHT, TFT_WIDTH);
			tft.setRotation(3);
			pinMode(TFT_BL, OUTPUT);
			digitalWrite(TFT_BL, HIGH);
			tftClear();
			useTFT = true;
		}



	#elif defined(ARDUINO_M5Stick_C)
		// Preliminary: this is not yet working...
		#include "Adafruit_GFX.h"

		#define TFT_CS		5
		#define TFT_DC		23
		#define TFT_RST		18

		#ifdef ARDUINO_M5Stick_Plus
			#include "Adafruit_ST7789.h"
			#define TFT_WIDTH	240
			#define TFT_HEIGHT	135
		#else
			#include "Adafruit_ST7735.h"
			#define TFT_WIDTH	160
			#define TFT_HEIGHT	80
		#endif

		#ifdef ARDUINO_M5Stick_Plus
			Adafruit_ST7789 tft = Adafruit_ST7789(TFT_CS, TFT_DC, TFT_RST);
		#else
			// make a subclass so we can adjust the x/y offsets
			class M5StickLCD : public Adafruit_ST7735 {
			public:
				M5StickLCD(int8_t cs, int8_t dc, int8_t rst) : Adafruit_ST7735(cs, dc, rst) {}
				void setOffsets(int colOffset, int rowOffset) {
					_xstart = _colstart = colOffset;
					_ystart = _rowstart = rowOffset;
				}
			};
			M5StickLCD tft = M5StickLCD(TFT_CS, TFT_DC, TFT_RST);
		#endif

		int readAXP(int reg) {
			Wire1.beginTransmission(0x34);
			Wire1.write(reg);
			Wire1.endTransmission();
			Wire1.requestFrom(0x34, 1);
			return Wire1.available() ? Wire1.read() : 0;
		}

		void writeAXP(int reg, int value) {
			Wire1.beginTransmission(0x34);
			Wire1.write(reg);
			Wire1.write(value);
			Wire1.endTransmission();
		}

		void tftInit() {
			#ifdef ARDUINO_M5Stick_Plus
				tft.init(TFT_HEIGHT, TFT_WIDTH);
 				tft.setRotation(3);
			#else
				tft.initR(INITR_MINI160x80);
				tft.setOffsets(26, 1);
				tft.setRotation(1);
			#endif
			tft.invertDisplay(true); // display must be inverted to give correct colors...
			tftClear();

			Wire1.begin(21, 22);
			Wire1.setClock(400000);

			// turn on LCD power pins (LD02 and LD03) = 0x0C
			// and for C+, turn on Ext (0x40) for the buzzer and DCDC1 (0x01) since M5Stack's init code does that
			int n = readAXP(0x12);
			writeAXP(0x12, n | 0x4D);

			int brightness = 12; // useful range: 7-12 (12 is max)
			n = readAXP(0x28);
			writeAXP(0x28, (brightness << 4) | (n & 0x0f)); // set brightness

			useTFT = true;
		}

	#elif defined(ARDUINO_M5STACK_Core2)
		// Preliminary: this is not yet working...
		#include "Adafruit_GFX.h"
		#include "Adafruit_ILI9341.h"
		#define TFT_CS	5
		#define TFT_DC	15
		#define TFT_WIDTH 320
		#define TFT_HEIGHT 240
		Adafruit_ILI9341 tft = Adafruit_ILI9341(TFT_CS, TFT_DC);

		int readAXP(int reg) {
			Wire1.beginTransmission(0x34);
			Wire1.write(reg);
			Wire1.endTransmission();
			Wire1.requestFrom(0x34, 1);
			return Wire1.available() ? Wire1.read() : 0;
		}

		void writeAXP(int reg, int value) {
			Wire1.beginTransmission(0x34);
			Wire1.write(reg);
			Wire1.write(value);
			Wire1.endTransmission();
		}

		void AXP192_SetDCVoltage(uint8_t number, uint16_t voltage) {
			uint8_t addr;
			if (number > 2) return;
			voltage = (voltage < 700) ? 0 : (voltage - 700) / 25;
			switch (number) {
			case 0:
				addr = 0x26;
				break;
			case 1:
				addr = 0x25;
				break;
			case 2:
				addr = 0x27;
				break;
			}
			writeAXP(addr, (readAXP(addr) & 0x80) | (voltage & 0x7F));
		}

		void AXP192_SetLDOVoltage(uint8_t number, uint16_t voltage) {
			voltage = (voltage > 3300) ? 15 : (voltage / 100) - 18;
			if (2 == number) writeAXP(0x28, (readAXP(0x28) & 0x0F) | (voltage << 4));
			if (3 == number) writeAXP(0x28, (readAXP(0x28) & 0xF0) | voltage);
		}

		void AXP192_SetLDOEnable(uint8_t number, bool state) {
			uint8_t mark = 0x01;
			if ((number < 2) || (number > 3)) return;

			mark <<= number;
			if (state) {
				writeAXP(0x12, (readAXP(0x12) | mark));
			} else {
				writeAXP(0x12, (readAXP(0x12) & (~mark)));
			}
		}

		void AXP192_SetDCDC3(bool state) {
			uint8_t buf = readAXP(0x12);
			if (state == true) {
				buf = (1 << 1) | buf;
			} else {
				buf = ~(1 << 1) & buf;
			}
			writeAXP(0x12, buf);
		}

		void AXP192_SetLCDRSet(bool state) {
			uint8_t reg_addr = 0x96;
			uint8_t gpio_bit = 0x02;
			uint8_t data = readAXP(reg_addr);

			if (state) {
				data |= gpio_bit;
			} else {
				data &= ~gpio_bit;
			}
			writeAXP(reg_addr, data);
		}

		void AXP192_SetLed(uint8_t state) {
			uint8_t reg_addr = 0x94;
			uint8_t data = readAXP(reg_addr);

			if (state) {
				data = data & 0xFD;
			} else {
				data |= 0x02;
			}
			writeAXP(reg_addr, data);
		}

		void AXP192_SetSpkEnable(uint8_t state) {
			// Set true to enable speaker

			uint8_t reg_addr = 0x94;
			uint8_t gpio_bit = 0x04;
			uint8_t data;
			data = readAXP(reg_addr);

			if (state) {
				data |= gpio_bit;
			} else {
				data &= ~gpio_bit;
			}
			writeAXP(reg_addr, data);
		}

		void AXP192_SetCHGCurrent(uint8_t state) {
			uint8_t data = readAXP(0x33);
			data &= 0xf0;
			data = data | ( state & 0x0f );
			writeAXP(0x33, data);
		}

		void AXP192_SetBusPowerMode(uint8_t state) {
			// Select source for BUS_5V
			// 0 : powered by USB or battery; use internal boost
			// 1 : powered externally

			uint8_t data;
			if (state == 0) {
				// Set GPIO to 3.3V (LDO OUTPUT mode)
				data = readAXP(0x91);
				writeAXP(0x91, (data & 0x0F) | 0xF0);
				// Set GPIO0 to LDO OUTPUT, pullup N_VBUSEN to disable VBUS supply from BUS_5V
				data = readAXP(0x90);
				writeAXP(0x90, (data & 0xF8) | 0x02);
				// Set EXTEN to enable 5v boost
				data = readAXP(0x10);
				writeAXP(0x10, data | 0x04);
			} else {
				// Set EXTEN to disable 5v boost
				data = readAXP(0x10);
				writeAXP(0x10, data & ~0x04);
				// Set GPIO0 to float, using enternal pulldown resistor to enable VBUS supply from BUS_5V
				data = readAXP(0x90);
				writeAXP(0x90, (data & 0xF8) | 0x07);
			}
		}


		void AXP192_begin() {
			// derived from AXP192.cpp from https://github.com/m5stack/M5Core2
			Wire1.begin(21, 22);
			Wire1.setClock(400000);

			writeAXP(0x30, (readAXP(0x30) & 0x04) | 0x02); // turn vbus limit off
			writeAXP(0x92, readAXP(0x92) & 0xf8); // set gpio1 to output
			writeAXP(0x93, readAXP(0x93) & 0xf8); // set gpio2 to output
			writeAXP(0x35, (readAXP(0x35) & 0x1c) | 0xa2); // enable rtc battery charging
			AXP192_SetDCVoltage(0, 3350); // set esp32 power voltage to 3.35v
			AXP192_SetDCVoltage(2, 2800); // set backlight voltage was set to 2.8v
			AXP192_SetLDOVoltage(2, 3300); // set peripheral voltage (LCD_logic, SD card) voltage to 2.0v
			AXP192_SetLDOVoltage(3, 2000); // set vibrator motor voltage to 2.0v
			AXP192_SetLDOEnable(2, true);
			AXP192_SetDCDC3(true); // LCD backlight
			AXP192_SetLed(false);
			AXP192_SetSpkEnable(true);

			AXP192_SetCHGCurrent(0); // charge current: 100mA
			writeAXP(0x95, (readAXP(0x95) & 0x72) | 0x84); // GPIO4

			writeAXP(0x36, 0x4C); // ???
			writeAXP(0x82,0xff); // ???

			AXP192_SetLCDRSet(0);
			delay(100);
			AXP192_SetLCDRSet(1);
			delay(100);

			// axp: check v-bus status
			if (readAXP(0x00) & 0x08) {
				writeAXP(0x30, readAXP(0x30) | 0x80);
				// if has v-bus power, disable M-Bus 5V output to input
				AXP192_SetBusPowerMode(1);
			} else {
				// otherwise, enable M-Bus 5V output
				AXP192_SetBusPowerMode(0);
			}
		}

		void tftInit() {
			AXP192_begin();

			tft.begin(40000000); // Run SPI at 80MHz/2
			tft.setRotation(1);
			tft.invertDisplay(true);
			uint8_t m = 0x08 | 0x04; // RGB pixel order, refresh LCD right to left
			tft.sendCommand(ILI9341_MADCTL, &m, 1);

			tftClear();
			useTFT = true;
		}
		// touch screen
		#define HAS_TFT_TOUCH
		#define TOUCH_CS_PIN 39

		void touchInit() {
			pinMode(TOUCH_CS_PIN, INPUT);	
			Wire1.begin(21, 22);
			Wire1.beginTransmission(0x38);
			Wire1.write(0xA4);
			Wire1.write(0);
			Wire1.endTransmission();

			Wire1.beginTransmission(0x38);
			Wire1.write(0x88);
			Wire1.write(13);
			Wire1.endTransmission();
			touchEnabled = true;
		}
		bool ispressed(){
			return (digitalRead(TOUCH_CS_PIN) == LOW);
		}

		static uint8 touchData[11];
		static int readFT6336Data(int index){
			if (ispressed()){
				Wire1.beginTransmission(0x38);
				Wire1.write(0x02);
				Wire1.endTransmission();
				// uint8 touchData[11];
				int count = sizeof(touchData);
				Wire1.requestFrom(0x38, count);
				for (int i = 0; i < count; i++) {
					touchData[i] = Wire1.available() ? Wire1.read() : 0;
				}
				int val = -1;
				if(touchData[0]){
					if (1 == index) val = ((touchData[1] << 8) | touchData[2]) & 0x0fff;
					if (2 == index) val = ((touchData[3] << 8) | touchData[4]) & 0x0fff;
					if (3 == index) val = touchData[0];
				}
				return val;
			} else{
				touchData[0] = 0;
				return 0;
			}
		}


		
	#elif defined(ARDUINO_NRF52840_CLUE)
		#include "Adafruit_GFX.h"
		#include "Adafruit_ST7789.h"

		#define TFT_CS		31
		#define TFT_DC		32
		#define TFT_RST		33
		#define TFT_WIDTH	240
		#define TFT_HEIGHT	240
		Adafruit_ST7789 tft = Adafruit_ST7789(&SPI1, TFT_CS, TFT_DC, TFT_RST);

		void tftInit() {
			tft.init(240, 240);
			tft.setRotation(1);
			tft.fillScreen(0);
			uint8_t rtna = 0x01; // Screen refresh rate control (datasheet 9.2.18, FRCTRL2)
			tft.sendCommand(0xC6, &rtna, 1);

			// fix for display gamma glitch on some Clue boards:
			uint8_t gamma = 2;
			tft.sendCommand(0x26, &gamma, 1);

			// Turn on backlight
			pinMode(34, OUTPUT);
			digitalWrite(34, HIGH);

			useTFT = true;
		}

	#elif defined(ARDUINO_IOT_BUS)
		#include "Adafruit_GFX.h"
		#include "Adafruit_ILI9341.h"
		#include <XPT2046_Touchscreen.h>
		#include <SPI.h>

		#define HAS_TFT_TOUCH
		#define TOUCH_CS_PIN 16
		XPT2046_Touchscreen ts(TOUCH_CS_PIN);

		#define X_MIN 256
		#define X_MAX 3632
		#define Y_MIN 274
		#define Y_MAX 3579

		#define TFT_CS	5
		#define TFT_DC	27

		#define TFT_WIDTH 320
		#define TFT_HEIGHT 240
		Adafruit_ILI9341 tft = Adafruit_ILI9341(TFT_CS, TFT_DC);

		void tftInit() {
			tft.begin();
			tft.setRotation(1);
//			tft._freq = 80000000; // this requires moving _freq to public in AdaFruit_SITFT.h
			tftClear();
			// Turn on backlight on IoT-Bus
			pinMode(33, OUTPUT);
			digitalWrite(33, HIGH);

			useTFT = true;
		}

		void touchInit() {
			ts.begin();
			ts.setCalibration(X_MIN, X_MAX, Y_MIN, Y_MAX);
			ts.setRotation(1);
			touchEnabled = true;
		}

	#elif defined(OLED_1106)
		// #undef BLACK // defined in SSD1306 header
		#include "Adafruit_GFX.h"
		#include "Adafruit_SH110X.h"

		#define TFT_WIDTH 128
		#define TFT_HEIGHT 64
		#define IS_MONOCHROME true

		Adafruit_SH1106G tft = Adafruit_SH1106G(TFT_WIDTH, TFT_HEIGHT,&Wire, -1);

		#undef UPDATE_DISPLAY
		#define UPDATE_DISPLAY() { if (!deferUpdates) { tft.display(); taskSleep(10); }}

		void tftInit() {
			tft.begin(0x3C,true);
			useTFT = true;
			tftClear();
		}
	#elif defined(SCOUT_MAKES_AZUL)
		#undef BLACK // defined in SSD1306 header
		#include "Adafruit_GFX.h"
		#include "Adafruit_SSD1306.h"

		#define TFT_WIDTH 128
		#define TFT_HEIGHT 32
		#define IS_MONOCHROME true

		Adafruit_SSD1306 tft = Adafruit_SSD1306(TFT_WIDTH, TFT_HEIGHT);

		#undef UPDATE_DISPLAY
		#define UPDATE_DISPLAY() { if (!deferUpdates) { tft.display(); taskSleep(-1); }}

		void tftInit() {
			tft.begin(SSD1306_SWITCHCAPVCC, 0x3C);
			useTFT = true;
			tftClear();
		}

	#elif defined(OLED_128_64)
		#undef BLACK // defined in SSD1306 header
		#include "Adafruit_GFX.h"
		#include "Adafruit_SSD1306.h"

		#define TFT_ADDR 0x3C
		#define TFT_WIDTH 128
		#define TFT_HEIGHT 64
		#define IS_MONOCHROME true

		Adafruit_SSD1306 tft = Adafruit_SSD1306(TFT_WIDTH, TFT_HEIGHT, &Wire, -1, 400000, 400000);

		void tftInit() {
			delay(5); // need 2 msecs minimum for micro:bit PicoBricks board power up I2C pullups
			if (!hasI2CPullups()) return; // no OLED connected and no I2C pullups
			int response = readI2CReg(TFT_ADDR, 0); // test if OLED responds at TFT_ADDR
			if (response < 0) return; // no OLED display detected

			tft.begin(SSD1306_SWITCHCAPVCC, TFT_ADDR);
			// set to max OLED brightness
			writeI2CReg(TFT_ADDR, 0x80, 0x81);
			writeI2CReg(TFT_ADDR, 0x80, 0xFF);
			useTFT = true;
			tftClear();
		}

		static void i2cWriteBytes(uint8 *bytes, int byteCount) {
			Wire.beginTransmission(TFT_ADDR);
			for (int i = 0; i < byteCount; i++) Wire.write(bytes[i]);
			Wire.endTransmission(true);
		}

		static void oledUpdate() {
			// Send the entire OLED buffer to the display via i2c. Takes about 30 msecs.
			// Periodically update the LED display to avoid flicker.
			uint8 oneLine[33];
			uint8 setupCmds[] = {
				0x20, 0,		// Horizontal mode
				0x22, 0, 7,		// Page start and end address
				0x21, 0, 0x7F	// Column start and end address
			};
			i2cWriteBytes(setupCmds, sizeof(setupCmds));
			oneLine[0] = 0x40;
			uint8 *displayBuffer = tft.getBuffer();
			uint8 *src = displayBuffer;
			for (int i = 0; i <= 1024; i++) {
				if ((i % 16) == 0) {
					captureIncomingBytes();
				}
				if ((i % 64) == 0) {
					// do time-sensitive background tasks
					updateMicrobitDisplay();
				}
				int col = i % 32;
				if ((col == 0) && (i != 0)) {
					i2cWriteBytes(oneLine, sizeof(oneLine));
					captureIncomingBytes();
				}
				oneLine[col + 1] = *src++;
			}
		}

		#undef UPDATE_DISPLAY
		#define UPDATE_DISPLAY() { if (!deferUpdates) { oledUpdate(); taskSleep(-1); }}
	
	#elif defined(MINGBAI)
		#include "Adafruit_GFX.h"
		#include "Adafruit_ST7789.h"

		#define TFT_MOSI 23
		#define TFT_SCLK 18
		#define TFT_CS 16
		#define TFT_DC 17
		#define TFT_RST -1
		// #define TFT_BL 4
		#define TFT_WIDTH 240
		#define TFT_HEIGHT 240
		// #define TFT_PWR 22
		Adafruit_ST7789 tft = Adafruit_ST7789(TFT_CS, TFT_DC, TFT_MOSI, TFT_SCLK, TFT_RST);
		// Adafruit_ST7789 tft = Adafruit_ST7789(TFT_CS, TFT_DC, TFT_MOSI, TFT_SCLK, TFT_RST);

		void tftInit() {
			tft.init(TFT_HEIGHT, TFT_WIDTH);
			tft.setRotation(2);
			tftClear();
			useTFT = true;
		}

	#elif defined(TTGO_DISPLAY)
		#include "Adafruit_GFX.h"
		#include "Adafruit_ST7789.h"

		#define TFT_MOSI 19
		#define TFT_SCLK 18
		#define TFT_CS 5
		#define TFT_DC 16
		#define TFT_RST 23
		#define TFT_BL 4
		#define TFT_WIDTH 240
		#define TFT_HEIGHT 135
		#define TFT_PWR 22
		Adafruit_ST7789 tft = Adafruit_ST7789(TFT_CS, TFT_DC, TFT_MOSI, TFT_SCLK, TFT_RST);

		void tftInit() {
			pinMode(TFT_BL, OUTPUT);
			digitalWrite(TFT_BL, 1);
			tft.init(TFT_HEIGHT, TFT_WIDTH);
			tft.setRotation(1);
			tftClear();
			useTFT = true;
		}

	#elif defined(GAMEPAD_DISPLAY)
		#include "Adafruit_GFX.h"
		#include "Adafruit_ST7735.h"

		#define TFT_MOSI 13
		#define TFT_SCLK 14
		#define TFT_CS 18
		#define TFT_DC 16
		#define TFT_RST 17
		#define TFT_WIDTH 128
		#define TFT_HEIGHT 128
		Adafruit_ST7735 tft = Adafruit_ST7735(TFT_CS, TFT_DC, TFT_MOSI, TFT_SCLK, TFT_RST);

		void tftInit() {
			tft.initR(INITR_144GREENTAB);
			tft.setRotation(3);
			tft.fillScreen(ST77XX_BLACK);
			useTFT = true;
		}

	#elif defined(TTGO_RP2040)
		#include "Adafruit_GFX.h"
		#include "Adafruit_ST7789.h"

		#define TFT_MOSI 3
		#define TFT_SCLK 2
		#define TFT_CS 5
		#define TFT_DC 1
		#define TFT_RST 0
		#define TFT_BL 4
		#define TFT_WIDTH 240
		#define TFT_HEIGHT 135
		#define TFT_PWR 22
		Adafruit_ST7789 tft = Adafruit_ST7789(TFT_CS, TFT_DC, TFT_MOSI, TFT_SCLK, TFT_RST);

		void tftInit() {
			pinMode(TFT_PWR, OUTPUT);
			pinMode(TFT_BL, OUTPUT);
			digitalWrite(TFT_PWR, 1);
			tft.init(TFT_HEIGHT, TFT_WIDTH);
			analogWrite(TFT_BL, 250);
			tft.setRotation(1);
			tftClear();
			useTFT = true;
		}
	
	#elif defined(FUTURE_LITE)
		#include "Adafruit_GFX.h"
		#include "Adafruit_ST7735.h"

		#define TFT_MOSI 48
		#define TFT_SCLK 45
		#define TFT_CS	46
		#define TFT_DC	12
		#define TFT_RST	-1
		#define TFT_BL 10
		#define TFT_WIDTH 160
		#define TFT_HEIGHT 128
		Adafruit_ST7735 tft = Adafruit_ST7735(TFT_CS, TFT_DC, TFT_MOSI, TFT_SCLK, TFT_RST);

		void tftInit() {
			tft.initR(INITR_BLACKTAB);
			tft.setRotation(3);
			tftClear();
			useTFT = true;
		}


	#elif defined(PICO_ED)
		#include <Adafruit_GFX.h>

		#define TFT_WIDTH 17
		#define TFT_HEIGHT 7
		#define IS_GRAYSCALE true

		// IS31FL3731 constants
		#define IS31FL_ADDR 0x74
		#define IS31FL_BANK_SELECT 0xFD
		#define IS31FL_FUNCTION_BANK 0x0B
		#define IS31FL_SHUTDOWN_REG 0x0A
		#define IS31FL_CONFIG_REG 0x00
		#define IS31FL_PICTUREFRAME_REG 0x01

		#undef UPDATE_DISPLAY
		#define UPDATE_DISPLAY() { if (!deferUpdates) tft.updateDisplay(); }

		class IS31FL3731 : public Adafruit_GFX {
		public:
			IS31FL3731(uint8_t width, uint8_t height) : Adafruit_GFX(width, height) {}

			TwoWire *wire;
			uint8 displayBuffer[144];

			bool begin();
			void drawPixel(int16_t x, int16_t y, uint16_t brightness);
			void clearDisplayBuffer();
			void showMicroBitPixels(int microBitDisplayBits, int xPos, int yPos);
			void updateDisplay(void);
			void setRegister(uint8_t reg, uint8_t value);
		};

		bool IS31FL3731::begin() {
			wire = &Wire1;
			if (readI2CReg(IS31FL_ADDR, 0) < 0) {
				// no display on external i2c bus, so this is a pico:ed v2

				// initialize internal i2c bus
				wire = &Wire;
				wire->setSDA(0);
				wire->setSCL(1);
				wire->begin();
				wire->setClock(400000);

				// speaker in on pin 3 of pico:ed v2
				setPicoEdSpeakerPin(3);
			}

			// select the function bank
			setRegister(IS31FL_BANK_SELECT, IS31FL_FUNCTION_BANK);

			// toggle shutdown
			setRegister(IS31FL_SHUTDOWN_REG, 0);
			delay(10);
			setRegister(IS31FL_SHUTDOWN_REG, 1);

			// picture mode
			setRegister(IS31FL_CONFIG_REG, 0);

			// set frame to display
			setRegister(IS31FL_PICTUREFRAME_REG, 0);

			// clear the display before enabling LED's
			memset(displayBuffer, 0, sizeof(displayBuffer));
			updateDisplay();

			// enable all LEDs
			for (uint8_t bank = 0; bank < 8; bank++) {
				setRegister(IS31FL_BANK_SELECT, bank);
				for (uint8_t i = 0; i < 18; i++) {
					setRegister(i, 0xFF);
				}
			}
			return true;
		}

		void IS31FL3731::clearDisplayBuffer() {
			memset(displayBuffer, 0, sizeof(displayBuffer));
		}

		void IS31FL3731::drawPixel(int16_t x, int16_t y, uint16_t brightness) {
			// Set the brightness of the pixel at (x, y).

			const uint8_t topRow[17] =
				{7, 23, 39, 55, 71, 87, 103, 119, 135, 136, 120, 104, 88, 72, 56, 40, 24};

			if ((x < 0) || (x > 16)) return;
			if ((y < 0) || (y > 6)) return;

			// adjust brightness (use range 0-100 to avoid making LED's painfully bright)
			if ((brightness != 0) && (brightness < 3)) brightness = 3; //
			brightness = (100 * brightness) / 255;
			if (brightness > 100) brightness = 100;

			int incr = (x < 9) ? -1 : 1;
			int i = topRow[x] + (y * incr);
			displayBuffer[i] = brightness;
		}

		void IS31FL3731::showMicroBitPixels(int microBitDisplayBits, int xPos, int yPos) {
			// Draw 5x5 image at the given location where 1,1 is the origin.

			int brightness = 100;
			int y = yPos;
			for (int i = 0; i < 25; i++) {
				int x = (i % 5) + 5 + xPos;
				if ((5 < x) && (x < 11) && (0 < y) && (y < 6)) {
					if (microBitDisplayBits & (1 << i)) drawPixel(x, y, brightness);
				}
				if ((i % 5) == 4) y++;
			}
			updateDisplay();
		}

		void IS31FL3731::updateDisplay() {
			// Write the entire display buffer to bank 0.

			setRegister(IS31FL_BANK_SELECT, 0); // select bank 0
			for (uint8_t i = 0; i < 6; i++) {
				wire->beginTransmission(IS31FL_ADDR);
				wire->write(0x24 + (24 * i)); // offset within bank
				wire->write(&displayBuffer[24 * i], 24);
				wire->endTransmission();
			}
		}

		void IS31FL3731::setRegister(uint8_t reg, uint8_t value) {
			wire->beginTransmission(IS31FL_ADDR);
			wire->write(reg);
			wire->write(value);
			wire->endTransmission();
		}

		// pretend display is 7 pixels wider so GFX will display partial characters
		IS31FL3731 tft = IS31FL3731(TFT_WIDTH + 7, TFT_HEIGHT);

		void tftInit() {
			tft.begin();
			useTFT = true;
		}

	void showMicroBitPixels(int microBitDisplayBits, int xPos, int yPos) {
		// Used by scrolling text; don't clear display.
		tft.showMicroBitPixels(microBitDisplayBits, xPos, yPos);
	}

	#elif defined(COCUBE)
		#include <Arduino_GFX_Library.h>
		#define TFT_MOSI 19
		#define TFT_SCLK 27
		#define TFT_CS -1
		#define TFT_DC 32
		#define TFT_RST 2
		#define TFT_BL 33
		#define TFT_WIDTH 240
		#define TFT_HEIGHT 240
		#define TFT_PWR -1
		#define DEFAULT_BATTERY_PIN 34

		Arduino_ESP32SPI bus = Arduino_ESP32SPI(TFT_DC, -1, TFT_SCLK, TFT_MOSI, -1);
		Arduino_ST7789 tft = Arduino_ST7789(&bus, TFT_RST, 1, false, 240, 240);

		// ArUco Marker, 4x4, 0-white, 1-black
        const uint16_t aruco_tags[100] = {
            0X4ACD, 0XF065, 0XCCD2, 0X66B9, 0XAB61, 0X8632, 0X61D1, 0X3B0D, 0X0125, 0X30A9, 0X066E, 0XEE58, 0XF148,
            0XD5F0, 0XDB4E, 0XD9C1, 0XB99A, 0X99FF, 0X93A1, 0X8950, 0X7974, 0X4FD4, 0X332A, 0X227D, 0X01B8, 0X6B8E,
            0X531B, 0X5AAB, 0XDEDC, 0XCB90, 0XBBEA, 0XA84D, 0X6130, 0X0F34, 0XF751, 0XF6D6, 0XE78A, 0XFB00, 0XF209,
            0XE3A5, 0XE8E7, 0XD5D7, 0XCD73, 0XC74D, 0XDB17, 0XD114, 0XD2C0, 0XB49B, 0XAFD1, 0XAFEC, 0XAE6B, 0XAA97,
            0XA2BE, 0XA068, 0X97FE, 0X9798, 0XEDB,  0X9E16, 0X94ED, 0X901A, 0X9820, 0X81E4, 0X7F5F, 0X7CBB, 0X745D,
            0X6C85, 0X7B93, 0X7AD5, 0X7A63, 0X6376, 0X605E, 0X4483, 0X43FB, 0X49A4, 0X4037, 0X4854, 0X35E0, 0X369D,
            0X26A7, 0X2C2A, 0X3367, 0X385F, 0X3AC8, 0X16A2, 0X06DA, 0X0444, 0X11D5, 0X08B2, 0XCA8A, 0X7552, 0X89E8,
            0XF530, 0XF9B4, 0XD23E, 0XB627, 0XBC0B, 0XB0C9, 0XB02C, 0X961B, 0X8F38};

		const uint64_t april_tags[100] = {
            0x0004064a19651ff1, 0x0004064a53f425b6, 0x0004064a8e832b7b, 0x0004064ac9123140, 0x0004064b03a13705,
            0x0004064b3e303cca, 0x0004064b78bf428f, 0x0004064bb34e4854, 0x0004064beddd4e19, 0x0004064c286c53de,
            0x0004064c62fb59a3, 0x0004064c9d8a5f68, 0x0004064d12a86af2, 0x0004064d4d3770b7, 0x0004064dc2557c41,
            0x0004064dfce48206, 0x0004064e377387cb, 0x0004064e72028d90, 0x0004064eac919355, 0x0004064f21af9edf,
            0x0004064fd15cb02e, 0x000406500bebb5f3, 0x00040650467abbb8, 0x00040650bb98c742, 0x00040650f627cd07,
            0x000406516b45d891, 0x00040651a5d4de56, 0x000406521af2e9e0, 0x000406525581efa5, 0x00040653052f00f4,
            0x000406533fbe06b9, 0x000406537a4d0c7e, 0x00040653ef6b1808, 0x0004065429fa1dcd, 0x0004065464892392,
            0x000406549f182957, 0x00040654d9a72f1c, 0x00040655143634e1, 0x000406554ec53aa6, 0x000406558954406b,
            0x00040655c3e34630, 0x00040655fe724bf5, 0x000406567390577f, 0x00040656ae1f5d44, 0x00040657233d68ce,
            0x00040657985b7458, 0x00040657d2ea7a1d, 0x00040658480885a7, 0x00040658bd269131, 0x00040659e1f1ae0a,
            0x0004065a919ebf59, 0x0004065bb669dc32, 0x0004065bf0f8e1f7, 0x0004065cdb34f90b, 0x0004065d15c3fed0,
            0x0004065d50530495, 0x0004065e3a8f1ba9, 0x0004065eea3c2cf8, 0x0004066049964f96, 0x000406608425555b,
            0x00040660beb45b20, 0x0004066133d266aa, 0x00040661e37f77f9, 0x000406621e0e7dbe, 0x00040662932c8948,
            0x00040662cdbb8f0d, 0x00040663084a94d2, 0x0004066342d99a97, 0x000406637d68a05c, 0x00040663f286abe6,
            0x0004066467a4b770, 0x00040664a233bd35, 0x00040664dcc2c2fa, 0x000406651751c8bf, 0x0004066551e0ce84,
            0x00040666b13af122, 0x00040666ebc9f6e7, 0x0004066760e80271, 0x00040668109513c0, 0x000406684b241985,
            0x00040668fad12ad4, 0x000406696fef365e, 0x00040669aa7e3c23, 0x00040669e50d41e8, 0x0004066bb9857010,
            0x0004066bf41475d5, 0x0004066c6932815f, 0x0004066ca3c18724, 0x0004066d536e9873, 0x0004066dc88ca3fd,
            0x0004066e031ba9c2, 0x0004066eb2c8bb11, 0x000406704cb1e374, 0x00040670c1cfeefe, 0x00040670fc5ef4c3,
            0x0004067136edfa88, 0x00040671ac0c0612, 0x00040673bb1339ff, 0x000406746ac04b4e, 0x00040676b4568500};

        const int april_bit_x[52] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 3, 4, 5, 4, 9, 9, 9, 9, 9, 9, 9, 9, 9, 6, 6, 6, 5,
                               9, 8, 7, 6, 5, 4, 3, 2, 1, 6, 5, 4, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3, 4};
        const int april_bit_y[52] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3, 4, 0, 1, 2, 3, 4, 5, 6, 7, 8, 3, 4, 5, 4,
                               9, 9, 9, 9, 9, 9, 9, 9, 9, 6, 6, 6, 5, 9, 8, 7, 6, 5, 4, 3, 2, 1, 6, 5, 4, 5};

        void tftInit() {
			tft.begin();
			tft.invertDisplay(1);
			tft.fillScreen(RGB565_BLACK);
			pinMode(TFT_BL, OUTPUT);
			digitalWrite(TFT_BL, HIGH);
			useTFT = true;

            unsigned char battery_percentage =constrain((2.54 * map(analogRead(DEFAULT_BATTERY_PIN), 0, 1023, 0, 3300) - 6800) / 16, 0, 99);
			char battery_percentage_char[4];
			itoa(battery_percentage, battery_percentage_char, 10);
			tft.setTextSize(10);
			if (battery_percentage > 66){
				tft.setTextColor(RGB565_GREEN);
			}
			else if (battery_percentage > 33)
			{
				tft.setTextColor(RGB565_ORANGE);
			}
			else{
				tft.setTextColor(RGB565_RED);
			}
			tft.setCursor(80, 80);
			tft.println(battery_percentage_char);
			delay(800);
		}

	#endif // end of board-specific sections

static int color24to16b(int color24b) {
	// Convert 24-bit RGB888 format to the TFT's target pixel format.
	// Return [0..1] for 1-bit display, [0-255] for grayscale, and RGB565 for 16-bit color.

	int r, g, b;

	#ifdef IS_MONOCHROME
		return color24b ? 1 : 0;
	#endif

	#ifdef IS_GRAYSCALE
		r = (color24b >> 16) & 0xFF;
		g = (color24b >> 8) & 0xFF;
		b = color24b & 0xFF;
		int gray = r;
		if (g > r) gray = g;
		if (b > r) gray = b;
		return gray;
	#endif

	r = (color24b >> 19) & 0x1F; // 5 bits
	g = (color24b >> 10) & 0x3F; // 6 bits
	b = (color24b >> 3) & 0x1F; // 5 bits
	#if defined(ARDUINO_M5Stick_C) && !defined(ARDUINO_M5Stick_Plus) && !defined(ARDUINO_M5Stick_C2) 
		return (b << 11) | (g << 5) | r; // color order: BGR
	#else
		return (r << 11) | (g << 5) | b; // color order: RGB
	#endif
}

void tftClear() {
	if (!hasTFT()) return;

	tft.fillScreen(BLACK);
	UPDATE_DISPLAY();
}

void tftSetHugePixel(int x, int y, int state) {
	if (!useTFT) return;

	#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_BBC_MICROBIT_V2) || \
		defined(ARDUINO_CALLIOPE_MINI) || defined(CALLIOPE_V3)
			// allow independent use of OLED and micro:bit display
			return;
	#endif

	// simulate a 5x5 array of square pixels like the micro:bit LED array
	#if defined(PICO_ED)
		if ((1 <= x) && (x <= 5) && (1 <= y) && (y <= 5)) {
			int brightness = (state ? 100 : 0);
			tft.drawPixel((x + 5), y, brightness);
			UPDATE_DISPLAY();
		}
		return;
	#endif
	int minDimension, xInset = 0, yInset = 0;
	if (tft.width() > tft.height()) {
		minDimension = tft.height();
		xInset = (tft.width() - tft.height()) / 2;
	} else {
		minDimension = tft.width();
		yInset = (tft.height() - tft.width()) / 2;
	}
	int lineWidth = (minDimension > 60) ? 3 : 1;
	int squareSize = (minDimension - (6 * lineWidth)) / 5;
	tft.fillRect(
		xInset + ((x - 1) * squareSize) + (x * lineWidth), // x
		yInset + ((y - 1) * squareSize) + (y * lineWidth), // y
		squareSize, squareSize,
		color24to16b(state ? mbDisplayColor : BLACK));
	UPDATE_DISPLAY();
}

void tftSetHugePixelBits(int bits) {
	if (!useTFT) return;

	#if defined(ARDUINO_BBC_MICROBIT) || defined(ARDUINO_BBC_MICROBIT_V2)
		// allow independent use TFT and micro:bit display
		return;
	#endif

	#if defined(PICO_ED)
		tft.clearDisplayBuffer();
		tft.showMicroBitPixels(bits, 1, 1);
		return;
	#endif
	if (0 == bits) {
		tftClear();
	} else {
		for (int x = 1; x <= 5; x++) {
			for (int y = 1; y <= 5; y++) {
				tftSetHugePixel(x, y, bits & (1 << ((5 * (y - 1) + x) - 1)));
			}
		}
	}
	UPDATE_DISPLAY();
}

OBJ primSetVib(int argCount, OBJ *args) {
	if (!useTFT) return falseObj;
	#if defined(ARDUINO_M5STACK_Core2)
		if ((argCount < 1) || !isInt(args[0])) return falseObj;
			int vib = obj2int(args[0]);
		(void) (vib); // reference var to suppress compiler warning
		if(vib) {
			AXP192_SetLDOEnable(3, true);
		}else{
			AXP192_SetLDOEnable(3, false);
		}
	#endif
	return falseObj;
}

OBJ primSetBacklight(int argCount, OBJ *args) {
	if (!hasTFT()) return falseObj;

	if ((argCount < 1) || !isInt(args[0])) return falseObj;
	int brightness = obj2int(args[0]);
	(void) (brightness); // reference var to suppress compiler warning

	#if defined(ARDUINO_IOT_BUS)
		pinMode(33, OUTPUT);
		digitalWrite(33, (brightness > 0) ? HIGH : LOW);
	#elif defined(COCUBE)
        pinMode(TFT_BL, OUTPUT);
        // digitalWrite(TFT_BL, (brightness > 0) ? HIGH : LOW);
		if (brightness < 0) brightness = 0;
		if (brightness > 10) brightness = 10;
		analogWrite(TFT_BL, brightness * 25);
	#elif defined(FUTURE_LITE)
		pinMode(TFT_BL, OUTPUT);
		digitalWrite(TFT_BL, (brightness > 0) ? HIGH : LOW);
	#elif defined(ARDUINO_M5Stack_Core_ESP32) || defined(ARDUINO_M5STACK_FIRE)
		pinMode(32, OUTPUT);
		digitalWrite(32, (brightness > 0) ? HIGH : LOW);
	#elif defined(ARDUINO_M5Stick_C2)
		pinMode(TFT_BL, OUTPUT);
		if (brightness < 0) brightness = 0;
		if (brightness > 10) brightness = 10;
		analogWrite(TFT_BL, brightness * 25);
	#elif defined(ARDUINO_M5Stick_C) || defined(ARDUINO_M5Stick_Plus)
		brightness = (brightness <= 0) ? 0 : brightness + 7; // 8 is lowest setting that turns on backlight
		if (brightness > 15) brightness = 15;
		int n = readAXP(0x28);
		writeAXP(0x28, (brightness << 4) | (n & 0x0f)); // set brightness (high 4 bits of reg 0x28)
	#elif defined(ARDUINO_NRF52840_CLUE)
		pinMode(34, OUTPUT);
		digitalWrite(34, (brightness > 0) ? HIGH : LOW);
 	#elif defined(TTGO_RP2040)
		pinMode(TFT_BL, OUTPUT);
		if (brightness < 0) brightness = 0;
		if (brightness > 10) brightness = 10;
		analogWrite(TFT_BL, brightness * 25);
	#elif defined(OLED_128_64)
		int oledLevel = (255 * brightness) / 10;
		if (oledLevel < 0) oledLevel = 0;
		if (oledLevel > 255) oledLevel = 255;
		writeI2CReg(TFT_ADDR, 0x80, 0x81);
		writeI2CReg(TFT_ADDR, 0x80, oledLevel);
	#endif
	return falseObj;
}

static OBJ primGetWidth(int argCount, OBJ *args) {
	if (!hasTFT()) return zeroObj;

	#ifdef TFT_WIDTH
		return int2obj(TFT_WIDTH);
	#else
		return int2obj(0);
	#endif
}

static OBJ primGetHeight(int argCount, OBJ *args) {
	if (!hasTFT()) return zeroObj;

	#ifdef TFT_HEIGHT
		return int2obj(TFT_HEIGHT);
	#else
		return int2obj(0);
	#endif
}

static OBJ primSetPixel(int argCount, OBJ *args) {
	if (!hasTFT()) return falseObj;

	int x = obj2int(args[0]);
	int y = obj2int(args[1]);
	int color16b = color24to16b(obj2int(args[2]));
	tft.drawPixel(x, y, color16b);
	UPDATE_DISPLAY();
	return falseObj;
}

static OBJ primLine(int argCount, OBJ *args) {
	if (!hasTFT()) return falseObj;

	int x0 = obj2int(args[0]);
	int y0 = obj2int(args[1]);
	int x1 = obj2int(args[2]);
	int y1 = obj2int(args[3]);
	int color16b = color24to16b(obj2int(args[4]));
	tft.drawLine(x0, y0, x1, y1, color16b);
	UPDATE_DISPLAY();
	return falseObj;
}

static OBJ primRect(int argCount, OBJ *args) {
	if (!hasTFT()) return falseObj;

	int x = obj2int(args[0]);
	int y = obj2int(args[1]);
	int width = obj2int(args[2]);
	int height = obj2int(args[3]);
	int color16b = color24to16b(obj2int(args[4]));
	int fill = (argCount > 5) ? (trueObj == args[5]) : true;
	if (fill) {
		tft.fillRect(x, y, width, height, color16b);
	} else {
		tft.drawRect(x, y, width, height, color16b);
	}
	UPDATE_DISPLAY();
	return falseObj;
}

static OBJ primRoundedRect(int argCount, OBJ *args) {
	if (!hasTFT()) return falseObj;

	int x = obj2int(args[0]);
	int y = obj2int(args[1]);
	int width = obj2int(args[2]);
	int height = obj2int(args[3]);
	int radius = obj2int(args[4]);
	int color16b = color24to16b(obj2int(args[5]));
	int fill = (argCount > 6) ? (trueObj == args[6]) : true;
	if (fill) {
		tft.fillRoundRect(x, y, width, height, radius, color16b);
	} else {
		tft.drawRoundRect(x, y, width, height, radius, color16b);
	}
	UPDATE_DISPLAY();
	return falseObj;
}

static OBJ primCircle(int argCount, OBJ *args) {
	if (!hasTFT()) return falseObj;

	int x = obj2int(args[0]);
	int y = obj2int(args[1]);
	int radius = obj2int(args[2]);
	int color16b = color24to16b(obj2int(args[3]));
	int fill = (argCount > 4) ? (trueObj == args[4]) : true;
	if (fill) {
		tft.fillCircle(x, y, radius, color16b);
	} else {
		tft.drawCircle(x, y, radius, color16b);
	}
	UPDATE_DISPLAY();
	return falseObj;
}

static OBJ primTriangle(int argCount, OBJ *args) {
	if (!hasTFT()) return falseObj;

	int x0 = obj2int(args[0]);
	int y0 = obj2int(args[1]);
	int x1 = obj2int(args[2]);
	int y1 = obj2int(args[3]);
	int x2 = obj2int(args[4]);
	int y2 = obj2int(args[5]);
	int color16b = color24to16b(obj2int(args[6]));
	int fill = (argCount > 7) ? (trueObj == args[7]) : true;
	if (fill) {
		tft.fillTriangle(x0, y0, x1, y1, x2, y2, color16b);
	} else {
		tft.drawTriangle(x0, y0, x1, y1, x2, y2, color16b);
	}
	UPDATE_DISPLAY();
	return falseObj;
}

static OBJ primText(int argCount, OBJ *args) {
	if (!hasTFT()) return falseObj;

	OBJ value = args[0];
	int x = obj2int(args[1]);
	int y = obj2int(args[2]);
	int color16b = color24to16b(obj2int(args[3]));
	int scale = (argCount > 4) ? obj2int(args[4]) : 2;
	int wrap = (argCount > 5) ? (trueObj == args[5]) : true;
	int bgColor = (argCount > 6) ? color24to16b(obj2int(args[6])) : -1;
	tft.setCursor(x, y);
	tft.setTextColor(color16b);
	tft.setTextSize(scale);
	tft.setTextWrap(wrap);

	int lineH = 8 * scale;
	int letterW = 6 * scale;
	if (IS_TYPE(value, StringType)) {
		char *str = obj2str(value);
		if (bgColor != -1) tft.fillRect(x, y, strlen(str) * letterW, lineH, bgColor);
		tft.print(obj2str(value));
	} else if (trueObj == value) {
		if (bgColor != -1)  tft.fillRect(x, y, 4 * letterW, lineH, bgColor);
		tft.print("true");
	} else if (falseObj == value) {
		if (bgColor != -1)  tft.fillRect(x, y, 5 * letterW, lineH, bgColor);
		tft.print("false");
	} else if (isInt(value)) {
		char s[50];
		sprintf(s, "%d", obj2int(value));
		if (bgColor != -1) tft.fillRect(x, y, strlen(s) * letterW, lineH, bgColor);
		tft.print(s);
	}
	UPDATE_DISPLAY();
	return falseObj;
}

static OBJ primClear(int argCount, OBJ *args) {
	if (!hasTFT()) return falseObj;
	tftClear();
	return falseObj;
}

#if defined(COCUBE) || defined(ARDUINO_M5Stack_Core_ESP32) || defined(ARDUINO_M5STACK_FIRE)
static OBJ primAruco(int argCount, OBJ *args) {
	if (!useTFT) return falseObj;

	int aruco_id = obj2int(args[0]);
	    if (aruco_id >= 100) {
        return falseObj;
    }
    tft.drawRect(0, 0, TFT_HEIGHT, TFT_HEIGHT, BLACK);
    const int cellSize = TFT_HEIGHT/8;
	const int startX = TFT_WIDTH/2 - (4 * cellSize);
    uint16_t tag = aruco_tags[aruco_id];
    for (int i = 0; i < 8; i++) {
        for (int j = 0; j < 8; j++) {
            bool isBlack = false;

            if (i == 0 || i == 7 || j == 0 || j == 7) {
                // 外层白色边框
                isBlack = false;
            } else if (i == 1 || i == 6 || j == 1 || j == 6) {
                // 内层黑色边框
                isBlack = true;
            } else {
                // 中央的4x4区域，用于编码信息
                int bitIndex = (i - 2) * 4 + (j - 2);
                isBlack = tag & (1 << (15 - bitIndex));
            }
            if (isBlack) {
                tft.fillRect(startX + j * cellSize, i * cellSize, cellSize, cellSize, BLACK);
            } else {
                tft.fillRect(startX + j * cellSize, i * cellSize, cellSize, cellSize, WHITE);
            }
        }
    }
    tft.setCursor(startX + 2, 2);
    tft.setTextColor(BLACK);
    tft.setTextSize(2);
    tft.print(aruco_id);
	UPDATE_DISPLAY();
	return falseObj;
}

static OBJ primAprilTag(int argCount, OBJ *args) {
    if (!useTFT) return falseObj;

    int tag_id = obj2int(args[0]);
    if (tag_id >= 100) {
        return falseObj;
    }
    tft.drawRect(0, 0, TFT_HEIGHT, TFT_HEIGHT, BLACK);
    const int cellSize = TFT_HEIGHT/10;
	const int startX = TFT_WIDTH/2 - (5 * cellSize);
    uint64_t codedata = april_tags[tag_id];

    // 绘制外圈的黑色方块
    for (int i = 1; i < 9; i++) {
        tft.fillRect(startX + i * cellSize, 1 * cellSize, cellSize, cellSize, BLACK);  // 左边界
        tft.fillRect(startX + i * cellSize, 8 * cellSize, cellSize, cellSize, BLACK);  // 右边界
        tft.fillRect(startX + 1 * cellSize, i * cellSize, cellSize, cellSize, BLACK);  // 上边界
        tft.fillRect(startX + 8 * cellSize, i * cellSize, cellSize, cellSize, BLACK);  // 下边界
    }

    // 绘制内圈的白色方块
    for (int i = 2; i < 8; i++) {
        tft.fillRect(startX + i * cellSize, 2 * cellSize, cellSize, cellSize, WHITE);  // 左边界
        tft.fillRect(startX + i * cellSize, 7 * cellSize, cellSize, cellSize, WHITE);  // 右边界
        tft.fillRect(startX + 2 * cellSize, i * cellSize, cellSize, cellSize, WHITE);  // 上边界
        tft.fillRect(startX + 7 * cellSize, i * cellSize, cellSize, cellSize, WHITE);  // 下边界
    }

    // 绘制编码的标签图像
    for (int i = 0; i < 52; i++) {
        int x = april_bit_x[i];
        int y = april_bit_y[i];
        bool bit = (codedata >> (51 - i)) & 1;
        uint16_t color = bit ? WHITE : BLACK;
        tft.fillRect(startX + x * cellSize, y * cellSize, cellSize, cellSize, color);
    }
    UPDATE_DISPLAY();
    return falseObj;
}
#endif
// display update control

static OBJ primDeferUpdates(int argCount, OBJ *args) {
	if (!hasTFT()) return falseObj;
	deferUpdates = true;
	return falseObj;
}

static OBJ primResumeUpdates(int argCount, OBJ *args) {
	if (!hasTFT()) return falseObj;
	deferUpdates = false;
	UPDATE_DISPLAY();
	return falseObj;
}

// 8 bit bitmap ops

static OBJ primMergeBitmap(int argCount, OBJ *args) {
	if (!hasTFT()) return falseObj;

	OBJ bitmap = args[0];
	int bitmapWidth = obj2int(args[1]);
	OBJ buffer = args[2];
	int scale = max(min(obj2int(args[3]), 8), 1);
	int alphaIndex = obj2int(args[4]);
	int destX = obj2int(args[5]);
	int destY = obj2int(args[6]);

	int bitmapHeight = BYTES(bitmap) / bitmapWidth;
	int bufferWidth = TFT_WIDTH / scale;
	int bufferHeight = TFT_HEIGHT / scale;
	uint8 *bitmapBytes = (uint8 *) &FIELD(bitmap, 0);
	uint8 *bufferBytes = (uint8 *) &FIELD(buffer, 0);

	for (int y = 0; y < bitmapHeight; y++) {
		if ((y + destY) < bufferHeight && (y + destY) >= 0) {
			for (int x = 0; x < bitmapWidth; x++) {
				if ((x + destX) < bufferWidth && (x + destX) >= 0) {
					int pixelValue = bitmapBytes[y * bitmapWidth + x];
					if (pixelValue != alphaIndex) {
						int bufIndex = (destY + y) * bufferWidth + x + destX;
						bufferBytes[bufIndex] = pixelValue;
					}
				}
			}
		}
	}
	return falseObj;
}

uint16_t bufferPixels[TFT_WIDTH * 8];

static OBJ primDrawBuffer(int argCount, OBJ *args) {
	if (!hasTFT()) return falseObj;

	OBJ buffer = args[0];
	OBJ palette = args[1]; // List, index-1 based
	int scale = max(min(obj2int(args[2]), 8), 1);

	int originX = 0;
	int originY = 0;
	int copyWidth = -1;
	int copyHeight = -1;

	if (argCount > 6) {
		originX = obj2int(args[3]);
		originY = obj2int(args[4]);
		copyWidth = obj2int(args[5]);
		copyHeight = obj2int(args[6]);
	}

	int bufferWidth = TFT_WIDTH / scale;
	int bufferHeight = TFT_HEIGHT / scale;

	int originWidth = copyWidth >= 0 ? copyWidth : bufferWidth;
	int originHeight = copyHeight >= 0 ? copyHeight : bufferHeight;

	uint8 *bufferBytes = (uint8 *) &FIELD(buffer, 0);
	// Read the indices from the buffer and turn them into color values from the
	// palette, and paint them onto the TFT
	for (int y = 0; y < originHeight; y ++) {
		for (int x = 0; x < originWidth; x ++) {
			int colorIndex = bufferBytes[
				(y + originY) * bufferWidth + (x + originX)];
			int color = color24to16b(obj2int(FIELD(palette, colorIndex + 1)));
			for (int i = 0; i < scale; i ++) {
				for (int j = 0; j < scale; j ++) {
					bufferPixels[(j * originWidth * scale) + x * scale + i] = color;
				}
			}
		}
		#ifdef COCUBE
			tft.fillRect(
			originX * scale,
			(originY + y) * scale,
			originWidth * scale,
			scale,
			bufferPixels[0]
		);
		#else
			tft.drawRGBBitmap(
				originX * scale,
				(originY + y) * scale,
				bufferPixels,
				originWidth * scale,
				scale
			);
		#endif
	}

	UPDATE_DISPLAY();
	return falseObj;
}

static OBJ primDrawBitmap(int argCount, OBJ *args) {
	// Draw an 8-bit bitmap at a given position without scaling.

	if (!hasTFT()) return falseObj;
	uint32 palette[256];

	if (argCount < 4) return fail(notEnoughArguments);
	OBJ bitmapObj = args[0]; // bitmap: a two-item list of [width (int), pixels (byte array)]
	OBJ paletteObj = args[1]; // palette: a list of RGB values
	int dstX = obj2int(args[2]);
	int dstY = obj2int(args[3]);

	if ((dstX > TFT_WIDTH) || (dstY > TFT_HEIGHT)) return falseObj; // off screen

	// process bitmap arg
	if (!IS_TYPE(bitmapObj, ListType) ||
	 	(obj2int(FIELD(bitmapObj, 0)) != 2) ||
	 	!isInt(FIELD(bitmapObj, 1)) ||
	 	!IS_TYPE(FIELD(bitmapObj, 2), ByteArrayType)) {
	 		return fail(bad8BitBitmap);
	}
	int bitmapWidth = obj2int(FIELD(bitmapObj, 1));
	OBJ bitmapBytesObj = FIELD(bitmapObj, 2);
	int bitmapByteCount = BYTES(bitmapBytesObj);
	if ((bitmapWidth <= 0) || ((bitmapByteCount % bitmapWidth) != 0)) return fail(bad8BitBitmap);
	int bitmapHeight = bitmapByteCount / bitmapWidth;

	// process palette arg
	if (!IS_TYPE(paletteObj, ListType)) return fail(badColorPalette);
	int colorCount = obj2int(FIELD(paletteObj, 0)); // list size
	if (colorCount > 256) colorCount = 256;
	memset(palette, 0, sizeof(palette)); // initialize to all black RGB values
	for (int i = 0; i < colorCount; i++) {
		int rgb = obj2int(FIELD(paletteObj, i + 1));
		if (rgb < 0) rgb = 0;
		if (rgb > 0xFFFFFF) rgb = 0xFFFFFF;
		palette[i] = rgb;
	}

	int srcX = 0;
	int srcW = bitmapWidth;
	if (dstX < 0) { srcX = -dstX; dstX = 0; srcW -= srcX; }
	if (srcW < 0) return falseObj; // off screen to left
	if ((dstX + srcW) > TFT_WIDTH) srcW = TFT_WIDTH - dstX;

	int srcY = 0;
	int srcH = bitmapHeight;
	if (dstY < 0) { srcY = -dstY; dstY = 0; srcH -= srcY; }
	if (srcH < 0) return falseObj; // off screen above
	if ((dstY + srcH) > TFT_HEIGHT) srcH = TFT_HEIGHT - dstY;

	uint8 *bitmapBytes = (uint8 *) &FIELD(bitmapBytesObj, 0);
	for (int i = 0; i < srcH; i++) {
		uint8 *row = bitmapBytes + ((srcY + i) * bitmapWidth);
		for (int j = 0; j < srcW; j++) {
			uint8 pix = row[srcX + j]; // 8-bit color index
			uint32 rgb = palette[pix]; // 24 bit RGB color
			tft.drawPixel(dstX + j, dstY + i, color24to16b(rgb));
		}
	}
	UPDATE_DISPLAY();
	return falseObj;
}

// touchscreen ops

static OBJ primTftTouched(int argCount, OBJ *args) {
	#ifdef HAS_TFT_TOUCH
		if (!touchEnabled) { touchInit(); }
		#ifdef ARDUINO_M5STACK_Core2
			return	ispressed() ? trueObj : falseObj;		
		#else
			return ts.touched() ? trueObj : falseObj;
		#endif
	#endif
	return falseObj;
}

static OBJ primTftTouchX(int argCount, OBJ *args) {
	#ifdef HAS_TFT_TOUCH
		if (!touchEnabled) { touchInit(); }
		#ifdef ARDUINO_M5STACK_Core2
			return int2obj(readFT6336Data(1));	
		#else
			if (ts.touched()) {
				TS_Point p = ts.getMappedPoint();
				return int2obj(p.x);
			}
		#endif
	#endif
	return int2obj(-1);
}

static OBJ primTftTouchY(int argCount, OBJ *args) {
	#ifdef HAS_TFT_TOUCH
		if (!touchEnabled) { touchInit(); }
		#ifdef ARDUINO_M5STACK_Core2
			return int2obj(readFT6336Data(2));	
		#else
		if (ts.touched()) {
			TS_Point p = ts.getMappedPoint();
			return int2obj(p.y);
		}
		#endif
	#endif
	return int2obj(-1);
}

static OBJ primTftTouchPressure(int argCount, OBJ *args) {
	#ifdef HAS_TFT_TOUCH
		if (!touchEnabled) { touchInit(); }
		#ifdef ARDUINO_M5STACK_Core2
			return int2obj(readFT6336Data(3));
		#else
			if (ts.touched()) {
				TS_Point p = ts.getMappedPoint();
				return int2obj(p.z);
			}
		#endif
	#endif
	return int2obj(-1);
}

#else // stubs

void tftInit() { }
void tftClear() { }
void tftSetHugePixel(int x, int y, int state) { }
void tftSetHugePixelBits(int bits) { }

static OBJ primSetBacklight(int argCount, OBJ *args) { return falseObj; }
static OBJ primGetWidth(int argCount, OBJ *args) { return int2obj(0); }
static OBJ primGetHeight(int argCount, OBJ *args) { return int2obj(0); }
static OBJ primSetPixel(int argCount, OBJ *args) { return falseObj; }
static OBJ primLine(int argCount, OBJ *args) { return falseObj; }
static OBJ primRect(int argCount, OBJ *args) { return falseObj; }
static OBJ primRoundedRect(int argCount, OBJ *args) { return falseObj; }
static OBJ primCircle(int argCount, OBJ *args) { return falseObj; }
static OBJ primTriangle(int argCount, OBJ *args) { return falseObj; }
static OBJ primText(int argCount, OBJ *args) { return falseObj; }
static OBJ primClear(int argCount, OBJ *args) { return falseObj; }

static OBJ primDeferUpdates(int argCount, OBJ *args) { return falseObj; }
static OBJ primResumeUpdates(int argCount, OBJ *args) { return falseObj; }

static OBJ primMergeBitmap(int argCount, OBJ *args) { return falseObj; }
static OBJ primDrawBuffer(int argCount, OBJ *args) { return falseObj; }
static OBJ primDrawBitmap(int argCount, OBJ *args) { return falseObj; }

static OBJ primTftTouched(int argCount, OBJ *args) { return falseObj; }
static OBJ primTftTouchX(int argCount, OBJ *args) { return falseObj; }
static OBJ primTftTouchY(int argCount, OBJ *args) { return falseObj; }
static OBJ primTftTouchPressure(int argCount, OBJ *args) { return falseObj; }

static OBJ primSetVib(int argCount, OBJ *args) { return falseObj; }

#endif

// Primitives

static PrimEntry entries[] = {
	{"setBacklight", primSetBacklight},
	{"getWidth", primGetWidth},
	{"getHeight", primGetHeight},
	{"setPixel", primSetPixel},
	{"line", primLine},
	{"rect", primRect},
	{"roundedRect", primRoundedRect},
	{"circle", primCircle},
	{"triangle", primTriangle},
	{"text", primText},
	{"clear", primClear},
	{"deferUpdates", primDeferUpdates},
	{"resumeUpdates", primResumeUpdates},
	
	{"mergeBitmap", primMergeBitmap},
	{"drawBuffer", primDrawBuffer},
	{"drawBitmap", primDrawBitmap},

	{"tftTouched", primTftTouched},
	{"tftTouchX", primTftTouchX},
	{"tftTouchY", primTftTouchY},
	{"tftTouchPressure", primTftTouchPressure},

	{"setVib",primSetVib},

	#if defined(COCUBE) || defined(ARDUINO_M5Stack_Core_ESP32) || defined(ARDUINO_M5STACK_FIRE)
	{"aruco", primAruco},
	{"aprilTag", primAprilTag},
	#endif
};

void addTFTPrims() {
	addPrimitiveSet(TFTPrims, "tft", sizeof(entries) / sizeof(PrimEntry), entries);
}
