defineClass PNGReader data allDataChunk unknownChunks colorType interlaceMethod bitmap width height depth palette transparency backColor bitsPerPixel bitsPerChannel bytesPerScanline BPP BlockWidth BlockHeight

method init PNGReader {
  BPP = (array (array 1 2 4 8 16)
               (array 0 0 0 0 0)
               (array 0 0 0 24 48)
               (array 1 2 4 8 0)
               (array 0 0 0 16 32)
               (array 0 0 0 0 0)
               (array 0 0 0 32 64)
               (array 0 0 0 0 0))
  BlockWidth = (array 8 4 4 2 2 1 1)
  BlockHeight = (array 8 8 4 4 2 2 1)
  depth = 32
}

method readFrom PNGReader d {
  init this
  data = (dataStream d true)
  unknownChunks = (list)
  sig = (toArray (nextData data 8))
  if (sig != (array 137 80 78 71 13 10 26 10)) {
	error 'Bad PNG file signature'
  }
  while (not (atEnd data)) {
    processNextChunk this
  }
  if ((count unknownChunks) > 0) {
//    print 'unknownChunks' unknownChunks
  }
  if (interlaceMethod == 0) {
     processNonInterlaced this allDataChunk
  } else {
     processInterlaced this allDataChunk
  }
  return bitmap
}

method processNextChunk PNGReader {
  length = (nextUInt32 data)
  chunkType = (nextString data 4)
  chunk = (nextData data length)
  chunkCrc = (nextUInt32 data)
  crc = (crc chunk false (crc chunkType))
  if (crc != chunkCrc) {
	error (join 'PNGReader crc error in chunk ' chunkType)
  }

  if (chunkType == 'IHDR') {
    processIHDRChunk this chunk
  } (chunkType == 'IEND') {
    return // *should* be the last chunk
  } (chunkType == 'PLTE') {
    processPLTEChunk this chunk
  } (chunkType == 'tRNS') {
    processTransparencyChunk this chunk
  } (chunkType == 'tEXt') {
    processTextChunk this chunk
  } (chunkType == 'iTXt') {
    processITextChunk this chunk
  } (chunkType == 'zTXt') {
    processZTextChunk this chunk
  } (chunkType == 'bKGD') {
    processBackgroundChunk this chunk
  } (chunkType == 'IDAT') {
    if (isNil allDataChunk) {
      allDataChunk = chunk
    } else {
      newChunk = (newBinaryData ((byteCount allDataChunk) + (byteCount chunk)))
      replaceByteRange newChunk 1 (byteCount allDataChunk) allDataChunk 1
      replaceByteRange newChunk ((byteCount allDataChunk) + 1) (byteCount newChunk) chunk 1
      allDataChunk = newChunk
    }
  } (chunkType == 'pHYs') {
    nop
  } (chunkType == 'iCCP') {
	nop
  } (chunkType == 'gAMA') {
    nop
  } (chunkType == 'sBIT') {
    nop
  } (chunkType == 'hIST') {
    nop
  } (chunkType == 'tIME') {
    nop
  } (chunkType == 'cHRM') {
    nop
  } (chunkType == 'sPLT') {
    nop
  } else {
    add unknownChunks chunkType
  }
}

method processIHDRChunk PNGReader chunk {
  s = (dataStream chunk true)
  width = (nextUInt32 s)
  height = (nextUInt32 s)
  bitsPerChannel = (nextUInt8 s)
  colorType = (nextUInt8 s)

  compression     = (nextUInt8 s)
  if (compression != 0) {error 'unsupported compression scheme'}
  filterMethod    = (nextUInt8 s)
  if (filterMethod != 0) {error 'unsupported compression scheme'}
  interlaceMethod = (nextUInt8 s)

  if (colorType == 0) { // grayscale
    palette = (grayColorsFor this bitsPerChannel)
  }
  bitsPerPixel = (at (at BPP (colorType + 1)) (highBit bitsPerChannel))
  bytesPerScanline = (truncate (((width * bitsPerPixel) + 7) / 8))
}

method grayColorsFor PNGReader d {
  // return a color table for a gray image

  palette = (newArray (1 << d))
  if (d == 1) {
    atPut palette 1 (color 0 0 0)
    atPut palette 2 (color 255 255 255)
  } (d == 2) {
    atPut palette 1 (color 0 0 0)
    atPut palette 2 (color 85 85 85)
    atPut palette 3 (color 170 170 170)
    atPut palette 4 (color 255 255 255)
  } (d == 4) {
    for i 16 {
      g = (i - 1)
      v = (truncate ((g * 255) / 15))
      atPut palette i (color v v v)
    }
  } (or (d == 8) (d == 16)) {
    for i 256 {
      v = (i - 1)
      atPut palette i (color v v v)
    }
  }
}

method processPLTEChunk PNGReader chunk {
  if (((byteCount chunk) % 3) != 0) {error 'wrong size palatte detected'}
  colorCount = (truncate ((byteCount chunk) / 3))
  palette = (newArray colorCount)
  for cc colorCount {
    index = (cc - 1)
    i = ((index * 3) + 1)
    atPut palette cc (color (byteAt chunk i) (byteAt chunk (i + 1)) (byteAt chunk (i + 2)))
  }
}

method processTransparencyChunk PNGReader chunk {
  s = (dataStream chunk true)
  if (colorType == 0) {
    transparency = (nextUInt16 s)
    transparency = (transparency & ((1 << bitsPerChannel) - 1))
  } (colorType == 2) {
    red = (nextUInt16 s)
    green = (nextUInt16 s)
    blue = (nextUInt16 s)
    red = (red & ((1 << bitsPerChannel) - 1))
    green = (green & ((1 << bitsPerChannel) - 1))
    blue = (blue & ((1 << bitsPerChannel) - 1))
    transparency = (array red green blue)
  } (colorType == 3) {
    index = 1
    while (not (atEnd s)) {
      alpha = (nextUInt8 s)
      c = (at palette index)
      atPut palette index (color (red c) (green c) (blue c) alpha)
      index += 1
    }
  }
}

method processBackgroundChunk PNGReader chunk {
  s = (dataStream chunk true)
  if (colorType == 3) {
    backColor = (at palette ((byteAt chunk 1) + 1))
    return
  }
  max = ((1 << bitsPerChannel) - 1)
  if (or (colorType == 0) (colorType == 4)) {
    val = (truncate (((nextUInt16 s) * 255) / max))
    backColor = (color val val val)
    return
  }
  if (or (colorType == 2) (colorType == 6)) {
    red = ((nextUInt16 s) * 255)
    green = ((nextUInt16 s) * 255)
    blue = ((nextUInt16 s) * 255)
    backColor = (color (red / max) (green / max) (blue / max))
  }
}

method processTextChunk PNGReader chunk {
  // TODO: Convert latin-1 to Unicode
  s = (dataStream chunk true)
  key = (nextNullTerminatedString s)
  val = (nextNullTerminatedString s)
  ignore s key val
}

method processITextChunk PNGReader chunk {
  s = (dataStream chunk true)
  key = (nextNullTerminatedString s)
  compressionFlag = (nextUInt8 s)
  compressionMethod = (nextUInt8 s)
  lang = (nextNullTerminatedString s)
  trans = (nextNullTerminatedString s)
  val = (nextNullTerminatedString s)
  if (compressionFlag != 0) {
	val = (zlibDecode (toBinaryData val))
  }
  ignore key compressionMethod lang trans
}

method processZTextChunk PNGReader chunk {
  s = (dataStream chunk true)
  key = (nextNullTerminatedString s)
  compressionMethod = (nextUInt8 s)
  byteCount = ((byteCount chunk) - (position s))
  compressed = (nextData s byteCount)
  val = (zlibDecode compressed true)
  ignore key compressionMethod val
}

method processNonInterlaced PNGReader chunk {
  copyMethods = (array 'copyPixelsGray' nil 'copyPixelsRGB' 'copyPixelsIndexed' 'copyPixelsGrayAlpha' nil 'copyPixelsRGBA')
  copyMethod = (at copyMethods (colorType + 1))
  bitmap = (newBitmap width height)
  strm = (dataStream (zlibDecode chunk) false)
  prevScanline = (newBinaryData bytesPerScanline)
  for y height {
    filter = (nextUInt8 strm)
    thisScanline = (nextData strm bytesPerScanline)
    if (filter > 0) { filterScanline this thisScanline prevScanline filter bytesPerScanline }
    call copyMethod this (y - 1) thisScanline 0 1
    prevScanline = thisScanline
  }
  if (not (atEnd strm)) {error 'Unexpected data'}
}

method processInterlaced PNGReader chunk {
  startingCol =  (array 0 4 0 2 0 1 0)
  colIncrement = (array 8 8 4 4 2 2 1)
  rowIncrement = (array 8 8 8 4 4 2 2)
  startingRow =  (array 0 0 4 0 2 0 1)
  copyMethods = (array 'copyPixelsGray' nil 'copyPixelsRGB' 'copyPixelsIndexed' 'copyPixelsGrayAlpha' nil 'copyPixelsRGBA')
  copyMethod = (at copyMethods (colorType + 1))
  bitmap = (newBitmap width height)
  strm = (dataStream (zlibDecode chunk) false)
  prevScanline = (newBinaryData bytesPerScanline)

  for pass 7 {
    if (doPass this pass) {
      cx = (at colIncrement pass)
      sc = (at startingCol pass)
      bytesPerPass = (truncate ((((truncate ((((width - sc) + cx) - 1) / cx)) * bitsPerPixel) + 7) / 8))
      y = (at startingRow pass)
      while (y <= (height - 1)) {
        filter = (nextUInt8 strm)
		thisScanline = (nextData strm bytesPerPass)
        if (filter > 0) { filterScanline this thisScanline prevScanline filter bytesPerPass }
        call copyMethod this y thisScanline sc cx
        prevScanline = thisScanline
        y += (at rowIncrement pass)
      }
    }
  }
  if (not (atEnd strm)) {error 'Unexpected data'}
}

method doPass PNGReader pass {
  if (pass == 1) {return true}
  if (and (width == 1) (height == 1)) {return false}
  if (pass == 2) {return (width >= 5)}
  if (pass == 3) {return (height >= 5)}
  if (pass == 4) {return (or (width >= 3) (height >= 5))}
  if (pass == 5) {return (height >= 3)}
  if (pass == 6) {return (width >= 2)}
  if (pass == 7) {return (height >= 2)}
}

method copyPixelsGray PNGReader y thisScanline startX incX {
  // Handle grayscale color mode (colorType = 0)
  s = (dataStream thisScanline true)
  if (bitsPerChannel == 16) {
    x = startX
    while (not (atEnd s)) {
      d = (nextUInt16 s)
      v = ((truncate ((d * 255) / 65535)) & 255)
      if (transparency == d) {
        v = 0
        a = 0
      } else {
        a = 255
      }
      setRGBA bitmap x y v v v a
      x += incX
      if (x >= width) {return}
    }
   return
  }
  if (or (bitsPerChannel == 8) (bitsPerChannel == 4) (bitsPerChannel == 2) (bitsPerChannel == 1)) {
    x = startX
    mask = ((1 << bitsPerChannel) - 1)
    while (not (atEnd s)) {
      d = (nextUInt8 s)
      for i (8 / bitsPerChannel) {
        v = ((d >> (((8 / bitsPerChannel) - i) * bitsPerChannel)) & mask)
        if (transparency == v) {
          v = 0
          a = 0
        } else {
          v = ((v * 255) / mask)
          a = 255
        }
        setRGBA bitmap x y v v v a
        x += incX
        if (x >= width) {return}
      }
    }
  }
}

method copyPixelsRGB PNGReader y thisScanline startX incX {
  // Handle RGB color mode (colorType = 2)
  s = (dataStream thisScanline true)
  if (bitsPerChannel == 16) {
    x = startX
    while (not (atEnd s)) {
      r = (nextUInt16 s)
      g = (nextUInt16 s)
      b = (nextUInt16 s)
      if (and (notNil transparency)
              ((at transparency 1) == r)
              ((at transparency 2) == g)
              ((at transparency 3) == b)) {
        r = 0
        g = 0
        b = 0
        a = 0
      } else {
        r = ((truncate ((r * 255) / 65535)) & 255)
        g = ((truncate ((g * 255) / 65535)) & 255)
        b = ((truncate ((b * 255) / 65535)) & 255)
        a = 255
      }
      setRGBA bitmap x y r g b a
      x += incX
      if (x >= width) {return}
    }
  } (bitsPerChannel == 8) {
    x = startX
    while (not (atEnd s)) {
      r = (nextUInt8 s)
      g = (nextUInt8 s)
      b = (nextUInt8 s)
      if (and (notNil transparency)
              ((at transparency 1) == r)
              ((at transparency 2) == g)
              ((at transparency 3) == b)) {
        r = 0
        g = 0
        b = 0
        a = 0
      } else {
        a = 255
      }
      setRGBA bitmap x y r g b a
      x += incX
      if (x >= width) {return}
    }
  }
}

method copyPixelsIndexed PNGReader y thisScanline startX incX {
  // Handle indexed color mode (colorType = 3)
  s = (dataStream thisScanline true)
  if (or (bitsPerChannel == 1) (bitsPerChannel == 2)
         (bitsPerChannel == 4) (bitsPerChannel == 8)) {
    x = startX
    mask = ((1 << bitsPerChannel) - 1)
    while (not (atEnd s)) {
      d = (nextUInt8 s)
      for i (8 / bitsPerChannel) {
        v = ((d >> (((8 / bitsPerChannel) - i) * bitsPerChannel)) & mask)
        c = (at palette (v + 1))
        setRGBA bitmap x y (red c) (green c) (blue c) (alpha c)
        x += incX
        if (x >= width) {return}
      }
    }
  }
}

method copyPixelsGrayAlpha PNGReader y thisScanline startX incX {
  // Handle grayscale with alpha color mode (colorType = 4)
  s = (dataStream thisScanline true)
  if (bitsPerChannel == 16) {
    x = startX
    while (not (atEnd s)) {
      d = (nextUInt16 s)
      a = (nextUInt16 s)
      if (transparency == d) {
        v = 0
        a = 0
      } else {
        v = ((truncate ((d * 255) / 65535)) & 255)
        a = ((truncate ((a * 255) / 65535)) & 255)
      }
      setRGBA bitmap x y v v v a
      x += incX
      if (x >= width) {return}
    }
  } (bitsPerChannel == 8) {
    x = startX
    while (not (atEnd s)) {
      v = (nextUInt8 s)
      a = (nextUInt8 s)
      if (transparency == v) {
        v = 0
        a = 0
      }
      setRGBA bitmap x y v v v a
      x += incX
      if (x >= width) {return}
    }
  }
}

method copyPixelsRGBA PNGReader y thisScanline startX incX {
  // RGBA color modes (colorType = 6)
  s = (dataStream thisScanline true)
  if (bitsPerChannel == 16) {
    x = startX
    while (not (atEnd s)) {
      r = (nextUInt16 s)
      g = (nextUInt16 s)
      b = (nextUInt16 s)
      a = (nextUInt16 s)
      if (and (notNil transparency)
              ((at transparency 1) == r)
              ((at transparency 2) == g)
              ((at transparency 3) == b)) {
        r = 0
        g = 0
        b = 0
        a = 0
      } else {
        r = ((truncate ((r * 255) / 65535)) & 255)
        g = ((truncate ((g * 255) / 65535)) & 255)
        b = ((truncate ((b * 255) / 65535)) & 255)
        a = ((truncate ((a * 255) / 65535)) & 255)
      }
      setRGBA bitmap x y r g b a
      x += incX
      if (x >= width) {return}
    }
  } (bitsPerChannel == 8) {
    x = startX
    while (not (atEnd s)) {
      r = (nextUInt8 s)
      g = (nextUInt8 s)
      b = (nextUInt8 s)
      a = (nextUInt8 s)
      if (and (notNil transparency)
              ((at transparency 1) == r)
              ((at transparency 2) == g)
              ((at transparency 3) == b)) {
        r = 0
        g = 0
        b = 0
        a = 0
      }
      setRGBA bitmap x y r g b a
      x += incX
      if (x >= width) {return}
    }
  }
}

method filterScanline PNGReader thisScanline prevScanline filter count {
  // Note: These are ordered by frequency based on a collection of PNG photos.
  if (4 == filter) { filterPaeth this thisScanline prevScanline count
  } (2 == filter) { filterVertical this thisScanline prevScanline count
  } (3 == filter) { filterAverage this thisScanline prevScanline count
  } (1 == filter) { filterHorizontal this thisScanline prevScanline count
  } else {
	error 'unknown filter type' filter
  }
}

method filterHorizontal PNGReader thisScanline prevScanilne count {
  // Use the pixel to the left as a predictor
  delta = (max (truncate (bitsPerPixel / 8)) 1)
  for i count {
    if (i > delta) {
      byteAtPut thisScanline i (((byteAt thisScanline i) + (byteAt thisScanline (i - delta))) & 255)
    }
  }
}

method filterVertical PNGReader thisScanline prevScanline count {
  // Use the pixel above as a predictor
  for i count {
    byteAtPut thisScanline i (((byteAt thisScanline i) + (byteAt prevScanline i)) & 255)
  }
}


method filterAverage PNGReader thisScanline prevScanline count {
  // Use the average of the pixel to the left and the pixel above as a predictor
  delta = (max (truncate (bitsPerPixel / 8)) 1)
  for i count {
    if (i <= delta) {
	  byteAtPut thisScanline i (((byteAt thisScanline i) + (truncate ((byteAt prevScanline i) / 2))) & 255)
	} else {
      byteAtPut thisScanline i (((byteAt thisScanline i) +
                                 (truncate (((byteAt prevScanline i) + (byteAt thisScanline (i - delta))) / 2))) & 255)
    }
  }
}

method filterPaeth PNGReader thisScanline prevScanline count {
  // Use the pixel to the left, the pixel above, or the pixel to above-left to
  // predict the value of this pixel. Based on Paeth (GG II, 1991).
  delta = (max (truncate (bitsPerPixel / 8)) 1)
  for i count {
    if (i <= delta) {
	  byteAtPut thisScanline i (((byteAt thisScanline i) + (byteAt prevScanline i)) & 255)
	} else {
	  pred = (paethPredict this
		(byteAt thisScanline (i - delta))
		(byteAt prevScanline i)
		(byteAt prevScanline (i - delta)))
      byteAtPut thisScanline i (((byteAt thisScanline i) + pred) & 255)
    }
  }
}

method paethPredict PNGReader a b c {
  da = (b - c)
  db = (a - c)
  pa = (abs da)
  pb = (abs db)
  pc = (abs (da + db))
  if (and (pa <= pb) (pa <= pc)) {return a}
  if (pb <= pc) {return b}
  return c
}
