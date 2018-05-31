#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/. */

# Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

devicePath=`readlink -f /dev/disk/by-label/MICROBIT`
mountPath=`mount | sed -e "s:^$devicePath on \(.*\) type .*:\1:g" | tail -n1`
cp vms/vm.ino.BBCmicrobit.hex $mountPath
