#!/bin/bash
# Rebuild and update the precompiled binaries.
pio run
cp .pio/build/microbit/firmware.hex precompiled/vm.ino.BBCmicrobit.hex 
cp .pio/build/calliope/firmware.hex precompiled/vm.ino.Calliope.hex
cp .pio/build/nodemcu/firmware.bin precompiled/vm.ino.nodemcu.bin
cp .pio/build/ed1/firmware.bin precompiled/vm.ino.citilab-ed1.bin
cp .pio/build/m5stack-grey/firmware.bin precompiled/vm.ino.m5stack-grey.bin
cp .pio/build/m5stack-core/firmware.bin precompiled/vm.ino.m5stack-core.bin
cp .pio/build/esp32/firmware.bin precompiled/vm.ino.esp32.bin
python uf2conv.py -c .pio/build/cpx/firmware.bin -o precompiled/vm.circuitplay.uf2
python uf2conv.py -c .pio/build/itsybitsy/firmware.bin -o precompiled/vm.itsybitsy.uf2
