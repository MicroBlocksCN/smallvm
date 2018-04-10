#include "mem.h"
#include "interp.h"
#include "persist.h"

void setup() {
  #ifdef ARDUINO_NRF52_PRIMO
    sd_softdevice_disable();
  #endif
  hardwareInit();
  memInit(2000); // 2000 words = 8000 bytes
  outputString("Welcome to MicroBlocks!");
  restoreScripts();
  startAll();
}

void loop() {
  vmLoop();
}

