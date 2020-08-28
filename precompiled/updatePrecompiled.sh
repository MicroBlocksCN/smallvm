#!/bin/bash
# Rebuild and update the precompiled binaries.
rm *.hex *.bin *.uf2
cd ..
pio run -e microbit
cp .pio/build/microbit/firmware.hex precompiled/vm.microbit.hex
pio run -e calliope
cp .pio/build/calliope/firmware.hex precompiled/vm.calliope.hex
pio run -e nodemcu
cp .pio/build/nodemcu/firmware.bin precompiled/vm.nodemcu.bin
pio run -e ed1
cp .pio/build/ed1/firmware.bin precompiled/vm.citilab-ed1.bin
pio run -e m5stack
cp .pio/build/m5stack/firmware.bin precompiled/vm.m5stack.bin
pio run -e m5stick
cp .pio/build/m5stick/firmware.bin precompiled/vm.m5stick.bin
pio run -e m5atom
cp .pio/build/m5atom/firmware.bin precompiled/vm.m5atom.bin
pio run -e esp32
cp .pio/build/esp32/firmware.bin precompiled/vm.esp32.bin
pio run -e cpx
python precompiled/uf2conv.py -c .pio/build/cpx/firmware.bin -o precompiled/vm.circuitplay.uf2
pio run -e cplay52
python precompiled/uf2conv.py -c .pio/build/cplay52/firmware.hex -f 0xADA52840 -o precompiled/vm.cplay52.uf2
pio run -e itsybitsy
python precompiled/uf2conv.py -c .pio/build/itsybitsy/firmware.bin -o precompiled/vm.itsybitsy.uf2
pio run -e clue
python precompiled/uf2conv.py -c -f 0xada52840 .pio/build/clue/firmware.hex -o precompiled/vm.clue.uf2
cd precompiled
