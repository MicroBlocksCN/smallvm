// Morph

defineClass Morph owner parts handler bounds costume costumeData transformedCostume costumeChanged isVisible alpha grabRule noticesTransparentTouch isClipping minWidth minHeight fps lastStepTime acceptsEvents penTrails penTrailsData tag param pen drawOnOwner rotation rotateWithOwner scaleX scaleY pinX pinY vectorPen shouldRedraw maxWidth maxHeight

to newMorph handler {
  return (initialize (new 'Morph' nil (list) handler (rect) nil nil nil false true 255 'defer' false false 1 1 nil nil true))
}

method initialize Morph {
  drawOnOwner = true
  pinX = 0
  pinY = 0
  rotation = 0
  rotateWithOwner = true
  scaleX = 1
  scaleY = 1
  shouldRedraw = false
  noticesTransparentTouch = true
  return this
}

// info

method fieldInfo Morph fieldName {
  if ('grabRule' == fieldName) {
    info = (dictionary)
    atPut info 'type' 'options'
    atPut info 'options' (array 'defer' 'handle' 'template' 'draggableParts' 'ignore')
    return info
  }
  return nil
}

// backstop

to handler anyObject { return nil } // allow "(handler nil)" for convenience

// accessing

method owner Morph {return owner}
method parts Morph {return parts}
method handler Morph {return handler}
method setHandler Morph aHandler {handler = aHandler}
method bounds Morph {return bounds}
method setBounds Morph aRect {bounds = aRect}
method costumeData Morph {return costumeData}
method setTag Morph aString {tag = aString}
method tag Morph {return tag}
method setParam Morph value {param = value}
method param Morph {return param}
method pinX Morph {return pinX}
method pinY Morph {return pinY}
method rotateWithOwner Morph {return rotateWithOwner}

method isTopLevel Morph {
  return (or (isNil owner) (isAnyClass (handler owner) 'Page' 'Stage'))
}

// disabling events

method acceptsEvents Morph {
  if (isNil acceptsEvents) {acceptsEvents = true}
  return acceptsEvents
}

method acceptEvents Morph bool {acceptsEvents = bool}

// bounds accessing

method left Morph { return (left bounds) }
method right Morph { return (right bounds) }
method top Morph { return (top bounds) }
method bottom Morph { return (bottom bounds) }
method width Morph { return (width bounds) }
method height Morph { return (height bounds) }

method page Morph {
  page = (handler (root this))
  if (not (isClass page 'Page')) {
    return nil // error 'This morph is not in a page'
  }
  return page
}

// Costume

method setCostume Morph aBitmapColorOrNil ignoreBounds {
  changed this
  if (isNil ignoreBounds) {ignoreBounds = false}
  transformedCostume = nil
  if (isClass aBitmapColorOrNil 'Bitmap') {
    costumeData = aBitmapColorOrNil
  } (isClass aBitmapColorOrNil 'Color') {
	costumeData = aBitmapColorOrNil
	changed this
	return
  } (isNil aBitmapColorOrNil) {
    costumeData = nil
  } else {
    error 'expected a bitmap, color, or nil. Received ' aBitmapColorOrNil
  }
  if (and (not ignoreBounds) (notNil costumeData)) {
    setWidth bounds (scaleX * (width costumeData))
    setHeight bounds (scaleY * (height costumeData))
  }
  changed this
}

method costumeChanged Morph {
  // Called when the original costume is changed (e.g. pixel color changed).

  if costumeChanged { return } // change was already reported
  costumeChanged = true
  changed this
}

method updateCostume Morph {
  // Called when the scale or rotation changes.

  transformedCostume = nil
  changed this
}

method isNormal Morph {
  // NOTE: This optimization causes problems with stamping in WordSpinner project in
  // some cases (normal stage size, final stamp in the circle).
  // The problem seems to be that we don't know, when the optimization is performed,
  // if we might render the morph into a destination with scale other than 1.
  // Tried disabling this, but noticed some signs of running out of textures,
  // so am reenabled it for now.

  if ('iOS' == (platform)) { return false } // force use of textures on iOS
  if ('Browser' == (platform)) { return false } // force use of textures on browsers

  return (and
    (0 == (rotation % 360))
    (scaleX == 1)
    (scaleY == 1)
  )
}

method transformedCostume Morph {
  if (isNil transformedCostume) {
	updateTransformedCostume this
  }
  return transformedCostume
}

method updateTransformedCostume Morph {
  if (notNil transformedCostume) { return }
  if (isNil costumeData) { return }
  srcW = (width costumeData)
  srcH = (height costumeData)
  dstW = (width this)
  dstH = (height this)
  if (or
	(isNil transformedCostume)
	(!= (width transformedCostume) dstW)
	(!= (height transformedCostume) dstH)) {
	  transformedCostume = (newBitmap dstW dstH)
  }
  warpBitmap transformedCostume costumeData (dstW / 2) (dstH / 2) scaleX scaleY (0 - rotation)
}

// scaling and rotating

method rotation Morph {return rotation}
method rotatesWithOwner Morph {return rotateWithOwner}
method setRotateWithOwner Morph bool {rotateWithOwner = bool}
method toggleRotationStyle Morph {rotateWithOwner = (not rotateWithOwner)}
method scale Morph {return scaleX}
method scaleX Morph {return scaleX}
method scaleY Morph {return scaleY}
method rotationCenter Morph {return (transform this pinX pinY)}

method setRotationCenter Morph x y {
  pin = (normal this x y)
  setPin this (first pin) (last pin)
}

method setRotationCenterTo Morph another {setRotationCenter this (hCenter (bounds another)) (vCenter (bounds another))}

method placeRotationCenter Morph x y {
  rc = (rotationCenter this)
  if (isNil x) {x = (first rc)}
  if (isNil y) {y = (last rc)}
  moveBy this (x - (first rc)) (y - (last rc))
}

method setPin Morph x y {
  if (isNil x) {x = 0}
  if (isNil y) {y = pinY}
  pinX = x
  pinY = y
}

method setPinToTopLeft Morph {
  // Set pin point to top-left corner.
  pinX = ((normalWidth this) / -2)
  pinY = ((normalHeight this) / -2)
}

method setScale Morph newScale {rotateAndScale this rotation newScale nil nil nil true}
method setScaleAround Morph aroundX aroundY newScale {rotateAndScale this rotation newScale nil aroundX aroundY}

method rotateAndScale Morph heading xScale yScale aroundX aroundY noDraw {
  if (isNil heading) {heading = 0}
  if (isNil xScale) {xScale = 1}
  if (isNil yScale) {yScale = xScale}
  rc = (rotationCenter this)
  rx = (first rc)
  ry = (last rc)
  fixedX = aroundX
  fixedY = aroundY
  if (isNil fixedX) {fixedX = rx}
  if (isNil fixedY) {fixedY = ry}
  if (isNil noDraw) {noDraw = false}

  unrotated = (scaleAndRotateAround rx ry (- rotation) fixedX fixedY)
  distX = ((first unrotated) - fixedX)
  distY = ((last unrotated) - fixedY)
  unscaledX = ((first unrotated) - (distX - (distX / scaleX)))
  unscaledY = ((last unrotated) - (distY - (distY / scaleY)))
  centerX = (unscaledX - pinX)
  centerY = (unscaledY - pinY)

  normalBounds = (rect
    (centerX - ((normalWidth this) / 2))
    (centerY - ((normalHeight this) / 2))
    (normalWidth this)
    (normalHeight this)
  )

  // apply
  xDelta = (xScale / scaleX)
  yDelta = (yScale / scaleY)
  rDelta = (heading - rotation)
  scaleX = xScale
  scaleY = yScale
  rotation = (heading % 360)
  if (rotation < 0) { rotation += 360 } // ensure range is [0..360)
  changed this
  bounds = (scaledAndRotatedBoundingBox normalBounds scaleX scaleY rotation fixedX fixedY)
  updateCostume this

  // draw pen trails
  if (and (isPenDown this) (not noDraw)) {
    target = (penTarget this)
    if (and (notNil target) (notNil pen)) {
	  movePenBy this 0 0 // fix initial pen position after being manually dragged
      setCanvas pen (requirePenTrails target)
      penEnd = (rotationCenter this)
      if (and ((x pen) == 0) ((y pen) == 0)) {
        setX pen ((rx - (left target)) / (scaleX target))
        setY pen ((ry - (top target)) / (scaleY target))
      }
      goto pen (((first penEnd) - (left target)) / (scaleX target)) (((last penEnd) - (top target)) / (scaleY target))
      if (isVisible target) {changed target}
    }
  }

  // propagate
  for each parts {
    if (rotatesWithOwner each) {
      rotateAndScale each (+ rDelta (rotation each)) (* xDelta (scaleX each)) (* yDelta (scaleY each)) fixedX fixedY noDraw
    } else {
      r = (rotation each)
      //ps = (rotationCenter each)
      rotateAndScale each (+ rDelta (rotation each)) (* xDelta (scaleX each)) (* yDelta (scaleY each)) fixedX fixedY true
      rotateAndScale each r (scaleX each) (scaleY each) nil nil noDraw
    }
  }

  changed this
  return
}

method normalWidth Morph {
  if (isClass costumeData 'Bitmap') {return (width costumeData)}
  return ((width this) / scaleX)
}

method normalHeight Morph {
  if (isClass costumeData 'Bitmap') {return (height costumeData)}
  return ((height this) / scaleY)
}

method normal Morph x y {
  // answer an array containing the given global coordinates
  // transformed to local ones relative to the receiver's center
  xd = (x - (hCenter bounds))
  yd = (y - (vCenter bounds))
  unrotated = (scaleAndRotateAround xd yd (- rotation))
  return (array ((first unrotated) / scaleX) ((last unrotated) / scaleY))
}

method penPosition Morph x y {
  // answer an array containing the given globel coordinates
  // transformed to local ones relative to the receiver's topLeft corner
  normal = (normal this x y)
  return (array
    ((first normal) + ((normalWidth this) / 2))
    ((last normal) + ((normalHeight this) / 2))
  )
}

method transform Morph x y {
  // answer an array containing the given local (normal, relative to the receiver's
  // center) coordinates transformed to globally scaled and rotated ones
  if (rotation == 0) {
	return (array ((hCenter bounds) + (scaleX * x)) ((vCenter bounds) + (scaleY * y)))
  }
  localP = (scaleAndRotateAround x y rotation 0 0 scaleX scaleY)
  return (array (+ (hCenter bounds) (first localP)) (+ (vCenter bounds) (last localP)))
}

method drawingPoint Morph {
  // Return the point at which the costume should be drawn.
  // Deduced from its currently scaled and rotated bounds.

  w = (width bounds)
  h = (height bounds)

  // take into account that the bounds can exceed the
  // costume's dimensions, e.g. inside scroll frames
  if (and (isClass costumeData 'Bitmap') ((rotation % 360) == 0)) {
	costumeW = (scaleX * (width costumeData))
	costumeH = (scaleY * (height costumeData))
	if (costumeW < w) { w = costumeW }
	if (costumeH < h) { h = costumeH }
  }

  // the area's center is invariant for the rotation primitive
  rx = ((left bounds) + (w / 2))
  ry = ((top bounds) + (h / 2))

  // determine the scaled extent of the unrotated texture
  scaledWidth = (scaleX * (normalWidth this))
  scaledHeight = (scaleY * (normalHeight this))

  // the left-top point is invariant for the scaling primitive
  return (array
    (rx - (scaledWidth / 2))
    (ry - (scaledHeight / 2))
  )
}

method scaleTo Morph other {
  otherRC = (rotationCenter other)
  rc = (rotationCenter this)
  dx = ((first otherRC) - (first rc))
  dy = ((last otherRC) - (last rc))
  dist = (sqrt ((dx * dx) + (dy * dy)))
  scl = (dist / ((normalWidth this) / 2))
  rotateAndScale this rotation scl scl
}

method pointTo Morph other {
  otherRC = (rotationCenter other)
  rc = (rotationCenter this)
  dx = ((first otherRC) - (first rc))
  dy = ((last otherRC) - (last rc))
  rotateAndScale this (atan (- dy) dx) scaleX scaleY
}

// visibility

method alpha Morph { return alpha }
method transparency Morph { return ((255 - alpha) / 2.55) }

method setAlpha Morph anInteger {
  if (isNil anInteger) {anInteger = 255}
  alpha = anInteger
  changed this
}

method setTransparency Morph n {
  // Range: 0 is opaque, 100 fully transparent

  setAlpha this (clamp (round (2.55 * (100 - n))) 0 255)
}

method isVisible Morph {return isVisible}
method isHidden Morph {return (not isVisible)}

method hide Morph {
  if isVisible {
    changed this
    isVisible = false
  }
}

method show Morph {
  if isVisible {return}
  isVisible = true
  changed this
}

// scrolling into view

method scrollIntoView Morph {
  sf = (ownerThatIsA this 'ScrollFrame')
  if (notNil sf) {
    scrollIntoView (handler sf) bounds
  }
}

// discoverability

method grabRule Morph {return grabRule}

method setGrabRule Morph aString {
  // 'defer' (default) - I can be a handle for grabbing a morph in my owner chain
  // 'handle' - I can be dragged directly (along with my parts, if any)
  // 'template' - if grabbed I will produce a duplicate of my handler
  // 'ignore' - I eclipse all dragging events, handling them myself
  grabRule = aString
}

method noticesTransparentTouch Morph {return noticesTransparentTouch}
method setTransparentTouch Morph bool {noticesTransparentTouch = bool}

// clipping

method isClipping Morph {return isClipping}

method setClipping Morph bool {
  isClipping = bool
  changed this
}

// other settings

method minWidth Morph {return minWidth}
method minHeight Morph {return minHeight}
method maxWidth Morph {return maxWidth}
method maxHeight Morph {return maxHeight}

method setMinExtent Morph x y {
  if (isNil x) {x = minWidth}
  if (isNil y) {y = minHeight}
  minWidth = x
  minHeight = y
}

method setMaxExtent Morph x y {
  if (isNil x) {x = maxWidth}
  if (isNil y) {y = maxHeight}
  maxWidth = x
  maxHeight = y
}

method resizingConstraint Morph xOffset yOffset {
  // answer an array denoting the minimum left and top coordinates for a resizing handle
  if (isNil xOffset) {xOffset = 0}
  if (isNil yOffset) {yOffset = 0}
  return (array ((left bounds) + (minWidth - xOffset)) ((top bounds) + (minHeight - yOffset)))
}

method fps Morph {return fps}

method setFPS Morph anIntegerOrNil {
  fps = anIntegerOrNil
  if (isNil fps) {
    lastStepTime = nil
  } else {
    lastStepTime = (msecsSinceStart)
  }
}

method disableStepping Morph {
  // Disable stepping. Used by the debugger to pause stepping when an error is encountered.
  // Details: Negative fps indicates stepping disabled. -1000 means original fps was nil.

  if (isNil fps) {
	fps = -1000
  } else {
	fps = (- (abs fps))
  }
}

method enableStepping Morph {
  // Enable stepping after it's been disabled.

  if (or (isNil fps) (fps > 0)) { return } // already enabled
  if (-1000 == fps) { setFPS this nil }
  setFPS this (abs fps)
}

// printing

method toString Morph {
  if (isNil handler) { return '<Morph>' }
  return (join '<Morph ' (className (classOf handler)) '>')
}

// constructing hierarchy

method addPart Morph another {
  if (notNil (owner another)) {removePart (owner another) another}
  add parts another
  setOwner another this
  changed another
}

method userAddPart Morph another {
  addPart this another
  setGrabRule another 'defer'
}

method removePart Morph another {
  uninterruptedly {
	changed another
	remove parts another
	setOwner another nil
	changed this
  }
}

method removeAllParts Morph {
  reportDamage this (fullBounds this) // remove damage enclosing all parts
  for p parts { setOwner p nil }
  parts = (list)
  changed this
}

method removeFromOwner Morph {
  if (notNil owner) {
	removePart owner this
  }
}

method comeToFront Morph {
  if (notNil owner) {
    addPart owner this
  }
}

method goBackBy Morph n {
  if (isNil owner) { return }
  if (isNil n) { n = 1 }
  ownerParts = (parts owner)
  i = (indexOf ownerParts this)
  if (isNil i) { return } // shouldn't happen
  remove ownerParts this
  addAt ownerParts (i - n) this
  changed this
}

method setOwner Morph another {
  // private - use 'addPart' to construct hierarchies
  owner = another
}

method printHierarchy Morph indent {
  if (isNil indent) { indent = 0 }
  prefix = (joinStrings (newArray (4 * indent) ' '))
  costumeBytes = ((4 * ((width bounds) * (height bounds))) / 1000)
  if (costumeBytes > 500) {
	if (isClass costumeData 'Bitmap') {
	  print prefix (className (classOf handler)) (width bounds) (height bounds) (join '' costumeBytes 'k')
	} else {
	  print prefix (className (classOf handler)) (className (classOf costumeData))
	}
  }
  for m parts {
	printHierarchy m (indent + 1)
  }
}

// accessing hierarchy

method root Morph {
  result = this
  while (notNil (owner result)) {result = (owner result)}
  return result
}

method allMorphs Morph includeHidden {
  // answer a list of myself and all my visible parts
  if (isNil includeHidden) { includeHidden = false }
  return (addAllMorphsTo this (list) includeHidden)
}

method addAllMorphsTo Morph aList includeHidden {
  // private - helper method for "allMorphs"
  if (or isVisible includeHidden) {
    add aList this
    for m parts {addAllMorphsTo m aList includeHidden}
  }
  return aList
}

method partThatIs Morph className {
  for m parts {
    if (isClass (handler m) className) {return m}
    result = (partThatIs m className)
    if (notNil result) {return result}
  }
  return nil
}

method morphsAt Morph x y result {
  // Answer a list of morphs at the given point.
  if (isNil result) { result = (list) }
  if (containsPoint bounds x y) {
	add result this
	for m parts {morphsAt m x y result}
  } else {
	if (not (isClipping this)) {
	  for m parts {morphsAt m x y result}
	}
  }
  return result
}

method allOwners Morph {
  // answer a list of all elements in my owner chain including myself
  result = (list)
  add result this
  m = owner
  while (notNil m) {
    add result m
    m = (owner m)
  }
  return result
}

method ownerThatIsA Morph className {
  m = this
  while (notNil m) {
	if (isClass (handler m) className) {return m}
	m = (owner m)
  }
  return nil
}

method parentHandler Morph {
  // Return the handler of this morph's owner or nil if the owner is nil.
  // skip stand-alone Morphs
  if (isNil owner) {return nil}
  if (notNil (handler owner)) {return (handler owner)}
  return (parentHandler owner)
}

method fullBounds Morph {
  result = (copy bounds)
  if (or isClipping (isEmpty parts)) { return result }
  for m parts {
    if (getField m 'isVisible') {
      merge result (fullBounds m)
    }
  }
  return result
}

method fullVisibleBounds Morph {
  result = (visibleBounds this)
  for m parts {
    if (getField m 'isVisible') {
      merge result (visibleBounds m)
    }
  }
  return result
}

method visibleBounds Morph {
  result = (copy bounds)
  for m (allOwners this) {
    if (isClipping m) {intersect result (bounds m)}
  }
  return result
}

method fullCostume Morph maxW maxH {
  fb = (fullBounds this)
  w = (ceiling (width fb))
  h = (ceiling (height fb))
  // truncate size to avoid running out of memory
  if (isNil maxW) { maxW = 2000 }
  if (isNil maxH) { maxH = 4000 }
  if (or (w > maxW) (h > maxH)) {
    w = (min w maxW)
    h = (min h maxH)
  }
  if (or (w == 0) (h == 0)) {return (newBitmap 1 1)}
  result = (newBitmap w h (gray 0 0))
  offX = ((left this) - (left fb))
  offY = ((top this) - (top fb))
  ctx = (newGraphicContextOn result)
  setOffset ctx (0 - (left fb)) (0 - (top fb))
  fullDrawOn this ctx
  return result
}

// shadow (bitmap shadow, used when not running the browser)

method shadow Morph transparency offset {
  if (isClass handler 'Block') { fixLayout handler }
  fb = (fullBounds this)
  bm = (fullCostume this)
  shadowBM = (newBitmap (width bm) (height bm) (gray 0 transparency))
  applyMask shadowBM bm
  s = (newMorph)
  setCostume s shadowBM // to do: make the shadow untouchable and neutral for fullBounds
  setPosition s ((left fb) + offset) ((top fb) + offset)
  return s
}

method stackPart Morph offset layers {
  clr = (color 153 255 213)
  drk = (darker clr 60)
  fb = (fullBounds this)
  fc = (fullCostume this)
  total = (layers * offset)
  bm = (newBitmap ((width fc) + total) ((height fc) + total))
  for l layers {
    drawBitmap bm fc (total - (offset * l)) (total - (offset * l))
  }
  mask = (newBitmap (width bm) (height bm))
  drawBitmap mask fc 0 0
  applyMask bm mask true // cut out fullCostume, offset left and up

  s = (newMorph)
  setTag s 'stack'
  setParam s layers
  setCostume s bm
  setPosition s (left fb) (top fb)
  return s
}

method getStackPart Morph {
  for each parts {
    if ((tag each) == 'stack') {return each}
  }
  return nil
}

method addStackPart Morph border layers {addPart this (stackPart this border layers)}

method removeStackPart Morph {
  st = (getStackPart this)
  if (notNil st) {
    removePart this st
    return true
  }
  return false
}

method signalPart Morph msg txtColor bgColor {
  if (isNil bgColor) {bgColor = (color 153 255 213)}
  if (isNil txtColor) {txtColor = (color)}
  drk = (darker bgColor 60)
  fb = (fullBounds this)

  scale = (global 'scale')
  bubble =  (stringImage (toString msg) 'Arial' (scale * 12) txtColor 'center' (lighter bgColor 80) scale scale 0 scale clr nil nil false)
  bm = (newBitmap (+ (width bubble) (height bubble)) ((height bubble) + 2))
  fillRoundedRect (newShapeMaker bm) (rect 0 0 (width bm) (height bm)) ((height bubble) / 2) bgColor 1 drk drk
  drawBitmap bm bubble ((height bubble) / 2) 1
  s = (newMorph)
  setTag s 'signal'
  setParam s msg
  setCostume s bm
  setPosition s (left fb) (top fb)
  return s
}

method getSignalPart Morph {
  for each parts {
    if ((tag each) == 'signal') {return each}
  }
  return nil
}

method addSignalPart Morph msg txtColor bgColor {addPart this (signalPart this msg txtColor bgColor)}

method removeSignalPart Morph {
  sp = (getSignalPart this)
  if (notNil sp) {
    removePart this sp
    return true
  }
  return false
}

// highlights

method highlight Morph size {
  highlightM = (getHighlight this)
  if (notNil highlightM) { return highlightM }

  if ('Browser' == (platform)) {
	highlightM = (morph (newShadowEffect handler 'highlight'))
  } else {
	s2 = (size * 2)
	bm = (fullCostume this)
	hl = (newBitmap (+ s2 (width bm)) (+ s2 (height bm)) (colorHex 'FED722'))

	maskBM = (newBitmap (width hl) (height hl))
	drawBitmap maskBM bm 0 0
	drawBitmap maskBM bm size 0
	drawBitmap maskBM bm s2 0
	drawBitmap maskBM bm s2 size
	drawBitmap maskBM bm s2 s2
	drawBitmap maskBM bm size s2
	drawBitmap maskBM bm 0 s2
	drawBitmap maskBM bm 0 size
	applyMask hl maskBM // make silhouette

	fill maskBM (transparent)
	drawBitmap maskBM bm size size
	applyMask hl maskBM true // punch a hole the shape of fullCostume

	highlightM = (newMorph)
	setCostume highlightM hl
	setPosition highlightM (- (left bounds) size) (- (top bounds) size)
  }
  setTag highlightM 'highlight'
  return highlightM
}

method getHighlight Morph {
  for each parts {
    if ((tag each) == 'highlight') {return each}
  }
  return nil
}

method addHighlight Morph {
  highlightWidth = (4 * (global 'scale'))
  if (isNil (getHighlight this)) {
	highlightM = (highlight this highlightWidth)
    addPart this highlightM
    goBackBy highlightM 10000 // behind everything else!
  }
}

method removeHighlight Morph {
  hl = (getHighlight this)
  if (notNil hl) {
    removePart this hl
    return true
  }
  return false
}

// tooltip

method showTooltip Morph aString tipWidth {
  if (or (isNil aString) ('' == aString)) { return nil }
  if (isNil owner) { return nil } // morph deleted before hint was scheduled to appear (e.g. a menu)
  page = (global 'page')
  vis = (visibleBounds this)
  scale = (global 'scale')
  overlap = (scale * 7)
  tip = (newToolTip aString tipWidth)
  rightSpace = ((right (morph page)) - (right vis))
  setTop (morph tip) ((top bounds) - ((height (morph tip)) - overlap))
  if (rightSpace > (width (morph tip))) {
    setLeft (morph tip) (- (right vis) overlap)
  } else {
    setRight (morph tip) (+ (left vis) overlap)
  }
  showTooltip page tip
  reportDamage this (fullBounds (morph tip))
  return tip
}

// talk bubble

method showHint Morph hintData bubbleWidth isHint isError {
  if (isNil isHint) { isHint = true }
  if (or (isNil hintData) ('' == hintData)) {return nil}
  if (isNil owner) {return nil} // morph deleted before hint was scheduled to appear (e.g. a menu)
  page = (page this)
  if (and (isNil page) (isClass (handler owner) 'Hand')) {
	page = (page (handler owner))
  }
  if (isNil page) {return nil} // the morph requesting the hint has been deleted
  vis = (visibleBounds this)
  scale = (global 'scale')
  overlap = (scale * 7)
  bubble = (newBubble hintData bubbleWidth 'right' isError)
  setClientMorph bubble this
  rightSpace = ((right (morph page)) - (right vis))
  setTop (morph bubble) ((top bounds) - ((height (morph bubble)) - overlap))
  if (rightSpace > (width (morph bubble))) {
    setLeft (morph bubble) (- (right vis) overlap)
  } else {
    setField bubble 'direction' 'left'
    fixLayout bubble
    setRight (morph bubble) (+ (left vis) overlap)
  }
  removeHintForMorph page this
  showHint page bubble isHint
  reportDamage this (fullBounds (morph bubble))
  return bubble
}

method showError Morph errorMsg {
  showHint this errorMsg 300 false true
}

method say Morph s {
  sayNothing this
  bubble = (showHint this s 300 false)
  if (isNil bubble) { return } // can happen if morph is in hand
  setClientMorph bubble this
  step bubble
}

method sayNothing Morph {
  pageMorph = (morph (global 'page'))
  for m (copy (parts pageMorph)) {
	h = (handler m)
	if (and (isClass h 'SpeechBubble') ((clientMorph h) == this)) {
	  removePart pageMorph m
	}
  }
}

// deleting

method userDestroy Morph recoverable {
  if (or (isNil handler) (okayToBeDestroyedByUser handler)) {
    destroy this recoverable
    return true
  }
  return false
}

method destroy Morph recoverable {
  if (isNil recoverable) {recoverable = false}
  if (notNil owner) {
	reportDamage owner (fullBounds this)
	removePart owner this
  }
  if (not recoverable) {
    costumeData = nil
    penTrailsData = nil
  }
  while ((count parts) > 0) {destroy (at parts 1)}
  if (notNil handler) {destroyedMorph handler}
  stopTasksFor (global 'page') handler
}

// moving

method moveBy Morph xDelta yDelta {
  if (and (xDelta == 0) (yDelta == 0)) { return }
  fb = (fullBounds this)
  reportDamage this fb
  if (isPenDown this) { movePenBy this xDelta yDelta }
  fastMoveBy this xDelta yDelta
  reportDamage this (translatedBy fb xDelta yDelta)
}

// fast positioning functions -- these do not report damage!

method fastSetPosition Morph x y { fastMoveBy this (x - (left bounds)) (y - (top bounds)) }
method fastSetLeft Morph x { fastMoveBy this (x - (left bounds)) 0 }
method fastSetTop Morph y { fastMoveBy this 0 (y - (top bounds)) }
method fastSetRight Morph x {fastMoveBy this (x - (right bounds)) 0}
method fastSetBottom Morph y {fastMoveBy this 0 (y - (bottom bounds))}
method fastSetXCenter Morph x {fastMoveBy this (x - ((left bounds) + (half (width bounds)))) 0}
method fastSetYCenter Morph y {fastMoveBy this 0 (y - ((top bounds) + (half (height bounds))))}

method fastSetYCenterWithin Morph top bottom {
  ySpan = (bottom - top)
  height = (height bounds)
  if (height > ySpan) {
	fastSetTop this top
  } else {
	fastSetTop this (top + (half (ySpan - height)))
  }
}

method fastMoveBy Morph xDelta yDelta {
  // Internal helper for moveBy. Just moves the morph and all its descendent morphs.
  // Does not report damage or move the pen.

  if (and (xDelta == 0) (yDelta == 0)) { return }
  translateBy bounds xDelta yDelta
  todo = (list)
  addAll todo parts
  while (notEmpty todo) {
	m = (removeFirst todo)
	translateBy (bounds m) xDelta yDelta
	addAll todo (parts m)
  }
}

method movePenBy Morph xDelta yDelta {
  target = (penTarget this)
  if (and (notNil target) (notNil pen)) {
    setCanvas pen (requirePenTrails target)
    rc = (rotationCenter this)
    setX pen (((first rc) - (left target)) / (scaleX target))
    setY pen (((last rc) - (top target)) / (scaleY target))
    goto pen (+ (xDelta / (scaleX target)) (x pen)) (+ (yDelta / (scaleY target)) (y pen))
    if (isVisible target) {changed target}
  }
}

method setPosition Morph x y {moveBy this (x - (left bounds)) (y - (top bounds))}
method setLeft Morph x {moveBy this (x - (left bounds)) 0}
method setRight Morph x {moveBy this (x - (right bounds)) 0}
method setTop Morph y {moveBy this 0 (y - (top bounds))}
method setBottom Morph y {moveBy this 0 (y - (bottom bounds))}
method gotoCenterOf Morph another {setCenter this (hCenter (bounds another)) (vCenter (bounds another))}

method setCenter Morph x y {
  moveBy this (x - ((left bounds) + (half (width bounds)))) (y - ((top bounds) + (half (height bounds))))
}

method setXCenter Morph x {moveBy this (x - ((left bounds) + (half (width bounds)))) 0}
method setYCenter Morph y {moveBy this 0 (y - ((top bounds) + (half (height bounds))))}

method setYCenterWithin Morph top bottom {
  height = (bottom - top)
  setYCenter this (+ top (half height))
  if (height < (height this)) {
    error 'taller than confines'
  }
  if ((bottom this) > bottom) {
    setBottom this bottom
  }
  if ((top this) < top) {
    setTop this top
  }
}

method keepWithin Morph trgRect srcRect {
  // srcRect is optional, if provided it keeps that portion of the
  // receiver morph within the target area
  stayLeftAbove this (right trgRect) (bottom trgRect) srcRect
  stayRightBelow this (left trgRect) (top trgRect) srcRect
}

method stayRightBelow Morph x y srcRect {
  if (isNil srcRect) {srcRect = (fullBounds this)}
  if (isNil x) {x = (left srcRect)}
  if (isNil y) {y = (top srcRect)}
  leftOff = (min 0 ((left srcRect) - x))
  topOff = (min 0 ((top srcRect) - y))
  if (or (leftOff < 0) (topOff < 0)) {
    moveBy this (abs leftOff) (abs topOff)
  }
}

method stayLeftAbove Morph x y srcRect {
  if (isNil srcRect) {srcRect = (fullBounds this)}
  if (isNil x) {x = (right srcRect)}
  if (isNil y) {y = (bottom srcRect)}
  rightOff = (max 0 ((right srcRect) - x))
  bottomOff = (max 0 ((bottom srcRect) - y))
  if (or (rightOff > 0) (bottomOff > 0)) {
    moveBy this (0 - rightOff) (0 - bottomOff)
  }
}

// animation

method animateTo Morph dstX dstY doneAction {
  updatePosition = (action
	(function m srcX srcY dstX dstY ratio {
	  newX = (round (srcX + (ratio * (dstX - srcX))))
	  newY = (round (srcY + (ratio * (dstY - srcY))))
	  reportDamage m (expandBy (fullBounds m) 1) // why is this needed?
	  setPosition m newX newY
	})
	this (left this) (top this) dstX dstY)
  addSchedule (global 'page') (newAnimation 0.0 1.0 400 updatePosition doneAction true)
}

// insetting (relative to owner)

method setInsetInOwner Morph dx dy {
  // Inset my left-top corner by the given amounts relative to my owner.
  if (isNil owner) { return }
  scale = (scale owner)
  newLeft = ((left owner) + (scale * dx))
  newTop = ((top owner) + (scale * dy))
  moveBy this (newLeft - (left bounds)) (newTop - (top bounds))
}

// resizing

method setExtent Morph width height {
  if (isNil width) {width = (max 0 (width bounds))}
  if (isNil height) {height = (max 0 (height bounds))}

  // only redraw if the dimensions have changed
  if (and (width == (width bounds)) (height == (height bounds))) {return}

  changed this
  setWidth bounds width
  setHeight bounds height
  resizePenTrails this
  rerender this
}

// event-induced resizing

method setExtentToRightBottom Morph another {
  changed this
  setRight bounds (right another)
  setBottom bounds (bottom another)
  raise this 'fixLayout' handler
  redraw handler
}

method setWidthToRight Morph another {
  changed this
  setRight bounds (right another)
  if ((width bounds) < minWidth) { setWidth bounds minWidth }
  if ((width bounds) > maxWidth) { setWidth bounds maxWidth }
  raise this 'fixLayout' handler
  redraw handler
}

method setHeightToBottom Morph another {
  changed this
  setBottom bounds (bottom another)
  if ((height bounds) < minHeight) { setHeight bounds minHeight }
  if ((height bounds) > maxHeight) { setHeight bounds maxHeight }
  raise this 'fixLayout' handler
  redraw handler
}

// drawing

method fullDrawOn Morph aContext {
  if (not isVisible) { return }
  if (and (isClass handler 'Block') (true == (getField handler 'layoutNeeded'))) { fixLayout handler }
  if (and isClipping (not (intersectsClip aContext bounds))) { return }

  if shouldRedraw {
	redraw handler
	shouldRedraw = false
  }
  if costumeChanged {
	transformedCostume = nil
	costumeChanged = false
  }

  saveState aContext
  if isClipping { setClip aContext bounds }

  // draw the morph
  if (intersectsClip aContext bounds) {
	if (and (isNil handler) (notNil costumeData)) {
	  // this case (no handler) is used for the hand's shadow
	  if (isClass costumeData 'Bitmap') {
		drawBitmap aContext costumeData (left bounds) (top bounds)
	  } (isClass costumeData 'Color') {
		fillRect aContext costumeData (left bounds) (top bounds) (width bounds) (height bounds)
	  }
	} else {
	  useOldDraw = false
	  if useOldDraw {
		drawCostumeOn this aContext
	  } else {
		drawOn handler aContext
	  }
	}
  }

  // draw its parts
  for each parts { fullDrawOn each aContext }
  restoreState aContext
}

to drawOn aHandler aContext {
  // Backstop for handlers that have not implemented drawOn.

  if (isNil aHandler) { return }
  morph = nil
  if (hasField aHandler 'morph') { morph = (getField aHandler 'morph') }
  if (isNil morph) { // shouldn't happen
	print 'nil morph in drawOn of' (className (class aHandler))
	return
  }
  drawCostumeOn (getField aHandler 'morph') aContext
}

method drawCostumeOn Morph aContext {
  // Draw my costumeData on the given GraphicContext.
  // Called when a handler does not implement drawOn.

  x = (left bounds)
  y = (top bounds)

  if (isClass costumeData 'Color') {
	fillRect aContext costumeData x y (width this) (height this) 1 // blend mode
  } (isClass costumeData 'Bitmap') {
	if (0 == (rotation % 360)) {
	  if (and (scaleX == 1) (scaleY == 1)) { // neither scaled nor rotated
		drawBitmap aContext costumeData x y
	  } else { // scaled, but not rotated
		warpBitmap aContext costumeData x y scaleX scaleX
	  }
	} else { // rotated
	  rotatedBM = (transformedCostume this)
	  if (notNil rotatedBM) { drawBitmap aContext rotatedBM x y }
	}
  }
}

// Old draw method (still used for off-screen rendering right now)

method draw Morph destination xOffset yOffset destScaleX destScaleY clipRect {
  // Still used for off-screen rendering of morphs.

  if (not isVisible) {return}
  if (isNil xOffset) {xOffset = 0}
  if (isNil yOffset) {yOffset = xOffset}
  if (isNil destScaleX) {destScaleX = 1}
  if (isNil destScaleY) {destScaleY = destScaleX}

  if isClipping {
    bnds = (translatedBy bounds xOffset yOffset)
    if (isNil clipRect) {
      clipRect = bnds
    } else {
      clipRect = (intersection bnds clipRect)
    }
  }
  if (notNil clipRect) {
	if (or ((width clipRect) <= 0) ((height clipRect) <= 0)) { return }
  }

  origin = (drawingPoint this)
  x = (((first origin) + xOffset) * destScaleX)
  y = (((last origin) + yOffset) * destScaleY)

  if (isClass costumeData 'Color') {
	r = (rect x y (width bounds) (height bounds))
	if (notNil clipRect) { intersect r clipRect }
	fillRect destination costumeData (left r) (top r) (width r) (height r) 1 // blendMode=blend
  } (isClass costumeData 'Bitmap') {
	if (0 == (rotation % 360)) {
	  if (and (scaleX == 1) (scaleY == 1)) { // neither scaled nor rotated
		drawBitmap destination costumeData x y alpha 1 clipRect
	  } else { // scaled, but not rotated
		centerX = (x + (half (destScaleX * (width bounds))))
		centerY = (y + (half (destScaleY * (height bounds))))
		warpBitmap destination costumeData centerX centerY (scaleX * destScaleX) (scaleY * destScaleY) 0
	  }
	} else { // rotated
	  drawBitmap destination (transformedCostume this) x y alpha 1 clipRect
	}
  }

  if (notNil penTrailsData) {
	drawPenTrailsOn this destination x y destScaleX destScaleY
  }

  for each parts {
    draw each destination xOffset yOffset destScaleX destScaleY clipRect
  }
}

method takeSnapshot Morph {
  // Return a bitmap with a snapshot of the given morph at its normal size.

  return (takeSnapshotWithBounds this (fullBounds this))
}

method takeSnapshotWithBounds Morph rect {
  // Return a bitmap with a snapshot of this morph with the given global rectangle.

  bm = (newBitmap (width rect) (height rect))
  ctx = (newGraphicContextOn bm)
  setOffset ctx (- (left rect)) (- (top rect))
  fullDrawOn this ctx
  return bm
}

method takeThumbnail Morph thumbWidth thumbHeight {
  w = (width this)
  h = (height this)

  bm = (newBitmap thumbWidth thumbHeight)
  fillRect bm (color 240 240 240) 0 0 (width bm) (height bm)

  if (or (height == 0) (width == 0)) {
    return bm
  }

  orig = (takeSnapshot this)
  mag = (min (thumbWidth / w) (thumbHeight / h))
  fitW = ((thumbHeight / h) >= (thumbWidth / w))

  areaFilled = (((w * mag) * (h * mag)) / (thumbWidth * thumbHeight))

  if (areaFilled < 0.2) {
    // too big of a mismatch in aspect ratio
    mag = (max (thumbHeight / h) (thumbWidth / w))
    thumb = (thumbnail orig (w * mag) (h * mag))

    if fitW {
      drawBitmap bm thumb ((thumbWidth - (width thumb)) / 2) 0
    } else {
      drawBitmap bm thumb 0 ((thumbHeight - (height thumb)) / 2)
    }
    return bm
  }

  orig = (takeSnapshot this)
  thumb = (thumbnail orig (w * mag) (h * mag))

  if fitW {
    drawBitmap bm thumb 0 ((thumbHeight - (height thumb)) / 2)
  } else {
    drawBitmap bm thumb ((thumbWidth - (width thumb)) / 2) 0
  }
  return bm
}

// sensing

method isTransparentAt Morph x y {
  // Return true if the given morph is transparent at the given (global) position.
  // Fast in apps but expensive for large blocks in the browser (30-60 msecs).
  // May want to try a different stategy -- draw onto canvas, read back one pixel.

  if (rotation != 0) { return false } // don't deal with rotation for now
  bm = (newBitmap (width bounds) (height bounds))
  ctx = (newGraphicContextOn bm)
  setOffset ctx (0 - (left this)) (0 - (top this))
  drawOn (handler this) ctx

  relX = (round (x - (left bounds)))
  relY = (round (y - (top bounds)))
  if (or (relX < 0) (relX >= (width bm))) { return true }
  if (or (relY < 0) (relY >= (height bm))) { return true }
  return ((getAlpha bm relX relY) < 10)
}

// stepping

method step Morph {
  if (notNil handler) {
    if (isNil fps) {
      leftover = 0
    } (fps <= 0) {
      leftover = 1
    } else {
	  now = (msecsSinceStart)
	  if (now < lastStepTime) { lastStepTime = 0 } // clock wrap
      leftover = ((truncate (1000 / fps)) - (now - lastStepTime))
    }
    if (leftover < 1) {
      lastStepTime = (msecsSinceStart)
      step handler
    }
  }
  for each parts {step each}
}

// change propagation

method changed Morph {
  if (and isVisible (notNil owner)) {
	reportDamage owner bounds
  } (and (isClass handler 'Hand') (notEmpty parts)) {
	reportDamage (morph (global 'page')) (fullBounds this)
  }
}

method reportDamage Morph rect {
  // Pass a damage rectangle up the owner chain and record it in Page/s damage list.
  // Propagation is stopped by an invisble morph (whose subtree is also invisible).
  // The damage rectangle is clipped to the bounds of clipping morphs.

  if (not isVisible) { return }

  if (isClass handler 'Page') {
	addDamage handler rect
  } (isClass handler 'Hand') {
	if (not (isEmpty parts)) { reportDamage (morph (global 'page')) rect }
  } (isClass handler 'Stage') {
	if costumeChanged { return } // stage has already reported damage
	costumeChanged = true // stage uses this flag to indicate that damage has been reported
	reportDamage owner bounds
  } (and isVisible (notNil owner) (owner != this)) {
	if isClipping {
	  if (intersects rect bounds) {
		reportDamage owner (intersection bounds rect)
	  }
	} else {
	  reportDamage owner rect
	}
  }
}

method rerender Morph {
  if shouldRedraw { return } // already reported damage
  changed this
  shouldRedraw = true
}

method raise Morph eventName origin {
  if (notNil owner) {
    if (and (acceptsEvents owner) (implements (handler owner) eventName)) {
      call eventName (handler owner) origin
    } else {
      raise owner eventName origin
    }
  }
}

// pentrails layer

method deletePenTrails Morph { penTrailsData = nil }

method clearPenTrails Morph {
  transparent = (gray 255 0) // transparent white
  if (notNil penTrailsData) { fill penTrailsData transparent }
}

method drawPenTrailsOn Morph destination dstX dstY dstScaleX dstScaleY {
  centerX = (dstX + (half (width this)))
  centerY = (dstY + (half (height this)))
  drawScaleX = (scaleX * dstScaleX)
  drawScaleY = (scaleY * dstScaleY)
  warpBitmap destination penTrailsData centerX centerY drawScaleX drawScaleY
}

method requirePenTrails Morph {
  if (isNil penTrailsData) {
	penTrailsData = (newBitmap (normalWidth this) (normalHeight this))
  }
  return penTrailsData
}

method resizePenTrails Morph {
  if (notNil penTrailsData) {
    bm = (newBitmap (width this) (height this))
    drawBitmap bm penTrailsData
    penTrailsData = bm
  }
}

// pen

method requirePen Morph {
  if (vectorTrails) {
    if (isClass pen 'TurtlePen') {
      return pen
    }
    pen = (newTurtlePen)
  } else {
    if (isClass pen 'Pen') {
      return pen
    }
    pen = (newPen)
  }
  setLineWidth pen (global 'scale')
  return pen
}

method penDown Morph {down (requirePen this)}
method isPenDown Morph {return (and (notNil pen) (isDown pen))}
method penUp Morph {if (notNil pen) {up pen}}
method isPenUp Morph {return (not (isPenDown this))}
method setPenColor Morph aColor {setColor (requirePen this) aColor}
method penColor Morph {return (color (requirePen this))}
method setPenLineWidth Morph aNumber {setLineWidth (requirePen this) aNumber}
method penLineWidth Morph {return (getField (requirePen this) 'size')}
method setDrawOnOwner Morph bool {drawOnOwner = bool}

method penClear Morph {
  target = (penTarget this)
  if (notNil target) {
    deletePenTrails target
    changed target
  }
}

method stampCostume Morph stampTransparency {
  // Paste my costume onto my owner's penTrails layer.
  // Optional stampTransparency has range 0 (opaque) to 100 (fully transparent).

  target = (penTarget this)
  if (isNil target) { return }
  if (isNil stampTransparency) { stampTransparency = 0 }
  stampAlpha = (clamp (toInteger (2.55 * (100 - stampTransparency))) 0 255)
  if (0 == stampAlpha) { return } // completely transparent; no effect
  trails = (requirePenTrails target)
  oldAlpha = alpha
  wasHidden = (isHidden this)
  show this
  alpha = stampAlpha
  draw this trails (- (left target)) (- (top target)) (1 / (scaleX target)) (1 / (scaleY target))
  if wasHidden { hide this }
  alpha = oldAlpha
  changed target
}

method penTarget Morph {
  if (isNil owner) {return nil}
  if (isClass (handler owner) 'Hand') {return nil}
  if drawOnOwner {
	target = owner
  } (isAnyClass (handler owner) 'Page' 'Stage') { // common case optimization
	target = owner
  } else {
	target = (ownerThatIsA this 'Stage')
	if (isNil target) {
	  target = (morph (global 'page'))
	}
  }
  return target
}

// menu

method contextMenu Morph {
  menu = (menu (toString handler) this)
  scale = (global 'scale')
  if (isNil costumeData) {
    thm = (newBitmap (* scale 18) (* scale 18))
  } else {
    thm = (thumbnail costumeData (* scale 18) (* scale 18))
  }
  if (or (devMode) (isClass handler 'Turtle') (notNil (scripts (classOf handler)))) {
    addItem menu 'select' 'openScripter' 'show the scripts for this object'
  }
  if (devMode) {
	addLine menu
	addItem menu 'explore...' 'exploreHandler' 'open an explorer window on this object''s internals'
	addItem menu 'browse class...' 'browseHandler' 'open a browser window on this object''s class'
	addLine menu
  }
  if (notNil penTrailsData) {
	addLine menu
    addItem menu 'clear pen trails' 'deletePenTrails'
  }
  if (isClass handler 'Page') { return menu }

  addItem menu 'come to front' 'comeToFront' 'show this object on top of its siblings'
  addLine menu
  addItem menu 'duplicate' 'duplicateMorph' 'duplicate and grab this object'
  addItem menu 'delete' 'destroy'
  addLine menu
  addItem menu 'scale...' (action 'scalingHandle' handler) 'scale this object'
  addItem menu 'rotate...' (action 'rotationHandle' handler) 'rotate this object'
  addItem menu 'rotation point...' (action 'pinHandle' handler) 'edit the point about which this object rotates'
  if (or (pinX != 0) (pinY != 0)) {
    addItem menu 'set rotation point to center...' (action 'setPin' this 0 0) 'make this object''s rotation point be its center'
  }
  if rotateWithOwner {
    addItem menu 'rotate independently' 'toggleRotationStyle' 'keep current orientation instead of rotating with the owner'
  } else {
    addItem menu 'rotate with owner' 'toggleRotationStyle' 'rotate with owner, as if rigidly attached to it'
  }
  addLine menu
//  addItem menu 'attach...' 'attach' 'stick this object to another object'
  if (not (isTopLevel this)) {
    addItem menu 'slide...' (action 'moveHandle' handler) 'move this object without detaching it'
    addItem menu 'detach' 'userGrab' 'detach and grab this part'
  } else {
    addItem menu 'grab' 'userGrab' 'grab this instance'
  }
  if ((count parts) > 0) {
	addLine menu
	addItem menu 'detach all parts (ungroup)' 'detachAll' 'detach all my parts'
  }
  if ('draggableParts' == grabRule) {
    addItem menu 'do not allow parts to be dragged in and out' (action 'toggleDraggableParts' this)
  } else {
    addItem menu 'allow parts to be dragged in and out' (action 'toggleDraggableParts' this)
  }
  addLine menu
  addPropertyEditingItems this menu
  return menu
}

method exploreHandler Morph {explore (hand (page this)) handler}

method browseHandler Morph {
  page = (page this)
  brs = (newClassBrowser)
  setPosition (morph brs) (x (hand page)) (y (hand page))
  addPart page brs
  browse brs (classOf handler)
}

method openScripter Morph {
  showInScripter (handler this)
}

method grab Morph hand {
  if (isNil handler) {return}
  if (isNil hand) {hand = (hand (global 'page'))}
  setCenter this (x hand) (y hand)
  grab hand handler
}

method userGrab Morph hand {
  setGrabRule this 'handle'
  grab this hand
}

method grabCentered Morph aHandler {
  h = (hand (page this))
  setCenter (morph aHandler) (x h) (y h)
  grab h aHandler
}

method grabTopLeft Morph {
  // Grab this morph near it's top-left corner.

  scale = (global 'scale')
  h = (hand (global 'page'))
  setPosition this ((x h) - (7 * scale)) ((y h) - (7 * scale))
  grab h handler
}

method detachAll Morph {
  newOwner = (self_stageMorph)
  if (isNil newOwner) { return }
  for p parts {
    setGrabRule p 'handle'
    addPart newOwner p
  }
}

method duplicateMorph Morph {
  newMorph = (deepCopy this (array owner))
  grabCentered this (handler newMorph)
}

method attach Morph {
  scale = (global 'scale')
  fb = (fullVisibleBounds this)
  page = (page this)
  targets = (list)
  all = (allMorphs (morph page))
  removeAll all (allMorphs this)
  for each all {
    if (intersects fb (fullVisibleBounds each)) {add targets each}
  }
  menu = (menu (join 'attach ' (toString handler) ' to:') this)
  for each targets {
    if (or (devMode) (not (isAnyClass (handler each) 'Page' 'Stage' 'ProjectEditor'))) {
      if (isNil (costumeData each)) {
        thm = (newBitmap (* scale 18) (* scale 18))
      } else {
        thm = (thumbnail (costumeData each) (* scale 18) (* scale 18))
      }
      addItem menu (join (toString (handler each)) '...') (action 'userAddPart' each) nil thm
    }
  }
  addLine menu
  addItem menu 'cancel' 'nop'
  popUpAtHand menu (page this)
}

method toggleDraggableParts Morph {
  if ('draggableParts' == grabRule) {
    setGrabRule this 'handle'
  } else {
    setGrabRule this 'draggableParts'
  }
}

// property editing

method addPropertyEditingItems Morph menu {
  // Add menu items for interactively changing properties such as transparency, color, or size.
  // Most of these properties are optional and only displayed if the handler implements
  // a setter for that property.

  addItem menu 'set transparency...' (action 'changeTransparency' this)
  if (implements handler 'setColor') {
    addItem menu 'set color...' (action 'changeColor' this)
  }
  if (implements handler 'setWidth') {
    addItem menu 'set width...' (action 'changeWidth' this)
  }
  if (implements handler 'setHeight') {
    addItem menu 'set height...' (action 'changeHeight' this)
  }
  if (implements handler 'setRadius') {
    addItem menu 'set radius...' (action 'changeRadius' this)
  }
  if (implements handler 'setText') {
    addItem menu 'set text...' (action 'changeText' this)
  }
  if (implements handler 'setFontName') {
    addItem menu 'set font name...' (action 'changeFontName' this)
  }
  if (implements handler 'setFontSize') {
    addItem menu 'set font size...' (action 'changeFontSize' this)
  }
}

method changeTransparency Morph {
  promptForNumber 'Transparency?' (action 'setTransparency' this) 0 100 (transparency this)
}

method changeColor Morph {
  if (isClass costumeData 'Color') {
    currentColor = (costumeData morph)
  } (hasField handler 'color') {
    currentColor = (getField handler 'color')
  } else {
    currentColor = (gray 200)
  }
  colorPicker = (newColorPicker (action 'setColor' handler) currentColor)
  addPart (global 'page') (morph colorPicker)
}

method changeWidth Morph {
  current = (normalWidth this)
  promptForNumber 'Width?' (action 'setWidth' handler) 1 1000 current
}

method changeHeight Morph {
  current = (normalHeight this)
  promptForNumber 'Height?' (action 'setHeight' handler) 1 1000 current
}

method changeRadius Morph {
  current = (half (min (normalWidth this) (normalHeight this)))
  promptForNumber 'Radius?' (action 'setRadius' handler) 1 500 current
}

method changeText Morph {
  current = ''
  if (hasField handler 'text') { current = (getField handler 'text') }
  s = (prompt (global 'page') 'Text?' current)
  if ('' == s) { return }
  setText handler s
}

method changeFontName Morph {
  current = ''
  if (hasField handler 'fontName') { current = (getField handler 'fontName') }
  fn = (prompt (global 'page') 'Font Name?' current)
  if ('' == fn) { return }
  setFontName handler fn
}

method changeFontSize Morph {
  current = 18
  if (hasField handler 'fontSize') { current = (getField handler 'fontSize') }
  promptForNumber 'Font Size?' (action 'setFontSize' handler) 1 500 current
}

// serialization

method serializedFieldNames Morph {
  omittedFields = (array 'costume' 'pen' 'penTrails' 'penTrailsData')
  result = (list)
  addAll result (fieldNames (classOf this))
  removeAll result omittedFields
  return (toArray result)
}

method deserialize Morph fieldDict {
  // Initialize this morph from the given dictionary,
  // migrating old fields to new fields as needed.

  for k (fieldNames (classOf this)) {
	setField this k (at fieldDict k)
  }

  if (contains fieldDict 'originalCostume') {
	origCostume = (at fieldDict 'originalCostume')
	if (notNil origCostume) { costumeData = origCostume }
  }

  // Initialize recently added instance variables
  if (isNil drawOnOwner) { drawOnOwner = true }
  if (isNil rotation) {
	rotation = 0
	rotateWithOwner = true
	scaleX = 1
	scaleY = 1
	pinX = 0
	pinY = 0
  }

  // Field rename: identifier -> tag
  if (contains fieldDict 'identifier') {
	tag = (at fieldDict 'identifier')
  }
}

method preSerialize Morph {
  if (hasField handler 'window') {
	w = (getField handler 'window')
	if (isClass w 'Window') { preSerialize w }
  } (implements handler 'redraw') {
	setCostume (morph handler) nil
  }
  costume = nil
  penTrails = nil
  preSerialize handler
  for m parts { preSerialize m }
}

method postSerialize Morph {
  for m parts { postSerialize m }
  postSerialize handler
  doRedraw = false
  if (hasField handler 'window') {
	w = (getField handler 'window')
	if (isClass w 'Window') {
	  doRedraw = true
	  postSerialize w
	}
  }
  if (and (not doRedraw) (isNil costumeData) (implements handler 'redraw')) {
	doRedraw = true
	if (notNil owner) {
	  // Optimization to avoid redundant drawing (and bitmap creation):
	  //   Assume ScrollFrames are inside Windows, so will be redrawn later
	  //   Morphs owned by a ScrollFrame or Slider will be redrawn by their owner

	  if (isClass handler 'ScrollFrame') { doRedraw = false }
	  if (isAnyClass (handler owner) 'ScrollFrame' 'Slider') { doRedraw = false }
	}
  }
  if doRedraw { redraw handler true }
  gcIfNeeded
}
