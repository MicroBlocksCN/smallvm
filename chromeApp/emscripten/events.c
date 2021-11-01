// events.c - SDL2 Events
// John Maloney, February 2014

#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>
#include <time.h>

#include "mem.h"
#include "dict.h"
#include "interp.h"

// From graphicsPrims.c:
extern int mouseScale;
extern int windowWidth;
extern int windowHeight;

static int initialized = false;

// ***** Event Keys and Type Names *****

static int _button;
static int _char;
static int _data1;
static int _data2;
static int _dx;
static int _dy;
static int _eventID;
static int _file;
static int _fingerID;
static int _keycode;
static int _keymodifiers;
static int _pressure;
static int _text;
static int _timestamp;
static int _touchID;
static int _type;
static int _windowID;
static int _x;
static int _y;

static int type_dropfile;
static int type_droptext;
static int type_keydown;
static int type_keyup;
static int type_mousedown;
static int type_mouseup;
static int type_mousemove;
static int type_mousewheel;
static int type_quit;
static int type_textinput;
static int type_touchdown;
static int type_touchmove;
static int type_touchup;
static int type_window;

// ***** Event Key Initialization *****

static int keyIndex = 0;

static int makeKey(char *key) {
	FIELD(eventKeys, keyIndex) = newString(key);
	return keyIndex++;
}

static OBJ key(int index) {
	if ((index < 0) || (index >= objWords(eventKeys))) {
		printf("implementation error! bad key index in events.c");
		exit(-1);
	}
	return FIELD(eventKeys, index);
}

static void initialize() {
	eventKeys = newArray(50);
	keyIndex = 0;

	_button = makeKey("button");
	_char = makeKey("char");
	_data1 = makeKey("data1");
	_data2 = makeKey("data2");
	_dx = makeKey("dx");
	_dy = makeKey("dy");
	_eventID = makeKey("eventID");
	_file = makeKey("file");
	_fingerID = makeKey("fingerID");
	_keycode = makeKey("keycode");
	_keymodifiers = makeKey("modifierKeys");
	_pressure = makeKey("pressure");
	_text = makeKey("text");
	_timestamp = makeKey("timestamp");
	_touchID = makeKey("touchID");
	_type = makeKey("type");
	_windowID = makeKey("windowID");
	_x = makeKey("x");
	_y = makeKey("y");

	type_dropfile = makeKey("dropFile");
	type_droptext = makeKey("dropText");
	type_keydown = makeKey("keyDown");
	type_keyup = makeKey("keyUp");
	type_mousedown = makeKey("mouseDown");
	type_mousemove = makeKey("mouseMove");
	type_mouseup = makeKey("mouseUp");
	type_mousewheel = makeKey("mousewheel");
	type_quit = makeKey("quit");
	type_textinput = makeKey("textinput");
	type_touchdown = makeKey("touchdown");
	type_touchup = makeKey("touchup");
	type_touchmove = makeKey("touchmove");
	type_window = makeKey("window");

	if (keyIndex >= objWords(eventKeys)) {
		printf("implementation error: event keys is not large enough in event.c");
		exit(-1);
	}
	initialized = true;
}

// ***** Entry Point *****

#ifdef EMSCRIPTEN

#include <emscripten.h>

// Emscripten event types:

#define MOUSE_DOWN		1
#define MOUSE_UP		2
#define MOUSE_MOVE		3
#define MOUSE_WHEEL		4
#define KEY_DOWN		5
#define KEY_UP			6
#define TEXTINPUT		7
#define TOUCH_DOWN		8
#define TOUCH_UP		9
#define TOUCH_MOVE		10

// position of last touchmove event used for the touchup event
int lastTouchX = 0;
int lastTouchY = 0;

static void codePointToUTF8(int unicode, char *utf8) {
	// Write the UTF8 encoding of the given Unicode character into utf8, followed by
	// a zero terminator byte. utf8 should have room for up to four bytes.

	int dst = 0;
	if (unicode < 0x80) {
		utf8[dst++] = unicode;
	} else if (unicode < 0x800) {
		utf8[dst++] = 0xc0 | (unicode >> 6);
		utf8[dst++] = 0x80 | (unicode & 0x3F);
	} else if (unicode < 0x10000) {
		utf8[dst++] = 0xe0 | (unicode >> 12);
		utf8[dst++] = 0x80 | ((unicode >> 6) & 0x3F);
		utf8[dst++] = 0x80 | (unicode & 0x3F);
	} else if (unicode <= 0x10FFFF) {
		utf8[dst++] = 0xf0 | (unicode >> 18);
		utf8[dst++] = 0x80 | ((unicode >> 12) & 0x3F);
		utf8[dst++] = 0x80 | ((unicode >> 6) & 0x3F);
		utf8[dst++] = 0x80 | (unicode & 0x3F);
	}
	utf8[dst] = 0; // zero terminator
}

OBJ getEvent() {
	if (!initialized) initialize();

	int evtLen = EM_ASM_INT({
		if (GP.events.length == 0) return -1;
		return GP.events[0].length; // length of the first event buffer
	}, NULL);
	if (evtLen < 0) return nilObj; // no events

	uint32 evt[100]; // event buffer
	EM_ASM_({
		var buf = ($0 / 4); // covert byte to word index
		var evt = GP.events.shift();
		var evtLen = evt.length;
		if (evtLen > 100) evtLen = 100;
		for (var i = 0; i < evt.length; i++) {
			Module.HEAPU32[buf++] = evt[i];
		}
	}, evt);

	struct timeval now;
	gettimeofday(&now, NULL);
	int secs = now.tv_sec - startTime.tv_sec;
	int usecs = now.tv_usec - startTime.tv_usec;
	OBJ timestamp = int2obj(((1000 * secs) + (usecs / 1000)) & 0x3FFFFFFF);

	char utf8[8];
	int evtType = evt[0];
	OBJ dict = newDict(10);
	dictAtPut(dict, key(_type), int2obj(evtType)); // defaults to event type integer
	dictAtPut(dict, key(_timestamp), timestamp);
	switch (evtType) {
		case MOUSE_DOWN:
		case MOUSE_UP:
			dictAtPut(dict, key(_type), key((evtType == MOUSE_DOWN) ? type_mousedown : type_mouseup));
			dictAtPut(dict, key(_x), int2obj(evt[1]));
			dictAtPut(dict, key(_y), int2obj(evt[2]));
			dictAtPut(dict, key(_button), int2obj(evt[3] ? 3 : 0)); // non-zero is right button
			dictAtPut(dict, key(_keymodifiers), int2obj(evt[4]));
			break;
		case MOUSE_MOVE:
			dictAtPut(dict, key(_type), key(type_mousemove));
			dictAtPut(dict, key(_x), int2obj(evt[1]));
			dictAtPut(dict, key(_y), int2obj(evt[2]));
			break;
		case MOUSE_WHEEL:
			dictAtPut(dict, key(_type), key(type_mousewheel));
			dictAtPut(dict, key(_x), int2obj(evt[1]));
			dictAtPut(dict, key(_y), int2obj(evt[2]));
			break;
		case KEY_DOWN:
		case KEY_UP:
			dictAtPut(dict, key(_type), key((evtType == KEY_DOWN) ? type_keydown : type_keyup));
			dictAtPut(dict, key(_keycode), int2obj(evt[1]));
			dictAtPut(dict, key(_char), int2obj(evt[2]));
			dictAtPut(dict, key(_keymodifiers), int2obj(evt[3]));
			break;
		case TEXTINPUT:
			codePointToUTF8(evt[1], utf8);
			dictAtPut(dict, key(_type), key(type_textinput));
			dictAtPut(dict, key(_text), newString(utf8));
			break;
		case TOUCH_MOVE:
		case TOUCH_DOWN:
		case TOUCH_UP:
			// Report touch events as mouse events to support mobile devices.
			if (TOUCH_MOVE == evtType) evtType = type_mousemove;
			else if (TOUCH_DOWN == evtType) evtType = type_mousedown;
			else evtType = type_mouseup;

			// use last known position for touchup event
			if (evtType == type_mouseup) {
				evt[1] = lastTouchX;
				evt[2] = lastTouchY;
			} else {
				lastTouchX = evt[1];
				lastTouchY = evt[2];
			}
			dictAtPut(dict, key(_type), key(evtType));
			dictAtPut(dict, key(_x), int2obj(evt[1]));
			dictAtPut(dict, key(_y), int2obj(evt[2]));
			dictAtPut(dict, key(_button), int2obj(evt[3]));
			break;
	}
	return dict;
}

#else // SDL version

#include "SDL.h"
#include "SDL_events.h"

static int hScrollSign = 1;

static int htmlKeycode(int keycode) {
	// Convert an SDL key code to an HTML5 key code. Range is 0..255.

	if ((4 <= keycode) && (keycode <= 29)) return keycode + 61; // letters A-Z
	if ((30 <= keycode) && (keycode <= 38)) return keycode + 19; // digits 1-9
	if ((58 <= keycode) && (keycode <= 69)) return keycode + 54; // function keys F1-F12

	switch (keycode) {
	case 39: return 48; // digit 0
	case 40: return 13; // enter
	case 41: return 27; // escape
	case 42: return 8;  // backspace
	case 43: return 9;  // tab
	case 44: return 32; // space
	case 45: return 189; // -
	case 46: return 187; // =
	case 47: return 219; // [
	case 48: return 221; // ]
	case 49: return 220; // backslash
	case 51: return 186; // ;
	case 52: return 222; // '
	case 53: return 192; // `
	case 54: return 188; // ,
	case 55: return 190; // .
	case 56: return 191; // /
	case 57: return 20; // caps lock
	case 76: return 46; // delete
	case 79: return 39; // right arrow
	case 80: return 37; // left arrow
	case 81: return 40; // down arrow
	case 82: return 38; // up arrow

	// modifier keys:
	case 224: return 17; // control
	case 225: return 16; // left shift
	case 226: return 18; // left option
	case 227: return 91; // left command/window
	case 229: return 16; // right shift (same as left in html)
	case 230: return 18; // right option (same as left in html)
	case 231: return 93; // right command/window
	}
	return keycode & 0xFF;
}

extern SDL_Window *window; // from graphicsPrims

static void updateMouseScale() {
	int logicalW, logicalH, actualW, actualH;
	SDL_GetWindowSize(window, &logicalW, &logicalH);
	SDL_GL_GetDrawableSize(window, &actualW, &actualH);
	mouseScale = (actualW == (2 * logicalW)) ? 2 : 1;
}

OBJ getEvent() {

	if (!initialized) {
		initialize();

		// Note: Mac OS also requires a plist setting to enable file drop
		SDL_EventState(SDL_DROPFILE, SDL_ENABLE); // allow file drop events

		SDL_version version;
		SDL_GetVersion(&version);
		if (version.patch > 2) hScrollSign = -1;
	}

	SDL_Event event;
	int evtType;

	while (true) { // skip events we're not interested in
		if (!SDL_PollEvent(&event)) return nilObj; // no more events
		evtType = event.type;
		if ((0x700 <= evtType) && (evtType <= 0x702)) continue; // skip touch events
		if ((0x800 <= evtType) && (evtType <= 0x802)) continue; // skip gesture events
		break;
	}

	int charCode, modifiers;
	OBJ dict = newDict(15);
	dictAtPut(dict, key(_type), int2obj(event.type));
	dictAtPut(dict, key(_timestamp), int2obj(event.common.timestamp));
	switch (event.type) {
		case SDL_MOUSEMOTION:
			dictAtPut(dict, key(_type), key(type_mousemove));
			dictAtPut(dict, key(_windowID), int2obj(event.motion.windowID));
			dictAtPut(dict, key(_x), int2obj(event.motion.x * mouseScale));
			dictAtPut(dict, key(_y), int2obj(event.motion.y * mouseScale));
			break;
		case SDL_MOUSEBUTTONDOWN:
		case SDL_MOUSEBUTTONUP:
			dictAtPut(dict, key(_type), key((event.type == SDL_MOUSEBUTTONDOWN) ? type_mousedown : type_mouseup));
			dictAtPut(dict, key(_windowID), int2obj(event.button.windowID));
			dictAtPut(dict, key(_button), int2obj(event.button.button));
			dictAtPut(dict, key(_x), int2obj(event.button.x * mouseScale));
			dictAtPut(dict, key(_y), int2obj(event.button.y * mouseScale));
			break;
		case SDL_MOUSEWHEEL:
			dictAtPut(dict, key(_type), key(type_mousewheel));
			dictAtPut(dict, key(_windowID), int2obj(event.wheel.windowID));
			dictAtPut(dict, key(_x), int2obj(event.wheel.x * hScrollSign));
			dictAtPut(dict, key(_y), int2obj(event.wheel.y));
			break;
		case SDL_FINGERMOTION:
		case SDL_FINGERDOWN:
		case SDL_FINGERUP:
			if (SDL_FINGERMOTION == event.type) evtType = type_touchmove;
			else if (SDL_FINGERDOWN == event.type) evtType = type_touchdown;
			else evtType = type_touchup;
			dictAtPut(dict, key(_type), key(evtType));
			dictAtPut(dict, key(_touchID), int2obj((int) event.tfinger.touchId & 0x3FFFFFF));
			dictAtPut(dict, key(_fingerID), int2obj((int) event.tfinger.fingerId & 0x3FFFFFF));
			dictAtPut(dict, key(_x), newFloat(event.tfinger.x));
			dictAtPut(dict, key(_y), newFloat(event.tfinger.y));
			dictAtPut(dict, key(_dx), newFloat(event.tfinger.dx));
			dictAtPut(dict, key(_dy), newFloat(event.tfinger.dy));
			dictAtPut(dict, key(_pressure), newFloat(event.tfinger.pressure));
			break;
		case SDL_KEYDOWN:
		case SDL_KEYUP:
			charCode = event.key.keysym.sym;
			if (charCode > 255) charCode = 0; // non character-generating key

			modifiers = 0;
			if (event.key.keysym.mod & KMOD_SHIFT) modifiers |= 1; // shift
			if (event.key.keysym.mod & KMOD_CTRL) modifiers |= 2; // control
			if (event.key.keysym.mod & KMOD_ALT) modifiers |= 4; // alt/option
			if (event.key.keysym.mod & KMOD_GUI) modifiers |= 8; // cmd/meta/windows

			dictAtPut(dict, key(_type), key((event.type == SDL_KEYDOWN) ? type_keydown : type_keyup));
			dictAtPut(dict, key(_windowID), int2obj(event.key.windowID));
			dictAtPut(dict, key(_char), int2obj(charCode));
			dictAtPut(dict, key(_keycode), int2obj(htmlKeycode(event.key.keysym.scancode)));
			dictAtPut(dict, key(_keymodifiers), int2obj(modifiers));
			break;
		case SDL_TEXTINPUT:
			dictAtPut(dict, key(_type), key(type_textinput));
			dictAtPut(dict, key(_windowID), int2obj(event.text.windowID));
			dictAtPut(dict, key(_text), newString(event.text.text));
			break;
		case SDL_DROPFILE:
			dictAtPut(dict, key(_type), key(type_dropfile));
			dictAtPut(dict, key(_file), newString(event.drop.file));
			SDL_free(event.drop.file);
			break;
		case SDL_DROPTEXT:
			dictAtPut(dict, key(_type), key(type_droptext));
			dictAtPut(dict, key(_file), newString(event.drop.file));
			SDL_free(event.drop.file);
			break;
		case SDL_WINDOWEVENT:
			dictAtPut(dict, key(_type), key(type_window));
			dictAtPut(dict, key(_windowID), int2obj(event.window.windowID));
			dictAtPut(dict, key(_eventID), int2obj(event.window.event));
			if ((4 <= event.window.event) && (event.window.event <= 6)) {
				// only move and resize events use the data fields
				dictAtPut(dict, key(_data1), int2obj(event.window.data1));
				dictAtPut(dict, key(_data2), int2obj(event.window.data2));
			}
			if (6 == event.window.event) {
				// SDL_WINDOWEVENT_SIZE_CHANGED: record new size
				updateMouseScale();
				windowWidth = event.window.data1 * mouseScale;
				windowHeight = event.window.data2 * mouseScale;
				createOrUpdateOffscreenBitmap(false);
			}
			break;
		case SDL_QUIT:
			dictAtPut(dict, key(_type), key(type_quit));
			break;
	}
	return dict;
}

#endif // SDL version
