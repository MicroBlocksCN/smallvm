#include "mem.h"
#include "interp.h"

extern "C" {
  // C function prototypes for tests

  void interpTests1(void);
  void taslTest(void);
}

void setup() {
  Serial.begin(9600);
  hardwareInit();
  memInit(5000); // 5k words = 20k bytes
  printStartMessage("Welcome to uBlocks for Arduino!");
}

void loop() {
    processMessage();
    stepTasks();
}
