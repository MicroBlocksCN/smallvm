var verbose = true,
    portList,
    connectionId,
    listenerId,
    dispatcher = new Dispatcher(),
    request = new XMLHttpRequest(),
    messageBuffer = [];

function log (string) {
    if (!verbose) { return; }
    console.log(string);
};

Array.prototype.toHexString = function () {
    return (this.map(function (each) { return each.toString(16); })).toString();
};


// We check for devices connected to the serial port every 1.5 seconds and
// store their descriptors in a list.

setInterval(
    function () {
        chrome.serial.getDevices(
            function (devices) {
                portList = devices;
            }
        );
    },
    1500
);


// We have received data from the board.

function onSerialReceive (info) {
    var newData = new Uint8Array(info.data);
    messageBuffer = messageBuffer.concat(Array.from(newData));
    dispatcher.parseMessage();
};


// TODO Since we need to communicate with the client bidirectionally, onMessageExternal
// is not going to be enough. We need to use chrome.runtime.connect to establish a
// long-lived connection instead: https://developer.chrome.com/extensions/messaging#connect

chrome.runtime.onMessageExternal.addListener(
    function (message, sender, sendResponse) {
        sendResponse(dispatcher[message.command].apply(this, (message.args || [])));
    }
);


// Command dispatcher

function Dispatcher() {};

Dispatcher.prototype.getDevices = function () {
    return portList;
};

Dispatcher.prototype.connect = function (portName) {
    log('connecting to ' + portName);
    chrome.serial.connect(
        portName, 
        { bitrate: 9600 },
        function (connectionInfo) {
            connectionId = connectionInfo.connectionId;
            listenerId = chrome.serial.onReceive.addListener(onSerialReceive);
            log('connected');
        }
    );
};

Dispatcher.prototype.disconnect = function (retries) {
    var myself = this;
    
    if (retries === 0) {
        throw new Error('Could not disconnect from board');
    }

    chrome.serial.disconnect(
        connectionId,
        function (success) {
            if (success) {
                log('disconnected');
                chrome.runtime.reload();
            } else {
                // we'll try to disconnect three times.
                log('could not disconnect, retrying... (attempt ' + (3 - retries) + ')');
                myself.disconnect(retries ? retries - 1 : 2);
            }
        }
    );
};

// Sends a message to the board over serial.
Dispatcher.prototype.sendMessage = function (array) {
    chrome.serial.send(
        connectionId,
        (new Uint8Array(array)).buffer,
        function () { 
            log('message sent: ' + array); 
        }
    );
};

Dispatcher.prototype.parseMessage = function () {
    var descriptor = protocol[messageBuffer[0]],
        dataSize;

    log('→ ' + messageBuffer.toHexString());

    if (!descriptor) {
        // We probably connected to the board while it was sending a message
        // and missed its header.
        messageBuffer = [];
        return;
    }

    if (descriptor.carriesData && messageBuffer.length >= 4) {
        dataSize = messageBuffer[3] | messageBuffer[2] << 8;
        if (messageBuffer.length === dataSize + 4) {
            // The message is complete, let's parse it.
            printMessage(descriptor, dataSize);
            messageBuffer = messageBuffer.slice(4 + dataSize);
        } 
    } else if (!descriptor.carriesData && messageBuffer.length === 2) {
        // this message carries no data and is complete
        printMessage(descriptor);
        messageBuffer = messageBuffer.slice(2);
    } 
};

// Just for test purposes
function printMessage (descriptor, dataSize) {
    var data;
    log('===');
    log('Message complete');
    log('OpCode:\t\t\t\t' + messageBuffer[0].toString(16));
    log('Description:\t\t' + descriptor.description);
    log('Object ID:\t\t\t' + messageBuffer[1]);
    log('Origin:\t\t\t\t' + descriptor.origin);
    log('Carries data:\t\t' + (descriptor.carriesData && dataSize > 0));
    if (dataSize) {
        data = messageBuffer.slice(4, 4 + dataSize);
        log('Data size:\t\t\t' + dataSize);
        log('Data:\t\t\t\t' + data.toHexString());
        if (descriptor.dataDescriptor) {
            log('Data description:\t' + descriptor.dataDescriptor[data]);
        }
    }
    log('===');
};
