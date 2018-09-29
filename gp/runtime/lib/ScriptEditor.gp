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
    if (isClass load 'Block') {updateFeedback this load hand}
  }
  updateHighlights this
}

// events

method wantsDropOf ScriptEditor aHandler {
  return (or
    (isAnyClass aHandler 'Block' 'CommandSlot')
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
  if (isClass (handler (owner morph)) 'ScrollFrame') {updateSliders (handler (owner morph))}
  scriptChanged this
}

method clicked ScriptEditor hand {
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

method targetFor ScriptEditor block x y {
  // answer a snapping target or nil
  if ((type block) == 'reporter') {return (inputFor this block x y)}
  isHatSrc = (== (type block) 'hat')
  scale = (scale block)
  thres = (15 * scale)
  x = (left (morph block))
  y = (top (morph block))
  yb = (bottom (morph (bottomBlock block)))
  others = (reversed (allMorphs morph))
  remove others morph
  remove others (morph block)
  for i (count others) {
    b = (at others i)
    if (and (isClass (handler b) 'Block') (isNil (function (handler b)))) {
      if isHatSrc {
        if (and ((type (handler b)) == 'command') (this === (handler (owner b)))) { // top of stack
          xd = (abs (x - (left b)))
          yd = (abs ((top b) - yb))
          if (and (xd < thres) (yd < thres)) {return (array (handler b))}
        }
      } else {
        if ((type (handler b)) == 'command') {
          xd = (abs (x - (left b)))
          yd = (abs (y - (bottom b)))
          if (and (xd < thres) (yd < thres)) {return (handler b)}
          if (this === (handler (owner b))) { // top of stack
            yd = (abs ((top b) - yb))
            if (and (xd < thres) (yd < thres)) {return (array (handler b))}
          }
        } ((type (handler b)) == 'hat') {
          xd = (abs (x - (left b)))
          yd = (abs (y - (bottom b)))
          if (and (xd < thres) (yd < thres)) {return (handler b)}
        }
      }
    } (and (not isHatSrc) (isClass (handler b) 'CommandSlot')) {
      xd = (abs (x - (+ (scaledCorner (handler b)) (left b))))
      yd = (abs (y - (+ (scaledCorner (handler b)) (top b))))
      if (and (xd < thres) (yd < thres)) {return (handler b)}
    }
  }
  return nil
}

method inputFor ScriptEditor block x y {
  // answer an input (slot or reporter) for dropping the block or nil
  area = (bounds (morph block))
  others = (reversed (allMorphs morph))
  remove others morph
  removeAll others (allMorphs (morph block))
  if (notNil x) {
    for i (count others) {
      b = (at others i)
      if (isAnyClass (handler b) 'InputSlot' 'BooleanSlot' 'ColorSlot') {
        bounds = (bounds b)
        if (and (isReplaceableByReporter (handler b)) (containsPoint bounds x y)) {
          return (handler b)
        }
      }
    }
  }
  for i (count others) {
    b = (at others i)
    if (or
        (and (isReplaceableByReporter (handler b)) (isAnyClass (handler b) 'InputSlot' 'BooleanSlot' 'ColorSlot'))
        (and
          (isClass (handler b) 'Block')
          ((type (handler b)) == 'reporter')
          (isClass (handler (owner b)) 'Block')
          ((grabRule b) != 'template')
          (not (isPrototype (handler b)))
        )
      ) {
      bounds = (bounds b)
      if (intersects bounds area) {
        return (handler b)
      }
    }
  }
  return nil
}

method updateFeedback ScriptEditor block hand {
  hide feedback
  if (isNil block) {return}
  trgt = (targetFor this block (x hand) (y hand))
  if (notNil trgt) {
    if ((type block) != 'reporter') { // command or hat types
      showCommandDropFeedback this trgt
    } ((type block) == 'reporter') {
      showReporterDropFeedback this trgt
    }
    addPart morph feedback // come to front
    show feedback
  }
}

method showCommandDropFeedback ScriptEditor target {
  setHeight (bounds feedback) (scale * 5)
  if (isClass target 'Block') {
    nb = (next target)
    top = (bottom (morph target))
    if (notNil nb) {top = (bottomLine target)}
    setPosition feedback (left (morph target)) top
  } (isClass target 'Array') {
    target = (at target 1)
    top = ((top (morph target)) - (height feedback))
    setPosition feedback (left (morph target)) top
  } (isClass target 'CommandSlot') {
    nb = (nested target)
    top = (+ (top (morph target)) (scaledCorner target))
    if (isNil nb) {top += (scaledCorner target)}
    setPosition feedback (+ (scaledCorner target) (left (morph target))) top
  }
  setCostume feedback (newBitmap (width (morph target)) (scale * 5) (gray 255))
}

method showReporterDropFeedback ScriptEditor target {
  setBounds feedback (expandBy (bounds (morph target)) (12 * scale))
  area = (rect 0 0 (width feedback) (height feedback))
  radius = (10 * scale)
  border = (3 * scale)
  fillColor = (gray 255 150) // translucent
  borderColor = (gray 255)
  bm = (newBitmap (width area) (height area))
  fillRoundedRect (newShapeMaker bm) area radius fillColor border borderColor borderColor
  setCostume feedback bm
}

// context menu

method contextMenu ScriptEditor {
  menu = (menu nil this)
  addItem menu 'clean up' 'cleanUp' 'arrange scripts'
  if (and (notNil lastDrop) (isRestorable lastDrop)) {
    addItem menu 'undrop' 'undrop' 'undo last drop'
  }
  addLine menu
  addItem menu 'save picture of all scripts' 'saveScriptsImage'
  addItem menu 'copy all scripts to clipboard' 'copyScriptsToClipboard'
  clip = (getClipboard)
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
  alignment = (newAlignment 'column' nil 'fullBounds' order)
  setMorph alignment morph
  fixLayout alignment
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
        addHighlight m (scale * 4)
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
  focus = nil
  root = (handler (root morph))
  if (isClass root 'Page') {stopEditing (keyboard root) this}
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

method inputContentsChanged ScriptEditor anInput {
  if (notNil focus) {
    edit this anInput
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
  setCenter (morph aBlock) (x h) (y h)
  grab h aBlock
}

// change detection

method scriptChanged ScriptEditor {
  scripterM = (ownerThatIsA morph 'Scripter')
  if (isNil scripterM) { scripterM = (ownerThatIsA morph 'MicroBlocksScripter') }
  if (notNil scripterM) { scriptChanged (handler scripterM) }
}

// saving script image

method saveScriptsImage ScriptEditor {
  fName = (uniqueNameNotIn (listFiles (gpFolder)) 'scriptsImage' '.png')
  fName = (fileToWrite fName '.png')
  if ('' == fName) { return }
  if (not (endsWith fName '.png')) { fName = (join fName '.png') }
  gc
  bnds = (bounds morph)
  bm = (newBitmap (width bnds) (height bnds))
  draw2 morph bm (- (left bnds)) (- (top bnds))
  pixelsPerInch = (72 * (global 'scale'))
  writeFile fName (encodePNG bm pixelsPerInch)
}

// script copy/paste via clipboard

method copyScriptsToClipboard ScriptEditor {
  scripter = (ownerThatIsA morph 'Scripter')
  if (isNil scripter) { return }
  targetObj = (targetObj (handler scripter))
  setClipboard (join 'GP Scripts' (newline) (scriptStringWithDefinitionBodies (classOf targetObj)))
}

method pasteScripts ScriptEditor {
  scripter = (ownerThatIsA morph 'Scripter')
  if (isNil scripter) { return }
  s = (getClipboard)
  i = (find (letters s) (newline))
  s = (substring s i)
  pasteScripts (handler scripter) s
  scriptChanged (handler scripter)
}
