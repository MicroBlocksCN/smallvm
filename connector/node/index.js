/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

var Connector,
    connector,
    Board,
    WebSocket = require('ws'),
    util = require('util'),
    fs = require('fs'),
    options = { placeTrayIcon: true },
    SysTray = require('systray').default,
    systray,
    trayItems,
    trayActions;

// ===== Board ===== //

function Board (portName) {
    this.portName = portName;
    this.serial = null;
    this.reconnectLoopId = null;
    this.onData = nop;
    this.onClose = nop;
    this.onError = nop;
};

Board.SerialPort = require('serialport');

Board.prototype.connect = function (connectCallback, onData, onClose, onError) {
    var myself = this;

    this.serial = new Board.SerialPort(
        this.portName,
        { baudRate: 115200 },
        connectCallback
    );

    this.onData = onData;
    this.onClose = function (err) { onClose.call(myself, err); };
    this.onError = onError;

    this.serial.on('data', this.onData);
    this.serial.on('close', this.onClose);
    this.serial.on('error', this.onError);
};

Board.prototype.disconnect = function (onSuccess, onError) {
    try {
        this.serial.close();
        this.portName = null;
        onSuccess();
    } catch (err) {
        onError();
    }
};

Board.prototype.reconnect = function (onSuccess) {
    var myself = this;
    this.connect(
        function (err) {
            if (!err) {
                log('Reconnection success!');
                if (systray) { systray.setBoardStatus(true); }
                clearInterval(myself.reconnectLoopId);
                myself.reconnectLoopId = null;
                onSuccess.call(myself);
            }
        },
        this.onData,
        this.onClose,
        this.onError
    );
};

Board.prototype.reconnectLoop = function (onSuccess) {
    var myself = this;
    if (!this.reconnectLoopId) {
        this.reconnectLoopId = setInterval(function () { myself.reconnect(onSuccess) }, 100);
    }
};

Board.prototype.send = function (arrayBuffer) {
    this.serial.write(arrayBuffer);
};


// ===== Connector ===== //

function Connector () {
    this.boards = {};
    this.wsServer = null;
    this.socket = null;
    this.init();
};

Connector.prototype.boardAt = function (portName) {
    return this.boards[portName];
};

Connector.prototype.init = function () {
    var myself = this;

    this.wsServer = new WebSocket.Server({ port: options.port || 9999 }),
    this.wsServer.on('connection', function (ws) {
        myself.socket = ws;
        log('Websocket client connected');
        if (systray) {
            systray.linked();
            systray.setClientStatus(true);
        }
        myself.socket.on('message', function (jsonData) {
            var json = JSON.parse(jsonData);
            myself.processMessage(json.portPath, json.message);
        });
        myself.socket.on('close', function () {
            log('Websocket client disconnected');
            if (systray) {
                systray.unlinked();
                systray.setClientStatus(false);
            }
            myself.socket = null;
        });
    });

    if (!options.silent) {
        console.log(
            'µBlocks websockets-serial bridge started.\n' +
            'Run me with --help for command line arguments\n' +
            'Debug is ' + (options.debugMode ? 'enabled' : 'disabled') + '.\n');
    }
    log(
        'Waiting for websockets client to connect at port ' +
        (options.port || 9999) + '.'
    );
};

// Serial Port

Connector.prototype.addBoard = function (portName, connectCallback) {
    var myself = this;

    if (this.boardAt(portName)) {
        log('There was a board already connected to this port. I\'m reusing it.');
        connectCallback.call(this, false); // is there an error?
        return;
    }

    log('Connecting to board at ' + portName + '...');

    function onData (data) {
        if (myself.socket) {
            log('Board sends from ' + portName + ' : ');
            log(data, 0);
            myself.socket.send(data);
        } else {
            log('Socket is not connected', 1);
        }
    };

    function onClose (err) {
        log('Board disconnected.', err ? 1 : 0);
        if (err) {
            myself.sendJsonMessage('boardUnplugged', [ this.portName ]);
            if (systray) { systray.setBoardStatus(false); }
            log('Starting auto-reconnect loop');
            this.reconnectLoop(function () {
                myself.sendJsonMessage('boardReconnected', [ this.portName ]);
            });
        }
    };

    function onError (err) {
        log(err, 1);
    };

    board = new Board(portName);
    board.connect(
        connectCallback,
        onData,
        onClose,
        onError
    );

    this.boards[portName] = board;
};

Connector.prototype.removeBoard = function (portName, onSuccess, onError) {
    var myself = this,
        board = this.boardAt(portName);
    if (board) {
        board.disconnect(
            function () {
                delete myself.boards[portName];
                onSuccess();
            },
            onError
        );
    }
};

Connector.prototype.boardSend = function (portName, arrayBuffer) {
    var board = this.boardAt(portName);
    if (board) {
        log('IDE sends to ' + portName + ': ');
        log(arrayBuffer, 0);
        board.send(arrayBuffer);
    } else {
        log('Board is not connected', 1);
    }
};

// Message composing

Connector.prototype.sendJsonMessage = function (selector, arguments) {
    var object = { selector: selector, arguments: arguments },
        data = this.stringToByteArray(JSON.stringify(object)),
        array = [0xFB, 0xFF, 0, data.length & 255, data.length >> 8];
    log('Sending JSON message to client:');
    log(object, 0);
    this.socket.send(array.concat(data));
};

Connector.prototype.stringToByteArray = function (str) {
    return str.split('').map(
        function (char) { return char.charCodeAt(0); }
    );
};

// Message processing

Connector.prototype.processMessage = function (portName, rawData) {
    var array = new Uint8Array(rawData),
        message;
    if (array[1] === 0xFF) {
        // this is an internal JSON message,
        // not supposed to reach the board
        array = array.slice(4);
        message = JSON.parse(String.fromCharCode.apply(null, array.slice(1)));
        log('Client sent us a JSON message:');
        log(message, 0);
        this.dispatcher[message.selector].call(this, message.arguments);
    } else {
        this.boardSend(portName, rawData);
    }
};

Connector.prototype.dispatcher = {
    getSerialPortList: function () {
        var myself = this;
        Board.SerialPort.list().then(function (devices) {
            var actualDevices = [];
            devices.forEach(function (device) {
                if (device.vendorId) {
                    actualDevices.push({
                        path: device.comName,
                        displayName: device.manufacturer
                    });
                }
            });
            if (options.tty) {
                actualDevices.push({ path: options.tty, displayName: 'Linux TTY Console' })
            }
            log('Client requested serial port list.');
            myself.sendJsonMessage('getSerialPortListResponse', [ actualDevices ]);
        });
    },
    serialConnect: function (portName) {
        var myself = this;
        this.addBoard(portName, function (err) {
            log('Client asked me to connect to a board.');
            if (systray && !err) { systray.setBoardStatus(true); }
            myself.sendJsonMessage('serialConnectResponse', [ !err, portName ]);
        });
    },
    serialDisconnect: function (portName) {
        var myself = this;
        log('Client asked me to disconnect from a board.');
        this.removeBoard(
            portName,
            // success callback
            function () {
                if (systray) { systray.setBoardStatus(false); }
                myself.sendJsonMessage('serialDisconnectResponse', [ true, portName ]);
            },
            // error callback
            function () {
                myself.sendJsonMessage('serialDisconnectResponse', [ false, portName ]);
            }
        );
    }
};


// ==== Global utils ==== //

log = function (str, code) {
    var color = [
        // code defines the message type
        '\x1b[1m', // data (white)
        '\x1b[31m', // error message (red)
        ];

    if (options.debugMode || (options.silent && code === 1)) {
        console.log((color[code] || '\x1b[0m') + util.format(str));
    }
};

printHelp = function (topic) {
    switch (topic) {
        case 'protocol':
            console.log('The µBlocks communications protocol');
            break;
        default:
            console.log(
                'Usage: ./start.sh [OPTION]…\n' +
                '       node index.js [OPTION]…\n' +
                'The µBlocks websockets-serial bridge enables communications between any device\n' +
                'with a µBlocks virtual machine and a µBlocks client. Communication to and from\n' +
                'the device is handled via serial port, whereas the client is interfaced via\n' +
                'websockets. To learn more about the µBlocks communications protocol (only\n' +
                'relevant to developers) run me with the --help=protocol option\n\n' +

                '-h, --help=TOPIC   Print this message and exit, or print information about\n' +
                '                   TOPIC, if specified. Possible topics are: protocol\n' +
                '-d, --debug        Set debug (verbose) mode.\n' +
                '-n, --no-tray      Do not place an icon in the system tray.\n' +
                '-s, --silent       Be silent except for errors.\n' +
                '-p=[PORT], --port=[PORT]\n' +
                '                   Choose the websockets port. If not defined, it will default\n' +
                '                   to 9999.\n' +
                '-t=[TTY], --tty=[TTY]\n' +
                '                   Add a GNU/Linux console TTY to the serial port list.\n' +
                '                   Ex. --tty=/dev/pts/4'
            );

    }
    process.exit();
};

function nop () {};


// ==== Command Line Parameters ==== //

process.argv.forEach(function (val) {
    var option = val.split('=');
    switch (option[0]) {
        case '--help':
        case '-h':
            printHelp(option[1]);
            break;
        case '--debug':
        case '-d':
            options.debugMode = true;
            break;
        case '--port':
        case '-p':
            options.port = option[1] || 9999;
            break;
        case '--no-tray':
        case '-n':
            options.placeTrayIcon = false;
            break;
        case '--tty':
        case '-t':
            options.tty = option[1];
            break;
        case '--silent':
        case '-s':
            options.silent = true;
            break;
    }
});

if (options.tty) {
    // If we do it inside the previous forEach we need to pass the -d option before the
    // tty one, else this message won't show up
    log('Added virtual serial port attached to GNU/Linux terminal ' + options.tty);
}


// ==== System Tray Icon ==== //

if (options.placeTrayIcon) {
    fs.readFile(
        'icons/unlinked.b64',
        'utf8',
        function (err, icon) {
            if (!err) {
                log('Placing system tray icon');
                systray = new SysTray({
                    debug: options.debugMode,
                    menu: {
                        icon: icon,
                        items: trayItems
                    }
                });

                systray.onClick(function (action) {
                    trayActions[action.item.title].call(systray);
                });

                systray.linked = function () {
                    this.sendAction({
                        type: 'update-menu',
                        menu: {
                            icon: fs.readFileSync('icons/linked.b64', 'utf8'),
                            items: trayItems
                        }
                    });
                };

                systray.unlinked = function () {
                    this.sendAction({
                        type: 'update-menu',
                        menu: {
                            icon: fs.readFileSync('icons/unlinked.b64', 'utf8'),
                            items: trayItems
                        }
                    });
                };

                systray.setStatus = function (status, itemIndex, checked) {
                    this.sendAction({
                        type: 'update-item',
                        item: {
                            title: status,
                            enabled: false,
                            checked: checked || false
                        },
                        seq_id: itemIndex
                    });
                };

                systray.setClientStatus = function (linked) {
                    this.setStatus((linked ? '' : 'not ') + 'linked to IDE', 0, linked);
                };

                systray.setBoardStatus = function (linked) {
                    this.setStatus((linked ? '' : 'not ') + 'linked to device', 1, linked);
                };

            } else {
                log('Failed to place system tray icon', 1);
                log(err);
                throw(err);
            }
        }
    );

    trayItems = [
        {
            title: 'not linked to IDE',
            enabled: false,
            checked: false
        },
        {
            title: 'not linked to device',
            enabled: false,
            checked: false
        },
        {
            title: 'Quit',
            tooltip: 'stop the connector',
            enabled: true,
        }
    ];

    trayActions = {
        'Quit':
            function () {
                log('Stopping connector at user\'s request');
                this.kill();
            }
    };
} else {
    log('Will not place system tray icon at users\'s request');
}


// ==== Connector Startup ==== //

// Set the process name to ublocks
process.title = 'ublocks';

// Start the connector
connector = new Connector();
