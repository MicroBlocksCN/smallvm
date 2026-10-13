#pragma once
#include <cstdint>
#include <vector>
#include <cassert>
inline void delay(int) {}
struct MockWire {
    uint8_t regs[256] = {};
    std::vector<uint8_t> tx;
    int readReg = 0, writeCount = 0, failReg = -1;
    bool shortRead = false;
    void begin(int sda, int scl) { assert(sda == 47 && scl == 48); }
    void setClock(int hz) { assert(hz == 400000); }
    void setTimeOut(int ms) { assert(ms == 50); }
    void beginTransmission(int address) { assert(address == 0x6e); tx.clear(); }
    void write(uint8_t value) { tx.push_back(value); }
    int endTransmission(bool = true) {
        if (tx[0] == failReg) return 2;
        readReg = tx[0];
        if (tx.size() == 2) { regs[tx[0]] = tx[1]; ++writeCount; }
        return 0;
    }
    int requestFrom(int address, int count) { assert(address == 0x6e && count == 1); return shortRead ? 0 : 1; }
    int read() { return regs[readReg]; }
};
extern MockWire Wire1;
