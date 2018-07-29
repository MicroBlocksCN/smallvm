// soundPrims.c
// John Maloney, October 2013

#include <stdio.h>
#include <string.h>
#include <sys/time.h>

#include "mem.h"
#include "interp.h"
#include "dict.h"

// ***** Audio Output *****

#ifdef EMSCRIPTEN

#include <emscripten.h>
#define M_PI 3.14159

static void startAudioOutput(int frameCount, int stereoFlag) {
	EM_ASM_({
		GP_startAudioOutput($0, $1);
	}, frameCount, stereoFlag);
}

static void stopAudioOutput() {
	EM_ASM({
		GP_stopAudioOutput();
	}, 0);
}

static int samplesNeeded() {
	int frameCount = EM_ASM_INT({
		if (GP.audioOutReady || !GP.audioOutBuffer) return 0;
		var frameCount = GP.audioOutBuffer.length;
		if (GP.audioOutIsStereo) frameCount = frameCount / 2;
		return frameCount;
	}, NULL);
	return frameCount;
}

static void writeSamples(OBJ buffer) {
	EM_ASM_({
		var src = $0 / 4; // word index
		var count = $1;
		if (!GP.audioOutBuffer) return;
		if (GP.audioOutBuffer.length < count) count = GP.audioOutBuffer.length;
		for (var i = 0; i < count; i++) {
			GP.audioOutBuffer[i] = (Module.HEAP32[src++] >> 1) / 32768.0; // convert obj -> int -> float
		}
		GP.audioOutReady = true;
	}, &FIELD(buffer, 0), objWords(buffer));
}

#else // end EMSCRIPTEN sound output

#include "SDL.h"

#define MAX_SAMPLES 8192
static short samples[MAX_SAMPLES];
static int samplesSize = 0; // number of samples actually used, set by startPlaying

static int isPlaying = false;
static int isStereo = false;
static int bufferEmpty = true;

void audioOutCallback(void *ignore, Uint8 *stream, int len) {
	int sampleCount = len / 2;
	short *out = (short *) stream;
	if (bufferEmpty) {
		// write silence (client hasn't provided any samples)
		for (int i = 0; i < sampleCount; i++) {
			*out++ = 0;
		}
	} else {
		// write samples
		short *src = samples;
		for (int i = 0; i < sampleCount; i++) {
			*out++ = *src++;
		}
	}
	bufferEmpty = true;
}

static void stopAudioOutput() {
	if (!isPlaying) return;
	SDL_PauseAudio(true);
	SDL_CloseAudio();
	samplesSize = 0;
	isPlaying = false;
}

static void startAudioOutput(int frameCount, int stereoFlag) {
	if (isPlaying) stopAudioOutput();

	isStereo = stereoFlag;
	int minBufSize = isStereo ? 512 : 256;
	samplesSize = clip(frameCount * (isStereo ? 2 : 1), minBufSize, MAX_SAMPLES);

	// set the audio format
	SDL_AudioSpec wanted;
	wanted.freq = 22050;
	wanted.format = AUDIO_S16SYS;
	wanted.channels = (isStereo ? 2 : 1);
	wanted.samples = (isStereo ? samplesSize / 2 : samplesSize);
#if defined(__linux__) && !defined(_LP64) && !defined(__arm__)
	// work-around for SDL sound bug on 32-bit Linux (Ubuntu 14.04 at least) for sampling rate 22050
	wanted.samples = 2 * wanted.samples;
#endif
	wanted.callback = audioOutCallback;
	wanted.userdata = NULL;

	// open the audio device, forcing the desired format
	if (SDL_OpenAudio(&wanted, NULL) < 0) {
		fprintf(stderr, "Couldn't open SDL audio: %s\n", SDL_GetError());
	} else {
		SDL_PauseAudio(false);
		isPlaying = true;
		bufferEmpty = true;
	}
}

static int samplesNeeded() {
	return (isPlaying && bufferEmpty) ? samplesSize : 0;
}

static void writeSamples(OBJ array) {
	if (!isPlaying || NOT_CLASS(array, ArrayClass)) return;
	int count = WORDS(array);
	if (count > samplesSize) count = samplesSize;
	for (int i = 0; i < samplesSize; i++) {
		if (i < count) {
			OBJ obj = FIELD(array, i);
			samples[i] = (short) ((isInt(obj) ? obj2int(obj) : 0) & 0xFFFF);
		} else {
			samples[i] = 0;
		}
	}
	bufferEmpty = false;
}

#endif // end SDL sound output

OBJ primCloseAudio(int nargs, OBJ args[]) {
	stopAudioOutput();
	return nilObj;
}

OBJ primOpenAudio(int nargs, OBJ args[]) {
	int frameCount = intArg(0, 1024, nargs, args);
	int stereoFlag = ((nargs > 1) && (args[1] == trueObj));
	startAudioOutput(frameCount, stereoFlag);
	return nilObj;
}

OBJ primSamplesNeeded(int nargs, OBJ args[]) {
	return int2obj(samplesNeeded());
}

OBJ primWriteSamples(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ outBuf = args[0];
	if (NOT_CLASS(outBuf, ArrayClass)) return primFailed("Sound output buffer must be an Array");
	writeSamples(outBuf);
	return nilObj;
}

// ***** Simple FFT Primitive *****

#define MAX_FFT 16384
static double windowFunction[MAX_FFT];
static int currentWindowWidth = -1;

void generateHanningWindow(int width) {
	if (currentWindowWidth == width) return; // already computed
	if (width <= 0) return;
	if (width > 16384) width = MAX_FFT; // should not happen
	double twoPiOverMax = ((2.0 * M_PI) / (width - 1));
	for (int i = 0; i < width; i++) {
		windowFunction[i] = (1.0 - cos(twoPiOverMax * i)) / 2.0;
	}
	currentWindowWidth = width;
}

void forwardFFT(long m, double *x, double *y) {
	/*
	 From http://paulbourke.net/miscellaneous/dft
	 (Code for inverse fft removed.)
	 This computes an in-place complex-to-complex FFT
	 x and y are the real and imaginary arrays of 2^m points.
	 */
	long n,i,i1,j,k,i2,l,l1,l2;
	double c1,c2,tx,ty,t1,t2,u1,u2,z;

	/* Calculate the number of points */
	n = 1;
	for (i=0; i<m; i++) n *= 2;

	/* Do the bit reversal */
	i2 = n >> 1;
	j = 0;
	for (i=0; i<n-1; i++) {
		if (i < j) {
			tx = x[i];
			ty = y[i];
			x[i] = x[j];
			y[i] = y[j];
			x[j] = tx;
			y[j] = ty;
		}
		k = i2;
		while (k <= j) {
			j -= k;
			k >>= 1;
		}
		j += k;
	}

	/* Compute the FFT */
	c1 = -1.0;
	c2 = 0.0;
	l2 = 1;
	for (l=0; l<m; l++) {
		l1 = l2;
		l2 <<= 1;
		u1 = 1.0;
		u2 = 0.0;
		for (j=0; j<l1; j++) {
			for (i=j; i<n; i+=l2) {
				i1 = i + l1;
				t1 = u1 * x[i1] - u2 * y[i1];
				t2 = u1 * y[i1] + u2 * x[i1];
				x[i1] = x[i] - t1;
				y[i1] = y[i] - t2;
				x[i] += t1;
				y[i] += t2;
			}
			z =  u1 * c1 - u2 * c2;
			u2 = u1 * c2 + u2 * c1;
			u1 = z;
		}
		c2 = -sqrt((1.0 - c1) / 2.0);
		c1 = sqrt((1.0 + c1) / 2.0);
	}
}

OBJ primFFT(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ buf = args[0];
	int useWindow = (nargs > 1) && (trueObj == args[1]);

	int size = objWords(buf);
	int n = size;
	int log2Size = 0;
	while (n > 1) {
		log2Size += 1;
		n = (n >> 1);
	}
	if (NOT_CLASS(buf, ArrayClass)) return primFailed("The argument must be an Array");
	if (size != (1 << log2Size)) return primFailed("The size of the argument Array must be a power of two.");
	if (size > MAX_FFT) return primFailed("The maximum FFT input size is 16384.");

	double fftReal[MAX_FFT];
	double fftImag[MAX_FFT];
	for (int i = 0; i < size; i++) {
		fftReal[i] = evalFloat(FIELD(buf, i));
		fftImag[i] = 0.0;
	}
	if (useWindow) {
		generateHanningWindow(size);
		for (int i = 0; i < size; i++) {
			fftReal[i] = windowFunction[i] * fftReal[i];
		}
	}

	forwardFFT(log2Size, fftReal, fftImag);

	int resultSize = (size / 2) + 1; // FFT output is symmetric, so just return the lower half plus 1
	OBJ result = newArray(resultSize);
	for (int i = 0; i < resultSize; i++) {
		double real = fftReal[i];
		double imag = fftImag[i];
		FIELD(result, i) = newFloat(sqrt((real * real) + (imag * imag)) / size); // scale to range [0..1]
	}
	// adjust the scale of the first and last bins
	int last = resultSize - 1;
	FIELD(result, 0) = newFloat(evalFloat(FIELD(result, 0)) / 2);
	FIELD(result, last) = newFloat(evalFloat(FIELD(result, last)) / 2);
	return result;
}

// Sampled instrument primitive

#define PLAYER_WORDS 12
#define PLAYER_samples 0
#define PLAYER_sampledKey 1
#define PLAYER_loopEnd 2
#define PLAYER_loopLength 3
#define PLAYER_decayStart 4
#define PLAYER_decayRate 5
#define PLAYER_totalSamples 6
#define PLAYER_samplesPlayed 7
#define PLAYER_incr 8
#define PLAYER_index 9
#define PLAYER_env 10
#define PLAYER_startDelay 11

OBJ primGenerateNoteSamples(int nargs, OBJ args[]) {
	if (nargs < 2) return notEnoughArgsFailure();
	OBJ notePlayer = args[0];
	OBJ buffer = args[1];

	if (objWords(notePlayer) < PLAYER_WORDS) return primFailed("First argument must be a NotePlayer");
	if (NOT_CLASS(buffer, ArrayClass)) return primFailed("Second argument must be an Array of Integers");

	int bufferSize = objWords(buffer);
	int startDelay = obj2int(FIELD(notePlayer, PLAYER_startDelay));
	if (startDelay >= bufferSize) {
		// just update startDelay and return
		FIELD(notePlayer, PLAYER_startDelay) = int2obj(startDelay - bufferSize);
		return nilObj;
	}
	FIELD(notePlayer, PLAYER_startDelay) = int2obj(0); // start delay is over

	OBJ samples = FIELD(notePlayer, PLAYER_samples);
	int loopEnd = evalFloat(FIELD(notePlayer, PLAYER_loopEnd));
	int loopLength = evalFloat(FIELD(notePlayer, PLAYER_loopLength));
	int decayStart = obj2int(FIELD(notePlayer, PLAYER_decayStart));
	double decayRate = evalFloat(FIELD(notePlayer, PLAYER_decayRate));
	int totalSamples = obj2int(FIELD(notePlayer, PLAYER_totalSamples));
	int samplesPlayed = obj2int(FIELD(notePlayer, PLAYER_samplesPlayed)); // must update
	double incr = evalFloat(FIELD(notePlayer, PLAYER_incr));
	double index = evalFloat(FIELD(notePlayer, PLAYER_index)); // must update
	double env = evalFloat(FIELD(notePlayer, PLAYER_env)); // must update

	for (int i = startDelay; i < bufferSize; i++) {
		if (samplesPlayed >= totalSamples) break; // done!

		// compute sample
		int intPart = (int) index;
		double frac = index - intPart;
		int s0 = obj2int(FIELD(samples, (intPart - 1)));
		int s1 = obj2int(FIELD(samples, intPart));
		int interpolated = s0 + (int) (frac * (s1 - s0));

		// mix in the interpolated sample scaled by the envelope
		int mixed = obj2int(FIELD(buffer, i) + (int) (env * interpolated));
		if (mixed > 32767) mixed = 32767;
		if (mixed < -32768) mixed = -32768;
		FIELD(buffer, i) = int2obj(mixed);

		// update source index
		index += incr;
		if (index > loopEnd) {
			if (loopLength == 0) { // unlooped sound; stop playing
				samplesPlayed = totalSamples;
				break; // done!
			}
			index = (index - loopLength);
		}

		// update the envelope
		if ((totalSamples - samplesPlayed) < 100) { // note cutoff ("release")
			env = 0.9 * env; // decay to silence in 100 samples (about 4.5 msecs)
		} else if (samplesPlayed > decayStart) { // decay while note is playing
			env = decayRate * env;
		}

		samplesPlayed++;
	}
	FIELD(notePlayer, PLAYER_samplesPlayed) = int2obj(samplesPlayed);
	FIELD(notePlayer, PLAYER_index) = newFloat(index);
	FIELD(notePlayer, PLAYER_env) = newFloat(env);
	return nilObj;
}

// ***** MIDI and Voice Output (MacOS/iOS only for now) *****

#if defined(__APPLE__) && defined(__MACH__)

#include <CoreMIDI/MIDIServices.h>

MIDIPortRef midiOutPort = 0;
struct MIDIPacketList midiPacketList;

void ensureMIDIOpen() {
	int dstCount = MIDIGetNumberOfDestinations();
	if (!dstCount) printf("There are no MIDI outputs available.\n");

	if (midiOutPort) return; // port is already open

	// Prepare MIDI Interface Client/Port for writing MIDI data:
	MIDIClientRef midiclient = 0;
	int err = MIDIClientCreate(CFSTR("Test client"), NULL, NULL, &midiclient);
	if (err) return;
	MIDIOutputPortCreate(midiclient, CFSTR("Test port"), &midiOutPort);
}

OBJ primSendMIDI(int nargs, OBJ args[]) {
	if (nargs < 2) return nilObj;

	ensureMIDIOpen();

	midiPacketList.numPackets = 1;
	MIDIPacket *packet = &midiPacketList.packet[0];
	packet->timeStamp = 0; // send immediately

	packet->length = (nargs > 2) ? 3 : 2;
	packet->data[0] = intArg(0, 0, nargs, args);
	packet->data[1] = intArg(1, 0, nargs, args);
	packet->data[2] = intArg(2, 0, nargs, args);

	MIDISend(midiOutPort, MIDIGetDestination(0), &midiPacketList);
	return nilObj;
}

OBJ primStartSpeech(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	if (NOT_CLASS(args[0], StringClass)) return primFailed("First argument must be a string");
	if ((nargs > 2) && (NOT_CLASS(args[1], StringClass))) return primFailed("Second argument must be a string");
	if ((nargs > 3) && !isInt(args[2])) return primFailed("Third argument must be an integer");

	char *argList[20];
	argList[0] = "say";
	argList[1] = obj2str(args[0]);
	argList[2] = NULL;
	if (nargs > 1) {
		argList[2] = "-v";
		argList[3] = obj2str(args[1]);
		argList[4] = NULL;
	}
	if (nargs > 2) {
		int r = obj2int(args[2]);
		char rateString[10];
		sprintf(rateString, "%d", clip(r, 10, 2000));
		argList[4] = "-r";
		argList[5] = rateString;
		argList[6] = NULL;
	}
	int pid = fork();
	if (pid == 0) {
		execvp("say", argList);
		exit(0);
		return nilObj;
	}
	return int2obj(pid);
}

OBJ primStopSpeech(int nargs, OBJ args[]) {
	// Note: Although intended to stop speech, this primitive can be used to kill any process.
	// It should probably be rewritten to enumerate and kill "say" processes.
	// See http://stackoverflow.com/questions/7729245/can-i-use-sysctl-to-retrieve-a-process-list-with-the-user
	if (nargs < 1) return notEnoughArgsFailure();
	if (isInt(args[0])) kill(obj2int(args[0]), 9);
	return nilObj;
}

#else // end MacOS/iOS

OBJ primSendMIDI(int nargs, OBJ args[]) { return nilObj; }
OBJ primStartSpeech(int nargs, OBJ args[]) { return nilObj; }
OBJ primStopSpeech(int nargs, OBJ args[]) { return nilObj; }

#endif

// ***** Sound Input *****

#define MAX_SAMPLE_COUNT 16384

#if defined(EMSCRIPTEN)

OBJ primStartAudioInput(int nargs, OBJ args[]) {
	int inputSampleCount = intArg(0, 2048, nargs, args);
	if (inputSampleCount > MAX_SAMPLE_COUNT) inputSampleCount = MAX_SAMPLE_COUNT;
	int sampleRate = intArg(1, 22050, nargs, args);
	if (!((22050 == sampleRate) || (44100 == sampleRate))) {
		return primFailed("Sample rate must be 22050 or 44100");
	}

	EM_ASM_({
		GP_startAudioInput($0, $1);
	}, inputSampleCount, sampleRate);

	return trueObj;
}

OBJ primStopAudioInput(int nargs, OBJ args[]) {
	EM_ASM({
		GP_stopAudioInput();
	}, 0);
	return nilObj;
}

OBJ primReadAudioInput(int nargs, OBJ args[]) {

	int inputSampleCount = EM_ASM_INT({
		if (!GP.audioInReady) return 0;
		return GP.audioInBuffer ? GP.audioInBuffer.length : 0;
	}, NULL);
	if (!inputSampleCount) return nilObj;

	OBJ result = newArray(inputSampleCount);
	EM_ASM_({
		var dst = $0 / 4; // word index
		var len = $1;
		for (var i = 0; i < len; i++) {
			Module.HEAPU32[dst++] = (GP.audioInBuffer[i] << 1) | 1;
		}
		GP.audioInReady = false;
	}, &FIELD(result, 0), inputSampleCount);
	return result;
}

#elif !defined(NO_SOUND) && !defined(NO_PORTAUDIO)

#include "portaudio.h"

static PaStream *inputStream = NULL;
static int inputSampleCount = 0;
static int inputReady = false; // true when input data is available
static short inBuf[MAX_SAMPLE_COUNT]; // mono

static int audioInputCallback(
	const void *inputBuffer, void *outputBuffer,
	unsigned long framesPerBuffer,
	const PaStreamCallbackTimeInfo* timeInfo,
	PaStreamCallbackFlags statusFlags,
	void *userData)
{
	short *dstPtr = inBuf;
	short *end = dstPtr + inputSampleCount;
	short *srcPtr = (short *) inputBuffer;
	while (dstPtr < end) *dstPtr++ = *srcPtr++;

	inputReady = true;
    return 0;
}

OBJ primStopAudioInput(int nargs, OBJ args[]) {
	if (inputStream) {
		Pa_AbortStream(inputStream);
		Pa_Terminate();
		inputStream = NULL;
	}
	inputSampleCount = 0;
	inputReady = false;
	return nilObj;
}

OBJ primStartAudioInput(int nargs, OBJ args[]) {
	if (inputStream) return trueObj;

	inputSampleCount = intArg(0, 2048, nargs, args);
	if (inputSampleCount > MAX_SAMPLE_COUNT) inputSampleCount = MAX_SAMPLE_COUNT;
	int sampleRate = intArg(1, 22050, nargs, args);
	if (!((22050 == sampleRate) || (44100 == sampleRate))) {
		return primFailed("Sample rate must be 22050 or 44100");
	}

	int err = Pa_Initialize();
	if (!err) err = Pa_OpenDefaultStream(&inputStream, 1, 0, paInt16, sampleRate, inputSampleCount, audioInputCallback, NULL);
	if (!err) err = Pa_StartStream(inputStream);
	if (err) {
		char s[200];
		snprintf(s, 200, "PortAudio error %s\n", Pa_GetErrorText(err));
		primStopAudioInput(0, NULL);
		return primFailed(s);
	}
	inputReady = false;
	return trueObj;
}

OBJ primReadAudioInput(int nargs, OBJ args[]) {
	if (!inputStream || !inputReady) return nilObj;

	OBJ result = newArray(inputSampleCount);

	short *srcPtr = inBuf;
	short *end = srcPtr + inputSampleCount;
	OBJ *dstPtr = &FIELD(result, 0);
	while (srcPtr < end) *dstPtr++ = int2obj(*srcPtr++);

	inputReady = false;
	return result;
}

#else // end portaudio sound input

OBJ primStartAudioInput(int nargs, OBJ args[]) { return falseObj; }
OBJ primStopAudioInput(int nargs, OBJ args[]) { return nilObj; }
OBJ primReadAudioInput(int nargs, OBJ args[]) { return nilObj; }

#endif // end no sound input

// ***** Sound Primitives *****

PrimEntry soundPrimList[] = {
	{"-----", NULL, "Sound"},
	{"openAudio",		primOpenAudio,		"Open the audio output driver. The optional frameCount argument is the number of stereo or mono samples (frames) to buffer, a power of 2 between 256 and 8192. Output is mono unless optional stereoFlag argument is true. Arguments: [frameCount stereoFlag]"},
	{"closeAudio",		primCloseAudio,		"Close the audio output driver."},
	{"samplesNeeded",	primSamplesNeeded,	"Return the number of stereo or mono samples (frames) needed. Zero if there's is no room in the buffer."},
	{"writeSamples",	primWriteSamples,	"Write sound samples (an array of signed, 16-bit integers). If stereo, left and right channels are interleaved. Arguments: sampleArray"},
	{"fft",				primFFT,			"Return the Fast Fourier Transform (FFT) of an audio buffer. The argument must be an Array of Integers or Floats whose size is a power of 2."},
	{"generateNoteSamples",	primGenerateNoteSamples, "Generate samples for a sampled instrument note. Arguements: aNotePlayer sampleArray"},
	{"sendMIDI",		primSendMIDI,		"Send a MIDI 2 or 3 byte MIDI message. Arguments: byte1 byte2 [byte3]"},
	{"startSpeech",		primStartSpeech,	"On platforms that suppot text-to-speech, speak the given text with the given voice and rate. Return the speech process id. Arguments: text voiceName"},
	{"stopSpeech",		primStopSpeech,		"Stop the speech with the given speech process id."},
	{"startAudioInput",	primStartAudioInput, "Start audio input. Arguments: [bufferSize sampleRate]"},
	{"stopAudioInput",	primStopAudioInput,	"Stop audio input."},
	{"readAudioInput",	primReadAudioInput,	"Return an audio input buffer of integer sound samples in the range -32768 to 32767, or nil if no data is available."},
};

PrimEntry* soundPrimitives(int *primCount) {
	*primCount = sizeof(soundPrimList) / sizeof(PrimEntry);
	return soundPrimList;
}
