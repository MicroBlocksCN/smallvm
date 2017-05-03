// Messaging between web client and middleware

function Postal (address, onReceive) {
    this.init(address, onReceive);
};

Postal.prototype.init = function (address, onReceive) {
    this.address = address;
    this.socket = new WebSocket(address);

    this.socket.addEventListener('open', function() {
        log('socket connection open');
    });

    this.socket.onmessage = function (event) {
        onReceive(event.data);
    };

    this.socket.onclose = function () {
        this.socket = null;
        log('socket connection closed');
    };
};

Postal.prototype.send = function (message) {
    log('sending ' + message);
    if (this.socket) {
        this.socket.send(message);
    }
};
