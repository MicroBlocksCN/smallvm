/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// sensorPrims.cpp - Microblocks I2C, SPI, tilt, and temperature primitives
// John Maloney, May 2018

#include <Arduino.h>
#include <SPI.h>
#include <Wire.h>
#include <stdio.h>
#include <stdlib.h>
#include "interp.h"

#define DA213ADDR 39

extern int accelStarted;

void boardInit() {
    // debug serial port
    // Serial1.begin(115200, SERIAL_8N1, 0, 2); // debug port at pad 1
    // Serial1.printf("Grapebit board init\n");
}

static void startDA213() {
    writeI2CReg(DA213ADDR, 0x7f, 0x83);
    writeI2CReg(DA213ADDR, 0x7f, 0x69);
    writeI2CReg(DA213ADDR, 0x7f, 0xbd);
    writeI2CReg(DA213ADDR, 0x8e, 0x00); // Assuming 0x00 is the value to write

    uint8_t a = readI2CReg(DA213ADDR, 0x8e);
    if (a == 0) {
        writeI2CReg(DA213ADDR, 0x8e, 0x00); // Assuming 0x00 is the value to write
    }

    accelStarted = true;
}


int readAcceleration(int registerID) {
    if (!accelStarted) {
		startDA213();
	}

    Wire.beginTransmission(DA213ADDR);
    Wire.write(0x02);
    Wire.endTransmission();
    Wire.requestFrom(DA213ADDR, 6);
    uint8_t data[6];
    for (int i = 0; i < 6; i++) {
        data[i] = Wire.read();
    }
    int16_t imu[3];
    imu[0] = (data[1] << 8) | data[0];
    imu[1] = (data[3] << 8) | data[2];
    imu[2] = (data[5] << 8) | data[4];
    // register from 1, 3, 5
    // Serial1.printf("IMU %d x: %d, y: %d, z: %d\n", registerID, imu[0], imu[1], imu[2]);
    int val = 0;
    // fix orders
    if (registerID == 1) {
        val = imu[0] / 16;
    } else if (registerID == 3) {
        val = -imu[1] / 16;
    } else if (registerID == 5) {
        val = imu[2] / 16;
    }
    // Serial1.printf("IMU %d val: %d\n", registerID, val);
	return val;
}

void setAccelRange(int range) {
	return;
}

int readTemperature() {
    return 0;
}
