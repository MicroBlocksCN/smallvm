char byteRead;

void setup() {
  Serial.begin(9600);
}

void loop() {
  while (Serial.available() > 0) {
    byteRead = Serial.read();
    Serial.print(byteRead);
  }
}
