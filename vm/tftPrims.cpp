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
int touchEnabled = false;

// Redefine this macro for displays that must explicitly push offscreen changes to the display
#define UPDATE_DISPLAY()

#if defined(ARDUINO_CITILAB_ED1) || defined(ARDUINO_M5Stack_Core_ESP32) || \
	defined(ARDUINO_M5Stick_C) || defined(ARDUINO_ESP8266_WEMOS_D1MINI) || \
	defined(ARDUINO_NRF52840_CLUE) || defined(ARDUINO_IOT_BUS) || defined(SCOUT_MAKES_AZUL) || \
	defined(TTGO_RP2040) || defined(ARDUINO_M5STACK_Core2)

	#define BLACK 0

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

	#elif defined(ARDUINO_M5Stack_Core_ESP32)
		#include "Adafruit_GFX.h"
		#include "Adafruit_ILI9341.h"
		#define TFT_CS	14
		#define TFT_DC	27
		#define TFT_RST	33
		#define TFT_WIDTH 320
		#define TFT_HEIGHT 240
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

	#elif defined(SCOUT_MAKES_AZUL)
		#include "Adafruit_GFX.h"
		#include "Adafruit_SSD1306.h"

		#define TFT_WIDTH 128
		#define TFT_HEIGHT 32
		#define IS_MONCHROME true

		Adafruit_SSD1306 tft = Adafruit_SSD1306(128, 32); // xxx may need params

		#undef UPDATE_DISPLAY
		#define UPDATE_DISPLAY() (tft.display())

		void tftInit() {
			int ok = tft.begin(SSD1306_SWITCHCAPVCC, 0x3C);
			tftClear();
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
	#endif

void tftClear() {
	tft.fillScreen(BLACK);
	UPDATE_DISPLAY();
}

OBJ primEnableDisplay(int argCount, OBJ *args) {
	if (trueObj == args[0]) {
		tftInit();
	} else {
		useTFT = false;
		#if defined(TTGO_RP2040)
			digitalWrite(TFT_PWR, 0);
		#endif
	}
	return falseObj;
}

OBJ primSetBacklight(int argCount, OBJ *args) {
	if ((argCount < 1) || !isInt(args[0])) return falseObj;
	int brightness = obj2int(args[0]);

	#if defined(ARDUINO_IOT_BUS)
		pinMode(33, OUTPUT);
		digitalWrite(33, (brightness > 0) ? HIGH : LOW);
	#elif defined(ARDUINO_M5Stack_Core_ESP32)
		pinMode(32, OUTPUT);
		digitalWrite(32, (brightness > 0) ? HIGH : LOW);
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
	#endif
	return falseObj;
}

static int color24to16b(int color24b) {
	// Convert 24-bit RGB888 format to the TFT's color format (e.g. 16-bit RGB565).

	#ifdef IS_MONCHROME
		return color24b ? 1 : 0;
	#endif
	int r = (color24b >> 19) & 0x1F; // 5 bits
	int g = (color24b >> 10) & 0x3F; // 6 bits
	int b = (color24b >> 3) & 0x1F; // 5 bits
	#if defined(ARDUINO_M5Stick_C) && !defined(ARDUINO_M5Stick_Plus)
		return (b << 11) | (g << 5) | r; // color order: BGR
	#else
		return (r << 11) | (g << 5) | b; // color order: RGB
	#endif
}

static OBJ primGetWidth(int argCount, OBJ *args) {
	#ifdef TFT_WIDTH
		return int2obj(TFT_WIDTH);
	#else
		return int2obj(0);
	#endif
}

static OBJ primGetHeight(int argCount, OBJ *args) {
	#ifdef TFT_HEIGHT
		return int2obj(TFT_HEIGHT);
	#else
		return int2obj(0);
	#endif
}

static OBJ primSetPixel(int argCount, OBJ *args) {
	int x = obj2int(args[0]);
	int y = obj2int(args[1]);
	int color16b = color24to16b(obj2int(args[2]));
	tft.drawPixel(x, y, color16b);
	UPDATE_DISPLAY();
	return falseObj;
}

static OBJ primLine(int argCount, OBJ *args) {
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
	OBJ value = args[0];
	int x = obj2int(args[1]);
	int y = obj2int(args[2]);
	int color16b = color24to16b(obj2int(args[3]));
	int scale = (argCount > 4) ? obj2int(args[4]) : 2;
	int wrap = (argCount > 5) ? (trueObj == args[5]) : true;
	tft.setCursor(x, y);
	tft.setTextColor(color16b);
	tft.setTextSize(scale);
	tft.setTextWrap(wrap);

	if (IS_TYPE(value, StringType)) {
		tft.print(obj2str(value));
	} else if (trueObj == value) {
		tft.print("true");
	} else if (falseObj == value) {
		tft.print("false");
	} else if (isInt(value)) {
		char s[50];
		sprintf(s, "%d", obj2int(value));
		tft.print(s);
	}
	UPDATE_DISPLAY();
	return falseObj;
}

void tftSetHugePixel(int x, int y, int state) {
	// simulate a 5x5 array of square pixels like the micro:bit LED array
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
		color24to16b(state ? 0x00FF00 : BLACK));
	UPDATE_DISPLAY();
}

void tftSetHugePixelBits(int bits) {
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

static OBJ primTftTouched(int argCount, OBJ *args) {
	#ifdef HAS_TFT_TOUCH
		if (!touchEnabled) { touchInit(); }
		return ts.touched() ? trueObj : falseObj;
	#endif
	return falseObj;
}

static OBJ primTftTouchX(int argCount, OBJ *args) {
	#ifdef HAS_TFT_TOUCH
		if (!touchEnabled) { touchInit(); }
		if (ts.touched()) {
			TS_Point p = ts.getMappedPoint();
			return int2obj(p.x);
		}
	#endif
	return int2obj(-1);
}

static OBJ primTftTouchY(int argCount, OBJ *args) {
	#ifdef HAS_TFT_TOUCH
		if (!touchEnabled) { touchInit(); }
		if (ts.touched()) {
			TS_Point p = ts.getMappedPoint();
			return int2obj(p.y);
		}
	#endif
	return int2obj(-1);
}

static OBJ primTftTouchPressure(int argCount, OBJ *args) {
	#ifdef HAS_TFT_TOUCH
		if (!touchEnabled) { touchInit(); }
		if (ts.touched()) {
			TS_Point p = ts.getMappedPoint();
			return int2obj(p.z);
		}
	#endif
	return int2obj(-1);
}

#else // stubs

void tftInit() { }
void tftClear() { }
void tftSetHugePixel(int x, int y, int state) { }
void tftSetHugePixelBits(int bits) { }

static OBJ primEnableDisplay(int argCount, OBJ *args) { return falseObj; }
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
static OBJ primTftTouched(int argCount, OBJ *args) { return falseObj; }
static OBJ primTftTouchX(int argCount, OBJ *args) { return falseObj; }
static OBJ primTftTouchY(int argCount, OBJ *args) { return falseObj; }
static OBJ primTftTouchPressure(int argCount, OBJ *args) { return falseObj; }

#endif

// Primitives

static PrimEntry entries[] = {
	{"enableDisplay", primEnableDisplay},
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
	{"tftTouched", primTftTouched},
	{"tftTouchX", primTftTouchX},
	{"tftTouchY", primTftTouchY},
	{"tftTouchPressure", primTftTouchPressure},
};

void addTFTPrims() {
	addPrimitiveSet("tft", sizeof(entries) / sizeof(PrimEntry), entries);
}
