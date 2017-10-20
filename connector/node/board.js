var Board,
    util = require('util');

function nop () {};

function Board (portName, options) {
    this.portName = portName;
    this.options = options;
    this.serial = null;
    this.reconnectLoopId = null;
    this.onData = nop;
    this.onClose = nop;
    this.onError = nop;
};

Board.SerialPort = require('serialport');

Board.prototype.connect = function (connectCallback, onData, onClose, onError) {
    this.serial = new Board.SerialPort(
        this.portName, 
        { baudRate: 115200 },
        connectCallback
    );

    this.onData = onData;
    this.onClose = onClose;
    this.onError = onError;

    this.serial.on('data', onData);
    this.serial.on('close', onClose);
    this.serial.on('error', onError);
};

Board.prototype.disconnect = function (onSuccess, onError) {
    this.serial.close(onError);
    this.portName = null;
    onSuccess();
};

Board.prototype.reconnect = function () {
    var myself = this;
    this.log('Attempting to reconnect...');
    this.connect(
        function (err) { 
            if (!err) {
                myself.log('Reconnection success!');
                clearInterval(myself.reconnectLoopId);
                myself.reconnectLoopId = null;
            }
        },
        this.onData,
        this.onClose,
        this.onError
    );
};

Board.prototype.reconnectLoop = function () {
    var myself = this;
    if (!this.reconnectLoopId) {
        this.reconnectLoopId = setInterval(function () { myself.reconnect() }, 100);
    }
};

Board.prototype.send = function (arrayBuffer) {
    this.serial.write(arrayBuffer);
};

Board.prototype.log = function (str, code) {
    var color = [
        // code defines the message type
        '\x1b[1m', // data (white)
        '\x1b[31m', // error message (red)
        ];

    if (this.options.debugMode) {
        console.log((color[code] || '\x1b[0m') + util.format(str));
    }
};

module.exports = Board;
