var extensionId = 'gkhiljdfnkgeeeadlpiiiejkdfchgiip',
    postal = new Postal();

// Messaging between web client and plugin

function Postal() {};

// Send a command for the plugin to run
Postal.prototype.sendCommand = function (command, args, callback) {
    // TODO Since we need to communicate with the client bidirectionally, onMessageExternal
    // is not going to be enough. We need to use chrome.runtime.connect to establish a
    // long-lived connection instead: https://developer.chrome.com/extensions/messaging#connect
    chrome.runtime.sendMessage(extensionId, { command: command, args: args }, callback);
};

// Send a message to the board
Postal.prototype.sendMessageToBoard = function (message) {
    this.sendCommand('sendMessage', [ message ]);
};
