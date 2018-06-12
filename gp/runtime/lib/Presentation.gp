// present an editable text box in a morphic window, adjust the text size to always fill it entirely

defineClass Presentation morph window text

method initialize Presentation contents {
  scale = (global 'scale')
  if (not (isClass contents 'String')) {contents = ''}
  window = (window 'Notes')
  morph = (morph window)
  border = (border window)

  text = (newText contents)
  setEditRule text 'editable'
  setGrabRule (morph text) 'ignore'
  setBorders text border border true
  align text 'center'
  addPart morph (morph text)

  setExtent morph (scale * 230) (scale * 200)
  setHandler morph this
  setMinExtent morph (scale * 120) (scale * 80)
  redraw this
}

method fixLayout Presentation {
  fixLayout window
  clientArea = (clientArea window)
  size = (fontSize text)
  border = (size / 5)
  extent = (extent text size border border)
  xDelta = ((width clientArea) - (width extent))
  yDelta = ((height clientArea) - (height extent))

  if (xDelta < 0) {
    ratio = (/ (toFloat (width clientArea)) (width extent))
    size = (truncate (* ratio size))
    border = (truncate (size / 5))
    extent = (extent text size border border)
    xDelta = ((width clientArea) - (width extent))
    yDelta = ((height clientArea) - (height extent))

    if (yDelta < 0) {
      ratio = (/ (toFloat (height clientArea)) (height extent))
      size = (truncate (* ratio size))
      border = (truncate (size / 5))
      extent = (extent text size border border)
      xDelta = ((width clientArea) - (width extent))
      yDelta = ((height clientArea) - (height extent))
    }

  } else {
    ratio = (/ (toFloat (width clientArea)) (width extent))
    size = (truncate (* ratio size))
    border = (truncate (size / 5))
    extent = (extent text size border border)
    xDelta = ((width clientArea) - (width extent))
    yDelta = ((height clientArea) - (height extent))

    if (yDelta < 0) {
      ratio = (/ (toFloat (height clientArea)) (height extent))
      size = (truncate (* ratio size))
      border = (truncate (size / 5))
      extent = (extent text size border border)
      xDelta = ((width clientArea) - (width extent))
      yDelta = ((height clientArea) - (height extent))
    }
  }

  while (or (> (width (extent text size border)) (width clientArea)) (> (height (extent text size border)) (height clientArea))) {
    size += -1
    border = (truncate (size / 5))
  }

  setBorders text border border
  setFont text nil size
  setCenter (morph text) (hCenter clientArea) (vCenter clientArea)
}

method updateScale Presentation {
  // Used to redraw window and contents when scale changes.
  updateScale window
  redraw this
}

method redraw Presentation {
  fixLayout window
  redraw window
  clientArea = (translatedBy (clientArea window) (0 - (left morph)) (0 - (top morph)))
  fillRect (costumeData morph) (clientColor window) (left clientArea) (top clientArea) (width clientArea) (height clientArea)
  updateCostume morph
  fixLayout this
}

method clicked Presentation hand {
  edit (keyboard (page hand)) text (slotAt text (left (morph text)) (top (morph text)))
  return false
}

method textEdited Presentation aText {fixLayout this}

to openPresentation page contents {
  ws = (new 'Presentation')
  initialize ws contents
  setPosition (morph ws) (x (hand page)) (y (hand page))
  addPart page ws
}

// serialization

method preSerialize Presentation {
  setCostume morph nil
}
