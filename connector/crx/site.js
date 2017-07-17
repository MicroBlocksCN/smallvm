var button = document.createElement('button');

button.innerText = 'Reload';
button.onclick = function () {
    if (connectionId) {
        serialDisconnect(
            connectionId, 
            function () { },
            function () { }
        );
    } else {
        chrome.runtime.reload();
    }
};

document.querySelector('#controls').append(button);
