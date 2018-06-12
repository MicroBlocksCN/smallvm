// Morphic Core Framework

// global settings and event hooks
// define these as methods of your own handlers
// to override the default behavior

to step aHandler { noop }
to redraw aHandler { noop }

to duplicate aHandler {
  error (join (className (classOf aHandler)) 'cannot be duplicated')
  return nil
}

to handMoveOver aHandler { noop }
to handDragOver aHandler aHand aDraggedHandler { noop }
to handEnter aHandler { noop }
to handLeave aHandler { noop }

to handDownOn aHandler hand {
  result = false
  if (dispatchEvent aHandler 'whenClicked') { result = true }
  if (dispatchEvent aHandler 'whenTracking' (self_mouseX) (self_mouseY)) {
    focusOn hand aHandler
    result = true
  }
  return result
}
to handMoveFocus aHandler { dispatchEvent aHandler 'whenTracking' (self_mouseX) (self_mouseY) }
to handUpOn aHandler {return false}

to clicked aHandler {return false}

to rightClicked aHandler {
  page = (global 'page')
  if (not (shiftKeyDown (keyboard page))) {
    devMenu (hand page) aHandler
    return true
  }
  return false
}

to touchHold aHandler {return false}
to swipe aHandler scrollX scrollY { return (dispatchEvent aHandler 'whenScrolled' scrollX scrollY) }
to pageResized aHandler { dispatchEvent aHandler 'whenPageResized' }
to changed aHandler { noop }
to okayToBeDestroyedByUser aHandler {return true}
to destroyedMorph aHandler { noop }

to acceptsEvents aHandler { return (and (notNil aHandler) (acceptsEvents (morph aHandler))) }
to isSelectable aHandler {return false}
to setMorph aHandler aMorph {setField aHandler 'morph' aMorph}
to doubleClicked aHandler {return false}

to aboutToBeGrabbed aHandler { noop }
to justGrabbedPart aHandler part { noop }
to justDropped aHandler { dispatchEvent aHandler 'whenDropped' }

to wantsDropOf dropReceiver aHandler {
  if (hasField dropReceiver 'morph') {
    return ('draggableParts' == (grabRule (getField dropReceiver 'morph')))
  }
  return false
}

to justReceivedDrop dropReceiver aHandler {
  if (and
    (hasField dropReceiver 'morph')
    (hasField aHandler 'morph')
    ('draggableParts' == (grabRule (getField dropReceiver 'morph'))) ) {
      setGrabRule (getField aHandler 'morph') 'defer'
  }
}

to morph aHandler {
  if (isNil aHandler) {return nil}
  return (getField aHandler 'morph')
}

// stubs for handler pre- and post-serialization

to preSerialize aHandler {}
to postSerialize aHandler {}

// Hand

defineClass Hand morph page isDown x y currentMorphs lastTouched lastClicked lastClickTime lastTouchTime oldOwner oldX oldY focus

to newHand {
  hand = (new 'Hand' nil nil false 0 0 (list) nil nil (newTimer) nil nil nil)
  morph = (newMorph hand)
  setMorph hand morph
  return hand
}

method page Hand {return page}
method setPage Hand aPage {page = aPage}
method isDown Hand {return isDown}
method x Hand {return x}
method y Hand {return y}
method focus Hand {return focus}
method focusOn Hand aHandler {focus = aHandler}
method changed Hand {changed page}

method objectAt Hand {
  // Answer the topmost morph under the hand.
  for m (reversed (morphsAt (morph page) x y)) {
    hdl = (handler m)
    if (and (notNil hdl) (not (isClass hdl 'Caret'))) {
      if (and (isVisible m) (containsPoint (visibleBounds m) x y)) {
        if (noticesTransparentTouch m) {return hdl}
        if (not (isTransparentAt m x y)) {return hdl}
      }
    }
  }
  return page
}

// grabbing and dropping

method grabbedObject Hand {
  if ((count (parts morph)) > 1) {return (handler (at (parts morph) 2))}
  return nil
}

method grab Hand handler {
  if (notNil (owner (morph handler))) {parent = (handler (owner (morph handler)))}
  aboutToBeGrabbed handler
  oldOwner = parent
  oldX = (left (morph handler))
  oldY = (top (morph handler))
  fb = (fullBounds (morph handler))
  if (not (containsPoint fb x y)) {
    // avoid "trailing behind" the mouse cursor
    setCenter (morph handler) x y
  }
  removeAllParts morph
  shadow = (shadow (morph handler) 60 (* (global 'scale') 7))
  addPart morph shadow
  addPart morph (morph handler)
  justGrabbedPart parent handler
}

method rootForGrab Hand handler {
  result = handler
  while (notNil result) {
    rule = (grabRule (morph result))
    if (rule == 'ignore') {return nil}
    if (rule == 'handle') {return result}
    if (rule == 'draggableParts') {return result}
    if (rule == 'template') {return (duplicate result)}
    parent = (owner (morph result))
    if (isNil parent) {return nil}
    if ('draggableParts' == (grabRule parent)) {
      setGrabRule (morph result) 'handle'
      return result
    }
    result = (handler parent)
  }
  return nil
}

method drop Hand {
  src = (grabbedObject this)
  if (isNil src) {return}
  trg = (objectAt this x y)
  if (isNil trg) {trg = page}
  while (not (wantsDropOf trg src)) {
    parent = (owner (morph trg))
    if (isNil parent) {return}
    trg = (handler parent)
  }
  if (isClass src 'Monitor') {
	// adjust a Monitor's scale when dropped
	if (isClass trg 'Stage') { // scale to stage
	  setScale (morph src) ((scale (morph trg)) / (global 'scale'))
	} else { // normal scale
	  setScale (morph src) 1
	}
  }
  destroy (at (parts morph) 1)
  addPart (morph trg) (morph src)
  justDropped src this
  justReceivedDrop trg src
}

method oldOwner Hand { return oldOwner }

method returnGrabbedObjectToOldPosition Hand aHandler {
  if (and (notNil aHandler) (notNil oldX) (notNil oldY)) {
    setPosition (morph aHandler) oldX oldY
  }
}

method animateBackToOldOwner Hand aMorph {
  doneAction = (action
	(function oldOwner m {
	  if (isNil oldOwner) {
		removeFromOwner m
		return
	  }
	  if (isClass (handler m) 'Block') {
		if (isClass (expression (handler m)) 'Reporter') {
		  scriptEditor = (ownerThatIsA oldOwner 'ScriptEditor')
		  if (notNil scriptEditor) {
			addPart scriptEditor m
			raise scriptEditor 'scriptChanged'
		  }
		} (isClass (handler oldOwner) 'Block') {
		  setNext (handler oldOwner) (handler m)
		} (isClass (handler oldOwner) 'CommandSlot') {
		  setNested (handler oldOwner) (handler m)
		} else {
		  addPart oldOwner m
		}
	  } else {
		addPart oldOwner m
	  }
	})
	(morph oldOwner) aMorph)
  addPart (morph page) aMorph // move in front of everything else during the animation
  animateTo aMorph oldX oldY doneAction
}

// stepping

method step Hand {
  // generate touch-hold events
  if (notNil lastTouchTime) {
    if ((msecs lastTouchTime) > 300) {processTouchHold this (currentObject this)}
  }
}

method processEvent Hand evt {
  type  = (at evt 'type')
  if (type == 'mousewheel') {
    processSwipe this (at evt 'x') (at evt 'y')
    return
  }
  x = (at evt 'x')
  y = (at evt 'y')
  setPosition morph x y
  if (type == 'mouseMove') {
	processMove this
  } (type == 'mouseDown') {
    isDown = true
	if (notNil (at evt 'modifierKeys')) { updateModifiedKeys (keyboard page) (at evt 'modifierKeys') }
    processDown this (at evt 'button')
  } (type == 'mouseUp') {
    isDown = false
	if (notNil (at evt 'modifierKeys')) { updateModifiedKeys (keyboard page) (at evt 'modifierKeys') }
    processUp this
	// Workaround for keyboard popping up on every mouse up on mobile Chrome:
	if (isNil (focus (keyboard page))) { showKeyboard false }
  }
}

method currentObject Hand {
  if (notNil focus) {return focus}
  return (objectAt this x y)
}

method processMove Hand {
  if (notNil focus) {
	handMoveFocus focus this
	return
  }
  oldMorphs = currentMorphs
  currentMorphs = (list)
  m = (morph (currentObject this))
  stopped = false
  while (and (not stopped) (notNil m)) {
    add currentMorphs m
    if (acceptsEvents m) {
      h = (handler m)
      if isDown {
        dragged = (grabbedObject this)
        if (isNil dragged) {
          handMoveOver h this
          if (notNil lastTouched) {
            toBeGrabbed = (rootForGrab this lastTouched)
            if (notNil toBeGrabbed) {
              closeUnclickedMenu page toBeGrabbed
              grab this toBeGrabbed
            }
          }
        } else {
          handDragOver h this dragged
        }
      }
      if (not (contains oldMorphs m)) {handEnter h this}
    }
    stopped = (isSelectable h this)
    m = (owner m)
  }
  for oldM oldMorphs {if (and (acceptsEvents oldM) (not (contains currentMorphs oldM))) {handLeave (handler oldM) this}}
  lastTouched = nil
  lastTouchTime = nil
}

method processSwipe Hand xDelta yDelta {
  trg = (currentObject this)
  while (not (and (acceptsEvents trg) (swipe trg xDelta yDelta this))) {trg = (parentHandler (morph trg))}
}

method processDown Hand button {
  currentObj = (currentObject this)
  stopEditingUnfocusedText this currentObj
  if (or (button == 3) (commandKeyDown (keyboard page))) {
    processRightClicked this currentObj
    return
  }
  closeUnclickedMenu page currentObj
  lastTouched = currentObj
  lastTouchTime = (newTimer)
  if (and (optionKeyDown (keyboard page)) (notNil currentObj)) {
	showInScripter currentObj
	lastTouched = nil
	lastTouchTime = nil
	return
  }
  trg = currentObj
  while (notNil trg) {
	if (and (acceptsEvents trg) (handDownOn trg this)) { return }
	trg = (parentHandler (morph trg))
  }
}

method processUp Hand {
  if (notNil focus) {
    handUpOn focus this
    focus = nil
    return
  }
  if (notNil (grabbedObject this)) {
	drop this
	return
  }
  current = (objectAt this x y)
  trg = current
  while (not (and (acceptsEvents trg) (handUpOn trg this))) {trg = (parentHandler (morph trg))}
  if (current === lastTouched) {
    trg = current
    while (or (not (acceptsEvents trg)) (false == (clicked trg this))) {trg = (parentHandler (morph trg))}
    if (current === lastClicked) {
      if ((msecs lastClickTime) < 500) {
        trg = current
        while (not (and (acceptsEvents trg) (doubleClicked trg this))) {trg = (parentHandler (morph trg))}
      }
    }
    lastClicked = current
    reset lastClickTime
  }
  lastTouched = nil
  lastTouchTime = nil
}

method processTouchHold Hand currentObj {
  isMobile = (or
  	('iOS' == (platform))
	(and ('Browser' == (platform)) (browserIsMobile)))
  if isMobile {
	// on mobile devices, make map touchHold gestures to rightClicked
	processRightClicked this currentObj
	return
  }
  trg = currentObj
  while (notNil trg) {
    if (and (acceptsEvents trg) (touchHold trg this)) {
      lastTouched = nil
      lastTouchTime = nil
      return
    }
    m = (morph trg)
    if (and (notNil m) (notNil (owner m))) {
      trg = (handler (owner m))
    } else {
      trg = nil
    }
  }
  if (isNil focus) {
    processMove this
  }
  lastTouched = nil
  lastTouchTime = nil
}

method processRightClicked Hand currentObj {
  if (shiftKeyDown (keyboard page)) {
    devMenu this currentObj
    return
  }
  trg = currentObj
  while (not (and (acceptsEvents trg) (rightClicked trg this))) {
	if (isNil (owner (morph trg))) { return } // uncommon, but can happen
    trg = (handler (owner (morph trg)))
    if (or (trg == page) (isClass trg 'Stage')) { return } // don't propagate rightClicked through an object to the page or stage
  }
  lastTouched = nil
  lastTouchTime = nil
}

method stopEditingUnfocusedText Hand currentObj {
  caret = (focus (keyboard page))
  if (isClass caret 'ScriptFocus') {
    // cancel caret
    return
  }
  if (or (not (isClass caret 'Caret')) (currentObj == (target caret))) { return }
  if (not (isClass currentObj 'Trigger')) {
    if ((editRule (target caret)) == 'code') {
      if (notNil (ownerThatIsA (morph (target caret)) 'Synopsis')) {
        cancel caret
      } else {
        accept caret
      }
    } else {
      accept caret
    }
  } ((editRule (target caret)) != 'code') {
      if (isClass (handler (owner (morph (target caret)))) 'ScriptFocus') {
        return
      }
      accept caret
  }
}

// menus

method devMenu Hand currentObj {
  if (isNil currentObj) {currentObj = (currentObject this)}
  se = (ownerThatIsA (morph currentObj) 'ScriptEditor')
  if (notNil se) {
    stopEditing (handler se)
  }
  if (not (devMode)) {
    if (isNil (ownerThatIsA (morph currentObj) 'Stage')) { return } // do nothing for objects in a Stage
    if (isClass currentObj 'Stage') { return } // do nothing if currentObj is a Stage
//	if (isNil (scripts (classOf currentObj))) { return } // do nothing for non-user-created objects
  }
  if (isTopLevel (morph currentObj)) {
    if (not (and (devMode) (shiftKeyDown (keyboard page)))) {
	  // if not in devMode with shift key pressed, skip the parts menu
	  popUpAtHand (contextMenu (morph currentObj)) page
	  return
	}
  }
  // display the parts menu
  scale = (global 'scale')
  menu = (menu nil this)
  for each (allOwners (morph currentObj)) {
    if (or (devMode) (not (isAnyClass (handler each) 'Page' 'Stage' 'ProjectEditor'))) {
      if (isNil (costumeData each)) {
        thm = (newBitmap (* scale 18) (* scale 18))
      } else {
        thm = (thumbnail (costumeData each) (* scale 18) (* scale 18))
      }
      addItem menu (join (toString (handler each)) '...') (action 'popUpAtHand' (contextMenu each) page) nil thm
    }
  }
  popUpAtHand menu page
}

method explore Hand anObject {
    ins = (explorerOn anObject)
    setPosition (morph ins) x y
    addPart page ins
}

// convenience methods to access hand state

to handX { return (x (hand (global 'page'))) }
to handY { return (y (hand (global 'page'))) }
to handIsDown { return (isDown (hand (global 'page'))) }
to keyIsDown key { return (keyDown (global 'page') key) }

// Keyboard

defineClass Keyboard page focus currentKeys

method page Keyboard {return page}
method setPage Keyboard aPage {page = aPage}
method focus Keyboard {return focus}
method focusOn Keyboard aHandler {focus = aHandler}

method processEvent Keyboard evt {
  type = (at evt 'type')
  key = (at evt 'keycode')
  updateModifiedKeys this (at evt 'modifierKeys')
  if (and (1 <= key) (key <= 255)) {
    if (type == 'keyDown') {
	  if (and (27 == key) (isInPresentationMode this)) {
		stopAll page
		exitPresentationMode page
		return
	  }
      if (and (27 == key) (isNil focus)) { // escape key
        stopAll page
        return
      } (and (13 == key) (isNil focus) (shiftKeyDown this)) { // shift-enter initiates keyboard editing for blocks
        startEditingScripts
        return
      }
      if (at currentKeys key) { return } // suppress duplicated keyDown events on Gnome and some other Linux desktops
      atPut currentKeys key true
	  if (isNil focus) {
        keyName = nil
        if (8 == key) { keyName = 'delete'
        }  (9 == key) { keyName = 'tab'
        } (13 == key) { keyName = 'enter'
        } (32 == key) { keyName = 'space'
        } (37 == key) { keyName = 'left arrow'
        } (38 == key) { keyName = 'up arrow'
        } (39 == key) { keyName = 'right arrow'
        } (40 == key) { keyName = 'down arrow'
        } (127 == key) { keyName = 'delete'
        } (and (65 <= key) (key <= 90)) { keyName = (string (key + 32)) // use lowercase key name
        }
        if (isNil keyName) {
		  ch = (at evt 'char')
		  if (and (32 < ch) (ch < 128)) { keyName = (string ch) } // symbols keys
        }
        if (notNil keyName) {
          dispatchKeyPressedEvent page keyName
        }
	  }
    } (type == 'keyUp') {
      atPut currentKeys key false
    }
  }
  if (notNil focus) {
    call type focus evt this
  }
}

method isInPresentationMode Keyboard {
  for m (parts (morph (global 'page'))) {
	if (isClass (handler m) 'Stage') { return true }
  }
  return false
}

method edit Keyboard aText slot keepFocus {
  if (isNil keepFocus) {keepFocus = false}
  if (not keepFocus) {stopEditing this}
  focus = (new 'Caret')
  initialize focus aText slot
}

method stopEditing Keyboard {
  if (isAnyClass focus 'Caret' 'ScriptFocus') {destroy focus}
  focus = nil
}

method shiftKeyDown Keyboard { return (at currentKeys 16) }
method controlKeyDown Keyboard { return (at currentKeys 17) }
method optionKeyDown Keyboard { return (at currentKeys 18) }
method commandKeyDown Keyboard { return (or (at currentKeys 91) (at currentKeys 93)) }

method keyDown Keyboard keyName {
  if ((byteCount keyName) == 1) {
    key = (byteAt keyName 1)
	if (isLowerCase keyName) { key += -32 }
	return (at currentKeys key)
  }
  if ('delete' == keyName) { return (at currentKeys 8) }
  if ('space' == keyName) { return (at currentKeys 32) }
  if ('right arrow' == keyName) { return (at currentKeys 39) }
  if ('left arrow' == keyName) { return (at currentKeys 37) }
  if ('down arrow' == keyName) { return (at currentKeys 40) }
  if ('up arrow' == keyName) { return (at currentKeys 38) }
  if ('shift' == keyName) { return (at currentKeys 16) }
  return false
}

method keyToEventName Keyboard key {
  // Convert a key number to a key event name.
  if (8 == key) { return 'delete' }
  if (16 == key) { return 'shift' }
  if (32 == key) { return 'space' }
  if (39 == key) { return 'right arrow' }
  if (37 == key) { return 'left arrow' }
  if (40 == key) { return 'down arrow' }
  if (38 == key) { return 'up arrow' }
  if (key < 128) { return (string key) }
  return ''
}

method updateModifiedKeys Keyboard modifierKeys {
  if (isNil modifierKeys) { return }
  shiftDown = ((modifierKeys & 1) != 0)
  ctrlDown = ((modifierKeys & 2) != 0)
  optDown = ((modifierKeys & 4) != 0)
  cmdDown = ((modifierKeys & 8) != 0)
  atPut currentKeys 16 shiftDown
  atPut currentKeys 17 ctrlDown
  atPut currentKeys 18 optDown
  atPut currentKeys 91 cmdDown
  atPut currentKeys 93 cmdDown
}

// Page

defineClass Page morph hand keyboard taskMaster soundMixer schedules activeMenu isChanged color activeHint isShowingConnectors foreground devMode profileTimer droppedFiles

to go tryRetina {
  // Run 'go' at command prompt to open or restart.
  if (and (isNil (global 'page')) (notNil (shared 'page' (topLevelModule)))) {
	// copy page and other state from topLevelModule
	pageVars = (array
		'authoringSpecs' 'page' 'scale' 'flat' 'flatBlocks' 'stealthBlocks' 'stealthLevel')
	for varName pageVars {
	  // Move page state from topLevelModule to sessionModule
	  value = (shared varName (topLevelModule))
	  if (notNil value) { setGlobal varName value }
	  deleteVar (topLevelModule) varName
	}
	// set default values if necessary
	if (isNil (global 'scale')) { setGlobal 'scale' 1 }
	if (isNil (global 'flat')) { setGlobal 'flat' true }
	if (isNil (global 'flatBlocks')) { setGlobal 'flatBlocks' false }
	if (isNil (global 'stealthBlocks')) { setGlobal 'stealthBlocks' false }
	if (isNil (global 'stealthLevel')) { setGlobal 'stealthLevel' -50 }
  } else {
	if (isNil (global 'page')) { openPage tryRetina }
  }
  startSteppingSafely (global 'page')
}

to openPage tryRetina {
  if (isNil tryRetina) {tryRetina = true}
  page = (newPage 1040 650) // make one dimension > 1024 for best iOS retina detection
  setGlobal 'page' page
  open page tryRetina
  changed page
  step (morph page)
}

to newPage width height color {
  if (isNil width) { width = 500 }
  if (isNil height) { height = 500 }
  if (isNil color) {color = (color 250 250 250)}
  page = (new 'Page' nil nil nil (newTaskMaster) (newSoundMixer) (list) nil false color nil false nil true nil)
  morph = (newMorph page)
  setTransparentTouch morph true
  setWidth (bounds morph) width
  setHeight (bounds morph) height
  setMorph page morph
  hand = (newHand)
  setPage hand page
  setHand page hand
  keyboard = (new 'Keyboard' page nil (newArray 255 false))
  setKeyboard page keyboard
  setField page 'droppedFiles' (list)
  return page
}

method open Page tryRetina title {
  setGlobal 'page' this
  setGlobal 'scale' 1
  setGlobal 'flat' true
  setGlobal 'flatBlocks' false
  setGlobal 'stealthBlocks' false
  setGlobal 'stealthLevel' -50
  setClipping morph true
  openWindow (width morph) (height morph) tryRetina title
  winSize = (windowSize)
  setExtent morph (at winSize 3) (at winSize 4) // actual extent
  if ((at winSize 3) > (at winSize 1)) {
	ratio = ((at winSize 3) / (at winSize 1))
	if (2 == ratio) {
	  setGlobal 'scale' 2 // retina display
	} else {
	  // revert to non-retina mode if scale != 2 (some iPhones have non-integer scales)
	  closeWindow
	  openWindow (width morph) (height morph) false title
	}
  }
}

to setBlocksMode option {
  // options can be 'normal', 'flat' or 'stealth'
  if (option == 'normal') {
    setGlobal 'flatBlocks' false
    setGlobal 'stealthBlocks' false
  } (option == 'flat') {
    setGlobal 'flatBlocks' true
    setGlobal 'stealthBlocks' false
  } (option == 'stealth') {
    setGlobal 'flatBlocks' true
    setGlobal 'stealthBlocks' true
  } else {
    error 'unsupported option' option
  }
}

to stealthLevel lo hi {
  if (isNil lo) {lo = 0}
  if (isNil hi) {hi = 255}
  st = ((hi - lo) / 100.0)
  sm = ((global 'stealthLevel') * st)
  return (round (lo + sm))
}

method hand Page {return hand}
method setHand Page aHand {hand = aHand}
method keyboard Page {return keyboard}
method setKeyboard Page aKeyboard {keyboard = aKeyboard}
method keyDown Page keyName { return (keyDown keyboard keyName) }
method soundMixer Page {return soundMixer}
method soundPlayer Page {return soundMixer} // backward compatibility for Mark's samples extension
method setColor Page newColor { color = newColor }
method width Page { return (width morph) }
method height Page { return (height morph) }

method addPart Page obj {
  if (isClass obj 'Morph') {
    addPart morph obj
  } else {
    addPart morph (morph obj)
  }
}

method removePart Page obj {
  if (isClass obj 'Morph') {
    removePart morph obj
  } else {
    removePart morph (morph obj)
  }
}

// developer mode

method setDevMode Page flag { devMode = flag }

method enterDeveloperMode Page {
  msg = 'With great power comes great responsibility.
Enter developer mode?'
  if (confirm this nil msg) {
	devMode = true
	editor = (findProjectEditor)
	if (notNil editor) {developerModeChanged editor}
  }
}

method exitDeveloperMode Page {
  setBlocksMode 'normal'
  devMode = false
  editor = (findProjectEditor)
  if (notNil editor) {developerModeChanged editor}
}

to devMode {
  page = (global 'page')
  if (isNil page) { return true }
  return (getField page 'devMode')
}

// stepping

method doOneCycle Page {
  // Note: 'step soundMixer' is called at multiple places to decrease the
  // chances of dropping a buffer. This allows the mixer to use a smaller
  // sound output buffer, thus decreasing the latency for starting a sound.

  t = (newTimer)
  step soundMixer
  gcIfNeeded
  processEvents this
  step hand
  step morph
  stepSchedules this
  wakeUpDisplayTasks taskMaster
  stepTasks taskMaster 75
  if isChanged {
    step soundMixer
    clearBuffer color
    draw morph nil 0 0 1 1 nil
    draw (morph hand)
	drawLinks this
	drawForeground this
    step soundMixer
    flipBuffer
    isChanged = false
  }
  step soundMixer
  // sleep for any extra time, but always sleep a little to ensure that
  // we get events (and to return control to the browser)
  sleepTime = (max 1 (15 - (msecs t)))
  waitMSecs sleepTime
}

method processEvents Page {
  evt = (getNextEvent)
  while (notNil evt) {
    nxt = (getNextEvent)
    type = (at evt 'type')
    if (or (type == 'mouseMove') (type == 'mouseDown') (type == 'mouseUp') (type == 'mousewheel')) {
      // optimization: out of consecutive mouseMove events only handle the last one
      if (not (and (type == 'mouseMove') (notNil nxt) ((at nxt 'type') == 'mouseMove'))) {
        processEvent hand evt
      }
    } (or (type == 'keyDown') (type == 'keyUp') (type == 'textinput')) {
      processEvent keyboard evt
    } (type == 'window') {
      processWindowEvent this evt
	} (type == 'dropFile') {
	  add droppedFiles evt
   } (type == 'quit') {
      confirmToQuit this
    }
    evt = nxt
  }
}

to getNextEvent {
  // filter out "touch" type events for now
  evt = (nextEvent)
  if (isNil evt) {return nil}
  type = (at evt 'type')
  if (or (type == 'touch') (isClass type 'Integer')) {return (getNextEvent)}
  return evt
}

method processWindowEvent Page evt {
  scale = (global 'scale')
  id = (at evt 'eventID')
  if (isOneOf id 5 6) {
	// note: things can break if w or h is less than 1
	w = (scale * (max 1 (at evt 'data1')))
	h = (scale * (max 1 (at evt 'data2')))

	clearBuffer color
	flipBuffer
	setPosition morph 0 0
	setExtent morph w h
	isChanged = true
	for each (parts morph) {pageResized (handler each) w h this}
  } else {
	isChanged = true
	for each (parts morph) {pageResized (handler each) w h this}
  }
}

method setWindowSize Page w h {
  scale = (global 'scale')
  tryRetina = (scale > 1)
  openWindow w h tryRetina
  clearBuffer color
  flipBuffer
  setPosition morph 0 0
  setExtent morph (w * scale) (h * scale)
  for m (parts morph) {
	pageResized (handler m) w h this
  }
}

method startStepping Page startFlag {
  if (isNil startFlag) { startFlag = false }
  stopAll this
  if startFlag { broadcastGo this }
  interactionLoop this
}

method stepForSeconds Page secs {
  // Useful when including running morphic unit tests.
  stopAll this
  timer = (newTimer)
  while ((secs timer) < secs) { doOneCycle this }
}

method startSteppingSafely Page startFlag {
  // Run the step loop as a subtask and restart it if an error is encountered.
  emergencyMemory = (newBinaryData 10000)
  if (isNil startFlag) { startFlag = false }
  stopAll this
  if startFlag { broadcastGo this }
  task = (newStepTask this)
  while true {
	resume task
	if ('timer' == (waitReason task)) {
	  msecsToWait = ((wakeMSecs task) - (msecsSinceStart))
	  if (msecsToWait > 0) { waitMSecs msecsToWait }
	} ('error' == (waitReason task)) {
	  stopAll this
	  emergencyMemory = nil
	  openDebugger task
	  task = (newStepTask this) // create a new task
	}
  }
}

method newStepTask Page {
  task = (newTask (newCommand 'interactionLoop' this))
  setField task 'tickLimit' 1000000
  setField task 'taskToResume' (currentTask)
  return task
}

method interactionLoop Page {
  while true { doOneCycle this }
}

// scheduling

method addSchedule Page aSchedule {add schedules aSchedule}

method stepSchedules Page {
  if (isEmpty schedules) {return}
  done = (list)
  for each schedules {
    step each
    if (isDone each) {add done each}
  }
  removeAll schedules done
}

method removeSchedulesFor Page op aMorph {
  if (isEmpty schedules) {return}
  newSchedules = (list)
  for each schedules {
    if (op == (op each)) {
      if (isClass aMorph 'Morph') {
        match = (aMorph == (first (args each)))
      } else {
        match = true
      }
    } else {
      match = false
    }
    if (not match) {add newSchedules each}
    // if (op != (op each)) {add newSchedules each}
  }
  schedules = newSchedules
}

// tasks

method launch Page cmdList targetObj doneAction {
  task = (newTask cmdList targetObj doneAction)
  addTask taskMaster task
  return task
}

method stopAll Page {
  stopEditing keyboard
  stopAllSounds soundMixer
  taskMaster = (newTaskMaster)
  return nil
}

method exitPresentationMode Page {
  for m (copy (parts morph)) {
	if (isClass (handler m) 'ScripterMenuBar') { exitPresentation (handler m) }
	if (isClass (handler m) 'ProjectEditor') { exitPresentation (handler m) }
  }
}

method isRunning Page cmdList rcvr { return (isRunning taskMaster cmdList rcvr) }
method stopRunning Page cmdList rcvr { stopRunning taskMaster cmdList rcvr }
method stopTasksFor Page rcvr { stopTasksFor taskMaster rcvr }

// menu

method showMenu Page aMenu x y {
  if (isNil x) {x = (half ((width morph) - (width (morph aMenu))))}
  if (isNil y) {y = (half ((height morph) - (height (morph aMenu))))}
  if (notNil activeMenu) {destroy (morph activeMenu)}
  removeHint this
  setPosition (morph aMenu) x y
  keepWithin (morph aMenu) (insetBy (bounds morph) 50)
  addPart morph (morph aMenu)
  activeMenu = aMenu
}

to inform msg { inform (global 'page') msg }

method inform Page msg {
  m = (menu msg)
  addItem m 'Ok' 'nop'
  buildMorph m this (y hand)
  setGrabRule (morph m) 'handle'
  showMenu this m ((x hand) - (half (width (morph m)))) ((y hand) - (half (height (morph m))))
}

method closeUnclickedMenu Page aHandler {
  removeHint this
  if (isNil activeMenu) {return}
  if (contains (allOwners (morph aHandler)) (morph activeMenu)) {return}
  if (and (isClass activeMenu 'Menu') (contains (triggers activeMenu) aHandler)) {return}
  destroy (morph activeMenu)
  activeMenu = nil
}

method hasActiveMenu Page {return (notNil activeMenu)}

// hint

method showHint Page aSpeechBubble isHint {
  removeHint this
  keepWithin (morph aSpeechBubble) (bounds morph)
  addPart this aSpeechBubble
  if isHint { activeHint = aSpeechBubble }
}

method removeHint Page {
  if (notNil activeHint) {
    destroy (morph activeHint)
    activeHint = nil
  }
}

// prompting and confirming

method prompt Page question default editRule callback {
  // prompt can be used either as a reporter or as a command
  // if a callback is passed prompt is used as a command, when
  // the user accepts the prompter, the callback is called with
  // the user's answer
  // if no callback is given, this method eclipses the page's
  // main loop until the user terminates the prompter.
  // the reporter version is much nicer to user in scripts,
  // but it doesn't handle multiple prompters gracefully, unless
  // the user "backtracks" the prompters in the reverse order
  // of having opened them.
  // the callback version, otoh, handles any number and
  // sequence of prompters gracefully, but is more cumbersome
  // to use in scripts
  if (isNil editRule) { editRule = 'line' }
  p = (new 'Prompter')
  initialize p question default editRule callback
  fixLayout p
  setCenter (morph p) (x hand) (y hand)
  keepWithin (morph p) (bounds morph)
  addPart morph (morph p)
  edit (textBox p) hand
  selectAll (textBox p)
  if (isNil callback) {
    setField hand 'lastTouchTime' nil
    while (not (isDone p)) {doOneCycle this}
    destroy (morph p)
    return (answer p)
  }
}

method confirm Page title question yesLabel noLabel callback {
  // see comment for ::prompt
  p = (new 'Prompter')
  initializeForConfirm p title question yesLabel noLabel callback
  setCenter (morph p) (x hand) (y hand)
  keepWithin (morph p) (insetBy (bounds morph) 50)
  addPart morph (morph p)
  if (isNil callback) {
    setField hand 'lastTouchTime' nil
    while (not (isDone p)) {doOneCycle this}
    destroy (morph p)
    return (answer p)
  }
}

// events

method changed Page {isChanged = true}
method handDownOn Page {return true}
method handUpOn Page {return true}
method clicked Page {return true}
method doubleClicked Page {return true}
method swipe Page {return true}

method wantsDropOf Page aHandler {
  return (or
    (devMode)
    (isClass aHandler 'ColorPicker')
    (and
      (hasField aHandler 'window')
      (isClass (getField aHandler 'window') 'Window')
    )
  )
}

method rightClicked Page {
  popUpAtHand (contextMenu this) this
  return true
}

// context menu

method contextMenu Page {
  menu = (menu 'GP' this)
  addItem menu 'GP version...' 'showGPVersion'
  addLine menu
  addItem menu 'show all' 'showAll' 'move any offscreen objects back into view'
  if (devMode) {
	addLine menu
	addItem menu 'broadcast "go"' 'broadcastGo'
	addItem menu 'stop all' 'stopAll' 'halt all currently running threads'
	addLine menu
	addItem menu 'enter project editor' (action 'startProjectEditorFromMorphic') 'enter the project editor'
	addItem menu 'workspace...' (action 'openWorkspace' this) 'open a window for interacting with text code'
	addItem menu 'trash can...' (action 'openTrashCan' this) 'open a window for deleting graphical elements'
	addItem menu 'notes...' (action 'openPresentation' this) 'open a window for presenting text headlines'
	addItem menu 'turtle...' 'addTurtle' 'create a new scriptable robot'
	addItem menu 'block editor...' (action 'openBlockEditor' this) 'open a window for assembling blocks code'
	addItem menu 'file list...' (action 'openFileList') 'open a list of files'
	addItem menu 'benchmark...' (action 'runBenchmarks') 'run some simple compute-speed benchmarks'
	addLine menu
	addItem menu 'exit developer mode' (action 'exitDeveloperMode' this) 'exit developer mode'
	if isShowingConnectors {
	  addItem menu 'hide connectors' 'toggleConnectors'
	} (notNil (detect (function each {return (isAnyClass (handler each) 'Inspector' 'Scripter' 'Explorer')}) (parts morph) nil)) {
	  addItem menu 'show connectors' 'toggleConnectors' 'connect Inspector widgets with inspected data'
	}
  } else {
	addItem menu 'notes...' (action 'openPresentation' this) 'open a window to add notes to this project'
  }
  addLine menu
  addItem menu 'quit' 'confirmToQuit'
  return menu
}

method showGPVersion Page {
  inform this (join 'GP Version ' (libraryVersion) (newline) (at (version) 1))
}

method broadcastGo Page { stopAll this; broadcast 'go' }
method runBenchmarks Page { inform this (tinyBenchmarks) }

method showAll Page {
  for m (parts morph) {
    keepWithin m (bounds morph)
    setAlpha m 255
	show m
  }
}

method addTurtle Page {
  t = (newTurtle)
  setField t 'x' (x hand)
  setField t 'y' (y hand)
  setPosition (morph t) (x hand) (y hand)
  addPart this t
}

method confirmToQuit Page {confirm this nil (join 'Are you sure' (newline) 'you want to quit GP?') nil nil 'exit'}

// foreground layer

method foreground Page {return foreground}
method createForeground Page {foreground = (newBitmap (width morph) (height morph))}
method deleteForeground Page {foreground = nil}

method drawForeground Page {
  if (notNil foreground) {drawBitmap nil foreground}
}

method resizeForeground Page {
  if (notNil foreground) {
    bm = (newBitmap (width this) (height this))
    drawBitmap bm foreground
    foreground = bm
  }
}

method requireForeground Page {
  if (or
	(isNil foreground)
	((width foreground) != (width morph))
	((height foreground) != (height morph))) {
		createForeground this
  } else {
    fill foreground (color 0 0 0 0)
  }
  return foreground
}

// display connectors

method isShowingConnectors Page { return isShowingConnectors }

method setIsShowingConnectors Page bool {
  isShowingConnectors = bool
  deleteForeground this
  changed this
}

method toggleConnectors Page {
  setIsShowingConnectors this (not isShowingConnectors)
}

method drawLinks Page {
  scale = (global 'scale')
  quickArrows = true
  if quickArrows {
	deleteForeground this
	pen = (newPen nil) // draw directly to the display buffer
  } else {
	pen = (newPen (requireForeground this))
  }
  projectEditor = (detect
    (function each {return (isClass (handler each) 'ProjectEditor')})
    (parts morph)
  )
  if (notNil projectEditor) {
    scripter = (morph (scripter (handler projectEditor)))
    sprites = (parts (morph (stage (handler projectEditor))))
  } else {
    sprites = (list)
  }

  // Draw links for any active MorphRefIcons
  if (notNil scripter) { drawMorphRefLinks (handler scripter) pen }
  if (not isShowingConnectors) { return } // don't show other links

  // draw connection of scripter to target object
  if (isNil scripter) {
    scripter = (detect
      (function each {return (isClass (handler each) 'Scripter')})
      (join (parts morph) (parts (morph hand)))
    )
  }
  if (and (notNil scripter) (isVisible scripter) (notNil (owner scripter)) (notNil (targetObj (handler scripter)))) {
    h = (targetObj (handler scripter))
    coll = (array)
    if (hasField h 'morph') {
      exemplar = (morph (targetObj (handler scripter)))
      coll = (intersectionsWithLineSegment (bounds scripter) (hCenter (bounds scripter)) (vCenter (bounds scripter)) (hCenter (bounds exemplar)) (vCenter (bounds exemplar)))
    }
    if (notEmpty coll) {
      pt = (first coll)
      ecx = (hCenter (bounds exemplar))
      ecy = (vCenter (bounds exemplar))
	  drawCircle pen (first pt) (last pt) (scale * 4) (gray 100) 1 (gray 255)
      if (containsPoint (bounds morph) ecx ecy) {
        drawArrow pen (first pt) (last pt) ecx ecy (gray 100)
      } else {
        coll = (intersectionsWithLineSegment (bounds morph) (first pt) (last pt) ecx ecy)
        if (notEmpty coll) {
          pt2 = (first coll)
          drawArrow pen (first pt) (last pt) (first pt2) (last pt2) (gray 100) true // no arrowhead
        }
      }
    }
  }

  // draw connection of the hand to its focus object (if any), confine to scrubbed texts
  if (isClass (focus hand) 'Text') {
    focus = (morph (focus hand))
    if (notNil focus) {
      coll = (intersectionsWithLineSegment (bounds focus) (hCenter (bounds focus)) (vCenter (bounds focus)) (x hand) (y hand))
      if (notEmpty coll) {
        pt = (first coll)
		drawCircle pen (first pt) (last pt) (scale * 4) (gray 120) 1 (gray 255)
		drawArrow pen (x hand) (y hand) (first pt) (last pt) (gray 120)
      }
    }
  }

  // draw connections involving inspectors, explorers and monitors
  inspectors = (filter
    (function each {return (isAnyClass (handler each) 'Inspector' 'Explorer' 'Monitor')})
    (join sprites (parts morph) (parts (morph hand)))
  )
  morphs = (join (allMorphs morph) (allMorphs (morph hand)))
  for each inspectors {
    if (isClass (handler each) 'Monitor') {
	  a = (getField (handler each) 'getAction')
	  if (and (notNil a) (notEmpty (arguments a))) {
		if ('eval' == (function a)) {
		  obj = (at (arguments a) 2)
		} else {
		  obj = (first (arguments a))
		}
	  }
    } else {
      obj = (getField (handler each) 'contents')
    }
    for other morphs {
      hdl = (handler other)
      if (isAnyClass (handler other) 'Inspector' 'Explorer') {
        sel = (currentSelection (handler other))
        ctr = (connectors (handler other))
        hlt = (currentHighlight (handler other))
      } else {
        sel = nil
        ctr = nil
        hlt = nil
      }
      if (and (notNil obj) (=== hdl obj)) {
        pt2 = (rotationCenter other)
        coll = (intersectionsWithLineSegment (bounds each) (hCenter (bounds each)) (vCenter (bounds each)) (first pt2) (last pt2))
        if (notEmpty coll) {
          pt = (first coll)
		  c = (gray 100)
          if (isClass (handler each) 'Monitor') { c = (bgColor (handler each)) }
		  drawCircle pen (first pt) (last pt) (scale * 4) c 1 (gray 255)
		  drawArrow pen (first pt) (last pt) (first pt2) (last pt2) c
        }
      }
      if (notNil ctr) {
        for connector ctr {
          if (=== obj (first connector)) {
            pt = (last connector)
            coll = (intersectionsWithLineSegment (bounds each) (hCenter (bounds each)) (vCenter (bounds each)) (first pt) (last pt))
            if (notEmpty coll) {
              cp = (first coll)
			  drawCircle pen (first pt) (last pt) (scale * 7) (color 0 120 30 120)
              drawArrow pen (first pt) (last pt) (first cp) (last cp) (color 0 120 30)
            }
          }
        }
      }
      if (and (notNil obj) (=== sel obj)) {
        lb = (getField (handler other) 'listBox')
        bds = (bounds (owner (morph lb)))
        cpx = (hCenter bds)
        cpy = (min (max (top bds) (vCenter (bounds (selectedMorph lb)))) (bottom bds))
        coll = (intersectionsWithLineSegment (bounds each) (hCenter (bounds each)) (vCenter (bounds each)) cpx cpy)
        if (notEmpty coll) {
          pt = (first coll)
          setColor pen (color 0 120 30)
          setLineWidth pen 1 // scale
          drawArrow pen cpx cpy (first pt) (last pt) (color 0 120 30)
        }
      }
      if (and (notNil obj) (=== hlt obj)) {
        lb = (getField (handler other) 'listBox')
        bds = (bounds (owner (morph lb)))
        cpx = (hCenter bds)
        cpy = (min (max (top bds) (vCenter (bounds (morph (highlighted lb))))) (bottom bds))
        setLineWidth pen (* scale 10)
        setColor pen (color 152 190 230 100)
        drawLine pen (hCenter (bounds each)) (vCenter (bounds each)) cpx cpy
        if (notNil (canvas pen)) {
		  fillRoundedRect (newShapeMaker (canvas pen)) (expandBy (bounds each) (scale * 2)) (scale * 5) (color 152 190 230 100)
		}
      }
    }
  }
}

// Dropped files (in Mac OS, file dropping only works when GP is packaged as an app)

method droppedFiles Page {
  // Return a list of dropFile events and clear droppedFiles.

  if (isEmpty droppedFiles) { return droppedFiles }
  result = droppedFiles
  droppedFiles = (list)
  return result
}

// Profiling

method startProfiling Page {
  clearProfileState this
  gc
  setField (currentTask) 'profileIndex' 1
  setField (currentTask) 'profileArray' (newArray 10000000)
  profileTimer = (newTimer)
  startProfileClock
}

method endProfiling Page {
  // Stop the profiler and return the profile.

  stopProfileClock
  if (notNil profileTimer) {
	msecs = (msecs profileTimer)
	profileTimer = nil
  }
  profileArray = (getField (currentTask) 'profileArray')
  profileIndex = (getField (currentTask) 'profileIndex')
  if (or (isNil profileArray) (isNil profileIndex)) {
	clearProfileState this
	return
  }
  gc
  data = (copyArray profileArray (profileIndex - 1))
  clearProfileState this
  gc
  result = (new 'Profile' data msecs)
  setGlobal 'lastProfile' result
  exploreProfile result
}

method clearProfileState Page {
  stopProfileClock
  setField (currentTask) 'profileIndex' nil
  setField (currentTask) 'profileArray' nil
  gc
}
