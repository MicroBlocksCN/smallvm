// browserPrims.c
// Primitives for the browser version of GP.
// John Maloney, Jan 2015

// To do:
//	[ ] remove flip parameter from showTexture (and fix calls in lib)

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <emscripten.h>
#include <emscripten/html5.h>

#include "mem.h"
#include "interp.h"

#define MAX_TEXTURE_SIZE 8192

// ***** Fetch request state *****

typedef enum {IN_PROGRESS, DONE, FAILED} FetchStatus;

typedef struct {
	int id;
	FetchStatus status;
	int bytesReceived;
	int bytesExpected;
	int byteCount;
	char *data;
} FetchRequest;

#define MAX_REQUESTS 100
FetchRequest httpRequests[MAX_REQUESTS];

static int nextFetchID = 100;

// ***** Helper Functions *****

static int isInBrowser() {
	return EM_ASM_INT({
		return !ENVIRONMENT_IS_NODE;
	}, NULL);
}

static void fetchProgressCallback(unsigned reqHandle, void *arg, int bytesReceived, int bytesExpected) {
	FetchRequest *req = arg;
	req->bytesReceived = bytesReceived;
	req->bytesExpected = bytesExpected;
}

static void fetchDoneCallback(unsigned reqHandle, void *arg, void *buf, unsigned bufSize) {
	FetchRequest *req = arg;
	req->data = malloc(bufSize);
	if (req->data) memmove(req->data, buf, bufSize);
	req->byteCount = bufSize;
	req->status = DONE;
}

static void fetchErrorCallback(unsigned reqHandle, void *arg, int httpStatus, const char* errorString) {
	FetchRequest *req = arg;
	printf("Fetch error, id = %d, status = %d\n", req->id, httpStatus);
	req->status = FAILED;
}

// ***** Browser Support Primitives *****

static OBJ primBrowserURL(int nargs, OBJ args[]) {
	if (!isInBrowser()) return primFailed("Only works in a browser");

	int len = EM_ASM_INT({
        GP.urlBytes = (typeof window == 'undefined') ? [] : toUTF8Array(window.location.href);
        return GP.urlBytes.length;
	}, NULL);

	if (!canAllocate(len / 4)) return nilObj;
	OBJ result = allocateString(len);
	EM_ASM_({
		var dst = $0;
		var len = $1;
		for (var i = 0; i < len; i++) {
			Module.HEAPU8[dst++] = GP.urlBytes[i];
		}
		GP.urlBytes = []; // clear URL
	}, &FIELD(result, 0), len);

	return result;
}

static OBJ primStartFetch(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ url = args[0];
	if (NOT_CLASS(url, StringClass)) return primFailed("First argument must be a string");

	if (!isInBrowser()) return primFailed("Only works in a browser");

	// find an unused request
	int i;
	for (i = 0; i < MAX_REQUESTS; i++) {
		if (!httpRequests[i].id) {
			httpRequests[i].id = nextFetchID++;
			httpRequests[i].status = IN_PROGRESS;
			httpRequests[i].bytesReceived = 0;
			httpRequests[i].bytesExpected = 0;
			httpRequests[i].data = NULL;
			httpRequests[i].byteCount = 0;
			break;
		}
	}
	if (i >= MAX_REQUESTS) return nilObj; // no free request slots (unlikely)

	emscripten_async_wget2_data(
		obj2str(url), "GET", "", &httpRequests[i], true,
		fetchDoneCallback, fetchErrorCallback, fetchProgressCallback);
	return int2obj(httpRequests[i].id);
}

static OBJ primFetchBytesReceived(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (!isInt(args[0])) return primFailed("Expected integer");
	int id = obj2int(args[0]);

	// find the fetch request with the given id
	int i;
	for (i = 0; i < MAX_REQUESTS; i++) {
		if (httpRequests[i].id == id) break;
	}

	int result = 0;
	if (i < MAX_REQUESTS) result = httpRequests[i].bytesReceived;
	return int2obj(result);
}

static OBJ primFetchBytesExpected(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (!isInt(args[0])) return primFailed("Expected integer");
	int id = obj2int(args[0]);

	// find the fetch request with the given id
	int i;
	for (i = 0; i < MAX_REQUESTS; i++) {
		if (httpRequests[i].id == id) break;
	}

	int result = 0;
	if (i < MAX_REQUESTS) result = httpRequests[i].bytesExpected;
	return int2obj(result);
}

static OBJ primFetchResult(int nargs, OBJ args[]) {
	// Returns a BinaryData object on success, false on failure, and nil when fetch is still in progress.
	if (nargs < 1) return notEnoughArgsFailure();
	if (!isInt(args[0])) return primFailed("Expected integer");
	int id = obj2int(args[0]);

	// find the fetch request with the given id
	int i;
	for (i = 0; i < MAX_REQUESTS; i++) {
		if (httpRequests[i].id == id) break;
	}
	if (i >= MAX_REQUESTS) return falseObj; // could not find request with id; report as failure
	if (IN_PROGRESS == httpRequests[i].status) return nilObj; // in progress

	OBJ result = falseObj;

	if (DONE == httpRequests[i].status && httpRequests[i].data) {
		// allocate result object
		int byteCount = httpRequests[i].byteCount;
		result = newBinaryData(byteCount);
		if (result) {
			memmove(&FIELD(result, 0), httpRequests[i].data, byteCount);
		} else {
			printf("Insufficient memory for requested file (%ul bytes needed); skipping.\n", byteCount);
		}
	}

	// mark request as free and free the request data, if any
	httpRequests[i].id = 0;
	if (httpRequests[i].data) free(httpRequests[i].data);
	httpRequests[i].data = NULL;
	httpRequests[i].byteCount = 0;

	return result;
}

static OBJ primBrowserSize(int nargs, OBJ args[]) {
	// Get the inner (contents) size of the browser window.
	// Code from http://www.javascripter.net/faq/browserw.htm
	int w = EM_ASM_INT({
		var winW = 630;
		if (document.body && document.body.offsetWidth) {
			winW = document.body.offsetWidth;
		}
		if (document.compatMode=='CSS1Compat' &&
			document.documentElement &&
			document.documentElement.offsetWidth ) {
				winW = document.documentElement.offsetWidth;
		}
		if (window.innerWidth) {
			winW = window.innerWidth;
		}
		return winW;
	}, NULL);

	int h = EM_ASM_INT({
		winH = 460;
		if (document.body && document.body.offsetHeight) {
			winH = document.body.offsetHeight;
		}
		if (document.compatMode=='CSS1Compat' &&
			document.documentElement &&
			document.documentElement.offsetHeight ) {
			winH = document.documentElement.offsetHeight;
		}
		if (window.innerHeight) {
			winH = window.innerHeight;
		}
		return winH - document.getElementById('canvas').offsetTop;
	}, NULL);

    // hack: inset by 1 pixel to avoid scrollbars
    w -= 1;
    h -= 1;

	OBJ result = newObj(ArrayClass, 2, nilObj);
	FIELD(result, 0) = int2obj(w);
	FIELD(result, 1) = int2obj(h);
	return result;
}

static OBJ primBrowserScreenSize(int nargs, OBJ args[]) {
	int w = EM_ASM_INT({
		return screen.width;
	}, NULL);

	int h = EM_ASM_INT({
		return screen.height;
	}, NULL);

	OBJ result = newObj(ArrayClass, 2, nilObj);
	FIELD(result, 0) = int2obj(w);
	FIELD(result, 1) = int2obj(h);
	return result;
}

static OBJ primSetFillBrowser(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();

	if (trueObj != args[0]) {
		if (falseObj != args[0]) {
			return primFailed("Expected a boolean (true or false)"); return nilObj;
		}
		emscripten_exit_soft_fullscreen();
		return nilObj;
	}

	EmscriptenFullscreenStrategy strategy;
	strategy.scaleMode = EMSCRIPTEN_FULLSCREEN_SCALE_DEFAULT;
	strategy.canvasResolutionScaleMode = EMSCRIPTEN_FULLSCREEN_CANVAS_SCALE_NONE;
	strategy.filteringMode = EMSCRIPTEN_FULLSCREEN_FILTERING_DEFAULT;
	strategy.canvasResizedCallback = NULL;
	strategy.canvasResizedCallbackUserData = NULL;

	emscripten_enter_soft_fullscreen("canvas", &strategy);
	return nilObj;
}

static OBJ primBrowserFileImport(int nargs, OBJ args[]) {
	EM_ASM({ importFile(); }, 0);
	return nilObj;
}

static OBJ primBrowserGetDroppedFile(int nargs, OBJ args[]) {
	int dropCount = EM_ASM_INT({ return GP.droppedFiles.length; }, NULL);
	if (!dropCount) return nilObj; // no files

	int nameSize = 0;
	int contentsSize = 0;
	EM_ASM_({
		var file = GP.droppedFiles[0];
		Module.HEAPU32[($0 / 4)] = file.name.length;
		Module.HEAPU32[($1 / 4)] = file.contents.byteLength;
	}, &nameSize, &contentsSize);

	OBJ fileName = newArray(nameSize);
	EM_ASM_({
		var file = GP.droppedFiles[0];
		var dst = $0 / 4;
		var len = $1;
		for (var i = 0; i < len; i++) {
			Module.HEAPU32[dst++] = (file.name[i] << 1) | 1;
		}
	}, &FIELD(fileName, 0), nameSize);

	OBJ contents = newBinaryData(contentsSize);
	if (!contents) {
		printf("Insufficient memory for dropped file (%ul bytes needed); skipping.\n", contentsSize);
		EM_ASM({ GP.droppedFiles.shift(); }, 0); // remove the first entry
		return nilObj; // could not allocate memory for file contents; ignore drop
	}

	EM_ASM_({
		var file = GP.droppedFiles[0];
		var data = new Uint8Array(file.contents);
		var dst = $0;
		var len = $1;
		for (var i = 0; i < len; i++) {
			Module.HEAPU8[dst++] = data[i];
		}
	}, &FIELD(contents, 0), contentsSize);

	OBJ result = newArray(2);
	FIELD(result, 0) = fileName;
	FIELD(result, 1) = contents;

	EM_ASM({ GP.droppedFiles.shift(); }, 0); // remove the first entry

	return result;
}

static OBJ primBrowserGetDroppedText(int nargs, OBJ args[]) {
	int len = EM_ASM_INT({
		return GP.droppedTextBytes.length;
	}, NULL);
	if (!len) return nilObj;

	if (!canAllocate(len / 4)) return nilObj;
	OBJ result = allocateString(len);
	EM_ASM_({
		var dst = $0;
		var len = $1;
		for (var i = 0; i < len; i++) {
			Module.HEAPU8[dst++] = GP.droppedTextBytes[i];
		}
		GP.droppedTextBytes = []; // clear dropped text
	}, &FIELD(result, 0), len);

	return result;
}

OBJ primBrowserGetMessage(int nargs, OBJ args[]) {
	int len = EM_ASM_INT({
		if (0 == GP.messages.length) return 0;
		return GP.messages[0].length;
	}, NULL);
	if (!len) return nilObj;

	if (!canAllocate(len / 4)) return nilObj;
	OBJ result = allocateString(len);
	EM_ASM_({
		var src = GP.messages.pop();
		var dst = $0;
		var len = $1;
		for (var i = 0; i < len; i++) {
			Module.HEAPU8[dst++] = src[i];
		}
	}, &FIELD(result, 0), len);

	return result;
}

OBJ primBrowserPostMessage(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return primFailed("Argument must be a string");
	int postToParent = ((nargs > 1) && (trueObj == args[1]));

	EM_ASM_({
		if ($1) {
			window.parent.postMessage(UTF8ToString($0), "*");
		} else {
			window.postMessage(UTF8ToString($0), "*");
		}
	}, obj2str(args[0]), postToParent);
	return nilObj;
}

// ***** Mobile Browser and Browser API Detection *****

static OBJ primBrowserIsMobile(int nargs, OBJ args[]) {
	int isMobile = EM_ASM_INT({
		return (/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent));
	}, NULL);
	return isMobile ? trueObj : falseObj;
}

static OBJ primBrowserHasLanguage(int nargs, OBJ args[]) {
	if (nargs < 1) return falseObj;
	if (NOT_CLASS(args[0], StringClass)) return primFailed("Argument must be a string");

	int result = EM_ASM_INT({
		var langCode = UTF8ToString($0);
		for (var i = 0; i < navigator.languages.length; i++) {
			if (navigator.languages[i].indexOf(langCode) > -1) return true;
		}
		return false;
	}, obj2str(args[0]));
	return result ? trueObj : falseObj;
}

static OBJ primBrowserIsChromeOS(int nargs, OBJ args[]) {
	int isChromeOS = EM_ASM_INT({
		return (/(CrOS)/.test(navigator.userAgent));
	}, NULL);
	return isChromeOS ? trueObj : falseObj;
}

static OBJ primBrowserHasWebSerial(int nargs, OBJ args[]) {
	int hasWebSerial = EM_ASM_INT({
		return hasWebSerial() || hasWebBluetooth();
	}, NULL);
	return hasWebSerial ? trueObj : falseObj;
}

// ***** Browser File Operations *****

static OBJ primBrowserReadFile(int nargs, OBJ args[]) {
	char *extension = "";
	if ((nargs > 0) && (IS_CLASS(args[0], StringClass))) extension = obj2str(args[0]);
	EM_ASM_({
		GP_ReadFile(UTF8ToString($0));
	}, extension);
	return nilObj;
}

static OBJ primBrowserWriteFile(int nargs, OBJ args[]) {
	char *suggestedFileName = "";
	char *id = "";
	if (nargs < 1) return notEnoughArgsFailure();
	if ((nargs > 1) && (IS_CLASS(args[1], StringClass))) suggestedFileName = obj2str(args[1]);
	if ((nargs > 2) && (IS_CLASS(args[2], StringClass))) id = obj2str(args[2]);

	if (IS_CLASS(args[0], StringClass)) {
		EM_ASM_({
			GP_writeFile(UTF8ToString($0), UTF8ToString($1), UTF8ToString($2));
		}, obj2str(args[0]), suggestedFileName, id);
	} else if (IS_CLASS(args[0], BinaryDataClass)) {
		EM_ASM_({
			let buf = new Uint8Array(HEAPU8.buffer, $0, $1);
			GP_writeFile(buf, UTF8ToString($2), UTF8ToString($3));
		}, &FIELD(args[0], 0), objBytes(args[0]), suggestedFileName, id);
	} else {
		return primFailed("Argument must be a string");
	}
	return nilObj;
}

static OBJ primBrowserLastSaveName(int nargs, OBJ args[]) {
	int len = EM_ASM_INT({
		if (GP.lastSavedFileName) {
			return (new TextEncoder()).encode(GP.lastSavedFileName).length;
		} else {
			return 0;
		}
	});

	if (!len) return nilObj;

	if (!canAllocate(len / 4)) return nilObj;
	OBJ result = allocateString(len);
	EM_ASM_({
		var dst = $0;
		var len = $1;
		var s = (new TextEncoder()).encode(GP.lastSavedFileName);
		for (var i = 0; i < len; i++) {
			Module.HEAPU8[dst++] = s[i];
		}
		GP.lastSavedFileName = null; // clear name after reading
	}, &FIELD(result, 0), len);

	return result;
}

// ***** Browser User Preferences *****

static OBJ primBrowserWritePrefs(int nargs, OBJ args[]) {
	char *jsonData = "";
	if ((nargs > 0) && (IS_CLASS(args[0], StringClass))) jsonData = obj2str(args[0]);
	EM_ASM_({
	    if ((typeof chrome !== 'undefined') && (typeof chrome.storage !== 'undefined')) {
 			chrome.storage.sync.set(
				{ userPrefs: UTF8ToString($0) },
				function() {});
	    } else {
		    localStorage.setItem('user-prefs', UTF8ToString($0));
		}
	}, jsonData);
	return nilObj;
}

static OBJ primBrowserReadPrefs(int nargs, OBJ args[]) {
	int len = EM_ASM_INT({
	    if ((typeof chrome !== 'undefined') && (typeof chrome.storage !== 'undefined')) {
            chrome.storage.sync.get(
                ['userPrefs'],
                function(result) { GP.prefs = result.userPrefs; });
	    } else {
	        GP.prefs = localStorage.getItem('user-prefs');
	    }
	    if (!GP.prefs) return 0;
		return (new TextEncoder()).encode(GP.prefs).length;
	});

	if (!len) return nilObj;

	if (!canAllocate(len / 4)) return nilObj;
	OBJ result = allocateString(len);
	EM_ASM_({
		var dst = $0;
		var len = $1;
		var prefs =
			(new TextEncoder()).encode(GP.prefs);
		for (var i = 0; i < len; i++) {
			Module.HEAPU8[dst++] = prefs[i];
		}
	}, &FIELD(result, 0), len);

	return result;
}

// Boardie Support

static OBJ primBrowserOpenBoardie(int nargs, OBJ args[]) {
	EM_ASM_({ GP_openBoardie(); });
	return nilObj;
}

static OBJ primBrowserCloseBoardie(int nargs, OBJ args[]) {
	EM_ASM_({ GP_closeBoardie(); });
	return nilObj;
}

static OBJ primBoardiePutFile(int nargs, OBJ args[]) {
	EM_ASM_(
		{
			var fileName = UTF8ToString($0);
			if (fileName === 'user-prefs') return;
			var data = Module.HEAPU8.subarray($1, $1 + $2);
			var dataString = "";
			for (var i = 0; i < data.length; i++) {
                dataString += String.fromCharCode(data[i]);
			}
			window.localStorage[fileName] = dataString;
		},
		obj2str(args[0]), // filename
		&FIELD(args[1], 0), // file data
		obj2int(args[2]) // file size
	);
	return nilObj;
}
static OBJ primBoardieGetFile(int nargs, OBJ args[]) {
	int fileSize =
		EM_ASM_INT(
			{ return window.localStorage[UTF8ToString($0)].length },
			obj2str(args[0])
		);
	OBJ result = newBinaryData(fileSize);

	EM_ASM_(
		{
			var fileName = UTF8ToString($1);
			if (fileName === 'user-prefs') return;
			var file = window.localStorage[fileName];
			for (var i = 0; i < file.length; i++) {
				setValue($0++, file.charCodeAt(i), 'i8');
			}
		},
		&FIELD(result, 0),
		obj2str(args[0])
	);
	return result;
}

static OBJ primBoardieListFiles(int nargs, OBJ args[]) {
	int fileCount =
			EM_ASM_INT({
				return Object.keys(window.localStorage).filter(
					fn => fn !== 'user-prefs').length;
			});
	OBJ fileList = newObj(ArrayClass, fileCount, nilObj);

	for (int i = 0; i < fileCount; i++) {
		int length = EM_ASM_INT(
			{ return Object.keys(window.localStorage).filter(
					fn => fn !== 'user-prefs')[$0].length; },
			i
		);
		OBJ fileName = allocateString(length);
		EM_ASM_(
			{
				var fileName = Object.keys(window.localStorage).filter(
					fn => fn !== 'user-prefs')[$0];
				stringToUTF8(fileName, $1, fileName.length + 1);
			},
			i,
			&FIELD(fileName, 0)
		);
		FIELD(fileList, i) = fileName;
	}
	return fileList;
}

// ***** Browser Canvas Shadow Effects *****

static OBJ primBrowserSetShadow(int nargs, OBJ args[]) {
	if ((nargs < 3) || !isInt(args[1]) || !isInt(args[2])) return nilObj;
	OBJ color = args[0];
	int offset = obj2int(args[1]);
	int blur = obj2int(args[2]);

	int r = 0, g = 0, b = 0, a = 255;
	int words = objWords(color);
	if (words >= 3) {
		r = clip(obj2int(FIELD(color, 0)), 0, 255);
		g = clip(obj2int(FIELD(color, 1)), 0, 255);
		b = clip(obj2int(FIELD(color, 2)), 0, 255);
		a = (words <= 3) ? 255 : clip(obj2int(FIELD(color, 3)), 0, 255);
	}

	EM_ASM({
		setShadow($0, $1, $2, $3, $4, $5);
	}, r, g, b, a / 255.0, offset, blur);
	return nilObj;
}

static OBJ primBrowserClearShadow(int nargs, OBJ args[]) {
	EM_ASM({
		clearShadow();
	}, 0);
	return nilObj;
}

// ***** Graphics Helper Functions *****

static inline uint32 alphaBlend(uint32 dstPix, uint32 srcPix, int srcAlpha) {
	// Return the pixel value of srcPix alpha-blended with dstPix.
	// srcAlpha is the alpha of srcPix multiplied by the global alpha.

	int dstAlpha = (dstPix >> 24) & 0xFF;
	int invAlpha = 255 - srcAlpha;
	int a = srcAlpha + ((dstAlpha * invAlpha) / 255);
	int r = ((srcAlpha * ((srcPix >> 16) & 0xFF)) + (invAlpha * ((dstPix >> 16) & 0xFF))) / 255;
	int g = ((srcAlpha * ((srcPix >> 8) & 0xFF)) + (invAlpha * ((dstPix >> 8) & 0xFF))) / 255;
	int b = ((srcAlpha * (srcPix & 0xFF)) + (invAlpha * (dstPix & 0xFF))) / 255;
	return (a << 24) | (r << 16) | (g << 8) | b;
}

static void finalizeTexture(OBJ obj) {
	ADDR *a = (ADDR*)BODY(obj);
	if (NOT_CLASS(obj, ExternalReferenceClass) ||
		(objWords(obj) < ExternalReferenceWords) ||
		(a[1] != (ADDR) finalizeTexture)) {
			return;
	}
	EM_ASM_({
		var cnvID = $0 - 1;
		if ((cnvID >= 0) && (cnvID < GP.canvasCache.length)) {
			GP.canvasCache[cnvID] = null;
		}
	}, (int) a[0]);

	a[0] = NULL;
}

static void freeCanvas(int cnvID) {
	EM_ASM_({
		var cnvID = $0 - 1;
		if ((cnvID >= 0) && (cnvID < GP.canvasCache.length)) {
			GP.canvasCache[cnvID] = null;
		}
	}, cnvID);
}

static int canvasID(OBJ obj) {
	// If obj is a texture reference, return its id. Otherwise, return -1.

	if (objWords(obj) < 3) return -1;
	OBJ ref = FIELD(obj, 2);
	if (NOT_CLASS(ref, ExternalReferenceClass)) return -1;
	ADDR *a = (ADDR*)BODY(ref);
	if (a[1] != ((ADDR) finalizeTexture)) return -1;
	return (int) a[0];
}

static int colorWord(OBJ color) {
	int r = 0, g = 0, b = 0, a = 255;
	int words = objWords(color);
	if (words >= 3) {
		r = clip(obj2int(FIELD(color, 0)), 0, 255);
		g = clip(obj2int(FIELD(color, 1)), 0, 255);
		b = clip(obj2int(FIELD(color, 2)), 0, 255);
		a = (words <= 3) ? 255 : clip(obj2int(FIELD(color, 3)), 0, 255);
	}
	return (a << 24) | (r << 16) | (g << 8) | b;
}

static inline int isBitmap(OBJ bitmap) {
	return
		(objWords(bitmap) >= 3) &&
		isInt(FIELD(bitmap, 0)) && isInt(FIELD(bitmap, 1)) &&
		IS_CLASS(FIELD(bitmap, 2), BinaryDataClass) &&
		objWords(FIELD(bitmap, 2)) == (obj2int(FIELD(bitmap, 0)) * obj2int(FIELD(bitmap, 1)));
}

static void setClipRect(OBJ clipRectObj) {
	EM_ASM({
		GP.clipLeft = GP.clipTop = GP.clipWidth = GP.clipHeight = null;
	}, 0);
	if (!clipRectObj || (objWords(clipRectObj) != 4)) return;

	int left = (int) evalFloat(FIELD(clipRectObj, 0));
	int top = (int) evalFloat(FIELD(clipRectObj, 1));
	int width = (int) evalFloat(FIELD(clipRectObj, 2));
	int height = (int) evalFloat(FIELD(clipRectObj, 3));
	EM_ASM_({
		GP.clipLeft = $0;
		GP.clipTop = $1;
		GP.clipWidth = $2;
		GP.clipHeight = $3;
	}, left, top, width, height);
}

// ***** Canvas-based graphics primitives *****

static OBJ primOpenWindow(int nargs, OBJ args[]) {
    // Note: We always use retina mode the browser.

	int w = intOrFloatArg(0, 500, nargs, args);
	int h = intOrFloatArg(1, 500, nargs, args);

	EM_ASM_({
		var w = $0;
		var h = $1;

        // make background gray to make any gaps less noticable
		document.body.style.backgroundColor = "rgb(200,200,200)";

		var winCnv = document.getElementById('canvas');
		if (winCnv) {
		    winCnv.style.setProperty('margin-top', -19 + 'px'); // avoid gray band in Chrome
			winCnv.style.setProperty('width', w + 'px');
			winCnv.style.setProperty('height', h + 'px');
			winCnv.width = 2 * w;
			winCnv.height = 2 * h;
			GP.isRetina = true;
		}
	}, w, h);

	return nilObj;
}

static OBJ primCloseWindow(int nargs, OBJ args[]) { return nilObj; } // noop

static OBJ primWindowSize(int nargs, OBJ args[]) {
	int logicalW = EM_ASM_INT({
		var winCnv = document.getElementById('canvas');
		return winCnv ? winCnv.clientWidth : 0;
	}, NULL);
	int logicalH = EM_ASM_INT({
		var winCnv = document.getElementById('canvas');
		return winCnv ? winCnv.clientHeight : 0;
	}, NULL);

	int physicalW = EM_ASM_INT({
		var winCnv = document.getElementById('canvas');
		return winCnv ? winCnv.width : 0;
	}, NULL);
	int physicalH = EM_ASM_INT({
		var winCnv = document.getElementById('canvas');
		return winCnv ? winCnv.height : 0;
	}, NULL);


	OBJ result = newArray(4);
	FIELD(result, 0) = int2obj(logicalW);
	FIELD(result, 1) = int2obj(logicalH);
	FIELD(result, 2) = int2obj(physicalW);
	FIELD(result, 3) = int2obj(physicalH);
	return result;
}

static OBJ primSetFullScreen(int nargs, OBJ args[]) { return nilObj; } // noop
static OBJ primSetWindowTitle(int nargs, OBJ args[]) { return nilObj; } // noop

static OBJ primClearWindowBuffer(int nargs, OBJ args[]) {
	uint32 color = (nargs > 0) ? colorWord(args[0]) : 0xFFFFFFFF;

	EM_ASM_({
		var color = $0;
		var winCnv = document.getElementById('canvas');
		if (winCnv) {
			var w = winCnv.width;
			var h = winCnv.height;
			var ctx = winCnv.getContext('2d');
			var a = ((color >> 24) & 255) / 255.0;
			var r = (color >> 16) & 255;
			var g = (color >> 8) & 255;
			var b = color & 255;
			ctx.fillStyle = 'rgba(' + r + ',' + g + ',' + b + ',' + a + ')';
			ctx.fillRect(0, 0, w, h);
		}
	}, color);

	return nilObj;
}

static OBJ primFlipWindowBuffer(int nargs, OBJ args[]) { return nilObj; } // noop

static OBJ primCreateTexture(int nargs, OBJ args[]) {
	int w = intOrFloatArg(0, -1, nargs, args);
	int h = intOrFloatArg(1, -1, nargs, args);
	OBJ color = (nargs > 2) ? args[2] : nilObj;

	if (w < 1) w = 1;
	if (w > MAX_TEXTURE_SIZE) w = MAX_TEXTURE_SIZE;
	if (h < 1) h = 1;
	if (h > MAX_TEXTURE_SIZE) h = MAX_TEXTURE_SIZE;

	int r = 0, g = 0, b = 0, a = 0;
	int words = objWords(color);
	if (words >= 3) {
		r = clip(obj2int(FIELD(color, 0)), 0, 255);
		g = clip(obj2int(FIELD(color, 1)), 0, 255);
		b = clip(obj2int(FIELD(color, 2)), 0, 255);
		a = (words <= 3) ? 255 : clip(obj2int(FIELD(color, 3)), 0, 255);
	}

	int cnvID = EM_ASM_INT({
		var w = $0;
		var h = $1;
		var r = $2;
		var g = $3;
		var b = $4;
		var a = $5 / 255.0;

		var newCnv = document.createElement('canvas');
		newCnv.setAttribute('width', w);
		newCnv.setAttribute('height', h);

		var ctx = newCnv.getContext('2d');
		var c = 'rgba(' + r + ',' + g + ',' + b + ',' + a + ')';
		ctx.fillStyle = c;
		ctx.fillRect(0, 0, w, h);

		if (!GP.canvasCache) GP.canvasCache = [];
		for (var i = 0; i < GP.canvasCache.length; i++) { // use an empty slot, if possible
			if (GP.canvasCache[i] == null) {
				GP.canvasCache[i] = newCnv;
				return i + 1;
			}
		}
		GP.canvasCache.push(newCnv);
		return GP.canvasCache.length; // index + 1; never zero
	}, w, h, r, g, b, a);

	OBJ ref = newBinaryObj(ExternalReferenceClass, ExternalReferenceWords);
	ADDR *addr = (ADDR*)BODY(ref);
	addr[0] = (ADDR) cnvID;
	addr[1] = (ADDR) finalizeTexture;
	return ref;
}

static OBJ primDestroyTexture(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	finalizeTexture(args[0]);
	return nilObj;
}

static OBJ primShowTexture(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();

	OBJ dst = args[0];
	int srcID = canvasID(args[1]);
	if (!srcID) return nilObj;
	int x = floatArg(2, 0, nargs, args);
	int y = floatArg(3, 0, nargs, args);
	int globalAlpha = intOrFloatArg(4, 255, nargs, args);
	globalAlpha = clip(globalAlpha, 0, 255);
	double xScale = floatArg(5, 1.0, nargs, args);
	double yScale = floatArg(6, 1.0, nargs, args);
	double rotation = floatArg(7, 0.0, nargs, args);
	if (rotation != 0.0) rotation = (rotation * M_PI) / -180.0; // convert to radians; rotate counter clockwise
	// flip is never used
//	int flip = intArg(8, 0, nargs, args); // 0 - none, 1 - horizontal, 2 - vertical
	int blendFlag = intArg(9, 1, nargs, args); // 0 - overwrite destination, 1 - alpha blend (default)

	OBJ clipRectObj = (nargs > 10) ? args[10] : nilObj;

	int dstID = 0;
	if (dst != nilObj) { // if dst not nil, draw onto it; otherwise draw onto the display
		dstID = canvasID(dst);
		if (dstID < 0) return primFailed("Bad texture");
	}

	int clipLeft = 0, clipTop = 0, clipWidth = 0, clipHeight = 0;
	if (clipRectObj) {
		clipLeft = (int) evalFloat(FIELD(clipRectObj, 0));
		clipTop = (int) evalFloat(FIELD(clipRectObj, 1));
		clipWidth = (int) evalFloat(FIELD(clipRectObj, 2));
		clipHeight = (int) evalFloat(FIELD(clipRectObj, 3));
		if ((clipWidth <= 0) || (clipHeight <= 0)) return nilObj;
	}

	EM_ASM_({
		var dstID = $0 - 1;
		var srcID = $1 - 1;
		var x = $2;
		var y = $3;
		var a = $4;
		var xScale = $5;
		var yScale = $6;
		var rotation = $7;
		var blendFlag = $8;
		var clipLeft = $9;
		var clipTop = $10;
		var clipWidth = $11;
		var clipHeight = $12;

		var dstCnv = (dstID < 0) ? document.getElementById('canvas') : GP.canvasCache[dstID];
		if (!dstCnv) return;
		var srcCnv = GP.canvasCache[srcID];
		if (!srcCnv) return;
		var ctx = dstCnv.getContext('2d');
		ctx.save();
		if (GP.shadowColor) setContextShadow(ctx);
		if (clipWidth > 0) {
			ctx.beginPath();
			ctx.rect(clipLeft, clipTop, clipWidth, clipHeight);
			ctx.clip();
		}
		if (!blendFlag) ctx.clearRect(x, y, srcCnv.width, srcCnv.height);
		ctx.globalAlpha = a;
		if ((xScale != 1) || (yScale != 1) || (rotation != 0)) {
			ctx.translate(x + ((xScale * srcCnv.width) / 2), y + ((yScale * srcCnv.height) / 2)); // center of scaled image
			ctx.scale(xScale, yScale);
			ctx.rotate(rotation);
			ctx.globalAlpha = a;
			ctx.drawImage(srcCnv, -srcCnv.width / 2, -srcCnv.height / 2); // draw image centered on (0,0)
		} else {
			ctx.drawImage(srcCnv, x, y);
		}
		ctx.restore();
		ctx.shadowColor = 'transparent';
	}, dstID, srcID, x, y, globalAlpha / 255.0, xScale, yScale, rotation, blendFlag,
		clipLeft, clipTop, clipWidth, clipHeight);

	return nilObj;
}

static OBJ copyCanvasToBitmap(int srcID, OBJ bitmap) {
	if (!isBitmap(bitmap)) return primFailed("Bad bitmap");

	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	OBJ bmData = FIELD(bitmap, 2);
	if (objWords(bmData) != (w * h)) return primFailed("Bad bitmap size");

	EM_ASM_({
		var bmData = $0;
		var w = $1;
		var h = $2;
		var srcID = $3 - 1;

		var cnv = GP.canvasCache[srcID];
		if ((!cnv) || (w != cnv.width) || (h != cnv.height)) return;
		var ctx = cnv.getContext('2d');
		var imgData = ctx.getImageData(0, 0, w, h);
		var imgBytes = imgData.data;
		var srcIndex = bmData;
		for (var i = 0; i < imgBytes.length; i += 4) {
			Module.HEAPU8[srcIndex++] = imgBytes[i + 2];
			Module.HEAPU8[srcIndex++] = imgBytes[i + 1];
			Module.HEAPU8[srcIndex++] = imgBytes[i];
			Module.HEAPU8[srcIndex++] = imgBytes[i + 3];
		}
	}, &FIELD(bmData, 0), w, h, srcID);
	return nilObj;
}

static OBJ primReadTexture(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();

	OBJ bitmap = args[0];
	int srcID = canvasID(args[1]);
	if (srcID < 1) return primFailed("Bad texture");

	if (!isBitmap(bitmap)) return primFailed("Bad bitmap");
	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	OBJ bmData = FIELD(bitmap, 2);
	if (objWords(bmData) != (w * h)) return primFailed("Bad bitmap size");

	EM_ASM_({
		var bmData = $0;
		var w = $1;
		var h = $2;
		var srcID = $3 - 1;

		var cnv = GP.canvasCache[srcID];
		if ((!cnv) || (w != cnv.width) || (h != cnv.height)) return;
		var ctx = cnv.getContext('2d');
		var imgData = ctx.getImageData(0, 0, w, h);
		var imgBytes = imgData.data;
		var srcIndex = bmData;
		for (var i = 0; i < imgBytes.length; i += 4) {
			Module.HEAPU8[srcIndex++] = imgBytes[i + 2];
			Module.HEAPU8[srcIndex++] = imgBytes[i + 1];
			Module.HEAPU8[srcIndex++] = imgBytes[i];
			Module.HEAPU8[srcIndex++] = imgBytes[i + 3];
		}
	}, &FIELD(bmData, 0), w, h, srcID);

	return nilObj;
}

static OBJ primUpdateTexture(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();

	int dstID = canvasID(args[0]);
	if (dstID < 1) return primFailed("Bad texture");
	OBJ bitmap = args[1];
	if (!isBitmap(bitmap)) return primFailed("Bad bitmap");
	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	OBJ bmData = FIELD(bitmap, 2);

	EM_ASM_({
		var dstID = $0 - 1;
		var bmData = $1;
		var w = $2;
		var h = $3;

		var cnv = GP.canvasCache[dstID];
		if ((!cnv) || (w != cnv.width) || (h != cnv.height)) return;
		var ctx = cnv.getContext('2d');
		var imgData = ctx.createImageData(w, h);
		var imgBytes = imgData.data;
		var srcIndex = bmData;
		for (var i = 0; i < imgBytes.length; i += 4) {
			imgBytes[i + 2] = Module.HEAPU8[srcIndex++];
			imgBytes[i + 1] = Module.HEAPU8[srcIndex++];
			imgBytes[i] = Module.HEAPU8[srcIndex++];
			imgBytes[i + 3] = Module.HEAPU8[srcIndex++];
		}
		ctx.putImageData(imgData, 0, 0);
	}, dstID, &FIELD(bmData, 0), w, h);

	return nilObj;
}

static void fillRectBitmap(OBJ bitmap, int x, int y, int w, int h, int c, int blendFlag) {
	int bitmapW = obj2int(FIELD(bitmap, 0));
	int bitmapH = obj2int(FIELD(bitmap, 1));
	int bmData = FIELD(bitmap, 2);
	int right = x + w;
	if (right > bitmapW) right = bitmapW;
	int bottom = y + h;
	if (bottom > bitmapH) bottom = bitmapH;
	int left = (x < 0) ? 0 : x;
	int top = (y < 0) ? 0 : y;
	int alpha = (c >> 24) & 0xFF;
	if (blendFlag && (alpha < 255)) { // do alpha blending
		if (alpha == 0) return; // source color is fully transparent; do nothing
		for (y = top; y < bottom; y++) {
			uint32 *dstPtr = &FIELD(bmData, 0) + (y * bitmapW) + left;
			for (int x = left; x < right; x++) {
				*dstPtr = alphaBlend(*dstPtr, c, alpha);
				dstPtr++;
			}
		}
	} else { // overwrite pixels, including alpha
		for (y = top; y < bottom; y++) {
			uint32 *dstPtr = &FIELD(bmData, 0) + (y * bitmapW) + left;
			for (int x = left; x < right; x++) *dstPtr++ = c;
		}
	}
}

static void fillRectCanvas(OBJ canvas, int x, int y, int w, int h, int c, int blendFlag) {
	int a = (c >> 24) & 0xFF;
	int r = (c >> 16) & 0xFF;
	int g = (c >> 8) & 0xFF;
	int b = c & 0xFF;

	EM_ASM_({
		var dstID = $0 - 1;
		var x = $1;
		var y = $2;
		var w = $3;
		var h = $4;
		var r = $5;
		var g = $6;
		var b = $7;
		var a = $8 / 255.0;
		var blendFlag = $9;

		var cnv = (dstID < 0) ? document.getElementById('canvas') : GP.canvasCache[dstID];
		if (!cnv) return;
		var ctx = cnv.getContext('2d');
		if (!blendFlag) ctx.clearRect(x, y, w, h);
		ctx.fillStyle = 'rgba(' + r + ',' + g + ',' + b + ',' + a + ')';
		ctx.fillRect(x, y, w, h);
	}, canvasID(canvas), x, y, w, h, r, g, b, a, blendFlag);
}

static OBJ primFillRect(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();

	OBJ dst = args[0];
	OBJ color = colorWord(args[1]);
	int x = intOrFloatArg(2, 0, nargs, args);
	int y = intOrFloatArg(3, 0, nargs, args);
	int w = intOrFloatArg(4, 100, nargs, args);
	int h = intOrFloatArg(5, 100, nargs, args);
	int blendFlag = intArg(6, 0, nargs, args); // 0 - overwrite destination (default), 1 - alpha blend

	if (isBitmap(dst)) {
		fillRectBitmap(dst, x, y, w, h, color, blendFlag);
	} else {
		fillRectCanvas(dst, x, y, w, h, color, blendFlag);
	}
	return nilObj;
}

static OBJ primDrawBitmap(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ dst = args[0];
	OBJ src = args[1];
	if (!isBitmap(src)) return primFailed("Bad bitmap");

	int x = intOrFloatArg(2, 0, nargs, args);
	int y = intOrFloatArg(3, 0, nargs, args);
	int globalAlpha = intOrFloatArg(4, 255, nargs, args);
	globalAlpha = clip(globalAlpha, 0, 255);
	int blendFlag = intArg(5, 1, nargs, args); // 0 - overwrite destination, 1 - alpha blend (default)
	OBJ clipRectObj = (nargs > 6) ? args[6] : nilObj;

	int w = obj2int(FIELD(src, 0));
	int h = obj2int(FIELD(src, 1));
	OBJ bmData = FIELD(src, 2);
	if (objWords(bmData) != (w * h)) return primFailed("Bad bitmap");
	if ((w <= 0) || (h <= 0)) return nilObj;

	int dstX = (x < 0) ? 0 : x;
	int dstY = (y < 0) ? 0 : y;
	int dstR = x + w;
	int dstB = y + h;
	int cpyW = w, cpyH = h;
	if (clipRectObj) {
		int clipLeft = (int) evalFloat(FIELD(clipRectObj, 0));
		int clipTop = (int) evalFloat(FIELD(clipRectObj, 1));
		int clipRight = clipLeft + (int) evalFloat(FIELD(clipRectObj, 2));
		int clipBottom = clipTop + (int) evalFloat(FIELD(clipRectObj, 3));
		if (clipLeft > dstX) dstX = clipLeft;
		if (clipTop > dstY) dstY = clipTop;
		if (clipRight < dstR) dstR = clipRight;
		if (clipBottom < dstB) dstB = clipBottom;
		cpyW = dstR - dstX;
		cpyH = dstB - dstY;
	}
	int srcX = dstX - x;
	int srcY = dstY - y;
	if (cpyW > (w - srcX)) cpyW = w - srcX;
	if (cpyH > (h - srcY)) cpyH = h - srcY;
	if ((cpyW <= 0) || (cpyH <= 0)) return nilObj;

	if (isBitmap(dst)) {
		int dstW = obj2int(FIELD(dst, 0));
		int dstH = obj2int(FIELD(dst, 1));
		int dstData = FIELD(dst, 2);

		if ((dstX >= dstW) || (dstY >= dstH)) return nilObj;
		int endX = dstX + cpyW;
		int endY = dstY + cpyH;
		if (endX > dstW) endX = dstW;
		if (endY > dstH) endY = dstH;
		for (y = dstY; y < endY; y++) {
			uint32 *srcPtr = &FIELD(bmData, 0) + (srcY++ * w) + srcX;
			uint32 *dstPtr = &FIELD(dstData, 0) + (y * dstW) + dstX;
			for (x = dstX; x < endX; x++) {
				uint32 srcPix = *srcPtr++;
				if (blendFlag) { // alpha blend
					int srcAlpha = ((((srcPix >> 24) & 255) * globalAlpha) / 255) & 0xFF;
					if (255 == srcAlpha) {
						*dstPtr = srcPix;
					} else if (srcAlpha > 0) {
						*dstPtr = alphaBlend(*dstPtr, srcPix, srcAlpha);
					}
					dstPtr++;
				} else {
					*dstPtr++ = srcPix;
				}
			}
		}
	} else {
		setClipRect(clipRectObj);
		EM_ASM_({
			var dstID = $0 - 1;
			var bmData = $1;
			var srcX = $2;
			var srcY = $3;
			var srcW = $4;
			var dstX = $5;
			var dstY = $6;
			var cpyW = $7;
			var cpyH = $8;
			var a = $9;
			var blendFlag = $10;

			var cnv = (dstID < 0) ? document.getElementById('canvas') : GP.canvasCache[dstID];
			if (!cnv) return;
			var ctx = cnv.getContext('2d');
			ctx.save();
			if (GP.clipLeft) {
				ctx.beginPath();
				ctx.rect(GP.clipLeft, GP.clipTop, GP.clipWidth, GP.clipHeight);
				ctx.clip();
			}
			var tmpCnv = document.createElement('canvas');
			tmpCnv.setAttribute('width', cpyW);
			tmpCnv.setAttribute('height', cpyH);
			var tmpCtx = tmpCnv.getContext('2d');
			var imgData = tmpCtx.createImageData(cpyW, cpyH);
			var imgBytes = imgData.data;
			var i = 0;
			for (var y = srcY; y < (srcY + cpyH); y++) {
				for (var x = srcX; x < (srcX + cpyW); x++) {
					// compute src index
					srcIndex = bmData + (4 * ((y * srcW) + x));
					imgBytes[i + 2] = Module.HEAPU8[srcIndex++];
					imgBytes[i + 1] = Module.HEAPU8[srcIndex++];
					imgBytes[i] = Module.HEAPU8[srcIndex++];
					imgBytes[i + 3] = Module.HEAPU8[srcIndex++];
					i += 4;
				}
			}
			tmpCtx.putImageData(imgData, 0, 0);
			if (!blendFlag) ctx.clearRect(x, y, tmpCnv.width, tmpCnv.height);
			ctx.globalAlpha = a;
			ctx.drawImage(tmpCnv, dstX, dstY);
			ctx.restore();
		}, canvasID(dst), &FIELD(bmData, 0), srcX, srcY, w, dstX, dstY, cpyW, cpyH,
			globalAlpha / 255.0, blendFlag);
	}
	return nilObj;
}

static int bitmapToTexture(OBJ bitmap) {
	// Helper function for primWarpBitmap. Copies a bitmap into a texture of the same size.

	if (!isBitmap(bitmap)) return -1;
	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	OBJ bmData = FIELD(bitmap, 2);

	int cnvID = EM_ASM_INT({
		var w = $0;
		var h = $1;
		var bmData = $2;

		// create canvas of given size
		var newCnv = document.createElement('canvas');
		newCnv.setAttribute('width', w);
		newCnv.setAttribute('height', h);

		if (!GP.canvasCache) GP.canvasCache = [];
		var i = 0;
		for (i = 0; i < GP.canvasCache.length; i++) { // use an empty slot, if possible
			if (GP.canvasCache[i] == null) {
				GP.canvasCache[i] = newCnv;
				break;
			}
		}
		if (i == GP.canvasCache.length) {
			GP.canvasCache.push(newCnv);
		}
		var cnvID = i + 1;

		// copy bitmap data into canvas
		var ctx = newCnv.getContext('2d');
		var imgData = ctx.createImageData(w, h);
		var imgBytes = imgData.data;
		var srcIndex = bmData;
		for (var i = 0; i < imgBytes.byteLength; i += 4) {
			imgBytes[i + 2] = Module.HEAPU8[srcIndex++];
			imgBytes[i + 1] = Module.HEAPU8[srcIndex++];
			imgBytes[i] = Module.HEAPU8[srcIndex++];
			imgBytes[i + 3] = Module.HEAPU8[srcIndex++];
		}
		ctx.putImageData(imgData, 0, 0);
		return cnvID;
	}, w, h, &FIELD(bmData, 0));

	return cnvID;
}

static OBJ primWarpBitmap(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();

	int centerX = intOrFloatArg(2, 0, nargs, args);
	int centerY = intOrFloatArg(3, 0, nargs, args);
	double scaleX = floatArg(4, 1, nargs, args);
	double scaleY = floatArg(5, 1, nargs, args);
	double rotation = floatArg(6, 0, nargs, args);
	OBJ clipRect = (nargs > 7) ? args[7] : nilObj;

	int dstID = (nilObj == args[0]) ? 0 : bitmapToTexture(args[0]);
	if (dstID < 0) return primFailed("warpBitmap destination must be a Bitmap or nil");
	int srcID = bitmapToTexture(args[1]);
	if (srcID < 0) return primFailed("Bad bitmap");

	setClipRect(clipRect);
	EM_ASM_({
		var dstID = $0 - 1;
		var srcID = $1 - 1;
		var centerX = $2;
		var centerY = $3;
		var scaleX = $4;
		var scaleY = $5;
		var rotation = $6;

		var dstCnv = (dstID < 0) ? document.getElementById('canvas') : GP.canvasCache[dstID];
		var srcCnv = (srcID < 0) ? document.getElementById('canvas') : GP.canvasCache[srcID];
		if ((!dstCnv) || (!srcCnv)) return;

		var halfSrcW = srcCnv.width / 2;
		var halfSrcH = srcCnv.height / 2;

		var ctx = dstCnv.getContext('2d');
		ctx.save();
		if (GP.clipLeft) {
			ctx.beginPath();
			ctx.rect(GP.clipLeft, GP.clipTop, GP.clipWidth, GP.clipHeight);
			ctx.clip();
		}
		ctx.translate(centerX - halfSrcW, centerY - halfSrcH); // position of top-left in dst before transforms
		ctx.translate(halfSrcW, halfSrcH); // rotate around center of scaled image
		ctx.rotate((rotation * Math.PI) / 180);
		ctx.scale(scaleX, scaleY);
		ctx.translate(-halfSrcW, -halfSrcH);
		ctx.drawImage(srcCnv, 0, 0);
		ctx.restore();
	}, dstID, srcID, centerX, centerY, scaleX, scaleY, rotation);

	if (nilObj != args[0]) {
		// if dst was not the screen, copy dst texture pixels into dst bitmap
		copyCanvasToBitmap(dstID, args[0]);
		freeCanvas(dstID);
	}
	freeCanvas(srcID);
	return nilObj;
}

static inline void plot(OBJ dst, int isBitmap, int x, int y, int width, int c) {
	// Plot a width x width square on the given bitmap or canvas.
	int halfW = width / 2;
	if (isBitmap) {
		fillRectBitmap(dst, (x - halfW), (y - halfW), width, width, c, true);
	} else {
		fillRectCanvas(dst, (x - halfW), (y - halfW), width, width, c, true);
	}
}

OBJ primDrawLineOnBitmap(int nargs, OBJ args[]) {
	OBJ dst = args[0];
	int x0 = intOrFloatArg(1, 0, nargs, args);
	int y0 = intOrFloatArg(2, 0, nargs, args);
	int x1 = intOrFloatArg(3, 0, nargs, args);
	int y1 = intOrFloatArg(4, 0, nargs, args);
	OBJ color = (nargs > 5) ? args[5] : nilObj;
	int lineWidth = intOrFloatArg(6, 1, nargs, args);

	int isBM = isBitmap(dst);
	int c = colorWord(color);

	// Bresenham's algorithm
	int dx = abs(x1 - x0);
	int dy = abs(y1 - y0);
	int sx = (x0 < x1) ? 1 : -1;
	int sy = (y0 < y1) ? 1 : -1;
	int err = dx - dy;
	while (true) {
		plot(dst, isBM, x0, y0, lineWidth, c);
		if ((x0 == x1) && (y0 == y1)) break;
		int e2 = 2 * err;
		if (e2 > -dy) {
			err -= dy;
			x0 += sx;
		}
		if ((x0 == x1) && (y0 == y1)) {
			plot(dst, isBM, x0, y0, lineWidth, c);
			break;
		}
		if (e2 < dx) {
			err += dx;
			y0 += sy;
		}
	}
	return nilObj;
}

// ***** User Input Primitives *****

OBJ primNextEvent(int nargs, OBJ args[]) {
	return getEvent();
}

OBJ primGetClipboard(int nargs, OBJ args[]) {
	int len = EM_ASM_INT({
		readGPClipboard();
		return GP.clipboardBytes.length;
	}, NULL);

	if (!canAllocate(len / 4)) return nilObj;
	OBJ result = allocateString(len);
	EM_ASM_({
		var dst = $0;
		var len = $1;
		for (var i = 0; i < len; i++) {
			Module.HEAPU8[dst++] = GP.clipboardBytes[i];
		}
	}, &FIELD(result, 0), len);
	return result;
}

OBJ primSetClipboard(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return primFailed("Argument must be a string");

	EM_ASM_({
		setGPClipboard(UTF8ToString($0));
	}, obj2str(args[0]));
	return nilObj;
}

OBJ primShowKeyboard(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();

	EM_ASM_({
		if ($0) {
			GP.clipboard.focus(); // may fail due to Emscripten's indirect event handling
			GP.clipboard.value = "";
		} else {
			document.activeElement.blur();
		}
	}, (args[0] == trueObj));
	return nilObj;
}

OBJ primSetCursor(int nargs, OBJ args[]) {
	if ((nargs < 1) || !IS_CLASS(args[0], StringClass)) return nilObj;

	EM_ASM_({
		document.body.style.setProperty('cursor', UTF8ToString($0));
	}, obj2str(args[0]));
	return nilObj;
}

static PrimEntry browserPrimList[] = {
	{"-----", NULL, "Browser Support"},
	{"browserURL",				primBrowserURL,			"Return the full URL of the current browser page."},
	{"startFetch",				primStartFetch,			"Start downloading the contents of a URL. Return an id that can be used to get the result. Argument: urlString"},
	{"fetchBytesReceived",		primFetchBytesReceived,	"Return the number number of bytes received by the fetch request so far. Argument: id"},
	{"fetchBytesExpected",		primFetchBytesExpected,	"Return the number bytes expected by the fetch request or zero if not yet known.  Argument: id"},
	{"fetchResult",				primFetchResult,		"Return the result of the fetch operation with the given id: a BinaryData object (success), false (failure), or nil if in progress. Argument: id"},
	{"browserSize",				primBrowserSize,		"Return the inner width and height of the browser window."},
	{"browserScreenSize",		primBrowserScreenSize,	"Return the width and height of the entire screen containing the browser."},
	{"setFillBrowser",			primSetFillBrowser,		"Set 'fill browser' mode. If true, the GP canvas is resized to fill the entire browser window."},
	{"browserFileImport",		primBrowserFileImport,	"Show a file input button that the user can click to import a file."},
	{"browserGetDroppedFile",	primBrowserGetDroppedFile,	"Get the next dropped file record array (fileName, binaryData), or nil if there isn't one."},
	{"browserGetDroppedText",	primBrowserGetDroppedText,	"Get last dropped or pasted text, or nil if there isn't any."},
	{"browserGetMessage",		primBrowserGetMessage,		"Get the next message from the browser, or nil if there isn't any."},
	{"browserPostMessage",		primBrowserPostMessage,		"Post a message to the browser using the 'postMessage' function."},
	{"browserIsMobile",			primBrowserIsMobile,		"Return true if running in a mobile browser."},
	{"browserHasLanguage",		primBrowserHasLanguage,		"Return true the given language code is in navigator.languages. Argument: language code string (e.g. 'en')."},
	{"browserIsChromeOS",		primBrowserIsChromeOS,		"Return true if running as a Chromebook app."},
	{"browserHasWebSerial",		primBrowserHasWebSerial,	"Return true the browser supports the Web Serial API."},
	{"browserReadFile",			primBrowserReadFile,		"Select and read a file in the browser. Args: [extension]"},
	{"browserWriteFile",		primBrowserWriteFile,		"Select and write a file the browser. Args: data [suggestedFileName, id]"},
	{"browserLastSaveName",		primBrowserLastSaveName,	"Return the name of the most recent file save."},
	{"browserSetShadow",		primBrowserSetShadow,		"Set the Canvas shadow color, offset, and blur for following graphics operations. Args: color, offset, blur"},
	{"browserClearShadow",		primBrowserClearShadow,		"Disable the Canvas shadow effect."},
	{"browserReadPrefs",		primBrowserReadPrefs,		"Read user preferences from localStorage."},
	{"browserWritePrefs",		primBrowserWritePrefs,		"Write user preferences to localStorage. Args: jsonString"},
	{"browserOpenBoardie",      primBrowserOpenBoardie,		"Open boardie."},
	{"browserCloseBoardie",     primBrowserCloseBoardie,	"Disconnect boardie."},
	{"boardiePutFile",          primBoardiePutFile,         "Store a file in boardie's file system."},
	{"boardieGetFile",          primBoardieGetFile,         "Read a file from boardie's file system."},
	{"boardieFileList",         primBoardieListFiles,       "Get a list of files in boardie's file system."},
};

static PrimEntry graphicsPrimList[] = {
	{"-----", NULL, "Graphics: Windows"},
	{"openWindow",		primOpenWindow,			"Open the graphics window. Arguments: [width height tryRetinaFlag title]"},
	{"closeWindow",		primCloseWindow,		"Close the graphics window."},
	{"windowSize",		primWindowSize,			"Return an array containing the width and height of the window in logical and physical (high resolution) pixels."},
	{"setFullScreen",	primSetFullScreen,		"Set full screen mode. Argument: fullScreenFlag"},
	{"setWindowTitle",	primSetWindowTitle,		"Set the graphics window title to the given string."},
	{"clearBuffer",		primClearWindowBuffer,	"Clear the offscreen window buffer to a color. Ex. clearBuffer (color 255 0 0); flipBuffer"},
	{"flipBuffer",		primFlipWindowBuffer,	"Flip the onscreen and offscreen window buffers to make changes visible."},
	{"-----", NULL, "Graphics: Textures"},
	{"createTexture",	primCreateTexture,		"Create a reference to new texture (a drawing surface in graphics memory). Arguments: width height [fillColor]. Ex. ref = (createTexture 100 100)"},
	{"destroyTexture",	primDestroyTexture,		"Destroy a texture reference. Ex. destroyTexture ref"},
	{"showTexture",		primShowTexture,		"Draw the given texture. Draw to window buffer if dstTexture is nil. Arguments: dstTexture srcTexture [x y alpha xScale yScale rotationDegrees flip blendMode clipRect]"},
	{"readTexture",		primReadTexture,		"Copy the given texture into the given bitmap. Arguments: bitmap texture"},
	{"updateTexture",	primUpdateTexture,		"Update the given texture from the given bitmap. Arguments: texture bitmap"},
	{"-----", NULL, "Graphics: Drawing"},
	{"fillRect",		primFillRect,			"Draw a rectangle. Draw to window buffer if textureOrBitmap is nil. Arguments: textureOrBitmap color [x y width height blendMode]."},
	{"drawBitmap",		primDrawBitmap,			"Draw a bitmap. Draw to window buffer if textureOrBitmap is nil. Arguments: textureOrBitmap srcBitmap [x y alpha blendMode clipRect]"},
	{"warpBitmap",		primWarpBitmap,			"Scaled and/or rotate a bitmap. Arguments: dstBitmap srcBitmap [x y scaleX scaleY rotation]"},
	{"drawLineOnBitmap", primDrawLineOnBitmap,	"Draw a line on a bitmap. Only 1-pixel anti-aliased lines are supported. Arguments: dstBitmap x1 y1 x2 y2 [color lineWidth antiAliasFlag]"},
	{"-----", NULL, "User Input"},
	{"nextEvent",		primNextEvent,			"Return a dictionary representing the next user input event, or nil if the queue is empty."},
	{"getClipboard",	primGetClipboard,		"Return the string from the clipboard, or the empty string if the cliboard is empty."},
	{"setClipboard",	primSetClipboard,		"Set the clipboard to the given string."},
	{"showKeyboard",	primShowKeyboard,		"Show or hide the on-screen keyboard on a touchsceen devices. Argument: true or false."},
	{"setCursor",		primSetCursor,			"Change the mouse pointer appearance. Argument: cursorNumber (0 -> arrow, 3 -> crosshair, 11 -> hand...)"},
};

PrimEntry* browserPrimitives(int *primCount) {
	*primCount = sizeof(browserPrimList) / sizeof(PrimEntry);
	return browserPrimList;
}

PrimEntry* graphicsPrimitives(int *primCount) {
	*primCount = sizeof(graphicsPrimList) / sizeof(PrimEntry);
	return graphicsPrimList;
}
