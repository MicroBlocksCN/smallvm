// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

//Copyright 2018 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksPatches.gp - This file patches/replaces methods in GP's normal class library
// with versions that support MicroBlocks (possibly making them no longer work correctly in
// the normal GP IDE.
//
// This file must be processed *after* the normal GP library has been read with a command like:
//
//	./gp runtime/lib/* microBlocks/GP-IDE/* -
//
// John Maloney, January, 2018

method allVarsMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)

  // shared vars
  scripter = (ownerThatIsA morph 'Scripter')
  if (isNil scripter) { scripter = (ownerThatIsA morph 'MicroBlocksScripter') }
  if (notNil scripter) {
	varNames = (copyWithout (variableNames (targetModule (handler scripter))) 'extensions')
	for varName varNames {
          // hide vars that start with underscore, used for libraries
          if (or ((at varName 1) != '_') (devMode)) {
            addItem menu varName varName
          }
	}
	if ((count varNames) > 0) { addLine menu }
  }

  // local vars
  myBlock = (handler (ownerThatIsA morph 'Block'))
  localVars = (collectLocals (expression (topBlock myBlock)))
  for field (fieldNames (classOf targetObj)) { remove localVars field }
  if (notEmpty localVars) {
	localVars = (sorted (keys localVars))
	for varName localVars {
	  addItem menu varName varName
	}
  }
  return menu
}

method buttonMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 'A'
  addItem menu 'B'
  return menu
}

method directions InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 'clockwise'
  addItem menu 'counter-clockwise'
  return menu
}

method thingTypesMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu ''
  addItem menu 'OnOffSwitch'
  addItem menu 'MultiLevelSwitch'
  addItem menu 'BinarySensor'
  addItem menu 'MultiLevelSensor'
  addItem menu 'ColorControl'
  addItem menu 'EnergyMonitor'
  addItem menu 'SmartPlug'
  addItem menu 'Light'
  addItem menu 'MotionSensor'
  addItem menu 'DoorSensor'
  addItem menu 'PushButton'
  return menu
}

method varTypesMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 'boolean'
  addItem menu 'number'
  addItem menu 'string'
  return menu
}

method propertyTypesMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu ''
  addItem menu 'BooleanProperty'
  addItem menu 'OnOffProperty'
  addItem menu 'MotionProperty'
  addItem menu 'OpenProperty'
  addItem menu 'PushedProperty'
  addItem menu 'LevelProperty'
  addItem menu 'BrightnessProperty'
  addItem menu 'ColorProperty'
  addItem menu 'ColorTemperatureProperty'
  addItem menu 'InstantaneousPowerProperty'
  addItem menu 'CurrentProperty'
  addItem menu 'VoltageProperty'
  addItem menu 'FrequencyProperty'
  return menu
}

method confirmToQuit Page {
	confirm this nil (join 'Quit MicroBlocks?') nil nil 'exit'
}

to findProjectEditor {
  page = (global 'page')
  if (notNil page) {
	for p (parts (morph page)) {
	  if (isClass (handler p) 'MicroBlocksEditor') { return (handler p) }
	}
  }
  return nil
}

to gpFolder {
  if ('iOS' == (platform)) { return '.' }
  path = (userHomePath)

  hidden = (global 'hideFolderShortcuts')
  if (and (notNil hidden) (contains hidden 'Projects')) { return '/' } // if GP hidden, use computer

  // Look for <home>/Documents
  if (contains (listDirectories path) 'Documents') {
	path = (join path '/Documents')
  }
  if (not (contains (listDirectories path) 'MicroBlocks')) {
	if (contains (listDirectories path) 'MicroBlocks Projects') {
		// if it exists, rename old 'MicroBlocks Projects' folder to 'MicroBlocks'
		renameFile (join path '/MicroBlocks Projects') (join path '/MicroBlocks')
	} else {
		// create the MicroBlocks folder if it does not already exist
		makeDirectory (join path '/MicroBlocks')
	}
  }
  if (contains (listDirectories path) 'MicroBlocks') {
	path = (join path '/MicroBlocks')
  }
  return path
}

to gpExamplesFolder { return 'Examples' }

method clicked Block hand {
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

method devMenu Hand currentObj {
	// disable the developer menu (comment this method out to re-enable it
}

method contextMenu Block {
  if (isPrototype this) {return nil}
  menu = (menu nil this)
  pe = (findProjectEditor)

  if (devMode) {
    addItem menu 'show instructions' (action 'showInstructions' (smallRuntime) this)
    addItem menu 'show compiled bytes' (action 'evalOnBoard' (smallRuntime) this true)
    addLine menu
  }

  isInPalette = ('template' == (grabRule morph))
  if (isVariadic this) {
    if (canExpand this) {addItem menu 'expand' 'expand'}
    if (canCollapse this) {addItem menu 'collapse' 'collapse'}
    addLine menu
  }
  if (and isInPalette (isRenamableVar this)) {
    addItem menu 'rename...' 'userRenameVariable'
    addLine menu
  }
  if (and isInPalette (notNil (functionNamed (module (project pe)) (primName expression)))) {
    addItem menu 'show definition...' 'showDefinition'
  }
  addItem menu 'duplicate' 'grabDuplicate' 'just this one block'
  if (and ('reporter' != type) (notNil (next this))) {
    addItem menu '...all' 'grabDuplicateAll' 'duplicate including all attached blocks'
  }
//  addItem menu 'copy to clipboard' 'copyToClipboard'

  addLine menu
  addItem menu 'save picture of script' 'exportAsImage'
  if (not isInPalette) {
    addLine menu
    addItem menu 'delete' 'delete'
  }
  return menu
}

method contextMenu BlockDefinition {
  menu = (menu nil this)
  for tp (array 'command' 'reporter') {
    addItem menu '' (action 'setType' this tp) tp (fullCostume (morph (block tp (color 4 148 220) '                    ')))
  }
  if (devMode) {
    addLine menu
    addItem menu 'show instructions' (action 'showInstructions' this)
    addItem menu 'show compiled bytes' (action 'showCompiledBytes' this)
  }
  addLine menu
  addItem menu 'hide definition' 'hideDefinition'
  addItem menu 'save picture of script' 'exportAsImage'
  addLine menu
  addItem menu 'delete' 'deleteDefinition'
  popUp menu (global 'page') (left morph) (bottom morph)
}

method showInstructions BlockDefinition {
  showInstructions (smallRuntime) (handler (owner (owner morph)))
}

method showCompiledBytes BlockDefinition {
  evalOnBoard (smallRuntime) (handler (owner (owner morph))) true
}

method initializeRepeater BlockDefinition aBlockSpec {
  if (isNil aBlockSpec) {
    isRepeating = false
  } else {
    isRepeating = (repeatLastSpec aBlockSpec)
  }
  drawer = (newBlockDrawer this nil 'vertical')
  repeater = (newAlignment 'centered-line' 0 'bounds')
  setMorph repeater (newMorph repeater)
  if isShort {
    hide (morph repeater)
  }
  setPadding repeater (5 * (global 'scale'))
return // xxx suppress the ability to make variadic user-defined blocks

  addPart (morph repeater) (morph drawer)

  scale = (global 'scale')
  if (global 'stealthBlocks') {
    labelColor = (gray (stealthLevel 255 0))
  } else {
    labelColor = (global 'blockTextColor')
    if (isNil labelColor) { labelColor = (gray 255) }
  }
  txt = (newText 'repeat last section:' 'Arial' (10 * scale) labelColor)
  addPart (morph repeater) (morph txt)

  corner = 5
  toggle = (toggleButton (action 'toggleRepeat' this) (action 'isRepeating' this) (scale * 20) (scale * 13) (scale * corner) (max 1 (scale / 2)) false false)
  addPart (morph repeater) (morph toggle)
}

method okayToBeDestroyedByUser Block {
  if (isPrototypeHat this) {
	editor = (findProjectEditor)
	if (isNil editor) { return false }
    function = (function (first (inputs this)))
    if (confirm (global 'page') nil 'Are you sure you want to remove this block definition?') {
	  removedUserDefinedBlock (scripter editor) function
	  deleteChunkForBlock (smallRuntime) this
      return true
    }
    return false
  }
  deleteChunkForBlock (smallRuntime) this
  return true
}

method contextMenu ScriptEditor {
  menu = (menu nil this)
  addItem menu 'clean up' 'cleanUp' 'arrange scripts'
  if (and (notNil lastDrop) (isRestorable lastDrop)) {
    addItem menu 'undrop' 'undrop' 'undo last drop'
  }
  addLine menu
  addItem menu 'save picture of all scripts' 'saveScriptsImage'
  return menu
}

method fixLayout Block {
  space = 3
  vSpace = 3

  break = 450
  lineHeights = (list)
  lines = (list)
  lineArgCount = 0

  left = (left morph)
  blockWidth = 0
  blockHeight = 0
  h = 0
  w = 0

  if (global 'stealthBlocks') {
    if (type == 'hat') {
      indentation = (stealthLevel (* scale (+ border space)) 0)
    } (type == 'reporter') {
      indentation = (stealthLevel (* scale rounding) (width (stealthText this '(')))
    } (type == 'command') {
      indentation = (stealthLevel (* scale (+ border inset dent (corner * 2))) 0)
    }
  } else {
    if (type == 'hat') {
      indentation = (* scale (+ border space))
    } (type == 'reporter') {
      indentation = (* scale rounding)
    } (type == 'command') {
      indentation = (* scale (+ border inset dent (corner * 2)))
    }
  }

  // arrange label parts horizontally and break up into lines
  currentLine = (list)
  for group labelParts {
    for each group {
      if (isVisible (morph each)) {
        if (isClass each 'CommandSlot') {
          add lines currentLine
          add lineHeights h
          setLeft (morph each) (+ left (* scale (+ border corner)))
          add lines (list each)
          add lineHeights (height (morph each))
          currentLine = (list)
          w = 0
          h = 0
        } else {
          x = (+ left indentation w)
          w += (width (fullBounds (morph each)))
          w += (space * scale)
		  if (and ('mbDisplay' == (primName expression)) (each == (first group))) {
			lineArgCount = 10; // force a line break after first item of 'mbDisplay' block
		  }
		  if (and ('setNeoPixelColors10' == (primName expression)) (each == (at group 3))) {
			lineArgCount = 10; // force a line break after first item of 'mbDisplay' block
		  }
		  if (and (or (w > (break * scale)) (lineArgCount >= 5)) (notEmpty currentLine)) {
            add lines currentLine
            add lineHeights h
            currentLine = (list)
            h = 0
            x = (+ left indentation)
            w = ((width (fullBounds (morph each))) + (space * scale))
            lineArgCount = 0
          }
          add currentLine each
          h = (max h (height (morph each)))
          setLeft (morph each) x
		  if (not (isClass each 'Text')) { lineArgCount += 1 }
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
      add lines currentLine
      add lineHeights h
      currentLine = (list)
      h = 0
      x = (+ left indentation)
      w = ((width (fullBounds (morph drawer))) + (space * scale))
    }
    add currentLine drawer
    h = (max h (height (morph drawer)))
    setLeft (morph drawer) x
  }

  // add last label line
  add lines currentLine
  add lineHeights h

  // purge empty lines
  // to do: prevent empty lines from being added in the first place
  for i (count lines) {
    if (isEmpty (at lines i)) {
      removeAt lines i
      removeAt lineHeights i
    }
  }

  // determine block dimensions from line data
  blockWidth = 0
  for each lines {
    if (notEmpty each) {
      elem = (last each)
      if (not (isClass elem 'CommandSlot')) {
        blockWidth = (max blockWidth ((right (fullBounds (morph elem))) - left))
      }
    }
  }
  blockWidth = (- blockWidth (space * scale))
  blockHeight = (callWith + (toArray lineHeights))
  blockHeight += (* (count lines) vSpace scale)

  // arrange label parts vertically
  if (global 'stealthBlocks') {
    tp = (+ (top morph) (stealthLevel (* 2 scale border) 0))
  } else {
    tp =  (+ (top morph) (* 2 scale border))
  }
  if (type == 'hat') {
    tp += (hatHeight this)
  }
  line = 0
  for eachLine lines {
    line += 1
    bottom = (+ tp (at lineHeights line) (vSpace * scale))
    for each eachLine {
      setYCenterWithin (morph each) tp bottom
    }
    tp = bottom
  }

  // add extra space below the bottom-most c-slot
  extraSpace = 0
  if (and (isNil drawer) (isClass (last (last labelParts)) 'CommandSlot')) {
    extraSpace = (scale * corner)
  }

  // set block dimensions
  blockWidth += (* -1 scale space)
  blockWidth += (* scale border)

  if (global 'stealthBlocks') {
    if (type == 'command') {
      setWidth (bounds morph) (+ blockWidth indentation (stealthLevel (scale * corner) 0))
      setHeight (bounds morph) (stealthLevel (+ blockHeight (* scale corner) (* scale border 4) extraSpace) blockHeight)
    } (type == 'hat') {
      setWidth (bounds morph) (max (scale * (+ hatWidth 20)) (+ blockWidth indentation (stealthLevel (scale * corner) 0)))
      setHeight (bounds morph) (stealthLevel (+ blockHeight (* scale corner 2) (* scale border) (hatHeight this) extraSpace) (+ blockHeight (hatHeight this)))
    } (type == 'reporter') {
      setWidth (bounds morph) (+ blockWidth (2 * indentation) (stealthLevel (scale * rounding) 0))
      setHeight (bounds morph) (stealthLevel (+ blockHeight (* scale border 4) extraSpace) blockHeight)
    }
  } else {
    if (type == 'command') {
      setWidth (bounds morph) (max (scale * 50) (+ blockWidth indentation (scale * corner)))
      setHeight (bounds morph) (+ blockHeight (* scale corner) (* scale border 4) extraSpace)
    } (type == 'hat') {
      setWidth (bounds morph) (max (scale * (+ hatWidth 20)) (+ blockWidth indentation (scale * corner)))
      setHeight (bounds morph) (+ blockHeight (* scale corner 2) (* scale border) (hatHeight this) extraSpace)
    } (type == 'reporter') {
      setWidth (bounds morph) (max (scale * 20) (+ blockWidth indentation (scale * rounding)))
      setHeight (bounds morph) (+ blockHeight (* scale border 4) extraSpace)
    }
  }

  for group labelParts {
    for each group {
      if (isClass each 'CommandSlot') {fixLayout each true}
    }
  }
  redraw this
  nb = (next this)
  if (notNil nb) {
    setPosition (morph nb) (left morph) (- (+ (top morph) (height morph)) (scale * corner))
  }
  raise morph 'layoutChanged' this
}

to newColorPicker action initialColor {
  // If there is already a ColorPicker on the screen, return it.
  // Otherwise, create and return a new one.

  for m (parts (morph (global 'page'))) {
	if (isClass (handler m) 'ColorPicker') {
	  setAction (handler m) action
	  return (handler m)
	}
  }
  return (initialize (new 'ColorPicker') action initialColor)
}

method setAction ColorPicker anAction { action = anAction }

method updateRGBReadouts ColorPicker c {
  // Adjust color for NeoPixels (see SmallCompiler instructionsForExpression)

  brightness = (((raise 2 (5 * (brightness c))) - 1) / 31) // range: 0-1
  saturation = (2 * (saturation c)) // increase saturation
  c = (colorHSV (hue c) saturation (0.125 * brightness))

  setText rText (join 'R ' (leftPadded (toString (red c)) 2 '0'))
  setText gText (join 'G ' (leftPadded (toString (green c)) 2 '0'))
  setText bText (join 'B ' (leftPadded (toString (blue c)) 2 '0'))
}
