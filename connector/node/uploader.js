/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

var Uploader,
    child_process = require('child_process'),
    os = require('os');

function Uploader (portName, boardType) {
    this.portName = portName;
    this.boardType = boardType;
};

Uploader.boardTypes = [
    {
        boardType: 'micro:bit',
        manufacturer: 'ARM',
        vendorId: '0d28',
        productId: 'DAPLink CMSIS-DAP'
    },
    {
        // WeMos D1
        boardType: 'ESP8266',
        manufacturer: '1a86',
        vendorId: '1a86',
        productId: 'USB2.0-Serial'
    },
    {
        // NodeMCU
        boardType: 'ESP8266',
        manufacturer: 'Silicon Labs',
        vendorId: '10c4',
        productId: 'CP2102 USB to UART Bridge Controller'
    },
    {
        // M0 clone
        boardType: 'M0',
        manufacturer: 'Unknown',
        vendorId: '2a03',
        productId: 'Arduino M0'
    },
    {
        boardType: 'Due',
        manufacturer: 'Arduino LLC',
        vendorId: '2341',
        productId: 'Arduino Due'
    },
    {
        boardType: 'Trinket M0',
        manufacturer: 'Adafruit Industries',
        vendorId: '239a',
        productId: 'Trinket M0'
    },
    {
        boardType: 'CircuitPlayground',
        manufacturer: 'Adafruit',
        vendorId: '239a',
        productId: 'Circuit Playground Express'
    }
];

Uploader.prototype.detectBoardType = function (onSuccess, onError, errorMessage) {
    // A non infallible attempt at detecting the board type by looking at the
    // serial port vendor ID, and product IDs and manufacturer name.
    // Different boards sharing the same serial chip will collide, and clones
    // that use a different serial chip from the original will not be properly
    // detected.
    var SerialPort = require('serialport'),
        boardType,
        myself = this;

    if (this.portName) {
        SerialPort.list().then(function (ports) {
            var port = ports.find(function (eachPort) {
                return eachPort.comName = myself.portName;
            });
            // use to find out about serial port manufacturer, vendorId and
            // productId for unlisted boards
            // console.log(port);
            if (port) {
                Uploader.boardTypes.forEach(
                    function (eachDescriptor) {
                        if (port.manufacturer === eachDescriptor.manufacturer &&
                                port.vendorId === eachDescriptor.vendorId &&
                                port.productId === eachDescriptor.productId) {
                            myself.boardType = eachDescriptor.boardType;
                            onSuccess.call(myself);
                            return;
                        }
                    }
                );
            }
            if (!myself.boardType) {
                // Could not find a matching manufacturer, vendorId and productId
                // for this board.
                onError.call(myself, errorMessage);
            }
        });
    }
};


Uploader.prototype.upload = function (onSuccess, onError) {
    var myself = this,
        extension = { linux: 'sh', darwin: 'sh', win32: 'bat' }[os.platform()];

    if (!this.boardType) {
        this.detectBoardType(
            function() { doUpload(onSuccess, onError); },
            onError,
            'Could not detect board type.\nPlease upload the VM manually.'
        );
    } else {
        doUpload();
    }

    function doUpload () {
        // os.platform() returns either linux, darwin or win32
        // we keep the uploader scripts in [os]-extras/uploaders/[board]
        child_process.exec(
            './' + myself.boardType + '.' + extension + ' ' + myself.portName,
            { cwd: os.platform() + '-extras/uploaders' },
            function (err, stdout, stderr) {
                if (err) {
                    onError.call(null, stderr || stdout);
                } else {
                    onSuccess.call(null, stdout);
                }
            }
        );
    }
};

module.exports = Uploader;
