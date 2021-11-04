// To test it:
// ./gp-linux64bit runtime/lib/* ../ide/MicroBlocksCompiler.gp ../ide/MicroBitDisplaySlot.gp renderScript.gp - --scriptString "script nil 10 10 { whenButtonPressed 'A'; repeatUntil (not (buttonA)) { '[display:mbDisplay]' 145728; waitMillis 250; '[display:mbDisplay]' 4685802; waitMillis 250; '[display:mbDisplayOff]'; waitMillis 300 } }" --libs '["LED Display"]'

to startup {
	initMicroBlocksSpecs (new 'SmallCompiler')

	// default param values
	fileName = 'script.png'
	scale = 2
	libs = (array)

	// parse params
	i = (indexOf (commandLine) '--scriptString')
	if (isNil i) { missingArg }
	scriptString = (at (commandLine) (i + 1))

	i = (indexOf (commandLine) '--fileName')
	if (i > 0) {
		fileName = (at (commandLine) (i + 1))
	}

	i = (indexOf (commandLine) '--scale')
	if (i > 0) {
		scale = (at (commandLine) (i + 1))
	}

	i = (indexOf (commandLine) '--libs')
	if (i > 0) {
		for lib (jsonParse (at (commandLine) (i + 1))) {
			(initLibrarySpecs lib)
		}
	}

	script = (last (argList (last (parse scriptString))))
	setGlobal 'scale' 2
	block = (toBlock (last (argList (last (parse scriptString)))))
	fixBlockColor block
	exportAsImageScaled block (toNumber scale) nil fileName
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
	print './gp-linux64bit runtime/lib/* ../ide/MicroBlocksCompiler.gp ../ide/MicroBitDisplaySlot.gp renderScript.gp - --scriptString "script nil 10 10 { whenButtonPressed ''A''; repeatUntil (not (buttonA)) { ''[display:mbDisplay]'' 145728; waitMillis 250; ''[display:mbDisplay]'' 4685802; waitMillis 250; ''[display:mbDisplayOff]''; waitMillis 300 } }" --libs ''["LED Display"]'''
	// just making my syntax highlighter happy.. */
	exit
}
