defineClass ScrollFrame morph contents hSlider vSlider noSliders padding cache cachingEnabled updateCache enableAutoScroll

to area aHandler {return (fullBounds (morph aHandler))}

to scrollFrame contents aColor noSliderFlag {
  return (initialize (new 'ScrollFrame') contents aColor noSliderFlag)
}

method initialize ScrollFrame newContents aColor noSliderFlag {
  sliderTransparency = 180
  if (isNil aColor) { aColor = (gray 200) }
  if (isNil noSliderFlag) { noSliderFlag = false }
  morph = (newMorph this)
  setCostume morph aColor
  contents = newContents
  noSliders = noSliderFlag
  enableAutoScroll = true
  addPart morph (morph contents)
  setTransparentTouch morph true
  setClipping morph true
  hSlider = (slider 'horizontal')
  setAlpha (morph hSlider) sliderTransparency
  addPart morph (morph hSlider)
  vSlider = (slider 'vertical')
  setAlpha (morph vSlider) sliderTransparency
  addPart morph (morph vSlider)
  setAction hSlider (action 'scrollToX' this)
  setAction vSlider (action 'scrollToY' this)
  cache = nil
  cachingEnabled = false
  updateCache = true
  updateSliders this
  return this
}

method contents ScrollFrame {return contents}
method setPadding ScrollFrame intOrNull {padding = intOrNull}
method setAutoScroll ScrollFrame bool {enableAutoScroll = bool}

method setContents ScrollFrame aHandler anInt {
  if (isNil anInt) {anInt = 0}
  padding = anInt
  idx = (indexOf (parts morph) (morph contents))
  setOwner (morph contents) nil
  atPut (parts morph) idx (morph aHandler)
  setOwner (morph aHandler) morph
  contents = aHandler
  setPosition (morph contents) (left morph) (top morph)
  updateCache = true
  updateSliders this
  changed morph
}

method hideSliders ScrollFrame {
  noSliders = true
  hide (morph hSlider)
  hide (morph vSlider)
}

method showSliders ScrollFrame {
  noSliders = false
  updateSliders this
}

method updateSliders ScrollFrame doNotAdjustContents {
  if (true != doNotAdjustContents) { adjustContents this }
  if noSliders {
    hide (morph hSlider)
    hide (morph vSlider)
    return
  }
  hw = (height (morph hSlider))
  vw = (width (morph vSlider))
  b = (bounds morph)
  if (notNil padding) {b = (insetBy b padding)}
  bc = (fullBounds (morph contents))
  if (isClass contents 'TreeBox') {bc = (area contents)}
  w = (width b)
  wc = (width bc)
  h = (height b)
  hc = (height bc)

  if ((+ hc hw) > h) {
    show (morph vSlider)
    fastSetPosition (morph vSlider) ((right b) - vw) (top b)
    setHeight (bounds (morph vSlider)) (- h hw)
    if ((bottom bc) < (- (bottom b) hw)) {setBottom (morph contents) (- (bottom b) hw)}

    shift = ((top b) - (top bc))
    overlap = ((hc + hw) - h)
    if (or (shift == 0) (overlap == 0)) {
      val = 0
    } else {
      ratio = (shift / overlap)
      val = (ratio * (hc + hw))
    }
    update vSlider 0 (+ hc hw) val h

  } else {
    hide (morph vSlider)
    fastSetTop (morph contents) (top b)
  }

  if (or (and (isVisible (morph vSlider)) ((+ wc vw) > w)) (and (not (isVisible (morph vSlider))) (wc > w))) {
    show (morph hSlider)
    fastSetPosition (morph hSlider) (left b) ((bottom b) - hw)
    setWidth (bounds (morph hSlider)) (- w vw)
    if ((right bc) < (- (right b) vw)) {fastSetRight (morph contents) (- (right b) vw)}

    shift = ((left b) - (left bc))
    overlap = ((wc + vw) - w)
    if (or (shift == 0) (overlap == 0)) {
      val = 0
    } else {
      ratio = (shift / overlap)
      val = (ratio * (wc + vw))
    }
    update hSlider 0 (+ wc vw) val w

  } else {
    hide (morph hSlider)
    fastSetLeft (morph contents) (left b)
  }

  if (and (not (isVisible (morph hSlider))) (hc <= h)) {
    hide (morph vSlider)
  } (not (isVisible (morph hSlider))) {
    setExtent (morph vSlider) nil h

    shift = ((top b) - (top bc))
    overlap = (hc - h)
    if (or (shift == 0) (overlap == 0)) {
      val = 0
    } else {
      ratio = (shift / overlap)
      val = (ratio * hc)
    }
    update vSlider 0 hc val h
  }
  changed morph
}

method adjustContents ScrollFrame {
  if (isAnyClass contents 'ListBox' 'TreeBox') {
    h = (height (area contents))
    if (and (isVisible (morph hSlider)) ((+ h (height (morph hSlider))) > (height morph))) {
      setMinWidth contents (- (width morph) (width (morph vSlider)))
    } else {
      setMinWidth contents (width morph)
    }
  } (implements contents 'adjustSizeToScrollFrame') {
    adjustSizeToScrollFrame contents this
  }
  updateCache = true
  changed morph
}

method scrollToX ScrollFrame x {
  w = (width (area contents))
  overlap = (toFloat (-
    (+ w (width (morph vSlider)))
    (width morph)
  ))
  fastSetLeft (morph contents) (-
    (left morph)
    (toInteger (* (/ (toFloat x) (ceiling hSlider)) overlap))
  )
  changed morph
}

method scrollToY ScrollFrame y {
  h = (height (area contents))
  if (not (isVisible (morph hSlider))) {
      overlap = (toFloat (- h (height morph)))
  } else {
      overlap = (toFloat (-
        (+ h (height (morph hSlider)))
        (height morph)
      ))
  }
  fastSetTop (morph contents) (-
    (top morph)
    (toInteger (* (/ (toFloat y) (ceiling vSlider)) overlap))
  )
  changed morph
}

method scrollIntoView ScrollFrame aRect favorTopLeft {
  ca = (clientArea this)
  trgt = aRect
  if (true == favorTopLeft) {
    trgt = (copy aRect)
    setWidth trgt (min (width trgt) (width ca))
    setHeight trgt (min (height trgt) (height ca))
  }
  currentlyClipping = (isClipping morph)
  setClipping morph false
  if (isClass contents 'Text') {
    keepWithin (morph contents) (insetBy ca (borderX contents) (borderY contents)) trgt
  } else {
    keepWithin (morph contents) ca trgt
  }
  updateSliders this
  setClipping morph currentlyClipping
}

method clientArea ScrollFrame {
  sw = (getField hSlider 'thickness')
  b = (bounds morph)
  if (isVisible (morph hSlider)) {
    return (rect (left b) (top b) ((width b) - sw) ((height b) - sw))
  }
  return (rect (left b) (top b) ((width b) - sw) (height b))
}

// events

method clicked ScrollFrame hand {
  if (and (isClass contents 'Text') ((editRule contents) != 'static')) {
    edit (keyboard (page hand)) contents
    selectAll contents
  }
  return false
}

method rightClicked ScrollFrame {
  raise morph 'handleContextRequest' this
  return true
}

// Scrolling with scrollwheel and keys

method swipe ScrollFrame x y {
  changeScrollOffset this (0 - x) (0 - y)
  return true
}

method scrollEnd ScrollFrame { changeScrollOffset this 0 1000000 }
method scrollHome ScrollFrame { changeScrollOffset this 0 -1000000 }

method arrowKey ScrollFrame dx dy {
  stepSize = (-40 * (global 'scale'))
  changeScrollOffset this (dx * stepSize) (dy * stepSize)
}

method scrollPage ScrollFrame dir {
  stepSize = (half (height morph))
  changeScrollOffset this 0 (dir * stepSize)
}

method changeScrollOffset ScrollFrame dx dy {
  contentsM = (morph contents)

  maxXOffset = (max 0 ((width contentsM) - (width morph)))
  maxYOffset = (max 0 ((height contentsM) - (height morph)))

  if (isVisible (morph vSlider)) { maxXOffset += (width (morph vSlider)) }
  if (isVisible (morph hSlider)) { maxYOffset += (height (morph hSlider)) }

  xOffset = (((left morph) - (left contentsM)) + dx)
  yOffset = (((top morph) - (top contentsM)) + dy)

  xOffset = (round (clamp xOffset 0 maxXOffset))
  yOffset = (round (clamp yOffset 0 maxYOffset))

  fastSetPosition contentsM ((left morph) - xOffset) ((top morph) - yOffset)
  updateSliders this true
}

// auto-scrolling

method step ScrollFrame {
  hand = (hand (global 'page'))
  dragged = (grabbedObject hand)
  if (and
      enableAutoScroll
      (notNil dragged)
      (containsPoint (bounds morph) (x hand) (y hand))
      (wantsDropOf (contents this) dragged)
  ) {
    autoScroll this hand dragged
  }
}

method autoScroll ScrollFrame hand obj {
return // xxx needs work to limit scrolling
  thres = (50 * (global 'scale'))
  jump = (5 * (global 'scale'))
  fb = (fullBounds (morph obj))
  contentsM = (morph contents)
  offsetX = (left contentsM)
  offsetY = (top contentsM)
  if (((x hand) - (left morph)) < thres) {
    if ((left fb) < (left morph)) {
      offsetX += jump
    }
  } (((right morph) - (x hand)) < thres) {
    if ((right fb) > (right morph)) {
      offsetX += (0 - jump)
    }
  }
  if (((y hand) - (top morph)) < thres) {
    if ((top fb) < (top morph)) {
      offsetY += (0 - jump)
    }
  } (((bottom morph) - (y hand)) < thres) {
    if ((bottom fb) > (bottom morph)) {
      offsetY += (0 - jump)
    }
  }
  if (or (offsetX != (left contentsM)) (offsetY != (left contentsM))) {
    fastSetPosition (morph contents) offsetX offsetY
    updateSliders this true
  }
}

method drawOn ScrollFrame ctx {
  bm = (cachedContents this)
  if (notNil bm) {
    x = (left (morph contents))
    y = (top (morph contents))
	drawBitmap ctx bm x y
	fullDrawOn (morph hSlider) ctx
	fullDrawOn (morph vSlider) ctx
  } else {
	drawCostumeOn morph ctx
  }
}

// caching support to improve redrawing speed

method cachingEnabled ScrollFrame { return cachingEnabled}
method setCachingEnabled ScrollFrame bool { cachingEnabled = bool }

method scriptChanged ScrollFrame { updateCache = true }
method functionBodyChanged ScrollFrame { saveNeeded = true }

// method changed ScrollFrame {
// print 'changed ScrollFrame'
//   updateCache = true // update the cache on next display
//   changed morph
// }

method cachedContents ScrollFrame {
  // Return a Bitmap containing my contents if caching is enabled, or nil if not.

  if (not cachingEnabled) { return nil }
  if updateCache {
print 'updating cache'
	contentsW = (normalWidth (morph contents))
	contentsH = (normalHeight (morph contents))
	if (or (isNil cache) ((width cache) != contentsW) ((height cache) != contentsH)) {
	  cache = (newBitmap contentsW contentsH)
	}
	if (isClass (costumeData morph) 'Color') {
	  fill cache (costumeData morph)
	} else {
	  fill cache (transparent)
	  if (isClass (costumeData morph) 'Bitmap') {
		drawBitmap cache (costumeData morph)
	  }
	}

	// draw contents onto cache
	ctx = (newGraphicContextOn cache)
	setOffset ctx (- (left (morph contents))) (- (top (morph contents)))
	fullDrawOn (morph contents) ctx

	updateCache = false
  }
  return cache
}
