var verbose = true;

// Utility functions

Array.prototype.toHexString = function () {
    return (this.map(function (each) { return each.toString(16); })).toString();
};

function log (string) {
    var element = document.querySelector('#log');
    if (!verbose) { return; }
    element.append(string + '\n');
    element.scrollTop = element.scrollHeight;
    console.log(string);
};

// µBlocks message parser

function Parser () {
    this.init();
};

Parser.prototype.init = function () {
    this.messageBuffer = [];
};

Parser.prototype.processRawData = function (data) {
    this.messageBuffer = this.messageBuffer.concat(data.split(','));
    this.parseMessage();
};

Parser.prototype.parseMessage = function () {
    var descriptor = this.protocol[this.messageBuffer[0]],
        dataSize;

    log('→ ' + this.messageBuffer.toHexString());

    if (!descriptor) {
        // We probably connected to the board while it was sending a message
        // and missed its header.
        this.messageBuffer = [];
        return;
    }

    if (descriptor.carriesData && this.messageBuffer.length >= 4) {
        dataSize = this.messageBuffer[3] | this.messageBuffer[2] << 8;
        if (this.messageBuffer.length === dataSize + 4) {
            // The message is complete, let's parse it.
            this.printMessage(descriptor, dataSize);
            this.messageBuffer = this.messageBuffer.slice(4 + dataSize);
        } 
    } else if (!descriptor.carriesData && this.messageBuffer.length === 2) {
        // this message carries no data and is complete
        this.printMessage(descriptor);
        this.messageBuffer = this.messageBuffer.slice(2);
    } 
};

// Just for test purposes
Parser.prototype.printMessage = function (descriptor, dataSize) {
    var data;
    log('===');
    log('Message complete');
    log('OpCode:\t\t\t' + this.messageBuffer[0].toString(16));
    log('Description:\t\t' + descriptor.description);
    log('Object ID:\t\t' + this.messageBuffer[1]);
    log('Origin:\t\t\t' + descriptor.origin);
    log('Carries data:\t\t' + (descriptor.carriesData && dataSize > 0));
    if (dataSize) {
        data = this.messageBuffer.slice(4, 4 + dataSize);
        log('Data size:\t\t' + dataSize);
        log('Data:\t\t\t' + data.toHexString());
        if (descriptor.dataDescriptor) {
            log('Data description:\t' + descriptor.dataDescriptor[data]);
        }
    }
    log('===');
};

// Message protocol

Parser.prototype.protocol = {
    0x75: {
        description: 'A thread has just started running',
        origin: 'board',
        carriesData: false
    },
    0x7D: {
        description: 'A thread has just stopped running',
        origin: 'board',
        carriesData: true
    },
    0x7E: {
        description: 'An error has occurred inside a thread',
        origin: 'board',
        carriesData: true,
        dataDescriptor: {
            0xD0: 'Division by zero',
            0x6E: 'Generic Error'
        }
    },
    0x7C: {
        description: 'The IDE wants to kill a thread',
        origin: 'ide',
        carriesData: false
    },
    0x5A: {
        description: 'The IDE wants to stop all threads',
        origin: 'ide',
        carriesData: false
    },
    0x1A: {
        description: 'The IDE requests the value of a variable',
        origin: 'ide',
        carriesData: false
    },
    0x10: {
        description: 'The IDE requests the state of an I/O pin',
        origin: 'ide',
        carriesData: false
    },
    0xB5: {
        description: 'The board sends back the value of a variable or an I/O pin',
        origin: 'board',
        carriesData: true
    },
    0x5C: {
        description: 'A script is sent to the board',
        origin: 'ide',
        carriesData: true
    }
};
