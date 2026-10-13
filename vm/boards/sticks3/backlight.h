/* MPL 2.0: https://mozilla.org/MPL/2.0/ */
#pragma once
#include <Arduino.h>

// Channels 6/7 share timer3 and are excluded from the VM PWM/servo allocator.
// Tone uses timer0; external PWM and servos use timers1/2.
static void stickS3SetBacklight(int brightness) {
	static bool initialized = false;
	if (!initialized) {
		if (ledcSetup(6, 20000, 8) == 0) return;
		ledcAttachPin(38, 6);
		initialized = true;
	}
	if (brightness < 0) brightness = 0;
	if (brightness > 10) brightness = 10;
	ledcWrite(6, brightness * 255 / 10);
}
