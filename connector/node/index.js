var options = {},
    WebSocket = require('ws'),
    SerialPort = require('serialport'),
    wsServer,
    serial,
    socket,
    util = require('util');

function serialConnect (portName, callback) {
    log('Connecting to board at ' + portName + '...');

    serial = new SerialPort(
        portName, 
        { baudRate: 115200 },
        callback
    );

    serial.on('data', function (data) {
        if (socket) {
            log('board sends: ');
            log(data, 0);
            socket.send(data);
        } else {
            log('Socket is not connected', 1);
        } 
    });

    serial.on('close', function (err) {
        log('Board disconnected.', err ? 1 : 0);
        if (err) {
            // Not yet supporting multiple boards
            // log('Starting auto-reconnect loop');
            //reconnect(boardId);
        }
    });
};

function serialDisconnect (boardId, onSuccess, onError) {
    // Not yet supporting multiple boards
    serial.close(onError);
    onSuccess();
};

function serialSend (arrayBuffer) {
    if (serial) {
        log('IDE sends: ');
        log(arrayBuffer, 0);
        serial.write(arrayBuffer);
    } else {
        log('Board is not connected', 1);
    }
};

// Message composing

function sendJsonMessage (selector, arguments) {
    var object = { selector: selector, arguments: arguments },
        data = stringToByteArray(JSON.stringify(object)),
        array = [0xFB, 0xFF, 0, data.length & 255, data.length >> 8];
    log('Sending JSON message to client:');
    log(object, 0);
    socket.send(array.concat(data));
};

// Message processing

function processMessage (rawData) {
    var array = new Uint8Array(rawData),
        message;
    if (array[1] === 0xFF) {
        // this is an internal JSON message,
        // not supposed to reach the board
        array = array.slice(4);
        message = JSON.parse(String.fromCharCode.apply(null, array.slice(1)));
        log('Client sent us a JSON message:');
        log(message, 0);
        dispatcher[message.selector].call(null, message.arguments);
    } else {
        serialSend(rawData);
    }
};

dispatcher = {
    getSerialPortList: function () {
        SerialPort.list().then(function (devices) {
            var actualDevices = [];
            devices.forEach(function (device) {
                if (device.vendorId) {
                    actualDevices.push({
                        path: device.comName, 
                        displayName: device.manufacturer
                    });
                } 
            })
            log('Client requested serial port list.');
            sendJsonMessage('getSerialPortListResponse', [ actualDevices ]);
        });
    },
    serialConnect: function (portPath) {
        serialConnect(portPath, function () {
            // aiming for future error control
            log('Client asked me to connect to a board.');
            sendJsonMessage('serialConnectResponse', [ true ]);
        });
    },
    serialDisconnect: function () {
        log('Client asked me to disconnect from a board.');
        serialDisconnect(
            // aiming for a future multi-board scenario
            connectionId, 
            // success callback
            function () { 
                sendJsonMessage('serialDisconnectResponse', [ true ]);
            },
            // error callback
            function () {
                sendJsonMessage('serialDisconnectResponse', [ false ]);
            }
        );
    }
};

function stringToByteArray (str) {
    return str.split('').map(
        function (char) { return char.charCodeAt(0); }
    );
};

function log (str, code) {
    var color = [
        // code defines the message type
        '\x1b[1m', // data (white)
        '\x1b[31m', // error message (red)
        ];

    if (options.debugMode) {
        console.log((color[code] || '\x1b[0m') + util.format(str));
    }
};

function parseArgs () {
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
        }
    });
};

function printHelp (topic) {
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

function startUp () {
    parseArgs();

    wsServer = new WebSocket.Server({ port: options.port || 9999 }),
    wsServer.on('connection', function (ws) {
        socket = ws;
        log('websocket client connected');
        socket.on('message', function (message) {
            processMessage(message);
        });
        socket.on('close', function () {
            log('websocket client disconnected');
            socket = null;
        });
    });

    console.log(
        'µBlocks websockets-serial bridge started.\n' +
        'Run me with --help for command line arguments\n' +
        'Debug is ' + (options.debugMode ? 'enabled' : 'disabled') + '.\n');
    log('Waiting for websockets client to connect at port ' + (options.port || 9999) + '.');
};

startUp();
