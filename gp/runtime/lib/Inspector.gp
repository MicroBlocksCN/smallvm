// explore GP objects

defineClass Inspector morph window contents listBox listFrame tabs tabsFrame readouts fieldFrame evalBox evalFrame

method initialize Inspector {
  scale = (global 'scale')
  window = (window (labelName this))
  clr = (clientColor window)
  border = (border window)
  morph = (morph window)
  setHandler morph this
  setMinExtent morph (scale * 130) (scale * 100)
  setFPS morph 3

  listBox = (listBox (fieldNames this) 'toString' (action 'selectField' this) clr (action 'inspectField' this))
  listFrame = (scrollFrame listBox clr)
  addPart morph (morph listFrame)

  tabs = (tabBar (array 'basic') nil (action 'tab' this))
  tabsFrame = (newMorph)
  setClipping tabsFrame true true
  addPart tabsFrame (morph tabs)
  addPart morph tabsFrame
  hide tabsFrame

  basicReadout = (newText)
  setBorders basicReadout border border true
  setEditRule basicReadout 'code'
  setCodeContext basicReadout contents
  setGrabRule (morph basicReadout) 'ignore'

  readouts = (dictionary)
  atPut readouts 'basic' basicReadout

  fieldFrame = (scrollFrame basicReadout clr)
  addPart morph (morph fieldFrame)

  evalBox = (newText)
  setBorders evalBox border border true
  setEditRule evalBox 'code'
  setCodeContext evalBox contents
  setGrabRule (morph evalBox) 'ignore'
  evalFrame = (scrollFrame evalBox clr)
  addPart morph (morph evalFrame)

  setExtent morph (scale * 250) (scale * 180)
  setPosition morph 5 57

  setFramePadding (alignment tabs) (4 * scale)
  fixLayout (alignment tabs)
  select tabs 'basic'
}

method fixLayout Inspector {
  fixLayout window
  clientArea = (clientArea window)
  border = (border window)

  setPosition (morph listFrame) (left clientArea) (top clientArea)
  setExtent (morph listFrame) (min ((width clientArea) / 3) (+ 12 (itemWidth listBox))) (height clientArea)

  tp = (top clientArea)
  w = (- (- (width clientArea) (width (morph listFrame))) border)
  h = 0
  if (isVisible tabsFrame) {
    h = (height (morph tabs))
    setPosition tabsFrame (+ (right (morph listFrame)) border) tp
    setExtent tabsFrame w h
    tp = (bottom tabsFrame)
  }

  setPosition (morph fieldFrame) (+ (right (morph listFrame)) border) tp
  setExtent (morph fieldFrame) w ((((height clientArea) / 3) * 2) - h)

  setPosition (morph evalFrame) (left (morph fieldFrame)) (+ (bottom (morph fieldFrame)) border)
  setExtent (morph evalFrame) w ((bottom clientArea) - (+ border (bottom (morph fieldFrame))))
}

method redraw Inspector {
  redraw window
  fixLayout this
}

method selectField Inspector aFieldName {
  basicReadout = (at readouts 'basic')
  readouts = (dictionary)
  atPut readouts 'basic' basicReadout

  if (shiftKeyDown (keyboard (handler (root morph)))) {
    select listBox nil
    setText (at readouts 'basic') ''
    select tabs 'basic'
    return
  }

  val = (getField contents aFieldName)
  setText (at readouts 'basic') (printString val)
  info = (fieldInfo contents aFieldName)
  if (notNil info) {
    atPut readouts (at info 'type') (readoutFor this info)
  }
  if (isClass val 'Boolean') {
    atPut readouts 'switch' (switchReadout this)
    setCollection tabs (keys readouts)
  } else {
    setCollection tabs (keys readouts)
  }
  if (2 > (count (keys readouts))) {
    hide tabsFrame
  } else {
    show tabsFrame
  }
  select tabs (last (keys readouts))
  fixLayout this
}

method labelName Inspector {
  if (contains (array 65 97 69 101 73 105 79 111 85 117) (byteAt (className (classOf contents)) 1)) {
    pref = 'an '
  } else {
    pref = 'a '
  }
  if (or (isNil contents) (true === contents) (false === contents)
		 (isClass contents 'Integer') (isClass contents 'Float')
		 (isClass contents 'String') (isClass contents 'ExternalReferences')) {
	cts = (join ': ' (printString contents))
  } else {
    cts = ''
  }
  return (join pref (className (classOf contents)) cts)
}

method fieldNames Inspector {
  if (isAnyClass contents 'String' 'Float' 'ExternalReference' 'BinaryData') {
    return (array)
  }
  fieldNames = (fieldNames (classOf contents))
  n = (min 1000 (objWords contents))
  slotNames = (newArray n)
  for i n {
    if (i <= (count fieldNames)) {
      slotName = (at fieldNames i)
    } else {
      slotName = i
    }
    atPut slotNames i slotName
  }
  return slotNames
}

method tab Inspector tabName {
  padding = (border window)
  if (tabName == 'basic') {padding = 0}
  setContents fieldFrame (at readouts tabName) padding
}

method inspectField Inspector aFieldName {
  page = (handler (root morph))
  ins = (inspectorOn (getField contents aFieldName))
  setPosition (morph ins) (x (hand page)) (y (hand page))
  addPart (morph page) (morph ins)
}

method textChanged Inspector origin {if (origin === (at readouts 'basic')) {pushCurrentField this}}

method pushCurrentField Inspector {
  fieldName = (selection listBox)
  if (isNil fieldName) {return}
  result = (eval (join '(id ' (text (at readouts 'basic')) ')') contents)
  setField contents fieldName result
  selectField this fieldName
}

method step Inspector {
  fieldName = (selection listBox)

  // update window label
  lbl = (labelName this)
  if (!= lbl (labelString window)) {
    setLabelString window lbl
  }

  // update fieldNames
  fieldNames = (fieldNames this)
  if (!= fieldNames (collection listBox)) {
    setCollection listBox fieldNames
    if (not (contains fieldNames fieldName)) {
      fieldName = nil
      setText (at readouts 'basic') ''
    }
    select listBox fieldName
  }

  // update readout
  if (isNil fieldName) {return}
  basicReadout = (at readouts 'basic')
  if (isVisible (morph basicReadout)) {
    result = (printString (getField contents fieldName))
    if (or (notNil (caret basicReadout)) (result == (text basicReadout))) {return}
    setText basicReadout result
  } else {
    update (at readouts (selection tabs))
  }
}

to inspectorOn anObject {
  ins = (new 'Inspector' nil nil anObject)
  initialize ins
  return ins
}

to openInspector obj {
  page = (global 'page')
  if (isNil page) {
    inspect obj
	return
  }
  addPart page (inspectorOn obj)
}

// context menus

method rightClicked Inspector hand {
  popUpAtHand (contextMenu this) (page hand)
  return true
}

method handleListContextRequest Inspector anArray {
  dta = (data (last anArray))
  popUpAtHand (fieldContextMenu this dta) (global 'page')
}

method contextMenu Inspector {
  menu = (menu nil this)
  addItem menu 'explore' (action 'openExplorer' contents)
  addLine menu
  addItem menu (join 'browse class: ' (className (classOf contents))) (action 'browseClass' this (classOf contents))
  return menu
}

method fieldContextMenu Inspector fieldName {
  cls = (classOf (getField contents fieldName))
  menu = (menu fieldName this)
  addItem menu 'explore' (action 'openExplorer' (getField contents fieldName))
  addItem menu 'inspect' (action 'inspectField' this fieldName)
  addItem menu (join 'browse class: ' (className cls)) (action 'browseClass' this cls)
  return menu
}

method browseClass Inspector aClass {
  page = (page morph)
  brs = (newClassBrowser)
  setPosition (morph brs) (x (hand page)) (y (hand page))
  addPart page brs
  browse brs aClass
}

// readouts

to fieldInfo fieldName {return nil}

method switchReadout Inspector {
  scale = (global 'scale')
  toggle = (toggleButton (action 'toggleField' this) (action 'getField' contents (selection listBox)) (scale * 20) (scale * 13) (scale * 5) (max 1 (scale / 2)) false)
  return (readout 'switch' contents (selection listBox) toggle 'refresh')
}

method toggleField Inspector {
  fieldName = (selection listBox)
  setField contents fieldName (not (getField contents fieldName))
}

method readoutFor Inspector info {
  if ('options' == (at info 'type')) {
    options = (listBox (at info 'options') 'id' (action 'setField' contents (selection listBox)))
    return (readout 'options' contents (selection listBox) options 'select')
  }
  error 'unsupported info type' (at info 'type')
}

method currentSelection Inspector {
  // answer the value of the currently selected field, if any
  fieldName = (selection listBox)
  if (isNil fieldName) {return nil}
  return (getField contents fieldName)
}

method currentHighlight Inspector {
  // answer the value of the currently highlighted field, if any
  hl = (highlighted listBox)
  if (isNil hl) {return nil}
  fieldName = (data hl)
  return (getField contents fieldName)
}

method connectors Inspector {
  tp = (top (morph listFrame))
  bt = (bottom (morph listFrame))
  x = (hCenter (bounds (morph listFrame)))
  result = (list)
  for item (parts (morph listBox)) {
    fieldName = (data (handler item))
    dta = (getField contents fieldName)
    y = (min bt (max tp (vCenter (bounds item))))
    add result (array dta (array x y))
  }
  return result
}
