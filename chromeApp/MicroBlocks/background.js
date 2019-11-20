var launchFileEntry; // startup project file; read at startup by code in gpSupport.js

chrome.app.runtime.onLaunched.addListener(function(launchData) {
	if (launchData.items && launchData.items.length) {
		// launched by double-clicking a project file; save the file entry
		launchFileEntry = launchData.items[0].entry;
	}
	chrome.app.window.create(
		'microblocks.html', { outerBounds: { width: 1000, height: 800 }});
});
