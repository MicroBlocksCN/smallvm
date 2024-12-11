/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

#include "mem.h"
#include "interp.h"
#include "persist.h"

#if defined(ICBRICKS)
#include "ICBricks/ICBricks.h"
#endif

void setup()
{
#if defined(ICBRICKS)
  	// 将esp32设置为其支持的最大频率240Mhz
  	//setCpuFrequencyMhz(240);
	ICBricks_Initializ();

	// 等到开机
	ICBricks_WaitForPowerState(true);
#endif
	memInit();
	primsInit();
	hardwareInit();
	outputString((char *) "Welcome to MicroBlocks!");
	restoreScripts();
	if (BLE_isEnabled()) BLE_start();
	startAll();
}

void loop() {
	vmLoop();
}
