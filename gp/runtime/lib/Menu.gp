// Morphic Menu handler

defineClass Menu morph label target items reverseCall selection returnFocus

to menu label target reverseCall returnFocus {
  if (isNil reverseCall) {reverseCall = false}
  return (new 'Menu' nil (localized label) target (list) reverseCall)
}

method addItem Menu itemLabel itemAction itemHint itemThumb {
  if (isNil itemAction) { itemAction = itemLabel }
  if (not (isAnyClass itemLabel 'Bitmap' 'String')) {
	itemLabel = (toString itemLabel)
  }
  if (isClass itemLabel 'String') {
        itemLabel = (localized itemLabel)
  }
  add items (array itemLabel itemAction itemHint itemThumb)
}

method addLine Menu lineWidth {
  if (isNil lineWidth) {lineWidth = 1}
  if (lastItemIsLine this) { return }
  add items (array (array 0 lineWidth))
}

method lastItemIsLine Menu {
  if ((count items) == 0) { return true }
  lastItem = (last items)
  return (and (isClass lastItem 'Array') ((count lastItem) == 1) ((count (first lastItem)) == 2))
}

method popUp Menu page x y noFocus {
  if (or (isNil noFocus) (not (isClass noFocus 'Boolean'))) {noFocus = false}
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
    padding = (* 3 (global 'scale'))
  }
  result = (newBitmap
    (max itemWidth (+ padding (width labelPic) thWidth))
    (+ (max (height labelPic) thHeight) (* 2 itemPaddingV))
  )
  if (notNil bgColor) {fill result bgColor}
  if (notNil thumbPic) {drawBitmap result thumbPic itemPaddingH (((height result) - thHeight) / 2)}
  drawBitmap result labelPic (+ padding thWidth itemPaddingH) (((height result) - (height labelPic)) / 2)
  return result
}

method buildMorph Menu page yPos {
  scale =  (global 'scale')

  // settings, to be refactored later to somewhere else
  labelFontName = 'Arial Bold'
  fontName = 'Arial'
  fontSize = (scale * 16)
  border = (scale * 1)
  corner = (scale * 2)
  labelPadding = (scale * 4)
  itemPaddingV = (scale * 1)
  itemPaddingH = (scale * 3)
  color = (gray 255)
  labelTextColor = (gray 255)
  labelBackgroundColor = (gray 60)
  borderColor = labelBackgroundColor
  itemTextColorNormal = (gray 0)
  itemTextColorHighlighted = itemTextColorNormal
  itemTextColorPressed = (gray 255)
  itemBackgroundColorHighlighted = (gray 210)
  itemBackgroundColorPressed = (gray 100)

  minHeight = (min (scale * 100) (height (morph page)))
  maxHeight = ((height (morph page)) - 100)

  if (notNil morph) {destroy morph}

  // create raw label bitmap - lbl
  lbl = label
  if (isClass lbl 'String') {
    lbl = (stringImage lbl labelFontName fontSize labelTextColor 'center' (darker labelTextColor 80) nil nil nil nil labelBackgroundColor)
  }
  lblHeight = 0
  lblWidth = 0
  if (isClass lbl 'Bitmap') {
    lblHeight = (+ (height lbl) (* labelPadding 2))
    lblWidth = (width lbl)
  }
  menuWidth = (+ lblWidth (* labelPadding 2))
  menuHeight = lblHeight

  // measure item labels, determine menu dimensions
  itemLbls = (newArray (count items))
  for i (count items) {
    tuple = (at items i)
    itemLbl = (at tuple 1)
    itemThm = nil
    if (> (count tuple) 3) {itemThm = (at tuple 4)}
    if (isClass itemLbl 'String') {
      itemLbl = (stringImage itemLbl fontName fontSize itemTextColorNormal)
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

  // create full label bitmap
  if (isClass lbl 'Bitmap') {
    fullLabel = (newBitmap widgetWidth lblHeight)
    fill fullLabel labelBackgroundColor
    x = (((width fullLabel) - (width lbl)) / 2)
    y = (((height fullLabel) - (height lbl)) / 2)
    drawBitmap fullLabel lbl x y

    // render full label on menu
    drawBitmap bg fullLabel border (+ border corner)
  } else {
    fullLabel = (rect)
  }
  y = (+ (height fullLabel) border)
  setCostume morph bg

  if (widgetHeight < menuHeight) {
    box = (newBox nil (transparent) 0 0 false false)
    container = (morph box)
    setExtent container menuWidth (menuHeight - lblHeight)
    scrollFrame = (scrollFrame box)
    setExtent (morph scrollFrame) widgetWidth (widgetHeight - lblHeight)
    setPosition (morph scrollFrame) border (+ (height fullLabel) border)
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
    itemThm = nil
    if (> (count tuple) 3) {itemThm = (at tuple 4)}
    ilbl = (at itemLbls i)
    if (isClass ilbl 'Bitmap') {
      nbm = (itemLabel this ilbl nil color menuWidth itemPaddingH itemPaddingV)
      if (isClass (at tuple 1) 'String') {ilbl = (stringImage (at tuple 1) fontName fontSize itemTextColorHighlighted)}
      hbm = (itemLabel this ilbl itemThm itemBackgroundColorHighlighted menuWidth itemPaddingH itemPaddingV)
      if (isClass (at tuple 1) 'String') {ilbl = (stringImage (at tuple 1) fontName fontSize itemTextColorPressed)}
      pbm = (itemLabel this ilbl itemThm itemBackgroundColorPressed menuWidth itemPaddingH itemPaddingV)
      if reverseCall {
        itemAction = (action target (at tuple 2))
      } else {
        itemAction = (action (at tuple 2) target)
      }
      action = (array
        (action 'unfocus' this)
        (action 'destroy' morph)
        itemAction)
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
  selectFirstItem this
  focusOn (keyboard page) this
}

method unfocus Menu {
  page = (global 'page')
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
