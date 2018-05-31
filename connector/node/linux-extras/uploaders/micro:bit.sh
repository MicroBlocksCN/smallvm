#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/. */

# Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

# This will only when there's a single micro:bit connected to this PC.
# We can't match serial devices to their virtual disk drives.

openocd/bin/openocd -d2 -f interface/cmsis-dap.cfg -c "transport select swd;" -f target/nrf51.cfg -c "program ../../../../vms/vm.ino.BBCmicrobit.hex verify reset; shutdown;"
