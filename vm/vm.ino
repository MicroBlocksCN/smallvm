#include "mem.h"
#include "interp.h"

void setup() {
  Serial.begin(115200);
  hardwareInit();
  memInit(5000); // 5k words = 20k bytes
  outputString("Welcome to uBlocks for Arduino!");
}

void loop() {
  vmLoop();
}
