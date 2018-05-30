/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

var Uploader,
    child_process = require('child_process'),
    os = require('os');

function Uploader (boardType) {
    this.boardType = boardType;
};

Uploader.prototype.upload = function (onSuccess, onError) {
    Uploader.factory[this.boardType](onSuccess, onError);
};

// VM uploader factory for different boards
Uploader.factory = {};
Uploader.factory['micro:bit'] = function (onSuccess, onError) {
    if (os.platform() === 'linux') {
        // find out where the micro:bit virtual drive is mounted
        child_process.exec(
            // get the symlink destination (will be a /dev/sdX path)
            'readlink -f /dev/disk/by-label/MICROBIT',
            function (err, diskPath, stderr) {
                if (!err) {
                    // find out the mount point for /dev/sdX
                    child_process.exec(
                        'mount',
                        function (err, mounts) {
                            diskPath = diskPath.replace(/\//g, '\\/');
                            var regex =
                                    new RegExp(
                                        '^' + diskPath.replace('\n','') + ' on (.*) type',
                                        'gm'
                                    ),
                                fsPath = regex.exec(mounts)[1];
                            child_process.exec(
                                'cp vms/vm.ino.BBCmicrobit.hex ' + fsPath,
                                function (err, stdout, stderr) {
                                    if (err) {
                                        onError.call(null, stderr);
                                    } else {
                                        onSuccess.call(null);
                                    }
                                }
                            );
                        }
                    );
                }
            }
        );
    }
};

module.exports = Uploader;
