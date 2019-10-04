#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/. */

# Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

# Find out the Serial ID for the device connected to $1
# sed's ;t;d makes sure we only print the matching line
serialId=`udevadm info --name=$1 | sed -e "s/.*SERIAL_SHORT=\(.*\)/\1/g;t;d"`

# If serialId is not found, openocd will resort to the first cmsis-dap interface it finds
openocd/bin/openocd -d2 -c "interface cmsis-dap; cmsis_dap_serial $serialId" -c "transport select swd;" -f target/nrf51.cfg -c "program ../../../../vms/vm.ino.BBCmicrobit.hex verify reset; shutdown;"
