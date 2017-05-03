var devicesDiv = document.querySelector('#devices'),
    allDevicePaths,
    serialDevice,
    discoveryInterval;

function startDiscovery () {
    allDevicePaths = [],
    devicesDiv.innerHTML = '';
    discoveryInterval = setInterval(
        renderDevices,
        1000
    );
};

function stopDiscovery () {
    var button = document.createElement('button');
    clearInterval(discoveryInterval);
    devicesDiv.innerHTML = 
        '<p>Connected to ' + serialDevice.displayName + 
        ' at ' + serialDevice.path + '</p>';
    button.innerText = 'Disconnect';
    button.onclick = function () {
        serialDisconnect(
            connectionId, 
            function () { startDiscovery(); }
        );
    };
    devicesDiv.append(button);
};

function renderDevices () {
    chrome.serial.getDevices(function (devices) {

        // Add buttons for all new devices
        devices.forEach(function (dev) {
            if (allDevicePaths.indexOf(dev.path) === -1) {
                var button = document.createElement('button');
                button.innerText = dev.path;
                button.title = dev.displayName;
                button.onclick = function () {
                    serialConnect(
                        dev.path,
                        function () {
                            serialDevice = dev;
                            stopDiscovery();
                        }
                    );
                };
                devicesDiv.append(button);
                allDevicePaths.push(dev.path);
            }
        });

        // Remove buttons for all obsolete devices
        [].forEach.call(
            devicesDiv.children,
            function (eachButton) {
                if (devices.every(function (each) { return each.path !== eachButton.innerText; })) {
                    eachButton.remove();
                    allDevicePaths.splice(allDevicePaths.indexOf(eachButton.innerText), 1);
                }
            }
        );
    });
}

startDiscovery();
