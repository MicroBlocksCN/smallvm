/*

    uprotocol.js

    a µblocks message protocol for the µblocks VM


    written by John Maloney, Jens Mönig, and Bernat Romagosa
    jens@moenig.org

    Copyright (C) 2017 by John Maloney, Jens Mönig, Bernat Romagosa

    This file is part of Snap!.

    Snap! is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as
    published by the Free Software Foundation, either version 3 of
    the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.


    prerequisites:
    --------------


    toc
    ---
    the following list shows the order in which all constructors are
    defined. Use this list to locate code in this document:

        Protocol
        Postal


    credits
    -------
    John Maloney designed the original µblocks bytecode system

*/

// Global stuff ////////////////////////////////////////////////////////

/*global modules */

// Utility functions

Array.prototype.toHexString = function () {
    return (this.map(function (each) { return each.toString(16); })).toString();
};

// µBlocks message protocol

function Protocol (ide) {
    this.init(ide);
};

Protocol.prototype.init = function (ide) {
    this.messageBuffer = [];
    this.ide = ide;
};

Protocol.prototype.processRawData = function (data) {
    this.messageBuffer = this.messageBuffer.concat(data);
    this.parseMessage();
};

Protocol.prototype.clearBuffer = function () {
    this.messageBuffer = [];
};

Protocol.prototype.parseMessage = function () {
    var opCode = this.messageBuffer[0],
        descriptor = this.descriptorFor(opCode),
        dataSize;

    if (!descriptor) {
        // We probably connected to the board while it was sending a message
        // and missed its header.
        this.clearBuffer();
        return;
    }

    if (descriptor.carriesData && this.messageBuffer.length >= 5) {
        dataSize = this.messageBuffer[3] | this.messageBuffer[4] << 8;
        if (this.messageBuffer.length === dataSize + 5) {
            // The message is complete, let's parse it.
            this.processMessage(descriptor, dataSize);
            this.messageBuffer = this.messageBuffer.slice(5 + dataSize);
        } 
    } else if (!descriptor.carriesData && this.messageBuffer.length === 5) {
        // this message carries no data and is complete
        this.processMessage(descriptor);
        this.messageBuffer = this.messageBuffer.slice(5);
    } 
};

Protocol.prototype.processMessage = function (descriptor, dataSize) {
    var data,
        stringData;

    if (dataSize) {
        data = this.messageBuffer.slice(5, 5 + dataSize);
        stringData = String.fromCharCode.apply(null, data);
    }

    if (descriptor.selector === 'jsonMessage') {
        this.processJSONMessage(JSON.parse(stringData));
    } else {
        this.printMessage(descriptor, data, stringData);
    }
};

Protocol.prototype.processJSONMessage = function (json) {
    this.dispatcher[json.selector].apply(
        this.ide.currentSprite,
        json.arguments
    );
};

// Just for test purposes
Protocol.prototype.printMessage = function (descriptor, data, stringData) {
    console.log('===');
    console.log('Raw message:\t' + this.messageBuffer);
    console.log('OpCode:\t\t\t' + this.messageBuffer[0].toString(16));
    console.log('Description:\t' + descriptor.description);
    console.log('Message ID:\t\t' + this.messageBuffer[1]);
    console.log('Stack ID:\t\t' + this.messageBuffer[2]);
    console.log('Origin:\t\t\t' + descriptor.origin);
    console.log('Carries data:\t' + (descriptor.carriesData && data));
    if (data) {
        console.log('Data size:\t\t' + data.length);
        console.log('Raw data:\t\t' + data.toHexString());
        console.log('Data as string:\t' + stringData);
        if (descriptor.dataDescriptor) {
            console.log('Data description:\t' + descriptor.dataDescriptor[data]);
        }
    }
    console.log('===');
};

Protocol.prototype.packMessage = function (selector, stackId, data) {
    var descriptor = this.descriptorFor(selector),
        messageId = Math.floor(Math.random() * 255), // temporary
        message = [descriptor.opCode, messageId, stackId];

    if (data) {
        if (selector === 'storeChunk') {
            // chunkType, hardcoded for now
            data = [1].concat(data);
        }

        // add the data size in little endian
        message = message.concat(data.length & 255).concat((data.length >> 8) & 255);

        // add the data
        message = message.concat(data);
    } else {
        message = message.concat([0, 0]);
    }

    return message;
};

Protocol.prototype.descriptorFor = function (selectorOrOpCode) {
    return detect(
        this.descriptors, 
        function (descriptor) {
            if (typeof selectorOrOpCode === 'string') {
                return descriptor.selector === selectorOrOpCode;
            } else {
                return descriptor.opCode === selectorOrOpCode;
            }
        }
    );
};

// Message descriptors

Protocol.prototype.descriptors = [
    {
        opCode: 0x00,
        description: 'Okay reply',
        origin: 'board',
        carriesData: false
    },
    {
        opCode: 0x01,
        description: 'Error reply',
        origin: 'board',
        carriesData: true,
        dataDescriptor: {
            0x00: 'Division by zero',
            0xFF: 'Generic Error'
        }
    },
    {
        opCode: 0x02,
        description: 'Store a code chunk',
        selector: 'storeChunk',
        origin: 'ide',
        carriesData: true
    },
    {
        opCode: 0x03,
        description: 'Delete a code chunk',
        selector: 'deleteChunk',
        origin: 'ide',
        carriesData: false
    },
    {
        opCode: 0x04,
        description: 'Start all threads',
        selector: 'startAll',
        origin: 'ide',
        carriesData: false
    },
    {
        opCode: 0x05,
        description: 'Stop all threads',
        selector: 'stopAll',
        origin: 'ide',
        carriesData: false
    },
    {
        opCode: 0x06,
        description: 'Start a code chunk',
        selector: 'startChunk',
        origin: 'ide',
        carriesData: false
    },
    {
        opCode: 0x07,
        description: 'Stop a code chunk',
        selector: 'stopChunk',
        origin: 'ide',
        carriesData: false
    },
    {
        opCode: 0x08,
        description: 'Get task status',
        selector: 'getTaskStatus',
        origin: 'ide',
        carriesData: false
    },
    {
        opCode: 0x09,
        description: 'Get task status reply',
        origin: 'board',
        carriesData: true
    },
    {
        opCode: 0x0A,
        description: 'Get output message',
        selector: 'getOutputMessage',
        origin: 'ide',
        carriesData: false
    },
    {
        opCode: 0x0B,
        description: 'Get output message reply',
        origin: 'board',
        carriesData: true
    },
    {
        opCode: 0x0C,
        description: 'Get return value',
        selector: 'getReturnValue',
        origin: 'ide',
        carriesData: false
    },
    {
        opCode: 0x0D,
        description: 'Get return value reply',
        origin: 'board',
        carriesData: true
    },
    {
        opCode: 0x0E,
        description: 'Get error info',
        selector: 'getErrorInfo',
        origin: 'ide',
        carriesData: false
    },
    {
        opCode: 0x0F,
        description: 'Get error info reply',
        origin: 'board',
        carriesData: true
    },
    {
        opCode: 0xFF,
        description: 'JSON message',
        selector: 'jsonMessage',
        carriesData: true
    }
];

Protocol.prototype.dispatcher = {
    getSerialPortListResponse: function (portList) {
        var portMenu = new MenuMorph(this, 'select a port'),
            world = this.world(),
            myself = this; // The receiving SpriteMorph

        portList.forEach(function(port) {
            portMenu.addItem(
                port.displayName + ' (' + port.path + ')',
                function() { myself.serialConnect(port.path); }
            );
        });
        
        portMenu.popUpAtHand(world);
    },
    serialConnectResponse: function (success) {
        // "this" is the receiving SpriteMorph
        this.serialConnected(success);
    },
    serialDisconnectResponse: function (success) {
        this.serialDisconnected(success);
    }
};

function Postal (address, onReceive) {
    this.init(address, onReceive);
};

Postal.prototype.init = function (address, ide) {
    this.address = address;
    this.protocol = new Protocol(ide);
    this.ide = ide;
    this.socket = null;

    this.startAutoConnect();
};

Postal.prototype.startAutoConnect = function () {
    var myself = this;
    this.connectInterval = setInterval(function () { myself.initSocket() }, 1000);
};

Postal.prototype.initSocket = function () {
    var myself = this;

    this.socket = new WebSocket(this.address);
    this.socket.binaryType = 'arraybuffer';

    this.socket.addEventListener('open', function() {
        clearInterval(myself.connectInterval);
        myself.connectInterval = null;
    });

    this.socket.onmessage = function (event) {
        myself.protocol.processRawData(Array.from(new Uint8Array(event.data)));
    };

    this.socket.onclose = function () {
        this.socket = null;
        clearInterval(myself.connectInterval);
        myself.startAutoConnect();
    };
};

Postal.prototype.rawSend = function (message) {
    if (this.socket) {
        this.socket.send((new Uint8Array(message)).buffer);
    }
};

Postal.prototype.sendMessage = function (selector, stackId, data) {
    if (selector === 'jsonMessage') {
        data = data.split('').map(
            function (char) { return char.charCodeAt(0); }
        );
    }
    this.rawSend(this.protocol.packMessage(selector, stackId, data));
};

Postal.prototype.sendJsonMessage = function (selector, arguments) {
    this.sendMessage('jsonMessage', 0, JSON.stringify({ selector: selector, arguments: arguments }));
};
