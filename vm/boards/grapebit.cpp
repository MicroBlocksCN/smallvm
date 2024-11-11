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

#define DA213ADDR 39

extern int accelStarted;


static void startDA213() {
    Wire.beginTransmission(DA213ADDR);
    Wire.write(0x7f);
    Wire.write(0x83);
    Wire.endTransmission();

    Wire.beginTransmission(DA213ADDR);
    Wire.write(0x7f);
    Wire.write(0x69);
    Wire.endTransmission();

    Wire.beginTransmission(DA213ADDR);
    Wire.write(0x7f);
    Wire.write(0xbd);
    Wire.endTransmission();

    Wire.beginTransmission(DA213ADDR);
    Wire.write(0x8e);
    Wire.endTransmission();
    Wire.requestFrom(DA213ADDR, 1);
    uint8_t a = Wire.read();
    if (a == 0) {
        Wire.beginTransmission(DA213ADDR);
        Wire.write(0x8e);
        Wire.write(0x50);
        Wire.endTransmission();
    }

    Wire.beginTransmission(DA213ADDR);
    Wire.write(0x0f);
    Wire.write(0x40);
    Wire.endTransmission();

    Wire.beginTransmission(DA213ADDR);
    Wire.write(0x20);
    Wire.write(0x00);
    Wire.endTransmission();

    Wire.beginTransmission(DA213ADDR);
    Wire.write(0x11);
    Wire.write(0x34);
    Wire.endTransmission();

    Wire.beginTransmission(DA213ADDR);
    Wire.write(0x10);
    Wire.write(0x07);
    Wire.endTransmission();

    Wire.beginTransmission(DA213ADDR);
    Wire.write(0x1a);
    Wire.write(0x04);
    Wire.endTransmission();

    Wire.beginTransmission(DA213ADDR);
    Wire.write(0x15);
    Wire.write(0x04);
    Wire.endTransmission();

    accelStarted = true;
}


int readAcceleration(int registerID) {
    if (!accelStarted) {
		startDA213();
	}

    Wire.beginTransmission(DA213ADDR);
    Wire.write(registerID);
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
    int val = imu[registerID];
	return (100 * val) >> 14;
}

void setAccelRange(int range) {
	return;
}

int readTemperature() {
    return 0;
}
