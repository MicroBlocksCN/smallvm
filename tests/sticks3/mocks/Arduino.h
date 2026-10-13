#pragma once
#include <cstdint>
#include <cmath>
#include <cassert>
static uint32_t testMillis = 0;
inline uint32_t millis() { return testMillis; }
static int ledcSetupCalls = 0, ledcAttachCalls = 0, ledcDuty = -1;
static bool ledcSetupFails = false;
inline double ledcSetup(int channel, double hz, int bits) {
    assert(channel == 6 && hz == 20000 && bits == 8);
    ++ledcSetupCalls;
    return ledcSetupFails ? 0 : hz;
}
inline void ledcAttachPin(int pin, int channel) {
    assert(pin == 38 && channel == 6);
    ++ledcAttachCalls;
}
inline void ledcWrite(int channel, int duty) { assert(channel == 6); ledcDuty = duty; }
