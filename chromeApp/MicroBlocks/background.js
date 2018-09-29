chrome.app.runtime.onLaunched.addListener(function() {
  chrome.app.window.create('gp.html', {
    'outerBounds': { 'width': 1000, 'height': 800 }
  });
});
