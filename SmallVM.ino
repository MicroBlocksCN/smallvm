#include "mem.h"
#include "interp.h"

extern "C" {
  // Entry points called from C

  void interpTests1(void);
  int microsecs() { return (int) micros; }
  int millisecs() { return (int) millis; }
  void putSerial(char *s) { Serial.print(s); }
  int readBytes(uint8 *buf, int count) { return Serial.readBytes(buf, count); }
  int writeBytes(uint8 *buf, int count) { return Serial.writeBytes(buf, count);
}

void setup() {
  // put your setup code here, to run once:
  pinMode(USER1_BUTTON, INPUT);
  pinMode(PIN_LED, OUTPUT);
  Serial.begin(9600);

  Serial.println("Starting...");
  memInit(5000); // 5k words = 20k bytes
//  interpTests1();
}

void loop() {
  // put your main code here, to run repeatedly:

  if (Serial.available() > 0) {
    readAndEvaluate();
    Serial.println("\r\nuBlocks>");
  }
}

static uint8 nextChunkIndex = 0;

static void runProg(int* prog, int byteCount) {
  storeCodeChunk(nextChunkIndex, 1, byteCount, (uint8 *) prog);
  startTaskForChunk(nextChunkIndex++);
  runTasksUntilDone();
}

void readAndEvaluate() {
  char header[4];
  char contents[1000];

  int n = Serial.readBytes(header, 4);
  if (n < 4) return; // fail - timed out

  unsigned int count = (header[2] << 8) + header[3];
  if (count > 5000) return; // fail - message too large
  n = Serial.readBytes(contents, count);
  Serial.print(n); Serial.println(" bytes read; Running...");
  runProg((int *) contents, count);
}
