// Version: 2 (change this version to force local cache flush of wasm files)

var cacheName = 'MicroBlocks';
var filesToCache = [
  '/run/',
  '/run/microblocks.html',
  '/run/emModule.js',
  '/run/gpSupport.js',
  '/run/FileSaver.js',
  '/run/gp_wasm.js',
  '/run/gp_wasm.wasm',
  '/run/gp_wasm.data',
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
