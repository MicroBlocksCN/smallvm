var cacheName = 'MicroBlocks';
var filesToCache = [
  '/mbtest/',
  '/mbtest/microblocks.html',
  '/mbtest/emModule.js',
  '/mbtest/gpSupport.js',
  '/mbtest/FileSaver.js',
  '/mbtest/gp_wasm.js',
  '/mbtest/gp_wasm.wasm',
  '/mbtest/gp_wasm.data',
];

/* Start the service worker and cache all of the app's content */
self.addEventListener('install', function(e) {
  e.waitUntil(
    caches.open(cacheName).then(function(cache) {
      return cache.addAll(filesToCache);
    })
  );
  self.skipWaiting();
});

/* Serve cached content when offline */
self.addEventListener('fetch', function(e) {
  e.respondWith(
    caches.match(e.request).then(function(response) {
      return response || fetch(e.request);
    })
  );
});
