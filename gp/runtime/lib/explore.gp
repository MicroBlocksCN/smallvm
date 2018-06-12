// explore GP objects

defineClass ExplorerNode name value parent

to exploreNode name value parent {return (new 'ExplorerNode' name value parent)}

method name ExplorerNode {return name}
method value ExplorerNode {return value}
method setValue ExplorerNode newValue {value = newValue}
method parent ExplorerNode {return parent}

method fields ExplorerNode {
  ans = (list)
  if (isAnyClass value 'String' 'Float' 'ExternalReference' 'BinaryData') {
    return ans
  }
  if (isClass value 'Dictionary') {
	for k (sorted (keys value)) {
	  add ans (exploreNode k (at value k) this)
	}
  } (isClass value 'List') {
	for i (min 1000 (count value)) {
	  add ans (exploreNode i (at value i) this)
	}
  } else {
	fieldNames = (fieldNames (classOf value))
	for i (min 1000 (objWords value)) {
	  if (i <= (count fieldNames)) {
		slot = (at fieldNames i)
	  } else {
		slot = i
	  }
	  add ans (exploreNode slot (getField value slot) this)
	}
  }
  return ans
}

method path ExplorerNode {
  ans = (list)
  cur = this
  while (notNil (name cur)) {
    add ans (name cur)
    cur = (parent cur)
  }
  add ans (value cur)
  return (reversed (toArray ans))
}

defineClass Explorer morph window contents listBox listFrame tabs tabsFrame readouts fieldFrame evalBox evalFrame resizer

method initialize Explorer {
  scale = (global 'scale')
  window = (window (labelName this))
  stayWithin (getField window 'resizer') (action 'windowConstraint' this)
  clr = (clientColor window)
  border = (border window)
  morph = (morph window)
  setHandler morph this
  setMinExtent morph (scale * 130) (scale * 100)
  setFPS morph 3

  listBox = (treeBox
    nil
    (exploreNode nil contents)
    'name'
    'fields'
    (action 'selectField' this)
    clr
    (action 'exploreField' this)
    nil
    true
  )

  listFrame = (scrollFrame listBox clr)
  setExtent (morph listFrame) (* scale 80)
  resizer = (resizeHandle listFrame 'horizontal')
  clearCostumes (getField resizer 'trigger')
  stayWithin resizer (action 'listFrameConstraint' this)
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

  setExtent morph (scale * 500) (scale * 300)
  setPosition morph 5 57

  setFramePadding (alignment tabs) (4 * scale)
  fixLayout (alignment tabs)
  select tabs 'basic'
}

method fixLayout Explorer {
  fixLayout window
  clientArea = (clientArea window)
  border = (border window)

  setPosition (morph listFrame) (left clientArea) (top clientArea)
  setExtent (morph listFrame) nil (height clientArea)

  setBounds (morph resizer) (rect (right (morph listFrame)) (top clientArea) border (height clientArea))

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
  addPart morph (morph resizer) // bring to front
}

method redraw Explorer {
  redraw window
  fixLayout this
}

method listFrameConstraint Explorer {return (insetBy (clientArea window) ((global 'scale') * 20))}

method windowConstraint Explorer {
  c = (resizingConstraint morph)
  l =  (+ (border window) (right (morph listBox)))
  t = (top (clientArea window))
  return (array (max l (first c)) (max t (last c)))
}

method selectField Explorer aNode {
  basicReadout = (at readouts 'basic')
  readouts = (dictionary)
  atPut readouts 'basic' basicReadout

  if (shiftKeyDown (keyboard (handler (root morph)))) {
    unselect listBox
    setText (at readouts 'basic') ''
    select tabs 'basic'
    return
  }

  val = (selectedValue this)
  setText (at readouts 'basic') (printString val)

  info = (fieldInfo (value (parent aNode)) (name aNode))
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

method labelName Explorer {
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

method tab Explorer tabName {
  padding = (border window)
  if (tabName == 'basic') {padding = 0}
  setContents fieldFrame (at readouts tabName) padding
}

method exploreField Explorer {
  page = (handler (root morph))
  ins = (explorerOn (selectedValue this))
  setPosition (morph ins) (x (hand page)) (y (hand page))
  addPart (morph page) (morph ins)
}

method textChanged Explorer origin {if (origin === (at readouts 'basic')) {pushCurrentField this}}

method pushCurrentField Explorer {
  sel = (selection listBox)
  if (isNil sel) {return}
  node = (data sel)
  result = (eval (join '(id ' (text (at readouts 'basic')) ')') contents)
  setNodeValue this node result
  select sel
}

method setNodeValue Explorer node value {
  parentObj = (value (parent node))
  if (isAnyClass parentObj 'Dictionary' 'List') {
	atPut parentObj (name node) value
  } else {
	setField parentObj (name node) value
  }
  setValue node value
}

method step Explorer {
  // update window label
  lbl = (labelName this)
  if (!= lbl (labelString window)) {
    setLabelString window lbl
  }

  // update fieldNames - tbd

  // update readout
  if (isNil (selection listBox)) {return}
  basicReadout = (at readouts 'basic')
  if (notNil (owner (morph basicReadout))) {
    result = (printString (selectedValue this))
    if (or (notNil (caret basicReadout)) (result == (text basicReadout))) {return}
    setText basicReadout result
  } else {
    update (at readouts (selection tabs))
  }
}

to explorerOn anObject {
  ins = (new 'Explorer' nil nil anObject)
  initialize ins
  return ins
}

to openExplorer obj {
  page = (global 'page')
  if (isNil page) {
    explore obj
	return
  }
  addPart page (explorerOn obj)
}

// context menus

method rightClicked Explorer hand {
  popUpAtHand (contextMenu this) (page hand)
  return true
}

method handleContextRequest Explorer item {
  aTreeBox = (handler (morph item))
  if (isClass aTreeBox 'TreeBox') {
	popUpAtHand (fieldContextMenu this aTreeBox) (global 'page')
  }
}

method contextMenu Explorer {
  menu = (menu nil this)
  addItem menu 'basic inspect' (action 'openInspector' contents)
  addLine menu
  addItem menu (join 'browse class: ' (className (classOf contents))) (action 'browseClass' this (classOf contents))
  return menu
}

method fieldContextMenu Explorer aTreeBox {
  node = (data aTreeBox)
  cls = (classOf (value node))
  menu = (menu (name node) this)
  addItem menu 'explore' (action 'openExplorer' (value node))
  addItem menu 'basic inspect' (action 'openExplorer' (value node))
  if (isClass (value node) 'String') {
	addItem menu 'show text' (action 'showText' (joinStrings (wordWrapped (value node) 300) (newline)))
  }
  addLine menu
  addItem menu (join 'browse class: ' (className cls)) (action 'browseClass' this cls)
  return menu
}

method browseClass Explorer aClass {
  page = (page morph)
  brs = (newClassBrowser)
  setPosition (morph brs) (x (hand page)) (y (hand page))
  addPart page brs
  browse brs aClass
}

// readouts

to fieldInfo fieldName {return nil}

method selectedValue Explorer {
  if (isNil (selection listBox)) {return nil}
  path = (path (data (selection listBox)))
  result = (first path)
  for i (range 2 (count path)) {
	thisPart = (at path i)
	if (isAnyClass result 'Dictionary' 'List') {
	  result = (at result thisPart)
	} else {
	  result = (getField result thisPart)
	}
  }
  return result
}

method switchReadout Explorer {
  scale = (global 'scale')
  toggle = (toggleButton (action 'toggleField' this) (action 'selectedValue' this) (scale * 20) (scale * 13) (scale * 5) (max 1 (scale / 2)) false)
  return (readout 'switch' (value (parent (data (selection listBox)))) (name (data (selection listBox))) toggle 'refresh')
}

method toggleField Explorer {
  sel = (selection listBox)
  node = (data sel)
  result = (not (value node))
  setNodeValue this node result
  select sel
}

method readoutFor Explorer info {
  node = (data (selection listBox))
  if ('options' == (at info 'type')) {
    options = (listBox (at info 'options') 'id' (action 'setNodeValue' this node))
    return (readout 'options' (value (parent node)) (name node) options 'select')
  }
  error 'unsupported info type' (at info 'type')
}

method currentSelection Explorer {
  // answer the value of the currently selected field, if any
  sel = (selection listBox)
  if (isNil sel) {return nil}
  return (value (data sel))
}

method currentHighlight Explorer {
  // answer the value of the currently highlighted field, if any
  hl = (highlighted listBox)
  if (isNil hl) {return nil}
  return (value (data (handler (morph hl))))
}

method connectors Explorer {
  tp = (top (morph listFrame))
  bt = (bottom (morph listFrame))
  x = (hCenter (bounds (morph listFrame)))
  result = (list)
  for node (allVisibleNodes listBox) {
    dta = (value (data node))
    y = (min bt (max tp (vCenter (bounds (morph node)))))
    add result (array dta (array x y))
  }
  return result
}
