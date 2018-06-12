// Support for block specs and slot information

// The following functions do nothing. They are used to record the block spec
// and slot information associated with a function or method.

defineClass BlockSpec blockType blockOp specs repeatLastSpec slotInfo

classComment BlockSpec '
A BlockSpec object records information about the format, keywords,
input slots, and possible extensions for a given block.

The blockType is one of " " (command), "r" (reporter), "c" (c-shaped)
or "h" (hat block).

A spec string has the text that appears on the block, possibly
with one or more underscore characters indicating input slots.

The specs field holds an array containing one or more spec strings.
The first spec is the base spec for the block. Any additional spec
strings reflect possible extensions of that block. Each extension
spec string have includes one or more input slots and possible additional
text.

If repeatLastSpec is true, the the block can be extended to an
arbibrary length by repeating the final spec as many times as
necessary.

The slotInfo field holds an array of records (arrays) that
define the input slots. Each record holds the slot type (string),
a default value for the slot, an optional hint string, and an
optional menu selector. The current slot types are: num, str, bool,
cmd, var, menu, or any. For slots of type any, the hint string is
displayed as a suggestion to the user (e.g. "list or array").
'

method blockType BlockSpec { return blockType }
method blockOp BlockSpec { return blockOp }
method specs BlockSpec { return specs }
method repeatLastSpec BlockSpec { return repeatLastSpec }
method isHat BlockSpec { return ('h' == blockType) }
method isReporter BlockSpec { return ('r' == blockType) }
method slotCount BlockSpec { return (count slotInfo) }

method hintAt BlockSpec i {
  if (i > (count slotInfo)) { return '' }
  return (at (at slotInfo i) 3)
}

to blockSpecFor function {
  if (isClass function 'String') {
    function = (functionNamed function)
  }
  if (not (isClass function 'Function')) {
    error 'Argument must be a function name or Function'
  }
  return (initializeForFunction (new 'BlockSpec') function)
}

to blockSpecFromStrings blockOp blockType specString typeString defaults {
  specs = (splitWith specString ':')
  for i (count specs) {
    atPut specs i (trim (at specs i))
  }
  repeatLastSpec = false
  if ('...' == (last specs)) {
	repeatLastSpec = true
    specs = (copyArray specs ((count specs) - 1))
  }
  result = (new 'BlockSpec' blockType blockOp specs repeatLastSpec (array))
  setSlotInfo result typeString defaults
  return result
}

method setSlotInfo BlockSpec typeString defaults {
  types = (words typeString)
  for i (count types) {
    parts = (splitWith (at types i) '.')
	if ((count parts) > 1) {
	  atPut types i (joinStringArray parts ' ')
	}
  }
  n = (max (count types) (count defaults) (countAllSpecSlots this))
  slotInfo = (newArray n)
  for i n {
    type = nil
	default = nil
	hint = nil
	menuSelector = nil
	if (i <= (count types)) { type = (at types i) }
	if (i <= (count defaults)) { default = (at defaults i) }
	if (isNil type) {
	  if (isNumber default) {
		type = 'num'
	  } else {
	    type = 'any'
	    if (isClass default 'String') { hint = default }
	    default = nil
	  }
	} else {
	  w = (words type)
	  type = (first w)
	  if ((count w) == 2) {
		menuSelector = (at w 2)
	  }
	  if (not (contains (array 'num' 'str' 'auto' 'bool' 'color' 'cmd' 'var' 'menu') type)) {
		hint = type
		type = 'any'
	  }
	}
    atPut slotInfo i (array type default hint menuSelector)
  }
}

method copyWithOp BlockSpec newOp oldName newName {
  // Return a deep copy of this BlockSpec with newOp as its blockOp and
  // newName substituted for oldName in both spec strings and the slot info.

  result = (clone this)
  setField result 'blockOp' newOp

  newSlotInfo = (copy slotInfo)
  for i (count newSlotInfo) {
	newEntry = (copy (at slotInfo i))
	for j (count newEntry) {
	  if ((at newEntry j) == oldName) {
		atPut newEntry j newName
	  }
	}
	atPut newSlotInfo i newEntry
  }
  setField result 'slotInfo' newSlotInfo

  newSpecs = (copy specs)
  for i (count newSpecs) {
	if ((at newSpecs i) == oldName) {
		atPut newSpecs i newName
	}
  }
  setField result 'specs' newSpecs
  return result
}

method inputSlot BlockSpec slotIndex blockColor isFormalParameter argNames {
  if (isNil isFormalParameter) {isFormalParameter = false}
  info = (slotInfoForIndex this slotIndex)
  editRule = 'static'
  slotType = (at info 1)
  if isFormalParameter {slotType = 'var'}
  slotContent = (at info 3) // hint
  menuSelector = (at info 4)
  if ('num' == slotType) {
    editRule = 'numerical'
    slotContent = (at info 2)
  }
  if ('str' == slotType) {
    editRule = 'editable'
    slotContent = (at info 2)
  }
  if ('auto' == slotType) {
    editRule = 'auto'
    slotContent = (at info 2)
  }
  if ('bool' == slotType) {
    slotContent = (at info 2)
    if (isNil slotContent) {slotContent = true}
    if (not (global 'stealthBlocks')) {
      return (newBooleanSlot slotContent)
    }
  }
  if ('color' == slotType) {
    return (newColorSlot)
  }
  if ('menu' == slotType) {
    slotContent = (at info 2)
  }
  if ('cmd' == slotType) {
    return (newCommandSlot blockColor)
  }
  if ('var' == slotType) {
    if isFormalParameter {
      if (or (isNil argNames) ((count argNames) < slotIndex)) {
        argName = 'args'
      } else {
        argName = (at argNames slotIndex)
      }
      rep = (toBlock (newReporter 'v' argName))
    } else {
      rep = (toBlock (newReporter 'v' (at info 2)))
    }
    setGrabRule (morph rep) 'template'
    return rep
  }
  inp = (newInputSlot slotContent editRule blockColor menuSelector)
  setGrabRule (morph inp) 'ignore'
  return inp
}

method slotInfoForIndex BlockSpec slotIndex {
  if (slotIndex <= (count slotInfo)) {
    return (at slotInfo slotIndex)
  }
  if (not repeatLastSpec) { error 'Slot index is out of range' }
  repeatedSlotCount = (countInputSlots this (last specs))
  if (repeatedSlotCount == 0) { error 'The repeated slot spec must have at least one input slot' }
  repeatedSlotStart = (((count slotInfo) - repeatedSlotCount))
  n = (slotIndex - repeatedSlotStart)
  i = (max 1 ((((n - repeatedSlotStart) % repeatedSlotCount)) + repeatedSlotStart))
  return (at slotInfo i)
}

method initializeForFunction BlockSpec function {
  blockOp = (functionName function)
  blockType = ' '
  if (returnsValue function) { blockType = 'r' }
  collectSpecs this function
  collectSlotInfo this function
  if ((count specs) == 0) { error 'empty spec list' }
  if repeatLastSpec {
    if ((countInputSlots this (last specs)) == 0) {
      error 'no input slots in the repeated last spec'
    }
  }
  return this
}

method collectSpecs BlockSpec function {
  repeatLastSpec = false
  if ((count (argNames function)) > 0) {
    repeatLastSpec = (endsWith (last (argNames function)) '...')
  }
  if (isInfix this function) {
	specs = (array (join '_ ' (functionName function) ' _'))
	return
  }
  if (isNil (functionName function)) {
	parts = (list '')
  }  else {
	parts = (list (separateCamelCase (functionName function)))
  }
  for argName (argNames function) {
	if (not (endsWith argName '...')) {
	  if ('this' != argName) {
		add parts ' '
		add parts argName
	  }
	  add parts ' _'
	}
  }
  specs = (array (joinStringArray (toArray parts)))
  if repeatLastSpec {
	specs = (copyWith specs '_')
  }
}

method isInfix BlockSpec function {
  if ((count (argNames function)) != 2) { return false }
  if (isNil (functionName function)) { return false }
  for ch (letters (functionName function)) {
    if (not (isSymbol ch)) { return false }
  }
  return true
}

method collectSlotInfo BlockSpec function {
  n = (countAllSpecSlots this)
  slotInfo = (newArray n)
  for i n {
    type = 'auto'
	default = 1
	hint = nil
	if (and (i == 1) (isMethod function)) {
	  className = (className (class (classIndex function)))
	  if ('String' == className) {
		default = 'Hello'
	  } ('Boolean' == className) {
		type = 'bool'
		default = false
	  } ('Color' == className) {
		type = 'color'
	  } ('Integer' == className) {
		default = 1
	  } ('Float' == className) {
		default = 1.0
	  } else {
		type = 'any'
		default = nil
		hint = 'this'
	  }
	}
    atPut slotInfo i (array type default hint nil)
  }
}

method countAllSpecSlots BlockSpec {
  // Return the total number input slots in all slot specs.
  return (countInputSlots this (joinStringArray specs))
}

method countInputSlots BlockSpec specString {
  // Return the number of underscores (input slots) in the given string.
  result = 0
  for ch (letters specString) {
	if ('_' == ch) { result += 1 }
  }
  return result
}

method specDefinitionString BlockSpec className {
  // Return a spec definition string for an exported class.
  // The className argument is provided for methods; it is nil for shared functions.

  result = (list 'spec')
  add result (printString blockType)
  add result (printString blockOp)

  specString = ''
  for i (count specs) {
	specString = (join specString (at specs i))
	if (i < (count specs)) { specString = (join specString ' : ') }
  }
  if repeatLastSpec  { specString = (join specString ' : ...') }
  add result (printString specString)

  if (not (isEmpty slotInfo)) {
	slotTypes = (list)
	defaultValues = (list)
	for info slotInfo {
	  slotType = (at info 1)
	  add slotTypes slotType
	  if (isOneOf slotType 'auto' 'str') {
		add defaultValues (printString (at info 2))
	  } (isOneOf slotType 'bool' 'num') {
		add defaultValues (toString (at info 2))
	  } else {
		add defaultValues 'nil'
	  }
	}
	if (notNil className) { atPut slotTypes 1 className } // for methods, first type is the class name
	add result (printString (joinStrings slotTypes ' '))
	for v defaultValues { add result v }
  } else {
	add result (printString '') // empty slot type string
  }
  return (joinStrings result ' ')
}

method updateClassHint BlockSpec aDictionary {
  // Use the given dictionary to map the hint slot of my first slot (the receiver of a method)
  // from and old to new class name if there is an entry for the hint in the given dictionary.

  if (isEmpty slotInfo) { return }
  oldClassName = (at (first slotInfo) 3)
  if (contains aDictionary oldClassName) {
	atPut (first slotInfo) 3 (at aDictionary oldClassName)
  }
}
