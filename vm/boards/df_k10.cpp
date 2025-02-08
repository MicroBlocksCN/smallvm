/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// sensorPrims.cpp - Microblocks I2C, SPI, tilt, and temperature primitives
// John Maloney, May 2018

#ifdef DF_K10
  #include "interp.h"
  #include <Arduino.h>
  #include <Audio.h>
  #include <ESP_IOExpander_Library.h>
  #include <SPI.h>
  #include <Wire.h>
  #include <stdio.h>
  #include <stdlib.h>

  Audio audio;

  void boardInit() {

    ESP_IOExpander *expander = new ESP_IOExpander_TCA95xx_16bit(
        I2C_NUM_0, ESP_IO_EXPANDER_I2C_TCA9554_ADDRESS_000, I2C_SCL_PIN,
        I2C_SDA_PIN);

    expander->init();
    expander->begin();
    expander->printStatus();
    expander->pinMode(0, OUTPUT);
    expander->pinMode(1, OUTPUT);
    expander->digitalWrite(0, HIGH);
    expander->digitalWrite(1, HIGH);
    expander->pinMode(2, INPUT);
    expander->pinMode(12, INPUT);

    audio.setPinout(I2S_BCLK, I2S_LRC, I2S_DOUT);
    audio.setVolume(0);
    Serial.println("Audio initialized");
  }
#endif