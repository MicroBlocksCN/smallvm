defineClass SourceManager originalDir overwriteFlag module parsedFiles

// Note: There are ten functions with empty bodies; this won't know what file they are from.

to newSourceManager originalDir overwriteFlag aModule {
  return (init (new 'SourceManager') originalDir overwriteFlag aModule)
}

method init SourceManager origDir overwrite aModule {
  if (isNil origDir) { origDir = 'lib' }
  if (isNil overwrite) { overwrite = false }
  if (isNil aModule) { aModule = (topLevelModule) }
  originalDir = origDir
  overwriteFlag = overwrite
  module = aModule
  return this
}

method fileForClass SourceManager cl {
  // Return the file name associated with the given class (from the first non-empty method).
  // Return nil if the class has no methods.

  for m (methods cl) {
	if (notNil (cmdList m)) {
	  fn = (fileName (cmdList m))
	  if ('<parse>' != fn) { return (filePart fn) }
	}
  }
  return nil
}

method fileForFunction SourceManager f {
  if (isNil (cmdList f)) { return nil }
  return (filePart (fileName (cmdList f)))
}

method allFileNames SourceManager {
  // Return a sorted list of all source file names referenced in my module.

  d = (dictionary)
  for cl (classes module) {
	fn = (fileForClass this cl)
	if (notNil fn) { add d (filePart fn) }
  }
  for f (functions module) {
	if (notNil (cmdList f)) {
	  fn = (fileName (cmdList f))
	  if (notNil fn) { add d (filePart fn) }
	}
  }
  remove d '<parse>'
  return (sorted (keys d))
}

method parseSourceFiles SourceManager {
  // Parse all source files and stores results in a dictionary keyed by file name.

  parsedFiles = (dictionary)
  for fn (allFileNames this) {
	contents = (readFile (join originalDir '/' fn))
	if (isNil contents) {
	  print 'Could not read source file:' fn
	} else {
	  atPut parsedFiles fn (parse contents)
	}
  }
}

method originalClassFields SourceManager cl {
  // Return a list of field names from the original class definition.

  fn = (fileForClass this cl)
  if (isNil fn) { return (array) } // true for classes with no methods such as Nil

  parsedContents = (at parsedFiles fn)
  if (isNil parsedContents) { error 'No entry for' fn }

  for cmd parsedContents {
	if ('defineClass' == (primName cmd)) {
	  args = (argList cmd)
	  if ((first args) == (className cl)) {
		return (copyFromTo args 2) // use first definition found
	  }
	}
  }
  return (array)
}

method showDiffs SourceManager {
  if (isNil parsedContents) { parseSourceFiles this }
  for cl (classes module) {
	origFields = (originalClassFields this cl)
	if (isNil origFields) {
	  print 'New class:' (className cl)
	} else {
	  if ((fieldNames cl) != origFields) {
		print 'Class definition changed:' (className cl)
	  }
	}
  }
}

// 1. every method in memory matches source file
// 2. every source file method matches the one in memory
// Possible: new methods, deleted methods, changed methods

