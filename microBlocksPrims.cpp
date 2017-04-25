// microBlocksPrims.c - Microblocks primitives
// John Maloney, April 2017

#include <stdio.h>
#include <string.h>

#include "mem.h"
#include "interp.h"

// Platform specific primitives

#ifdef ARDUINO
#include "arduino.h"

static const int analogPin[] = {A0, A1, A2, A3, A4, A5};

OBJ primAnalogRead(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum > 5)) return int2obj(0);
	int pin = analogPin[pinNum];
	pinMode(pin, INPUT);
	return int2obj(analogRead(pin));
}

OBJ primAnalogWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	int value = obj2int(args[1]);
	if ((pinNum < 0) || (pinNum > 5)) return nilObj;
	int pin = analogPin[pinNum];
	pinMode(pin, OUTPUT);
	analogWrite(pin, value);
	return nilObj;
}

OBJ primDigitalRead(OBJ *args) {
	int pinNum = obj2int(args[0]);
	if ((pinNum < 0) || (pinNum > 15)) return falseObj;
	pinMode(pinNum, INPUT);
	return (HIGH == digitalRead(pinNum)) ? trueObj : falseObj;
}

OBJ primDigitalWrite(OBJ *args) {
	int pinNum = obj2int(args[0]);
	int value = (args[1] == trueObj) ? HIGH : LOW;
	if ((pinNum < 0) || (pinNum > 15)) return nilObj;
	pinMode(pinNum, OUTPUT);
	digitalWrite(pinNum, value);
	return nilObj;
}

OBJ primMicros(OBJ *args) {
	return int2obj(micros());
}

OBJ primMillis(OBJ *args) {
	return int2obj(millis());
}

OBJ primPeek(OBJ *args) {
	if (!isInt(args[0])) return int2obj(0);
	int *addr = (int *) obj2int(args[0]);
	return int2obj(*addr);
}

OBJ primPoke(OBJ *args) {
	if (!isInt(args[0])) return nilObj;
	int *addr = (int *) obj2int(args[0]);
	*addr = obj2int(args[1]);
	return nilObj;
}

#else

// stubs for testing on laptop
OBJ primAnalogRead(OBJ *args) { return int2obj(0); }
OBJ primAnalogWrite(OBJ *args) { return nilObj; }
OBJ primDigitalRead(OBJ *args) { return falseObj; }
OBJ primDigitalWrite(OBJ *args) { return nilObj; }
OBJ primMicros(OBJ *args) { return int2obj(0); }
OBJ primMillis(OBJ *args) { return int2obj(0); }
OBJ primPeek(OBJ *args) { return int2obj(0); }
OBJ primPoke(OBJ *args) { return nilObj; }

#endif
