defineClass PNGWriter bitmap dataStream

to encodePNG aBitmap pixelsPerInch { return (writeImage (new 'PNGWriter') aBitmap pixelsPerInch) }

method writeImage PNGWriter aBitmap pixelsPerInch {
  bitmap = aBitmap
  dataStream = (dataStream (newBinaryData ((width bitmap) * (height bitmap))) true)

  writeSignature this
  writeChunk this 'IHDR' (headerChunk this)
  if (notNil pixelsPerInch) { writeChunk this 'pHYs' (physChunk this pixelsPerInch) }
  writeChunk this 'IDAT' (dataChunk this)
  writeChunk this 'IEND' (newBinaryData 0)

  return (contents dataStream)
}

method writeSignature PNGWriter {
  pngSignature = (toBinaryData (array 137 80 78 71 13 10 26 10))
  nextPutAll dataStream pngSignature
}

method writeChunk PNGWriter chunkID data {
  length = (byteCount data)
  crc = (crc data false (crc chunkID))
  putUInt32 dataStream length
  nextPutAll dataStream chunkID
  nextPutAll dataStream data
  putUInt32 dataStream crc
}

method headerChunk PNGWriter {
  chunk = (dataStream (newBinaryData 20) true)
  putUInt32 chunk (width bitmap)
  putUInt32 chunk (height bitmap)
  putUInt8 chunk 8 // bitsPerChannel
  putUInt8 chunk 6 // colorType
  putUInt8 chunk 0 // compression
  putUInt8 chunk 0 // filter method
  putUInt8 chunk 0 // interface method
  return (contents chunk)
}

method physChunk PNGWriter pixelsPerInch {
  inchesPerMeter = 39.3700787
  pixelsPerMeter = (round (pixelsPerInch * inchesPerMeter))
  chunk = (dataStream (newBinaryData 20) true)
  putUInt32 chunk pixelsPerMeter
  putUInt32 chunk pixelsPerMeter
  putUInt8 chunk 1 // unit is meters
  return (contents chunk)
}

method dataChunk PNGWriter {
  width = (width bitmap)
  height = (height bitmap)
  pixels = (getField bitmap 'pixelData')
  widthBytes = (width * 4)
  scanLineBytes = (widthBytes + 1)
  dst = (newBinaryData (height * scanLineBytes))
  for yy height {
	y = (yy - 1)
	offset = ((y * scanLineBytes) + 2)
	replaceByteRange dst offset ((offset + widthBytes) - 1) pixels ((y * widthBytes) + 1)
	for x width {
	  tmp = (byteAt dst offset)
	  byteAtPut dst offset (byteAt dst (offset + 2))
	  byteAtPut dst (offset + 2) tmp
	  offset += 4
	}
  }
  compressed = (zlibEncode dst)
  return compressed
}
