// MicroBlocksAppMaker.gp
// John Maloney, June 2018
//
// Build stand-alone MicroBlocks application.
// To do: allow saving apps for platforms other than current one

// ToDo:
//	[x] output mutiple applications
//	generate Mac .app with correct plist and icons
//	pull examples from internal file system
//	button to import a library
//	get translations from 'translations'
//	translation button

// createEmbeddedFS (new 'MicroBlocksAppMaker')
// test (new 'MicroBlocksAppMaker')

defineClass MicroBlocksAppMaker

method test MicroBlocksAppMaker {
	embeddedFS = (createEmbeddedFS this)
	writeExeFile this (appPath) embeddedFS '../apps/ublocks-test'
	writeExeFile this 'gp-win.exe' embeddedFS '../apps/ublocks-win.exe'
	writeExeFile this 'gp-linux32bit' embeddedFS '../apps/ublocks-linux32bit'
	writeExeFile this 'gp-linux64bit' embeddedFS '../apps/ublocks-linux64bit'
	writeExeFile this 'gp-raspberryPi' embeddedFS '../apps/ublocks-raspberryPi'
	print 'Done!'
}

method exportApp MicroBlocksAppMaker name {
  if (isNil name) { name = 'MicroBlocks' }
  dir = (directoryPart name)
  if ('' == dir) { dir = (gpFolder) }
  name = (filePart name)
  embeddedFS = (createEmbeddedFS this)
  if ('Mac' == (platform)) {
	exportMacApp this dir name embeddedFS
  } else {
	extension = nil
	if ('Win' == (platform)) { extension = '.exe' }
	fileName = (uniqueNameNotIn (join (listDirectories dir) (listFiles dir)) name extension)
	writeExeFile this (join dir '/' fileName) embeddedFS
  }
}

method createEmbeddedFS MicroBlocksAppMaker {
	// Return a ZipFile object containing the embedded file system.

	zip = (create (new 'ZipFile'))
	libDir = (join (directoryPart (appPath)) 'runtime/lib')
	addFolderToEmbeddedFS this libDir 'lib' zip // xxx check this on Sierra...
	addFolderToEmbeddedFS this '../ide' 'lib' zip // note: must add MicroBlocks ide after GP lib
	addFolderToEmbeddedFS this '../gp/Examples' 'Examples' zip
	addFolderToEmbeddedFS this '../gp/Libraries' 'Libraries' zip
	addFolderToEmbeddedFS this '../precompiled' 'precompiled' zip
	addFolderToEmbeddedFS this '../translations' 'translations' zip
	return zip
}

method addFolderToEmbeddedFS MicroBlocksAppMaker srcFolder dstFolder zip {
	// Add the files from srcFolder to dstFilder in the given ZipFile object.

	dirs = (listDirectories srcFolder)
	for fn (listFiles srcFolder) {
		if (contains dirs fn) {
			addFolderToEmbeddedFS this (join srcFolder '/' fn) (join dstFolder '/' fn) zip
		} (not (isOneOf fn '.DS_Store' '.' '..')) {
			data = (readFile (join srcFolder '/' fn))
			addFile zip (join dstFolder '/' fn) data true
		}
	}
}

method writeExeFile MicroBlocksAppMaker srcAppPath embeddedFS dstPath {
	// Create an executable file that combines the given GP virtual macine
	// with the given embedded file system (a ZipFile).

	print 'Writing' dstPath '...'
	appData = (readFile srcAppPath true)
	writeFile dstPath (executableWithData this appData (contents embeddedFS))
	setFileMode dstPath (+ (7 << 6) (5 << 3) 5)  // set executable bits
}

method executableWithData MicroBlocksAppMaker appData embeddedFSData {
  appEnd = (findAppEnd this appData)
  byteCount = (+ appEnd 4 (byteCount embeddedFSData))
  result = (newBinaryData byteCount)
  replaceByteRange result 1 appEnd appData
  replaceByteRange result (appEnd + 1) (appEnd + 4) 'GPFS'
  replaceByteRange result (appEnd + 5) byteCount embeddedFSData
  return result
}

method findAppEnd MicroBlocksAppMaker appData {
  // Return the index of 'GPFSPK\03\04'
  for i (byteCount appData) {
	if (and
		(71 == (byteAt appData i))
		(80 == (byteAt appData (i + 1)))
		(70 == (byteAt appData (i + 2)))
		(83 == (byteAt appData (i + 3)))
		(80 == (byteAt appData (i + 4)))
		(75 == (byteAt appData (i + 5)))
		( 3 == (byteAt appData (i + 6)))
		( 4 == (byteAt appData (i + 7)))) {
			return i
		}
  }
  return (byteCount appData)
}

// Macintosh App Bundle Support

method exportMacApp MicroBlocksAppMaker dir name embeddedFS {
  // Create a Mac application bundle with the given embedded file system (a ZipFile).

  name = (uniqueNameNotIn (join (listDirectories dir) (listFiles dir)) name '.app')
  appName = (join dir '/' name)
  name = (withoutExtension name)
  makeDirectory appName
  makeDirectory (join appName '/Contents')
  makeDirectory (join appName '/Contents/MacOS')
  makeDirectory (join appName '/Contents/Resources')
  writeFile (join appName '/Contents/info.plist') (macInfoFile this name)
  writeShellScript this name (join appName '/Contents/MacOS/start.sh')
  writeExeFile this (appPath) embeddedFS (join appName '/Contents/MacOS/' name)
}

method macInfoFile MicroBlocksAppMaker name {
  return (join '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>' name '</string>
	<key>CFBundleDisplayName</key>
	<string>' name '</string>
	<key>CFBundleExecutable</key>
	<string>start.sh</string>
	<key>CFBundleIconFile</key>
	<string>AppIcons</string>
</dict>
</plist>
')
}

method writeShellScript MicroBlocksAppMaker name fileName {
  shellScript = (join '#!/bin/sh
# This shell script starts GP with the appropriate top-level directory.
# Add >>app.log 2>&1 to redirect stdout and stderr to app.log for debugging.

DIR=`dirname "$0"`
cd "$DIR"
cd ../../..
"$DIR"/"' name '"
')
  writeFile fileName shellScript
  setFileMode fileName (7 << 6) // set executable bits
}
