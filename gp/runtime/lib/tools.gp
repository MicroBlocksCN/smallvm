// useful global functions

// print and inspect

to print args... {
  result = (list)
  for i (argCount) {
    add result (toString (arg i))
    if (i != (argCount)) {add result ' '}
  }
  log (joinStringArray (toArray result))
}

to inspect obj {
  class = (classOf obj)
  className = (getField class 'className')
  if (or (isNil obj) (true === obj) (false === obj)
		 (isClass obj 'Integer') (isClass obj 'Float')
		 (isClass obj 'String') (isClass obj 'ExternalReference')) {
	print className (printString obj)
  } (isClass obj 'BinaryData') {
    print className (join '(' (byteCount obj) ' bytes)')
	printBytes obj
  } else {
    n = (min 100 (objWords obj))
	fieldNames = (getField class 'fieldNames')
    print className '{'
	for i n {
	  if (i <= (count fieldNames)) {
	    slotName = (join '  ' (at fieldNames i) ':')
	  } else {
	    slotName = (join '  ' i ':')
	  }
	  print slotName (printString (getField obj i))
	}
	extra = ((objWords obj) - n)
	if (extra > 0) {
	  print '  ...' extra 'more ...'
	}
	print '}'
  }
}

to printBytes binaryData {
  byteCount = (byteCount binaryData)
  i = 1
  repeat 10 {
    line = (list)
    for col 20 {
      if (i > byteCount) {
	    print (joinStringArray (toArray line))
        return
	  }
      add line (toString (byteAt binaryData i))
	  add line ' '
	  if ((col % 5) == 0) { add line '  ' }
	  i += 1
	}
	print (joinStringArray (toArray line))
  }
  print '...' (byteCount - (i - 1)) 'more bytes ...'
}

to printString obj {
  return (toString obj)
}

// time and date

to dateString {
  now = (localDateAndTime)
  amPm = 'am'
  hours = (at now 4)
  if (hours >= 12) { amPm = 'pm' }
  if (hours > 12) { hours += -12 }
  min = (toString (at now 5))
  if ((count min) < 2) { min = (join '0' min) }
  secs = (toString (at now 6))
  if ((count secs) < 2) { secs = (join '0' secs) }
  return (join '' (at now 1) '-' (at now 2) '-' (at now 3) ' ' hours ':' min ':' secs amPm)
}

to localDateAndTime {
  // Return an array with the local date and time.

  time = (time)
  localOffset = (at time 3)
  if (at time 4) { localOffset += -3600 } // adjust for daylight savings time
  return (secondsToDateAndTime ((at time 1) - localOffset))
}

to secondsToDateAndTime secs {
  // Convert the given second count (seconds since midnight Jan 1, 2000)
  // to an array of integers: year month day hour minute second

  secsPerDay = (* 24 60 60)
  year = 2000 // start of gp epoch
  while (secs >= (secondsInYear year)) {
    secs = (secs - (secondsInYear year))
    year += 1
  }
  isLeap = (and ((year % 4) == 0) (or ((year % 100) != 0) ((year % 400) == 0)))
  daysPerMonth = (array 31 28 31 30 31 30 31 31 30 31 30 31)
  if isLeap { atPut daysPerMonth 2 29 }
  day = (ceiling ((toFloat secs) / secsPerDay))
  month = 1
  while (day > (at daysPerMonth month)) {
    day = (day - (at daysPerMonth month))
    month += 1
  }
  minutesSinceMidnight = (truncate ((secs % secsPerDay) / 60))
  hour = (truncate (minutesSinceMidnight / 60))
  minute = (minutesSinceMidnight % 60)
  second = (secs % 60)
  return (array year month day hour minute second)
}

to secondsInYear year {
  isLeap = (and ((year % 4) == 0) (or ((year % 100) != 0) ((year % 400) == 0)))
  if isLeap {
    return (* 366 24 60 60)
  }
  return (* 365 24 60 60)
}

to timeSince startSecs {
  // Return a string like '3 hours, 42 seconds' or '2 years, three months'
  // that represents the elapsed time since the given starting time.

  secsPerHour = (60 * 60)
  secsPerDay = (24 * secsPerHour)
  secs = (truncate ((first (time)) - startSecs)) // seconds
  if (secs < 0) { secs = 0 }
  if (secs < 60) { return (join '' secs ' seconds') }
  if (secs < 3600) { return (join '' (truncate (secs / 60)) ' minutes ' (secs % 60) ' seconds') }
  if (secs < secsPerDay) {
	return (join 'about ' (truncate (secs / secsPerHour)) ' hours ' (truncate ((secs % secsPerHour) / 60)) ' minutes') }

  days = (truncate (secs / secsPerDay))
  if (days < 31) {
	hours = (truncate ((secs - (days * secsPerDay)) / secsPerHour))
	return (join 'about ' days ' days ' hours ' hours') }

  // approximate months as 31 days for under a year
  if (days <= 365) {
	months = (truncate (days / 31))
	return (join 'about ' months ' months ' (days - (months * 31)) ' days') }

  // approximate months/days using average year and month lengths
  secsPerYear = (truncate (365.25 * secsPerDay))
  secsPerMonth = (truncate (secsPerYear / 12))
  years = (truncate (secs / secsPerYear))
  months = (truncate ((secs - (years * secsPerYear)) / secsPerMonth))
  if (months == 0) { return (join 'about ' years ' years') }
  return (join 'about ' years ' years ' months ' months')
}

to timestamp {
  // Return the current time in RFC3339 Internet Timestamp format.

  rawTime = (time)
  now = (secondsToDateAndTime (at rawTime 1))

  year = (at now 1)
  month = (leftPadded (toString (at now 2)) 2 '0')
  day = (leftPadded (toString (at now 3)) 2 '0')
  hour = (leftPadded (toString (at now 4)) 2 '0')
  min = (leftPadded (toString (at now 5)) 2 '0')
  sec = (leftPadded (toString (at now 6)) 2 '0')
  usec = (leftPadded (toString (at rawTime 2)) 6 '0')
  return (join '' year '-' month '-' day 'T' hour ':' min ':' sec '.' usec 'Z' )
}

// memory

to mem {
  // Return a string describing current memory useage.
  stats = (memStats)
  used = (truncate ((at stats 1) / 1000))
  total = (truncate ((at stats 2) / 1000))
  percent = (toString ((100.0 * used) / total) 3)
  free = (truncate (((at stats 2) - (at stats 1)) / 1000))
  return (join 'used ' used 'k (' percent '%' ' of ' total 'k); ' free 'k free')
}

to gcIfNeeded {
  // Garbage collect periodically.
  // Current policy: GC when under 10 mbyte free or every 50 mbytes of allocations

return // xxx garbage collection should now be automatic; remove calls to gcIfNeeded after more testing

  stats = (memStats)
  mbytesFree = (((at stats 2) - (at stats 1)) / 1000000)
  mbytesAllocated = ((at stats 4) / 1000000)

  if (or (mbytesFree < 10) (mbytesAllocated > 50) ) {
	t = (newTimer)
	kbytesReclaimed = (truncate ((gc) / 1000))
	kbytesFree = (((at stats 2) - (at stats 1)) / 1000)
//	print 'reclaimed' kbytesReclaimed 'kbytes in' (msecs t) 'msecs;' kbytesFree 'kbytes available'
	stats = (memStats)
	mbytesFree = (((at stats 2) - (at stats 1)) / 1000000)
	if (mbytesFree < 2) { error 'GC could not reclaim enough space' }
  }
}

// object stats

to objectStats onlyCountGarbage {
  // Return statistics about the number of instances and words used by objects
  // by class. If onlyCountGarbage is true, then count only garbage objects.

  countAll = true
  if onlyCountGarbage {
    findGarbage
    countAll = false
  }
  stats = (table 'class' 'instances' 'words')
  add stats 'totals' 0 0
  totalsRow = (row stats 1)
  end = (array 'end') // marker for last object
  obj = (objectAfter nil)
  while (not (obj === end)) {
    if (or countAll (isGarbage obj)) {
	  instWords = (objWords obj)
	  className = (className (classOf obj))
	  i = (find stats 'class' className)
	  if (i == 0) {
	    add stats className 1 instWords
	  } else {
	    row = (row stats i)
		atPut row 2 ((at row 2) + 1)
		atPut row 3 ((at row 3) + instWords)
	  }
	  atPut totalsRow 2 ((at totalsRow 2) + 1)
	  atPut totalsRow 3 ((at totalsRow 3) + instWords)
	}
	obj = (objectAfter obj)
  }
  return (sorted stats 'words' '>')
}

to allInstances classOrClassName {
  // Return all instances of the given class.
  // If className is omitted, return all objects.
  if (isClass classOrClassName 'String') {
	cl = (class classOrClassName) // top-level module
	if (isNil cl) {
	  classesWithName = (classesWithName classOrClassName)
	  if ((count classesWithName) > 0) {
		cl = (first classesWithName)
	  }
	}
	if (isNil cl) { error (join 'No class named ' classOrClassName) }
	classID = (classIndex cl)
  } (isClass classOrClassName 'Class') {
	classID = (classIndex classOrClassName)
  } else {
	classID = classOrClassName
  }
  result = (list)
  obj = (objectAfter nil classID)
  while (notNil obj) {
    add result obj
    obj = (objectAfter obj classID)
  }
  return result
}

to classesWithName name {
  // Return a list of classes with the given name, independent of which module they are in.
  result = (list)
  for cl (classes) {
	if ((className cl) == name) { add result cl }
  }
  return result
}

// useful object queries

to hasField obj fieldName {
  fields = (getField (classOf obj) 'fieldNames')
  for fn fields {
    if (fn == fieldName) { return true }
  }
  return false
}

to getFieldOrNil obj fieldName {
  if (hasField obj fieldName) {
	return (getField obj fieldName)
  } else {
    return nil
  }
}

to implements obj opName {
  // Return true if the class of the given object implements the given method.
  methods = (getField (classOf obj) 'methods')
  for m methods {
    if (opName == (getField m 'functionName')) { return true }
  }
  return false
}

to findPathFromTo startObj finalObj {
  // Return an array of field names/field indexs that defines a chain of references from
  // startObj to finalObj, or nil if no path is found.

  if (not (containsReferences startObj)) { return nil }
  visited = (dictionary)
  todo = (list (array startObj (array)))
  while (notEmpty todo) {
	pair = (removeFirst todo)
	obj = (first pair)
	path = (last pair)
	if (isClass obj 'Array') {
	  for i (count obj) {
		nextObj = (at obj i)
		if (nextObj === finalObj) { return (copyWith path i) }
		if (and (containsReferences nextObj) (not (contains visited nextObj))) {
		  add visited nextObj
		  add todo (array nextObj (copyWith path i))
		}
	  }
	} else {
	  for f (fieldNames (classOf obj)) {
		nextObj = (getField obj f)
		if (nextObj === finalObj) { return (copyWith path f) }
		if (and (containsReferences nextObj) (not (contains visited nextObj))) {
		  add visited nextObj
		  add todo (array nextObj (copyWith path f))
		}
	  }
	}
  }
  return nil
}

to rootPathsTo anObject {
  // Return an list of paths from the root modules to the given object.
  // A path is an array of field names/field indexs that defines a chain
  // of references from a root (e.g. (sessionModule) to the given object.

  seen = (dictionary)
  result = (list)
  todo = (list (array anObject (array)))
  while (notEmpty todo) {
	pair = (removeFirst todo)
	obj = (first pair)
	path = (last pair)
	gc
	for ref (objectReferences obj) {
	  if (or (ref === pair) (ref === (stack (currentTask)))) {
		// ignore
	  } (or (ref === (sessionModule)) (ref === (topLevelModule))) {
		path = (reversed (join path (array (fieldNameOrIndexFor ref obj) ref)))
		add result path
		add seen path
	  } (not (contains seen ref)) {
		path = (copyWith path (fieldNameOrIndexFor ref obj))
		add seen path
		add seen ref
		add todo (array ref path)
	  } else {
		// already seen
	  }
	}
  }
  return result
}

to fieldNameOrIndexFor srcObj referencedObj {
  fieldNames = (fieldNames (classOf srcObj))
  for i (objWords srcObj) {
	if ((getField srcObj i) === referencedObj) {
	  if (i <= (count fieldNames)) { return (at fieldNames i) }
	  return i
	}
  }
  error 'No reference found'
}

to containsReferences obj {
  if (and (isClass obj 'Array') ((count obj) > 0)) { return true }
  return ((count (fieldNames (classOf obj))) > 0)
}

// tests

to isNumber obj {
  if (isClass obj 'Integer') { return true }
  if (isClass obj 'Float') { return true }
  if (isClass obj 'LargeInteger') { return true }
  return false
}

to isAnyClass obj classNames... {
  // Return true if obj is an instance of one of the given classes.

  for i ((argCount) - 1) {
    if (isClass obj (arg (i + 1))) { return true }
  }
  return false
}

to isOneOf obj items... {
  // Return true if obj is equal to any of the remaining arguments.

  for i ((argCount) - 1) {
    if (obj == (arg (i + 1))) { return true }
  }
  return false
}

// runtime folder

to runtimeFolder subfolder {
  path = 'runtime/'
  if ('iOS' == (platform)) { path = '/runtime/' } // use internal file system
  if (notNil subfolder) { path = (join path subfolder) }
  return path
}

// file loading

to reload fileName {
  // Reload a top level module file. The 'lib/' prefix and '.gp'
  // suffix can be omitted. Example: "reload 'List'"

  if (not (contains (letters fileName) '/')) { fileName = (join (runtimeFolder 'lib/') fileName) }
  if (not (endsWith fileName '.gp')) { fileName = (join fileName '.gp') }
  return (load fileName (topLevelModule))
}

to load fileName module {
  str = (readFile fileName)
  if (isNil str) { error 'Could not read file' fileName }
  return (eval str nil module)
}

// unique names (for files and other things)

to uniqueNameNotIn nameList baseName ext {
  if (isNil ext) { ext = '' }
  if (and (ext != '') (not (beginsWith ext '.'))) { ext = (join '.' ext) }
  i = 2
  result = (join baseName ext)
  while true {
	if (not (contains nameList result)) { return result }
	result = (join baseName i ext)
	i += 1
  }
}

// simple file chooser

to chooseFile fileAction dir extensions x y {
  // Use a sequence popup menus to select a file.
  // Extensions may be either nil (all files), a string, or a list of strings.
  page = (global 'page')
  if (isNil dir) { dir = '.' }
  if (isNil extensions) { extensions = '' }
  if (isNil x) { x = (x (hand page)) }
  if (isNil y) { y = (y (hand page)) }
  dir = (absolutePath dir)
  menu = (menu dir)
  addItem menu 'Parent Folder' (action 'chooseFile' fileAction (parentDir dir) extensions x y)
  addLine menu
  prefix = dir
  if ('/' != prefix) { prefix = (join prefix '/') }
  for subdir (sorted (listDirectories dir)) {
	addItem menu (join '• ' subdir) (action 'chooseFile' fileAction (join prefix subdir) extensions x y)
  }
  addLine menu
  for fn (sorted (listFiles dir)) {
	if (and (fn != '.DS_Store') (hasExtension fn extensions)) {
	  addItem menu fn (action fileAction (join prefix fn))
	}
  }
  addLine menu

  conf = (gpServerConfiguration)
  if (notNil conf) {
    user = (at conf 'username')
    serverDirectory = (at conf 'serverDirectory')
    account = (at conf 'account')
    accountPassword = (at conf 'accountPassword')
  }
  if (and (notNil user) (notNil serverDirectory)) {
    addItem menu 'Server...' (action 'chooseServerFile' fileAction page (join serverDirectory user '/') extensions account accountPassword x y)
  }
  addLine menu
  addItem menu 'cancel' 'ignore'
  popUp menu page x y
}

to gpServerConfiguration {
  // Return a dictionary with the GP server settings or nil if there is no server configuration file

  file = (readFile 'server.conf')
  if (isNil file) { return nil }
  return (jsonParse file)
}

to chooseServerFile fileAction page dir extensions account accountPassword x y {
  menu = (menu dir)
  m = (loadModule 'modules/DAVDirectory.gpm')
  u = (url (initialize (new (at m 'URIParser')) dir))
  c = (new (at m 'DAVClient'))
  setUser c account
  setPassword c accountPassword
  list = (listFiles c u)

  if (notNil list) {
    for fn (toArray list) {
      if (hasExtension fn extensions) {
        addItem menu fn (action fileAction (join dir '/' fn))
      }
    }
  }
  addLine menu
  addItem menu 'cancel' 'ignore'
  popUp menu page x y
}

to hasExtension filename extensions {
	if (isClass extensions 'String') { extensions = (list extensions) }
	for ext extensions {
		if (endsWith filename ext) { return true }
	}
	return false
}

// detecting media file types

to isJPEG data {
	byteCount = (byteCount data)
	if (byteCount < 4) { return false }
	return (and
		(255 == (byteAt data 1))
		(216 == (byteAt data 2))
		(255 == (byteAt data (byteCount - 1)))
		(217 == (byteAt data byteCount)))
}

to isPNG data {
	if ((byteCount data) < 4) { return false }
	return (and
		(137 == (byteAt data 1))
		(80 == (byteAt data 2))
		(78 == (byteAt data 3))
		(71 == (byteAt data 4)))
}

// directory searches

to allFiles rootDir suffix result {
  if (isNil rootDir) { rootDir = '.' }
  if (isNil result) { result = (list) }
  for fileName (listFiles rootDir) {
	if (or (isNil suffix) (endsWith fileName suffix)) {
	  add result (join rootDir '/' fileName)
	}
  }
  for dirName (listDirectories rootDir) {
	allFiles (join rootDir '/' dirName) suffix result
  }
  return result
}

to findProjectsWithString s rootDir {
  for fileName (allFiles rootDir '.gpp') {
	if (projectScriptsIncludesString fileName s) {
	  print fileName
	}
  }
}

to projectScriptsIncludesString projectFileName s {
  proj = (read (new 'ZipFile') (readFile projectFileName true))
  scripts = (toString (extractFile proj 'scripts.txt'))
  return ((find (letters scripts) s) > 0)
}

// benchmarks

to primeSieve flags {
  primeCount = 0
  fillArray flags true
  i = 2
  repeat 8188 {
    if (at flags i) {
      primeCount += 1 // found a prime
      j = (2 * i)
      while (j < 8190) { // mark multiples of i as non-prime
		atPut flags j false
		j += i
      }
    }
    i += 1
  }
  return primeCount
}

to benchFib n {
  if (n < 2) { return 1 }
  return (+ (benchFib (n - 1)) (benchFib (n - 2)) 1)
}

to tinyBenchmarks {
  result = (list)
  flags = (newArray 8190)
  n = 1
  msecs = 0
  while (msecs < 500) {
	timer = (newTimer)
	repeat n { primeSieve flags }
	msecs = (msecs timer)
	n = (2 * n)
  }
  add result (join '' n ' prime sieves in ' msecs ' msecs -- about ' (round ((1000.0 * n) / msecs)) ' sieves/sec')
  add result (join '  (equivalent to ' (round ((n * 500) / msecs) 0.1) ' million Squeak bytcodes per second)')

  n = 20
  msecs = 0
  while (msecs < 500) {
	timer = (newTimer)
	calls = (benchFib n)
	msecs = (msecs timer)
	n += 1
  }
  add result (join '' calls ' calls in ' msecs ' msecs -- ' (round (calls / (1000 * msecs)) 0.2) ' million calls/sec')
  return (joinStrings result (newline))
}

// no-ops

to nop { noop }
to ignore args... { noop }
to id obj { return obj }
