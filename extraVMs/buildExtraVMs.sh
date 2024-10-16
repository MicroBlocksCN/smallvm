#!/bin/bash
# Rebuild and update the precompiled binaries.
rm -f *.hex *.bin *.uf2
cd ..

pio run -e itsybitsy
python precompiled/uf2conv.py -c .pio/build/itsybitsy/firmware.bin -o extraVMs/vm_itsybitsy.uf2
pio run -e metroM0
python precompiled/uf2conv.py -c .pio/build/metroM0/firmware.bin -o extraVMs/vm_metroM0.uf2
pio run -e mbits
cp .pio/build/mbits/firmware.bin extraVMs/vm_mbits.bin
pio run -e pico-xrp
cp .pio/build/pico-xrp/firmware.uf2 extraVMs/vm_pico_xrp.uf2
pio run -e makerport
python precompiled/uf2conv.py -c .pio/build/makerport/firmware.bin -o extraVMs/vm_makerport_v1.uf2
pio run -e makerportV2
python precompiled/uf2conv.py -c .pio/build/makerportV2/firmware.bin -o extraVMs/vm_makerport_v2.uf2
pio run -e makerportV3
python precompiled/uf2conv.py -c .pio/build/makerportV3/firmware.bin -o extraVMs/vm_makerport_v3.uf2
pio run -e m5atom
cp .pio/build/m5atom/firmware.bin extraVMs/vm_m5atom.bin
pio run -e m5atom-lite
cp .pio/build/m5atom-lite/firmware.bin extraVMs/vm_m5atom_lite.bin

pio run -e esp32-s2
cp .pio/build/esp32-s2/firmware.bin extraVMs/vm_esp32-s2.bin
pio run -e esp32-s3
cp .pio/build/esp32-s3/firmware.bin extraVMs/vm_esp32-s3.bin
pio run -e esp32-c3
cp .pio/build/esp32-c3/firmware.bin extraVMs/vm_esp32-c3.bin
pio run -e freenoveCamera
cp .pio/build/freenoveCamera/firmware.bin extraVMs/vm_freenoveCamera.bin

pio run -e gizmo-mechatronics
cp .pio/build/gizmo-mechatronics/firmware.uf2 extraVMs/vm_gizmo_mechatronics.uf2
