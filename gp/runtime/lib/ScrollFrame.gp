defineClass ScrollFrame morph contents hSlider vSlider noSliders enableAutoScroll verticalScrollOnly dragOriginX dragOriginY baseX baseY

to area aHandler {return (fullBounds (morph aHandler))}

to scrollFrame contents aColor noSliderFlag thickness padding {
  return (initialize (new 'ScrollFrame') contents aColor noSliderFlag thickness padding)
}

method initialize ScrollFrame newContents aColor noSliderFlag thickness padding {
  sliderTransparency = 180
  if (isNil aColor) { aColor = (gray 200) }
  if (isNil noSliderFlag) { noSliderFlag = false }
  morph = (newMorph this)
  setCostume morph aColor
  contents = newContents
  noSliders = noSliderFlag
  enableAutoScroll = true
  verticalScrollOnly = false
  addPart morph (morph contents)
  setTransparentTouch morph true
  setClipping morph true
  hSlider = (slider 'horizontal' nil nil thickness nil nil nil nil padding)
  setAlpha (morph hSlider) sliderTransparency
  addPart morph (morph hSlider)
  vSlider = (slider 'vertical' nil nil thickness nil nil nil nil padding)
  setAlpha (morph vSlider) sliderTransparency
  addPart morph (morph vSlider)
  setAction hSlider (action 'scrollToX' this)
  setAction vSlider (action 'scrollToY' this)
  updateSliders this
  return this
}

method contents ScrollFrame {return contents}
method setAutoScroll ScrollFrame bool {enableAutoScroll = bool}
method setVerticalScrollOnly ScrollFrame bool {verticalScrollOnly = bool}

method setColor ScrollFrame aColor {
  setCostume morph aColor
}

method setSliderColors ScrollFrame bgColor fgColor {
  if (notNil hSlider) { setColors hSlider bgColor fgColor }
  if (notNil vSlider) { setColors vSlider bgColor fgColor }
}

method setContents ScrollFrame aHandler {
  idx = (indexOf (parts morph) (morph contents))
  setOwner (morph contents) nil
  atPut (parts morph) idx (morph aHandler)
  setOwner (morph aHandler) morph
  contents = aHandler
  setPosition (morph contents) (left morph) (top morph)
  updateSliders this
  changed morph
}

method drawOn ScrollFrame ctx {
  // Fill bounds with my color.
  drawCostumeOn morph ctx
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

  if (and (not verticalScrollOnly) (or (and (isVisible (morph vSlider)) ((+ wc vw) > w)) (and (not (isVisible (morph vSlider))) (wc > w)))) {
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

method updateSliderPositions ScrollFrame {
  if (not (or (isVisible (morph vSlider)) (isVisible (morph hSlider)))) {
	return // neither slider is visible
  }

  frameBnds = (bounds morph)
  contentBnds = (fullBounds (morph contents))
  if (isClass contents 'TreeBox') { contentBnds = (area contents) }

  if (isVisible (morph vSlider)) {
    shift = ((top frameBnds) - (top contentBnds))
    overlap = ((height contentBnds) - (height frameBnds))
    if (or (shift == 0) (overlap == 0)) {
      val = 0
    } else {
      ratio = (shift / overlap)
      val = (ratio * (height contentBnds))
    }
    update vSlider 0 (height contentBnds) val (height frameBnds)
  }

  if (isVisible (morph hSlider)) {
	totalW = ((width contentBnds) + (width (morph vSlider)))
    shift = ((left frameBnds) - (left contentBnds))
    overlap = (totalW - (width frameBnds))
    if (or (shift == 0) (overlap == 0)) {
      val = 0
    } else {
      ratio = (shift / overlap)
      val = (ratio * totalW)
    }
    update hSlider 0 totalW val (width frameBnds)
  }
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
  changed morph
}

method scrollToX ScrollFrame x {
  if verticalScrollOnly { return }
  if (0 == (ceiling hSlider)) {
    // special case when empty
    fastSetLeft (morph contents) (left morph)
    return
  }

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
  if (0 == (ceiling vSlider)) {
    // special case when empty
    fastSetTop (morph contents) (top morph)
    return
  }

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
	if (or
		(isClass contents 'TreeBox')
		(isClass contents 'ListBox')
	) {
		arrowKey contents dx dy this
		return
	}
	stepSize = (-50 * (global 'scale'))
	changeScrollOffset this (dx * stepSize) (dy * stepSize)
}

method scrollPage ScrollFrame dir {
  stepSize = ((height morph) / 3)
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

  if verticalScrollOnly { xOffset = 0 }

  fastSetPosition contentsM ((left morph) - xOffset) ((top morph) - yOffset)
  changed morph
  updateSliderPositions this
}

method setScrollOffset ScrollFrame newX newY {
  contentsM = (morph contents)

  maxXOffset = (max 0 ((width contentsM) - (width morph)))
  maxYOffset = (max 0 ((height contentsM) - (height morph)))

  if (isVisible (morph vSlider)) { maxXOffset += (width (morph vSlider)) }
  if (isVisible (morph hSlider)) { maxYOffset += (height (morph hSlider)) }

  xOffset = (round (clamp newX 0 maxXOffset))
  yOffset = (round (clamp newY 0 maxYOffset))


  fastSetPosition contentsM ((left morph) - xOffset) ((top morph) - yOffset)
  changed morph
  updateSliderPositions this
}

// dragging with mouse

method startDragScroll ScrollFrame aHand {
  contentsM = (morph contents)
  baseX = ((left morph) - (left contentsM))
  baseY = ((top morph) - (top contentsM))
  dragOriginX = (x aHand)
  dragOriginY = (y aHand)
  focusOn aHand this
}

method handMoveFocus ScrollFrame aHand {
  dx = ((x aHand) - dragOriginX)
  dy = ((y aHand) - dragOriginY)
  setScrollOffset this (baseX - dx) (baseY - dy)
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
  thres = (80 * (global 'scale'))
  jump = (15 * (global 'scale'))
  dx = 0
  dy = 0

  if (((x hand) - (left morph)) < thres) { dx = jump }
  if (((right morph) - (x hand)) < thres) { dx = (0 - jump) }
  if (((y hand) - (top morph)) < thres) { dy = jump }
  if (((bottom morph) - (y hand)) < thres) { dy = (0 - jump) }

  if (or (dx != 0) (dy != 0)) {
    extra = (10 * (global 'scale'))
    contentBounds = (bounds (morph contents))
    frameBounds = (bounds morph)
    minX = ((right frameBounds) - ((width contentBounds) + extra))
    minY = ((bottom frameBounds) - ((height contentBounds) + extra))
    newX = (clamp ((left contentBounds) + dx) minX (left frameBounds))
    newY = (clamp ((top contentBounds) + dy) minY (top frameBounds))

	if verticalScrollOnly { newX = (left contentBounds) }
    fastSetPosition (morph contents) newX newY
    changed morph
    updateSliders this true
  }
}
