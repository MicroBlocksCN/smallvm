/* MPL 2.0: https://mozilla.org/MPL/2.0/ */
#pragma once
#include <SparkFun_BMI270_Arduino_Library.h>

static BMI270 stickIMU;
static bool stickIMUReady = false;
static bool stickIMURetryPending = false;
static uint32_t stickIMURetryAt = 0;
static int stickRequestedRange = 0;

static void stickIMUFailed() {
	stickIMUReady = false;
	accelStarted = false;
	stickIMURetryPending = true;
	stickIMURetryAt = millis() + 1000;
}

static bool configureStickIMURange() {
	bmi2_sens_config config = {};
	config.type = BMI2_ACCEL;
	if (stickIMU.getConfig(&config) != BMI2_OK) return false;
	config.cfg.acc.range = stickRequestedRange; // 0..3: +/-2,4,8,16g
	return stickIMU.setConfig(config) == BMI2_OK;
}

static bool startStickIMU() {
	if (stickIMUReady) return true;
	// At most one initialization per request, no more than once per second.
	if (stickIMURetryPending && (int32_t) (millis() - stickIMURetryAt) < 0) return false;
	Wire1.begin(47, 48);
	Wire1.setClock(400000);
	if (stickIMU.beginI2C(0x68, Wire1) != BMI2_OK || !configureStickIMURange()) {
		stickIMUFailed();
		return false;
	}
	stickIMUReady = true;
	accelStarted = true;
	stickIMURetryPending = false;
	return true;
}

static int readAcceleration(int reg) {
	if (!startStickIMU()) { fail(i2cTransferFailed); return 0; }
	if (stickIMU.getSensorData() != BMI2_OK) {
		stickIMUFailed();
		fail(i2cTransferFailed);
		return 0;
	}
	// Match M5Unified's StickS3 axes; MicroBlocks uses 100 per g at range 1.
	float g = (reg == 1) ? stickIMU.data.accelY :
		(reg == 3) ? -stickIMU.data.accelX : stickIMU.data.accelZ;
	return (int) roundf(g * 100 / (1 << stickRequestedRange));
}

static void setAccelRange(int range) {
	stickRequestedRange = range;
	if (!stickIMUReady) {
		if (!startStickIMU()) fail(i2cTransferFailed);
	} else if (!configureStickIMURange()) {
		// SparkFun updates its conversion scale before writing the hardware.
		// Invalidate both states until initialization restores a matching range.
		stickIMUFailed();
		fail(i2cTransferFailed);
	}
}

static int readTemperature() {
	if (!startStickIMU()) { fail(i2cTransferFailed); return 0; }
	float temperature;
	if (stickIMU.getTemperature(&temperature) != BMI2_OK) {
		stickIMUFailed();
		fail(i2cTransferFailed);
		return 0;
	}
	return (int) roundf(temperature);
}
