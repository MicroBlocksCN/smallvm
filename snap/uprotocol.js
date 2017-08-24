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
    var opCode = this.messageBuffer[0],
        descriptor = this.descriptorFor(opCode),
        dataSize,
        dataRemainder;

    if (!descriptor) {
        // We probably connected to the board while it was sending a message
        // and missed its header.
        this.clearBuffer();
        return;
    }

    if (descriptor.carriesData && this.messageBuffer.length >= 5) {
        dataSize = this.messageBuffer[3] | this.messageBuffer[4] << 8;
        if (this.messageBuffer.length >= dataSize + 5) {
            // The message is complete, let's parse it.
            this.processMessage(descriptor, dataSize);
            this.messageBuffer = this.messageBuffer.slice(5 + dataSize);
        }
    } else if (!descriptor.carriesData && this.messageBuffer.length >= 5) {
        // this message carries no data and is complete
        this.processMessage(descriptor);
        dataRemainder = this.messageBuffer.slice(5);
        this.clearBuffer();
        this.processRawData(dataRemainder);
    }
};

Protocol.prototype.processMessage = function (descriptor, dataSize) {
    var data,
        messageId = this.messageBuffer[1],
        taskId = this.messageBuffer[2];

    if (dataSize) {
        data = this.messageBuffer.slice(5, 5 + dataSize);
    }

    if (descriptor.selector === 'jsonMessage') {
        value = 
            this.processJSONMessage(JSON.parse(String.fromCharCode.apply(null, data)));
    } else {
        if (descriptor.carriesData) {
            this.dispatcher[descriptor.selector].call(this, data, taskId, messageId);
        } else {
            this.dispatcher[descriptor.selector].call(this, taskId, messageId);
        }
    }
};

Protocol.prototype.processJSONMessage = function (json) {
    this.dispatcher[json.selector].apply(
        this.ide,
        json.arguments
    );
};

Protocol.prototype.showBubbleFor = function (taskId, data, isError) {
    var stack = this.ide.findStack(taskId);
    if (stack) {
        // this.ide.currentSprite may not be the actual target,
        // in the future we may want to have board ids
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
    }

    return isNil(value) ? 'unknown type' : value;
};

Protocol.prototype.packMessage = function (selector, taskId, data) {
    var descriptor = this.descriptorFor(selector),
        messageId = Math.floor(Math.random() * 255), // temporary
        message = [descriptor.opCode, messageId, taskId];

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
        selector: 'okayReply',
        origin: 'board',
        carriesData: false
    },
    {
        opCode: 0x01,
        description: 'Error reply',
        selector: 'errorReply',
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
        selector: 'getTaskStatusReply',
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
        selector: 'getOutputMessageReply',
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
        selector: 'getReturnValueReply',
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
        selector: 'getErrorInfoReply',
        origin: 'board',
        carriesData: true
    },
    {
        opCode: 0x10,
        description: 'System Reset',
        selector: 'systemResetMsg',
        origin: 'ide',
        carriesData: false
    },
    {
        opCode: 0x11,
        description: 'Task Started',
        selector: 'taskStarted',
        origin: 'board',
        carriesData: false
    },
    {
        opCode: 0x12,
        description: 'Task Done',
        selector: 'taskDone',
        origin: 'board',
        carriesData: false
    },
    {
        opCode: 0xFF,
        description: 'JSON message',
        selector: 'jsonMessage',
        carriesData: true
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
    okayReply: nop,
    taskStarted: function (taskId) {
        var stack = this.ide.findStack(taskId);
        stack.addHighlight(stack.topBlock().removeHighlight());
    },
    taskDone: function (taskId) {
        var stack = this.ide.findStack(taskId);
        stack.removeHighlight();
    },
    errorReply: function (data, taskId) {
        this.ide.findStack(taskId).addErrorHighlight();
        this.ide.postal.sendMessage('getErrorInfo', taskId);
    },
    getErrorInfoReply: function (data, taskId) {
        this.showBubbleFor(taskId, data, true);
    },
    getReturnValueReply: function (data, taskId) {
        this.showBubbleFor(taskId, data);
    },
    getOutputMessage: nop,
    getOutputMessageReply: function (data, taskId) {
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
