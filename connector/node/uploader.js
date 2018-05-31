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
    var extension = { linux: 'sh', darwin: 'sh', win32: 'bat' }[os.platform()];
    child_process.exec(
        os.platform() + '-extras/uploaders/microbit.' + extension,
        function (err, stdout, stderr) {
            if (err) {
                onError.call(null, stderr);
            } else {
                onSuccess.call(null, stdout);
            }
        }
    );
};

module.exports = Uploader;
