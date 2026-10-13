#include "Arduino.h"
#include "Wire.h"
MockWire Wire1;
static int accelStarted = false;
static const int i2cTransferFailed = 35;
static int errorCode = 0;
static void fail(int error) { errorCode = error; }
#include "../../vm/boards/sticks3/imu.h"
static void reset() {
    stickIMU = BMI270{};
    stickIMUReady = stickIMURetryPending = false;
    stickRequestedRange = accelStarted = errorCode = 0;
    testMillis = 0;
}
int main() {
    reset();
    assert(readAcceleration(1) == 200 && readAcceleration(3) == -100);
    assert(readAcceleration(5) == -100 && readTemperature() == -3);
    assert(stickIMU.beginCalls == 1 && accelStarted && !errorCode);
    for (int range = 0; range < 4; ++range) {
        setAccelRange(range);
        assert(stickIMU.range == range);
        assert(readAcceleration(1) == (int) roundf(200.0f / (1 << range)));
    }
    // Initialization/config-read/config-write failures are rate limited, then recover.
    for (int stage = 0; stage < 3; ++stage) {
        reset();
        int *failure = stage == 0 ? &stickIMU.beginError :
            stage == 1 ? &stickIMU.configReadError : &stickIMU.configWriteError;
        *failure = -1;
        readAcceleration(1);
        assert(errorCode == i2cTransferFailed && !accelStarted && !stickIMUReady);
        *failure = 0;
        testMillis = 999;
        readAcceleration(1);
        assert(stickIMU.beginCalls == 1);
        testMillis = 1000; errorCode = 0;
        assert(readAcceleration(1) == 200 && !errorCode && accelStarted);
    }
    // Failed range write must never return values using inconsistent scale.
    reset(); readAcceleration(1);
    stickIMU.configWriteError = -1;
    setAccelRange(3);
    assert(errorCode == i2cTransferFailed && !stickIMUReady && !accelStarted);
    stickIMU.configWriteError = 0;
    testMillis = 1000; errorCode = 0;
    assert(readAcceleration(1) == 25 && stickIMU.range == 3 && !errorCode);
    // Sensor/temperature read failures use VM errors and permit later recovery.
    stickIMU.sampleError = -1;
    readAcceleration(1);
    assert(errorCode == i2cTransferFailed && !stickIMUReady);
    stickIMU.sampleError = 0;
    testMillis += 1000; errorCode = 0;
    assert(readAcceleration(1) == 25 && !errorCode);
    stickIMU.tempError = -1;
    readTemperature();
    assert(errorCode == i2cTransferFailed && !stickIMUReady);
    stickIMU.tempError = 0;
    testMillis += 1000; errorCode = 0;
    assert(readTemperature() == -3 && !errorCode);
    // millis() wrapping must not bypass the retry delay or prevent recovery.
    reset(); testMillis = UINT32_MAX - 499;
    stickIMU.beginError = -1; readAcceleration(1);
    stickIMU.beginError = 0; testMillis = 499; readAcceleration(1);
    assert(stickIMU.beginCalls == 1);
    testMillis = 500; errorCode = 0;
    assert(readAcceleration(1) == 200 && !errorCode);
}
