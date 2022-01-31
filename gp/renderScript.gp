// To test it:
// ./gp-linux64bit runtime/lib/* ../ide/MicroBlocksCompiler.gp ../ide/MicroBitDisplaySlot.gp renderScript.gp - --jsonFile jsonFile

to startup {
	initMicroBlocksSpecs (new 'SmallCompiler')

	// default param values
	fileName = 'script.png'
	scale = 2
	locale = 'English'

	// get file name
	i = (indexOf (commandLine) '--jsonFile')
	if (isNil i) { missingArg }
	jsonFile = (at (commandLine) (i + 1))

	// parse JSON file
	params = (jsonParse (readFile jsonFile))

	setLanguage (authoringSpecs) (at params 'locale')

	libs = (at params 'libs')
	if (notNil libs) {
		for lib libs {
			(initLibrarySpecs lib)
		}
	}

	script = (last (argList (last (parse (at params 'script')))))
	setGlobal 'scale' 2
	block = (toBlock (last (argList (last (parse (at params 'script'))))))
	fixBlockColor block
	exportAsImageScaled block (toNumber (at params 'scale')) nil (at params 'outPath')
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
	// should look like:
	// (array 'Output' (array ' ' 'setUserLED' 'set user LED _' 'bool' 'true') ...)
	category = 'Foo'
	for line lines {
		words = (words line)
		if ((count words) > 0) {
			if ('module' == (at words 1)) {
				category = (last words)
				add specs category
			}
			if ('spec' == (at words 1)) {
				add specs (copyFromTo words 2)
				op = (at words 4)
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
