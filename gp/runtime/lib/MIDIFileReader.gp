// MIDIFileReader.gp - Create a ScorePlayer from a MIDI file.

to playMidi fName instrName {
  play (playerForMIDIFile fName instrName)
}

to playerForMIDIFile fName instrName {
  // Return a player for the given MIDI file. If instrName is not nil,
  // play all voices on that instrument.

  if (not (endsWith fName '.mid')) { fName = (join fName '.mid') }
  if (not (contains (letters fName) '/')) { fName = (join (runtimeFolder 'midi/') fName) }
  midi = (decodeMIDI (new 'MIDIFileReader') (readFile fName true))

  defaultInstrName = instrName
  if (isNil defaultInstrName) { defaultInstrName = 'guitar' }
  player = (newScorePlayer (newSampledInstrument defaultInstrName))

  tracks = (tracks midi)
  for i (count tracks) {
	if (isNil instrName) {
	  addVoice player (at tracks i) (instrForTrack midi i)
	} else {
	  addVoice player (at tracks i) // use the instrument specified by caller
	}
  }
  for track (drumTracks midi) {
	addVoice player track (newSampledInstrument 'drums')
  }
  if (notNil (tempo midi)) {
	setTempo player (tempo midi)
  }
  return player
}

defineClass MIDIFileReader msecsPerTick tempo tracks trackPrograms drumTracks cmd

method tempo MIDIFileReader { return tempo }
method tracks MIDIFileReader { return tracks }
method drumTracks MIDIFileReader { return drumTracks }

method decodeMIDI MIDIFileReader data {
  tracks = (list)
  trackPrograms = (list)
  drumTracks = (list)
  stream = (dataStream data true)
  readHeaderChunk this stream
  while (not (atEnd stream)) {
	chunkType = (nextString stream 4)
	chunkSize = (nextUInt32 stream)
	if ('MTrk' == chunkType) {
	  trackData = (nextData stream chunkSize)
	  readTrack this (dataStream trackData true)
	} else {
	  print 'Skipping unexpected chunk type' chunkType
	  skip stream chunkSize
	}
  }
  return this
}

method instrForTrack MIDIFileReader trackIndex {
  instrName = 'guitar' // default
  if (trackIndex <= (count trackPrograms)) {
	p = (at trackPrograms trackIndex)
	if (p < 8) { instrName = 'guitar' // nicer than our current piano
	} (p == 12) { instrName = 'marimba'
	} (p < 16) { instrName = 'vibraphone'
	} (p < 24) { instrName = 'organ'
	} (p < 32) { instrName = 'guitar'
	} (p < 40) { instrName = 'bass'
	} (p < 48) { instrName = 'guitar' // nicer than current strings
	} (p < 56) { instrName = 'guitar' // nicer than current strings
	} (p < 64) { instrName = 'brass'
	} (p < 68) { instrName = 'sax'
	} (p < 71) { instrName = 'bassoon'
	} (p < 72) { instrName = 'clarinet'
	}
  }
  return (newSampledInstrument instrName)
}

method readHeaderChunk MIDIFileReader stream {
  chunkType = (nextString stream 4)
  chunkSize = (nextUInt32 stream)
  if (or ('MThd' != chunkType) (6 < chunkSize)) {
	error 'Bad MIDI header; not a MIDI file?'
  }
  format = (nextUInt16 stream)
  trackCount = (nextUInt16 stream)
  division = (nextUInt16 stream)
  if (format == 2) {
	print 'Format 2 MIDI file: tracks are independent'
  } (format > 2) {
	print 'Unknown MIDI file format:' format
  }
  if (division < 32768) {
	ticksPerBeat = division
  } else {
	print 'Ignoring SMTPE time unit'
	ticksPerBeat = 600
  }
  msecsPerTick = (600 / ticksPerBeat) // 100 beats/minute
}

method readTrack MIDIFileReader stream {
  events = (list)
  t = 0 // current time in beats
  program = nil
  isDrums = false
  cmd = nil // clear running status
  while (not (atEnd stream)) {
	deltaT = (readVarInt this stream)
	t += (deltaT * msecsPerTick)
	byte = (nextUInt8 stream)
	if (byte == 255) {
	  readMetaEvent this stream t
	} (isOneOf byte 240 247) {
	  // System exclusive messages in MIDI files appear to be extremely rare.
	  error 'MIDIFileReader does not yet handle system exclusive messages:' byte
	} (byte > 248) {
	  // real-time message; ignore
	} else {
	  evt = (readEvent this stream byte)
	  cmd = (first evt)
	  if (and (128 <= cmd) (cmd <= 159)) {
		// collect noteOn and noteOff events
		add events (array (round t) evt)
		if ((cmd & 15) == 9) { isDrums = true } // channel 9 is always drums
	  } (and (192 <= cmd) (cmd <= 207)) {
		if (isNil program) { program = (at evt 2) } // first program event determines track instrument
	  }
	}
  }
  noteList = (createNotes this events)
  if ((count noteList) > 0) {
	if isDrums {
	  add drumTracks noteList
	} else {
	  add tracks noteList
	  if (isNil program) { program = 0 }
	  add trackPrograms program
	}
  }
}

method readMetaEvent MIDIFileReader stream t {
  // Read and discard a meta event of the form: 255 <type> <len> <data bytes...>

  type = (nextUInt8 stream)
  len = (readVarInt this stream)
  if (and (1 <= type) (type <= 15)) {
	// meta event types 1-15 are reserved for string data
	printMetaInfo = false // make true to print string meta events
	if printMetaInfo {
	  print (nextString stream len)
	} else {
	  skip stream len
	}
  } else {
	if (and (81 == type) (isNil tempo)) { // extract tempo from the first tempo event
	  // Note: Some MIDI files contain many tempo changes. Later, these could
	  // be collected into a tempo change track for use by the ScorePlayer.
	  usecsPerBeat = (nextUInt8 stream)
	  usecsPerBeat = ((usecsPerBeat << 8) + (nextUInt8 stream))
	  usecsPerBeat = ((usecsPerBeat << 8) + (nextUInt8 stream))
	  tempo = (round (60000000 / usecsPerBeat))
	  skip stream -3
	}
	skip stream len
  }
}

method readEvent MIDIFileReader stream byte {
  // Return an array containing a MIDI command byte followed by one or two argument bytes.

  if (byte < 128) {
	if (notNil cmd) {
	  skip stream -1 // running status; use the last cmd and position stream to first arg byte
	} else { // should not happen in a well-formed MIDI file
	  print 'No previous command for running status; skipping to the next command byte'
	  while (and (byte < 128) ((remaining stream) > 0)) {
		byte = (nextUInt8 stream)
	  }
	  cmd = byte
	}
  } else {
	cmd = byte // start of a new command
  }
  type = ((cmd >> 4) & 15)
  if (or (type == 12) (type == 13)) { // one arg byte
	return (array cmd (nextUInt8 stream))
  } (type < 15) { // two arg bytes
	return (array cmd (nextUInt8 stream) (nextUInt8 stream))
  }
  error 'Unexpected command byte:' cmd
}

method readVarInt MIDIFileReader stream {
  // Read a variable-length unsigned integer. Each byte has seven bits of the result.
  // If the most significant bit is set, then additional byte(s) follow. The maximum
  // number of bytes is four, resulting in a 28-bit integer.

  result = 0
  repeat 4 { // at most four bytes
	byte = (nextUInt8 stream)
	result = ((result << 7) + (byte & 127))
	if (byte < 128) { return result }
  }
  return result
}

method createNotes MIDIFileReader cmdList {
  // Convert a list of MIDI commands into a sequence of Note objects.

  soundingNotes = (list)
  result = (list)
  for pair cmdList {
	t = (first pair)
	evt = (last pair)
	cmd = ((first evt) & 240)
	key = (at evt 2)
	vel = (at evt 3)
	if (and (144 == cmd) (vel > 0)) { // noteOn
	  note = (newScoreNote t key vel 123) // 123 is a placeholder; the actual duration is set later
	  add soundingNotes note
	  add result note
	} (or (128 == cmd) (and (144 == cmd) (vel == 0))) { // noteOff
	  note = (findNoteForKey this soundingNotes key)
	  if (notNil note) {
		dur = (max 1 (t - (startTime note)))
		setDuration note dur
		remove soundingNotes note
	  }
	} else {
	  print 'Unexpected cmd in createNotes:' cmd
	}
  }
  return result
}

method findNoteForKey MIDIFileReader soundingNotes key {
  for n soundingNotes {
	if (key == (key n)) { return n }
  }
  return nil
}
