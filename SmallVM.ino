#include "mem.h"
#include "interp.h"

extern "C" {
  // C function prototypes for tests

  void interpTests1(void);
  void taskTest(void);
}

void setup() {
  Serial.begin(115200);
  hardwareInit();
  memInit(5000); // 5k words = 20k bytes
  printStartMessage("Welcome to uBlocks for Arduino!");
}

void loop() {
    processMessage();
    stepTasks();
}
