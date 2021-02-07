/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// linuxOutputPrims.c - Microblocks 5x5 LED display primitives simulated on an
//                      SDL window
// Bernat Romagosa, February 2021

static OBJ primLightLevel(int argCount, OBJ *args) { return int2obj(0); }

static OBJ primMBDisplayOff(int argCount, OBJ *args) {
	microBitDisplayBits = 0;
	if (useTFT) tftClear();
}

static PrimEntry entries[] = {
	{"lightLevel", primLightLevel},
	{"mbDisplay", primMBDisplay},
	{"mbDisplayOff", primMBDisplayOff},
	{"mbPlot", primMBPlot},
	{"mbUnplot", primMBUnplot},
	{"mbDrawShape", primMBDrawShape},
	{"mbShapeForLetter", primMBShapeForLetter},
	{"neoPixelSend", primNeoPixelSend},
	{"neoPixelSetPin", primNeoPixelSetPin},
};

void addDisplayPrims() {
	addPrimitiveSet("display", sizeof(entries) / sizeof(PrimEntry), entries);
}
