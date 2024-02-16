#!/bin/sh
# Build Boardie: MicroBlocks VM that runs in a web browser

emcc -std=gnu99 -Wall -O3 \
	-Wno-shift-negative-value -Wno-format \
	-D EMSCRIPTEN \
	-D GNUBLOCKS \
	-s TOTAL_MEMORY=268435456 \
	-s ALLOW_MEMORY_GROWTH=0 \
	--closure 1 \
	--memory-init-file 0 \
	-s WASM=1 \
	-sEXPORTED_FUNCTIONS=_main,_getScripts,_taskSleep \
	-I ../vm \
	boardie.c ../vm/*.c \
	boardieIOPrims.c boardieOutputPrims.c boardieTftPrims.c boardieNetPrims.c \
	boardieSensorPrims.c boardieFilePrims.c boardieSerialPrims.c \
	-o run_boardie.js

cp font/adafruit_font.ttf ../chromeApp/webapp/boardie
cp webfiles/* ../chromeApp/webapp/boardie
cp boardie.js ../chromeApp/webapp/boardie
mv run_boardie.js ../chromeApp/webapp/boardie
mv run_boardie.wasm ../chromeApp/webapp/boardie
