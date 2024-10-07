// Morphic Menu handler

defineClass Menu morph label target items reverseCall selection returnFocus isTopMenu

to menu label target reverseCall returnFocus {
  if (isNil reverseCall) {reverseCall = false}
  return (new 'Menu' nil (localized label) target (list) reverseCall)
}

method addItemNonlocalized Menu itemLabel itemAction itemHint itemThumb {
  addItem this itemLabel itemAction itemHint itemThumb false
}

method addItem Menu itemLabel itemAction itemHint itemThumb localizeFlag disabledFlag {
  if (isNil itemAction) { itemAction = itemLabel }
  if (isNil localizeFlag) { localizeFlag = true }
  if (not (isAnyClass itemLabel 'Bitmap' 'String')) {
	itemLabel = (toString itemLabel)
  }
  if (and (isClass itemLabel 'String') localizeFlag) {
        itemLabel = (localized itemLabel)
  }
  if disabledFlag { itemAction = nil }
  add items (array itemLabel itemAction itemHint itemThumb disabledFlag)
}

method addLine Menu lineWidth {
  if (isNil lineWidth) {lineWidth = 1}
  if (lastItemIsLine this) { return }
  add items (array (array 0 lineWidth))
}

method setIsTopMenu Menu aBool { isTopMenu = aBool }

method lastItemIsLine Menu {
  if ((count items) == 0) { return true }
  lastItem = (last items)
  return (and (isClass lastItem 'Array') ((count lastItem) == 1) ((count (first lastItem)) == 2))
}

method popUp Menu page x y noFocus {
  if (or (isNil noFocus) (not (isClass noFocus 'Boolean'))) {noFocus = false}
  if (isEmpty items) { return }
  buildMorph this page y
  showMenu page this x y
  if (not noFocus) {focus this}
}

method popUpAtHand Menu page noFocus {
  popUp this page  (x (hand page)) (y (hand page)) noFocus
}

to popUpAtHand {
  // allows (context-) menus to be "nil"
  nop
}

method waitForSelection Menu {
	// Pop up menu and wait until a selection is made or menu is closed.

	page = (global 'page')
	popUpAtHand this page
	while (notNil (owner morph)) { doOneCycle page }
}

method rightClicked Menu {return true}

method itemLabel Menu labelPic thumbPic bgColor itemWidth itemPaddingH itemPaddingV {
  // private - answer a bitmap containg both the labelPic and the thumbPic
  if (and (isNil bgColor) (isNil thumbPic)) {return labelPic}
  if (isNil itemWidth) {itemWidth = 0}
  if (isNil itemPaddingH) {itemPaddingH = 0}
  if (isNil itemPaddingV) {itemPaddingV = 0}
  thWidth = 0
  thHeight = 0
  padding = 0
  if (notNil thumbPic) {
    thWidth = (width thumbPic)
    thHeight = (height thumbPic)
  }
  result = (newBitmap
    (max itemWidth (+ padding (width labelPic) thWidth))
    (+ (max (height labelPic) thHeight) (* 2 itemPaddingV))
  )
  if (notNil bgColor) {fill result bgColor}
  if (notNil thumbPic) {
    bgColor = (microBlocksColor 'blueGray' 900)
    drawBitmap result thumbPic itemPaddingH (((height result) - thHeight) / 2)
  }
  drawBitmap result labelPic (+ padding thWidth itemPaddingH) (((height result) - (height labelPic)) / 2)
  return result
}

method buildMorph Menu page yPos {
  scale =  (global 'scale')

  // settings, to be refactored later to somewhere else
  fontName = 'Arial'
  fontSize = (scale * 16)
  if ('Linux' == (platform)) { fontSize = (scale * 13) }
  border = (scale * 1)
  corner = (scale * 2)
  itemPaddingV = (scale * 1)
  if isTopMenu {
	itemPaddingH = (scale * 32)
  } else {
	itemPaddingH = (scale * 6)
  }

  if isTopMenu {
	color = (microBlocksColor 'blueGray' 900)
	borderColor = (microBlocksColor 'blueGray' 700)
	itemTextColorNormal = (microBlocksColor 'blueGray' 50)
	itemTextColorDisabled = (microBlocksColor 'blueGray' 600)
	itemTextColorHighlighted = color
	itemTextColorPressed = color
  } else {
	color = (microBlocksColor 'blueGray' 50)
	borderColor = (microBlocksColor 'blueGray' 100)
	itemTextColorNormal = (microBlocksColor 'blueGray' 900)
	itemTextColorDisabled = (microBlocksColor 'blueGray' 200)
	itemTextColorHighlighted = itemTextColorNormal
	itemTextColorPressed = itemTextColorNormal
  }

  itemBackgroundColorHighlighted = (microBlocksColor 'yellow')
  itemBackgroundColorPressed = itemBackgroundColorHighlighted

  minHeight = (min (scale * 100) (height (morph page)))
  maxHeight = ((height (morph page)) - 100)

  menuWidth = 50
  menuHeight = 0

  if (notNil morph) {destroy morph}

  // measure item labels, determine menu dimensions
  itemLbls = (newArray (count items))
  for i (count items) {
    tuple = (at items i)
    itemLbl = (at tuple 1)
    itemThm = nil
    disabled = false
    if (> (count tuple) 3) {itemThm = (at tuple 4)}
    if (> (count tuple) 4) {disabled = (at tuple 5)}
    if (isClass itemLbl 'String') {
      if disabled {
        itemLbl = (menuStringImage itemLbl fontName fontSize itemTextColorDisabled color)
      } else {
        itemLbl = (menuStringImage itemLbl fontName fontSize itemTextColorNormal color)
      }
      itemLbl = (itemLabel this itemLbl itemThm)
      menuWidth = (max menuWidth (+ (width itemLbl) (* itemPaddingH 2)))
      menuHeight += (+ (height itemLbl) (* itemPaddingV 2))
    } (isClass itemLbl 'Bitmap') {
      itemLbl = (itemLabel this itemLbl itemThm)
      menuWidth = (max menuWidth (+ (width itemLbl) (* itemPaddingH 2)))
      menuHeight += (+ (height itemLbl) (* itemPaddingV 2))
    } (isClass itemLbl 'Array') {
      if ((at itemLbl 1) == 0) { // line
        menuHeight += (* scale (at itemLbl 2))
      }
    }
    atPut itemLbls i itemLbl
  }

  widgetHeight = (min menuHeight maxHeight)
  widgetWidth = menuWidth
  if (widgetHeight < menuHeight) {
    widgetWidth += (scale * 10) // slider thickness
  }

  // create the actual menu Morph
  morph = (newMorph this)
  bg = (newBitmap (+ widgetWidth border border) (+ widgetHeight border border))

  pen = (newShapeMaker bg)
  area = (rect 0 0 (width bg) (height bg))
  fillRoundedRect pen area corner borderColor 1 frameColor
  setWidth (bounds morph) (width bg)
  setHeight (bounds morph) (height bg)

  setCostume morph bg
  y = border

  if (widgetHeight < menuHeight) {
    box = (newBox nil (transparent) 0 0 false false)
    container = (morph box)
    setExtent container menuWidth menuHeight
    scrollFrame = (scrollFrame box)
    setExtent (morph scrollFrame) widgetWidth widgetHeight
    setPosition (morph scrollFrame) border border
    addPart morph (morph scrollFrame)
    updateSliders scrollFrame
    setAlpha (morph (getField scrollFrame 'vSlider')) 255
    y = (top (morph box))
  } else {
    container = morph
  }

  // create and position actual menu items
  for i (count items) {
    tuple = (at items i)
    paddingH = itemPaddingH
    itemThm = nil
    disabled = false
    if (> (count tuple) 3) { itemThm = (at tuple 4) }
    if (notNil itemThm) { paddingH = 0 }
    if (> (count tuple) 4) {disabled = (at tuple 5)}
    ilbl = (at itemLbls i)
    if (isClass ilbl 'Bitmap') {
      nbm = (itemLabel this ilbl nil color menuWidth paddingH itemPaddingV)
      if (isClass (at tuple 1) 'String') {ilbl = (menuStringImage (at tuple 1) fontName fontSize itemTextColorHighlighted itemBackgroundColorHighlighted)}
      if disabled {
        hbm = nbm
      } else {
        hbm = (itemLabel this ilbl itemThm itemBackgroundColorHighlighted menuWidth paddingH itemPaddingV)
      }
      if (isClass (at tuple 1) 'String') {ilbl = (menuStringImage (at tuple 1) fontName fontSize itemTextColorPressed itemBackgroundColorPressed)}
      pbm = (itemLabel this ilbl itemThm itemBackgroundColorPressed menuWidth paddingH itemPaddingV)
      if reverseCall {
        itemAction = (action target (at tuple 2))
      } else {
        itemAction = (action (at tuple 2) target)
      }
	  if disabled {
	    action = nil
	  } else {
        action = (array
          (action 'unfocus' this)
          (action 'destroy' morph)
          itemAction)
	  }
      item = (new 'Trigger' nil action nbm hbm pbm)
      setHint item (localized (at tuple 3))
      m = (newMorph item)
      setMorph item m
      normal item
      setWidth (bounds m) (width nbm)
      setHeight (bounds m) (height nbm)
      setTransparentTouch m true
      setPosition m border y
      addPart container m
        y += (height nbm)
    } (isClass ilbl 'Array') {
      if ((at ilbl 1) == 0) {
        y += (scale * (at ilbl 2))
      }
    }
  }
}

// keyboard accessibility hooks - experimental
// uses the 'selection' and 'returnFocus' fields

method focus Menu {
  page = (page morph)
//  if (notNil fallbackFocus) {
//    stopEditing (keyboard page)
//  }
//  selectFirstItem this // xxx
  focusOn (keyboard page) this
}

method unfocus Menu {
  page = (global 'page')
  clearActiveMenu page
  if ((focus (keyboard page)) === this) {
      stopEditing (keyboard page)
  }
}

method destroyedMorph Menu {unfocus this}

method keyDown Menu evt keyboard {
  code = (at evt 'keycode')
  if (13 == code) { trigger this // enter
  } (27 == code) { cancel this // escape
  } (32 == code) { trigger this // space
  } (37 == code) { selectPreviousItem this // left arrow
  } (38 == code) { selectPreviousItem this // up arrow
  } (39 == code) { selectNextItem this // right arrow
  } (40 == code) { selectNextItem this // down arrow'
  }
}

method keyUp Menu evt keyboard {nop}

method textinput Menu evt keyboard {
  // to be used for keyboard shortcuts
  // char = (at evt 'text')
  // jumpTo this char
}

method triggers Menu {
  result = (list)
  for m (parts morph) {
    if (isClass (handler m) 'Trigger') {
      add result (handler m)
    } (isClass (handler m) 'ScrollFrame') {
      for p (parts (morph (contents (handler m)))) {
        if (isClass (handler p) 'Trigger') {
          add result (handler p)
        }
      }
    }
  }
  return result
}

method selectFirstItem Menu {
  triggers = (triggers this)
  if (notEmpty triggers) {select this (first triggers)}
}

method selectNextItem Menu {
  triggers = (triggers this)
  if (isEmpty triggers) { return }
  idx = (indexOf triggers selection)
  if (or (isNil idx) (idx >= (count triggers))) {
    sel = (first triggers)
  } else {
    sel = (at triggers (idx + 1))
  }
  select this sel
}

method selectPreviousItem Menu {
  triggers = (triggers this)
  if (isEmpty triggers) { return }
  idx = (indexOf triggers selection)
  if (isNil idx) {
    sel = (first triggers)
  } (idx <= 1) {
    sel = (last triggers)
  } else {
    sel = (at triggers (idx - 1))
  }
  select this sel
}

method select Menu trigger {
  if (notNil selection) {normal selection}
  selection = trigger
  highlight selection
  scrollIntoView (morph trigger)
}

method trigger Menu {
  if (isNil selection) {
    selectFirstItem this
  } else {
    trigger selection
  }
}

method cancel Menu {
  page = (page morph)
  unfocus this
  destroy morph
  if (notNil returnFocus) {
    focusOn (keyboard page) returnFocus
    redraw returnFocus
  }
}
