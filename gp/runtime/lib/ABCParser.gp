// ABCParser.gp - Convert a string in ABC notation to a list of notes.
//
// To do:
//	- parse and apply key signature (e.g. K:Bmin)
//	- test case: http://abcnotation.com/tunePage?a=trillian.mit.edu/~jc/music/abc/mirror/mandozine.com/La_Partida/0000
//
// Pitch:
//   optional: _^=
//   letter (upper or lower)
//   optional: ,'
//
// Chord:
//   set of pitches inside []
//   (optional chord duration follows the closing square bracket)
//
// Duration:
//   <digits>
//   /
//   <digits>
//   (all parts optional)
//
//  Example: playABC 'ABcde/d/c/B/A2'
//  Example: playABC 'C,,C,Ccc''c'''''
//  Example: playABC '[ceg][Acf][Bdg][ceg]2'

defineClass ABCParser noteNames keysigAdjustment input next notes

to playABC s instr beatsPerMinute transposition {
  if (isNil instr) { instr = 'piano' }
  if (isNil beatsPerMinute) { beatsPerMinute = 120 }
  if (isClass instr 'String') {
	instrument = (newSampledInstrument instr)
  } (isClass instr 'Array') {
	instrument = (sampledInstrumentFromSamples instr)
  } else {
	return nil
  }
  scorePlayer = (newScorePlayer instrument beatsPerMinute)
  voice = (parse (new 'ABCParser') s)
  if (notNil transposition) { transpose (new 'ABCParser') voice transposition }
  addVoice scorePlayer voice
  playScore scorePlayer
  return scorePlayer
}

method parse ABCParser s {
  noteNames = (letters 'C D EF G A Bc d ef g a b')
  keysigAdjustment = (newArray 12 0)
  input = (withoutWhitespace this s)
  next = 1
  notes = (list)
  while (next <= (count input)) {
	readNextEvent this
  }
  convertBeatsToMSecs this
  return notes
}

method convertBeatsToMSecs ABCParser {
  // Convert durations from beats to milliseconds and set note start starting times.
  msecsPerBeat = 600
  t = 0
  for n notes {
	msecs = (truncate ((duration n) * msecsPerBeat))
	setDuration n msecs
	if (isAnyClass (key n) 'Array' 'List') {
	  for pair (key n) {
		atPut pair 2 (truncate ((last pair) * msecsPerBeat))
	  }
	}
	setStartTime n t
	t += msecs
  }
}

method transpose ABCParser noteList transposition {
  for n noteList {
	noteOrChord = (key n)
	if (isAnyClass noteOrChord 'List' 'Array') {
	  for pair noteOrChord {
		k = (first pair)
		if (k > 0) {
		  atPut pair 1 (clamp (k + transposition) 1 127)
		}
	  }
	} else {
	  setKey n (clamp (noteOrChord + transposition) 1 127)
	}
  }
}

method withoutWhitespace ABCParser s {
  letters = (list)
  for line (lines s) {
	lineLetters = (letters line)
	if (and ((count lineLetters) > 1) (':' == (at lineLetters 2))) {
	  if ('K' == (at lineLetters 1)) {
		keysig = (list)
		for ch (letters (substring line 3)) {
		  if (ch > ' ') { add keysig ch }
		}
		setKeysignature this (toLowerCase (joinStrings keysig))
	  }
	} else {
	  i = (indexOf lineLetters '%')
	  if (notNil i) { lineLetters = (copyFromTo lineLetters 1 (i - 1)) }
	  addAll letters lineLetters
	}
  }
  result = (list)
  for ch letters {
	// remove whitespace and ABC barlines, repeat signs, ties, and slurs
	if (and (ch > ' ') (not (isOneOf ch '|' ':' '-' '(' ')' '\' '>'))) { add result ch }
  }
  return (toArray result)
}

method setKeysignature ABCParser keysig {
  scale = (array 'c' 'd' 'e' 'f' 'g' 'a' 'b')
  scaleDegree = (indexOf scale (at keysig 1)) // 1-8
  if (and ((count keysig) > 1) ('b' == (at keysig 2))) {
	useFlats = true
  } else {
	useFlats = false
  }
  isMinor = (or (endsWith keysig 'min') (endsWith keysig 'm'))
  if isMinor {
	scaleDegree += 2 // use the key signature of relative major
	if (scaleDegree > 7) { scaleDegree += -7 }
	useFlats = ('#' != (at keysig 2))
  }
  if useFlats {
	keysigTable = (array
	  (array -1  0 -1  0 -1 -1  0 -1  0 -1  0 -1)  // Cb
	  (array  0  0 -1  0 -1  0  0 -1  0 -1  0 -1)  // Db
	  (array  0  0  0  0 -1  0  0  0  0 -1  0 -1)  // Eb
	  (array  0  0  0  0  0  0  0  0  0  0  0 -1)  // F
	  (array -1  0 -1  0 -1  0  0 -1  0 -1  0 -1)  // Gb
	  (array  0  0 -1  0 -1  0  0  0  0 -1  0 -1)  // Ab
	  (array  0  0  0  0 -1  0  0  0  0  0  0 -1)) // Bb
  } else {
	keysigTable = (array
	  (array  0  0  0  0  0  0  0  0  0  0  0  0)  // C
	  (array  1  0  0  0  0  1  0  0  0  0  0  0)  // D
	  (array  1  0  1  0  0  1  0  1  0  0  0  0)  // E
	  (array  1  0  1  0  1  1  0  1  0  1  0  0)  // F#
	  (array  0  0  0  0  0  1  0  0  0  0  0  0)  // G
	  (array  1  0  0  0  0  1  0  1  0  0  0  0)  // A
	  (array  1  0  1  0  0  1  0  1  0  1  0  0)) // B
  }
  keysigAdjustment = (at keysigTable scaleDegree)
}

method readNextEvent ABCParser {
  while ('"' == (peek this)) { // skip comment/chord
	next += 1
	while (and (not (atEnd this)) ('"' != (peek this))) { next += 1 }
	next += 1
  }
  if ('[' == (peek this)) {
	chord = (readChord this)
	ch = (peek this)
	if (or (isDigit ch) ('/' == ch)) {
	  chordDur = (readDuration this)
	  for pitchAndDur chord { // multiply all note durations by chordDur
		atPut pitchAndDur 2 (chordDur * (last pitchAndDur))
	  }
	}
	if ((count chord) > 0) {
	  chordDur = (last (first chord))
	  for pitchAndDur chord {
		chordDur = (min chordDur (last pitchAndDur))
	  }
	  add notes (newScoreNote 0 chord 127 chordDur)
	}
  } else {
	p = (readPitch this)
	dur = (readDuration this)
	add notes (newScoreNote 0 p 127 dur)
  }
}

method readChord ABCParser {
  chord = (list)
  next += 1 // initial '['
  while (not (isOneOf (peek this) ']' '')) {
	p = (readPitch this)
	dur = (readDuration this)
	add chord (array p dur)
  }
  next += 1 // final ']'
  return chord
}

method readPitch ABCParser {
  // Return the midi key number (middle C = 60) for this note.
  // Return zero for a rest (z or Z).
  pitch = 0
  ch = (nextLetter this)
  if (isOneOf ch 'Z' 'z') { return 0 } // rest
  hasNatural = false
  while (isOneOf ch '^' '_' '=') {
	if ('^' == ch) { pitch += 1 }
	if ('_' == ch) { pitch += -1 }
	if ('=' == ch) { pitch = 0; hasNatural = true }
	ch = (nextLetter this)
  }
  if (isNoteName this ch) {
	k = (indexOf noteNames ch)
	if (not hasNatural) {
	  k = (adjustForKeySigniture this k)
	}
	pitch += (59 + k)
  } else {
	findNextNote this // recovery: skip bad note
	return 0 // rest
  }
  ch = (peek this)
  while (isOneOf ch ',' '''') {
	if (',' == ch) { pitch += -12 }
	if ('''' == ch) { pitch += 12 }
	next += 1
	ch = (peek this)
  }
  return pitch
}

method adjustForKeySigniture ABCParser k {
  i = (((k - 1) % 12) + 1)
  return (k + (at keysigAdjustment i))
}

method readDuration ABCParser {
  dur = (max 1 (readInteger this))
  if ('/' == (peek this)) {
	next += 1
	if (isDigit (peek this)) {
	  dur = (dur / (readInteger this))
	} else {
	  dur = (dur / 2)
	}
  }
  return dur
}

method readInteger ABCParser {
  digits = ''
  while (isDigit (peek this)) {
	digits = (join digits (nextLetter this))
  }
  return (toInteger digits)
}

method findNextNote ABCParser {
  // Skip to the start of the next note (or end) to recover from an error.
  while true {
	ch = (peek this)
	if (or
		(atEnd this)
		(isOneOf ch '_' '^' '=' 'z' 'Z')
		(isNoteName this ch)) {
			return
	}
	next += 1
  }
}

method isNoteName ABCParser ch {
  return (or
	(and ('a' <= ch) (ch <= 'g'))
	(and ('A' <= ch) (ch <= 'G')))
}

//*** stream helper methods ***

method atEnd ABCParser { return (next > (count input)) }

method peek ABCParser {
  if (next > (count input)) { return '' }
  return (at input next)
}

method nextLetter ABCParser {
  if (atEnd this) { return '' }
  next += 1
  return (at input (next - 1))
}
