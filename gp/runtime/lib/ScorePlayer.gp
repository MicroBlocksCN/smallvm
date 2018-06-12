// ScorePlayer.gp
// A ScorePlayer plays one or more voices on a synthesized instrument.
// Each voice is a sequence of ScoreNotes.

defineClass ScoreNote startTime key velocity duration

method key ScoreNote { return key }
method velocity ScoreNote { return velocity }
method duration ScoreNote { return duration }
method startTime ScoreNote { return startTime }
method endTime ScoreNote { return (startTime + duration) }

method setKey ScoreNote k { key = k }
method setStartTime ScoreNote t { startTime = t }
method setDuration ScoreNote dur { duration = dur }

to newScoreNote t key vel dur {
  return (new 'ScoreNote' t key vel dur)
}

defineClass ScorePlayer defaultInstrument instruments voices isMuted voiceIndex speed msecsPerBeat startTime prevTime endTime

method instruments ScorePlayer { return instruments }
method trackCount ScorePlayer { return (count voices) }
method voices ScorePlayer { return voices }
method tempo ScorePlayer { return (round (100 * speed)) }

method setTempo ScorePlayer beatsPerMinute {
  speed = (beatsPerMinute / 100)
  msecsPerBeat = (round (60000 / beatsPerMinute))
}

to newScorePlayer defaultInstrument beatsPerMinute {
   return (initialize (new 'ScorePlayer') defaultInstrument beatsPerMinute)
}

method initialize ScorePlayer defaultInstr beatsPerMinute {
  if (isNil defaultInstr) { defaultInstr = (newSampledInstrument 'guitar') }
  if (isNil beatsPerMinute) { beatsPerMinute = 100 }
  defaultInstrument = defaultInstr
  instruments = (list)
  voices = (list)
  isMuted = (list)
  voiceIndex = (list)
  setTempo this beatsPerMinute
  startTime = 0
  return this
}

method addVoice ScorePlayer v instr {
  // Add a voice (a list of ScoreNotes) to the score.
  add voices v
  if (isNil instr) {
	add instruments defaultInstrument
  } else {
	add instruments instr
  }
  add isMuted false
}

method instrumentForTrack ScorePlayer n {
  n = (toInteger n)
  if (or (n < 1) (n > (count instruments))) { return }
  return (instrumentName (at instruments n))
}

method setInstrumentForTrack ScorePlayer n instrName {
  n = (toInteger n)
  if (or (n < 1) (n > (count instruments))) { return }
  atPut instruments n (newSampledInstrument instrName)
}

method isTrackMuted ScorePlayer n {
  n = (toInteger n)
  if (or (n < 1) (n > (count isMuted))) { return }
  return (at isMuted n)
}

method setTrackMuted ScorePlayer n bool {
  n = (toInteger n)
  if (or (n < 1) (n > (count isMuted))) { return }
  return (atPut isMuted n (true == bool))
}

method notesForTrack ScorePlayer n {
  n = (toInteger n)
  if (or (n < 1) (n > (count voices))) { return (list) }
  return (at voices n)
}

method scoreTime ScorePlayer {
  mixer = (getMixer)
  fudgeFactor = (700 * ((count (getField mixer 'buffer')) / 4096))
  if (not (isPlaying mixer this)) { return 0 }
  approximateTime = (speed * (((estimatedMSecs mixer) - startTime) - fudgeFactor))
  return (max 0 (round approximateTime))
}

method playScore ScorePlayer {
  mixer = (getMixer)
  step mixer // ensure mixer is running
  voiceIndex = (newArray (count voices) 1)
  startTime = (msecs mixer)

  // set the start time to be the first multiple of msecsPerBeat after nextBufferTime
  nextBufferTime = (nextMSecs mixer)
  startTime = ((ceiling (nextBufferTime / msecsPerBeat)) * msecsPerBeat)

  prevTime = 0
  endTime = 0 // computed dynamically
  addSound mixer this

  if (notNil (global 'page')) {
	while (isPlaying mixer this) {
	  waitMSecs 10
	}
  } else {  // running in the command prompt
	while (hasPlayingSounds mixer) {
	  step mixer
	  waitMSecs 10
	}
  }
}

// sample generation (mixer API)

method sound ScorePlayer { return this }

method isDone ScorePlayer {
  for v (count voices) {
    if ((at voiceIndex v) <= (count (at voices v))) { return false }
  }
  mixer = (getMixer)
  t = ((msecs mixer) - startTime)
  return (t >= endTime)
}

method mixIntoBuffer ScorePlayer buffer {
  // Start new notes.
  mixer = (getMixer)
  t = (round (speed * ((msecs mixer) - startTime)))
  bufferMSecs = (round (2 * ((count buffer) / 22.05)))
  for v (count voices) {
	voice = (at voices v)
	instr = (at instruments v)
	voiceEnd = (count voice)
	i = (at voiceIndex v)
	while (and (i <= voiceEnd) ((startTime (at voice i)) < t)) {
	  evt = (at voice i)
	  // endTime determines how long the ScorePlayer waits after submitting the last note to the mixer
	  // make this a buffer plus a beat shorter than the last note duration to allow the next
	  // block to start a ScorePlayer that begins on the next beat boundary.
	  endTime = (max endTime ((t + (duration evt)) - (bufferMSecs + msecsPerBeat))) // xxx adjust for speed
	  delaySamples = (round (22.05 * ((startTime evt) - prevTime)))
	  delaySamples = (round (delaySamples / speed))
	  keyOrChord = (key evt)
	  if (not (at isMuted v)) {
		if (isAnyClass keyOrChord 'Array' 'List') {
		  for pair keyOrChord {
			k = (first pair)
			if (k > 0) {
			  dur = (floor ((last pair) / speed))
			  note = (notePlayer instr k dur (velocity evt))
			  setStartDelay note delaySamples
			  mixIntoBuffer note buffer
			  addSound mixer note
			}
		  }
		} (keyOrChord > 0) { // single note (not a chord and not a rest)
		  dur = (floor ((duration evt) / speed))
		  note = (notePlayer instr keyOrChord dur (velocity evt))
		  setStartDelay note delaySamples
		  mixIntoBuffer note buffer
		  addSound mixer note
		}
	  }
	  i += 1
	}
	atPut voiceIndex v i
  }
  prevTime = t
}

method totalScoreTime ScorePlayer {
  // Return the total score time in seconds.
  totalTime = 0
  for v voices {
	for evt v {
	  if ((endTime evt) > totalTime) { totalTime = (endTime evt) }
	}
  }
  return (totalTime / (1000.0 * speed))
}

method generateAllSamples ScorePlayer keepFlag {
  // Generate all the samples for this score. Used for performance testing.
  // If keepFlag is true, return a list of buffers containing the generated sound.

  if (isNil keepFlag) { keepFlag = false }
  voiceIndex = (newArray (count voices) 1)
  buffer = (newArray 200 0)
  scoreTime = 0
  playingNotes = (list)
  isPlaying = true
  if keepFlag { result = (list) }

  while (or isPlaying ((count playingNotes) > 0)) {
	isPlaying = false
	for v (count voices) {
	  voice = (at voices v)
	  instr = (at instruments v)
	  voiceEnd = (count voice)
	  i = (at voiceIndex v)
	  if (i <= voiceEnd) { isPlaying = true }
	  while (and (i <= voiceEnd) ((startTime (at voice i)) < scoreTime)) {
		evt = (at voice i)
		keyOrChord = (key evt)
		if (not (at isMuted v)) {
		  if (isAnyClass keyOrChord 'Array' 'List') {
			for pair keyOrChord {
			  k = (first pair)
			  if (k > 0) {
				dur = (floor ((last pair) / speed))
				note = (notePlayer instr k dur (velocity evt))
				setStartDelay note 0
				add playingNotes note
			  }
			}
		  } (keyOrChord > 0) { // single note (not a chord and not a rest)
			dur = (floor ((duration evt) / speed))
			note = (notePlayer instr keyOrChord dur (velocity evt))
			setStartDelay note 0
			add playingNotes note
		  }
		}
		i += 1
	  }
	  atPut voiceIndex v i
	}
	for n (copy playingNotes) {
	  mixIntoBuffer n buffer
	  if (isDone n) { remove playingNotes n }
	}
	if keepFlag {
	  add result buffer
	  buffer = (newArray (count buffer) 0)
	}
	scoreTime += (round (speed * ((count buffer) / 22.050)))
  }
  if keepFlag {
	allSamples = (callWith 'join' (toArray result))
	return (newSound allSamples 22050 false)
  }
}
