// ScriptEditor -- Supports constructing and editing block scripts by drag-n-drop.

defineClass ScriptEditor morph feedback scale focus lastDrop

to newScriptEditor width height {
  return (initialize (new 'ScriptEditor') width height)
}

method initialize ScriptEditor width height {
  morph = (newMorph this)
  setExtent morph width height
  setMinExtent morph 100 150
  feedback = (newMorph)
  scale = (global 'scale')
  return this
}

// stepping

method step ScriptEditor {
  hide feedback
  hand = (hand (handler (root morph)))
  if (containsPoint (bounds morph) (left (morph hand)) (top (morph hand))) {
    load = (grabbedObject hand)
    if (isClass load 'Block') {updateFeedback this load}
  }
  updateHighlights this
}

// events

method handDownOn ScriptEditor aHand {
	if (notNil (grabbedObject aHand)) { return false } // hand is not empty
	scripter = (handler (ownerThatIsA morph 'MicroBlocksScripter'))
	if (isNil scripter) { return }
	selection = (selection scripter)
	if (and (notNil selection) (notEmpty selection)) {
		if (shiftKeyDown (keyboard (page aHand))) { return false }
		grabbed = (ownerThatIsA (morph (objectAt aHand)) 'Block')
		if (and (notNil grabbed) (contains selection (handler grabbed))) {
			dragBlocks selection
			return true
		}
	}
	if (isClass (objectAt aHand) 'ScriptEditor') {
		if (not (isMobile)) {
			startSelecting scripter aHand
		}
	}
	return true
}

method wantsDropOf ScriptEditor aHandler {
  return (or
    (isAnyClass aHandler 'Block' 'CommandSlot' 'MicroBlocksSelectionContents')
    (and
      (devMode)
      (isClass aHandler 'Text')
      (== 'code' (editRule aHandler))))
}

method justReceivedDrop ScriptEditor aHandler {
  scriptChanged this
}

method rightClicked ScriptEditor aHand {
  popUpAtHand (contextMenu this) (page aHand)
  return true
}

method justGrabbedPart ScriptEditor part {
  if (isClass (handler (owner morph)) 'ScrollFrame') {
    updateSliders (handler (owner morph))
  }
}

method clicked ScriptEditor hand {
  // Support for GP keyboard block entry.

  if (isMicroBlocks) { return } // do nothing in MicroBlocks
  kbd = (keyboard (page hand))
  if (and (devMode) (keyDown kbd 'space')) {
    txt = (newText '' 'Arial' ((global 'scale') * 12) (gray 0))
    setEditRule txt 'code'
    setGrabRule (morph txt) 'ignore'
    setCenter (morph txt) (x hand) (y hand)
    addPart morph (morph txt)
    edit txt hand
    return true
  } (shiftKeyDown kbd) {
    edit this this nil (x hand) (y hand)
    return true
  } (notNil focus) {
    cancel focus
    return true
  }
  return false
}

method textChanged ScriptEditor text {
  if ('code' == (editRule text)) {
    if ('' == (text text)) {
      destroy (morph text)
      return
    }
	if (beginsWith (text text) '(') {
	  parsed = (parse (text text))
	} else {
	  parsed = (parse (join '{' (text text) '}'))
	}
    if (isEmpty parsed) {
      literal = (parse (text text))
      if (isEmpty literal) {
        setColor text (color 180 0 0)
      } else {
        setColor text (color 0 0 180)
      }
      setGrabRule (morph text) 'handle'
    } else {
      element = (at parsed 1)
      if (isClass element 'Command') {
        element = (at (parse (join '{' (newline) (text text) (newline) '}')) 1)
      }
      if ('method' == (primName element)) {
		args = (toList (argList element))
		methodName = (removeFirst args)
		methodClass = (class (removeFirst args))
		methodBody = (removeLast args)
		methodParams = (join (array 'this') args)
		func = (addMethod methodClass methodName methodParams methodBody)
        block = (scriptForFunction func)
      } else {
        block = (toBlock element)
      }
      addSchedule (global 'page') (newAnimation 1.0 1.2 200 (action 'setScaleAround' (morph text) (left (morph text)) (top (morph text))) (action 'swapBlockForText' this block text) true)
      return
    }
  }
  raise morph 'textChanged' text
}

method layoutChanged ScriptEditor { changed morph }

// swapping blocks for text

method swapBlockForText ScriptEditor block text {
  setPosition (morph block) (left (morph text)) (top (morph text))
  addPart morph (morph block)
  fixBlockColor block
  destroy (morph text)
  snap block
}

method swapTextForBlock ScriptEditor text block hand {
  setPosition (morph text) (left (morph block)) (top (morph block))
  addPart morph (morph text)
  edit text hand
  destroy (morph block)
}

// snapping

method targetFor ScriptEditor block {
  // Answer a snapping target or nil if none found.

  xThreshold = (50 * (blockScale))
  yThreshold = (15 * (blockScale))

  if ('reporter' == (type block)) {return (inputFor this block)}
  isHatSrc = ('hat' == (type block))

  x = (left (morph block))
  y = (top (morph block))
  yb = (bottom (morph (bottomBlock block)))
  cSlot = (openCSlot block)

  others = (reversed (allMorphs morph))
  remove others morph
  for m others {
    if (and (isClass (handler m) 'Block') (isNil (function (handler m)))) {
      targetType = (type (handler m))
      if isHatSrc {
        if (and ('command' == targetType) (this === (handler (owner m)))) { // top of stack
          xd = (abs (x - (left m)))
          yd = (abs ((top m) - yb))
          if (and (xd < xThreshold) (yd < yThreshold)) {return (array (handler m) 'top' cSlot)}
        }
      } else {
        if ('command' == targetType) {
          xd = (abs (x - (left m)))
          yd = (abs (y - (bottom m)))
          if (and (xd < xThreshold) (yd < yThreshold)) {return (handler m)}
          if (this === (handler (owner m))) { // top of stack
            yd = (abs ((top m) - yb))
            if (and (xd < xThreshold) (yd < yThreshold)) {return (array (handler m) 'top' cSlot)}
            if (notNil cSlot) {
              yd = (abs ((top (morph cSlot)) - (top m)))
              if (and (xd < xThreshold) (yd < yThreshold)) {return (array (handler m) 'wrap' cSlot)}
            }
         }
        } ('hat' == targetType) {
          xd = (abs (x - (left m)))
          yd = (abs (y - (bottom m)))
          if (and (xd < xThreshold) (yd < yThreshold)) {return (handler m)}
        }
      }
    } (and (not isHatSrc) (isClass (handler m) 'CommandSlot')) {
      xd = (abs (x - (+ (scaledCorner (handler m)) (left m))))
      yd = (abs (y - (+ (scaledCorner (handler m)) (top m))))
      if (and (xd < xThreshold) (yd < yThreshold)) {return (handler m)}
    }
  }
  return nil
}

method inputFor ScriptEditor block {
  // Answer an input (slot or reporter) for dropping the givenblock or nil if none found.

  others = (reversed (allMorphs morph))
  remove others morph
  x = (left (morph block))
  y = (top (morph block))

  // look for a slot
  for m others {
    if (isAnyClass (handler m) 'InputSlot' 'BooleanSlot' 'ColorSlot') {
      // expand drop rectangle to make the target easier to hit
      dropRect = (expandBy (bounds m) (5 * (global 'scale')))
      if (and (isReplaceableByReporter (handler m)) (containsPoint dropRect x y)) {
        return (handler m)
      }
    }
  }

  // look for a reporter to replace
  for m others {
    if (or
	  (and (isReplaceableByReporter (handler m)) (isAnyClass (handler m) 'InputSlot' 'BooleanSlot' 'ColorSlot'))
	  (and
	    (isClass (handler m) 'Block')
	    ((type (handler m)) == 'reporter')
	    (isClass (handler (owner m)) 'Block')
	    ((grabRule m) != 'template')
	    (not (isPrototype (handler m)))
      )) {
        if (containsPoint (bounds m) x y) { return (handler m) }
    }
  }
  return nil
}

method updateFeedback ScriptEditor block {
  hide feedback
  if (isNil block) {return}
  cSlot = (openCSlot block)
  trgt = (targetFor this block)
  if (isNil trgt) { // no drop target
    if (and (notNil cSlot) (notNil (wrapHeight cSlot))) { // clear cSlot's wrap height
      setWrapHeight cSlot nil
      draggedObjectChanged (hand (global 'page'))
    }
  } else { // found a drop target
    if ('reporter' == (type block)) { // dragging a reporter
      showReporterDropFeedback this trgt
    } else { // dragging a command or hat block (including C-shaped command blocks)
      if (notNil cSlot) {
        // adjust size of cSlot
        if (and (isClass trgt 'Array') ('wrap' == (at trgt 2))) {
          setWrapHeight cSlot ((height (fullBounds (morph (first trgt)))) + (10 * (blockScale)))
        } else {
          setWrapHeight cSlot nil
        }
      }
      draggedObjectChanged (hand (global 'page'))
      showCommandDropFeedback this trgt
    }
    addPart morph feedback // come to front
    show feedback
  }
}

method dropFeedbackColor ScriptEditor { return (colorHex 'FED722') }

method showCommandDropFeedback ScriptEditor target {
  if (isClass target 'Block') {
    nb = (next target)
    top = (bottom (morph target))
    if (notNil nb) {top = (bottomLine target)}
    setPosition feedback (left (morph target)) top
  } (isClass target 'Array') {
    rec = target
    target = (at rec 1)
    top = ((top (morph target)) - (height feedback))
    setPosition feedback (left (morph target)) top
  } (isClass target 'CommandSlot') {
    nb = (nested target)
    top = (+ (top (morph target)) (scaledCorner target))
    if (isNil nb) {top += (scaledCorner target)}
    setPosition feedback (+ (scaledCorner target) (left (morph target))) top
  }
  setExtent feedback (width (morph target)) (5 * scale)
  setCostume feedback (dropFeedbackColor this)
}

method showReporterDropFeedback ScriptEditor target {
  setBounds feedback (expandBy (bounds (morph target)) (12 * scale))
  area = (rect 0 0 (width feedback) (height feedback))
  radius = (10 * scale)
  border = (3 * scale)
  fillColor = (withAlpha (dropFeedbackColor this) 150) // translucent
  borderColor = (dropFeedbackColor this)
  bm = (newBitmap (width area) (height area))
  fillRoundedRect (newShapeMaker bm) area radius fillColor border borderColor borderColor
  setCostume feedback bm
}

// context menu

method contextMenu ScriptEditor {
  menu = (menu nil this)
  addItem menu 'set block size...' 'setBlockSize' 'make blocks bigger or smaller'
  addLine menu
  if (notNil lastDrop) {
    addItem menu 'undrop (ctrl-Z)' 'undrop' 'undo the last block drop'
  }
  addItem menu 'clean up' 'cleanUp' 'arrange scripts'
  addLine menu
  addItem menu 'copy all scripts to clipboard' 'copyScriptsToClipboard'
  addItem menu 'copy all scripts to clipboard as URL' 'copyScriptsToClipboardAsURL'
  addLine menu
  clip = (readClipboard)
  if (beginsWith clip 'GP Scripts') {
	addItem menu 'paste all scripts from clipboard' 'pasteScripts'
  } (beginsWith clip 'GP Script') {
	addItem menu 'paste script from clipboard' 'pasteScripts'
  }
  addLine menu
  addItem menu 'save a picture of all visible scripts' 'saveScriptsImage'
  if (devMode) {
    addItem menu 'set exported script scale' 'setExportedScriptScale'
  }
  return menu
}

method contextMenuForGP ScriptEditor {
  menu = (menu nil this)
  addItem menu 'set block size...' 'setBlockSize' 'make blocks smaller'
  addLine menu
  addItem menu 'clean up' 'cleanUp' 'arrange scripts'
  if (notNil lastDrop) {
    addItem menu 'undrop' 'undrop' 'undo last drop'
  }
  addLine menu
  addItem menu 'set exported script scale' 'setExportedScriptScale'
  addItem menu 'save picture of all scripts' 'saveScriptsImage'
  addItem menu 'copy all scripts to clipboard' 'copyScriptsToClipboard'
  clip = (readClipboard)
  if (beginsWith clip 'GP Scripts') {
	addItem menu 'paste scripts' 'pasteScripts'
  } (beginsWith clip 'GP Script') {
	addItem menu 'paste script' 'pasteScripts'
  }
  cb = (ownerThatIsA morph 'ClassBrowser')
  if (notNil cb) {
    if (wasEdited (handler cb)) {
      addLine menu
      addItem menu 'save changes' (action 'saveEditedFunction' (handler cb))
      addItem menu 'revert' (action 'revertEditedFunction' (handler cb))
    }
  }
  return menu
}

method cleanUp ScriptEditor {
  order = (function m1 m2 {return ((top m1) < (top m2))})
  alignment = (newAlignment 'multi-line' nil 'fullBounds' order)
  setPadding alignment (20 * (blockScale))
  setVPadding alignment (20 * (blockScale))
  setMorph alignment morph
  fixLayout alignment
}

method setBlockSize ScriptEditor {
  menu = (menu nil (action 'setBlockScalePercent' this) true)
  currentPercent = ((global 'blockScale') * 100)
  for percent (list 50 75 100 125 150 200 250) {
	  if (currentPercent == percent) {
	  	addItem menu (join '' percent '% ✓') percent
	  } else {
	  	addItem menu (join '' percent '%') percent
	  }
  }
  popUpAtHand menu (global 'page')
}

method setBlockScalePercent ScriptEditor percent {
  if (or (percent < 25) (percent > 300)) { return }
  pe = (findProjectEditor)
  oldBlockScale = (global 'blockScale')
  if (notNil pe) {
	setGlobal 'blockScale' (percent / 100)
	languageChanged pe
	saveToUserPreferences pe 'blockSizePercent' percent
  }
  factor = ((global 'blockScale') / oldBlockScale)
  if (1 == factor) { return }

  originX = (left morph)
  originY = (top morph)
  for m (parts morph) {
	if (isClass (handler m) 'Block') {
	  dx = (round (factor * ((left m) - originX)))
	  dy = (round (factor * ((top m) - originY)))
	  setPosition m (originX + dx) (originY + dy)
    }
  }
  if (isClass (parentHandler morph) 'ScrollFrame') {
    updateSliders (parentHandler morph)
  }
}

// highlighting

method updateHighlights ScriptEditor {
  scripter = (ownerThatIsA morph 'Scripter')
  if (and (isNil scripter) (notNil (ownerThatIsA morph 'MicroBlocksScripter'))) { return }
  if (notNil scripter) { targetObj = (targetObj (handler scripter)) }
  taskMaster = (getField (page morph) 'taskMaster')
  for m (parts morph) {
    if (isClass (handler m) 'Block') {
      tasks = (numberOfTasksRunning taskMaster  (expression (handler m)) targetObj)
      if (tasks > 0) {
        addHighlight m
        if (tasks > 1) {
          st = (getStackPart m)
          if (isNil st) {
            addStackPart m (scale * 6) 2
          }
          sp = (getSignalPart m)
          if (isNil sp) {
            addSignalPart m tasks
          } ((param sp) != tasks) {
            removeSignalPart m
            addSignalPart m tasks
          }
        } else {
          removeSignalPart m
        }
      } else {
        removeSignalPart m
        removeStackPart m
        removeHighlight m
      }
    }
  }
}

// auto-resizing

method adjustSizeToScrollFrame ScriptEditor scrollFrame {
  box = (copy (bounds (morph scrollFrame)))
  area = (scriptsArea this)
  if (notNil area) {
    merge box (expandBy area (50 * (global 'scale')))
  }
  setBounds morph box
}

method scriptsArea ScriptEditor {
  area = nil
  for m (parts morph) {
    if (isNil area) {
      area = (fullBounds m)
    } else {
      merge area (fullBounds m)
    }
  }
  return area
}

// serialization

method preSerialize ScriptEditor {
  setCostume morph nil
  setCostume feedback nil
}

method postSerialize ScriptEditor {
  redraw (handler feedback)
}

// keyboard editing

method edit ScriptEditor elementOrNil aFocus x y {
  page = (page morph)
  stopEditing (keyboard page)
  focus = aFocus
  if (isNil focus) {focus = (initialize (new 'ScriptFocus') this elementOrNil x y)}
  if (and (notNil x) (notNil y)) {setCenter (morph focus) x y}
  focusOn (keyboard page) focus
  scriptChanged this
}

method startEditing ScriptEditor {
  page = (page morph)
  inset = (50 * (global 'scale'))
  sorted = (sortedScripts this)
  if (notEmpty sorted) {
    elem = (first sorted)
  } else {
    elem = this
    x = (+ inset (left morph))
    y = (+ inset (top morph))
  }
  stopEditing (keyboard page)
  focus = (initialize (new 'ScriptFocus') this elem x y)
  if (and (notNil x) (notNil y)) {setPosition (morph focus) x y}
  focusOn (keyboard page) focus
}

method stopEditing ScriptEditor {
  if (isNil focus) { return }
  focus = nil
  root = (handler (root morph))
  if (isClass root 'Page') {stopEditing (keyboard root) this}
  scriptChanged this
}

method focus ScriptEditor {return focus}
method setFocus ScriptEditor aScriptFocus {focus = aScriptFocus}

method sortedScripts ScriptEditor {
  sortingOrder = (function m1 m2 {return ((top m1) < (top m2))})
  morphs = (sorted (toArray (parts morph)) sortingOrder)
  result = (list)
  for each morphs {
    hdl = (handler each)
    if (isClass hdl 'Block') {add result hdl}
  }
  return result
}

method accepted ScriptEditor aText {
  if (notNil focus) {
    inp = (handler (ownerThatIsA (morph aText) 'InputSlot'))
    addSchedule (global 'page') (schedule (action 'edit' this inp))
  }
}

method cancelled ScriptEditor aText {
  if (notNil focus) {
    inp = (handler (ownerThatIsA (morph aText) 'InputSlot'))
    edit this inp
  }
}

// undrop

method clearDropHistory ScriptEditor {lastDrop = nil}

method recordDrop ScriptEditor block target input next {
  lastDrop = (new 'DropRecord' block target input next)
}

method undrop ScriptEditor {
  if (notNil lastDrop) {restore lastDrop this}
  lastDrop = nil
  scriptChanged this
}

method grab ScriptEditor aBlock {
  h = (hand (handler (root morph)))
  setPosition (morph aBlock) (x h) (y h)
  grab h aBlock
  changed h
}

// change detection

method scriptChanged ScriptEditor {
  scripterM = (ownerThatIsA morph 'Scripter')
  if (isNil scripterM) { scripterM = (ownerThatIsA morph 'MicroBlocksScripter') }
  if (notNil scripterM) { scriptChanged (handler scripterM) }
}

// saving script image

method setExportedScriptScale ScriptEditor {
  // Set the scale used for exported scripts.

  menu = (menu nil (action 'setExportScale' this) true)
  addItem menu 'small (50%)' 50
  addItem menu 'normal (65%)' 65
  addItem menu 'large (100%)' 100
  addItem menu 'printable (200%)' 200
  popUpAtHand menu (global 'page')
}

method setExportScale ScriptEditor percent {
  setGlobal 'blockExportScale' (percent / 100)
}

method saveScriptsImage ScriptEditor fName doNotCrop {
  // draw scripts (cropped to the dimensions of the ScriptEditor's scroll frame)
  // Use the current block scale, not blockExportScale to support semi-WYSIWYG.

  timer = (newTimer)
  bm = (croppedScriptsCostume this doNotCrop)

  scriptsString = nil
  mbScripter = (ownerThatIsA morph 'MicroBlocksScripter')
  if (notNil mbScripter) {
    scriptsString = (join 'GP Scripts' (newline) (allScriptsString (handler mbScripter)))
  }

  if (or ((width bm) == 0) ((height bm) == 0)) { return } // no scripts; empty bitmap
  pngData = (encodePNG bm nil scriptsString)

  defaultFileName = (join 'allScripts' (msecsSinceStart) '.png')
  if ('Browser' == (platform)) {
    if ((msecs timer) > 4000) {
      // if it has been more than a few seconds the user must click again to allow file save
      inform (global 'page') (localized 'PNG preparation complete.')
    }
	browserWriteFile pngData defaultFileName 'scriptImage'
  } else {
    if (isNil fName) {
      fName = (fileToWrite defaultFileName '.png')
      if ('' == fName) { return }
    }
    if (not (endsWith fName '.png')) { fName = (join fName '.png') }
	writeFile fName pngData
  }
}

method croppedScriptsCostume ScriptEditor doNotCrop {
  r = (scriptsRect this)
  w = (ceiling (width r))
  h = (ceiling (height r))
  if (or (w == 0) (h == 0)) { return (newBitmap 1 1) }

  if (true != doNotCrop) {
    // limit size to dimensions of ScriptEditor's scroll frame
    bnds = (bounds (owner morph))
    if (or (w > (width bnds)) (h > (height bnds))) {
      print 'Cropping scripts image to avoid running out of memory'
      w = (min w (width bnds))
      h = (min h (height bnds))
    }
  }
  if ('Browser' == (platform)) { // in browser, draw on Texture for speed
    result = (newTexture w h (gray 255 0))
  } else {
    result = (newBitmap w h (gray 255 0))
  }
  ctx = (newGraphicContextOn result)
  setOffset ctx (0 - (left r)) (0 - (top r))
  fullDrawOn morph ctx
  if ('Browser' == (platform)) {
    result = (toBitmap result)
  }
  return result
}

method scriptsRect ScriptEditor {
  // Return a rectangle that enclose all my scripts.

  if (isEmpty (parts morph)) { return (rect 0 0 0 0) }
  for m (parts morph) {
    if (isNil result) {
      result = (fullBounds m)
    } else {
      merge result (fullBounds m)
    }
  }
  return (expandBy result 2) // add an extra pixel all around to allow for anti-aliasing
}

// script copy/paste via clipboard

method copyScriptsToClipboard ScriptEditor {
  scripter = (ownerThatIsA morph 'MicroBlocksScripter')
  if (isNil scripter) { return }
  setClipboard (allScriptsString (handler scripter))
}

method copyScriptsToClipboardAsURL ScriptEditor {
  scripter = (ownerThatIsA morph 'MicroBlocksScripter')
  if (isNil scripter) { return }
  scriptsString = (allScriptsString (handler scripter))
  urlPrefix = (urlPrefix (findMicroBlocksEditor))
  setClipboard (join urlPrefix '#scripts=' (urlEncode scriptsString true))
}

method pasteScripts ScriptEditor {
  scripter = (ownerThatIsA morph 'Scripter')
  if (isNil scripter) { scripter = (ownerThatIsA morph 'MicroBlocksScripter') }
  if (isNil scripter) { return }
  s = (readClipboard)
  i = (find (letters s) (newline))
  s = (substring s i)
  pasteScripts (handler scripter) s true
  scriptChanged (handler scripter)
}
