/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// Fire up the control window
chrome.runtime.onStartup.addListener(function() {
    chrome.app.window.create(
        'index.html',
        {
            id: 'µBlocks connector',
            bounds: { width: 480, height: 360 }
        }
    );
});

chrome.app.window.create(
    'index.html',
    {
        id: 'µBlocks connector',
        bounds: { width: 480, height: 360 }
    }
);
