// notePlayer.gp - Support for sampled instruments and drums.
//
// A NotePlayer generates one note. It supports pitch-shifting, optional looping (for sustaining
// the note), optional decay while sustaining, and smooth cut-offs.
//
// A SampledInstrument is a collection of sampled notes to cover different pitch ranges
// or different drums/percussion instruments.

defineClass NotePlayer samples sampledKey loopEnd loopLength decayStart decayRate totalSamples samplesPlayed incr index env startDelay

method play NotePlayer {
  // For testing. Example:
  //   p = (newSampledInstrument 'clarinet')
  //   for k (range 60 72) { play (notePlayer p k 170) }
  mixer = (getMixer)
  addSound mixer this
  while (not (isDone this)) {
	step mixer
	waitMSecs 5
  }
}

method setStartDelay NotePlayer n { startDelay = n }

method setPitchDurLoudness NotePlayer midiKey msecs loudness {
  // Follows MIDI conventions: midiKey is the key number, where 60 is middle-C. Fractional
  // key values are allowed to get pitches not in the equal-tempered scale.
  // Loudness range is 1-127. Internally, this range maps to an exponential curve.
  if (isNil loudness) { loudness = 80 }
  totalSamples  = (ceiling (msecs * 22.05))
  samplesPlayed = 0
  if (loopEnd == -1) {
	loopEnd = ((count samples) - 1)
	totalSamples = loopEnd
  }
  pitch = (keyToPitch this midiKey)
  originalPitch = (keyToPitch this sampledKey)
  incr = (pitch / originalPitch)
  index = 1
  env = ((raise 50 (loudness / 180)) / 50)
  startDelay = 0 // may be changed by score player
}

method keyToPitch NotePlayer midiKey {
  midiKey = (clamp midiKey 0 127)
  return (440 * (raise 2 ((midiKey - 69) / 12))) // midi key 69 is 440 Hz (A above middle C)
}

// sample generation (mixer API)

method sound NotePlayer { return this }
method isDone NotePlayer { return (samplesPlayed >= totalSamples) }

method mixIntoBuffer NotePlayer buffer {
  if true { // make false to disable the primitive
	generateNoteSamples this buffer
	return
  }
  bufferSize = (count buffer)
  if (startDelay >= bufferSize) {
	startDelay = (startDelay - bufferSize)
	return
  }
  for i (range (startDelay + 1) bufferSize) {
	if (samplesPlayed >= totalSamples) { return }
	intPart = (truncate index)
	frac = (index - intPart)
	s0 = (at samples intPart)
	s1 = (at samples (intPart + 1))
	interpolated = (s0 + (truncate (frac * (s1 - s0))))

	// mix in the interpolated sample scaled by the envelope
	mixed = ((at buffer i) + (truncate (env * interpolated)))
	if (mixed > 32767) { mixed = 32767; clip = true }
	if (mixed < -32768) { mixed = -32768; clip = true }
	atPut buffer i mixed

	// update source index
	index += incr
	if (index > loopEnd) {
	  if (loopLength == 0) { // unlooped sound; stop playing
		samplesPlayed = totalSamples
		return
	  }
	  index = (index - loopLength)
	}

	// update the envelope
	if ((totalSamples - samplesPlayed) < 100) { // note cutoff ("release")
	  env = (0.9 * env) // decay to silence in 100 samples (about 4.5 msecs)
	} (samplesPlayed > decayStart) { // decay while note is playing
	  env = (decayRate * env)
	}
	samplesPlayed += 1
  }
  startDelay = 0
}

defineClass SampledInstrument instrumentName sampleSet

method instrumentName SampledInstrument { return instrumentName }

to newSampledInstrument instName {
  return (init (new 'SampledInstrument') instName)
}

to sampledInstrumentFromSamples samples midiKey instrName {
  if (isNil midiKey) { midiKey = 72 }
  if (isNil instrName) { instrName = 'samples' }
  instrument = instrName
  sampleSet = (list
	(list 128 samples midiKey -1 -1 0 0)) // unlooped, no decay
  return (new 'SampledInstrument' instrName sampleSet)
}

to instrumentNames {
  return (list
	'bass' 'bassoon' 'brass' 'clarinet' 'drums' 'electric piano' 'guitar'
	'marimba' 'organ' 'piano' 'pizz' 'sax' 'steel drum' 'strings' 'vibraphone'
  )
}

method init SampledInstrument instName {
  instrumentName = instName
  loadSamples this instName
  if (isEmpty sampleSet) {
	error 'Could not load instrument' instName
  }
  return this
}

method notePlayer SampledInstrument midiKey msecs loudness {
  // Return a NotePlayer for a note with the given parameters.
  // Spec format for non-drum instruments:
  //   <key> <samples> <sampled key> <loop start> <loop end> <decay start> <decay>

  if ('drums' == instrumentName) {
	return (drumPlayer this midiKey msecs loudness)
  }
  spec = (specForKey this midiKey)
  samples = (at spec 2)
  sampledKey = (at spec 3)
  loopEnd = (at spec 5)
  loopLength = (loopEnd - (at spec 4))
  decayStart = (truncate (22.050 * (at spec 6)))
  if ((at spec 7) == 0) {
	decayRate = 1 // no decay
  } else {
	decayRate = (raise 33000 (-1 / (22050 * (at spec 7))))
  }
  note = (new 'NotePlayer' samples sampledKey loopEnd loopLength decayStart decayRate)
  setPitchDurLoudness note midiKey msecs loudness
  return note
}

method specForKey SampledInstrument midiKey {
  for spec sampleSet {
	if ((first spec) >= midiKey) { return spec }
  }
  return (last sampleSet)
}

method drumPlayer SampledInstrument midiKey msecs loudness {
  // Return a NotePlayer for drum with the given parameters.
  // Spec format for drums:
  //   <key> <sample file> <pitch shift in semitones> [<loop start> <loop end> [<decay>]]

  midiKey = (toInteger midiKey)
  if (or (midiKey < 35) (midiKey > 81)) {
	midiKey = 75 // placeholder for keys outside the drum range
  }
  spec = (at sampleSet (midiKey - 34)) // drum spec
  samples = (at spec 2)
  sampledKey = (midiKey - (at spec 3)) // adjusted by pitch shift
  loopEnd = -1
  loopLength = 0
  decayStart = 0
  decayRate = 1 // no decay
  if ((count spec) > 3) {
	loopEnd = (at spec 5)
	loopLength = (loopEnd - (at spec 4))
  }
  if ((count spec) > 5) {
	decayRate = (raise 33000 (-1 / (22050 * (at spec 6))))
  }
  note = (new 'NotePlayer' samples sampledKey loopEnd loopLength decayStart decayRate)
  setPitchDurLoudness note midiKey msecs loudness
  return note
}

method loadSamples SampledInstrument instName {
  if ('bass' == instName) { specs = (bassSamples this)
  } ('bassoon' == instName) { specs = (bassoonSamples this)
  } ('brass' == instName) { specs = (brassSamples this)
  } ('clarinet' == instName) { specs = (clarinetSamples this)
  } ('drums' == instName) { specs = (drumSamples this)
  } ('electric piano' == instName) { specs = (electricPianoSamples this)
  } ('guitar' == instName) { specs = (guitarSamples this)
  } ('marimba' == instName) { specs = (marimbaSamples this)
  } ('organ' == instName) { specs = (organSamples this)
  } ('piano' == instName) { specs = (pianoSamples this)
  } ('pizz' == instName) { specs = (pizzSamples this)
  } ('sax' == instName) { specs = (saxSamples this)
  } ('steel drum' == instName) { specs = (steelDrumSamples this)
  } ('strings' == instName) { specs = (stringSamples this)
  } ('vibraphone' == instName) { specs = (vibraphoneSamples this)
  } else {
	print 'No' instName '-- using "piano"'
  	specs = (pianoSamples this)
  }
  sampleSet = (list)
  for spec specs {
	data = (loadSampleFile this (at spec 2))
	if (notNil data) {
	  atPut spec 2 data
	  add sampleSet spec
	}
  }
}

method loadSampleFile SampledInstrument baseName {
  // Load a sample file (WAV file) with the given base name.
  // Sample data is cached so there is only one copy of each in memory.

  instrumentData = (global 'instrumentData')
  if (isNil instrumentData) {
	instrumentData = (dictionary)
	setGlobal 'instrumentData' instrumentData
  }
  if (contains instrumentData baseName) {
	return (at instrumentData baseName)
  }
  fName = (join (runtimeFolder 'instruments/') baseName '.wav')
  if ('drums' == instrumentName) {
	fName = (join (runtimeFolder 'instruments/drums/') baseName '.wav')
  }
  snd = (readWAVFile fName)
  if (notNil snd) {
	if (and (22050 == (samplingRate snd)) (false == (isStereo snd))) {
	  samples = (samples snd)
	  atPut instrumentData baseName samples
	  return samples
	} else {
	  print fName 'is not the right format for a SampledInstrument (mono 22050 samples/second)'
	}
  }
  return nil
}

method bassSamples SampledInstrument {
  return (list
	(list 34 'ElectricBass_G1' 31 41912 42363 0 17)
	(list 48 'ElectricBass_G1' 31 41912 42363 0 14)
	(list 64 'ElectricBass_G1' 31 41912 42363 0 12)
	(list 128 'ElectricBass_G1' 31 41912 42363 0 10))
}

method bassoonSamples SampledInstrument {
  return (list
	(list 57 'Bassoon_C3' 48 2428 4284 0 0)
	(list 67 'Bassoon_C3' 48 2428 4284 0 0)		// [40 0 0)) used slower attack [40 0 0))
	(list 76 'Bassoon_C3' 48 2428 4284 0 0)		// [80 0 0)) used slower attack [80 0 0))
	(list 84 'EnglishHorn_F3' 53 7538 8930 0 0)	// [40 0 0)) used slower attack [40 0 0))
	(list 128 'EnglishHorn_D4' 62 4857 5231 0 0))
}

method brassSamples SampledInstrument {
  return (list
	(list 30 'BassTrombone_A2_3' 45 1357 2360 0 0)
	(list 40 'BassTrombone_A2_2' 45 1893 2896 0 0)
	(list 55 'Trombone_B3' 59 2646 3897 0 0)
	(list 88 'Trombone_B3' 59 2646 3897 0 0)	// [50 0 0)) used slower attack
	(list 128 'Trumpet_E5' 76 2884 3152 0 0))
}

method clarinetSamples SampledInstrument {
  return (list
	(list 128 'Clarinet_C4' 60 14540 15468 0 0))
}

method electricPianoSamples SampledInstrument {
  return (list
	(list 48 'ElectricPiano_C2' 36 15338 17360 80 10)
	(list 74 'ElectricPiano_C4' 60 11426 12016 40 8)
	(list 128 'ElectricPiano_C4' 60 11426 12016 0 6))
}

method guitarSamples SampledInstrument {
  return (list
	(list 40 'AcousticGuitar_F3' 53 36665 36791 0 15)
	(list 56 'AcousticGuitar_F3' 53 36665 36791 0 13.5)
	(list 60 'AcousticGuitar_F3' 53 36665 36791 0 12)
	(list 67 'AcousticGuitar_F3' 53 36665 36791 0 8.5)
	(list 72 'AcousticGuitar_F3' 53 36665 36791 0 7)
	(list 83 'AcousticGuitar_F3' 53 36665 36791 0 5.5)
	(list 128 'AcousticGuitar_F3' 53 36665 36791 0 4.5))
}

method marimbaSamples SampledInstrument {
  return (list
	(list 128 'Marimba_C4' 60 -1 -1 0 0)) // unlooped
}

method organSamples SampledInstrument {
  return (list
	(list 128 'Organ_G2' 43 1306 3330 0 0)) // no decay
}

method pianoSamples SampledInstrument {
  return (list
	(list 38 'AcousticPiano_As3' 58 10266 17053 100 22)
	(list 44 'AcousticPiano_C4' 60 13968 18975 100 20)
	(list 51 'AcousticPiano_G4' 67 12200 12370 80 18)
	(list 62 'AcousticPiano_C6' 84 13042 13276 80 16)
	(list 70 'AcousticPiano_F5' 77 12425 12965 40 14)
	(list 77 'AcousticPiano_Ds6' 87 12368 12869 20 10)
	(list 85 'AcousticPiano_Ds6' 87 12368 12869 0 8)
	(list 90 'AcousticPiano_Ds6' 87 12368 12869 0 6)
	(list 96 'AcousticPiano_D7' 98 7454 7606 0 3)
	(list 128 'AcousticPiano_D7' 98 7454 7606 0 2))
}

method pizzSamples SampledInstrument {
  return (list
	(list 38 'Pizz_G2' 43 8554 8782 0 5)
	(list 45 'Pizz_G2' 43 8554 8782 12 4)
	(list 56 'Pizz_A3' 57 11460 11659 0 4)
	(list 64 'Pizz_A3' 57 11460 11659 0 3.2)
	(list 72 'Pizz_E4' 64 17525 17592 0 2.8)
	(list 80 'Pizz_E4' 64 17525 17592 0 2.2)
	(list 128 'Pizz_E4' 64 17525 17592 0 1.5))
}

method saxSamples SampledInstrument {
  return (list
	(list 40 'TenorSax_C3' 48 8939 10794 0 0)
	(list 50 'TenorSax_C3' 48 8939 10794 0 0)	// [20 0 0)) used slower attack
	(list 59 'TenorSax_C3' 48 8939 10794 0 0)	// [40 0 0)) used slower attack
	(list 67 'AltoSax_A3' 57 8546 9049 0 0)
	(list 75 'AltoSax_A3' 57 8546 9049 0 0)		// [20 0 0)) used slower attack
	(list 80 'AltoSax_A3' 57 8546 9049 0 0)		// [20 0 0)) used slower attack
	(list 128 'AltoSax_C6' 84 1258 1848 0 0))
}

method steelDrumSamples SampledInstrument {
  return (list
	(list 128 'SteelDrum_D5' 74.4 -1 -1 0 2)) // unlooped
}

method stringSamples SampledInstrument { // too much bow chiff; slow attacks on low range
  return (list
	(list 41 'Cello_C2' 36 8548 8885 0 0)
	(list 52 'Cello_As2' 46 7465 7845 0 0)
	(list 62 'Violin_D4' 62 10608 11360 0 0)
	(list 75 'Violin_A4' 69 3111 3314 0 0)		// [70 0 0)) used slower attack
	(list 128 'Violin_E5' 76 2383 2484 0 0))
}

method vibraphoneSamples SampledInstrument {
  return (list
	(list 38 'Vibraphone_C3' 48 6202 6370 100 8)
	(list 48 'Vibraphone_C3' 48 6202 6370 100 7.5)
	(list 59 'Vibraphone_C3' 48 6202 6370 60 7)
	(list 70 'Vibraphone_C3' 48 6202 6370 40 6)
	(list 78 'Vibraphone_C3' 48 6202 6370 20 5)
	(list 86 'Vibraphone_C3' 48 6202 6370 0 3)
	(list 128 'Vibraphone_C3' 48 6202 6370 0 2))
}

method drumSamples SampledInstrument {
  // Return an array of drum specs that spans the MIDI key range 35-81.
  // Spec format for drums:
  //   <key> <sample file> <pitch shift in semitones> <loop start> <loop end> <decay>
  // Loop start/stop and decay are optional.

  return (array
	(list 35 'BassDrum' -9)
	(list 36 'BassDrum' 0)
	(list 37 'SideStick' 0)
	(list 38 'SnareDrum' 0)
	(list 39 'Clap' 0)
	(list 40 'SnareDrum' 2)
	(list 41 'Tom' -9 7260 7483 4)
	(list 42 'HiHatClosed' 0)
	(list 43 'Tom' -5 7260 7483 3.2)
	(list 44 'HiHatPedal' 0)
	(list 45 'Tom' 0 7260 7483 3)
	(list 46 'HiHatOpen' -8)
	(list 47 'Tom' 2 7260 7483 3)
	(list 48 'Tom' 7 7260 7483 2.7)
	(list 49 'Crash' -8)
	(list 50 'Tom' 10 7260 7483 2.7)
	(list 51 'HiHatOpen' -2) // ride cymbal 1
	(list 52 'Crash' -11) // chinese cymbal
	(list 53 'HiHatOpen' 2) // ride bell
	(list 54 'Tambourine' 0)
	(list 55 'Crash' 0 -1 -1 3.5) // splash cymbal
	(list 56 'Cowbell' 0)
	(list 57 'Crash' -8 -1 -1 3.5) // unlooped
	(list 58 'Vibraslap' -6)
	(list 59 'HiHatOpen' 2) // ride cymbal 2
	(list 60 'Bongo' 0)
	(list 61 'Bongo' 2)
	(list 62 'Conga' -5 4247 4499 0.2)
	(list 63 'Conga' -5 4247 4499 2)
	(list 64 'Conga' -12 4247 4499 6)
	(list 65 'Bongo' 15) // high timbale
	(list 66 'Bongo' 8) // low timbale
	(list 67 'Cowbell' 19) // high agogo
	(list 68 'Cowbell' 12) // low agogo
	(list 69 'Cabasa' 0)
	(list 70 'Maracas' 0)
	(list 71 'Cuica' 12) // short whistle
	(list 72 'Cuica' 5) // long whistle
	(list 73 'GuiroShort' 0)
	(list 74 'GuiroLong' 0)
	(list 75 'Claves' 0)
	(list 76 'WoodBlock' 0)
	(list 77 'WoodBlock' -4)
	(list 78 'Cuica' -5)
	(list 79 'Cuica' 0)
	(list 80 'Triangle' -6 16843 17255 0.4) // (mute triangle)
	(list 81 'Triangle' -6 16843 17255 6))
}
