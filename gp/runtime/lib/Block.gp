// Block
// Handlers for the GP blocks GUI

defineClass Block morph blockSpec type expression labelParts corner color expansionLevel function isAlternative layoutNeeded pathCache cacheW cacheH originalColor

to block type color opName {
  block = (new 'Block')
  scale = (blockScale block)

  if (isNil opName) {opName = 'foo'}
  if (isNil type) {type = 'command'} // type can be 'command', 'reporter' or 'hat'
  if (isNil color) {color = (gray 150)}
  labelParts = (list (list))
  for i ((argCount) - 2) {add (at labelParts 1) (arg (i + 2))}
  if ((count (at labelParts 1)) == 0)  {
    labelParts = (list (list (labelText block opName)))
    op = opName
  } else {
    op = (arg 3)
  }
  group = (at labelParts 1)
  for i (count group) {
    part = (at group i)
    if (isClass part 'String') {
      atPut group i (labelText block part)
    } (isClass part 'Command') {
      inp = (newCommandSlot color)
      atPut group i inp
    }
  }
  argValues = (list op)
  for each group {
    if (isAnyClass each 'InputSlot' 'BooleanSlot' 'ColorSlot' 'CommandSlot' 'MicroBitDisplaySlot') {add argValues (contents each)}
  }
  setField block 'type' type
  setField block 'labelParts' labelParts
  setField block 'color' color
  setField block 'corner' 3
  setField block 'expansionLevel' 1
  setField block 'layoutNeeded' true
  morph = (newMorph block)
  if (type == 'command') {
    setField block 'expression' (callWith 'newCommand' (toArray argValues))
  } (type == 'hat') {
    setField block 'expression' (newCommand 'nop')
  } (type == 'reporter') {
    setField block 'expression' (callWith 'newReporter' (toArray argValues))
  }
  setMorph block morph
  setGrabRule morph 'handle'
  setTransparentTouch morph false
  for each group {addPart (morph block) (morph each)}
  layoutChanged block
  fixLayout block
  return block
}

to slot contents isID {
  if (isNil isID) {isID = false}
  if (isAnyClass contents 'Integer' 'Float') {
    inp = (newInputSlot contents 'numerical')
    setGrabRule (morph inp) 'ignore'
    return inp
  } (isClass contents 'String') {
    inp = (newInputSlot contents 'editable')
    setGrabRule (morph inp) 'ignore'
    return inp
  } (isClass contents 'Boolean') {
    inp = (newBooleanSlot contents)
    return inp
  } (isClass contents 'Color') {
    inp = (newColorSlot contents)
    return inp
  } else {
    inp = (newInputSlot contents 'static')
    setID inp isID
    setGrabRule (morph inp) 'defer'
    return inp
  }
}

to blockScale {
  if (isNil (global 'blockScale')) { setGlobal 'blockScale' 1.25 }
  return ((global 'blockScale') * (global 'scale'))
}

to blockExportScale {
  // This variable is controls the scale of exported script PNG files.

  if (isNil (global 'blockExportScale')) { setGlobal 'blockExportScale' 0.65 } // default
  return (global 'blockExportScale')
}

method fixLayoutNow Block {
  layoutNeeded = true
  fixLayout this
}

method fixLayout Block {
  if (isNil layoutNeeded) { layoutNeeded = true }
  if (not layoutNeeded) { return }
  border = 1
  scale = (blockScale)
  wasHighlighted = false

  if (and (isClass (handler (owner morph)) 'ScriptEditor') (notNil (getHighlight morph))) {
	removeHighlight morph
	wasHighlighted = true
  }

  // fix layout of parts
  for m (parts morph) {
	if (isClass (handler m) 'Block') { fixLayout (handler m) }
	if (isClass (handler m) 'CommandSlot') {
	  nestedBlock = (nested (handler m))
	  if (notNil nestedBlock) { fixLayout nestedBlock }
	  fixLayout (handler m)
	}
	if (isClass (handler m) 'InputDeclaration') {
	  fixLayout (handler m)
	}
  }

  space = 6
  vSpace = 3

  break = 450
  lineHeights = (list)
  lines = (list)
  lineArgCount = 0

  left = ((left morph) + (3 * scale))
  h = 0
  w = 0

  if (type == 'hat') {
    indentation = (* scale (+ border space))
  } (type == 'reporter') {
    indentation = (* scale 6)
  } (type == 'command') {
    indentation = (* scale (+ border space border))
  }

  // arrange label parts horizontally and break up into lines
  op = (primName expression)
  breakLineBeforeFirstArg = (isOneOf op '[display:mbDisplay]' 'setNeoPixelColors10')
  maxArgsPerLine = 6
  if ('setNeoPixelColors10' == op) { maxArgsPerLine = 5 }
  currentLine = (list)
  for group labelParts {
    for each group {
      if (isVisible (morph each)) {
        if (isClass each 'CommandSlot') {
          if (notEmpty currentLine) {
          	add lines currentLine
          	add lineHeights h
          }
          fastSetLeft (morph each) ((+ left (* scale (+ border corner))) + (2 * scale))
          add lines (list each)
          h = (height (morph each))
          if (notNil (wrapHeight each)) { // increase size for wrapping feedback
			h = (wrapHeight each)
			setHeight (bounds (morph each)) h
		  }
          add lineHeights h
          currentLine = (list)
          w = 0
          h = 0
        } else {
          isArgSlot = (and (not (isClass each 'Text')) (not (isClass each 'SVGImage')))
		  // forced break indicated by special label #BR#
		  isForcedBreak = (and (isClass each 'Text') (== (text each) '#BR#'))
		  if isForcedBreak {
			isArgSlot = true
			setColor each (transparent)
		    lineArgCount = 10
		  } else {
			x = (+ left indentation w)
			w += (width (fullBounds (morph each)))
			w += (space * scale)
		  }
          if (and breakLineBeforeFirstArg isArgSlot) {
			breakLineBeforeFirstArg = false // only do this once
 			lineArgCount = 10 // force a line break before first arg
		  }
		  if (and breakLineBeforeFirstArg (each == (first group))) {
			lineArgCount = 10 // force a line break after first item of block
		  }
		  if ('if' == op) { lineArgCount = 0 } // never break 'if' blocks
		  if (and
                (notEmpty currentLine)
                (or (w > (break * scale)) (and isArgSlot (lineArgCount >= maxArgsPerLine)))
            ) {
			if (notEmpty currentLine) {
			  add lines currentLine
			  add lineHeights h
			  currentLine = (list)
			}
            h = 0
			x = (+ left indentation)
			if isForcedBreak {
			  w = 0
			} else {
			  w = ((width (fullBounds (morph each))) + (space * scale))
			}
            lineArgCount = 0
          }
          add currentLine each
          h = (max h (height (morph each)))
          fastSetLeft (morph each) x
		  if isArgSlot { lineArgCount += 1 }
        }
      }
    }
  }

  // add the block drawer, if any
  drawer = (drawer this)
  if (notNil drawer) {
    x = (+ left indentation w)
    w += (width (fullBounds (morph drawer)))
    w += (space * scale)
    if (and (w > (break * scale)) (notEmpty currentLine)) {
      if (notEmpty currentLine) {
		add lines currentLine
		add lineHeights h
		currentLine = (list)
	  }
      h = 0
      x = (+ left indentation)
      w = ((width (fullBounds (morph drawer))) + (space * scale))
    }
    add currentLine drawer
    h = (max h (height (morph drawer)))
    fastSetLeft (morph drawer) x
  }

  // add last line
  if (notEmpty currentLine) {
	add lines currentLine
	add lineHeights h
  }

  // adjust minimum block height for one-line blocks
  if (notEmpty lineHeights) {
    minHeight = (21 * scale)
    atPut lineHeights 1 (max (at lineHeights 1) minHeight)
  }

  // determine blockWidth from line data
  blockWidth = 0
  for each lines {
    if (notEmpty each) {
      elem = (last each)
      if (isClass elem 'CommandSlot') {
        blockWidth = (max blockWidth (56 * scale)) // min size for "forever" and "if"
      } else {
        blockWidth = ((max blockWidth ((right (fullBounds (morph elem))) - left)))
      }
    }
  }
  blockHeight = (callWith + (toArray lineHeights))
  blockHeight += ((count lines) * (vSpace * scale))

  // set vertical position of block labels and inputs (possibly multiple lines of them)
  tp = (+ (top morph) (* 2 scale border) scale)
  if (type == 'hat') { // adjustment for hat blocks
    tp += (hatHeight this)
    if (blockHeight < 24) {
      blockHeight = (28 * scale)
      tp += (4 * scale)
    }
  }
  line = 1
  for eachLine lines {
    bottom = (+ tp (at lineHeights line))
    for each eachLine {
      fastSetYCenterWithin (morph each) tp (bottom + (1 * scale)) // adjust slightly downward
    }
    line += 1
    tp = (bottom + (vSpace * scale))
  }

  // add extra space below the bottom-most c-slot
  extraSpace = 0
  if (isClass (last (last labelParts)) 'CommandSlot') {
	// adjust space below last command slot
	if (isNil drawer) {
	  extraSpace = (7 * scale)
	} else {
	  // adjust layout of final block drawer in if-else block
	  blockHeight += (-6 * scale)
	  fastMoveBy (morph drawer) (-2 * scale) (-5 * scale)
	}
  }

  // adjust block width (i.e. right margin)
  if (type == 'command') {
	blockWidth += (2 * scale)
  } (type == 'hat') {
	blockWidth += (2 * scale)
  } (type == 'reporter') {
	blockWidth += (-4 * scale)
  }

  if (type == 'command') {
    setWidth (bounds morph) (max (scale * 50) (+ blockWidth indentation (3 * scale)))
    setHeight (bounds morph) (+ blockHeight (* scale corner) (* scale border 4) extraSpace)
  } (type == 'hat') {
    setWidth (bounds morph) (max (scale * 100) (+ blockWidth indentation (3 * scale)))
    setHeight (bounds morph) (+ blockHeight (* scale corner 2) (* scale border) (hatHeight this) extraSpace)
  } (type == 'reporter') {
    setWidth (bounds morph) (max (scale * 20) (+ blockWidth indentation (11 * scale)))
    setHeight (bounds morph) (+ blockHeight (* scale border 4) extraSpace)
  }

  if ((localized 'RTL') == 'true') { fixLayoutRTL this }

  nb = (next this)
  if (notNil nb) {
    fastSetPosition (morph nb) (left morph) ((bottom morph) - (scale * (corner + 1)))
  }
  rerender morph
  if wasHighlighted { addHighlight morph }
  layoutNeeded = false
}

method fixLayoutRTL Block {
	block_width = (width morph)
	if (and (notNil expression) ('if' == (primName expression))) {
	  block_width += (15 * (blockScale))
	}
	block_left = (left (fullBounds morph))
	drawer = (drawer this)
	if (notNil drawer) {
		block_width = (block_width - (width (fullBounds (morph drawer))))
		block_width = (block_width - (3 * (blockScale)))
	}

	for group labelParts {
		for each group {
			if (isVisible (morph each)) {
				word_left = ((left (fullBounds (morph each))) - block_left)
				w = (width (fullBounds (morph each)))
				if (not (isClass each 'CommandSlot')) {
					setLeft (morph each) (block_left + ((block_width - word_left) - w))
				}
			}
		}
	}
}

method drawOn Block ctx {
	if (notNil (getField ctx 'surface')) {
		drawShape this (getShapeMaker ctx)
		return
	}

	if (or (isNil pathCache) (cacheW != (width morph)) (cacheH != (height morph))) {
		// update pathCache
		sm = (newShapeMakerForPathRecording)
		drawShape this sm
		pathCache = (recordedPaths sm)
		cacheW = (width morph)
		cacheH = (height morph)
	}
	drawCachedPaths ctx pathCache (left morph) (top morph)
}

method drawShape Block aShapeMaker {
	scale = (blockScale)
	if (isRecording aShapeMaker) {
		r = (rect 0 0 (width morph) (height morph))
	} else {
		r = (bounds morph)
	}
	if (type == 'command') {
		commandSlots = (commandSlots this)
		if (isEmpty commandSlots) {
			drawBlock aShapeMaker r color
		} else {
			drawBlockWithCommandSlots aShapeMaker r commandSlots color
		}
	} (type == 'reporter') {
		radius = (15 * scale) // semi-circular for slot heights up to 30 * blockScale
		clr = color
		if (getAlternative this) { clr = (lighter color 17) }
		drawReporter aShapeMaker r clr radius
	} (type == 'hat') {
		drawHatBlock aShapeMaker r color
	}
}

method commandSlots Block {
	result = (list)
	top = (top morph)
	for m (parts morph) {
		if (isClass (handler m) 'CommandSlot') { add result (list ((top m) - top) ((height m) - (blockScale))) }
	}
	return result
}

method hatHeight Block {
  hw = (80 * (blockScale))
  ru = (hw / (sqrt 2))
  return (truncate (ru - (hw / 2)))
}

// accessing

method type Block {return type}
method scale Block {return (blockScale)}
method blockSpec Block {return blockSpec}
method function Block {return function}
method isPrototype Block {return (notNil function)}

method bottomLine Block {
  scale = (blockScale)
  return ((bottom morph) - (scale * corner))
}

method blockDefinition Block {
  if (isNil function) {return nil}
  if ((count labelParts) < 1) {return nil}
  def = (first (first labelParts))
  if (not (isClass def 'BlockDefinition')) {return nil}
  return def
}

method editedDefinition Block {
  prot = (editedPrototype this)
  if (notNil prot) {
    return (blockDefinition prot)
  }
  return nil
}

method expression Block className {
  if (isPrototypeHat this) {
    prot = (editedPrototype this)
    parms = (toList (argNames (function prot)))
    body = (next this)
    if (notNil body) {
      body = (expression body)
    }
    if (and (notNil className) (isMethod (function prot))) {
      def = (list 'method' (functionName (function prot)) className)
      removeFirst parms
    } else {
      def = (list 'to' (functionName (function prot)))
    }
    addAll def parms
    add def body
    expr = (callWith 'newCommand' (toArray def))
    return expr
  }
  return expression
}

method isPrototypeHat Block {
  if (type != 'hat') {return false}
  inp = (inputs this)
  if ((count inp) < 1) {return false}
  prot = (first inp)
  if (not (isClass prot 'Block')) {return false}
  return (isPrototype prot)
}

method editedPrototype Block {
  if (type != 'hat') {return nil}
  inp = (inputs this)
  if ((count inp) < 1) {return nil}
  prot = (first inp)
  if (not (isClass prot 'Block')) {return nil}
  if (isPrototype prot) {return prot}
  return nil
}

method contents Block {
  // for compatibility with input slots and command slots
  // in case a 'var' type slot has been renamed by the user
  // we might want to refactor 'expression' to 'contents' at some point
  return expression
}

method inputIndex Block anInput {
  idx = 0
  items = (flattened labelParts)

  if (not (isMicroBlocks)) {
    // special case for GP variable assignments
    opName = (primName expression)
    if (or (opName == '=') (opName == '+=')) {
      // transformed assignment blocks represent the variable name as Text,
      // not an InputSlot; in this case, increment the input slot index
      if (and ((count items) > 1) (isClass (at items 2) 'Text')) {idx += 1}
    }
  }

  for each items {
    if (isAnyClass each 'InputSlot' 'BooleanSlot' 'ColorSlot' 'CommandSlot' 'Block' 'MicroBitDisplaySlot') {
      idx += 1
      if (each === anInput) {return idx}
    }
  }
  return nil
}

method inputs Block {
  // disregard variable accessing
  return (filter
    (function each {return (isAnyClass each 'InputSlot' 'BooleanSlot' 'ColorSlot' 'CommandSlot' 'Block' 'MicroBitDisplaySlot')})
    (flattened labelParts)
  )
}

method openCSlot Block {
  for cSlot (flattened labelParts) {
    if (isClass cSlot 'CommandSlot') {
      if (isEmpty (parts (morph cSlot))) {
        return cSlot
      } else {
        return nil
      }
    }
  }
  return nil
}

// events

method justDropped Block hand {
  cancelSelection
  snap this
}

method snap Block {
  scale = (blockScale)
  parent = (handler (owner morph))
  if (isClass parent 'ScriptEditor') {
    b = (targetFor parent this)
    if (and (isClass b 'Block') ((type b) != 'reporter')) { // command or hat type targets
      recordDrop parent this b (next b)
      setNext b this
    } (isClass b 'Array') {
      recordDrop parent this b
      rec = b
      b = (at rec 1)
      dropType = (at rec 2)
      cSlot = (at rec 3)
      if (notNil cSlot) { setWrapHeight cSlot nil }
      if ('top' == dropType) {
        bb = (bottomBlock this)
        setPosition morph (left (morph b)) (+ (scale * corner) ((top (morph b)) - (height (fullBounds (morph this)))))
        setNext bb b
      } ('wrap' == dropType) {
        setNested cSlot b
      }
    } (isClass b 'CommandSlot') {
      recordDrop parent this b (nested b)
      setNested b this
    } (notNil b) { // dropped reporter
      tb = (handler (owner (morph b)))
      if (isClass tb 'Block') {
        recordDrop parent this tb nil b
        replaceInput tb b this
      }
    } else { // no snap target, record drop on scripting area
      recordDrop parent this
      if ('reporter' == type) { fixBlockColor this }
    }
    tb = (topBlock this)
    removeStackPart (morph tb)
    removeHighlight (morph tb)
    if (isClass (handler (owner (morph parent))) 'ScrollFrame') {updateSliders (handler (owner (morph parent)))}
  }
}

method aboutToBeGrabbed Block {
  page = (global 'page')
  if (isNil (owner morph)) {return}
  tb = (topBlock this)
  se = (ownerThatIsA (morph tb) 'ScriptEditor')
  if (notNil se) {
    stopEditing (handler se)
  }
  removeSignalPart (morph tb)
  removeStackPart (morph tb)
  removeHighlight (morph tb)

  hand = (hand page)
  setPosition morph (x hand) (y hand)

  if (or
		(commandKeyDown (keyboard page))
		(controlKeyDown (keyboard page))
  ) {
	// duplicate all with control + grab
	dup = (duplicate this)
	owner = (handler (owner morph))
	if (shiftKeyDown (keyboard page)) {
		// duplicate block with control + shift + grab
		if (notNil (next dup)) {setNext dup nil}
	}
	if (notNil owner) {
		if (isClass owner 'CommandSlot') {
			setNested owner dup
		} (isClass owner 'Block') {
			if ((type dup) == 'reporter') {
				replaceInput owner this dup
			} else {
				setNext owner dup
			}
		} (isClass owner 'ScriptEditor') {
			addPart (morph owner) (morph dup)
		}
	}
  }

  // extract block with shift + grab
  if (and
		(shiftKeyDown (keyboard page))
		(notNil (next this))
  ) {
    extractBlock this true
	return
  }

  parent = (handler (owner morph))
  if (isClass parent 'Block') {
    if (type == 'reporter') {
      revertToDefaultInput parent this
    } else {
      setNext parent nil
    }
  } (isClass parent 'CommandSlot') {
    setNested parent nil
  }
}

method layoutChanged Block origin {
	changed morph
	layoutNeeded = true
	raise morph 'layoutChanged' origin
}

method inputChanged Block aSlotOrReporter {
  value = (contents aSlotOrReporter)
  if (and (isClass aSlotOrReporter 'Block') ('template' == (grabRule (morph aSlotOrReporter)))) {
    varExpr = (expression aSlotOrReporter)
    if (isOneOf (primName varExpr) 'v' 'my') {
      // this is a 'var' slot; use variable name as input
      value = (first (argList varExpr))
    }
  } else {
    // the user has changed the default value of a formal parameter declaration
    id = (ownerThatIsA (morph aSlotOrReporter) 'InputDeclaration')
    if (notNil id) {
      setDefault (handler id) value
      return
    }
  }
  setArg expression (inputIndex this aSlotOrReporter) value
  raise morph 'scriptChanged' this
}

method expressionChanged Block changedBlock {
  if (isPrototype this) {
    return
  } (or (type == 'reporter') ((type changedBlock) == 'reporter')) {
    idx = (inputIndex this changedBlock)
    if (notNil idx) {
      setArg expression idx (expression changedBlock)
      return
    }
  } (changedBlock == (next this)) {
    setField expression 'nextBlock' (expression changedBlock)
    return
  }
  raise morph 'expressionChanged' changedBlock
}

method clicked Block hand {
  if (not (isMicroBlocks)) { return (gpClicked hand) }

  selection = (selection (scripter (findProjectEditor)))
  kbd = (keyboard (page hand))

  if (and (notNil selection) (shiftKeyDown kbd)) {
	toggleAddBlock selection this
	return
  } else {
	cancelSelection
  }

  if (and (contains (array 'template' 'defer') (grabRule morph)) (isRenamableVar this)) {
    userRenameVariable this
    return
  } (isPrototype this) {
    def = (blockDefinition this)
    if (notNil def) {
      return (clicked def hand)
    }
    return true
  } (isPrototypeHat this) {
    prot = (editedPrototype this)
    if (notNil prot) {
      return (clicked prot hand)
    }
  } (isClass (handler (owner morph)) 'BlockOp') {
    return
  }

  topBlock = (topBlock this)
  if (isPrototypeHat topBlock) { return }
  runtime = (smallRuntime)
  if (isRunning runtime topBlock) {
	stopRunningChunk runtime (lookupChunkID runtime topBlock)
  } else {
	evalOnBoard runtime topBlock
  }
}

method gpClicked Block hand {
  tb = (topBlock this)
  kbd = (keyboard (page hand))
  if (shiftKeyDown kbd) {
    scripts = (ownerThatIsA (owner morph) 'ScriptEditor')
    if (notNil scripts) {
      edit (handler scripts) this
      return
    }
  } (and (devMode) (keyDown kbd 'space')) {
    turnIntoText (topBlock this) hand
    return true
  }

  if (and (contains (array 'template' 'defer') (grabRule morph)) (isRenamableVar this)) {
    userRenameVariable this
    return
  } (isPrototype this) {
    def = (blockDefinition this)
    if (notNil def) {
      return (clicked def hand)
    }
    return true
  } (isPrototypeHat this) {
    prot = (editedPrototype this)
    if (notNil prot) {
      return (clicked prot hand)
    }
  } (isClass (handler (owner morph)) 'BlockOp') {
    return
  }

  cmdList = (expression tb)
  // if this block is in a Scripter, run it in the context of the Scriptor's targetObj
  scripter = (ownerThatIsA morph 'Scripter')
  if (notNil scripter) { targetObj = (targetObj (handler scripter)) }

  if (isRunning (page hand) cmdList targetObj) {
    stopRunning (page hand) cmdList targetObj
  } else {
    launch (page hand) cmdList targetObj (action 'showResult' tb)
  }
  return true
}

method doubleClicked Block hand {
  if (isPrototype this) {
    def = (blockDefinition this)
    if (notNil def) {
      closeUnclickedMenu (page hand) this
      return (doubleClicked def hand)
    }
  } (isPrototypeHat this) {
    prot = (editedPrototype this)
    if (notNil prot) {
      return (doubleClicked prot hand)
    }
  }
  return false
}

method showResult Block result {
  if ((type this) == 'reporter') {
	if (isNil result) {result = 'result is missing'}
	showHint morph (printString result) 300
  } (notNil result) {
	showHint morph (printString result) 300
  }
}

method rightClicked Block aHand {
  se = (ownerThatIsA morph 'ScriptEditor')
  if (notNil se) {
    stopEditing (handler se)
  }
  if (isPrototype this) {
    def = (blockDefinition this)
    if (notNil def) {
      return (rightClicked def hand)
    }
  } (isPrototypeHat this) {
    return (rightClicked (editedPrototype this) aHand)
  }
  popUpAtHand (contextMenu this) (page aHand)
  return true
}

method okayToBeDestroyedByUser Block {
  if (isPrototypeHat this) {
	editor = (findProjectEditor)
	if (isNil editor) { return false }
    function = (function (first (inputs this)))
    if (confirm (global 'page') nil 'Are you sure you want to remove this block definition?') {
	  removedUserDefinedBlock (scripter editor) function
      return true
    }
    return false
  }
  return true
}

// stacking

method next Block {
  items = (count (flattened labelParts))
  offset = 1
  if (and (isVariadic this) (not (isPrototype this))) {offset = 2} // because there is also a drawer
  if (notNil (getHighlight morph)) { offset += 1 }
  if ((count (parts morph)) > (items + (offset - 1))) {
    nxt = (handler (at (parts morph) (+ offset items)))
    if (not (isClass nxt 'Block')) { return nil } // guard against return non-blocks
    return (handler (at (parts morph) (+ offset items)))}
  return nil
}

method previous Block {
  parent = (ownerThatIsA (owner morph) 'Block')
  if (notNil parent) {return (handler parent)}
  return nil
}

method setNext Block another {
  scale = (blockScale)
  removeHighlight morph
  if (notNil another) {removeHighlight (morph another)}
  n = (next this)
  if (notNil n) {remove (parts morph) (morph n)}
  if (isNil another) {
    setField expression 'nextBlock' nil
  } else {
    setPosition (morph another) (left morph) ((((top morph) + (height morph)) - (scale * corner)) - (max 1 (blockScale)))
    addPart morph (morph another)
    setField expression 'nextBlock' (expression another)
    if (notNil n) {setNext (bottomBlock another) n}
  }
  if (isPrototypeHat this) {
    prot = (editedPrototype this)
    func = (function prot)
    cmd = nil
    if (isClass another 'Block') {cmd = (expression another)}
    setField func 'cmdList' cmd
    blockStackChanged this
  } else {
    raise morph 'scriptChanged' this
    raise morph 'blockStackChanged' this
  }
}

method blockStackChanged Block another {
  if (isPrototypeHat this) {
    raise morph 'functionBodyChanged' this
    def = (editedDefinition this)
    if (notNil def) {hideDetails def}
  } else {
    raise morph 'blockStackChanged' this
  }
}

method scriptChanged Block {
  if (isPrototypeHat this) {
    raise morph 'functionBodyChanged' this
    def = (editedDefinition this)
    if (notNil def) {hideDetails def}
  } else {
    raise morph 'scriptChanged' this
  }
}

method bottomBlock Block {
  n = (next this)
  if (isNil n) {return this}
  return (bottomBlock n)
}

method topBlock Block {
  if (isNil (owner morph)) { return this }
  t = (handler (owner morph))
  if (isAnyClass t 'Block' 'CommandSlot') {return (topBlock t)}
  return this
}

method stackList Block {
  stack = (list)
  current = this
  while (notNil current) {
    add stack current
    current = (next current)
  }
  return stack
}

method scriptEditor Block {
  se = (handler (owner (morph (topBlock this))))
  if (isClass se 'ScriptEditor') {return se}
  return nil
}

// nesting (inputs)

method replaceInput Block source target {
  if (notNil (owner (morph target))) {removePart (owner (morph target)) (morph target)}
  idx = (indexOf (parts morph) (morph source))
  if (isNil idx) {  // can happen when call has more parameters than prototype has slots
    print 'skipping extra input'
    return
  }
  replaceLabelPart this source target
  atPut (parts morph) idx (morph target)
  setOwner (morph target) morph
  setOwner (morph source) nil
  if (isClass source 'Block') {
    editor = (scriptEditor this)
    addPart (morph editor) (morph source)
    moveBy (morph source) 20 20
  }
  if (isAnyClass target 'InputSlot' 'BooleanSlot' 'ColorSlot') {
    setArg expression (inputIndex this target) (contents target)
  } (isClass target 'Block') {
    setArg expression (inputIndex this target) (expression target)
  }
  layoutChanged this
  if (isClass target 'Block') { fixBlockColor target }
  raise morph 'scriptChanged' this
}

method replaceLabelPart Block source target {
  // private - helper for replaceInput
  for group labelParts {
    for i (count group) {
      if ((at group i) === source) {
        atPut group i target
        return
      }
    }
  }
  error 'label part not found'
}

method revertToDefaultInput Block aReporter {
  oldX = (left (morph aReporter))
  oldY = (top (morph aReporter))
  if (isNil blockSpec) {
    replaceInput this aReporter (slot 10)
  } else {
    replaceInput this aReporter (inputSlot blockSpec (inputIndex this aReporter) color)  }
  setPosition (morph aReporter) oldX oldY
}

// context menu

method contextMenu Block {
  if (not (isMicroBlocks)) { return (gpContextMenu this) }

  if (isPrototype this) {return nil}
  menu = (menu nil this)
  
  pe = (findProjectEditor)
  scripter = (scripter pe)
  selection = (selection scripter)
  if (and (notNil selection) (notEmpty selection)) {
  	return (contextMenu selection)
  }

  isInPalette = ('template' == (grabRule morph))
  if (and isInPalette (isRenamableVar this)) {
    addItem menu 'rename...' 'userRenameVariable'
    addLine menu
  }
  addItem menu 'duplicate' 'grabDuplicate' 'duplicate this block'
  if (and ('reporter' != type) (notNil (next this))) {
    addItem menu 'duplicate all' 'grabDuplicateAll' 'duplicate this block and all blocks below it'
  }
  addLine menu
  if (and (not isInPalette) ('reporter' != type)) {
    addItem menu 'extract block' 'extractBlock' 'pull out this block'
  }
  addLine menu
  if (hasHelpEntryFor pe this) {
    addItem menu 'help' (action 'openHelp' pe this) 'show help for this block in a browser'
    addLine menu
  }
  addItem menu 'copy to clipboard' (action 'copyToClipboard' (topBlock this)) 'copy these blocks to the clipboard'
  addItem menu 'copy to clipboard as URL' (action 'copyToClipboardAsURL' (topBlock this)) 'copy these blocks to the clipboard as a URL'
  addLine menu
  addItem menu 'save picture of script' 'exportAsImage' 'save a picture of these blocks as a PNG file'
  if (not (isPrototypeHat (topBlock this))) {
	if (or ('reporter' == (type (topBlock this))) (devMode)) {
	  addItem menu 'save picture of script with result' 'exportAsImageWithResult' 'save a picture of these blocks and their result as a PNG file'
	}
  }
  if (devMode) {
	addLine menu
    addItem menu 'show instructions' (action 'showInstructions' (smallRuntime) this)
    addItem menu 'show compiled bytes' (action 'showCompiledBytes' (smallRuntime) this)
    if (and isInPalette (notNil (functionNamed (project pe) (primName expression)))) {
	  addItem menu 'show call tree' (action 'showCallTree' (smallRuntime) this)
    }

	// xxx internal testing only; remove later!:
	if (contains (commandLine) '--allowMorphMenu') {
		addItem menu 'test decompiler' (action 'testDecompiler' (smallRuntime) this) // xxx
	}
  }
  addLine menu

  if (contains (array 'v' '=' '+=') (primName expression)) {
	  addItem menu 'find variable accessors' 'findVarAccessors' 'find scripts or block definitions where this variable is being read'
	  addItem menu 'find variable modifiers' 'findVarModifiers' 'find scripts or block definitions where this variable is being set or changed'
  } else {
	  addItem menu 'find uses of this block' 'findBlockUsers' 'find scripts or block definitions using this block'
  }
  if (notNil (functionNamed (project pe) (primName expression))) {
    addItem menu 'show block definition...' 'showDefinition' 'show the definition of this block'
	if isInPalette {
	  addLine menu
	  addItem menu 'delete block definition...' 'deleteBlockDefinition' 'delete the definition of this block'
	}
  } (and (notNil blockSpec) (beginsWith (at (specs blockSpec) 1) 'obsolete')) {
	  addLine menu
	  addItem menu 'delete obsolete block...' 'deleteObsolete' 'delete this obsolete block from the project'
  }
  if ((primName expression) == 'v') {
	varNames = (allVariableNames (project scripter))
	if (and (not isInPalette) ((count varNames) > 1)) {
		for varName varNames {
			if (or ((at varName 1) != '_') (showHiddenBlocksEnabled pe)) {
				b = (toBlock (newReporter 'v' varName))
				fixLayout b
				addItem menu (fullCostume (morph b)) (action 'changeVar' this varName)
			}
		}
	}
  } else {
	alternativeOps = (alternateOperators this)
	if (and (not isInPalette) (notNil alternativeOps)) {
		addLine menu
		myOp = (primName expression)
		for op alternativeOps {
		  // create and display block morph (with translated spec)
		  spec = (specForOp (authoringSpecs) op)
		  if (and (notNil spec) (op != myOp)) {
			b = (blockForSpec spec)
			fixLayout b
			addItem menu (fullCostume (morph b)) (action 'changeOperator' this op)
		  }
		}
	}
  }
  if (not isInPalette) {
	addLine menu
	addItem menu 'delete block' 'delete' 'delete this block'
  }
  return menu
}

method gpContextMenu Block {
  if (isPrototype this) {return nil}
  menu = (menu nil this)
  isInPalette = ('template' == (grabRule morph))
  addItem menu 'explore result' 'explore'
  if (canShowMonitor this) {
    addItem menu 'monitor' 'addMonitor'
  }
  addLine menu
  if (isVariadic this) {
    if (canExpand this) {addItem menu 'expand' 'expand'}
    if (canCollapse this) {addItem menu 'collapse' 'collapse'}
    addLine menu
  }
  if (and isInPalette (isRenamableVar this)) {
    addItem menu 'rename...' 'userRenameVariable'
    addLine menu
  }
  addItem menu 'duplicate' 'grabDuplicate' 'just this one block'
  if (and ('reporter' != type) (notNil (next this))) {
    addItem menu '...all' 'grabDuplicateAll' 'duplicate including all attached blocks'
  }
  addItem menu 'copy to clipboard' 'copyToClipboard'
  addItem menu 'export as image' 'exportAsImage'
  addLine menu
  addItem menu 'show definition...' 'showDefinition'
  addLine menu
  if isInPalette {
	proj = (project (findProjectEditor))
	if (isUserDefinedBlock proj this) {
	  addLine menu
	  if (showingAnExtensionCategory proj this) {
		addItem menu 'remove from palette' (action 'removeFromCurrentCategory' proj this)
	  } else {
		addItem menu 'export to palette...' (action 'exportToExtensionCategory' proj this)
	  }
	}
  }
  if (devMode) {
    addLine menu
    addItem menu 'implementations...' 'browseImplementors'
    addItem menu 'text code...' 'editAsText'
  }
  if (not isInPalette) {
    addLine menu
    addItem menu 'delete' 'delete'
  }
  return menu
}

method grabDuplicate Block {
  dup = (duplicate this)
  if (notNil (next dup)) {setNext dup nil}
  grabTopLeft (morph dup)
}

method grabDuplicateAll Block {
  grabTopLeft (morph (duplicate this))
}

method duplicate Block {
  def = (blockDefinition this)
  if (notNil def) {
    op = (op def)
    spec = (specForOp (authoringSpecs) op)
    if (isNil spec) {spec = (blockSpecFor function)}
    return (blockForSpec spec) spec
  }

  if (notNil blockSpec) {
    dup = (new 'Block')
    initializeForSpec dup blockSpec true
    initializeForNode dup (copy expression)
  } else {
    dup = (toBlock (copy expression))
  }
  fixLayout dup
  setPosition (morph dup) (left morph) (top morph)
  return dup
}

method extractBlock Block whileGrabbing {
  cancelSelection
  whileGrabbing = (whileGrabbing == true)
  if ('reporter' != type) { // hat or command
    nxt = (next this)
    if (and (notNil nxt) (notNil (owner morph))) {
      prev = (ownerThatIsA (owner morph) 'Block')
      cslot = (ownerThatIsA (owner morph) 'CommandSlot')
      scripts = (ownerThatIsA (owner morph) 'ScriptEditor')
      if (and (notNil prev) (=== this (next (handler prev)))) {
        setNext this nil
		if whileGrabbing {
			// needed while grabbing or we end up in an infinite recursion
			setNext (handler prev) nil
		}
		setNext (handler prev) nxt
      } (and (notNil cslot) (=== this (nested (handler cslot)))) {
        setNext this nil
		if whileGrabbing {
			// needed while grabbing or we end up in an infinite recursion
			setNested (handler cslot) nil
		}
        setNested (handler cslot) nxt
      } (notNil scripts) {
        addPart scripts (morph nxt)
        fixBlockColor nxt
      }
      setNext this nil
    }
  }
  if (not whileGrabbing) { grabTopLeft morph }
}

method copyToClipboard Block {
  setClipboard (scriptText this)
}

method copyToClipboardAsURL Block {
  setClipboard (join
    'https://microblocks.fun/run/microblocks.html#scripts='
	(urlEncode (scriptText this) true)
  )
}

method scriptText Block useSemicolons {
  // Note: scriptText is also called by exportAsImageScaled when saving PNG files.

  if (not (isMicroBlocks)) { return (gpScriptText this) }

  mbScripter = (handler (ownerThatIsA morph 'MicroBlocksScripter'))
  return (scriptStringFor mbScripter this)
}

method gpScriptText Block useSemicolons {
  useSemicolons = (useSemicolons == true) // useSemicolons is an optional parameter
  pp = (new 'PrettyPrinter')
  if useSemicolons {
    useSemicolons pp
    result = (list)
  } else {
    result = (list 'GP Script' (newline))
  }
  add result (join 'script 10 10 ')
  if (isClass expression 'Reporter') {
	if (isOneOf (primName expression) 'v') {
      varName = (first (argList expression))
      if (varMustBeQuoted varName) {
        varName = (printString varName) // enclose varName in quotes
      }
	  add result (join '(v ' varName ')')
	} else {
	  add result (join '(' (prettyPrint pp expression) ')')
	}
    if (not useSemicolons) { add result (newline) }
  } else {
	add result '{'
    if (not useSemicolons) { add result (newline) }
    add result (prettyPrintList pp expression)
    add result '}'
    if (not useSemicolons) { add result (newline) }
  }
  if (not useSemicolons) { add result (newline) }
  return (joinStrings result)
}

method exportAsImage Block { exportAsImageScaled (topBlock this) }
method exportAsImageWithResult Block { exportScriptImageWithResult (smallRuntime) this }

method exportAsImageScaled Block result isError fName {
  // Save a PNG picture of the given script at the given scale.
  // If result is not nil, include a speech bubble showing the result.

  timer = (newTimer)

  // if block is a function definition hat use its prototype block
  if (isPrototypeHat this) {
	proto = (editedPrototype this)
	if (notNil proto) { this = proto }
  }

  // draw script and bubble at high resolution
  oldScale = (global 'scale')
  setGlobal 'scale' 2 // change global scale temporarily to ensure retina resolution

  // use given block scale
  oldBlockScale = (global 'blockScale')
  scale = (blockExportScale)
  setGlobal 'blockScale' scale

  if (notNil (function this)) {
	scaledScript = (scriptForFunction (function this))
  } else {
    scaledScript = (toBlock (expression this))
  }
  fixLayout scaledScript
  bnds = (fullBounds (morph scaledScript))
  scriptW = (width bnds)
  scriptH = (height bnds)
  if ('reporter' == type) {
    scriptH += (2 * (blockScale)) // padding to align reporter and command block bottoms in Wiki
  }

  // draw the result bubble, if any
  if (notNil result) {
	scaledBubble = (newBubble result 200 'right' isError)
	bubbleW = (width (fullBounds (morph scaledBubble)))
	bubbleH = (height (fullBounds (morph scaledBubble)))
	bubbleInsetX = (5 * scale)
	bubbleInsetY = (5 * scale)
	if ('hat' == type) { bubbleInsetY = ((half (height morph)) + (3 * scale)) }
  } else {
	bubbleW = 0
	bubbleH = 0
	bubbleInsetX = 0
	bubbleInsetY = 0
  }

  // add an extra pixel all around to allow for anti-aliasing
  scriptW += 2
  scriptH += 2

  // combine the morph and result bubble, if any
  bm = (newBitmap (+ scriptW bubbleW (- bubbleInsetX)) (+ scriptH bubbleH (- bubbleInsetY)) (gray 255 0))
  ctx = (newGraphicContextOn bm)
  setOffset ctx 1 ((bubbleH - bubbleInsetY) + 1) // inset by one pixel for anti-aliasing
  fullDrawOn (morph scaledScript) ctx
  if (notNil scaledBubble) {
	topMorphWidth = (width (morph scaledScript))
    adjustment = (round (6 * scale)) // needed because bubble bounds is slightly too large
	setOffset ctx ((topMorphWidth - bubbleInsetX) + adjustment) (- adjustment)
	fullDrawOn (morph scaledBubble) ctx
	if ('hat' == type) { bm = (cropTransparent bm) } // remove extra space
  }

  // revert to old scale
  setGlobal 'blockScale' oldBlockScale
  setGlobal 'scale' oldScale

  // save result as a PNG file
  pngData = (encodePNG bm nil (scriptText this))
  if ('Browser' == (platform)) {
    if ((msecs timer) > 4500) {
      // if it has been more than ~4.5 seconds the user must click to allow file save
      inform (global 'page') (localized 'PNG preparation complete.')
    }
	browserWriteFile pngData (join 'scriptImage' (msecsSinceStart) '.png') 'scriptImage'
  } else {
  	if (isNil fName) {
  	  fName = (fileToWrite (join 'scriptImage' (msecsSinceStart) '.png'))
  	}
    if ('' == fName) { return }
	writeFile fName pngData
  }
}

method delete Block {
  if ('reporter' != type) { // hat or command
    nxt = (next this)
    if (and (notNil nxt) (notNil (owner morph))) {
      prev = (ownerThatIsA (owner morph) 'Block')
      cslot = (ownerThatIsA (owner morph) 'CommandSlot')
      scripts = (ownerThatIsA (owner morph) 'ScriptEditor')
      if (and (notNil prev) (=== this (next (handler prev)))) {
        setNext this nil
        setNext (handler prev) nxt
      } (and (notNil cslot) (=== this (nested (handler cslot)))) {
        setNext this nil
        setNested (handler cslot) nxt
      } (notNil scripts) {
        addPart scripts (morph nxt)
      }
    }
  }
  aboutToBeGrabbed this
  removeFromOwner morph
}

method editAsText Block {
  openWorkspace (page morph) (toTextCode this)
}

method turnIntoText Block hand {
  scale = (blockScale)
  owner = (owner morph)
  if (or (isNil owner) (not (isClass (handler owner) 'ScriptEditor'))) {return}
  code = (toTextCode this)
  x = (left morph)
  y = (top morph)
  txt = (newText code 'Arial' ((global 'scale') * 12) (color))
  setEditRule txt 'code'
  setGrabRule (morph txt) 'ignore'
  addSchedule (global 'page') (newAnimation 1.0 0.7 200 (action 'setScaleAround' morph (left morph) (top morph)) (action 'swapTextForBlock' (handler owner) txt this hand) true)
}

method toTextCode Block {
  scripter = (ownerThatIsA morph 'Scripter')
  if (notNil scripter) {
    className = (className (classOf (getField (handler scripter) 'targetObj')))
  }
  pp = (new 'PrettyPrinter')
  code = ''
  nb = (expression this className)
  useBrackets = (and (isClass nb 'Command') (not (isControlStructure nb)))
  if useBrackets { code = (join '{' (newline)) }
  while (notNil nb) {
    code = (join code (prettyPrint pp nb) (newline))
    nb = (nextBlock nb)
  }
  if useBrackets {
  	code = (join code '}')
  } (type == 'reporter') {
	code = (substring code 1 ((count code) - 1)) // remove line break
	code = (join '(' code ')')
  }
  return code
}

method browseImplementors Block {
  name = (primName expression)
  implementors = (implementors name)
  menu = (menu (join 'implementations of' (newline) name) (action 'openClassBrowser' this) true) // reverse call
  for each implementors {
    addItem menu (join each '...') each
  }
  popUpAtHand menu (global 'page')
}

method openClassBrowser Block className {
  if ('<generic>' == className) {
	page = (global 'page')
	brs = (newClassBrowser)
	setPosition (morph brs) (x (hand page)) (y (hand page))
	addPart page brs
    browse brs (globalBlocksName brs) (functionNamed (primName expression) (topLevelModule))
    return
  }
  editor = (ownerThatIsA morph 'ProjectEditor')
  if (notNil editor) {
	cl = (classNamed (module (project (handler editor))) className)
  }
  if (isNil cl) { cl = (class className) }
  browseClass cl (primName expression)
}

method showDefinition Block {
  if (not (isMicroBlocks)) { return gpShowDefinition this }
  pe = (findProjectEditor)
  if (isNil pe) { return }
  showDefinition (scripter pe) (primName expression)
}

method gpShowDefinition Block {
  pe = (findProjectEditor)
  if (isNil pe) { return }
  scripter = (scripter pe)
  targetClass = (targetClass scripter)
  if (isNil targetClass) { return }
  calledFunction = (primName expression)

  if (not (isShowingDefinition this targetClass calledFunction)) {
	if (notNil (methodNamed targetClass calledFunction)) {
	  ref = (newCommand 'method' calledFunction (className targetClass))
	} else {
	  f = (functionNamed (module (project pe)) calledFunction)
	  if (isNil f) { return } // shouldn't happen
	  ref = (newCommand 'to' calledFunction)
	}

	// add the method/function definition to the scripts for targetClass
	entry = (array (rand 50 200) (rand 50 200) ref)
	setScripts targetClass (join (array entry) (scripts targetClass))
	restoreScripts scripter
  }
  scrollToDefinitionOf scripter calledFunction
}

method isShowingDefinition Block aClass calledFunction {
  if (isNil (scripts aClass)) { return false }
  for entry (scripts aClass) {
	cmd = (at entry 3) // third item of entry is command
	if (isOneOf (primName cmd) 'method' 'to') {
	  if (calledFunction == (first (argList cmd))) { return true }
	}
  }
  return false // not found
}

// monitors

method canShowMonitor Block {
  if (or ('reporter' != type) (isPrototype this)) { return false }
  op = (primName expression)
  if (and (isOneOf op 'v' 'my') (notNil (ownerThatIsA morph 'Scripter'))) {
	// can only show monitors on instance variables (not locals)
	varName = (first (argList expression))
	scripter = (ownerThatIsA morph 'Scripter')
	return (and (notNil scripter) (hasField (targetObj (handler scripter)) varName))
  }
  if (isOneOf op 'global' 'shared') { return true }
  return ((count (argList expression)) == 0)
}

method addMonitor Block {
  monitor = (makeMonitor this)
  if (isNil monitor) { return }
  step monitor
  setCenter (morph monitor) (handX) (handY)
  grab (hand (global 'page')) monitor
}

method makeMonitor Block {
  targetObj = nil
  scripter = (ownerThatIsA morph 'Scripter')
  if (isNil scripter) { scripter = (ownerThatIsA morph 'MicroBlocksScripter') }
  if (notNil scripter) { targetObj = (targetObj (handler scripter)) }
  op = (primName expression)
  monitorColor = (blockColorForOp (authoringSpecs) op)
  if (isOneOf op 'v' 'my') {
	varName = (at (argList expression) 1)
	if (and ('this' == varName) (notNil targetObj)) {
	  getter = (action 'id' targetObj)
	  return (newMonitor varName getter monitorColor)
	} (hasField targetObj varName) {
	  getter = (action 'getFieldOrNil' targetObj varName)
	  return (newMonitor (join 'my ' varName) getter monitorColor)
	}
  } ('shared' == op) {
	mod = nil
	if (notNil scripter) { mod = (targetModule (handler scripter)) }
	varName = (at (argList expression) 1)
	getter = (action 'shared' varName mod)
	return (newMonitor varName getter monitorColor)
  } ('global' == op) {
	varName = (at (argList expression) 1)
	getter = (action 'global' varName)
	return (newMonitor varName getter monitorColor)
  } (beginsWith op 'self_') {
	if (isNil targetObj) { return nil }
	getter = (action 'eval' op targetObj)
	label = (first (specs (blockSpec this)))
	return (newMonitor label getter monitorColor)
  } else {
	label = (first (specs (blockSpec this)))
	return (newMonitor label (action op) monitorColor)
  }
  return nil
}

method explore Block {
  page = (global 'page')
  targetObj = nil
  scripter = (ownerThatIsA morph 'Scripter')
  if (notNil scripter) { targetObj = (targetObj (handler scripter)) }

  op = (primName expression)
  if (isOneOf op 'v' 'my') {
	varName = (at (argList expression) 1)
	if (and ('this' == varName) (notNil targetObj)) {
	  obj = targetObj
	} (hasField targetObj varName) {
	  obj = (call 'getField' targetObj varName)
	}
	openExplorer obj
  } else {
	// evaluate as a task so errors give debugger
	cmd = (expression (topBlock this))
	launch page cmd targetObj (action 'openExplorer')
  }
}

// renaming variable getters

method isRenamableVar Block {
  return (and
    (notNil expression)
    ('reporter' == type)
    (isOneOf (primName expression) 'v' 'my')
    (or
      (== 'handle' (grabRule morph))
      (and
        (contains (array 'template' 'defer') (grabRule morph))
        (isAnyClass (handler (owner morph)) 'Block' 'BlockSectionDefinition' 'InputDeclaration')
      )
    )
  )
}

method isReceiverSlotTemplate Block {
  sec = (owner morph)
  if (isClass (handler sec) 'BlockSectionDefinition') {
    def = (owner sec)
    if (isClass (handler def) 'BlockDefinition') {
      if (1 == (indexOf (parts def) sec)) {
        func = (function (handler (owner def)))
        if (not (isMethod func)) {
          return false
        }
        return (2 == (indexOf (parts sec) morph))
      }
    }
  }
  return false
}

method userRenameVariable Block {
  if  (or (not (isRenamableVar this)) (isReceiverSlotTemplate this)) {return}
  freshPrompt (page morph) 'Variable Name?' (at (argList expression) 1) 'line' (action 'renameVariableTo' this)
}

method renameVariableTo Block varName {
  if (or (isNil varName) (== '' varName) (not (isRenamableVar this))) {return}
  oldName = (at (argList expression) 1)
  setArg expression 1 varName
  setText (at (at labelParts 1) 1) varName
  layoutChanged this

  if (notNil (ownerThatIsA morph 'BlockSectionDefinition')) {
    raise morph 'updateBlockDefinition'
    return
  }

  raise morph 'inputChanged' this

  // update the function
  if (notNil (owner morph)) {func = (function (handler (owner morph)))}
  if (isNil func) {return}
  idx = (indexOf (argNames func) oldName)
  atPut (argNames func) idx varName
}

// constructing blocks from commands and reporters

to toBlock commandOrReporter {
  block = (new 'Block')
  initialize block commandOrReporter
  layoutChanged block
  fixLayout block
  return block
}

method isMathOperator Block aString {
  return (isOneOf aString '=' '+' '/' '×' '−' '≠' // last three: unicode multiply, minus, not equals
	'<' '<=' '=' '>=' '>' '&' '|' '^' '~' '<<' '>>')
}

method labelText Block aString {
  scale = (blockScale)
  fontName = 'Arial Bold'
  fontSize = (14 * scale)
  if (isMathOperator this aString) { fontSize += (2 * scale) }
  isSVG = (beginsWith aString '#SVG#')
  labelColor = (global 'blockTextColor')
  if (isNil labelColor) { labelColor = (gray 255) }
  
  if (and (notNil blockSpec) ('comment' == (blockOp blockSpec))) { labelColor = (gray 80) }
  if isSVG {
    return (newSVGImage (substring aString 6) labelColor color scale)
  }
  if ('Linux' == (platform)) {
    fontName = 'Noto Sans Bold'
    fontSize = (11 * scale)
  }
  return (newText aString fontName fontSize labelColor)
}

method rawInitialize Block commandOrReporter {
  // disregard any block spec, e.g. if none is found

  scale = (blockScale)
  cslots = (list)
  expression = commandOrReporter
  op = (primName expression)
  type = 'command'
  if (isClass expression 'Reporter') { type = 'reporter' }
  setBlockColor this (primName expression)

  morph = (newMorph this)
  setGrabRule morph 'handle'
  setTransparentTouch morph false
  labelParts = (list (list (labelText this (primName expression))))
  group = (at labelParts 1)
  corner = 3
  expansionLevel = 1

  for each (argList expression) {
    if (isClass each 'Command') {
      element = (newCommandSlot color (toBlock each))
      add cslots element
    } (isClass each 'Reporter') {
      element = (toBlock each)
    } else {
      element = (slot each)
    }
    add group element
  }

  // special cases for variables and assignment
  if (isOneOf op 'v' 'my') {
    s = (at (argList expression) 1)
    if ('my' == op) { s = (join 'my ' s) }
    labelParts = (list (list (labelText this s)))
    group = (at labelParts 1)
  }
  if (isOneOf op '=' '+=') {
    varName = (at (argList expression) 1)
    if ('=' == op) {
      labelParts = (list (list (labelText this 'set') (labelText this varName) (labelText this 'to')))
    } else {
      labelParts = (list (list (labelText this 'increase') (labelText this varName) (labelText this 'by')))
    }
    group = (at labelParts 1)
    rhs = (at (argList expression) 2)
    if (isClass rhs 'Reporter') {
      add group (toBlock rhs)
    } else {
      add group (slot rhs)
    }
  }

  for p group { addPart morph (morph p) }
  if (and (type != 'reporter') (notNil (nextBlock expression))) {
    addPart morph (morph (toBlock (nextBlock expression)))
  }
}

method initializeForNode Block commandOrReporter {
  expandTo this commandOrReporter
  slots = (inputs this)
  idx = 0
  for each (argList commandOrReporter) {
    idx += 1
	if (idx <= (count slots)) {
	  slot = (at slots idx)
	} else {
	  slot = (newInputSlot each 'auto')
	}
    if (isClass each 'Command') {
      if (isClass slot 'CommandSlot') {
        setNested slot (toBlock each)
      } else {
        // perhaps we should somehow warn the user here
        replaceInput this slot (newCommandSlot color (toBlock each)) false
      }
    } (isClass each 'Reporter') {
      if (and ('colorSwatch' == (primName each)) (isClass slot 'ColorSlot')) {
        setContents slot (eval each)
      } else {
        replaceInput this slot (toBlock each) false
      }
    } else {
      if (isAnyClass slot 'InputSlot' 'BooleanSlot' 'ColorSlot' 'MicroBitDisplaySlot') {
        setContents slot each true
      } (and (isClass slot 'Block') (isRenamableVar slot)) {
        renameVariableTo slot each
      } (notNil each) {
        error 'cannot set contents of' slot
      }
    }
  }

  // special case for variables
  if (isOneOf (primName commandOrReporter) 'v' 'my') {
    s = (at (argList commandOrReporter) 1)
    if ('my' == op) { s = (join 'my ' s) }
    labelParts = (list (list (labelText this s)))
    removeAllParts morph
    addPart morph (morph (at (at labelParts 1) 1))
  }

  if (and (type != 'reporter') (notNil (nextBlock commandOrReporter))) {
    addPart morph (morph (toBlock (nextBlock commandOrReporter)))
  }
  expression = commandOrReporter
  layoutChanged this
}

method initialize Block commandOrReporter {
  op = (primName commandOrReporter)
  // special case for variables
  if (isOneOf (primName commandOrReporter) 'v' 'my') {
    rawInitialize this commandOrReporter
    s = (at (argList commandOrReporter) 1)
	if ('my' == op) { s = (join 'my ' s) }
    labelParts = (list (list (labelText this s)))
    removeAllParts morph
    addPart morph (morph (at (at labelParts 1) 1))
    expression = commandOrReporter
    layoutChanged this
    return
  }

  spec = (specForOp (authoringSpecs) op commandOrReporter)
  if (and (notNil spec) ((slotCount spec) < (count (argList commandOrReporter))) (not (repeatLastSpec spec))) {
    spec = nil // ignore bad spec: not enough input slots and not expandable
  }
  if (isNil spec) {
    rawInitialize this commandOrReporter
    layoutChanged this
    return
  }
  initializeForSpec this spec true true
  initializeForNode this commandOrReporter
}

to blockForFunction aFunction {
  spec = (specForOp (authoringSpecs) (primName aFunction))
  if (isNil spec) {
	cl = nil
	if ((classIndex aFunction) > 0) { cl = (class (classIndex aFunction)) }
	spec = (blockSpecFor aFunction)
  }
  return (blockForSpec spec)
}

to blockForSpec spec {
  block = (new 'Block')
  spec = (translateToCurrentLanguage (authoringSpecs) spec)
  initializeForSpec block spec
  return block
}

to scriptForFunction aFunction {
  if (isNil aFunction) { return nil }
  hatLabel = (localized 'define')
  if (isMethod aFunction) { hatLabel = 'method' }
  block = (block 'hat' (color 140 0 140) hatLabel (blockPrototypeForFunction aFunction))
  if (notNil (cmdList aFunction)) {
	setNext block (toBlock (cmdList aFunction))
  }
  return block
}

to blockPrototypeForFunction aFunction {
  spec = (specForOp (authoringSpecs) (primName aFunction))
  if (isNil spec) {
	spec = (blockSpecFor aFunction)
  }
  clr = (blockColorForOp (authoringSpecs) (primName aFunction))
  block = (block (blockType (blockType spec)) clr (newBlockDefinition spec (argNames aFunction) (not (isMethod aFunction))))
  setField block 'function' aFunction
  setGrabRule (morph block) 'template'
  return block
}

method initializeForSpec Block spec suppressExpansion {
  scale = (blockScale)

  blockSpec = spec
  type = 'command'
  if (isHat spec) { type = 'hat' }
  if (isReporter spec) { type = 'reporter' }
  setBlockColor this (blockOp blockSpec)

  morph = (newMorph this)
  setGrabRule morph 'handle'
  setTransparentTouch morph false

  corner = 3
  expansionLevel = 1

  // create the base label parts
  group = (labelGroup this 1)
  for p group {
    addPart morph (morph p)
  }
  labelParts = (list group)
  addAllLabelParts this

  // expand to the first input slot, if any
  if suppressExpansion {return}
  if (and (repeatLastSpec blockSpec) (== 0 (countInputSlots blockSpec (at (specs blockSpec) 1)))) {
    expand this
  }
}

method labelGroup Block index {
  max = (count (specs blockSpec))
  if (index <= max) {
    specString = (at (specs blockSpec) index)
  } else {
    specString = (at (specs blockSpec) max)
  }
  slotIndex = 1
  for i (index - 1) {
    if (i > max) {
      slotIndex += (countInputSlots blockSpec (at (specs blockSpec) max))
    } else {
      slotIndex += (countInputSlots blockSpec (at (specs blockSpec) i))
    }
  }
  if (isPrototype this) {argNames = (argNames function)}
  group = (list)
  for w (words specString) {
    if ('_' == w) {
      add group (inputSlot blockSpec slotIndex color (isPrototype this) argNames)
      slotIndex += 1
    } else {
      add group (labelText this w)
    }
  }
  if (isEmpty group) {return (list (labelText this ''))}
  return group
}

method setBlockColor Block op {
    color = (blockColorForOp (authoringSpecs) op)
}

method flash Block {
	oldColor = color
	color = (color 255 255 0)
	pathCache = nil
	changed morph
	doOneCycle (global 'page')
	waitMSecs 50
	color = oldColor
	pathCache = nil
	changed morph
	doOneCycle (global 'page')
	waitMSecs 80
}

// expanding and collapsing

method drawer Block {
  if (and (isVariadic this) (not (isPrototype this))) {
    items = (count (flattened labelParts))
    return (handler (at (parts morph) (+ 1 items)))
  }
  return nil
}

method isVariadic Block {
  return (and (notNil blockSpec) (or (repeatLastSpec blockSpec) (> (count (specs blockSpec)) 1)))
}

method canExpand Block {
  return (and (notNil blockSpec) (or (repeatLastSpec blockSpec) (> (count (specs blockSpec)) expansionLevel)))
}

method canCollapse Block {
  return (and (notNil blockSpec) (expansionLevel > 1))
}

method expand Block {
  if ('template' == (grabRule morph)) { return } // do nothing if block is in palette

  nb = (next this)
  removeAllParts morph
  expansionLevel += 1
  add labelParts (labelGroup this expansionLevel)
  adjustIfElseBlocks this expression
  addAllLabelParts this
  setNext this nb
  if ('template' == (grabRule morph)) { comeToFront morph } // ensure collapse arrow not covered
}

method expandTo Block commandOrReporter {
  // helper method for initializeForNode
  // expands the blocks so it can accomodate at least the given
  // number of inputs
  numberOfInputs = (count (argList commandOrReporter))
  nb = (next this)
  removeAllParts morph
  while (and ((count (inputs this)) < numberOfInputs) (canExpand this)) {
    expansionLevel += 1
    add labelParts (labelGroup this expansionLevel)
  }
  adjustIfElseBlocks this commandOrReporter
  addAllLabelParts this
  setNext this nb
}

method collapse Block {
  nb = (next this)
  old = (at labelParts expansionLevel)
  removeAt labelParts expansionLevel
  removeAllParts morph
  expansionLevel += -1
  adjustIfElseBlocks this expression
  addAllLabelParts this
  setNext this nb

  // preserve old embedded blocks, if any
  editor = (scriptEditor this)
  if (isNil editor) {return}
  for slot old {
    keep = nil
    if (and (isClass slot 'Block') (!= 'template' (grabRule (morph slot)))) {
      keep = (morph slot)
    } (and (isClass slot 'CommandSlot') (notNil (nested slot))) {
      keep = (morph (nested slot))
    }
    if (notNil keep) {
      addPart (morph editor) keep
      moveBy keep 20 20
    }
  }
}

method ifElseParts Block boolSlot cmdSlot {
  // Helper method for adjustIfElseBlocks. Return a localized set of parts for
  // an ifElse section with the given boolean and command slots.
  // Assume this is an 'if' block.

  setField boolSlot 'displayAsElse' false // set Boolean slot to normal display mode
  result = (labelGroup this 2)
  for i (count result) {
    if (isClass (at result i) 'BooleanSlot') { atPut result i boolSlot }
    if (isClass (at result i) 'CommandSlot') { atPut result i cmdSlot }
  }
  return result
}


method adjustIfElseBlocks Block commandOrReporter {
  // Adjust the parts list of an if statement to show "else" if the final condition is
  // the constant true. Make all intermediate cases "else if <condition>".

  if ('if' != (primName commandOrReporter)) { return } // do nothing this is not an "if" block

  // convert final case to "else" if the condition is the constant true
  args = (argList commandOrReporter)
  isExpanding = ((count labelParts) > ((count args) / 2))
  isCollapsing = ((count labelParts) < ((count args) / 2))
  if isCollapsing { args = (copyFromTo args 1 ((count args) - 2)) } // dropping the last 2 args

  lastCondition = (at args ((count args) - 1))
  if (or isExpanding (and ((count args) > 2) (true == lastCondition))) {
    // final condition is of the form "else if true ..."
    // convert it to a Boolean slot that displays as "else" (localized)
    oldCmdSlot = (last (last labelParts))
    removeLast labelParts
    add labelParts (list (newBooleanSlot true true) oldCmdSlot)
  }

  if ((count labelParts) <= 2) { return } // no intermediate cases

  // convert intermediate cases to "else if <condition>"
  for i (range 2 ((count labelParts) - 1)) {
    parts = (at labelParts i)
    if (and ((count parts) == 2) (isClass (first parts) 'BooleanSlot') (isClass (last parts) 'CommandSlot')) {
      atPut labelParts i (ifElseParts this (first parts) (last parts))
    }
  }
}

method addAllLabelParts Block {
  allParts = (flattened labelParts)
  for p allParts {addPart morph (morph p)}
  if (and (isVariadic this) (not (isPrototype this))) {addPart morph (morph (newBlockDrawer this))}

  // create a new expression with the matching number of empty argument slots
  cmdAndArgs = (list (blockOp blockSpec))
  for p allParts {
    if (isAnyClass p 'InputSlot' 'BooleanSlot' 'ColorSlot' 'CommandSlot' 'Block' 'MicroBitDisplaySlot') {
      add cmdAndArgs nil
    }
  }

  cmdAndArgs = (toArray cmdAndArgs)
  if (isReporter blockSpec) {
    expression = (callWith 'newReporter' cmdAndArgs)
  } else {
    expression = (callWith 'newCommand' cmdAndArgs)
  }

  // update the expression's arguments' values with the actual input values
  // since these could have changed in the meantime (e.g. if the user typed
  // in something different)
  if (not (isPrototype this)) {
    for p allParts {
      if (isAnyClass p 'InputSlot' 'BooleanSlot' 'ColorSlot' 'CommandSlot' 'Block' 'MicroBitDisplaySlot') {
        inputChanged this p
      }
    }
  }
  layoutChanged this
  if (not (isPrototype this)) {
    raise morph 'expressionChanged' this
  }
}

// editing block prototypes (function definitions)

method updateBlockDefinition Block aBlockDefinition {
  if (isRenamableVar this) {
    raise morph 'updateBlockDefinition'
    return
  }

  if (isNil function) {return} // to do: raise an error

  // update the function
  setField function 'argNames' (inputNames aBlockDefinition)

  // update the block spec
  sp = (callWith 'blockSpecFromStrings' (specArray aBlockDefinition))
  recordBlockSpec (authoringSpecs) (primName function) sp

  // notify interested editors
  raise morph 'blockPrototypeChanged' this
}

method containsPrim Block aPrimName {
  for each (allMorphs morph) {
    hdl = (handler each)
    if (and (isClass hdl 'Block') (== aPrimName (primName (expression hdl)))) {
      return true
    }
  }
  return false
}

method setContents Block obj {nop} // only used for 'var' type input slots

// zebra-coloring for reporter blocks

method color Block {return color}

method getAlternative Block {
  if (isNil isAlternative) {isAlternative = false}
  return isAlternative
}

method fixBlockColor Block {
  if (and (type == 'reporter') (notNil (owner morph))) {
    parent = (handler (owner morph))
    oldAlternative = isAlternative
    if (and (isClass parent 'Block') ((color parent) == color)) {
      isAlternative = (not (getAlternative parent))
    } else {
      isAlternative = false
    }
    if (isAlternative != oldAlternative) {
	  pathCache = nil
      changed morph
      fixPartColors this
    }
  }
}

method fixPartColors Block {
  for m (parts morph) {
    if (isClass (handler m) 'Block') {
      fixBlockColor (handler m)
    }
  }
}

// changing block operations in place

method alternateOperators Block {
  if (contains (array 'v' '=' '+=') (primName expression)) {
	// if it's a variable, return a group with all existing variables
	return (array '')
  } else {
	opGroups = (array
		(array 'analogReadOp' 'digitalReadOp')
		(array 'analogWriteOp' 'digitalWriteOp')
		(array 'analogPins' 'digitalPins')
		(array 'and' 'or')
		(array '+' '-' '*' '/' '%')
		(array 'buttonA' 'buttonB')
		(array '<' '<=' '==' '!=' '>=' '>')
		(array 'maximum' 'minimum')
		(array 'millisOp' 'microsOp')
		(array '=' '+=')
		(array '&' '|' '^' '<<' '>>')
	)
	op = (primName expression)
	for group opGroups {
		if (contains group op) { return group }
	}
  }
  return nil
}

method changeOperator Block newOp {
  cancelSelection
  setField expression 'primName' newOp
  scripter = (scripter (findProjectEditor))
  updateScriptAfterOperatorChange scripter this
}

method changeVar Block varName {
  cancelSelection
  newVarReporter = (newReporter 'v' varName)
  blockOwner = (handler (owner morph))
  if (isClass blockOwner 'Block') {
    owningExpr = (expression blockOwner)
    args = (argList owningExpr)
    for i (count args) {
      if ((at args i) == (expression this)) {
        setArg owningExpr i newVarReporter
      }
    }
  } else { // top level var reporter
    expression = newVarReporter
  }
  scripter = (scripter (findProjectEditor))
  updateScriptAfterOperatorChange scripter this
}

// Inspection operations

method findBlockUsers Block {
	pe = (findProjectEditor)
	findBlockUsers (project pe) this
}

method findVarAccessors Block {
	pe = (findProjectEditor)
	findVarAccessors (project pe) this
}

method findVarModifiers Block {
	pe = (findProjectEditor)
	findVarModifiers (project pe) this
}

// Block definition operations

method deleteObsolete Block {
  pe = (findProjectEditor)
  if (isNil pe) { return }

  // find out whether block is being used in the project
  finder = (initialize (new 'BlockFinder') (project (scripter pe)) this)
  find finder 'users'
  if (notEmpty (allEntries finder)) {
    if (not
      (confirm
	    (global 'page')
	    nil
        (join
          'This block is still being used in '
          (count (allEntries finder))
          ' scripts or functions.'
          (newline)
          (newline)
          'Are you sure you want to remove this obsolete block definition?'
        )
	  )
	) { return }
  }

  remove (blockSpecs (project (scripter pe))) (primName expression)
  updateBlocks (scripter pe)
}

method deleteBlockDefinition Block {
  pe = (findProjectEditor)
  if (isNil pe) { return }

  confirmation = 'Are you sure you want to remove this block definition?'

  // find out whether block is being used in the project
  finder = (initialize (new 'BlockFinder') (project (scripter pe)) this)
  find finder 'users'
  if (notEmpty (allEntries finder)) {
    confirmation = (join
      'This block is still being used in '
      (count (allEntries finder))
      ' scripts or functions.'
	  (newline)
	  (newline)
	  confirmation
	)
  }

  if (not (confirm (global 'page') nil confirmation)) { return }

  deleteFunction (scripter pe) (primName expression)
}

// additions to Block for script selection

method select Block {
  if (isNil originalColor) {
    originalColor = color
    color = (mixed color 50 (color 0 255 0))
    pathCache = nil
    changed morph
    if (notNil (next this)) {
      select (next this)
    }
    for i (inputs this) {
      if (isClass i 'Block') {
        select i
      } (and
          (isClass i 'CommandSlot')
          (notNil (nested i))
      ) {
        select (nested i)
      }
    }
  }
}

method unselect Block {
  if (notNil originalColor) {
    color = originalColor
    originalColor = nil
    pathCache = nil
    changed morph
    if (notNil (next this)) {
      unselect (next this)
    }
    for i (inputs this) {
      if (isClass i 'Block') {
        unselect i
      } (and
          (isClass i 'CommandSlot')
          (notNil (nested i))
      ) {
        unselect (nested i)
      }
    }
  }
}

// keyboard accessibility hooks

method trigger Block {
  if (and ('template' == (grabRule morph)) (isRenamableVar this)) {
    userRenameVariable this
  }
}
