#include "mem.h"
#include "interp.h"
#include "persist.h"

void setup() {
  #ifdef ARDUINO_NRF52_PRIMO
    sd_softdevice_disable();
  #endif
  Serial.begin(115200);
  hardwareInit();
  memInit(5000); // 5k words = 20k bytes
  outputString("Welcome to uBlocks for Arduino!");
  restoreScripts();
  startAll();
}

void loop() {
  vmLoop();
}

