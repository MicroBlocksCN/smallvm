#include "../../vm/stickS3Backlight.h"
int main() {
    ledcSetupFails = true;
    stickS3SetBacklight(10);
    assert(ledcAttachCalls == 0 && ledcDuty == -1);
    ledcSetupFails = false;
    stickS3SetBacklight(10);
    assert(ledcDuty == 255 && ledcAttachCalls == 1);
    stickS3SetBacklight(5); assert(ledcDuty == 127);
    stickS3SetBacklight(0); assert(ledcDuty == 0);
    stickS3SetBacklight(-3); assert(ledcDuty == 0);
    stickS3SetBacklight(20); assert(ledcDuty == 255);
    assert(ledcSetupCalls == 2 && ledcAttachCalls == 1);
}
