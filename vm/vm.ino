#include "mem.h"
#include "interp.h"
#include "persist.h"

void setup() {
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
