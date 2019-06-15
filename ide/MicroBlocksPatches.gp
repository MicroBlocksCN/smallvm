// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

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
  scripter = (ownerThatIsA morph 'MicroBlocksScripter')
  if (notNil scripter) {
	varNames = (allVariableNames (project (handler scripter)))
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
  addItem menu 'TemperatureSensor'
  addItem menu 'LeakSensor'
  addItem menu 'PushButton'
//   addItem menu 'Camera'
//   addItem menu 'VideoCamera'
  addItem menu 'Alarm'

  return menu
}

method varTypesMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 'boolean'
  addItem menu 'number'
  addItem menu 'string'
  return menu
}

method numberPropertyTypesMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 'LevelProperty'
  addItem menu 'BrightnessProperty'
  addItem menu 'ColorTemperatureProperty'
  addItem menu 'InstantaneousPowerProperty'
  addItem menu 'CurrentProperty'
  addItem menu 'VoltageProperty'
  addItem menu 'FrequencyProperty'
  addItem menu 'TemperatureProperty'
//   addItem menu 'ImageProperty'
//   addItem menu 'VideoProperty'
  return menu
}

method booleanPropertyTypesMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 'BooleanProperty'
  addItem menu 'OnOffProperty'
  addItem menu 'MotionProperty'
  addItem menu 'OpenProperty'
  addItem menu 'LeakProperty'
  addItem menu 'PushedProperty'
  addItem menu 'AlarmProperty'
  return menu
}

method stringPropertyTypesMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 'ColorProperty'
  addItem menu 'TextProperty'
  return menu
}

method hummingbirdSensorsMenu InputSlot {
  menu = (menu nil (action 'setContents' this) true)
  addItem menu 'Light'
  addItem menu 'Dial'
  addItem menu 'Distance (cm)'
  addItem menu 'Sound'
  addItem menu 'Other'
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
    addItem menu 'show compiled bytes' (action 'showCompiledBytes' (smallRuntime) this)
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
  if (notNil (functionNamed (project pe) (primName expression))) {
	if isInPalette {
	  addItem menu 'delete function...' 'deleteFunction'
	}
    addItem menu 'show function definition...' 'showDefinition'
    addLine menu
  }
  addItem menu 'duplicate' 'grabDuplicate' 'just this one block'
  if (and ('reporter' != type) (notNil (next this))) {
    addItem menu '...all' 'grabDuplicateAll' 'duplicate including all attached blocks'
  }

  addLine menu
  addItem menu 'save picture of script' 'exportAsImage'
  addLine menu
  addItem menu 'copy script' 'copyToClipboard'
  if (not isInPalette) {
    addItem menu 'pick up' 'pickUp'
    addLine menu
    addItem menu 'delete' 'delete'
  }
  return menu
}

method pickUp Block {
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
        fixBlockColor nxt
      }
    }
  }
  grabCentered morph this
}

method deleteFunction Block {
  pe = (findProjectEditor)
  if (isNil pe) { return }
  deleteFunction (scripter pe) (primName expression)
}

method showDefinition Block {
  pe = (findProjectEditor)
  if (isNil pe) { return }
  showDefinition (scripter pe) (primName expression)
}

method hideDefinition BlockDefinition {
  // Remove this method/function definition from the scripting area.

  pe = (findProjectEditor)
  if (isNil pe) { return }
  hideDefinition (scripter pe) op
}

method inputIndex Block anInput {
  idx = 0
  items = (flattened labelParts)

  // Note: removed special case for variable assignments

  for each items {
    if (isAnyClass each 'InputSlot' 'BooleanSlot' 'ColorSlot' 'CommandSlot' 'Block' 'MicroBitDisplaySlot') {
      idx += 1
      if (each === anInput) {return idx}
    }
  }
  return nil
}

method representsANumber String {
	// MicroBlocks only supports integers.
	if ('' == String) { return true }
	isFirst = true
	for c (letters this) {
		if ('-' == c) {
			if (not isFirst) { return false }
		} (not (isDigit c)) {
			return false
		}
		isFirst = false
	}
	return true
}

method contextMenu BlockDefinition {
  menu = (menu nil this)
  if (devMode) {
    addItem menu 'show instructions' (action 'showInstructions' this)
    addItem menu 'show compiled bytes' (action 'showCompiledBytes' this)
    addLine menu
  }
  addItem menu 'hide function definition' 'hideDefinition'
  addItem menu 'save picture of script' 'exportAsImage'
  addLine menu
  addItem menu 'delete' 'deleteDefinition'
  popUp menu (global 'page') (left morph) (bottom morph)
}

method showInstructions BlockDefinition {
  showInstructions (smallRuntime) (handler (owner (owner morph)))
}

method showCompiledBytes BlockDefinition {
  showCompiledBytes (smallRuntime) (handler (owner (owner morph)))
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
  addItem menu 'copy all scripts' 'copyScriptsToClipboard'
  clip = (getClipboard)
  if (beginsWith clip 'GP Scripts') {
	addItem menu 'paste all scripts' 'pasteScripts'
  } (beginsWith clip 'GP Script') {
	addItem menu 'paste script' 'pasteScripts'
  }
  addLine menu
  addItem menu 'save picture of all scripts' 'saveScriptsImage'
  return menu
}

// Block layout tweak

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

// Make ColorSlots be round

method redraw ColorSlot {
  scale = (global 'scale')
  border = (1 * scale)
  center = (9 * scale)
  radius = (center - 1)
  size = (2 * center)
  bm = (costume morph)
  bm = nil
  if (isNil bm) { bm = (newBitmap size size) }
  fill bm (gray 0 0)
  drawCircle (newShapeMaker bm) center center radius contents border (gray 0)
  setCostume morph bm
}

// Color picker tweaks

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

// Block colors

method setCategoryFor AuthoringSpecs op category {
  atPut opCategory op category
}

method blockColorForCategory AuthoringSpecs cat {
  defaultColor = (colorHSV 200.0 0.982 0.863)
  if ('Output' == cat) { return (colorHSV 235 0.62 0.80) // (colorHSV 224.211 0.636 0.82)
  } ('Input' == cat) { return (colorHSV 170 0.78 0.62) // (colorHSV 161.077 0.788 0.647)
  } ('Pins' == cat) { return (colorHSV 296 0.60 0.63) // (colorHSV 296.033 0.627 0.757)
  } ('Control' == cat) { return (colorHSV 36.196 0.811 0.89)
  } ('Math' == cat) { return (colorHSV 93 0.85 0.68) // (colorHSV 92.914 0.902 0.761)
  } ('Variables' == cat) { return (colorHSV 26 0.80 0.88) // (colorHSV 25.67 0.822 0.925)
  } ('Lists' == cat) { return (colorHSV 21 0.85 0.80) // (colorHSV 20.503 0.881 0.886)
  } ('Advanced' == cat) { return (colorHSV 36.923 0.722 0.706)
  } ('Functions' == cat) { return (colorHSV 205.445 0.83 0.902)
  } ('Obsolete' == cat) { return (colorHSV 4.592 1.0 0.769)
  }
  return defaultColor
}

// Scratch		1.0					2.0
// Motion	(color 102 124 236)	(color 76 111 209)
// Looks	(color 147 84 235)	(color 36 139 216)
// Sound	(color 217 43 225)	(color 185 72 193)
// Pen		(color 35 165 124)	(color 29 153 109)
// Control	(color 227 154 43)	(color 224 168 48)
// Sensing	(color 39 149 230)	(color 53 166 223) like default color
// Operators (color 99 196 44)	(color 95 181 39)
// Variables (color 226 95 27)	(color 236 125 42) variables is like 2.0
// Events						(color 199 130 57)
// More Blocks					(color 98 50 151)))

// ListBox: Support for colored blocks categories

method normalCostume ListBox data accessor {
  scale = (global 'scale')
  if (isNil accessor) {accessor = getEntry}
  dta = (call accessor data)
  if (isClass dta 'String') {
	// Colored categories:
	if (and (isClass onSelect 'Action') (isOneOf (function onSelect) 'categorySelected' 'librarySelected')) {
	  // add color swatch for category
	  c = (blockColorForCategory (authoringSpecs) dta)
	  stringBM = (stringImage (localized dta) fontName fontSize (gray 50))
	  bm = (newBitmap ((width stringBM) + (50 * scale)) (21 * scale))
	  fillRect bm c (4 * scale) (1 * scale) (10 * scale) ((height bm) - (4 * scale))
	  drawBitmap bm stringBM (19 * scale) (1 * scale)
	  return bm
	}
	return (stringImage dta fontName fontSize txtClrNormal nil nil nil nil paddingX paddingY)
  } (isClass dta 'Bitmap') {
    bm = (newBitmap (+ (* 2 paddingX) (width dta)) (+ (height dta) (* 2 paddingY)) bgClrNormal)
    drawBitmap bm dta paddingX paddingY normalAlpha
    return bm
  }
  return (itemCostume this dta txtClrNormal nil normalAlpha 'id')
}

method itemCostume ListBox data foregroundColor backgroundColor alpha accessor {
  scale = (global 'scale')
  if (isNil accessor) {accessor = getEntry}
  dta = (call accessor data)
  if (isClass dta 'Bitmap') {
    bm = (newBitmap (max (+ (* 2 paddingX) (width dta)) (width morph)) (+ (height dta) (* 2 paddingY)) backgroundColor)
    drawBitmap bm dta paddingX paddingY alpha
    return bm
  } (isClass dta 'Morph') {
    return (itemCostume this (fullCostume dta) foregroundColor backgroundColor alpha 'id')
  } (hasField dta 'morph') {
    return (itemCostume this (fullCostume (getField dta 'morph')) foregroundColor backgroundColor alpha 'id')
  } (isAnyClass dta 'Command' 'Reporter') {
    return (itemCostume this (fullCostume (morph (toBlock dta))) foregroundColor backgroundColor alpha 'id')
  } (isClass dta 'String') {
	// Colored categories:
	if (and (isClass onSelect 'Action') (isOneOf (function onSelect) 'categorySelected' 'librarySelected')) {
	  c = (blockColorForCategory (authoringSpecs) dta)
	  isMouseOver = (bgClrReady == backgroundColor)
	  if isMouseOver { c = (shiftSaturation (lighter c 20) -30) }
	  bm = (newBitmap ((width morph) + (20 * scale)) (21 * scale))
	  fillRect bm c 0 0 (width bm) ((height bm) - (2 * scale))
	  stringBM = (stringImage (localized dta) fontName fontSize (gray 255))
	  drawBitmap bm stringBM (29 * scale) (1 * scale)
	  return bm
	}
    return (itemCostume this (stringImage dta fontName fontSize foregroundColor) foregroundColor backgroundColor alpha 'id')
  } else {
    return (itemCostume this (toString dta) foregroundColor backgroundColor alpha 'id')
  }
}
