#!/bin/sh
# Build Boardie: MicroBlocks VM that runs in a web browser

emcc -std=gnu99 -Wall -O3 \
	-Wno-shift-negative-value -Wno-format \
	-D EMSCRIPTEN \
	-D GNUBLOCKS \
	-s TOTAL_MEMORY=268435456 \
	-s ALLOW_MEMORY_GROWTH=0 \
	--memory-init-file 0 \
	-s WASM=1 \
	-I ../vm \
	boardie.c ../vm/*.c \
	boardieIOPrims.c boardieOutputPrims.c boardieTftPrims.c \
	-o run_boardie.html
