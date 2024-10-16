#!/bin/bash
# Rebuild and update the precompiled binaries.
rm -f *.hex *.bin *.uf2
cd ..
pio run -e microbit
cp .pio/build/microbit/firmware.hex precompiled/vm_microbitV1.hex
pio run -e microbitV2-ble
cp .pio/build/microbitV2-ble/firmware.hex precompiled/vm_microbitV2.hex
pio run -e calliope
cp .pio/build/calliope/firmware.hex precompiled/vm_calliope.hex
pio run -e calliopeV3-ble
cp .pio/build/calliopeV3-ble/firmware.hex precompiled/vm_calliopeV3-ble.hex
pio run -e nodemcu
cp .pio/build/nodemcu/firmware.bin precompiled/vm_nodemcu.bin
pio run -e ed1
cp .pio/build/ed1/firmware.bin precompiled/vm_citilab-ed1.bin
pio run -e m5stack
cp .pio/build/m5stack/firmware.bin precompiled/vm_m5stack.bin
pio run -e esp32
cp .pio/build/esp32/firmware.bin precompiled/vm_esp32.bin
pio run -e cpx
python precompiled/uf2conv.py -c .pio/build/cpx/firmware.bin -o precompiled/vm_circuitplay.uf2
pio run -e cplay52
python precompiled/uf2conv.py -c .pio/build/cplay52/firmware.hex -f 0xADA52840 -o precompiled/vm_cplay52.uf2
pio run -e clue
python precompiled/uf2conv.py -c -f 0xada52840 .pio/build/clue/firmware.hex -o precompiled/vm_clue.uf2
pio run -e pico-w-ble
cp .pio/build/pico-w-ble/firmware.uf2 precompiled/vm_pico_w.uf2
pio run -e pico-ed
cp .pio/build/pico-ed/firmware.uf2 precompiled/vm_pico_ed.uf2
pio run -e wukong2040
cp .pio/build/wukong2040/firmware.uf2 precompiled/vm_wukong2040.uf2
pio run -e databot
cp .pio/build/databot/firmware.bin precompiled/vm_databot.bin

# Copy Linux VMs
cp linux+pi/vm_* precompiled/

# Create micro:bit Universal Hex File
# Make sure we have the proper dep(s) installed
cd precompiled
npm install
node buildUniversalHex.js
rm vm_microbitV1.hex vm_microbitV2.hex
rm vm_calliope.hex vm_calliopeV3-ble.hex

