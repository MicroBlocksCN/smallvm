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
  cachingEnabled = true
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
  updateSliders this
}

method redraw ScrollFrame {
  changed this
  updateSliders this
}

method updateSliders ScrollFrame {
  adjustContents this
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
    setPosition (morph vSlider) ((right b) - vw) (top b)
    setHeight (bounds (morph vSlider)) (- h hw)
    redraw vSlider
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
    setTop (morph contents) (top b)
  }

  if (or (and (isVisible (morph vSlider)) ((+ wc vw) > w)) (and (not (isVisible (morph vSlider))) (wc > w))) {
    show (morph hSlider)
    setPosition (morph hSlider) (left b) ((bottom b) - hw)
    setWidth (bounds (morph hSlider)) (- w vw)
    redraw hSlider
    if ((right bc) < (- (right b) vw)) {setRight (morph contents) (- (right b) vw)}

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
    setLeft (morph contents) (left b)
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
}

method adjustContents ScrollFrame {
  if (isAnyClass contents 'ListBox' 'TreeBox') {
    h = (height (area contents))
    if ((+ h (height (morph hSlider))) > (height morph)) {
      setMinWidth contents (- (width morph) (width (morph vSlider)))
    } else {
      setMinWidth contents (width morph)
    }
  } (implements contents 'adjustSizeToScrollFrame') {
    adjustSizeToScrollFrame contents this
  }
  changed this
}

method scrollToX ScrollFrame x {
  w = (width (area contents))
  overlap = (toFloat (-
    (+ w (width (morph vSlider)))
    (width morph)
  ))
  setLeft (morph contents) (-
    (left morph)
    (toInteger (* (/ (toFloat x) (ceiling hSlider)) overlap))
  )
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
  setTop (morph contents) (-
    (top morph)
    (toInteger (* (/ (toFloat y) (ceiling vSlider)) overlap))
  )
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

method swipe ScrollFrame x y {
  factor = (4.0 * (global 'scale'))
  if (isVisible (morph hSlider)) {
    moveBy (morph (grip hSlider)) ((0 - x) * factor) 0
    trigger (grip hSlider)
  }
  if (isVisible (morph vSlider)) {
    moveBy (morph (grip vSlider)) 0 ((0 - y) * factor)
    trigger (grip vSlider)
  }
  return true
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
  thres = (50 * (global 'scale'))
  jump = (5 * (global 'scale'))
  fb = (fullBounds (morph obj))
  if (((x hand) - (left morph)) < thres) {
    if ((left fb) < (left morph)) {
      moveBy (morph (grip hSlider)) (0 - jump) 0
      trigger (grip hSlider)
    }
  } (((right morph) - (x hand)) < thres) {
    if ((right fb) > (right morph)) {
      moveBy (morph (grip hSlider)) jump 0
      trigger (grip hSlider)
    }
  }
  if (((y hand) - (top morph)) < thres) {
    if ((top fb) < (top morph)) {
      moveBy (morph (grip vSlider)) 0 (0 - jump)
      trigger (grip vSlider)
    }
  } (((bottom morph) - (y hand)) < thres) {
    if ((bottom fb) > (bottom morph)) {
      moveBy (morph (grip vSlider)) 0 jump
      trigger (grip vSlider)
    }
  }
}

// caching support to improve redrawing speed

method setCachingEnabled ScrollFrame bool { cachingEnabled = bool }

method changed ScrollFrame {
  if cachingEnabled { updateCache = true } // update the cache on next display
}

method cachedContents ScrollFrame {
  // Return a Texture containing my contents if caching is enabled, or nil if not.

  if (not cachingEnabled) { return nil }
  if updateCache {
	if (or (isNil cache)
			((width cache) != (normalWidth morph))
			((height cache) != (normalHeight morph))) {
	  if (notNil cache) { destroyTexture cache }
	  cache = (newTexture (normalWidth morph) (normalHeight morph))
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
	xOffset = (- (left morph))
	yOffset = (- (top morph))
	clipRect = (rect 0 0 (width cache) (height cache))
	for m (parts morph) {
	  draw2 m cache xOffset yOffset clipRect
	}
	updateCache = false
  }
  return cache
}
