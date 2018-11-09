#!/bin/bash
# Update the precompile binaries.
# You must first use the Arduino IDE to export the compiled binary for each board.

cp vm/vm.ino.BBCmicrobit.hex precompiled
cp vm/vm.ino.CalliopeMini.hex precompiled/vm.ino.Calliope.hex
cp vm/vm.ino.nodemcu.bin precompiled
cp vm/vm.ino.lolin32.bin precompiled/vm.ino.esp32.bin
python uf2conv.py -c vm/vm.ino.circuitplay.bin -o precompiled/vm.circuitplay.uf2
python uf2conv.py -c vm/vm.ino.itsybitsy_m0.bin -o precompiled/vm.itsybitsy.uf2
