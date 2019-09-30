#!/bin/bash
# Rebuild and update the precompiled binaries.
cd ..
pio run -e microbit
cp .pio/build/microbit/firmware.hex precompiled/vm.ino.BBCmicrobit.hex
pio run -e calliope
cp .pio/build/calliope/firmware.hex precompiled/vm.ino.Calliope.hex
pio run -e nodemcu
cp .pio/build/nodemcu/firmware.bin precompiled/vm.ino.nodemcu.bin
pio run -e ed1
cp .pio/build/ed1/firmware.bin precompiled/vm.ino.citilab-ed1.bin
pio run -e m5stack
cp .pio/build/m5stack/firmware.bin precompiled/vm.ino.m5stack.bin
pio run -e esp32
cp .pio/build/esp32/firmware.bin precompiled/vm.ino.esp32.bin
pio run -e cpx
python precompiled/uf2conv.py -c .pio/build/cpx/firmware.bin -o precompiled/vm.circuitplay.uf2
pio run -e itsybitsy
python precompiled/uf2conv.py -c .pio/build/itsybitsy/firmware.bin -o precompiled/vm.itsybitsy.uf2
cd precompiled
