#pragma once
#include "Arduino.h"
#include "Wire.h"
#define BMI2_OK 0
#define BMI2_ACCEL 1
struct bmi2_sens_config {
    int type;
    struct { struct { int range; } acc; } cfg;
};
struct BMI270 {
    struct { float accelX = 1, accelY = 2, accelZ = -1; } data;
    int beginError = 0, configReadError = 0, configWriteError = 0;
    int sampleError = 0, tempError = 0, beginCalls = 0, range = 0;
    int beginI2C(int address, MockWire&) { assert(address == 0x68); ++beginCalls; return beginError; }
    int getConfig(bmi2_sens_config *config) { config->cfg.acc.range = range; return configReadError; }
    int setConfig(bmi2_sens_config config) {
        assert(config.type == BMI2_ACCEL);
        range = config.cfg.acc.range; // mirror the driver's scale update before I2C completion
        return configWriteError;
    }
    int getSensorData() { return sampleError; }
    int getTemperature(float *temperature) { *temperature = -2.6f; return tempError; }
};
