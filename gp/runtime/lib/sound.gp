// sound.gp - Sampled sounds and sound mixer using SDL2 sound output

defineClass Sound samples samplingRate isStereo name

method samples Sound { return samples }
method samplingRate Sound { return samplingRate }
method isStereo Sound { return isStereo }
method name Sound { return name }
method setName Sound s { name = s }

to newSound samples samplingRate isStereo name {
  if (isNil samples) { samples = (array) }
  if (isNil samplingRate) { samplingRate = 22050 }
  if (isNil isStereo) { isStereo = false }
  if (isNil name) { name = '' }
  return (new 'Sound' samples samplingRate isStereo name)
}

method shrinkSound Sound {
  // Reduce to a single channel with a sampling rate of under 32k.

  skip = 1
  if (samplingRate > 32000) {
	skip = (max 1 (truncate (samplingRate / 16000)))
	newSamplingRate = (samplingRate / skip)
  }
  if isStereo {
	skip = (2 * skip)
  }
  if (skip < 2) { return this }
  newSampleCount = (truncate ((count samples) / skip))
  newSamples = (newArray newSampleCount)
  src = 1
  if isStereo {
	for dst newSampleCount {
		s = ((at samples src) + (at samples (src + 1)))
		atPut newSamples dst (s >> 1) // average (use shift for integer divide by 2)
		src += skip
	}
  } else { // mono
	for dst newSampleCount {
		atPut newSamples dst (at samples src)
		src += skip
	}
  }
  return (newSound newSamples newSamplingRate false name)
}

method play Sound { play (newSamplePlayer this) }

defineClass SamplePlayer sound incr index

to newSamplePlayer snd { return (initialize (new 'SamplePlayer') snd) }

method initialize SamplePlayer snd {
  sound = snd
  incr = ((samplingRate snd) / 22050)
  index = 1
  return this
}

// sample generation (mixer API)

method sound SamplePlayer { return sound }
method isDone SamplePlayer { return (index >= (count (samples sound))) }

method mixIntoBuffer SamplePlayer buffer {
  samples = (samples sound)
  srcChannels = 1
  end = (count samples)
  if (isStereo sound) {
	srcChannels = 2
	end = (end - 1)
  }
  for i (count buffer) {
	srcIndex = ((truncate index) * srcChannels)
	if (srcIndex >= end) { return }
	sample = (at samples srcIndex)
	if (not (isNumber sample)) {
	  index = (count samples)
	  return
	}
	frac = (index - (truncate index))
	if (frac != 0) { // interpolate between samples
	  nextIndex = (srcIndex + srcChannels)
	  sample += (truncate (frac * ((at samples nextIndex) - sample)))
	}
	// mix this sample into buffer
	out = ((at buffer i) + sample)
	if (out > 32767) { out = 32767 }
	if (out < -32768) { out = -32768 }
	atPut buffer i out
	index += incr
  }
}

method play SamplePlayer {
  // Useful for testing from command line.
  mixer = (getMixer)
  addSound mixer this
  while (not (isDone this)) {
	step mixer
	waitMSecs 5
  }
}


defineClass SoundMixer players buffer msecs lastMixMSecs speechPIDs

method hasPlayingSounds SoundMixer { return ((count players) > 0) }
method msecs SoundMixer { return (round msecs) }
method nextMSecs SoundMixer = { return (round (msecs + ((count buffer) / 22.050))) }

method estimatedMSecs SoundMixer {
  return (msecs + ((msecsSinceStart) - lastMixMSecs))
}

to newSoundMixer { return (reset (new 'SoundMixer')) }

to getMixer {
  // Get an existing sound mixer if there is one. Create one and
  // remember it if there isn't. Works in the prompt and in Morphic.
  mixer = (global 'mixer')
  if (notNil mixer) { return mixer }
  page = (global 'page')
  if (notNil page) { return (soundMixer page) }
  mixer = (newSoundMixer)
  setGlobal 'mixer' mixer
  return mixer
}

method reset SoundMixer {
  stopSpeaking this
  closeAudio
  players = (list)
  buffer = nil
  msecs = 0
  lastMixMSecs = (msecsSinceStart)
  return this
}


method stopAllSounds SoundMixer {
  stopSpeaking this
  stopAudioInput
  players = (list)
}

method isPlaying SoundMixer snd {
  for p players {
	if ((sound p) == snd) { return true }
  }
  return false
}

method addSound SoundMixer snd {
  if (isClass snd 'Sound') {
	add players (newSamplePlayer snd)
  } else {
	add players snd
  }
}

method removeSound SoundMixer snd {
  newPlayers = (list)
  for p players {
	if ((sound p) != snd) { add newPlayers p }
  }
  players = newPlayers
}

method step SoundMixer {
  // Mix and output samples for all sound players.

  if (isEmpty players) { return }

  // bufferSize is a tradeoff between low latency (starting sounds quickly) and avoiding skipping. A size
  // of 1024 works on a Mac Powerbook, but some browsers (e.g. Safari) need more.
  bufferSize = 2048
  if ('Browser' == (platform)) { bufferSize = 8192 }
  if (isNil buffer) {
    openAudio bufferSize
    if ((samplesNeeded) > 0) { bufferSize = (samplesNeeded) } // buffer may be smaller than requested
	buffer = (newArray bufferSize)
	msecs = 0
  }
  if ((samplesNeeded) == 0) { return }
  lastMixMSecs = (msecsSinceStart)

  finished = (list)
  fillArray buffer 0
  for p (copy players) {
	mixIntoBuffer p buffer
	if (isDone p) { add finished p }
  }
  writeSamples buffer
  if ((count finished) > 0) { removeAll players finished }
  msecs += ((count buffer) / 22.050)
  gcIfNeeded
}

method speak SoundMixer text voice rate {
  if (isNil voice) { voice = 'Alex' }
  if (isNil rate) { rate = 150 }
  pid = (startSpeech text voice rate)
  add speechPIDs pid
}

method stopSpeaking SoundMixer {
  if (isNil speechPIDs) { speechPIDs = (list) }
  for pid speechPIDs { stopSpeech pid }
  speechPIDs = (list)
}

to soundInput {
  // Wait for sound input and return an array of signed, 16-bit integer samples.
  startAudioInput 1024 22050
  while true {
	buf = (readAudioInput)
	if (notNil buf) { return buf }
	waitMSecs 1
  }
}
