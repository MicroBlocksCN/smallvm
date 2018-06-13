// WAVFile - Encode and decode sounds in the WAV file format

defineClass WAVFile stream

to readWAVFile fileName {
	data = (readFile fileName true)
	if (isNil data) { error 'File not found:' fileName }
	return (decodeWAV data)
}

to decodeWAV data { return (read (new 'WAVFile') data) }
to encodeWAV snd doCompress { return (write (new 'WAVFile') snd doCompress ) }

method read WAVFile data {
  // Return the sound encoded by the given WAV file data.

  stream = (dataStream data false)

  // read WAVE file header
  if ('RIFF' != (nextString stream 4)) { error 'WAVFile: bad file header' }
  totalSize = (nextUInt32 stream)
  if ((byteCount data) != (totalSize + 8)) { print 'WAVFile: bad RIFF size; ignoring' }
  if ('WAVE'!= (nextString stream 4)) { error 'WAVFile: not a WAVE file' }

  // read format chunk
  formatChunk = (extractChunk this 'fmt ')
  if (isNil formatChunk) { error 'WAVFile: No format chunk; not a WAVE file' }
  if ((byteCount formatChunk) < 16) { error 'WAVFile: format chunk is too small' }
  s = (dataStream formatChunk)
  encoding = (nextUInt16 s)
  channels = (nextUInt16 s)
  samplingRate = (nextUInt32 s)
  bytesPerSecond = (nextUInt32 s)
  blockAlignment = (nextUInt16 s)
  bitsPerSample = (nextUInt16 s)
  if ((remaining s) >= 4) { // extra info for ADPCM (encoding 17)
	skip s 2  // skip extra header byte count
	samplesPerBlock = (nextUInt16 s)
  }

  // extract the samples
  byteCount = (findChunk this 'data') // positions stream at start of data
  if (1 == encoding) { // uncompressed
	if (16 == bitsPerSample) {
	  sampleCount = (floor (byteCount / 2))
	  samples = (newArray sampleCount)
	  for i sampleCount {
		atPut samples i (nextInt16 stream)
	  }
	} (8 == bitsPerSample) {
	  sampleCount = byteCount
	  samples = (newArray sampleCount)
	  for i sampleCount {
		atPut samples i (nextInt8 stream)
	  }
	} else {
	   error 'WAVFile: can only handle 8-bit or 16-bit uncompressed PCM data'
	}
  } (17 == encoding) {
	if (1 != channels) { error 'WAVFile: ADPCM supports only one channel (monophonic)' }
	if (isNil samplesPerBlock) { error 'WAVFile: ADPCM format chunk is too small' }
	adpcmBlockSize = ((half (samplesPerBlock - 1)) + 4) // block size in bytes
	factChunk = (extractChunk this 'fact')
	if (and (notNil factChunk) (4 == (byteCount factChunk))) {
	  sampleCount = (nextUInt32 (dataStream factChunk false))
	} else {
	  // this should never happen, since there should always be a 'fact' chunk
	  sampleCount = (2 * byteCount)  // slight over-estimate; doesn't take ADPCM headers into account
	}
	// XXX decode ADPCM here...
  } else {
	 error (join 'WAVFile: unknown encoding' encoding)
  }

  return (newSound samples samplingRate (channels == 2))
}

method extractChunk WAVFile desiredType {
  // Return the contents of the first chunk of the given type or nil if not found.
  chunkSize = (findChunk this desiredType)
  if (isNil chunkSize) { return nil }
  return (nextData stream chunkSize)
}

method findChunk WAVFile desiredType {
  // Position the stream at start of the first chunk of the given type and return its size.
  // Return nil if the chunk is not found.
  setPosition stream 12
  while ((remaining stream) > 8) {
	chunkType = (nextString stream 4)
	chunkSize = (nextUInt32 stream)
	if (chunkType == desiredType) {
	  if (chunkSize > (remaining stream)) { return nil }
	  return chunkSize
	} else {
	  setPosition stream ((position stream) + chunkSize)
	}
  }
  return nil
}

method write WAVFile snd compressFlag {
  // Return a BinaryData object that encodes the given sound in WAV file format.

compressFlag = false // xxx

  formatChunkBytes = 16
  if compressFlag { formatChunkBytes += 4 }
  headerBytes = (formatChunkBytes + 20)
  totalBytes = ((2 * (count (samples snd))) + headerBytes)
  stream = (dataStream (newBinaryData totalBytes) false)

  // RIFF + WAVE header
  nextPutAll stream 'RIFF'
  putUInt32 stream totalBytes	// total size, excluding 8-byte RIFF header
  nextPutAll stream 'WAVE'

  // format chunk
  rate = (samplingRate snd)
  channels = 1
  if (isStereo snd) { channels = 2 }
  nextPutAll stream 'fmt '
  putUInt32 stream 16			// chunk size
  putUInt16 stream 1			// encoding; 1 = PCM
  putUInt16 stream channels		// channels
  putUInt32 stream rate			// samplesPerSecond
  if (isStereo snd) {
	putUInt32 stream (4 * rate)	// bytesPerSecond
	putUInt16 stream 4			// blockAlignment
  } else {
	putUInt32 stream (2 * rate)	// bytesPerSecond
	putUInt16 stream 2			// blockAlignment
  }
  putUInt16 stream 16			// bitsPerSample

  // data chunk
  samples = (samples snd)
  nextPutAll stream 'data'
  putUInt32 stream (2 * (count samples))	// chunk size (in bytes)
  for n samples {
	putUInt16 stream n
  }

  return (contents stream)
}

//-----------------------------------------------------------------------
// ADPCM Sound Compression (WAV file IMA/DVI format, 4-bits per sample)
//-----------------------------------------------------------------------

method stepTable WAVFile {
  return (array
	7 8 9 10 11 12 13 14 16 17 19 21 23 25 28 31 34 37 41 45
	50 55 60 66 73 80 88 97 107 118 130 143 157 173 190 209 230
	253 279 307 337 371 408 449 494 544 598 658 724 796 876 963
	1060 1166 1282 1411 1552 1707 1878 2066 2272 2499 2749 3024 3327
	3660 4026 4428 4871 5358 5894 6484 7132 7845 8630 9493 10442 11487
	12635 13899 15289 16818 18500 20350 22385 24623 27086 29794 32767)
}

method indexTable WAVFile {
  return (array
	-1 -1 -1 -1 2 4 6 8
	-1 -1 -1 -1 2 4 6 8)
}

method imaCompress WAVFile samples blockSize {
  // Compress monophonic sample data using the IMA ADPCM algorithm (4-bits/sample).

  if (isNil blockSize) { blockSize = 512 }
  stepTable = (stepTable this)
  indexTable = (indexTable this)
  index = 0
  savedNibble = -1	// -1 indicates that there is no saved nibble
  srcIndex = 1		// index of next sample to compress
  end = (count samples)

  // Round sample count up to an integral number of blocks
  samplesPerBlock = ((2 * (blockSize - 4)) + 1)
  blockCount = (floor (((count samples) + (samplesPerBlock - 1)) / samplesPerBlock))
  sampleCount = (samplesPerBlock * blockCount)
  out = (dataStream (newBinaryData (blockCount * blockSize)) false)

  repeat sampleCount {
	// get next sample
	if (srcIndex <= end) {
	  sample = (at samples srcIndex)
	  srcIndex += 1
	} else {
	  sample = 0
	}

	if (((position out) % blockSize) == 0) { // write the block header
	  putUInt16 out sample
	  putUInt8 out index
	  putUInt8 out 0
	  predicted = sample
	} else {
	  // compute the 4-bit code for this sample and the delta it encodes
	  diff = (sample - predicted)
	  step = (at stepTable (index + 1))
	  code = 0
	  delta = 0
	  if (diff < 0) { code = 8; diff = (- diff) } // negative difference
	  if (diff >= step) { code += 4; diff += (- step); delta += step }
	  step = (step >> 1)
	  if (diff >= step) { code += 2; diff += (- step); delta += step }
	  step = (step >> 1)
	  if (diff >= step) { code += 1; diff += (- step); delta += step }
	  delta += (step >> 1)

	  // output code (two codes per byte)
	  if (savedNibble < 0) {
		savedNibble = code
	  } else {
		putUInt8 out ((code << 4) | savedNibble)
		savedNibble = -1
	  }

	  // compute the predicted next sample
	  if ((code & 8) > 0) {
		predicted += (- delta)
	  } else {
		predicted += delta
	  }
	  if (predicted > 32767) { predicted = 32767 }
	  if (predicted < -32768) { predicted = -32768 }

	  // compute the next index
	  index += (at indexTable (code + 1))
	  if (index > 88) { index = 88 }
	  if (index < 0) { index = 0 }
	}
  }
  if (savedNibble >= 0) { putUInt8 out savedNibble }
  return (contents out)
}

method imaDecompress WAVFile compressedData blockSize {
  // Decompress sample data using the IMA ADPCM algorithm (one channel, 4-bits/sample).

  if (isNil blockSize) { blockSize = 512 }
  stepTable = (stepTable this)
  indexTable = (indexTable this)

  compressed = (dataStream compressedData false)
  index = 0
  lastByte = -1	// -1 indicates that there is no saved lastByte
  out = (list)

  while true {
	if (and (((position compressed) % blockSize) == 0) (lastByte < 0)) {	// read block header
	  if (atEnd compressed) { return (toArray out) }
	  sample = (nextInt16 compressed)
	  index = (nextUInt8 compressed)
	  if (index > 88) { index = 88 }
	  skip compressed 1		// skip extra header byte
	  add out sample
	} else {
	  // read 4-bit code and compute delta from previous sample
	  if (lastByte < 0) {
		if (atEnd compressed) { return (toArray out) }
		lastByte = (nextUInt8 compressed)
		code = (lastByte & 15)
	  } else {
		code = ((lastByte >> 4) & 15)
		lastByte = -1
	  }
	  step = (at stepTable (index + 1))
	  delta = 0
	  if ((code & 4) > 0) { delta += step }
	  if ((code & 2) > 0) { delta += (step >> 1) }
	  if ((code & 1) > 0) { delta += (step >> 2) }
	  delta += (step >> 3)

	  // compute next index
	  index += (at indexTable (code + 1))
	  if (index > 88) { index = 88 }
	  if (index < 0) { index = 0 }

	  // compute and output sample
	  if ((code & 8) > 0) {
		sample += (0 - delta)
	  } else {
		sample += delta
	  }
	  if (sample > 32767) { sample = 32767 }
	  if (sample < -32768) { sample = -32768 }
	  add out sample
	}
  }
  return (toArray out)
}
