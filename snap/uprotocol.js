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
// I interpret and dispatch messages received via the µBlocks postal service

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
    var check = this.messageBuffer[0],
        isLong = check == 0xFB,
        opCode = this.messageBuffer[1],
        descriptor, dataSize, dataRemainder;

    if (check !== 0xFA && check !== 0xFB) {
        // We probably connected to the board while it was sending a message
        // and missed its header.
        this.clearBuffer();
        return;
    }

    if (!opCode) {
        // We haven't yet gotten our opCode, let's wait for it.
        return;
    }

    descriptor = this.descriptorFor(opCode);

    if (isLong && this.messageBuffer.length >= 5) {
        dataSize = this.messageBuffer[3] | this.messageBuffer[4] << 8;
        if (this.messageBuffer.length >= dataSize + 5) {
            // The message is complete, let's parse it.
            this.processMessage(descriptor, dataSize);
            this.messageBuffer = this.messageBuffer.slice(5 + dataSize);
        }
    } else if (!isLong && this.messageBuffer.length >= 3) {
        // this message carries no data and is complete
        this.processMessage(descriptor);
        dataRemainder = this.messageBuffer.slice(5);
        this.clearBuffer();
        this.processRawData(dataRemainder);
    }
};

Protocol.prototype.processMessage = function (descriptor, dataSize) {
    var data,
        taskId = this.messageBuffer[2];

    if (dataSize) {
        data = this.messageBuffer.slice(5, 5 + dataSize);
    }

    if (descriptor.selector === 'jsonMessage') {
        value = 
            this.processJSONMessage(JSON.parse(String.fromCharCode.apply(null, data)));
    } else {
        if (dataSize) {
            this.dispatcher[descriptor.selector].call(this, data, taskId);
        } else {
            this.dispatcher[descriptor.selector].call(this, taskId);
        }
    }
};

Protocol.prototype.processJSONMessage = function (json) {
    this.dispatcher[json.selector].apply(
        this.ide,
        json.arguments
    );
};

Protocol.prototype.showBubbleFor = function (stack, data, isError) {
    if (stack) {
        // this.ide.currentSprite may not be the actual target,
        // in the future we may want to have board IDs
        stack.showBubble(
            (isError ? 'Error\n' : '') + this.processReturnValue(data),
            false,
            this.ide.currentSprite
        );
    }
};

Protocol.prototype.processReturnValue = function (rawData) {
    var type = rawData[0],
        value;

    if (type === 1) {
        // integer
        value = (rawData[4] << 24) | (rawData[3] << 16) | (rawData[2] << 8) | (rawData[1]);
    } else if (type === 2) {
        // string
        value = String.fromCharCode.apply(null, rawData.slice(1));
    } else if (type === 3) {
        // boolean
        value = rawData.slice(1) == 1;
    }

    return isNil(value) ? 'unknown type' : value;
};

Protocol.prototype.packMessage = function (selector, taskId, data) {
    var descriptor = this.descriptorFor(selector),
        message = [data ? 0xFB : 0xFA, descriptor.opCode, taskId];

    if (data) {
        if (selector === 'storeChunk') {
            // chunkType, hardcoded for now
            data = [1].concat(data);
        }
        // add the data size in little endian
        message = message.concat(data.length & 255).concat((data.length >> 8) & 255);
        // add the data
        message = message.concat(data);
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
    // IDE → Board
    {
        opCode: 0x01,
        selector: 'storeChunk'
    },
    {
        opCode: 0x02,
        selector: 'deleteChunk'
    },
    {
        opCode: 0x03,
        selector: 'startChunk'
    },
    {
        opCode: 0x04,
        selector: 'stopChunk'
    },
    {
        opCode: 0x05,
        selector: 'startAll'
    },
    {
        opCode: 0x06,
        selector: 'stopAll'
    },
    {
        opCode: 0x0E,
        selector: 'deleteAll'
    },
    {
        opCode: 0x0F,
        selector: 'systemReset'
    },

    // Board → IDE
    {
        opCode: 0x10,
        selector: 'taskStarted'
    },
    {
        opCode: 0x11,
        selector: 'taskDone'
    },
    {
        opCode: 0x12,
        selector: 'taskReturned'
    },
    {
        opCode: 0x13,
        selector: 'taskError',
        dataDescriptor: {
            0x00: 'Division by zero',
            0xFF: 'Generic Error'
        }
    },
    {
        opCode: 0x14,
        selector: 'outputString'
    }, 

    // Bridge → IDE
    {
        opCode: 0xFF,
        selector: 'jsonMessage'
    }
];

Protocol.prototype.dispatcher = {
    // JSON messages
    getSerialPortListResponse: function (portList) {
        var portMenu = new MenuMorph(this, 'select a port'),
            world = this.world(),
            myself = this; // The receiving IDE_Morph

        portList.forEach(function(port) {
            portMenu.addItem(
                port.displayName + ' (' + port.path + ')',
                function() { myself.serialConnect(port.path); }
            );
        });

        portMenu.popUpAtHand(world);
    },
    serialConnectResponse: function (success) {
        // "this" is the IDE
        this.serialConnected(success);
    },
    serialDisconnectResponse: function (success) {
        this.serialDisconnected(success);
    },

    // µBlocks messages
    taskStarted: function (taskId) {
        var stack = this.ide.findStack(taskId);
        stack.addHighlight(stack.topBlock().removeHighlight());
    },
    taskDone: function (taskId) {
        var stack = this.ide.findStack(taskId);
        stack.removeHighlight();
    },
    taskReturned: function (data, taskId) {
        var stack = this.ide.findStack(taskId);
        stack.removeHighlight();
        this.showBubbleFor(stack, data, false);
    },
    taskError: function (data, taskId) {
        this.ide.findStack(taskId).addErrorHighlight();
        // Not dealing with error codes yet
        this.showBubbleFor(stack, data, true);
    },
    outputString: function (data, taskId) {
        console.log('# DEBUG # ' + this.processReturnValue(data));
    }
};

// µBlocks postal service
// I facilitate messaging between the web client and the µBlocks plugin

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

Postal.prototype.sendMessage = function (selector, taskId, data) {
    if (selector === 'jsonMessage') {
        data = data.split('').map(
            function (char) { return char.charCodeAt(0); }
        );
    }
    this.rawSend(this.protocol.packMessage(selector, taskId, data));
};

Postal.prototype.sendJsonMessage = function (selector, arguments) {
    this.sendMessage('jsonMessage', 0, JSON.stringify({ selector: selector, arguments: arguments }));
};
