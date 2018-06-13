// AppMaker.gp
// John Maloney, April 2016
//
// Turns a GP project into a stand-alone application.
// To do: allow saving apps for platforms other than current one

// exportApp (new 'AppMaker') nil 'MicroBlocks'

defineClass AppMaker appName

method exportApp AppMaker project name {
  if (isNil name) { name = 'MyApp' }
  dir = (directoryPart name)
  if ('' == dir) { dir = (gpFolder) }
  name = (filePart name)
  embeddedFS = (createEmbeddedFS this project)
  if ('Mac' == (platform)) {
	exportMacApp this dir name embeddedFS
  } else {
	extension = nil
	if ('Win' == (platform)) { extension = '.exe' }
	fileName = (uniqueNameNotIn (join (listDirectories dir) (listFiles dir)) name extension)
	writeExeFile this (join dir '/' fileName) embeddedFS
  }
}

method writeExeFile AppMaker fileName embeddedFS {
  // Write an executable file with the given embedded file system (a ZipFile).

  writeFile fileName (executableWithData this (contents embeddedFS))
  setFileMode fileName (+ (7 << 6) (5 << 3) 5)  // set executable bits
}

method createEmbeddedFS AppMaker project {
  // Return a ZipFile object containing the GP library.

  zip = (create (new 'ZipFile'))
  if (notEmpty (listEmbeddedFiles)) {
	// use embedded file system
	for fn (listEmbeddedFiles) {
	  if (beginsWith fn 'lib/') {
		data = (readEmbeddedFile fn)
		addFile zip fn data true
	  }
	  if ('startup.gp' == fn) {
		startup = (readEmbeddedFile fn)
	  }
	}
	for fn (listEmbeddedFiles) {
	  if (beginsWith fn 'modules/') {
		data = (readEmbeddedFile fn)
		addFile zip fn data true
	  }
	}
  } else {
	// use external file system
	prefix = (directoryPart (appPath))
	if (isEmpty (listFiles (join prefix 'lib'))) {
	  prefix = (join prefix 'runtime/')
	  if (isEmpty (listFiles (join prefix 'lib'))) {
		error 'Could not find library folder'
	  }
	}
	for fn (listFiles (join prefix 'lib')) {
	  if (not (isOneOf fn '.DS_Store' '.' '..')) {
	    fullName = (join 'lib/' fn)
		data = (readFile (join prefix fullName))
		addFile zip fullName data true
	  }
	}
	for fn (listFiles  (join prefix 'modules')) {
	  if (not (isOneOf fn '.DS_Store' '.' '..')) {
	    fullName = (join 'modules/' fn)
		data = (readFile (join prefix fullName))
		addFile zip fullName data true
	  }
	}
	startup = (readFile (join (directoryPart (appPath)) '/runtime/startup.gp'))
  }
  if (notNil project) {
	// add startup.gp and project file
	addFile zip 'startup.gp' (startupFile this) true
	if (notNil project) {
	  addFile zip 'project.gpp' (projectData2 project) true
	}
  } else {
	addFile zip 'startup.gp' startup true
  }
  return zip
}

method startupFile AppMaker {
  return '
to startup {
  setGlobal ''vectorTrails'' false
  openPage true
  openProjectFromFile (newStage) ''project.gpp''
  gc
  print (mem)
  startSteppingSafely (global ''page'') true
}
'
}

method executableWithData AppMaker data {
  appData = (readFile (appPath) true)
  appEnd = (findAppEnd this appData)
  byteCount = (+ appEnd 4 (byteCount data))
  result = (newBinaryData byteCount)
  replaceByteRange result 1 appEnd appData
  replaceByteRange result (appEnd + 1) (appEnd + 4) 'GPFS'
  replaceByteRange result (appEnd + 5) byteCount data
  return result
}

method findAppEnd AppMaker appData {
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

method exportMacApp AppMaker dir name embeddedFS {
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
  writeExeFile this (join appName '/Contents/MacOS/' name) embeddedFS
}

method macInfoFile AppMaker name {
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

method writeShellScript AppMaker name fileName {
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
