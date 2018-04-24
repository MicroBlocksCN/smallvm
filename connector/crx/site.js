/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

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
