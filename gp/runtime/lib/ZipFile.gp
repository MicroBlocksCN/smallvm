// Zipfile.gp - Read and write ZIP files
//
// To build a zip file: create, addFile, contents
// To read a zip file: read, fileNames, extractFile
// See zipTest for sample code.

defineClass ZipFile stream entries version fileEntryID dirEntryID endID crcTable

method entries ZipFile { return entries }

method zipTest ZipFile data outFileName {
  // Create, then read a zip file. If data is provided, include it in the
  // zip file. If outFileName is provided, write the zip data to that file.
  // Ex: zipTest (new 'ZipFile') (readFile '20000Leagues.txt') 'test.zip'

  if (isNil data) { data = 'This is file 2.' }
  zip = (create (new 'ZipFile'))
  addFile zip 'file1.txt' 'This is file 1.'
  addFile zip 'file2.txt' data true
  data = (contents zip)
  if (notNil outFileName) { writeFile outFileName data }

  reader = (read (new 'ZipFile') data)
  fileNames = (fileNames reader)
  print 'Read' (count fileNames) 'files:'
  for fileName fileNames {
	fileData = (extractFile reader fileName)
    print '  ' fileName (byteCount fileData) 'bytes'
  }
}

// Entry points - writing

method create ZipFile {
  // Prepare for writing.

  initConstants this
  entries = (table 'fileName' 'fileData' 'compressionMethod' 'offset' 'uncompressedSize' 'compressedSize' 'dosTime' 'crc')
  return this
}

method addFile ZipFile fileName fileData useCompression {
  // Add the given file to this zip file.

  if (isNil useCompression) { useCompression = false }
  i = (find entries 'fileName' fileName)
  if (i != 0) { removeRow entries i } // remove old entry for fileName, if any
  compressionMethod = 0
  if useCompression { compressionMethod = 8 }
  add entries fileName fileData compressionMethod
}

method contents ZipFile {
  // Call this method after creating and adding files.
  // Builds a zip file from the files added and returns its contents (a BinaryData).

  stream = (dataStream (newBinaryData 100000) false) // little endian
  for r (rowCount entries) {
    writeEntry this r
  }
  finishWriting this
  return (contents stream)
}

// Entry points - reading

method read ZipFile data {
  // Read the given zip file data and read its directory.
  // Files can then be read using extractFile.

  initConstants this
  stream = (dataStream data false) // little endian
  entries = (table 'fileName' 'dosTime' 'offset' 'compressionMethod' 'uncompressedSize' 'compressedSize' 'crc')
  findEndRecord this
  entryCount = (readEndRecord this) // positions stream at the first directory entry
  for i entryCount { readDirectoryEntry this }
  return this
}

method fileNames ZipFile {
  return (column entries 'fileName')
}

method extractNestedFile ZipFile fileName {
  for fullPath (fileNames this) {
	if ((filePart fullPath) == fileName) {
	  return (extractFile this fullPath)
	}
  }
  return nil
}

method extractFile ZipFile fileName {
  // Extract and return the given file, or nil if the file is missing.
  // Details: Read the file entry data. Decompress the file contents, if necessary, and check the CRC.

  entryIndex = (find entries 'fileName' fileName)
  if (entryIndex == 0) { return nil }

  offset = (cellAt entries entryIndex 'offset')
  setPosition stream offset
  if (fileEntryID != (nextUInt32 stream)) { error 'zip: bad local file header' }

  versionNeeded = (nextUInt16 stream)
  flags = (nextUInt16 stream)
  compressionMethod = (nextUInt16 stream)
  dosTime = (nextUInt32 stream)
  crc = (nextUInt32 stream)
  compressedSize = (nextUInt32 stream)
  uncompressedSize = (nextUInt32 stream)
  nameLength = (nextUInt16 stream)
  extraLength = (nextUInt16 stream)
  fileName = (nextString stream nameLength)
  extra = (nextData stream extraLength)

  ignore versionNeeded dosTime uncompressedSize extra

  if ((flags & 8) != 0) {
	// use the sizes and crc values from directory entry
	// (these values are also stored following the data)
	compressedSize = (cellAt entries entryIndex 'compressedSize')
	uncompressedSize = (cellAt entries entryIndex 'uncompressedSize')
	crc = (cellAt entries entryIndex 'crc')
  }

  if ((flags & 1) != 0) { error 'zip: cannot read encrypted files' }
  if (and (compressionMethod != 0) (compressionMethod != 8)) {
    error (join 'zip: cannot handle zip compression method' compressionMethod)
  }

  data = (nextData stream compressedSize)
  if (compressionMethod == 8) {
	data = (inflate data)
  }
  if (crc != (crc data)) { error (join 'zip: bad CRC for ' fileName) }

  return data
}

// utilities

method initConstants ZipFile {
  version = 10
  fileEntryID = (hex '04034b50')
  dirEntryID = (hex '02014b50')
  endID = (hex '06054b50')
}

// utilities - writing

method writeEntry ZipFile e {
  fileName = (cellAt entries e 'fileName')
  compressionMethod = (cellAt entries e 'compressionMethod')
  data = (cellAt entries e 'fileData')
  uncompressedSize = (byteCount data)
  crc = (crc data)
  dosTime = (dosTime this)
  cellAtPut entries e 'offset' (position stream)
  cellAtPut entries e 'uncompressedSize' uncompressedSize
  cellAtPut entries e 'compressedSize' uncompressedSize
  cellAtPut entries e 'dosTime' dosTime
  cellAtPut entries e 'crc' crc
  if (compressionMethod == 8) {
	data = (deflate data)
	cellAtPut entries e 'compressedSize' (byteCount data)
  }

  // write file entry
  putUInt32 stream fileEntryID
  putUInt16 stream version
  putUInt16 stream 0 // flags
  putUInt16 stream compressionMethod
  putUInt32 stream dosTime
  putUInt32 stream crc
  putUInt32 stream (byteCount data)
  putUInt32 stream uncompressedSize
  putUInt16 stream (byteCount fileName)
  putUInt16 stream 0 // extra info length
  nextPutAll stream fileName
  nextPutAll stream data
}

method finishWriting ZipFile {
  // Write the central directory and end record.

  dirStart = (position stream)

  // write directory entries
  for e (rowCount entries) {
	fileName = (cellAt entries e 'fileName')
	putUInt32 stream dirEntryID
	putUInt16 stream version // created by version
	putUInt16 stream version // minimum version needed to extract
	putUInt16 stream 0 // flags
	putUInt16 stream (cellAt entries e 'compressionMethod')
	putUInt32 stream (cellAt entries e 'dosTime')
	putUInt32 stream (cellAt entries e 'crc')
	putUInt32 stream (cellAt entries e 'compressedSize')
	putUInt32 stream (cellAt entries e 'uncompressedSize')
	putUInt16 stream (byteCount fileName)
	putUInt16 stream 0 // extra info length
	putUInt16 stream 0 // comment length
	putUInt16 stream 0 // starting disk number
	putUInt16 stream 0 // internal file attributes
	putUInt32 stream 0 // external file attributes
	putUInt32 stream (cellAt entries e 'offset')
	nextPutAll stream fileName
  }

  // write the end record
  dirSize = ((position stream) - dirStart)
  entryCount = (rowCount entries)
  putUInt32 stream endID
  putUInt16 stream 0			// number of this disk
  putUInt16 stream 0			// central directory start disk
  putUInt16 stream entryCount	// number of directory entries on this disk
  putUInt16 stream entryCount	// total number of directory entries
  putUInt32 stream dirSize		// length of central directory in bytes
  putUInt32 stream dirStart		// offset of central directory from start of file
  putUInt32 stream 0			// comment length
}

method dosTime ZipFile {
  dateAndTime = (secondsToDateAndTime (at (time) 1))
  year = ((at dateAndTime 1) - 1980)
  month = (at dateAndTime 2)
  day = (at dateAndTime 3)
  hour = (at dateAndTime 4)
  minute = (at dateAndTime 5)
  second = (at dateAndTime 6)
  return (((toLargeInteger year) << 25) | (+ (month << 21) (day << 16) (hour << 11) (minute << 5) (second >> 1)))
}

// utilities - reading

method findEndRecord ZipFile {
  // Scan backwards from the end of the data to the last EndOfCentralDiretory record.
  // If successful, leave the buffer positioned at the start of that record.
  data = (data stream)
  i = ((byteCount data) - 4)
  while (i >= 0) {
     if ((byteAt data i) == 80) { // found first byte of possible endID
	  setPosition stream (i - 1)
	  if (endID == (nextUInt32 stream)) { // found complete endID
	    setPosition stream (i - 1)
		return
	  }
	}
	i += -1
  }
}

method readEndRecord ZipFile {
  // Read the end-of-central-directory record. If successful, leave the stream
  // positioned at the start of the directory and return the number of entries.

  if (endID != (nextUInt32 stream)) { error 'zip: bad zip end record' }

  thisDiskNum = (nextUInt16 stream)
  startDiskNum = (nextUInt16 stream)
  entriesOnThisDisk = (nextUInt16 stream)
  totalEntries = (nextUInt16 stream)
  directorySize = (nextUInt32 stream)
  directoryOffset = (nextUInt32 stream)
  commentLength = (nextUInt16 stream)
  comment = (nextString stream commentLength)
  ignore directorySize comment

  if (or (thisDiskNum != startDiskNum) (entriesOnThisDisk != totalEntries)) {
	error 'cannot read multiple disk zip files'
  }
  setPosition stream directoryOffset
  return totalEntries
}

method readDirectoryEntry ZipFile {
  // Add the directory entry at the current stream position to the entries table.

  if (dirEntryID != (nextUInt32 stream)) { error 'zip: bad central directory entry' }

  versionMadeBy = (nextUInt16 stream)
  versionNeeded = (nextUInt16 stream)
  flags = (nextUInt16 stream)
  compressionMethod = (nextUInt16 stream)
  dosTime = (nextUInt32 stream)
  crc = (nextUInt32 stream)
  compressedSize = (nextUInt32 stream)
  uncompressedSize = (nextUInt32 stream)
  nameLength = (nextUInt16 stream)
  extraLength = (nextUInt16 stream)
  commentLength = (nextUInt16 stream)
  diskNum = (nextUInt16 stream)
  internalAttributes = (nextUInt16 stream)
  externalAttributes = (nextUInt32 stream)
  offset = (nextUInt32 stream)
  fileName = (nextString stream nameLength)
  extra = (nextData stream extraLength)
  comment = (nextString stream commentLength)

  ignore versionMadeBy versionNeeded flags diskNum internalAttributes externalAttributes extra comment

  add entries fileName dosTime offset compressionMethod uncompressedSize compressedSize crc
}
