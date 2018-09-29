// morphic tree node handlers, used for hierarchical tree list items

// example:
// addPart (global 'page') (treeBox nil (array 'foo' 'bar' 'baz' (array 'quux' 'frob' (array 'fred' 'brum')) 'garply' (array 'bla' 'blubb' 'brabbel') 'spam'))

defineClass TreeBox morph toggle level isCollapsed getEntry getBranches data onSelect onDoubleClick getHint selection omitRoot bgColor highlighted

to treeBox trunk data getEntryAction getBranchesAction onSelect bgColor onDoubleClick getHint omitRoot {
  if (isNil getEntryAction) {getEntryAction = 'toString'}
  if (isNil getBranchesAction) {getBranchesAction = 'id'}
  if (isNil onSelect) {onSelect = 'nop'}
  if (isNil bgColor) {bgColor = (color 255 255 255)}
  if (isNil omitRoot) {omitRoot = false}

  tn = (new 'TreeBox')
  setField tn 'getEntry' getEntryAction
  setField tn 'getBranches' getBranchesAction
  setField tn 'isCollapsed' true
  setField tn 'data' data
  setField tn 'bgColor' bgColor
  setField tn 'onSelect' onSelect
  setField tn 'getHint' getHint
  setField tn 'onDoubleClick' onDoubleClick

  if (isNil trunk) {
    if omitRoot {
      setField tn 'level' 0
    } else {
      setField tn 'level' 1
    }
  } else {
    setField tn 'level' (+ 1 (level trunk))
  }
  initialize tn omitRoot
  return tn
}

method initialize TreeBox hideRoot {
  omitRoot = hideRoot
  tr = (new 'Trigger' nil (action 'select' this))
  if (notNil getHint) {setHint tr (call getHint data)}
  if (notNil onDoubleClick) {onDoubleClick tr (action onDoubleClick data)}
  setRenderer tr this
  morph = (newMorph this)
  setTransparentTouch morph true
  setMorph tr morph
  toggle = (new 'Toggle' morph tr (action 'isSelected' this) 'handEnter')
  addPart morph (morph (arrowToggle this))
  if omitRoot {
    createBranches this
  } else {
    setCostume morph (normalCostume this)
    refresh toggle
  }
  fixLayout this
}

method select TreeBox silently {
  if (isNil silently) {silently = false}
  r = (root this)
  setField r 'selection' this
  if (not silently) {
    call onSelect data
    for each (allMorphs (morph r)) {
      if (isClass (handler each) (className (classOf this))) {
        refresh (handler each)
      }
    }
  }
}

method unselect TreeBox {
  if (isSelected this) {
    setField (root this) 'selection' nil
    refresh this
  }
  for each (parts morph) {
    if (isClass (handler each) (className (classOf this))) {
      unselect (handler each)
    }
  }
}

method isSelected TreeBox {
  return (=== this (getField (root this) 'selection'))
}

method handDownOn TreeBox aHand {return (handDownOn toggle aHand)}

method handEnter TreeBox aHand {
  if (containsPoint (bounds morph) (x aHand) (y aHand)) {
    handEnter toggle aHand
  }
}

method isSelectable TreeBox aHand {
  if (containsPoint (bounds morph) (x aHand) (y aHand)) {
    return true
  }
  return false
}

method handLeave TreeBox aHand {handLeave toggle aHand}
method clicked TreeBox aHand {return (clicked toggle aHand)}
method doubleClicked TreeBox {return (doubleClicked toggle)}
method setHint TreeBox aStringOrNil {setHint toggle aStringOrNil}
method rightClicked TreeBox {return (rightClicked toggle)}
method level TreeBox {return level}
method isCollapsed TreeBox {return isCollapsed}
method data TreeBox {return data}
method toggle TreeBox {return toggle}
method selection TreeBox {return selection}

method refresh TreeBox {
  clr = (gray 128)
  wht = bgColor
  arrow = (handler (first (parts morph)))
  refresh toggle
  if (isSelected this) {
    replaceCostumes arrow (arrowCostume this 'down' wht) (arrowCostume this 'right' wht)
  } else {
    replaceCostumes arrow (arrowCostume this 'down' clr) (arrowCostume this 'right' clr)
  }
  refresh arrow
}

method area TreeBox {
  if omitRoot {
    ans = (rect (left morph) (top morph) 0 0)
    for i ((count (parts morph)) - 1) {
      each = (at (parts morph) (i + 1))
      merge ans (fullBounds each)
    }
    return ans
  }
  return (fullBounds morph)
}

method indent TreeBox {
  scale = (global 'scale')
  fontSize = (12 * scale)
  fontName = 'Arial'
  setFont fontName fontSize
  return (+ (scale * 2) (fontHeight))
}

method root TreeBox {
  if (isNil (owner morph)) {return this}
  parent = (handler (owner morph))
  if (isClass parent (className (classOf this))) {
    return (root parent)
  }
  return this
}

method isRoot TreeBox {
  if (isNil (owner morph)) {return true}
  return (not (isClass (handler (owner morph)) (className (classOf this))))
}

method hasBranches TreeBox {
  branches = (call getBranches data)
  return (and (isAnyClass branches 'Array' 'List') (not (isEmpty branches)))
}

method createBranches TreeBox {
  removeAllBranches this
  branches = (call getBranches data)
  if (not (isAnyClass branches 'Array' 'List')) {return}
  for each branches {
    addPart morph (morph (treeBox this each getEntry getBranches onSelect bgColor onDoubleClick getHint))
  }
  if ((count branches) > 0) {toggleExpansion this true}
}

method removeAllBranches TreeBox {
  arrow = (first (parts morph))
  removeAllParts morph
  addPart morph arrow
}

method fixLayout TreeBox {
  paddingX = (3 * (global 'scale'))
  x = (left morph)
  y = (bottom morph)
  for i (count (parts morph)) {
    each = (at (parts morph) i)
    if (i == 1) { // arrow
        setPosition each (+ x paddingX (* (indent this) (level - 1))) (top morph)
    } else {
        setPosition each x y
        y += (height (fullBounds each))
    }
  }
  if (isRoot this) {
    parent = nil
    if (notNil (owner morph)) {
      parent = (handler (owner morph))
    }
    if (isClass parent 'ScrollFrame') {
      adjustContents parent
      updateSliders parent
    } else {
      adjustWidths this
    }
  }
}

method setMinWidth TreeBox minWidth {adjustWidths this minWidth}

method adjustWidths TreeBox maxWidth {
  if (isNil maxWidth) {maxWidth = 0}
  itemsWidth = (maxItemWidth this)
  mw = (max maxWidth itemsWidth)
  for each (allVisibleNodes this) {
    setWidth (bounds (morph each)) mw
  }
  if (notNil selection) {
    removeCostume (toggle selection) 'highlight'
    refresh selection
  }
}

method maxItemWidth TreeBox {
  mw = 0
  for each (allVisibleNodes this) {
    if (not (isHidden (morph each))) {
      nc = (getField each 'toggle' 'trigger' 'normalCostume')
      if (isClass nc 'Bitmap') {
        mw = (max mw (width nc))
      }
    }
  }
  return mw
}

method allVisibleNodes TreeBox {
  if (isHidden (morph this)) {return (list)}
  ans = (list this)
  for i ((count (parts morph)) - 1) {
    each = (at (parts morph) (i + 1))
    addAll ans (allVisibleNodes (handler each))
  }
  return ans
}

method normalCostume TreeBox inputData accessor {
  if omitRoot {return (newBitmap 0 0)}
  return (itemCostume this data (color) nil nil getEntry)
}

method highlightCostume TreeBox inputData accessor {
  return (itemCostume this data bgColor (gray 130) nil getEntry)
}

method pressedCostume TreeBox inputData accessor {
  return (itemCostume this data (color) (darker bgColor 10) nil getEntry)
}

method itemCostume TreeBox inputData foregroundColor backgroundColor alpha accessor {
  // private - return a bitmap representing a list item

  // simulate constants
  scale = (global 'scale')
  paddingX = (3 * scale)
  paddingY = scale
  fontName = 'Arial'
  fontSize = (12 * (global 'scale'))

  if (isNil accessor) {accessor = getEntry}
  dta = (call accessor inputData)
  if (isClass dta 'Bitmap') {
    indent = (* level (indent this))
    bm = (newBitmap (max (+ indent (* 2 paddingX) (width dta)) (width morph)) (+ (height dta) (* 2 paddingY)) backgroundColor)
    drawBitmap bm dta (+ indent paddingX) paddingY alpha
    return bm
  } (isClass dta 'Morph') {
    return (itemCostume this (fullCostume dta) foregroundColor backgroundColor alpha 'id')
  } (hasField dta 'morph') {
    return (itemCostume this (fullCostume (getField dta 'morph')) foregroundColor backgroundColor alpha 'id')
  } (isAnyClass dta 'Command' 'Reporter') {
    return (itemCostume this (fullCostume (morph (toBlock dta))) foregroundColor backgroundColor alpha 'id')
  } (isClass dta 'String') {
    return (itemCostume this (stringImage dta fontName fontSize foregroundColor) foregroundColor backgroundColor alpha 'id')
  } else {
    return (itemCostume this (toString dta) foregroundColor backgroundColor alpha 'id')
  }
}

method arrowToggle TreeBox {
  clr = (gray 128)
  tr = (new 'Trigger' nil (action 'toggleExpansion' this))
  m = (newMorph)
  setMorph tr m
  setTransparentTouch m true
  ar = (new 'Toggle' m tr (action 'isCollapsed' this))
  setHandler m ar
  replaceCostumes tr (arrowCostume this 'down' clr) (arrowCostume this 'right' clr)
  side = (indent this)
  setWidth (bounds m) side
  setHeight (bounds m) side
  refresh ar true
  if (not (hasBranches this)) {hide (morph ar)}
  return ar
}

method toggleExpansion TreeBox expand {
  if (isNil expand) {
    isCollapsed = (not isCollapsed)
  } else {
    isCollapsed = (not expand)
  }
  if isCollapsed {
    for i (- (count (parts morph)) 1) { // hide branches
      branch = (at (parts morph) (i + 1))
      hide branch
      unselect (handler branch)
    }
  } else {
    if ((count (parts morph)) < 2) {
      createBranches this
    } else {
      for i (- (count (parts morph)) 1) { // show branches
        show (at (parts morph) (i + 1))
      }
    }
  }
  refresh (handler (first (parts morph))) true
  cm = morph
  fixLayout this
  while (and (notNil (owner cm)) (isClass (handler (owner cm)) (className (classOf this)))) {
    cm = (owner cm)
    fixLayout (handler cm)
  }
}

method arrowCostume TreeBox direction color {
  // direction can be 'right', 'left', 'up' or 'down'
  side = (indent this)
  border = (side / 4)
  bm = (newBitmap side side)
  fillArrow (newShapeMaker bm) (rect border border (side - (border * 2)) (side - (border * 2))) direction color
  return bm
}

method highlighted TreeBox {return highlighted}
method highlightOn TreeBox aListItem {highlighted = aListItem}

method highlightOff TreeBox aListItem {
  if (highlighted === aListItem) {
    highlighted = nil
  }
}

method selectedMorph TreeBox {
  sel = (selection (root this))
  if (isNil sel) {return nil}
  return (morph sel)
}
