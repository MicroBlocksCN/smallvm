#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/. */

# Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

esptool/esptool -vv -cd nodemcu -cb 115200 -cp "$1" -ca 0x00000 -cf "../../vms/vm.ino.nodemcu.bin"
