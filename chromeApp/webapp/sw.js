// MicroBlocks Service Worker to support offline operation
// See https://serviceworke.rs/strategy-cache-and-update_service-worker_doc.html

var cacheName = 'MicroBlocks';

var filesToCache = [
  '/run/',
  '/run/microblocks.html',
  '/run/emModule.js',
  '/run/gpSupport.js',
  '/run/FileSaver.js',
  '/run/gp_wasm.js',
  '/run/gp_wasm.wasm',
  // '/run/gp_wasm.data',
  // use cloud file for speeding up
  'https://scratch3-files.just4fun.site/gp_wasm-1-2-5.data',
];

self.addEventListener('install', function(e) {
  e.waitUntil(
    caches.open(cacheName).then(function(cache) {
      return cache.addAll(filesToCache);
    })
  );
  self.skipWaiting(); // make this become the active service worker
  console.log("service worker installed v01");
});

self.addEventListener('fetch', function(evt) {
  var isVersionCheck = (evt.request.url.indexOf("VERSION.txt") > -1);
  if (isVersionCheck) { // don't cache version checks
	evt.respondWith(fetch(evt.request));
  	return;
  }
  evt.respondWith(cachedFile(evt.request)); // use cached value
  evt.waitUntil(updateCachedFile(evt.request)); // update the cache if online
});

function cachedFile(request) {
  return caches.open(cacheName).then(function (cache) {
    return cache.match(request).then(function (matching) {
     if (matching) {
        return matching;
      } else {
        return fetch(request);
      }
    });
  });
}

function updateCachedFile(request) {
  return caches.open(cacheName).then(function (cache) {
    return fetch(request).then(function (response) {
      return cache.put(request, response);
    }).catch(function (error) { }); // ignore the error if fetch() fails
  });
}
