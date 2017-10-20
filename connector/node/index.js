var Connector,
    WebSocket = require('ws'),
    util = require('util'),
    Board = require('./board.js');

function Connector () {
    this.boards = {};
    this.options = {};
    this.wsServer = null;
    this.socket = null;
    this.init();
};

Connector.prototype.boardAt = function (portName) {
    return this.boards[portName];
};

Connector.prototype.init = function () {
    var myself = this;
    this.parseArgs();

    this.wsServer = new WebSocket.Server({ port: this.options.port || 9999 }),
    this.wsServer.on('connection', function (ws) {
        myself.socket = ws;
        myself.log('websocket client connected');
        myself.socket.on('message', function (message) {
            myself.processMessage(message);
        });
        myself.socket.on('close', function () {
            myself.log('websocket client disconnected');
            myself.socket = null;
        });
    });

    console.log(
        'µBlocks websockets-serial bridge started.\n' +
        'Run me with --help for command line arguments\n' +
        'Debug is ' + (this.options.debugMode ? 'enabled' : 'disabled') + '.\n');
    this.log(
        'Waiting for websockets client to connect at port ' +
        (this.options.port || 9999) + '.'
    );
};

Connector.prototype.parseArgs = function () {
    var myself = this;
    process.argv.forEach(function (val) {
        var option = val.split('=');
        switch (option[0]) {
            case '--help':
            case '-h':
                myself.printHelp(option[1]);
            break;
            case '--debug':
            case '-d':
                myself.options.debugMode = true; 
                break;
            case '--port':
            case '-p':
                myself.options.port = option[1] || 9999;
                break;
        }
    });
};

// Serial Port

Connector.prototype.addBoard = function (portName, connectCallback) {
    var myself = this,
        board;

    this.log('Connecting to board at ' + portName + '...');

    if (this.boardAt(portName)) {
        myself.log(
            'There is already a board connected to port ' + portName + '.\n' +
                'Please disconnect from that port and try again.',
            1 // error log
        );
    } else {
        board = new Board(portName, this.options);
        board.connect(
            connectCallback,
            function (data) { // onData
                if (myself.socket) {
                    myself.log('board sends: ');
                    myself.log(data, 0);
                    myself.socket.send(data);
                } else {
                    myself.log('Socket is not connected', 1);
                } 
            },
            function (err) { // onClose
                myself.log('Board disconnected.', err ? 1 : 0);
                if (err) {
                    myself.log('Starting auto-reconnect loop');
                    board.reconnectLoop();
                } 
            },
            function (err) { myself.log(err, 1); } // onError
        );

        this.boards[portName] = board;
    }
};

Connector.prototype.removeBoard = function (portName, onSuccess, onError) {
    var myself = this;
    this.boardAt(portName).disconnect(
        function () {
            delete myself.boards[portName];
            onSuccess()
        },
        onError
    );
};

Connector.prototype.boardSend = function (portName, arrayBuffer) {
    var board = this.boardAt(portName);
    if (board) {
        this.log('IDE sends: ');
        this.log(arrayBuffer, 0);
        board.send(arrayBuffer);
    } else {
        this.log('Board is not connected', 1);
    }
};

// Message composing

Connector.prototype.sendJsonMessage = function (selector, arguments) {
    var object = { selector: selector, arguments: arguments },
        data = this.stringToByteArray(JSON.stringify(object)),
        array = [0xFB, 0xFF, 0, data.length & 255, data.length >> 8];
    this.log('Sending JSON message to client:');
    this.log(object, 0);
    this.socket.send(array.concat(data));
};

Connector.prototype.stringToByteArray = function (str) {
    return str.split('').map(
        function (char) { return char.charCodeAt(0); }
    );
};

// Message processing

Connector.prototype.processMessage = function (rawData) {
    var array = new Uint8Array(rawData),
        message;
    if (array[1] === 0xFF) {
        // this is an internal JSON message,
        // not supposed to reach the board
        array = array.slice(4);
        message = JSON.parse(String.fromCharCode.apply(null, array.slice(1)));
        this.log('Client sent us a JSON message:');
        this.log(message, 0);
        this.dispatcher[message.selector].call(this, message.arguments);
    } else {
        // TODO We should get the portName somehow, but sending all messages
        //      as JSON would probably slow things down by quite a lot.
        //      For now, we only support one board, although the infrastructure
        //      is there for a future multiboard support.
        this.boardSend(Object.keys(this.boards)[0], rawData);
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
            myself.log('Client requested serial port list.');
            myself.sendJsonMessage('getSerialPortListResponse', [ actualDevices ]);
        });
    },
    serialConnect: function (portName) {
        var myself = this;
        this.addBoard(portName, function (err) {
            myself.log('Client asked me to connect to a board.');
            myself.sendJsonMessage('serialConnectResponse', [ !err ]);
        });
    },
    serialDisconnect: function (portName) {
        var myself = this;
        this.log('Client asked me to disconnect from a board.');
        this.removeBoard(
            portName, 
            // success callback
            function () { 
                myself.sendJsonMessage('serialDisconnectResponse', [ true ]);
            },
            // error callback
            function () {
                myself.sendJsonMessage('serialDisconnectResponse', [ false ]);
            }
        );
    }
};

// Printing and logging

Connector.prototype.log = function (str, code) {
    var color = [
        // code defines the message type
        '\x1b[1m', // data (white)
        '\x1b[31m', // error message (red)
        ];

    if (this.options.debugMode) {
        console.log((color[code] || '\x1b[0m') + util.format(str));
    }
};

Connector.prototype.printHelp = function (topic) {
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
            '-p=[PORT], --port=[PORT]\n' +
            '                   Choose the websockets port. If not defined, it will default\n' +
            '                   to 9999.\n'
       );
    }
    process.exit();
};

new Connector();
