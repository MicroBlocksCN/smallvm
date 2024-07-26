// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksAppMaker.gp
// John Maloney, June 2018
//
// Build stand-alone MicroBlocks application.

defineClass MicroBlocksAppMaker

method buildApps MicroBlocksAppMaker {

	system = (detect (function each { return (isOneOf each 'win' 'linux32bit' 'linux64bit' 'raspberryPi' 'mac') }) (commandLine))
	embeddedFS = (createEmbeddedFS this system)

	if (notNil system) {
		if (system == 'win') { system = 'win.exe' }
		writeExeFile this (join 'gp-' system) embeddedFS (join '../apps/ublocks-' system)
		if (system == 'mac') {
			writeMacApp this 'gp-mac' embeddedFS '../apps'
		}
	} else {
		writeExeFile this 'gp-win.exe' embeddedFS '../apps/ublocks-win.exe'
		writeExeFile this 'gp-linux32bit' embeddedFS '../apps/ublocks-linux32bit'
		writeExeFile this 'gp-linux64bit' embeddedFS '../apps/ublocks-linux64bit'
		writeExeFile this 'gp-raspberryPi' embeddedFS '../apps/ublocks-raspberryPi'
		writeExeFile this 'gp-mac' embeddedFS '../apps/ublocks-mac'
		writeMacApp this 'gp-mac' embeddedFS '../apps'
	}
	print 'Done!'
}

method createEmbeddedFS MicroBlocksAppMaker system {
	// Return a ZipFile object containing the embedded file system.

	zip = (create (new 'ZipFile'))
	addVersionFileToEmbeddedFS this zip
	libDir = (join (directoryPart (appPath)) 'runtime/lib')
	addFolderToEmbeddedFS this libDir 'lib' zip
	addFolderToEmbeddedFS this '../img' 'img' zip
	addFolderToEmbeddedFS this '../ide' 'lib' zip // note: must add MicroBlocks ide after GP lib
	addFolderToEmbeddedFS this '../gp/Examples' 'Examples' zip
	addFolderToEmbeddedFS this '../gp/Libraries' 'Libraries' zip
	addFolderToEmbeddedFS this '../precompiled' 'precompiled' zip
	addFolderToEmbeddedFS this '../translations' 'translations' zip
	addFolderToEmbeddedFS this '../esp32' 'esp32' zip
	return zip
}

method addVersionFileToEmbeddedFS MicroBlocksAppMaker zip {
	fileName = 'versions'
	data = (readFile (join (directoryPart (appPath)) 'runtime/' fileName) true)
	if (notNil data) {
		addFile zip fileName data true
	}
}

method addFolderToEmbeddedFS MicroBlocksAppMaker srcFolder dstFolder zip {
	// Add the files from srcFolder to dstFilder in the given ZipFile object.

	dirs = (listDirectories srcFolder)
	for fn (listFiles srcFolder) {
		if (and (not (isOneOf fn '.DS_Store' '.' '..'))
				(not (contains dirs fn))
				(not (beginsWith fn '.'))) {
			data = (readFile (join srcFolder '/' fn) true)
			addFile zip (join dstFolder '/' fn) data true
		}
	}
	for fn dirs {
		if ('node_modules' != fn) {
			addFolderToEmbeddedFS this (join srcFolder '/' fn) (join dstFolder '/' fn) zip
		}
	}
}

method writeExeFile MicroBlocksAppMaker srcAppPath embeddedFS dstPath {
	// Create an executable file that combines the given GP virtual macine
	// with the given embedded file system (a ZipFile).

	print 'Writing' dstPath '...'
	appData = (readFile srcAppPath true)
	if (notNil embeddedFS) {
		writeFile dstPath (executableWithData this appData (contents embeddedFS))
	} else {
		writeFile dstPath appData
	}
	setFileMode dstPath (+ (7 << 6) (5 << 3) 5) // set executable bits
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

// Macintosh App Creation

method writeMacApp MicroBlocksAppMaker srcAppPath embeddedFS dstPath {
	// Create a Mac application bundle that combines the given GP virtual macine
	// with the given embedded file system (a ZipFile).

	name = 'MicroBlocks'
	appName = (join dstPath '/' name '.app')
	makeDirectory appName
	makeDirectory (join appName '/Contents')
	makeDirectory (join appName '/Contents/MacOS')
	makeDirectory (join appName '/Contents/Resources')
	writeFile (join appName '/Contents/info.plist') (macInfoFile this name)
	writeExeFile this srcAppPath nil (join appName '/Contents/MacOS/' name)
	writeFile (join appName '/Contents/Resources/fs.data') (contents embeddedFS)
	writeFile (join appName '/Contents/Resources/MicroBlocks.icns') (readFile 'MicroBlocks.icns' true)
}

method macInfoFile MicroBlocksAppMaker name {
	return '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">

<dict>
	<key>CFBundleName</key>
	<string>MicroBlocks</string>
	<key>CFBundleExecutable</key>
	<string>MicroBlocks</string>
	<key>CFBundleIconFile</key>
	<string>MicroBlocks</string>

	<key>NSHighResolutionCapable</key><true/>

	<key>CFBundleIdentifier</key>
	<string>org.gpblocks.MicroBlocks</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>

	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>MicroBlocks Project File</string>
			<key>LSHandlerRank</key>
			<string>Owner</string>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>LSItemContentTypes</key>
			<array>
				<!-- MicroBlocks specific extensions (see UTExportedTypeDeclarations) -->
			<string>org.gpblocks.gp.gpp</string>
			</array>
		</dict>

		<dict>
			<key>CFBundleTypeName</key>
			<string>Media File</string>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>LSHandlerRank</key>
			<string>Alternate</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>public.data</string>
			</array>
		</dict>

	</array>

	<key>UTExportedTypeDeclarations</key>
	<array>
		<dict>
			<key>UTTypeIdentifier</key>
			<string>org.gpblocks.gp.gpp</string>
			<key>UTTypeDescription</key>
			<string>GP Project File</string>
			<key>UTTypeTagSpecification</key>
			<dict>
				<key>public.filename-extension</key>
				<string>gpp</string>
				<key>public.mime-type</key>
				<string>application/octet-stream</string>
			</dict>
			<key>UTTypeConformsTo</key>
			<array>
				<string>public.data</string>
			</array>
		</dict>
	</array>

</dict>
</plist>
'
}
