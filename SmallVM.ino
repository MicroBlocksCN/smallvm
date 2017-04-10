#include "mem.h"
#include "interp.h"

void interpTests1(void);

void setup() {
  // put your setup code here, to run once:
  Serial.begin(9600);
  Serial.println("Starting...");
  memInit(5000); // 5k words = 20k bytes
  interpTests1();
}

void loop() {
  // put your main code here, to run repeatedly:

}
