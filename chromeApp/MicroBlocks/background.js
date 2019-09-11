chrome.app.runtime.onLaunched.addListener(function() {
  chrome.app.window.create('microblocks.html', {
    'outerBounds': { 'width': 1000, 'height': 800 }
  });
});
