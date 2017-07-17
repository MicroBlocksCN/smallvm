var verbose = true,
    port = 9999,
    httpServer,
    server,
    socket,
    connectionId,
    listenerId;

// Utility functions

function log (string) {
    console.log(string);
};

// WebSocket server
if (http.Server && http.WebSocketServer) {
    httpServer = new http.Server();
    wsServer = new http.WebSocketServer(httpServer);
    httpServer.listen(port);

    wsServer.addEventListener('request', function (request) {
        log('websocket client connected');
        socket = request.accept();
        socket.binaryType = 'arraybuffer';

        // redirect anything we get on the socket to the serial port
        socket.addEventListener('message', function (event) {
            // event.data should contain an array of integers
            processMessage(event.data);
        });

        socket.addEventListener('close', function() {
            log('websocket client disconnected');
            socket = null;
        });
        return true;
    });
}

// Connection handling

function serialConnect (portName, callback) {
    log('connecting to ' + portName);
    chrome.serial.connect(
        portName, 
        { bitrate: 9600 },
        function (connectionInfo) {
            connectionId = connectionInfo.connectionId;
            listenerId = chrome.serial.onReceive.addListener(onSerialReceive);
            log('connected');
            callback();
        }
    );
};

function serialDisconnect (connectionId, callback, onErrorCallback, retries) {
    var myself = this;
    
    if (retries === 0) {
        onErrorCallback();
        throw new Error('Could not disconnect from board');
    }

    chrome.serial.onReceive.removeListener(listenerId);
    chrome.serial.disconnect(
        connectionId,
        function (success) {
            if (success) {
                log('disconnected');
                callback();
                chrome.runtime.reload();
            } else {
                log('could not disconnect, retrying... (attempt #' + (3 - retries) + ')');
                myself.serialDisconnect(connectionId, callback, onErrorCallback, retries ? retries - 1 : 2);
            }
        }
    );
};

// Serial messaging

function onSerialReceive (info) {
    //var arrayBuffer = (new Uint8Array(info.data)).buffer;
    if (socket) {
        socket.send(info.data);
    } else {
        log('Socket is not connected');
    }
};

function serialSend (arrayBuffer) {
    if (connectionId) {
        chrome.serial.send(
            connectionId,
            arrayBuffer,
            function (result) { }
        );
    } else {
        log('Board is not connected');
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
        chrome.serial.getDevices(function (devices) {
            sendJsonMessage('getSerialPortListResponse', [ devices ]);
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
