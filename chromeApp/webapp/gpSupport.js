// Handlers are ignored in gp.html when running as a Chrome App so must be added here:

function addGPHandlers() {
	var kbdButton = document.getElementById('KeyboardButton');
	var backspaceButton = document.getElementById('BackspaceButton');
	var fullscreenButton = document.getElementById('FullscreenButton');
	var enableMicrophoneButton = document.getElementById('EnableMicrophoneButton');
	var uploadButton = document.getElementById('UploadButton');
	var seeInsideButton = document.getElementById('SeeInsideButton');
	var presentButton = document.getElementById('PresentButton');
	var goButton = document.getElementById('GoButton');
	var stopButton = document.getElementById('StopButton');
	var fileUploader = document.getElementById('FileUploader');
	var canvas = document.getElementById('canvas');

	kbdButton.onclick = function(evt) { GP.clipboard.focus(); };
	backspaceButton.onclick = function(evt) { GP_backspace(); };
	fullscreenButton.onclick = function(evt) { GP_toggleFullscreen(); };
	uploadButton.onclick = function(evt) { GP_UploadFiles(); };
	enableMicrophoneButton.onclick = function(evt) { GP_startAudioInput(1024, 22050); };
	seeInsideButton.onclick = function(evt) { queueGPMessage('seeInside'); };
	presentButton.onclick = function(evt) { queueGPMessage('present'); };
	goButton.onclick = function(evt) { queueGPMessage('go'); };
	stopButton.onclick = function(evt) { queueGPMessage('stop'); };
	fileUploader.onchange = function(evt) { uploadFiles(fileUploader.files); };
	canvas.oncontextmenu = function(evt) { evt.preventDefault(); }
}
addGPHandlers();

// GP variables

var GP = {
	events: [],
	isRetina: false,

	shadowColor: null,
	shadowOffset: 0,
	shadowBlur: 0,

	clipboard: null,
	clipboardBytes: [],
	droppedTextBytes: [],
	droppedFiles: [],
	lastSavedFileName: null,
	messages: [],

	audioOutBuffer: null,
	audioOutIsStereo: false,
	audioOutReady: false,

	audioInBuffer: null,
	audioInDownsampling: false,
	audioInReady: false,
	audioInSource: null,
	audioInCapture: null,
};

// Add the following to the meta tags in the header to suppress scaling of the GP canvas
// <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />

// Clipboard Support
//	Chrome: works on HTTPS pages
//	Firefox: does not support clipboard.readText except in extensions
//	Safari: navigator.clipboard exists since 13.1 but is blocked for security reasons

GP.clipboard = document.createElement('textarea');
GP.clipboard.style.position = 'absolute';
GP.clipboard.style.right = '101%'; // placed just out of view
GP.clipboard.style.top = '0px';
document.body.appendChild(GP.clipboard);

function isChromeOS() {
	return (
		(typeof chrome !== 'undefined') &&
		(typeof chrome.app !== 'undefined') &&
		(typeof chrome.app.runtime !== 'undefined') &&
		(typeof chrome.app.window !== 'undefined'));
}

function setGPClipboard(s) {
	// Called by GP's setClipboard primitive

	GP.clipboardBytes = toUTF8Array(s);
	GP.clipboard.value = s;

	if ((typeof navigator.clipboard !== 'undefined') && (navigator.clipboard.writeText)) {
		navigator.clipboard.writeText(s).catch(() => {});
	} else {
		GP.clipboard.focus();
		GP.clipboard.select();
		try {
			document.execCommand('copy');
		} catch (err) {
			console.error('setGPClipboard failed', err);
		}
	}
}

async function readGPClipboard(s) {
	if ((typeof navigator.clipboard !== 'undefined') && (navigator.clipboard.readText)) {
		var s = await navigator.clipboard.readText().catch(() => {});
		if (s) GP.clipboard.value = s;
	} else {
		GP.clipboard.focus();
		GP.clipboard.select();
		try {
			document.execCommand('paste');
		} catch (err) {
			console.error('readGPClipboard failed', err);
		}
	}
	GP.clipboardBytes = toUTF8Array(GP.clipboard.value);
	return GP.clipboardBytes.length;
}

function toUTF8Array(str) {
	// Convert a Javascript string into an array of UTF8 bytes that can be read by GP.
	var utf8 = [];
	for (var i = 0; i < str.length; i++) {
		var charcode = str.charCodeAt(i);
		if (charcode < 0x80) utf8.push(charcode);
		else if (charcode < 0x800) {
			utf8.push(
				0xc0 | (charcode >> 6),
				0x80 | (charcode & 0x3f));
		}
		else if (charcode < 0x10000) {
			utf8.push(
				0xe0 | (charcode >> 12),
				0x80 | ((charcode >> 6) & 0x3f),
				0x80 | (charcode & 0x3f));
		} else if (charcode <= 0x10FFFF) {
			utf8.push(
				0xf0 | (charcode >> 18),
				0x80 | ((charcode >> 12) & 0x3f),
				0x80 | ((charcode >> 6) & 0x3f),
				0x80 | (charcode & 0x3f));
		}
	}
	return utf8;
}

// events

function initGPEventHandlers() {
	var MOUSE_DOWN = 1;
	var MOUSE_UP = 2;
	var MOUSE_MOVE = 3;
	var MOUSE_WHEEL = 4;
	var KEY_DOWN = 5;
	var KEY_UP = 6;
	var TEXTINPUT = 7;
	var TOUCH_DOWN = 8;
	var TOUCH_UP = 9;
	var TOUCH_MOVE = 10;
	var WINDOW_SHOWN = 11;

	function localPoint(x, y, yOffset) {
		var r = canvas.getBoundingClientRect();
		x = (x - r.left) | 0;
		y = (y - r.top) | 0;
		if (x < 0) x = 0;
		if (y < 0) y = 0;
		if (GP.isRetina) {
			x = 2 * x;
			y = 2 * y;
			yOffset = 2 * yOffset;
		}
		return [x, y - yOffset];
	}
	function modifierBits(evt) {
		var modifiers = ( // SDL modifier flags (for left-side versions of those keys)
		(evt.shiftKey ? 1 : 0) |
		(evt.ctrlKey ? 2 : 0) |
		(evt.altKey ? 4 : 0) |
		(evt.metaKey ? 8 : 0));
		return modifiers;
	}
	function keyEvent(evtType, evt) {
		var keyCode = evt.keyCode;
		var charCode = 0;
		if (evt.keyIdentifier) { // Safari
			if (evt.keyIdentifier.startsWith('U+')) {
				charCode = parseInt(evt.keyIdentifier.substring(2), 16);
			}
		} else if (evt.key && evt.key.charCodeAt && (evt.key.length == 1)) { // Chrome, Firefox
			if (evt.key.length == 1) {
				charCode = evt.key.charCodeAt(0);
			}
		}
		if (0 == charCode) {
			if (8 == evt.keyCode) charCode = 8; // backspace key
			if (9 == evt.keyCode) charCode = 9; // tab
			if (13 == evt.keyCode) charCode = 13; // enter
			if (27 == evt.keyCode) charCode = 27; // escape
			if (46 == evt.keyCode) charCode = 8; // map delete key to backspace
		}
		if ((65 <= charCode) && (charCode <= 90) && !evt.shiftKey) charCode += 32; // lowercase

		// make Firefox keycodes the same as Chrome/Safari:
		if ((59 == keyCode) && (59 == charCode)) keyCode = 186;
		if ((61 == keyCode) && (61 == charCode)) keyCode = 187;
		if ((173 == keyCode) && (45 == charCode)) keyCode = 189;
		if (224 == keyCode) keyCode = 91;

		var modifiers = ( // SDL modifier flags (for left-side versions of those keys)
			(evt.shiftKey ? 1 : 0) |
			(evt.ctrlKey ? 2 : 0) |
			(evt.altKey ? 4 : 0) |
			(evt.metaKey ? 8 : 0));

		return [evtType, keyCode, charCode, modifiers];
	}

	var canvas = document.getElementById('canvas');

	canvas.onmousedown = function(evt) {
		evt.preventDefault();
		var p = localPoint(evt.clientX, evt.clientY, 0);
		GP.events.push([MOUSE_DOWN, p[0], p[1], evt.button, modifierBits(evt)]);
	}
	canvas.onmouseup = function(evt) {
		var p = localPoint(evt.clientX, evt.clientY, 0);
		GP.events.push([MOUSE_UP, p[0], p[1], evt.button, modifierBits(evt)]);
	}
	canvas.onmousemove = function(evt) {
		var p = localPoint(evt.clientX, evt.clientY, 0);
		GP.events.push([MOUSE_MOVE, p[0], p[1]]);
	}
	document.onkeydown = function(evt) {
		var key = evt.which;
		if ((13 == key) && (/Android/i.test(navigator.userAgent))) {
			// On Android, generate text input events for entire string when the enter key is pressed
			var s = GP.clipboard.value;
			for (var i = 0; i < s.length; i++) GP.events.push([TEXTINPUT, s.charCodeAt(i)]);
			if (s.length == 0) GP.events.push([TEXTINPUT, 13]); // insert newline if no other characters
			GP.clipboard.value = '';
			evt.preventDefault();
			return;
		}
		var eventRecord = keyEvent(KEY_DOWN, evt);
		GP.events.push(eventRecord);
		// suppress browser's default behavior for various keys
		if ((9 == key) || (32 == key)) { // tab or space
			GP.events.push([TEXTINPUT, key]); // suppress, but do generate a textinput event
			evt.preventDefault();
		}
		if (8 == key) evt.preventDefault(); // backspace key
		if ((33 <= evt.which) && (evt.which <= 36)) evt.preventDefault(); // home, end, page up/down keys
		if ((37 <= evt.which) && (evt.which <= 40)) evt.preventDefault(); // arrow keys
		if (46 == key) evt.preventDefault(); // delete key
		if ((112 <= evt.which) && (evt.which <= 123)) evt.preventDefault(); // function keys
		if (evt.ctrlKey || evt.metaKey) {
			// special case for ctrl/cmd-C, ctrl/cmd-V, and ctrl/cmd-X  (copy, paste, cut)
			if ((67 == evt.keyCode) || (86 == evt.keyCode) || (88 == evt.keyCode)) {
				// push key down/up events for GP
				GP.events.push(keyEvent(KEY_DOWN, evt));
				GP.events.push(keyEvent(KEY_UP, evt));

				// focus and select clipboard element
				GP.clipboard.focus();
				GP.clipboard.select();
			}
		}
	}
	document.onkeyup = function(evt) {
		GP.events.push(keyEvent(KEY_UP, evt));
	}
	document.onkeypress = function(evt) {
		var charCode = evt.charCode;
		if (13 == charCode) return; // don't report a text input event for cr/enter
		if (evt.char && (evt.char.length == 1)) charCode = evt.char.codePointAt(0);
		GP.events.push([TEXTINPUT, charCode]);
	}

	// IME composition events
	document.addEventListener('compositionstart', function(evt) {
		GP.compositionText = '';
	});
	document.addEventListener('compositionupdate', function(evt) {
		GP.compositionText = evt.data;
	});
	document.addEventListener('compositionend', function(evt) {
		for (let ch of GP.compositionText) {
			GP.events.push([TEXTINPUT, ch.codePointAt(0)]);
		}
		GP.compositionText = '';
	});

	canvas.onwheel = function(evt) {
		if (evt.shiftKey || evt.ctrlKey) { return; } // default behavior (browser zoom)
		var dx = evt.wheelDeltaX;
		var dy = evt.wheelDeltaY;
		GP.events.push([MOUSE_WHEEL, dx, dy]);
		evt.preventDefault();
	}
	canvas.ontouchstart = function(evt) {
		var touch = evt.touches[0];
		if (touch) {
			// var button = (evt.touches.length == 2) ? 3 : 0; // did not work
			// Attempt to use two-finger touch for right button failed; always use left button.
			var button = 0;
			var p = localPoint(touch.clientX, touch.clientY, 10);
			GP.events.push([TOUCH_DOWN, p[0], p[1], button]);
		}
		evt.preventDefault();
	}
	canvas.ontouchmove = function(evt) {
		var touch = evt.touches[0];
		if (touch) {
			var p = localPoint(touch.clientX, touch.clientY, 10);
			GP.events.push([TOUCH_MOVE, p[0], p[1], 0]);
		}
		evt.preventDefault();
	}
	canvas.ontouchend = function(evt) {
		var touch = evt.changedTouches[0];
		if (touch) {
			var p = localPoint(touch.clientX, touch.clientY, 10);
			GP.events.push([TOUCH_UP, p[0], p[1], 0]);
		}
		evt.preventDefault();
	}
	canvas.ontouchcancel = function(evt) {
		GP.events.push([TOUCH_UP, 200, 200, 0]); // push a dummy touch_up event
	}
	window.onfocus = function(evt) {
		GP.events.push([WINDOW_SHOWN]);
	}
}
initGPEventHandlers();

function GP_backspace() {
	// Simulate the backspace/delete key on Android.
	var KEY_DOWN = 5;
	var KEY_UP = 6;
	GP.events.push([KEY_DOWN, 8, 8, 0]);
	GP.events.push([KEY_UP, 8, 8, 0]);
}

// drag-n-drop events

window.addEventListener(
	'dragover',
	function(evt) {
		evt.preventDefault();
	},
	false
);

window.addEventListener(
	'drop',
	function(evt) {
		evt.preventDefault();
		var files = evt.target.files || evt.dataTransfer.files;
		if (files && files.length) {
			uploadFiles(files);
		} else if (evt.dataTransfer) {
			// Dropping a text clipping or URL can be used as workaround for paste
			var s = evt.dataTransfer.getData('text/plain');
			if (s) GP.droppedTextBytes = toUTF8Array(s);
			var url = evt.dataTransfer.getData('URL');
			if (url) GP.droppedTextBytes = toUTF8Array(url + '\n');
		}
	},
	false
);

// message handling

function queueGPMessage(s) {
	// Queue a message that can be read by GP with the 'browserGetMessage' primitive
	// This mechanism is currently used by HTML buttons for 'go', 'stop', and 'see inside'.

	GP.messages.push(toUTF8Array(s));
}

function handleMessage(evt) {
	// Handle a message sent by the JavaScript postMessage() function.
	// This is used to control button visibility, to queue a message to GP
	// or to communicate with Boardie.

	var msg = evt.data;
	if (GP.boardie.isOpen && msg instanceof Uint8Array) {
		if (msg[0]) {
			// Boardie sent us bytes. Let's add them to the serial buffer.
			GP_serialInputBuffers.push(msg);
		}
	} else if (msg.constructor === Array) {
		switch (msg[0]) {
			case 'showButton':
				var btn = msg[1];
				if (btn) btn.style.display = 'inline';
				return;
			case 'hideButton':
				var btn = document.getElementById(msg[1]);
				if (btn) btn.style.display = 'none';
				return;
			case 'boardieKeyDown':
				GP.boardie.press(msg[1]);
				return;
			case 'boardieKeyUp':
				GP.boardie.unpress(msg[1]);
				return;
			case 'boardieGetFile':
				GP.boardie.files[msg[1]] = msg[2];
				return;
			case 'boardieDeleteFile':
				delete(GP.boardie.files[msg[1]]);
				return;
			case 'boardieSoundStart':
				boardie.element.querySelector('.audio').classList.add('--is-active');
				return;
			case 'boardieSoundStop':
				boardie.element.querySelector('.audio').classList.remove('--is-active');
				return;
			default:
				console.log('unrecognized message:', msg);
				return;
		}
	} else {
		queueGPMessage(msg);
	}
}

window.addEventListener("message", handleMessage, false);

// file upload support

function GP_UploadFiles(evt) {
	// Upload using "Upload" button
	var inp = document.getElementById('FileUploader'); // use the hidden file input element
	if (inp) inp.click();
}

function uploadFiles(files) {
	// Upload files. Initiated from either FileUploader click or drag-and-drop.

	function recordFile(f) {
		reader = new FileReader();
		reader.onloadend = function() {
			if (reader.result) {
				GP.droppedFiles.push({ name: toUTF8Array(f.name), contents: reader.result });
			}
			if (todo.length) recordFile(todo.shift());
		};
		reader.readAsArrayBuffer(f);
	}
	var todo = [];
	if (files && files.length) {
		for (var i = 0; i < files.length; i++) todo.push(files[i]);
		recordFile(todo.shift());
	}
}

function adjustButtonVisibility() {
	// Show the appropriate buttons in a mobile or non-mobile browser.
	var kbdButton = document.getElementById('KeyboardButton');
	var bsButton = document.getElementById('BackspaceButton');
	var fsButton = document.getElementById('FullscreenButton');
	var userAgent = navigator.userAgent;
	var isKindle = /Kindle|Silk|KFAPW|KFARWI|KFASWI|KFFOWI|KFJW|KFMEWI|KFOT|KFS‌​AW|KFSOWI|KFTBW|KFTH‌​W|KFTT|WFFOWI/i.test(userAgent);
	var isOtherMobile = /Android|webOS|iPhone|iPad|iPod|CriOS|BlackBerry|IEMobile|Opera Mini/i.test(userAgent);
	if (isKindle || isOtherMobile) {
		kbdButton.style.display = 'inline';
	} else {
		kbdButton.style.display = 'none';
	}
	if (isKindle || /Android/i.test(navigator.userAgent)) {
		bsButton.style.display = 'inline';
	} else {
		bsButton.style.display = 'none';
	}
	if (/iPhone|iPad|iPod|CriOS/i.test(userAgent)) {
		fsButton.style.display = 'none';
	} else {
		fsButton.style.display = 'inline';
	}

	if (window.parent === window) {
		document.getElementById('EnableMicrophoneButton').style.display = 'none';
	}

	// adjust buttons when opened with 'go.html' URL
	if ((typeof window !== 'undefined') && (window.location.href.includes('go.html'))) {
		document.getElementById('SeeInsideButton').style.display = 'inline';
		document.getElementById('PresentButton').style.display = 'none';
	} else if ((typeof window !== 'undefined') && (window.location.href.includes('microblocks'))) {
		document.getElementById('controls').style.display = 'none';
		if (isKindle || isOtherMobile) {
			// show the keyboard button on mobile devices, but hide others
			document.getElementById('controls').style.display = 'inline';
			document.getElementById('KeyboardButton').style.display = 'inline';
			document.getElementById('BackspaceButton').style.display = 'none';
			document.getElementById('FullscreenButton').style.display = 'none';
			document.getElementById('UploadButton').style.display = 'none';
			document.getElementById('EnableMicrophoneButton').style.display = 'none';
			document.getElementById('SeeInsideButton').style.display = 'none';
			document.getElementById('PresentButton').style.display = 'none';
			document.getElementById('GoButton').style.display = 'none';
			document.getElementById('StopButton').style.display = 'none';
		}
	} else {
		document.getElementById('SeeInsideButton').style.display = 'none';
		document.getElementById('PresentButton').style.display = 'inline';
	}
}
adjustButtonVisibility();

// Canvas shadow effects

function setContextShadow(ctx) {
	if (!GP.shadowColor) return;
	ctx.shadowColor = GP.shadowColor;
	ctx.shadowOffsetX = GP.shadowOffsetX;
	ctx.shadowOffsetY = GP.shadowOffsetY;
	ctx.shadowBlur = GP.shadowBlur;
}

function setShadow(red, green, blue, alpha, offsetX, offsetY, blur) {
	GP.shadowColor = 'rgba(' + red + ', ' + green + ', ' + blue + ', ' + alpha + ')';
	GP.shadowOffsetX = offsetX;
	GP.shadowOffsetY = offsetY;
	GP.shadowBlur = blur;
}

function clearShadow() {
	GP.shadowColor = null;
	GP.shadowOffsetX = 0;
	GP.shadowOffsetY = 0;
	GP.shadowBlur = 0;
}

// audio input and output support

function GP_audioContext() {
	// Note: Cache the audio context because browsers only allow you to create a few of them.
	if (GP.cachedAudioContext) return GP.cachedAudioContext;

	function unsuspendAudioContext () {
		// On iOS, the audio context is suspended until resumed by a touch event.
		if (GP.cachedAudioContext &&  ('suspended' === GP.cachedAudioContext.state)) {
			GP.cachedAudioContext.resume();
		}
	}
	var AudioContextClass = (window.AudioContext || window.webkitAudioContext ||
		window.mozAudioContext || window.msAudioContext || window.oAudioContext);
	if (!AudioContextClass) {
		console.warn('This browser does not support audio');
		return null;
	}
	GP.cachedAudioContext = new AudioContextClass();
	document.body.addEventListener('touchend', unsuspendAudioContext, false);
	return GP.cachedAudioContext;
}

// iOS hack -- create the audio context at startup so a touch event
// can unsuspend the audio context before we actually need it:
// Still needed? Commented out for now... (April, 2020)
//GP_audioContext();

function GP_startAudioInput(inputSampleCount, sampleRate) {
	if (GP.audioInCapture && GP.audioInSource) return; // already open

	function doSoundInput(evt) {
		var buf = evt.inputBuffer.getChannelData(0);
		if (GP.audioInDownsampling) {
			for (i = 0; i < buf.length; i += 2) {
				var n = ((buf[i] + buf[i + 1]) * 16383) | 0; // average two samples and convert to signed int (16383 is 32767 / 2)
				GP.audioInBuffer[i / 2] = n;
			}
		} else {
			for (i = 0; i < buf.length; i++) {
				GP.audioInBuffer[i] = (buf[i] * 32767) | 0; // convert to signed int
			}
		}
		GP.audioInReady = true;
	}
	function openAudioInput(stream) {
		var rawSampleCount = GP.audioInDownsampling ? (2 * inputSampleCount) : inputSampleCount;
		GP.audioInSource = audioContext.createMediaStreamSource(stream);
		GP.audioInCapture = audioContext.createScriptProcessor(rawSampleCount, 1); // will down-sample to 22050
		GP.audioInCapture.onaudioprocess = doSoundInput;
		GP.audioInSource.connect(GP.audioInCapture);
		GP.audioInCapture.connect(audioContext.destination);
	}
	function openAudioInputFailed(e) {
		console.warn('Could not open audio input: ' + e);
	}

	audioContext = GP_audioContext();
	if (!audioContext) return;

	var data = new ArrayBuffer(2 * inputSampleCount); // two-bytes per sample
	GP.audioInBuffer = new Int16Array(data);
	GP.audioInDownsampling = (sampleRate < audioContext.sampleRate);
	GP.audioInReady = false;

	navigator.getUserMedia = navigator.getUserMedia || navigator.webkitGetUserMedia ||
		navigator.mozGetUserMedia || navigator.msGetUserMedia || navigator.oGetUserMedia;
	if (navigator.getUserMedia) {
		navigator.getUserMedia({audio: true}, openAudioInput, openAudioInputFailed);
	} else {
		console.warn('Audio input is not supported by this browser');
	}
}

function GP_stopAudioInput() {
	if (GP.audioInSource) GP.audioInSource.disconnect();
	if (GP.audioInCapture) GP.audioInCapture.disconnect();
	GP.audioInSource = null;
	GP.audioInCapture = null;
	GP.audioInReady = false;
}

function GP_startAudioOutput(frameCount, isStereo) {
	if (GP.callbackID) return; // already open

	audioContext = GP_audioContext();
	if (!audioContext) return;

	function soundProcess() {
		if (!GP.callbackID) return; // audio output closed
		if (audioContext.currentTime <= GP.audioOutFlipTime) {
			GP.callbackID = requestAnimationFrame(soundProcess);
			return;
		}

		// select the buffer to fill and swap buffers
		var buf = GP.audioOutBuffers[GP.audioOutBufferIndex];
		GP.audioOutBufferIndex = (GP.audioOutBufferIndex + 1) % 2;

		if (GP.audioOutReady) {
			if (GP.audioOutIsStereo) { // stereo
				var left = buf.getChannelData(0);
				var right = buf.getChannelData(1);
				for (var i = 0; i < left.length; i++) {
					left[i] = GP.audioOutBuffer[2 * i];
					right[i] = GP.audioOutBuffer[(2 * i) + 1];
				}
			} else { // mono
				var samples = buf.getChannelData(0);
				for (var i = 0; i < samples.length; i++) samples[i] = GP.audioOutBuffer[i];
			}
		} else { // no GP audio data available; fill all channels with silence
			for (var chan = 0; chan < buf.numberOfChannels; chan++) {
				var samples = buf.getChannelData(chan);
				for (var i = 0; i < samples.length; i++) samples[i] = 0;
			}
		}
		GP.audioOutReady = false;

		var startTime = GP.audioOutFlipTime + buf.duration;
		if (audioContext.currentTime > startTime) startTime = audioContext.currentTime;
		var source = audioContext.createBufferSource();
		source.buffer = buf;
		source.start(startTime);
		source.connect(audioContext.destination);
		GP.audioOutFlipTime = startTime; // when this buffer starts playing, GP can fill the other one
		GP.callbackID = requestAnimationFrame(soundProcess);
	}

	var channelCount = isStereo ? 2 : 1;
	var data = new ArrayBuffer(4 * frameCount * channelCount); // four-bytes per sample (Float32's)
	GP.audioOutBuffer = new Float32Array(data);
	GP.audioOutIsStereo = isStereo;
	GP.audioOutReady = false;

	GP.audioOutBuffers = [];
	GP.audioOutBuffers.push(audioContext.createBuffer(channelCount, frameCount, 22050));
	GP.audioOutBuffers.push(audioContext.createBuffer(channelCount, frameCount, 22050));
	GP.audioOutBufferIndex = 0;
	GP.audioOutFlipTime = -1;

	GP.callbackID = requestAnimationFrame(soundProcess);
}

function GP_stopAudioOutput() {
	if (!GP.callbackID) cancelAnimationFrame(GP.callbackID);
	GP.callbackID = null;
}

function GP_toggleFullscreen() {
	var doc = window.document;
	var docEl = doc.documentElement;

	var requestFullScreen = docEl.requestFullscreen || docEl.mozRequestFullScreen || docEl.webkitRequestFullScreen || docEl.msRequestFullscreen;
	var cancelFullScreen = doc.exitFullscreen || doc.mozCancelFullScreen || doc.webkitExitFullscreen || doc.msExitFullscreen;

	if(!doc.fullscreenElement && !doc.mozFullScreenElement && !doc.webkitFullscreenElement && !doc.msFullscreenElement) {
		requestFullScreen.call(docEl);
	} else {
		cancelFullScreen.call(doc);
	}
}

// Boardie Support

// The IDE communicates with Boardie as if it were a serial port (i.e. using serial read/write)
// Boardie receives serial data from the IDE as a queue of Uint8 buffers.
// Boardie sends serial data to the IDE by pushing Uint8 buffers to GP_serialInputBuffers.

GP.boardie = {
	element: null,
	iframe: null,
	isOpen: false,
	position: null,
	reset: function () {
		win = this.iframe.contentWindow;
		win.postMessage(new Uint8Array([ 0xFA, 0x0F, 3 ]), '*'); // system reset w/ Boardie option
		ctx = win.document.querySelector('canvas').getContext('2d');
		ctx.fillStyle = "#000";
		ctx.fillRect(0, 0, 240, 240); // clear screen
		win.postMessage(new Uint8Array([ 0xFA, 0x05, 0 ]), '*'); // start all
	},
	buttonForCode: function (keyCode) {
		switch (parseInt(keyCode)) {
			case 37:
			case 65:
				return 'a';
			case 39:
			case 66:
				return 'b';
			case 84:
				return 'ab';
			default:
				return '';
		}
	},
	files: {},
	press: function (keyCode, andSendToBoard) {
		var button = this.buttonForCode(keyCode),
				element = this.element.querySelector(`[data-button="${button}"]`);
		if (element) { element.classList.add('--is-active'); }
		if (andSendToBoard) {
			this.iframe.contentWindow.postMessage(['keyDown', keyCode], '*');
		}
	},
	unpress: function (keyCode, andSendToBoard) {
		var button = this.buttonForCode(keyCode);
				element = this.element.querySelector(`[data-button="${button}"]`);
		if (element) { element.classList.remove('--is-active'); }
		if (andSendToBoard) {
			this.iframe.contentWindow.postMessage(['keyUp', keyCode], '*');
		}
	}
};

function GP_openBoardie() {
	var req = new XMLHttpRequest();
		boardie = GP.boardie;

	GP_closeSerialPort(); // close serial port if open
	GP.boardie.files = {}; // reset file cache

	req.open('GET', 'boardie/boardie.html?version=2-0-35-1');
	req.onreadystatechange = function () {
		if (req.readyState == 4 && req.status == 200) {
			boardie.element = document.createElement('div');
			boardie.element.innerHTML = req.responseText;
			boardie.element.style.position = 'absolute';
			boardie.element.style.width = '272px';
			boardie.element.style.zIndex = 999;

			var ideCnv = document.getElementById('canvas');
			if (boardie.position &&
				(boardie.position.x <= ideCnv.clientWidth - 45) &&
				(boardie.position.y <= ideCnv.clientHeight - 45)) {
					boardie.element.style.left = boardie.position.x + 'px';
					boardie.element.style.top = boardie.position.y + 'px';
			} else {
				boardie.element.style.top = '70px';
				boardie.element.style.right = '34px';
			}
			boardie.element.style.cursor = 'grab';

			var isStandAlone = window.matchMedia('(display-mode: standalone)').matches;
			boardie.iframe = boardie.element.querySelector('iframe');
			if ((window.location.hostname == 'microblocks.fun') && !isStandAlone) {
				// Run Boardie from a separate domain to ensure it runs as an OOPIF
				boardie.iframe.src = 'https://boardie.microblocks.fun/vm.html';
			} else {
				// Load from source domain when not running from microblocks.fun
				// (e.g. when running as a stand-alone progressive web app).
				// Not the end of the world, but the UI will interfere with
				// time-sensitive threads, such as when making music
				boardie.iframe.src = 'boardie/vm.html?version=2-0-35-1';
			}

			boardie.element.onclick = function (evt) {
				if (!evt.target.closest('[data-button]')) {
					boardie.iframe.focus();
				}
			}

			document.body.append(boardie.element);

			makeDraggable(boardie.element);

			boardie.element.querySelectorAll('[data-button]').forEach(
				button => {
					button.addEventListener('keydown', (evt) => {
						boardie.press(evt.keyCode, true);
						boardie.iframe.focus();
					});
				}
			);

			boardie.iframe.contentWindow.addEventListener('click', (event) => {
				boardie.element.classList.add('--is-active');
			});

			boardie.isOpen = true;
		}
	};

	req.send();
};

function makeDraggable (element) {
	// taken from w3schools (https://www.w3schools.com/howto/howto_js_draggable.asp)
	var lastX = 0, lastY = 0;

	element.onpointerdown = dragMouseDown;

	function dragMouseDown(e) {
		e = e || window.event;
		if (!e.target.closest('[data-undraggable]')) {
			element.style.cursor = 'grabbing';
			e.preventDefault();
			// get the mouse cursor position at startup:
			lastX = e.clientX;
			lastY = e.clientY;
			document.onpointerup = endElementDrag;
			// call a function whenever the cursor moves:
			document.onpointermove = elementDrag;
		}
	};

	function elementDrag(e) {
		e = e || window.event;
		e.preventDefault();

		// compute max position
		var maxX = document.getElementById('canvas').clientWidth - element.clientWidth;
		var maxY = document.getElementById('canvas').clientHeight - element.clientHeight;

		// calculate the new cursor position:
		var newX = Math.round(element.offsetLeft + (e.clientX - lastX));
		var newY = Math.round(element.offsetTop + (e.clientY - lastY));

		// constrain top left corner to be at least partially on screen
		newX = (newX < 0) ? 0 : ((newX < maxX) ? newX : maxX);
		newY = (newY < 0) ? 0 : ((newY < maxY) ? newY : maxY);
		lastX = e.clientX;
		lastY = e.clientY;
		// set the element's new position:
		element.style.left = newX + "px";
		element.style.top = newY + "px";
		if (!element.classList.contains('--is-dragged')) {
			element.classList.add('--is-dragged');
		}
	};

	function endElementDrag() {
		// stop moving when mouse button is released:
		document.onpointerup = null;
		document.onpointermove = null;
		var r = element.getBoundingClientRect();
		GP.boardie.position = { x: r.x, y: r.y }; // record final position
		element.classList.remove('--is-dragged');
		element.style.cursor = 'grab';
	};
};

function focusDetection (elementSelector) {
	document.addEventListener('click', (event) => {
		var element = document.querySelector(elementSelector);
		if (element) {
			if (event.target.closest('.boardie')) {
				if (!element.classList.contains('--is-active')) {
					element.classList.add('--is-active');
				}
			} else {
				element.classList.remove('--is-active');
			}
		}
	});
};
focusDetection('.boardie');

function GP_closeBoardie() {
	if (GP.boardie.element) {
		document.body.removeChild(GP.boardie.element);
		GP.boardie.element = null;
		GP.boardie.iframe = null;
		GP.boardie.isOpen = false;
	}
}

// Serial Ports (supported in Chrome OS and Chromium-based browsers only)
// Only one serial port can be open at a time.

function hasChromeSerial() {
	return ((typeof chrome != 'undefined') && (typeof chrome.serial != 'undefined'))
}

function hasWebSerial() {
	return (typeof navigator.serial != 'undefined');
}

function hasWebBluetooth() {
	return (typeof navigator.bluetooth != 'undefined');
}

function webBluetoothConnected() {
	return hasWebBluetooth() && bleSerial.isConnected();
}

// WebSerial support for Chrome browser (navigator.serial API)

GP_webSerialPort = null;
GP_webSerialReader = null;

function webSerialIsConnected() {
	return !(!GP_webSerialPort || !GP_webSerialReader);
}

async function webSerialConnect() {
	// Prompt user to choose a serial port and open the one selected.

	var vendorIDs = [
		{ usbVendorId: 0x0403},		// FTDI
		{ usbVendorId: 0x0d28},		// micro:bit, Calliope
		{ usbVendorId: 0x10c4},		// Silicon Laboratories, Inc. (CP210x)
		{ usbVendorId: 0x1a86},		// CH340
		{ usbVendorId: 0x239a},		// AdaFruit
		{ usbVendorId: 0x2a03},		// Arduino
		{ usbVendorId: 0x2341},		// Arduino MKR Zero
		{ usbVendorId: 0x03eb},		// Atmel Corporation
		{ usbVendorId: 0x1366},		// SEGGER Calliope mini
		{ usbVendorId: 0x16c0},		// Teensy
		{ usbVendorId: 0x2e8a},		// Raspberry Pi Pico RP2040
		{ usbVendorId: 0x303a},		// Espressif USB JTAG/serial debug unit
		{ usbVendorId: 0x28e9},  	// GD32 USB CDC ACM
	];
	webSerialDisconnect();
	GP_webSerialPort = await navigator.serial.requestPort({filters: vendorIDs}).catch((e) => { console.log(e); });
	if (!GP_webSerialPort) return; // no serial port selected
	await GP_webSerialPort.open({ baudRate: 115200 });
	GP_webSerialReader = await GP_webSerialPort.readable.getReader();
	webSerialReadLoop();
}

async function webSerialDisconnect() {
	if (GP_webSerialReader) await GP_webSerialReader.cancel().catch(() => {});
	if (GP_webSerialPort) await GP_webSerialPort.close().catch(() => {});
	GP_webSerialReader = null;
	GP_webSerialPort = null;
}

async function webSerialReadLoop() {
	try {
		while (true) {
			var { value, done } = await GP_webSerialReader.read();
			if (value) {
				GP_serialInputBuffers.push(value);
			}
			if (done) { // happens when GP_webSerialReader.cancel() is called by disconnect
				GP_webSerialReader.releaseLock();
				return;
			}
		}
	} catch (e) { // happens when board is unplugged
		console.log(e);
		await GP_webSerialPort.close().catch(() => {});
		GP_webSerialPort = null;
		GP_webSerialReader = null;
		console.log('Connection closed.');
	}
}

function webSerialWrite(data) {
	if (!GP_webSerialPort || !GP_webSerialPort.writable) return 0;  // port not open
	const w = GP_webSerialPort.writable.getWriter();
	w.write(data.buffer);
	w.releaseLock();
	return data.buffer.byteLength;
}

// Variables used by Chromebook App Serial (chrome.serial API)

GP_serialPortNames = [];
GP_serialPortID = -1;
GP_serialInputBuffers = [];  // a list of Uint8 arrays
GP_serialPortListenersAdded = false;

// Serial support for both WebSerial and Chromebook App

function GP_getSerialPorts() {
	// Request an update to the serial port list, GP_serialPortNames. Since this call
	// is asynchronous, the result is not available in GP_serialPortNames immediately.
	// The caller should call this, wait a bit, then read GP_serialPortNames.

	function listPorts(ports) {
		GP_serialPortNames = [];
		for (var i = 0; i < ports.length; i++) {
			if (!ports[i].path.startsWith('/dev/ttyMSM')) {
				GP_serialPortNames.push(toUTF8Array(ports[i].path));
			}
		}
	}
	if (hasChromeSerial()) chrome.serial.getDevices(listPorts);
}

function GP_openSerialPort(id, path, baud) {
	function serialPortError(info) {
		console.log('Serial port error: ' + info.error);
		GP_closeSerialPort();
	}
	function serialPortDataReceived(info) {
		GP_serialInputBuffers.push(new Uint8Array(info.data));
	}
	function portOpened(connectionInfo) {
		if (!connectionInfo || chrome.runtime.lastError) {
			var reason = '';
			if (chrome.runtime.lastError) reason = chrome.runtime.lastError.message
			console.log('Port open failed ' + reason);
			GP_serialPortID = -1;
			return; // failed to open port
		}
		GP_serialPortID = connectionInfo.connectionId;
		GP_serialInputBuffers = [];
		if (!GP_serialPortListenersAdded) {
			// Listeners only need to be added once.
			chrome.serial.onReceiveError.addListener(serialPortError);
			chrome.serial.onReceive.addListener(serialPortDataReceived);
			GP_serialPortListenersAdded = true;
		}
	}
	if (GP.boardie.isOpen) { return 1; }
	if (hasWebBluetooth() && (path == 'webBLE')) {
		bleSerial.connect();
	} else if (hasWebSerial()) {
		webSerialConnect();
	} else if (hasChromeSerial()) {
		if (GP_serialPortID >= 0) return 1; // already open (not an error)
		chrome.serial.connect(path, {bitrate: baud}, portOpened)
	}
	return 1; // connect is asynchronous, but assume it will succeed
}

function GP_isOpenSerialPort() {
	if (GP.boardie.isOpen) { return true; }
	if (webBluetoothConnected()) { return true; }
	if (hasWebSerial()) return webSerialIsConnected();
	if (hasChromeSerial()) return (GP_serialPortID >= 0);
	return false;
}

function GP_closeSerialPort() {
	if (GP.boardie.isOpen) {
		GP_closeBoardie();
	} else if (webBluetoothConnected()) {
		bleSerial.disconnect();
	} else if (hasWebSerial()) {
		webSerialDisconnect();
	} else if (GP_serialPortID > 0) {
		function portClosed(ignored) { }
		chrome.serial.disconnect(GP_serialPortID, portClosed);
	}
	GP_serialPortID = -1;
	GP_serialInputBuffers = [];
}

function GP_readSerialPort(maxBytes) {
	if (GP_serialInputBuffers.length == 0) {
		return new Uint8Array(new ArrayBuffer(0)); // no data available
	}
	var count = 0;
	for (var i = 0; i < GP_serialInputBuffers.length; i++) {
		count += GP_serialInputBuffers[i].byteLength;
	}
	var result = new Uint8Array(new ArrayBuffer(count));
	var dst = 0;
	for (var i = 0; i < GP_serialInputBuffers.length; i++) {
		var buf = GP_serialInputBuffers[i];
		result.set(GP_serialInputBuffers[i], dst);
		dst += GP_serialInputBuffers[i].byteLength;
	}
	if (result.byteLength <= maxBytes) {
		GP_serialInputBuffers = [];
	} else {
		GP_serialInputBuffers = [result.slice(maxBytes)];
		result = result.slice(0, maxBytes);
	}
	return result;
}

function GP_writeSerialPort(data) {
	if (GP.boardie.isOpen) {
		GP.boardie.iframe.contentWindow.postMessage(data, '*');
		return data.buffer.byteLength;
	} else if (webBluetoothConnected()) {
		return bleSerial.write_data(data);
	} else if (hasWebSerial()) {
		return webSerialWrite(data);
	} else if (hasChromeSerial()) {
		function dataSent(ignored) { }
		if (GP_serialPortID < 0) return -1; // port not open
		chrome.serial.send(GP_serialPortID, data.buffer, dataSent);
		return data.buffer.byteLength;
	}
	return 0;
}

async function GP_setSerialPortDTR(flag) {
	if (GP.boardie_IsOpen) {
		return; // do nothing
	} else if (hasWebSerial()) {
		if (!GP_webSerialPort) return; // port not open
		await GP_webSerialPort.setSignals({ dtr: flag, dataTerminalReady: flag }).catch(() => {});
	} else if (hasChromeSerial()) {
		function ignore(result) {}
		flag = (flag) ? true : false;
		chrome.serial.setControlSignals(GP_serialPortID, { dtr: flag }, ignore);
	}
}

async function GP_setSerialPortRTS(flag) {
	if (GP.boardie_IsOpen) {
		return; // do nothing
	} else if (hasWebSerial()) {
		if (!GP_webSerialPort) return; // port not open
		await GP_webSerialPort.setSignals({ rts: flag, requestToSend: flag }).catch(() => {});
	} else if (hasChromeSerial()) {
		function ignore(result) {}
		flag = (flag) ? true : false;
		chrome.serial.setControlSignals(GP_serialPortID, { rts: flag }, ignore);
	}
}

async function GP_setSerialPortDTRandRTS(dtrFlag, rtsFlag) {
	if (hasWebSerial()) {
		if (!GP_webSerialPort) return; // port not open
		await GP_webSerialPort.setSignals(
			{ dtr: dtrFlag, dataTerminalReady: dtrFlag, rts: rtsFlag, requestToSend: rtsFlag }
		).catch(() => {});
	} else if (hasChromeSerial()) {
		function ignore(result) {}
		flag = (flag) ? true : false;
		chrome.serial.setControlSignals(GP_serialPortID, { dtr: dtrFlag, rts: rtsFlag }, ignore);
	}
}

// Support for Web Bluetooth

// MicroBlocks UUIDs:
const MICROBLOCKS_SERVICE_UUID = 'bb37a001-b922-4018-8e74-e14824b3a638'
const MICROBLOCKS_RX_CHAR_UUID = 'bb37a002-b922-4018-8e74-e14824b3a638' // board receive characteristic
const MICROBLOCKS_TX_CHAR_UUID = 'bb37a003-b922-4018-8e74-e14824b3a638' // board transmit characteristic

const BLE_PACKET_LEN = 240; // Max BLE attribute length is 512 but 240 gives best performance

class NimBLESerial {
	// Device to communicate over BLE using the Nordic Semiconductor UART service

	constructor() {
		this.device = undefined;
		this.service = undefined;
		this.rx_char = undefined;
		this.connected = false;
		this.sendInProgress = false;
	}

	handle_disconnected(event) {
		console.log("BLE disconnected");
		this.rx_char = undefined;
		this.connected = false;
		this.sendInProgress = false;
	}

	handle_read(event) {
		let data = new Uint8Array(event.target.value.buffer);
		GP_serialInputBuffers.push(data);
	}

	async connect() {
		// Connect to a microBit
		this.device = await navigator.bluetooth.requestDevice({
			filters: [{ services: [MICROBLOCKS_SERVICE_UUID] }]
		})
		this.device.addEventListener('gattserverdisconnected', this.handle_disconnected.bind(this));
		const server = await this.device.gatt.connect();
		this.service = await server.getPrimaryService(MICROBLOCKS_SERVICE_UUID);
		const tx_char = await this.service.getCharacteristic(MICROBLOCKS_TX_CHAR_UUID);
		this.rx_char = await this.service.getCharacteristic(MICROBLOCKS_RX_CHAR_UUID);
		await tx_char.startNotifications();
		// bind overrides the default this=tx_char to this=the NimBLESerial
		tx_char.addEventListener("characteristicvaluechanged", this.handle_read.bind(this));
 		this.connected = true;
		this.sendInProgress = false;
		console.log("BLE connected");
	}

	disconnect() {
		if (this.device != undefined) {
			this.device.gatt.disconnect();
		}
	}

	isConnected() {
		return this.connected;
	}

	write_data(data) {
		// Write the given data (a Uint8Array) and return the number of bytes written.

		if ((this.rx_char == undefined) || !this.connected) {
			console.log("Not connected");
			return 0;
		}
		if (this.sendInProgress) {
			console.log("Send in progress in gpSupport.js write_data()");
			return 0;
		}
		let byteCount = (data.length > BLE_PACKET_LEN) ? BLE_PACKET_LEN : data.length;
		this.async_write_data(data.subarray(0, byteCount));
		return byteCount;
 	}

	async async_write_data(data) {
		if (this.rx_char == undefined) return;
		this.sendInProgress = true;
		try {
			await this.rx_char.writeValueWithoutResponse(data);
		} catch (error) {
			// print the error; give up if BLE has been disconnected
			console.log("BLE write failed:\n ", error);
		}
		this.sendInProgress = false;
	}
}

const bleSerial = new NimBLESerial();

// File read/write

function hasChromeFilesystem() {
	return ((typeof chrome != 'undefined') && (typeof chrome.fileSystem != 'undefined'))
}

async function GP_ReadFile(ext) {
	// Upload using Native File API.

	function onFileSelected(entry) {
		void chrome.runtime.lastError; // suppress error message
		if (!entry) return; // no file selected
		entry.file(function(file) {
			var reader = new FileReader();
			reader.onload = function(evt) {
				GP.droppedFiles.push({ name: toUTF8Array(file.name), contents: evt.target.result });
			};
			reader.readAsArrayBuffer(file);
		});
	}

	if (hasChromeFilesystem()) {
		if ('' == ext) ext = 'txt';
		const options = {
			type: 'openFile',
			accepts: [{ description: 'MicroBlocks', extensions: [ext] }]
		};
		chrome.fileSystem.chooseEntry(options, onFileSelected);
	} else if (typeof window.showOpenFilePicker != 'undefined') { // Native Filesystem API
		var options = {};
		if ('' != ext) {
			options = { types: [{ description: 'MicroBlocks', accept: { 'text/plain': ['.' + ext] }}] };
		}
		const files = await window.showOpenFilePicker(options).catch((e) => { console.log(e); });
		if (typeof files === 'undefined') { console.log('No file selected.'); return; }
		const file = await files[0].getFile();
		const contents = await file.arrayBuffer();
		GP.droppedFiles.push({ name: toUTF8Array(file.name), contents: contents });
	} else {
		GP_UploadFiles();
		return;
	}
}

function download(filename, text) {
	// from https://stackoverflow.com/questions/2897619/using-html5-javascript-to-generate-and-save-a-file

	var pom = document.createElement('a');
	pom.setAttribute('href', 'data:text/plain;charset=utf-8,' + encodeURIComponent(text));
	pom.setAttribute('download', filename);

	if (document.createEvent) {
		var event = document.createEvent('MouseEvents');
		event.initEvent('click', true, true);
		pom.dispatchEvent(event);
	} else {
		pom.click();
	}
}

async function GP_writeFile(data, fName, id) {
	// Write the given data to the given file. fName should include an extension.
	// id is hint for the operation type (e.g. 'project' for saving a project file).
	// The browser remembers the folder for the last save with that id.

	function onFileSelected(entry) {
		void chrome.runtime.lastError; // suppress error message
		if (entry) entry.createWriter(function(writer) {
			GP.lastSavedFileName = entry.name;
			writer.write(new Blob([data], {type: 'text/plain'})); });
	}

	i = fName.lastIndexOf('.');
	ext = (i >= 0) ? fName.substr(i + 1) : '';

	i = fName.lastIndexOf('.');
	if (i > 0) fName = fName.substr(0, i);
	if (i == 0) fName = 'Untitled';

	if (hasChromeFilesystem()) {
		// extract the extension from fName
		const options = {
			type: 'saveFile',
			suggestedName: fName + '.' + ext,
			accepts: [{ description: 'MicroBlocks', extensions: [ext] }]
		};
		chrome.fileSystem.chooseEntry(options, onFileSelected);
	} else if (typeof window.showSaveFilePicker != 'undefined') { // Native Filesystem API
		if (/(CrOS)/.test(navigator.userAgent) || /Linux/.test(navigator.userAgent)) {
			// On Chromebooks and Linux, the extension is not automatically appended.
			fName = fName + '.' + ext;
		}
		options = { suggestedName: fName, id: id };
		if ('' != ext) {
			if ('.' != ext[0]) ext = '.' + ext;
			if (('.hex' == ext) || ('.uf2' == ext)) {
				options.types = [{ accept: { 'application/octet-stream': [ext] } }];
			} else {
				options.types = [{ accept: { 'text/plain': [ext] } }];
			}
		}

		const fileHandle = await window.showSaveFilePicker(options).catch((e) => { console.log(e); });
		if (!fileHandle) {
			GP.lastSavedFileName = '_no_file_selected_';
			return; // no file selected
		}
		const writable = await fileHandle.createWritable();
		await writable.write(new Blob([data]));
		await writable.close().catch(() => {});
		GP.lastSavedFileName = fileHandle.name;
	} else {
		saveAs(new Blob([data]), fName + '.' + ext);
	}
}

// On ChromeOS, read the file opened to launch the application, if any

function GP_ChromebookLaunch(bgPage) {
	if (bgPage.launchFileEntry) {
		var fName = bgPage.launchFileEntry.fullPath;
		bgPage.launchFileEntry.file(function(file) {
			var reader = new FileReader();
			reader.onload = function(evt) {
				GP.droppedFiles.push({ name: toUTF8Array(fName), contents: evt.target.result });
			};
			reader.readAsArrayBuffer(file);
		});
	}
}

if ((typeof chrome != 'undefined') &&
	(typeof chrome.runtime != 'undefined') &&
	(typeof chrome.runtime.getBackgroundPage != 'undefined')) {
		chrome.runtime.getBackgroundPage(GP_ChromebookLaunch);
}

// warn before leaving page

window.onbeforeunload = function() {
	return "Leave this page? (changes will be lost)";
};

// progressive web app service worker

window.onload = function() {
	if (('serviceWorker' in navigator) && !hasChromeFilesystem()) {
		navigator.serviceWorker.register('sw.js');
	}
}
