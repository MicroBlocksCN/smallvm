#!/bin/bash
# Rebuild and update the precompiled binaries.

#rm *.hex *.bin *.uf2
# run this script in parent folder
cd ..

# make a new, empty precompiled folder
rm -r precompiled
mkdir precompiled

pio run -e calliope
cp .pio/build/calliope/firmware.hex precompiled/vm_calliope.hex
pio run -e nodemcu
cp .pio/build/nodemcu/firmware.bin precompiled/vm_nodemcu.bin
pio run -e ed1
cp .pio/build/ed1/firmware.bin precompiled/vm_citilab-ed1.bin
pio run -e m5stack
cp .pio/build/m5stack/firmware.bin precompiled/vm_m5stack.bin
pio run -e esp32
cp .pio/build/esp32/firmware.bin precompiled/vm_esp32.bin
pio run -e cpx
python precompiledBuilder/uf2conv.py -c .pio/build/cpx/firmware.bin -o precompiled/vm_circuitplay.uf2
pio run -e cplay52
python precompiledBuilder/uf2conv.py -c .pio/build/cplay52/firmware.hex -f 0xADA52840 -o precompiled/vm_cplay52.uf2
pio run -e clue
python precompiledBuilder/uf2conv.py -c -f 0xada52840 .pio/build/clue/firmware.hex -o precompiled/vm_clue.uf2
#pio run -e itsybitsy
#python precompiledBuilder/uf2conv.py -c .pio/build/itsybitsy/firmware.bin -o precompiled/vm_itsybitsy.uf2
pio run -e metroM0
python precompiledBuilder/uf2conv.py -c .pio/build/metroM0/firmware.bin -o precompiled/vm_metroM0.uf2
pio run -e pico
cp .pio/build/pico/firmware.uf2 precompiled/vm_pico.uf2
pio run -e pico-w
cp .pio/build/pico-w/firmware.uf2 precompiled/vm_pico_w.uf2
pio run -e pico-ed
cp .pio/build/pico-ed/firmware.uf2 precompiled/vm_pico_ed.uf2
pio run -e wukong2040
cp .pio/build/wukong2040/firmware.uf2 precompiled/vm_wukong2040.uf2
pio run -e databot
cp .pio/build/databot/firmware.bin precompiled/vm_databot.bin
pio run -e mbits
cp .pio/build/mbits/firmware.bin precompiled/vm_mbits.bin

# Copy Linux VMs
cp linux+pi/vm_* precompiled/

# build micro:bit V1 and V2 binaries an copy into builder folder for processing
pio run -e microbit
cp .pio/build/microbit/firmware.hex precompiledBuilder/vm_microbitV1.hex
pio run -e microbitV2
cp .pio/build/microbitV2/firmware.hex precompiledBuilder/vm_microbitV2.hex

# Create micro:bit universal hex file
# First, make sure we have the proper dep(s) installed
cd precompiledBuilder
npm install
# Build the universal hex file
node buildUniversalHex.js
# Move the universal hex file into precompiled and remove the V1 and V2 binaries
mv vm_microbit-universal.hex ../precompiled
rm vm_microbitV1.hex vm_microbitV2.hex
