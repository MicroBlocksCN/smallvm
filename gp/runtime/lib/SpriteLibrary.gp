// a container displaying a list of user-edited classes and a list of instances for the selected class

defineClass SpriteLibrary morph scripter newClassButton newInstanceButton clearButton classes classesFrame instances instancesFrame lastClasses instanceLabelWidth

method initialize SpriteLibrary aScripter {
  scripter = aScripter
  classes = (listBox (array) 'className' (action 'selectClass' this) (gray 240))
  setFont classes 'Arial' 13
  classesFrame = (scrollFrame classes (gray 240))
  instances = (initialize (new 'SpriteList'))
  instancesFrame = (scrollFrame instances (gray 220))
  setCachingEnabled instancesFrame false
  morph = (newMorph this)
  setTransparentTouch morph true
  newClassButton = (makeNewThingButton this 'createClass' 'Make a new class')
  newInstanceButton = (makeNewThingButton this 'addInstance' 'Make a new instance of this class')
  clearButton = (pushButton 'Clear' (gray 120) (action 'clearInstances' this))
  setHint clearButton 'Remove all instances of this class except the selected one'

  addPart morph (morph classesFrame)
  addPart morph (morph instancesFrame)
  addPart morph (morph newClassButton)
  addPart morph (morph newInstanceButton)
  addPart morph (morph clearButton)
  updateClasses this
  setExtent morph 800 400
  setFPS morph 2
  return this
}

method redraw SpriteLibrary {
  scale = (global 'scale')
  border = (2 * scale)
  titleBarH = (24 * scale)
  fontSize = (15 * scale)
  bnds = (bounds morph)
  bm = (newBitmap (max 1 (width bnds)) (max 1 (height bnds)) (gray 150))
  fillRect bm (gray 220) 0 border ((width bnds) - border) (titleBarH - border)
  fillRect bm (gray 150) (100 * scale) border border (titleBarH - border)
  setFont 'Arial Bold' fontSize
  drawString bm 'Classes'  (gray 50) (points 4) (points 4)
  instancesLabel = 'Instances'
  targetObj = (targetObj scripter)
  if (notNil targetObj) {
	targetClass = (classOf targetObj)
	instancesLabel = (join 'Instances of ' (className targetClass))
  }
  drawString bm instancesLabel (gray 50) (points 108) (points 4)
  instanceLabelWidth = (stringWidth instancesLabel)
  setCostume morph bm
  fixLayout this
}

method fixLayout SpriteLibrary {
  scale = (global 'scale')
  border = (scale * 2)
  titleBarH = (24 * scale)
  setPosition (morph classesFrame) (left morph) (+ (top morph) titleBarH border)
  setExtent (morph classesFrame) (scale * 100) (max 0 ((height morph) - (titleBarH + (2 * border))))
  setPosition (morph instancesFrame) (+ border (right (morph classesFrame))) (+ (top morph) titleBarH border)
  setExtent (morph instancesFrame) (max 0 (((width morph) - (width (morph classesFrame))) - (2 * border))) (max 0 (height (morph classesFrame)))
  setInsetInOwner (morph newClassButton) (81 * scale) (5 * scale)
  setInsetInOwner (morph newInstanceButton) (+ (width (morph classesFrame)) instanceLabelWidth (25 * scale)) (5 * scale)
  setInsetInOwner (morph clearButton) ((width morph) - ((width (morph clearButton)) + (10 * scale))) (7 * scale)
}

method clearLibrary SpriteLibrary {
  lastClasses = (dictionary)
  setCollection classes (array)
  select classes nil
  clear instances
}

// stepping

method step SpriteLibrary {
  if (classesHaveChanged this) { updateClasses this }
  if (isNil scripter) {return}
  targetObj = (targetObj scripter)
  if (and (notNil targetObj) (not (isSelected instances targetObj))) {
	targetClass = (classOf targetObj)
	select classes targetClass
	setClass instances targetClass targetObj
	redraw this
  }
}

method classesHaveChanged SpriteLibrary {
  // This called by step a few times a second, so it has to
  // be efficient. This version runs in about 35 useconds
  // and does minimal object creation.

  if (isNil lastClasses) { lastClasses = (dictionary) }
  count = 0
  for cl (classes (targetModule scripter)) {
	oldName = (at lastClasses cl)
	if (isNil oldName) { return true } // new class
	if ((className cl) != oldName) { return true } // class name changed
	count += 1
  }
  return (count != (count lastClasses)) // class deleted
}

method updateClasses SpriteLibrary {
  // Update my class list when a class change is detected.
  // If the currently selected class has been deleted, select another.

  lastClasses = (dictionary)
  newClasses = (list)

  for cl (classes (targetModule scripter)) {
	atPut lastClasses cl (className cl)
	add newClasses cl
  }
  newClasses = (sorted newClasses (function c1 c2 { return ((className c1) < (className c2)) }))
  selectedClass = (selection classes)
  setCollection classes newClasses
  if (not (contains newClasses selectedClass)) {
	if (isEmpty newClasses) {
	  selectedClass = nil
	  clear instances
	} else {
	  selectedClass = (first newClasses)
	}
	select classes selectedClass
  }
}

// class selection

method selectClass SpriteLibrary aClass {
  // User clicked on a name in the class list.

  if (aClass != (targetClass instances)) {
    setClass instances aClass
    if (notNil scripter) {
      // view some instance of the newly selected class
      obj = (selectFirst instances)
      if (isNil obj) { // no instaces yet; create one
        obj = (instantiate (targetClass instances) (stageMorph scripter))
      }
      setTargetObj scripter obj
    }
    redraw this
  }
}

// operations

method clearInstances SpriteLibrary {
  stageM = (stageMorph scripter)
  targetClass = (targetClass instances)
  toDelete = (list)
  for m (parts stageM) {
	if (isClass (handler m) targetClass) { add toDelete m }
  }
  if ((count toDelete) > 1) {
	if (notNil (targetObj scripter)) {
	  remove toDelete (morph (targetObj scripter))
	} else {
	  removeFirst toDelete
	}
	for m2 toDelete {
	  removePart stageM m2
	}
  }
  clear instances
  gc
}

// class menu

method handleListContextRequest SpriteLibrary pair {
  if (isNil scripter) {return}
  cl = (data (last pair))
  menu = (menu)
  addItem menu 'make a new class' (action 'createClass' scripter false)
  if (devMode) {
	addItem menu 'make a helper (non-visible) class' (action 'createClass' scripter true)
  }
  addItem menu 'import a class' (action 'importClass' scripter)
  addLine menu
  if (devMode) {
	addItem menu 'browse this class' (action 'browseClass' cl)
	addItem menu 'export this class' (action 'exportClass' scripter cl)
  }
  addItem menu 'rename this class' (action 'renameClass' scripter cl)
  addLine menu
  addItem menu 'delete this class' (action 'deleteClass' scripter cl)
  popUpAtHand menu (global 'page')
}

// script copy by dropping

method wantsDropOf SpriteLibrary aHandler {
  // Accept drops of Blocks dropped on a class name in the class list.
  return (and (isClass aHandler 'Block') (notNil (dropTargetClass this aHandler)))
}

method dropTargetClass SpriteLibrary aBlock {
  // Return the class on which the given Block was dropped or nil.
  hand = (hand (global 'page'))
  dropX = (x hand)
  dropY = (y hand)
  for m (parts (morph classes)) {
	if (containsPoint (bounds m) dropX dropY) {
	  return (data (handler m))
	}
  }
  return nil
}

method justReceivedDrop SpriteLibrary aBlock {
  if (not (isClass aBlock 'Block')) { return }
  targetClass = (dropTargetClass this aBlock)
  if (isNil targetClass) { return }
  script = (expression aBlock (className targetClass))
  if (isOneOf (primName script) 'method' 'to') {
	script = (copyMethodOrFunction scripter script targetClass)
  } else {
	script = (copy script)
  }
  if (isNil (scripts targetClass)) {
	setScripts targetClass (list)
  }
  scriptList = (toList (scripts targetClass))
  add scriptList (array (rand 100) (rand 100) script)
  setScripts targetClass (toArray scriptList)
  if (targetClass == (classOf (targetObj scripter))) {
	restoreScripts scripter
  }
  animateBackToOldOwner (hand (global 'page')) (morph aBlock)
}

// new class/instance buttons

method makeNewThingButton SpriteLibrary selector hint {
  btn = (new 'Trigger' (newMorph) (action selector scripter))
  setHandler (morph btn) btn
  m = (morph btn)
  setTransparentTouch m true
  if (notNil hint) { setHint btn hint }
  setCostume m (plusIcon this)
  setScale m ((global 'scale') / 2)
  return (handler m)
}

method plusIcon SpriteLibrary {
  data = '
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEEBAIBAAIEBAIAAAAAAAAA
AAAAAAAAAAAAAAAAAAIEAAAAAAAAAAAAAAQCAAAAAAAAAAAAAAAAAAAAAAAEAAAWXZm9zc2/nGEaAAAE
AAAAAAAAAAAAAAAAAAABAwAem/D///////////OiJQACAQAAAAAAAAAAAAAAAQAAa/j////mwKqpvuP/
///8dgAAAgAAAAAAAAAAAAEAAJv///+zSQ0AAAAAC0Or////qAAAAQAAAAAAAAAAAwCb///oRwAAAAUI
CAYAAAA94P//qQACAAAAAAAAAAQAa///1hIABAMCAAAAAAAEBQAKy///ewAEAAAAAAACAB74/+cSAAYA
AQBEaWRdBwAABgAJ3v//KgACAAAAAAQAm///RwAGAAAEALr///8SAAEABQA4//+qAAQAAAABABbw/7MA
BAAAAAMAq//86xAAAQAABQCk//ghAAIAAAQAXf//SQADAgQEBwCw///vFAAFBAMDADr//20ABAAABACZ
/+YNAAIAAAAAAKn//+0AAAAAAAEABdv/qAAEAAACAL3/wAAFAEirnaGa4f//+aaenqh5AAUAsv/KAAEA
AAEAzf+qAAgAe////////v///////84ABgCb/9kDAAEAAADN/6kACABz//n9/f7////9/fr/wAAGAJv/
2QQAAQACAL//vgAGAHD/8vf2/P////f29P+7AAUAsP/MAAEAAAQAnP/jCwAADR4bHw+3///wKhgcHRUA
AAPZ/6sABAAABABh//9DAAQAAAAAAKz//+4KAAAAAAMANf//cQAEAAACABrz/6wABQACAgUArf/97BIA
AwIBBQCc//smAAIAAAAEAKL//z0ABgAABAC2///5EQABAAUAL/7/sgADAAAAAAIAJf3/4AoABQADAI3a
z8ENAAEFAALV//8xAAMAAAAAAAQAdv//ywkABQMBAAAAAAADBQACv///hgAEAAAAAAAAAAIAqP//3jgA
AAAEBQUEAAAAL9X//7YAAQEAAAAAAAAAAQAAqf///6Q6BQAAAAADNZz+//+2AAACAAAAAAAAAAAAAgAA
e//////bspubsNn/////hgAAAgAAAAAAAAAAAAAAAQIAKqr4///////////7sjEAAQIAAAAAAAAAAAAA
AAAAAAQAACFtqMrZ2cyrcSYAAAQBAAAAAAAAAAAAAAAAAAAAAAIEAAAAAAMEAAAAAAMDAAAAAAAAAAAA
AAAAAAAAAAAAAAACBAQBAAABBAQCAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAQAAAAAAAAAAAAAA
AAAAAA=='
  bm = (newBitmap 32 32)
  applyAlphaChannel bm (base64Decode data) (gray 80)
  return bm
}
