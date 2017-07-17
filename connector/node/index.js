var WebSocket = require('ws'),
    SerialPort = require('serialport'),
    wsServer = new WebSocket.Server({ port: 9999 }),
    serial,
    socket;

wsServer.on('connection', function (ws) {
    socket = ws;
    console.log('websocket client connected');
    socket.on('message', function (message) {
        processMessage(message);
    });
    socket.on('close', function () {
        console.log('websocket client disconnected');
        socket = null;
    });
});

function serialConnect (portName, callback) {
    serial = new SerialPort(
        portName, 
        { baudRate: 9600 },
        callback
    );

    serial.on('data', function (data) {
        if (socket) {
            console.log('socket send');
            console.log(data);
            socket.send(data);
        } else {
            console.log('Socket is not connected');
        } 
    });
};

function serialSend (arrayBuffer) {
    if (serial) {
        console.log('serial send');
        console.log(arrayBuffer);
        serial.write(arrayBuffer);
    } else {
        console.log('Board is not connected');
    }
};

// Message composing

function sendJsonMessage (selector, arguments) {
    var object = { selector: selector, arguments: arguments },
        data = stringToByteArray(JSON.stringify(object)),
        array = [0xFF, 0, 0, data.length & 255, data.length >> 8];
    socket.send(array.concat(data));
};

// Message processing

function processMessage (rawData) {
    var array = new Uint8Array(rawData),
        message;
    if (array[0] === 0xFF) {
        // this is an internal JSON message,
        // not supposed to reach the board
        array = array.slice(4);
        message = JSON.parse(String.fromCharCode.apply(null, array.slice(1)));
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
            sendJsonMessage('getSerialPortListResponse', [ actualDevices ]);
        });
    },
    serialConnect: function (portPath) {
        serialConnect(portPath, function () {
            // aiming for future error control
            sendJsonMessage('serialConnectResponse', [ true ]);
        });
    },
    serialDisconnect: function () {
        serialDisconnect(
            // aiming for a future multi-board scenario
            connectionId, 
            // success callback
            function () { 
                sendJsonMessage('serialDisconnectResponse', [ true ]);
            },
            // error callback
            function () {
                sendJsonMessage('serialConnectResponse', [ false ]);
            }
        );
    }
};

function stringToByteArray (str) {
    return str.split('').map(
        function (char) { return char.charCodeAt(0); }
    );
};
