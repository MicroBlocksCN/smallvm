// PanePacker - handles layout of multi-pane windows

defineClass PanePacker rect border allPanes

to newPanePacker rect innerBorder outerBorder {
  if (isNil innerBorder) { innerBorder = 2 }
  if (isNil outerBorder) { outerBorder = 0 }
  scale = (global 'scale')
  result = (new 'PanePacker')
  setField result 'rect' (insetBy rect (outerBorder * scale))
  setField result 'border' (innerBorder * scale)
  setField result 'allPanes' (dictionary)
  return result
}

// Pane layout

method packPanesH PanePacker panesAndWidthSpecs... {
  scale = (global 'scale')
  panes = (list)
  widths = (list)
  spaceAvailable = (width rect)
  for i (range 2 (argCount) 2) {
    add panes (arg i)
    w = (arg (i + 1)) // a number for fixed space, "NN%" for percent, 'rest' for what's left, 'done' or an Action
    if (isNumber w) {
      w = (scale * (max 0 (toInteger w)))
      spaceAvailable = (spaceAvailable - w)
    }
    add widths w
  }

  spaceAvailable += (- (border * ((count panes) - 1)))
  x = (left rect)
  for i (count panes) {
    w = (at widths i)
    if (isClass w 'String') {
      if (w == 'rest') {
        w = ((right rect) - x)
      } (w == 'done') {
        noop // ignore
      } else {
        w = (percentOfSpace this w spaceAvailable)
      }
    } (isClass w 'Action') {
      w = (call w spaceAvailable)
    }
    pane = (at panes i)
    paneMorph = (morph pane)
    if (w == 'done') {
      x += (border + (width paneMorph))
    } else {
	  w = (max w 0)
      setLeft paneMorph x
      setWidth (bounds paneMorph) w
      if (isClass pane 'Text') { setMinWidth pane w }
      x += (w + border)
    }
  }
  addAll allPanes panes
}

method packPanesV PanePacker panesAndHeightSpecs... {
  scale = (global 'scale')
  panes = (list)
  heights = (list)
  spaceAvailable = (height rect)
  for i (range 2 (argCount) 2) {
    add panes (arg i)
    h = (arg (i + 1)) // // a number for fixed space, "NN%" for percent, 'rest' for what's left, 'done' or an Action
    if (isNumber h) {
      h = (scale * (max 0 (toInteger h)))
      spaceAvailable = (spaceAvailable - h)
    }
    add heights h
  }

  spaceAvailable += (- (border * ((count panes) - 1)))
  y = (top rect)
  for i (count panes) {
    h = (at heights i)
    if (isClass h 'String') {
      if (h == 'rest') {
        h = ((bottom rect) - y)
      } (h == 'done') {
        noop // ignore
      } else {
        h = (percentOfSpace this h spaceAvailable)
      }
    } (isClass h 'Action') {
      h = (call h spaceAvailable)
    }
    pane = (at panes i)
    paneMorph = (morph pane)
    if (h == 'done') {
      y += (border + (height paneMorph))
    } else {
	  h = (max h 0)
      setTop paneMorph y
      setHeight (bounds paneMorph) h
      if (isClass pane 'Text') { setMinHeight pane h }
      y += (h + border)
    }
  }
  addAll allPanes panes
}

method percentOfSpace PanePacker percent total {
  letters = (letters percent)
  if ((last letters) != '%') { error 'Size string should be a percentage such as "50%"' }
  s = (joinStringArray (copyArray letters ((count letters) - 1)))
  return (truncate (((toInteger s) * total) / 100))
}

method finishPacking PanePacker {
  for pane (keys allPanes) {
	bnds = (bounds (morph pane))
	setExtent (morph pane) (width bnds) (height bnds)
  }
}
