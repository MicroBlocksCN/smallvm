#include "mem.h"
#include "interp.h"
#include "persist.h"

void setup() {
  #ifdef ARDUINO_NRF52_PRIMO
    sd_softdevice_disable();
  #endif
  hardwareInit();
  memInit(1800); // 1800 words = 7200 bytes
  outputString("Welcome to MicroBlocks!");
  restoreScripts();
  startAll();
}

void loop() {
  vmLoop();
}

