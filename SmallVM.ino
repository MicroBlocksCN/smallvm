#include "mem.h"
#include "interp.h"

extern "C" {
  // Entry points called from C

  void interpTests1(void);
  void putLineSerial(char *s) { Serial.println(s); }
  void putSerial(char *s, int x) { Serial.print(s); }
  int serialAvailable() { return (Serial.available() > 0); }

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

void readAndEvaluate() {
  char header[4];
  char contents[5000];

  int n = Serial.readBytes(header, 4);
  if (n < 4) return; // fail - timed out

  unsigned int count = (header[2] << 8) + header[3];
  if (count > 5000) return; // fail - message too large
  n = Serial.readBytes(contents, count);
  Serial.print(n); Serial.println(" bytes read; Running...");
  runProg((int *) contents);
}

