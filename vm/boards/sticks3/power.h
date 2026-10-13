/* MPL 2.0: https://mozilla.org/MPL/2.0/ */
// StickS3 internal power bus. Read-modify-write preserves unrelated settings.
#pragma once
#include <Wire.h>
static bool stickS3Read(uint8_t reg, uint8_t &value) {
	Wire1.beginTransmission(0x6e);
	Wire1.write(reg);
	if (Wire1.endTransmission(false) != 0) return false;
	if (Wire1.requestFrom(0x6e, 1) != 1) return false;
	value = Wire1.read();
	return true;
}
static bool stickS3Write(uint8_t reg, uint8_t value) {
	Wire1.beginTransmission(0x6e);
	Wire1.write(reg);
	Wire1.write(value);
	return Wire1.endTransmission() == 0;
}
static bool stickS3Update(uint8_t reg, uint8_t clear, uint8_t set) {
	uint8_t value;
	return stickS3Read(reg, value) && stickS3Write(reg, (value & ~clear) | set);
}
static bool stickS3PowerInit() {
	Wire1.begin(47, 48);
	Wire1.setClock(400000);
	Wire1.setTimeOut(50);
	// Disable external boost before enabling LCD power. Never enable it implicitly.
	if (!stickS3Update(0x06, 0x08, 0)) return false;
	if (!stickS3Write(0x09, 0) || !stickS3Write(0x0a, 0)) return false;
	// GPIO2: GPIO function, push-pull high, output (L3B LCD supply).
	if (!stickS3Update(0x16, 0x30, 0) ||
		!stickS3Update(0x13, 0x04, 0) ||
		!stickS3Update(0x11, 0, 0x04) ||
		!stickS3Update(0x10, 0, 0x04)) return false;
	delay(100);
	return true;
}
