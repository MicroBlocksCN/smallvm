// browserPrims.c
// Primitives for the browser version of GP.
// John Maloney, Jan 2015

// To do:
//	 [ ] remove flip parameter from showTexture (and fix calls in lib)

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <emscripten.h>
#include <emscripten/html5.h>

#include "mem.h"
#include "interp.h"

#define MAX_TEXTURE_SIZE 2048

// ***** Fetch request state *****

typedef enum {IN_PROGRESS, DONE, FAILED} FetchStatus;

typedef struct {
	int id;
	FetchStatus status;
	int byteCount;
	char *data;
} FetchRequest;

#define MAX_REQUESTS 1000
FetchRequest requests[MAX_REQUESTS];

static int nextFetchID = 100;

// ***** Helper Functions *****

static int isInBrowser() {
	return EM_ASM_INT({
		return !ENVIRONMENT_IS_NODE;
	}, NULL);
}

static void fetchDoneCallback(void *arg, void *buf, int bufSize) {
	FetchRequest *req = arg;
	req->data = malloc(bufSize);
	if (req->data) memmove(req->data, buf, bufSize);
	req->byteCount = bufSize;
	req->status = DONE;
}

static void fetchErrorCallback(void *arg) {
	FetchRequest *req = arg;
	printf("Fetch error, id = %d\n", req->id);
	req->status = FAILED;
}

// ***** Browser Support Primitives *****

static OBJ primBrowserURL(int nargs, OBJ args[]) {
	// Note: This does not handle UTF-8 strings (i.e. bytes with
	// values > 127). However, Unicode characters above the ASCII
	// range must be encoded as hex values in URL's, so no valid
	// URL should contain bytes outside the ASCII range.

	if (!isInBrowser()) return primFailed("Only works in a browser");

	char s[1000];
	EM_ASM_({
		var result = "";
		if (typeof window !== 'undefined') result = window.location.href;
		var out = $0;
		var outLen = $1;
		var outIndex = 0;
		for (var i = 0; i < result.length; i++) {
			var ch = result.charCodeAt(i);
			if ((ch < 128) && (outIndex < outLen)) {
				Module.HEAPU8[out + outIndex++] = ch;
			}
		}
		Module.HEAPU8[out + outIndex] = 0; // null terminate
	}, &s, sizeof(s));
	return newString(s);
}

static OBJ primStartFetch(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ url = args[0];
	if (NOT_CLASS(url, StringClass)) return primFailed("First argument must be a string");

	if (!isInBrowser()) return primFailed("Only works in a browser");

	// find an unused request
	int i;
	for (i = 0; i < MAX_REQUESTS; i++) {
		if (!requests[i].id) {
			requests[i].id = nextFetchID++;
			requests[i].status = IN_PROGRESS;
			requests[i].data = NULL;
			requests[i].byteCount = 0;
			break;
		}
	}
	if (i >= MAX_REQUESTS) return nilObj; // no free request slots (unlikely)

	emscripten_async_wget_data(obj2str(url), &requests[i], fetchDoneCallback, fetchErrorCallback);
	return int2obj(requests[i].id);
}

static OBJ primFetchResult(int nargs, OBJ args[]) {
	// Returns a BinaryData object on success, false on failure, and nil when fetch is still in progress.
	if (nargs < 1) return notEnoughArgsFailure();
	if (!isInt(args[0])) return primFailed("Expected integer");
	int id = obj2int(args[0]);

	// find the fetch request with the given id
	int i;
	for (i = 0; i < MAX_REQUESTS; i++) {
		if (requests[i].id == id) break;
	}
	if (i >= MAX_REQUESTS) return falseObj; // could not find request with id; report as failure
	if (IN_PROGRESS == requests[i].status) return nilObj; // in progress

	OBJ result = falseObj;

	if (DONE == requests[i].status && requests[i].data) {
		// allocate result object
		int byteCount = requests[i].byteCount;
		result = newBinaryData(byteCount);
		if (result) {
			memmove(&FIELD(result, 0), requests[i].data, byteCount);
		} else {
			printf("Insufficient memory for requested file (%ul bytes needed); skipping.\n", byteCount);
		}
	}

	// mark request as free and free the request data, if any
	requests[i].id = 0;
	if (requests[i].data) free(requests[i].data);
	requests[i].data = NULL;
	requests[i].byteCount = 0;

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
			Module.HEAPU32[dst++] = (file.name.charCodeAt(i) << 1) | 1;
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

// ***** Mobile Browser and Chromebook Detection *****

static OBJ primBrowserIsMobile(int nargs, OBJ args[]) {
	int isMobile = EM_ASM_INT({
		return (/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent));
	}, NULL);
	return isMobile ? trueObj : falseObj;
}

static OBJ primBrowserIsChromebook(int nargs, OBJ args[]) {
	int isChromebook = EM_ASM_INT({
		return (/X11; CrOS/i.test(navigator.userAgent));
	}, NULL);
	return isChromebook ? trueObj : falseObj;
}

// ***** Chromebook File Operations *****

static OBJ primChromeUploadFile(int nargs, OBJ args[]) {
	EM_ASM({ GP_UploadFiles(); }, 0);
	return nilObj;
}

static OBJ primChromeWriteFile(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return primFailed("Argument must be a string");
	char *suggestedFileName = "";
	if ((nargs > 1) && (IS_CLASS(args[1], StringClass))) suggestedFileName = obj2str(args[1]);

	EM_ASM_({
		GP_writeFile(UTF8ToString($0), UTF8ToString($1));
	}, obj2str(args[0]), suggestedFileName);
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
		if ((cnvID >= 0) || (cnvID < GP.canvasCache.length)) {
			GP.canvasCache[cnvID] = null;
		}
	}, (int) a[0]);

	a[0] = NULL;
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

// ***** Canava-based graphics primitives *****

static OBJ primOpenWindow(int nargs, OBJ args[]) {
	int w = intOrFloatArg(0, 500, nargs, args);
	int h = intOrFloatArg(1, 500, nargs, args);

	EM_ASM_({
		var w = $0;
		var h = $1;

		var winCnv = document.getElementById('canvas');
		if (winCnv) {
			winCnv.width = w;
			winCnv.height = h;
			winCnv.style.setProperty("width", w + "px");
			winCnv.style.setProperty("height", h + "px");
		}
	}, w, h);

	return nilObj;
}

static OBJ primCloseWindow(int nargs, OBJ args[]) { return nilObj; } // noop

static OBJ primWindowSize(int nargs, OBJ args[]) {
	int w = EM_ASM_INT({
		var winCnv = document.getElementById('canvas');
		return winCnv ? winCnv.getAttribute('width') : 0;
	}, NULL);
	int h = EM_ASM_INT({
		var winCnv = document.getElementById('canvas');
		return winCnv ? winCnv.getAttribute('height') : 0;
	}, NULL);

	OBJ result = newArray(4);
	FIELD(result, 0) = int2obj(w);
	FIELD(result, 1) = int2obj(h);
	FIELD(result, 2) = int2obj(w);
	FIELD(result, 3) = int2obj(h);
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
			var w = winCnv.getAttribute('width');
			var h = winCnv.getAttribute('height');
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
// 	int flip = intArg(8, 0, nargs, args); // 0 - none, 1 - horizontal, 2 - vertical
	int blendFlag = intArg(9, 1, nargs, args); // 0 - overwrite destination, 1 - alpha blend (default)

	OBJ clipRectObj = (nargs > 10) ? args[10] : nilObj;

	int dstID = 0;
	if (dst != nilObj) {  // if dst not nil, draw onto it; otherwise draw onto the display
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
	}, dstID, srcID, x, y, globalAlpha / 255.0, xScale, yScale, rotation, blendFlag,
		clipLeft, clipTop, clipWidth, clipHeight);

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

static OBJ primWarpBitmap(int nargs, OBJ args[]) { return nilObj; } // Not yet implemented

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

static PrimEntry browserPrimList[] = {
	{"-----", NULL, "Browser Support"},
	{"browserURL",				primBrowserURL,			"Return the full URL of the current browser page."},
	{"startFetch",				primStartFetch,			"Start downloading the contents of a URL. Return an id that can be used to get the result. Argument: urlString"},
	{"fetchResult",				primFetchResult,		"Return the result of the fetch operation with the given id: a BinaryData object (success), false (failure), or nil if in progress. Argument: id"},
	{"browserSize",				primBrowserSize,		"Return the inner width and height of the browser window."},
	{"browserScreenSize",		primBrowserScreenSize,	"Return the width and height of the entire screen containing the browser."},
	{"setFillBrowser",			primSetFillBrowser, 	"Set 'fill browser' mode. If true, the GP canvas is resized to fill the entire browser window."},
	{"browserFileImport",		primBrowserFileImport,	"Show a file input button that the user can click to import a file."},
	{"browserGetDroppedFile",	primBrowserGetDroppedFile,	"Get the next dropped file record array (fileName, binaryData), or nil if there isn't one."},
	{"browserGetDroppedText",	primBrowserGetDroppedText,	"Get last dropped or pasted text, or nil if there isn't any."},
	{"browserGetMessage",		primBrowserGetMessage,		"Get the next message from the browser, or nil if there isn't any."},
	{"browserPostMessage",		primBrowserPostMessage,		"Post a message to the browser using the 'postMessage' function."},
	{"browserIsMobile",			primBrowserIsMobile,		"Return true if running in a mobile browser."},
	{"browserIsChromebook",		primBrowserIsChromebook,	"Return true if running on a Chromebook."},
	{"chromeReadFile",			primChromeUploadFile,		"Select and upload a file on Chromebook."},
	{"chromeWriteFile",			primChromeWriteFile,		"Write a file on a Chromebook. Args: data [suggestedFileName]"},
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
};

PrimEntry* browserPrimitives(int *primCount) {
	*primCount = sizeof(browserPrimList) / sizeof(PrimEntry);
	return browserPrimList;
}

PrimEntry* graphicsPrimitives(int *primCount) {
	*primCount = sizeof(graphicsPrimList) / sizeof(PrimEntry);
	return graphicsPrimList;
}
