// AuthoringCommands.gp - Commands for the authoring level
//
// Note: By convention, commands that use the implicit receiver are prefixed with "self_"

// instantiation

to instantiate handlerClass destMorph initData {
  result = (new handlerClass)
  for i (objWords result) {
	setField result i 0 // initialize all fields to 0 (not nil)
  }
  if (not (hasField result 'morph')) { // helper class
	if (implements result 'initialize') { initialize result initData }
  	return result
  }
  if (isNil destMorph) { destMorph = (morph (global 'page')) }
  setMorph result (newMorph result)
  resultM = (morph result)
  setGrabRule resultM 'handle'
  bm = (imageNamed (projectForMorph nil) 'ship')
  if (isNil bm) {
	bm = (makeShip (new 'Project'))
  } else {
	bm = (copy bm)
  }
  setCostume resultM bm
  setDrawOnOwner resultM false // draw on the page
  setScale resultM (scale destMorph)
  x = (rand (left destMorph) ((right destMorph) - (width resultM)))
  y = (rand (top destMorph) ((bottom destMorph) - (height resultM)))
  setPosition resultM x y
  if (implements result 'initialize') { initialize result initData }
  if (implements result 'redraw') { redraw result }
  addPart destMorph resultM
  return result
}

to implicitReceiver {
  result = (lastReceiver)
  if (isNil result) {
	// block executed outside of a scripter; use a dummy receiver
	result = (newBox (newMorph))
	setExtent (morph result) 1 1
	redraw result
  }
  return result
}

to isInHand aMorph {
  // Return true if the given morph is owned by the Hand.
  owner = (owner aMorph)
  return (and (notNil owner) (isClass (handler owner) 'Hand'))
}

to self_stopAll { stopAll (global 'page') }

to self_show { show (morph (implicitReceiver)) }
to self_hide { hide (morph (implicitReceiver)) }
to self_comeToFront { comeToFront (morph (implicitReceiver)) }
to self_goBackBy n { goBackBy (morph (implicitReceiver)) n }

to self_say s { say (morph (implicitReceiver)) s }
to self_sayNothing { sayNothing (morph (implicitReceiver)) }

to self_moveBy dx dy {
  if (isNil dx) { dx = 0 }
  if (isNil dy) { dy = 0 }
  m = (morph (implicitReceiver))
  if (isInHand m) { return } // don't move when picked up
  stage = (self_stageMorph)
  if (notNil stage) {
	dx = (dx * (scale stage))
	dy = (0 - (dy * (scale stage)))
  }
  moveBy m dx dy
}

to self_moveInDirection distance degrees {
  if (isNil degrees) { degrees = (rotation (morph (implicitReceiver))) }
  self_moveBy (distance * (cos degrees)) (distance * (sin degrees))
}

to self_bounceOffEdge {
  m = (morph (implicitReceiver))
  stage = (self_stageMorph)
  if (isNil stage) {return}
  fb = (fullBounds m)
  if (containsRectangle (bounds stage) fb) {return}
  dirX = (cos (rotation m))
  dirY = (sin (rotation m))
  if ((left fb) < (left stage)) {
    dirX = (abs dirX)
  }
  if ((right fb) > (right stage)) {
    dirX = (-1 * (abs dirX))
  }
  if ((top fb) < (top stage)) {
    dirY = (-1 * (abs dirY))
  }
  if ((bottom fb) > (bottom stage)) {
    dirY = (abs dirY)
  }
  rotateAndScale m (atan dirY dirX) (scale m)
  keepWithin m (bounds stage)
}

to self_keepInOwner {
  m = (morph (implicitReceiver))
  o = (owner m)
  if (and (notNil o) (not (isClass (handler o) 'Hand'))) {
	keepWithin m (bounds o)
  }
}

to self_setPosition x y {
  m = (morph (implicitReceiver))
  if (isInHand m) { return } // don't move when picked up
  stage = (self_stageMorph)
  if (notNil stage) {
    p = (transform stage x (0 - y))
    x = (first p)
    y = (last p)
  }
  placeRotationCenter m x y
}

to self_getPosition {
  m = (morph (implicitReceiver))
  stage = (self_stageMorph)
  p = (rotationCenter m)
  if (notNil stage) {
	p = (normal stage (first p) (last p))
	atPut p 2 (0 - (at p 2))
  }
  return p
}

to self_setX x { self_setPosition x (last (self_getPosition)) }
to self_setY y { self_setPosition (first (self_getPosition)) y }

to self_getX { return (first (self_getPosition)) }
to self_getY { return (last (self_getPosition)) }

to self_getWidth name {
  m = (morph (implicitReceiver))
  if (or (isNil name) ('' == name)) { return (normalWidth m) }
  bm = (imageNamed name m)
  if (isNil bm) { return 0 }
  return (width bm)
}

to self_getHeight name {
  m = (morph (implicitReceiver))
  if (or (isNil name) ('' == name)) { return (normalHeight m) }
  bm = (imageNamed name m)
  if (isNil bm) { return 0 }
  return (height bm)
}

to self_getProperty property obj {
  if (isNil obj) { obj = (implicitReceiver) }
  if (hasField obj property) {
	return (getField obj property)
  }
  if (hasField obj 'morph') {
	m = (morph obj)
	p = (rotationCenter m)
	stage = (self_stageMorph)
	if (notNil stage) { p = (normal stage (first p) (last p)) }
	if ('x' == property) {
	  return (first p)
	} ('y' == property) {
	  return (- (last p))
	}
  }
  return nil
}

to stageWidth {
  m = (morph (implicitReceiver))
  stage = (self_stageMorph)
  if (notNil stage) { return (width (costumeData stage)) }
  return (width (morph (global 'page')))
}

to stageHeight {
  m = (morph (implicitReceiver))
  stage = (self_stageMorph)
  if (notNil stage) { return (height (costumeData stage)) }
  return (height (morph (global 'page')))
}

to self_setAlpha a { setAlpha (morph (implicitReceiver)) (toInteger (255 * (clamp a 0 1))) } // obsolete
to self_setTransparency n { setTransparency (morph (implicitReceiver)) n }

to self_setRotation newRotation {
  m = (morph (implicitReceiver))
  if (isInHand m) { return } // don't move when picked up
  rotateAndScale m newRotation (scale m)
}

to self_setScale newScale {
  m = (morph (implicitReceiver))
  if (isInHand m) { return } // don't move when picked up
  maxDimension = 4000
  minDimension = 1
  minScale = (max (minDimension / (normalWidth m)) (minDimension / (normalHeight m)))
  maxScale = (max (maxDimension / (normalWidth m)) (maxDimension / (normalHeight m)))
  stage = (self_stageMorph)
  if (notNil stage) { normalizedScale = ((scale stage) * newScale) }
  normalizedScale = (clamp normalizedScale minScale maxScale)
  setScale m normalizedScale
}

to self_changeRotation delta { self_setRotation ((self_getRotation) - delta) }
to self_changeScale delta { self_setScale ((self_getScale) + delta) }

to self_getRotation { return (rotation (morph (implicitReceiver))) }

to self_getScale {
  // Return the authoring view of the scale (i.e. without normalization for display resolution)

  m = (morph (implicitReceiver))
  result = (scale m)
  stage = (self_stageMorph)
  if (notNil stage) { result = (result / (scale stage)) }
  return result
}

to self_setDraggable bool {
  if (true == bool) {
	newRule = 'handle'
  } else {
  	newRule = 'defer'
  }
  setGrabRule (morph (implicitReceiver)) newRule
}

to self_grab aHandler {
  if (isNil aHandler) {
	m = (morph (implicitReceiver))
  } (implementes aHandler 'morph') {
	m = (morph aHandler)
  }
  if (and (notNil m) ('handle' == (grabRule m))) {
	grab m
  }
}

to self_addPart part newOwner {
  if (isNil part) { return }
  m = (morph (implicitReceiver))
  stage = (self_stageMorph)
  if (isNil newOwner) { newOwner = m }
  if (not (isClass part 'Morph')) { part = (morph part) }
  if (isClass (handler part) 'Stage') { return }
  if (not (isClass newOwner 'Morph')) { newOwner = (morph newOwner) }
  if (contains (allOwners newOwner) part) { return }
  if (part == newOwner) { return } // you can't be a part of yourself

  if (isOneOf newOwner stage (morph (global 'page'))) {
    setGrabRule part 'handle' // allow grabbing on stage or page
  } else {
    setGrabRule part 'defer' // defer grabbing when added to another sprite
  }
  addPart newOwner part
}

to self_placePart part xInset yInset {
  if (isNil part) { return }
  if (isNil xInset) { xInset = 10 }
  if (isNil yInset) { yInset = 10 }
  if (not (isClass part 'Morph')) { part = (morph part) }
  m = (morph (implicitReceiver))
  self_addPart part m
  scale = (scale m)
  setPosition part ((left m) + (scale * xInset)) ((top m) + (scale * yInset))
}

to self_parts obj {
  if (isNil obj) { obj = (morph (implicitReceiver)) }
  if (not (isClass obj 'Morph')) { obj = (morph obj) }
  result = (list)
  for partM (parts obj) {
	add result (handler partM)
  }
  return result
}

to self_delete part {
  page = (global 'page')
  if (isNil part) { part = (morph (implicitReceiver)) }
  if (not (isClass part 'Morph')) { part = (morph part) }
  setGrabRule part 'handle' // re-enable grabbing
  if (notNil (owner part)) { removePart (owner part) part }
  stopTasksFor page (handler part)
}

to self_instantiate classOrName initData {
  class = nil
  if (isNil classOrName) {
    class = (classOf (implicitReceiver))
  } (isClass classOrName 'Class') {
    class = classOrName
  } else {
    caller = (caller (currentTask))
    if (notNil caller) {
      class = (classNamed (module caller) classOrName)
    }
  }
  if (isNil class) { return nil }

  if (not (contains (fieldNames class) 'morph')) { // helper class optimization
	result = (new class)
	if (notNil (methodNamed class 'initialize')) { initialize result initData }
  	return result
  }

  return (instantiate class (self_stageMorph) initData)
}

to self_owner obj {
  if (isNil obj) { obj = (morph (implicitReceiver)) }
  if (not (isClass obj 'Morph')) { obj = (morph obj) }
  owner = (owner obj)
  if (isNil owner) { return nil }
  return (handler owner)
}

to self_stageMorph {
  stageM = (global 'StageMorph')
  if (notNil stageM) { return stageM }
  stage = (self_stage)
  if (isNil stage) { return nil }
  setGlobal 'StageMorph' (morph stage)
  return (morph stage)
}

to self_stage {
  m = (implicitReceiver)
  stageM = nil
  if (hasField m 'morph') {
	stageM = (ownerThatIsA (morph (implicitReceiver)) 'Stage')
  }
  if (notNil stageM) { return (handler stageM) }
  for p (parts (morph (global 'page'))) {
	if (isClass (handler p) 'ProjectEditor') {
	  return (stage (handler p))
	}
  }
  for p (parts (morph (global 'page'))) {
	if (isClass (handler p) 'Stage') {
	  return (handler p)
	}
  }
  return nil
}

to self_neighbors expansion className {
  // Return the neighboring instances of the receiver within the bounding box of
  // the receiver expanded by the given amount. If expansion is nil or 0, the
  // neighbors must be actually touching the receiver. If className is provided,
  // only neighbors of that class are included in the results.

  if (isNil expansion) { expansion = 0 }
  if (isOneOf className '' '*' 'any class') { className = nil }
  rcvr = (implicitReceiver)
  r = (fullBounds (morph rcvr))
  if (expansion > 0) { r = (expandBy r expansion) }
  stageM = (self_stageMorph)
  if (isNil stageM) { return (list) }

  allNeighbors = (list)
  for m (copy (parts stageM)) {
	if (rectanglesTouch (bounds m) r) {
	  add allNeighbors (handler m)
	}
  }
  remove allNeighbors rcvr

  result = (list)
  for n allNeighbors { // select only neighbors of className
	if (or (isNil className) (className == (className (classOf n)))) {
	  if (or (expansion > 0) (self_touching n)) { // if expansion is 0, must be actually touching
		add result n
	  }
	}
  }
  return result
}

to self_createCostume w h color {
  if (isNil color) { color = (gray 200) }
  m = (morph (implicitReceiver))
  p = (rotationCenter m)
  setCostume m (newBitmap w h color)
  placeRotationCenter m (first p) (last p)
  l = ((first p) - ((w / 2) + (pinX m)))
  t = ((last p) - ((h / 2) + (pinY m)))
  setBounds m (scaledAndRotatedBoundingBox (rect l t w h) (scaleX m) (scaleY m) (rotation m) (first p) (last p))
}

to self_costume name {
  m = (morph (implicitReceiver))
  if (isClass name 'String') {
	bm = (imageNamed name m)
	if (isNil bm) { bm = (costumeData m) }
  } else {
	bm = (costumeData m)
  }
  return (copy bm)
}

to imageNamed name m {
  proj = (projectForMorph m)
  if (isNil proj) { return nil }
  return (imageNamed proj name)
}

to self_setCostume bitmapOrName {
  m = (morph (implicitReceiver))
  if (isClass bitmapOrName 'String') {
	bitmapOrName = (imageNamed bitmapOrName m)
  }
  if (not (isClass bitmapOrName 'Bitmap')) { return }
  p = (rotationCenter m)
  setCostume m bitmapOrName
  placeRotationCenter m (first p) (last p)
}

to self_setTextCostume s c fontName fontSize {
  if (not (isClass s 'String')) { s = (toString s) }
  if (isNil c) { c = (gray 0) }
  if (isNil fontName) { fontName = 'Arial Bold' }
  if (isNil fontSize) { fontSize = 24 }
  setFont fontName fontSize
  w = (min ((stringWidth s) + (round (fontSize / 10))) 1000) // increase width by 10% of font size for italic
  h = (min (fontHeight) 1000)
  bm = (newBitmap w h (withAlpha c 1)) // alpha = 1 allow transparent areas to be touched
  setFont fontName fontSize
  drawString bm s c 0 0
  setCostume (morph (implicitReceiver)) bm
}

to self_snapshotCostume name {
  // Save a snapshot of my current costume to the images tab.

  m = (morph (implicitReceiver))
  proj = (projectForMorph m)
  if (isNil proj) { return }
  saveImageAs proj (takeSnapshot m) name
}

to self_snapshotStage name {
  // Save a snapshot of the stage (and everything on it) to the images tab.

  m = (morph (implicitReceiver))
  stage = (self_stageMorph)
  if (isNil stage) { return }
  proj = (projectForMorph m)
  if (isNil proj) { return }
  saveImageAs proj (takeSnapshot stage) name
}

to self_drawLine x1 y1 x2 y2 color w {
  if (isNil w) { w = 1 }
  m = (morph (implicitReceiver))
  bm = (costumeData m)
  if (not (isClass bm 'Bitmap')) { return }
  pen = (newVectorPen bm m (not (vectorTrails)))
  beginPath pen x1 y1
  lineTo pen x2 y2
  stroke pen color w
}

to self_fillWithColor color {
  // Fill my costume with the given color.
  bm = (costumeData (morph (implicitReceiver)))
  if (not (isClass bm 'Bitmap')) { return }
  fill bm color
  costumeChanged (morph (implicitReceiver))
}

to self_floodFill x y color threshold {
  bm = (costumeData (morph (implicitReceiver)))
  if (not (isClass bm 'Bitmap')) { return }
  floodFill bm (toInteger x) (toInteger y) color threshold
  costumeChanged (morph (implicitReceiver))
}

to self_fillRect x y w h color roundness {
  m = (morph (implicitReceiver))
  x = (toInteger x)
  y = (toInteger y)
  w = (abs (toInteger w))
  h = (abs (toInteger h))
  bm = (costumeData m)
  if (not (isClass bm 'Bitmap')) { return }
  if (and (notNil roundness) (roundness > 0)) {
	fillRoundedRect (newShapeMaker bm) (rect x y w h) roundness color
  } else {
	fillRect bm color x y w h
  }
  costumeChanged m
}

to self_fillCircle cx cy radius color borderWidth borderColor {
  bm = (costumeData (morph (implicitReceiver)))
  if (not (isClass bm 'Bitmap')) { return }
  drawCircle (newShapeMaker bm) cx cy radius color borderWidth borderColor
  costumeChanged (morph (implicitReceiver))
}

to self_drawText s x y color {
  bm = (costumeData (morph (implicitReceiver)))
  if (not (isClass bm 'Bitmap')) { return }
  if (not (isClass s 'String')) { s = (toString s) }
  drawString bm s color x y
  costumeChanged (morph (implicitReceiver))
}

to self_setFont fontName fontSize {
  if (isNil fontName) { fontName = 'Arial' }
  if (isNil fontSize) { fontSize = 24 }
  setFont fontName fontSize
}

to self_getPixel x y bm {
  // Note: Pixel coordinates are 1-based in the authoring system!

  if (isNil bm) { bm = (costumeData (morph (implicitReceiver))) }
  if (not (isClass bm 'Bitmap')) { return }
  return (interpolatedPixel bm x y (color))
}

to self_setPixel x y color bm {
  // Note: Pixel coordinates are 1-based in the authoring system!

  if (notNil bm) { // fast version for offscreen bitmaps
	setPixel bm (x - 1) (y - 1) color
	return
  }
  m = (morph (implicitReceiver))
  bm = (costumeData m)
  setPixel bm (x - 1) (y - 1) color
  costumeChanged m
}

to projectForMorph m {
  for p (parts (morph (global 'page'))) {
	if (isClass (handler p) 'ProjectEditor') {
	  return (project (handler p))
	}
  }
  for p (parts (morph (global 'page'))) {
	if (isClass (handler p) 'Stage') {
	  return (project (handler p))
	}
  }
  return nil
}

to self_drawBitmap bitmapOrName x y scale alpha {
  m = (morph (implicitReceiver))
  if (isClass bitmapOrName 'String') {
	srcBM = (imageNamed bitmapOrName m)
  } else {
	srcBM = bitmapOrName
  }
  if (not (isClass srcBM 'Bitmap')) { return }

  if (notNil scale) {
	w = (width srcBM)
	h = (height srcBM)
	scale = (min scale (4000 / w) (4000 / h))
	dstTxt = (newTexture (scale * w) (scale * h))
	srcTxt = (toTexture srcBM)
	showTexture dstTxt srcTxt 0 0 255 scale scale
	srcBM = (toBitmap dstTxt)
	destroyTexture srcTxt
	destroyTexture dstTxt
  }

  bm = (costumeData m)
  if (and (isClass bm 'Bitmap') (isClass srcBM 'Bitmap')) {
	drawBitmap bm srcBM x y alpha
	costumeChanged m
  }
}

to self_setPinXY x y { setPin (morph (implicitReceiver)) x y }

to self_mouseX {
  stage = (self_stageMorph)
  if (notNil stage) {
	return (first (normal stage (handX) (handY)))
  } else {
	return (handX)
  }
}

to self_mouseY {
  stage = (self_stageMorph)
  if (notNil stage) {
	return (0 - (last (normal stage (handX) (handY))))
  } else {
	return (handY)
  }
}

to self_distanceToMouse {
  m = (morph (implicitReceiver))
  rc = (rotationCenter m)
  dx = ((handX) - (first rc))
  dy = ((handY) - (last rc))
  dist = (sqrt ((dx * dx) + (dy * dy))) // screen distance
  stage = (self_stageMorph)
  if (notNil stage) { dist = (dist / (scale stage)) }
  return dist
}

to self_directionToMouse {
  m = (morph (implicitReceiver))
  rc = (rotationCenter m) //  in global (screen) coordinates
  dx = ((handX) - (first rc))
  dy = ((handY) - (last rc))
  return (atan (- dy) dx)
}

to self_distanceToSprite other {
  if (isClass other 'String') { other = (self_findInstanceOf other) }
  if (not (hasField other 'morph')) { return 0 }
  otherRC = (rotationCenter (morph other))
  m = (morph (implicitReceiver))
  rc = (rotationCenter m)
  dx = ((first rc) - (first otherRC))
  dy = ((last rc) - (last otherRC))
  dist = (sqrt ((dx * dx) + (dy * dy)))
  stage = (self_stageMorph)
  if (notNil stage) { dist = (dist / (scale stage)) }
  return dist
}

to self_directionToSprite other {
  if (isClass other 'String') { other = (self_findInstanceOf other) }
  if (not (hasField other 'morph')) { return 0 }
  m = (morph (implicitReceiver))
  otherRC = (rotationCenter (morph other))
  myRC = (rotationCenter m)
  dx = ((first otherRC) - (first myRC))
  dy = ((last otherRC) - (last myRC))
  return (atan (- dy) dx)
}

to self_findInstanceOf className {
  // Return an instance of the given class on the stage or nil if there isn't one.
  stage = (self_stageMorph)
  if (notNil stage) {
	for m (parts stage) {
	  if (className == (className (classOf (handler m)))) { return (handler m) }
	}
  }
  for m (parts (morph (hand (global 'page')))) {
	if (isClass (handler m) className) { return (handler m) }
  }
  return nil
}

to self_localMouseX {
  m = (morph (implicitReceiver))
  return (toInteger ((first (normal m (handX) (handY))) + ((normalWidth m) / 2)))
}

to self_localMouseY {
  m = (morph (implicitReceiver))
  return (toInteger ((last (normal m (handX) (handY))) + ((normalHeight m) / 2)))
}

to self_touchingMouse {
  handX = (handX)
  handY = (handY)
  morph = (morph (implicitReceiver))
  if (not (containsPoint (bounds morph) handX handY)) { return false }
  return ((implicitReceiver) == (objectAt (hand (global 'page'))))
}

to self_touching other {
  if ('edge' == other) {
	stage = (self_stageMorph)
	if (isNil stage) { return false }
	fb = (fullBounds (morph (implicitReceiver)))
	return (not (containsRectangle (bounds stage) fb))
  }
  if ('mouse' == other) {
	return (self_touchingMouse)
  }
  if (isClass other 'String') {
	// if other is a string, return true if this sprite
	// is touching any sprite with the given class name
	for each (self_neighbors 0 other) {
		if (self_touching each) { return true }
	}
	return false
  }
  if (not (isClass other 'Morph')) { other = (morph other) }
  m = (morph (implicitReceiver))
  if (not (intersects (bounds m) (bounds other))) { return false }

  r = (intersection (bounds m) (bounds other))
  if (or ((width r) < 1) ((height r) < 1)) { return false }
  xOffset = (- (left r))
  yOffset = (- (top r))
  ownerScale = (scale (owner m))
  w = (ceiling ((width r) / ownerScale))
  h = (ceiling ((height r) / ownerScale))
  if (or (w < 1) (h < 1)) { return false }
  txt = (newTexture w h)
  draw m txt xOffset yOffset (1 / ownerScale)
  bm1 = (toBitmap txt)
  fill txt (transparent)
  draw other txt xOffset yOffset (1 / ownerScale)
  bm2 = (toBitmap txt)
  destroyTexture txt
  return (bitmapsTouch bm1 bm2)
}

to self_penDown {penDown (morph (implicitReceiver))}
to self_penUp {penUp (morph (implicitReceiver))}
to self_setPenSize num {setPenLineWidth (morph (implicitReceiver)) (max 0 num)}
to self_setPenColor clr {setPenColor (morph (implicitReceiver)) clr}
to self_stampCostume transparency {stampCostume (morph (implicitReceiver)) transparency}
to self_clear {penClear (morph (implicitReceiver))}

to self_penFillArea x y color {
  m = (morph (implicitReceiver))
  target = (penTarget m)
  if (isNil target) { return }
  trails = (requirePenTrails target true)
  trailsBM = (toBitmap trails)
  seedX = (toInteger (x + ((width trailsBM) / 2)))
  seedY = (toInteger (((height trailsBM) / 2) - y))
  if (isNil color) { color = (color (requirePen m)) }
  floodFill trailsBM seedX seedY color
  drawBitmap trails trailsBM 0 0 255 0 // blend mode 'none' so we can fill with transparent)
  changed target
}

to playSound snd {
  if (isClass snd 'String') {
	// argument is the name of a sound
	proj = (projectForMorph (morph (implicitReceiver)))
	if (notNil proj) { snd = (soundNamed proj snd) }
  }
  if (not (isClass snd 'Sound')) { return }
  mixer = (soundMixer (global 'page'))
  addSound mixer snd
  while (isPlaying mixer snd) {
	waitForNextFrame
  }
}

to samplesForSoundNamed sndName {
  proj = (projectForMorph (morph (implicitReceiver)))
  if (notNil proj) { snd = (soundNamed proj sndName) }
  if (isNil snd) { error (join 'No sound named' sndName) }
  return (samples snd)
}

to playSoundSamples samples rate {
  if (isNil rate) { rate = 100 }
  snd = (newSound samples (220.50 * rate) false 'samples')
  mixer = (soundMixer (global 'page'))
  addSound mixer snd
  while (isPlaying mixer snd) {
	waitForNextFrame
  }
}

to stopSound snd {
  removeSound (soundMixer (global 'page')) snd
}

to stopAllSounds {
  stopAllSounds (soundMixer (global 'page'))
}

to fftOfSamples samples useWindow {
  if (isNil useWindow) { useWindow = true }
  n = (count samples)
  if (n < 2) { return (array) }
  if (not (isPowerOfTwo n)) {
	fftSize = 2
	while (and (fftSize <= 8192) ((n >= (2 * fftSize)))) {
		fftSize = (2 * fftSize)
	}
	samples = (copyFromTo samples 1 fftSize)
  }
  return (fft (toArray samples) useWindow)
}

to setPageColor color {
  page = (global 'page')
  setColor page color
  changed page
}

to self_setStageColor color bitmapOrName {
  m = (morph (implicitReceiver))
  stage = (self_stageMorph)
  if (notNil stage) {
	setColor (handler stage) color
	if (isClass bitmapOrName 'String') {
	  bitmapOrName = (imageNamed bitmapOrName m)
	}
	setBackgroundImage (handler stage) bitmapOrName
  } else {
	setPageColor color
  }
}

to points n {
  return (n * (global 'scale'))
}

to httpGet host path port {
  if (isNil path) { path = '/' }
  if (not (beginsWith path '/')) { path = (join '/' path) }
  if (isNil port) { port = 80 }
  socket = (openClientSocket host port)
  if (isNil socket) { return '' }
  crlf = (string 13 10)
  request = (join
    'GET ' (urlEncode path) ' HTTP/1.1' crlf
    'Host: ' host crlf crlf)
  writeSocket socket request
  waitMSecs 1000 // wait a bit
  response = (list)
  count = 1 // start loop
  while (count > 0) {
	chunk = (readSocket socket)
	count = (byteCount chunk)
	if (count > 0) { add response chunk }
  }
  closeSocket socket
  return (joinStrings response)
}

to showText s {
  if (not (isClass s 'String')) { s = (toString s) }
  openWorkspace (global 'page') s
}

to askUser question defaultAnswer {
  if (isNil defaultAnswer) { defaultAnswer = '' }
  page = (global 'page')
  hand = (hand page)

  // center the dialog on the Stage or page
  centerX = (hCenter (bounds (morph page)))
  centerY = (vCenter (bounds (morph page)))
  for m (allMorphs (morph page)) {
	if (isClass (handler m) 'Stage') {
	  centerX = (hCenter (bounds m))
	  centerY = (vCenter (bounds m))
	}
  }

  p = (new 'Prompter')
  initialize p question defaultAnswer 'line'
  fixLayout p
  setCenter (morph p) centerX centerY
  keepWithin (morph p) (bounds (morph page))
  addPart (morph page) (morph p)
  edit (textBox p) hand
  selectAll (textBox p)
  while (not (isDone p)) {
	waitMSecs 100
  }
  result = (answer p)
  if (notNil (toNumber result nil)) { result = (toNumber result) }
  return result
}

to selectFromMenu itemList {
  if (not (isAnyClass itemList 'Array' 'List')) { return nil }
  if (isEmpty itemList) { return nil }
  resultHolder = (array nil)
  menu = (menu nil (action 'atPut' resultHolder 1) true)
  for item itemList {
	addItem menu item nil nil (thumbnailOrNil item)
  }
  popUpAtHand menu (global 'page')
  while (notNil (owner (morph menu))) {
	waitMSecs 50
  }
  return (first resultHolder)
}

to showMenuFor itemList action {
  if (not (isAnyClass itemList 'Array' 'List')) { return }
  if (isEmpty itemList) { return }
  menu = (menu nil action true)
  for item itemList {
	addItem menu item nil nil (thumbnailOrNil item)
  }
  popUpAtHand menu (global 'page')
}

to thumbnailOrNil anObject {
  thumbSize = (20 * (global 'scale'))
  if (isClass anObject 'Bitmap') {
	return (thumbnail anObject thumbSize thumbSize)
  } (isClass anObject 'Morph') {
	return (thumbnailOrNil (costumeData anObject))
  } (hasField anObject 'morph') {
	return (thumbnailOrNil (getField anObject 'morph'))
  }
  return nil
}

to self_readFile fileName binaryFlag {
  if (true == binaryFlag) {
	return (readFile fileName true)
  }
  data = (readFile fileName)
  if (isNil data) { return nil }
  if (beginsWith data '~=== Begin GP Object Data ===~') {
	return (read (new 'Serializer') (toBinaryData data))
  } (beginsWith data (toBinaryData (array 137 80 78 71))) {
	return (readFrom (new 'PNGReader') (toBinaryData data))
  }
  return data
}

to self_writeFile fileName data {
  if (isAnyClass data 'String' 'BinaryData') {
	writeFile fileName data
  } (isClass data 'Bitmap') {
	writeFile fileName (encodePNG data)
  } else {
	blob = (write (new 'Serializer') data)
	writeFile fileName blob
  }
}

to playNote pitch seconds instrument {
  if (isNil seconds) { seconds = 1 }
  if (isNil instrument) { instrument = 'piano' }
  if (isNumber pitch) {
	k = pitch
  } else {
	k = (toNumber pitch nil)
	if (isNil k) {
	  notes = (parse (new 'ABCParser') pitch)
	  if ((count notes) > 0) {
		k = (key (first notes))
	  }
	}
	if (isNil k) { return } // not a valid pitch
  }
  k = (clamp k 12 127)
  if (seconds < 0) {
	// Negative seconds makes the command return immediately rather than waiting until
	// the note finishes playing. The duration is the absolute value of seconds.
	seconds = (- seconds)
	doNotWait = true
  } else {
	doNotWait = false
  }
  notePlayer = (notePlayer (newSampledInstrument instrument) k (round (1000 * seconds)))
  mixer = (getMixer)
  addSound mixer notePlayer
  if doNotWait {return}
  while (isPlaying mixer notePlayer) {
	waitMSecs 5
  }
}

to speak text voice rate {
  speak (getMixer) text voice rate
}

to stopSpeaking {
  stopSpeaking (getMixer)
}

to self_costumeColor x y {
  m = (morph (implicitReceiver))

  stage = (self_stageMorph)
  if (notNil stage) {
    p = (transform stage x (0 - y))
    x = (first p)
    y = (last p)
  }

  p = (normal m x y)
  localX = (toInteger ((first p) + ((normalWidth m) / 2)))
  localY = (toInteger ((last p) + ((normalHeight m) / 2)))

  bm = (costumeData m)
  if (not (isClass bm 'Bitmap')) { return }
  return (interpolatedPixel bm localX localY (color))
}

to screenColorAt x y {
  stage = (self_stageMorph)
  if (notNil stage) {
    p = (transform stage x (0 - y))
    x = (first p)
    y = (last p)
  }
  bm = (takeSnapshotWithBounds (morph (global 'page')) (rect x y 1 1))
  return (getPixel bm 0 0)
}

to self_beginPath x y {
  m = (morph (implicitReceiver))
  bm = (costumeData m)
  if (not (isClass bm 'Bitmap')) { return }
  pen = (newVectorPen bm m)
  setField m 'vectorPen' pen
  beginPath pen x y
}

to self_setPathDirection angle {
  m = (morph (implicitReceiver))
  pen = (getField m 'vectorPen')
  if (isNil pen) { return }
  setHeading pen angle
}

to self_extendPath distance curvature {
  m = (morph (implicitReceiver))
  pen = (getField m 'vectorPen')
  if (isNil pen) { return }
  forward pen distance curvature
}

to self_turnPath distance degrees radius {
  m = (morph (implicitReceiver))
  pen = (getField m 'vectorPen')
  if (isNil pen) { return }
  turn pen distance degrees radius
}

to self_addLineToPath x y {
  m = (morph (implicitReceiver))
  pen = (getField m 'vectorPen')
  if (isNil pen) { return }
  lineTo pen x y
}

to self_addCurveToPath x y cx cy {
  m = (morph (implicitReceiver))
  pen = (getField m 'vectorPen')
  if (isNil pen) { return }
  curveTo pen x y cx cy
}

to self_strokePath color width jointStyle capStyle {
  m = (morph (implicitReceiver))
  pen = (getField m 'vectorPen')
  if (isNil pen) { return }
  stroke pen color width jointStyle capStyle
}

to self_fillPath color {
  m = (morph (implicitReceiver))
  pen = (getField m 'vectorPen')
  if (isNil pen) { return }
  fill pen color
}
