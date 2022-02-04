// To test:
// ./gp-linux64bit runtime/lib/* ../ide/* renderScript.gp - --jsonFile test.json

to startup {
	outFilePath = '/tmp/render.png'

	// delete previous output file, if any, so if there will be no file if rendering fails
	safelyRun (action 'deleteFile' outFilePath)

	// get file name from the command line
	i = (indexOf (commandLine) '--jsonFile')
	if (or (isNil i) ((count (commandLine)) < (i + 1))) { missingArg }
	jsonFile = (at (commandLine) (i + 1))

	// read and extract parameters from JSON file
	data = (readFile jsonFile)
	if (isNil data) { exit }
	params = (jsonParse data)
	localeParam = (at params 'locale' 'English')
	libsParam = (at params 'libs' (array))
	scriptParam = (at params 'script')
	if (isNil scriptParam) { exit } // gotta have a script!

	// initalize blocks specs
	initMicroBlocksSpecs (new 'SmallCompiler')

	// import libraries
	for lib libsParam {
		initLibrarySpecs lib
	}

	// set the language
	setLanguage (authoringSpecs) localeParam

	// set scale and blockScale to 1; scale will be determined by desiredScale
	setGlobal 'scale' 1
	setGlobal 'blockScale' 1
	desiredScale = 2

	script = (last (argList (last (parse scriptParam))))
	block = (toBlock script)
	fixBlockColor block
	exportAsImageScaled block desiredScale nil outFilePath
	exit
}

to initLibrarySpecs libraryName {
	// try to find the library
	libPath = (findLibrary libraryName 'Libraries')
	if (isNil libPath) {
		print 'Library' libraryName 'not found'
		exit
	}
	data = (readFile libPath)
	if (isNil data) {
		print 'Could not import library' libraryName
		exit
	}
	lines = (lines data)
	specs = (list)
	category = 'None'
	for line lines {
		words = (words line)
		if ((count words) > 0) {
			if ('module' == (at words 1)) {
				category = (last words)
				add specs category
			}
			if ('spec' == (at words 1)) {
				blockSpec = (argList (first (parse line)))
				add specs blockSpec
				op = (at blockSpec 2)
				setOpCategory (authoringSpecs) op category
			}
		}
	}
	addSpecs (authoringSpecs) specs
}

to findLibrary libraryName path {
	for filePath (listFiles path) {
		if (endsWith filePath (join libraryName '.ubl')) {
			return (join path '/' filePath)
		}
	}
	// recurse into subdirs
	for dirPath (listDirectories path) {
		libFile = (findLibrary libraryName (join path '/' dirPath))
		if (notNil libFile) { return libFile }
	}
	return nil
}

to missingArg {
	print 'Missing argument(s)!'
	print 'Usage example: '
	print './gp-linux64bit runtime/lib/* ../ide/MicroBlocksCompiler.gp ../ide/MicroBitDisplaySlot.gp renderScript.gp - --jsonFile jsonFile'
	// just making my syntax highlighter happy.. */
	exit
}
