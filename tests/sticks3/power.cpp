#include "Wire.h"
MockWire Wire1;
#include "../../vm/boards/sticks3/power.h"
int main() {
    Wire1.regs[6] = 0xff;
    Wire1.regs[0x16] = 0xff;
    Wire1.regs[0x13] = 0xff;
    assert(stickS3PowerInit());
    assert(Wire1.regs[6] == 0xf7); // boost off, other power bits preserved
    assert(Wire1.regs[0x16] == 0xcf); // GPIO2 two-bit field, neighbors preserved
    assert(Wire1.regs[0x13] == 0xfb);
    assert(Wire1.regs[0x11] == 4 && Wire1.regs[0x10] == 4);
    for (int reg : {6, 9, 10, 0x16, 0x13, 0x11, 0x10}) {
        Wire1 = MockWire{};
        Wire1.failReg = reg;
        assert(!stickS3PowerInit());
        assert(Wire1.regs[0x10] == 0); // never enable LCD after any failed operation
    }
    Wire1 = MockWire{};
    Wire1.failReg = 6;
    assert(!stickS3PowerInit() && Wire1.writeCount == 0);
    Wire1 = MockWire{};
    Wire1.shortRead = true;
    assert(!stickS3PowerInit() && Wire1.writeCount == 0);
}
