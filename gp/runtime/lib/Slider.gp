defineClass Slider morph orientation action floor ceiling value size thickness color scale

to slider orientation span action thickness floor ceiling value size color {
  scale = (global 'scale')
  if (isNil span) {span = 0}
  if (isNil action) {action = 'nop'}
  if (isNil thickness) {thickness = (scale * 10)}
  if (isNil floor) {floor = 0}
  if (isNil ceiling) {ceiling = 100}
  if (isNil value) {value = 50}
  if (isNil size) {size = 10}
  if (isNil color) {color = (color 240 240 240)}
  sl = (new 'Slider' nil orientation action floor ceiling value size thickness color)
  initialize sl span
  return sl
}

method initialize Slider span {
  if (orientation == 'horizontal') {
    w = span
    h = thickness
  } else {
    w = thickness
    h = span
  }
  morph = (newMorph this)
  sb = (sliderButton this)
  addPart morph (morph sb)
  setAlpha (morph sb) 145
  setWidth (bounds morph) w
  setHeight (bounds morph) h
  redraw this
  updateGripFromValue this
  trigger this
}

method sliderButton Slider {
  bt = (new 'Trigger' nil (action 'updateValueFromGrip' this))
  m = (newMorph)
  setGrabRule m 'ignore'
  setMorph bt m
  tg = (new 'Grip' m bt orientation 0 morph)
  setHandler m tg
  setRenderer bt this
  return tg
}

method orientation Slider {return orientation}
method value Slider {return value}
method floor Slider {return floor}
method ceiling Slider {return ceiling}
method size Slider {return size}
method grip Slider {return (handler (at (parts morph) 1))}
method unit Slider {return (/ (toFloat ((span this) - (stretch this))) (valueRange this))}
method stretch Slider {return (max thickness (toInteger ((/ (toFloat (span this)) (valueRange this)) * (toFloat size))))}

method valueRange Slider {
  // Return the value range of this slider or 1 if floor == ceiling (to avoid divide by zero).
  if (floor == ceiling) { return 1 }
  return (- ceiling floor)
}

method span Slider {
  if (orientation == 'horizontal') {return (width morph)}
  return (height morph)
}

method update Slider floorNum ceilNum valNum sizeNum {
  if (isNil floorNum) {floorNum = floor}
  if (isNil ceilNum) {ceilNum = ceiling}
  if (isNil valNum) {valNum = value}
  if (isNil sizeNum) {sizeNum = size}
  floor = floorNum
  ceiling = ceilNum
  value = valNum
  size = sizeNum
  updateGripFromValue this
}

method setFloor Slider num {update this num}
method setCeiling Slider num {update this nil num}
method setValue Slider num {update this nil nil num}
method setSize Slider num {update this nil nil nil num}
method setAction Slider anAction {action = anAction}

method setColor Slider aColor {
  color = aColor
  redraw this
}

method trigger Slider {
  if (isClass action 'Array') {
    for each action {call each value}
  } else {
    call action value
  }
}

method redraw Slider {
  // adjust to a change of bounds
  scale = (global 'scale')
  w = (width morph)
  h = (height morph)
  nbm = (buttonBitmap nil color w h true (thickness / 3) (max 1 (scale / 2)))
  setCostume morph nbm
}

method updateGripFromValue Slider {
  grip = (grip this)
  pos = (toInteger ((unit this) * (toFloat (value - floor))))
  if (orientation == 'horizontal') {
    setExtent (morph grip) (stretch this) thickness
    setPosition (morph grip) (+ (left morph) pos) (top morph)
  } else {
    setExtent (morph grip) thickness (stretch this)
    setPosition (morph grip) (left morph) (+ (top morph) pos)
  }
  keepWithin (morph grip) (bounds morph)
}

method updateValueFromGrip Slider {
  grip = (grip this)
  if (orientation == 'horizontal') {
    dist = ((left (morph grip)) - (left morph))
  } else {
    dist = ((top (morph grip)) - (top morph))
  }
  value = (floor + (toInteger ((toFloat dist) / (unit this))))
  trigger this
}

method handDownOn Slider aHand {
  setCenter (morph (grip this)) (x aHand) (y aHand)
  keepWithin (morph (grip this)) (bounds morph)
  updateValueFromGrip this
  return (handDownOn (grip this) aHand)
}

method normalCostume Slider {
  grip = (grip this)
  w = (width (morph grip))
  h = (height (morph grip))
  return (buttonBitmap nil (darker color 40) w h false (thickness / 3) (max 1 (scale / 2)))
}

method highlightCostume Slider {
  grip = (grip this)
  w = (width (morph grip))
  h = (height (morph grip))
  return (buttonBitmap nil (darker color 50) w h false (thickness / 3) (max 1 (scale / 2)))
}

method pressedCostume Slider {return (highlightCostume this)}
