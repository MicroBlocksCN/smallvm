defineClass Profile profileArray totalMSecs totalTicks totalEntries callTree primStats leafStats

to profile func args... {
  gc
  args = (newArray ((argCount) - 1))
  for i ((argCount) - 1) {
	atPut args i (arg (i + 1))
  }
  setField (currentTask) 'profileIndex' 1
  setField (currentTask) 'profileArray' (newArray 10000000)
  timer = (newTimer)
  startProfileClock
  callWith func args
  stopProfileClock
  msecs = (msecs timer)
  count = ((getField (currentTask) 'profileIndex') - 1)
  gc
  data = (copyArray (getField (currentTask) 'profileArray') count)
  gc
  return (new 'Profile' data msecs)
}

// String results, for use from command line

method prims Profile {
  if (isNil primStats) { analyzeProfileData this }
  pairs = (reversed (sortedPairs primStats))
  lines = (list 'Primitives:')
  for p pairs {
	n = (at p 1)
	percent = (((10000 * n) / totalTicks) / 100.0)
	add lines (join '  ' (at p 2) ' [' n '] ' (round percent 0.01) '%')
  }
  return (joinStrings lines (newline))
}

method methods Profile {
  if (isNil callTree) { analyzeProfileData this }
  root = callTree
  if ((count (children root)) == 1) { root = (first (children root)) } // skip root if it has only one child
  lines = (list 'Method statistics:')
  addMethodCounts this root 1 lines
  return (joinStrings lines (newline))
}

method addMethodCounts Profile node level lines {
  // Recursive helper function. Add method stats for the
  // given node and all its descendants.
  indent = (joinStringArray (newArray level '   '))
  percent = ((((count node) * 10000) / totalTicks) / 100.0)
  percent = (round percent 0.01) // round to two digits
  if (isEmpty (children node)) {
	add lines (join indent (functionName node) ' [' (count node) '] ' percent '%')
  } else {
	add lines (join indent (functionName node) ' [' (count node) '] ' percent '% {')
	for child (children node) {
	  addMethodCounts this child (level + 1) lines
	}
	add lines (join indent '}')
  }
}

method leaves Profile {
  if (isNil callTree) { analyzeProfileData this }
  lines = (list 'Leaf methods:')
  for p (reversed (sortedPairs leafStats)) {
	fName = (functionName (at p 2))
	if (isNil fName) { fName = '<function>' }
	n = (at p 1)
	percent = (((n * 10000) / totalTicks) / 100.0)
	add lines (join  '  ' fName ' [' n '] ' (round percent 0.01) '%')
  }
  return (joinStrings lines (newline))
}

// View results as a dictionary in an Explorer

method exploreProfile Profile {
  if (isNil callTree) { analyzeProfileData this }
  root = callTree
  if ((count (children root)) == 1) { root = (first (children root)) } // skip root if it has only one child
  result = (dictionary)
  atPut result 'info' (join 'Profile ' totalEntries ' entries ' totalTicks ' ticks in ' totalMSecs ' msecs')
  atPut result 'methods (call tree)' (methodTree this root)
  atPut result 'methods (flat)' (leavesDict this)
  atPut result 'primitives' (primsDict this)
  openExplorer result
}

method methodTree Profile node {
  // Recursive helper function. Return a dictionary for the given node.
  percent = ((((count node) * 10000) / totalTicks) / 100.0)
  label = (join (functionName node) ' [' (count node) ']   '  (round percent 0.01) '%')
  if (isEmpty (children node)) { return label }
  result = (dictionary)
  for child (children node) {
	percent = ((((count child) * 10000) / totalTicks) / 100.0)
	label = (join (functionName child) ' [' (count child) ']   ' (round percent 0.01) '%')
	atPut result label (methodTree this child totalTicks)
  }
  return result
}

method leavesDict Profile {
  result = (dictionary)
  i = 1
  for p (reversed (sortedPairs leafStats)) {
	fnc = (at p 2)
	fName = (functionName fnc)
	if (isNil fName) { fName = '<function>' }
	if (isMethod fnc) {
	  fName = (join fName ' (' (className (class (classIndex fnc))) ')')
	}
	n = (at p 1)
	percent = (((n * 10000) / totalTicks) / 100.0)
	k = (join (withLeadingZeros this i) '   ' fName ' [' n '] ' (round percent 0.01) '%')
	atPut result k n
	i += 1
  }
  return result
}

method primsDict Profile {
  result = (dictionary)
  i = 1
  for p (reversed (sortedPairs primStats)) {
	n = (at p 1)
	percent = (((10000 * n) / totalTicks) / 100.0)
	k = (join (withLeadingZeros this i) '   ' (at p 2) ' [' n '] ' (round percent 0.01) '%')
	atPut result k n
	i += 1
  }
  return result
}

method withLeadingZeros Profile n {
  s = (toString n)
  if (n < 10) {
	s = (join '00' s)
  } (n < 100) {
	s = (join '0' s)
  }
  return s
}

// Profile data processing

method analyzeProfileData Profile {
  // Scan the profileArray, recording the primitive and the call chain for each entry.
  // Each profile entry has the form:
  //	block (Command or Reporter)
  //	tick count (may be > 1 for long-running primitives)
  //	zero or more Functions (the call chain in revere order, possibly truncated).

  totalTicks = 0
  totalEntries = 0
  callTree = (new 'ProfileNode' 'root' 0 (array))
  primStats = (dictionary)
  leafStats = (dictionary)
  end = (count profileArray)
  i = 1
  while (i <= end) {

	block = (at profileArray i)
	ticks = (at profileArray (i + 1))
	totalTicks += ticks
	totalEntries += 1
	i += 2

	if (isClass block 'Function') { error 'Profile data entry should start with a Command or Reporter' }
	add primStats (primName block) ticks

	// Find the start of the next entry
	isLeaf = true
	while (and (i <= end) (isClass (at profileArray i) 'Function')) {
	  if isLeaf { add leafStats (at profileArray i); isLeaf = false }
	  i += 1
	}
	entryEnd = (i - 1)
	recordEntry this ticks entryEnd
  }
  profileArray = nil
}

method recordEntry Profile ticks i {
  // Record the entry with the given ending index. Process function calls in
  // reverse order, which is the original calling order.
  node = callTree
  incrCount node ticks
  while true {
	f = (at profileArray i)
	if (not (isClass (at profileArray i) 'Function')) { return } // done; reached start of this entry
	node = (childFor node f)
	incrCount node ticks
	i += -1
  }
}

defineClass ProfileNode function count children

method function ProfileNode { return function }
method count ProfileNode { return count }
method incrCount ProfileNode ticks { count += ticks }
method children ProfileNode { return children }

method functionName ProfileNode {
  if (isClass function 'String') { return function }
  if (isNil (functionName function)) { return '<function>' }
  if (isMethod function) {
	return (join (functionName function) ' (' (className (class (classIndex function))) ')')
  }
  return (functionName function)
}

method childFor ProfileNode func {
  // Return the child node for the given function. Add a new node for the function if necessary.
  for child children {
	if (func == (function child)) { return child }
  }
  newNode = (new 'ProfileNode' func 0 (array))
  children = (copyWith children newNode)
  return newNode
}
