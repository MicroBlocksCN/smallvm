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
