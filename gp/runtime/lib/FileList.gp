// Experimental GP FileList
//
// To do:

defineClass FileList morph window directoryName buttonsPane listPane contentPane shortcutsPane

to newFileList {
  return (initialize (new 'FileList') '.')
}

to openFileList {
  page = (global 'page')
  if (isNil page) {
    newPage = true
    page = (newPage 1000 800)
    open page true
  }

  fileList = (newFileList)

  addPart page fileList
  if (newPage == true) {
    startStepping page
  }
}

method initialize FileList path {
  directoryName = path
  if (isNil directoryName) {directoryName = '.'}

  scale = (global 'scale')
  window = (window 'FileList')
  morph = (morph window)
  setHandler morph this
  clr = (clientColor window)

  buttonsPane = (newBox nil (gray 250) nil nil false false)
  addPart morph (morph buttonsPane)
  addPart (morph buttonsPane) (makeButton this 'Delete' 'doDelete')

  lbox = (listBox (listFiles directoryName) nil (action 'updateListSelection' this) clr)
  setFont lbox 'Arial'
  listPane = (scrollFrame lbox clr)
  addPart morph (morph listPane)
  setGrabRule (morph listPane) 'ignore'

  text = (newText)
  setEditRule text 'editable'
  contentPane = (scrollFrame text (color 255 255 255))
  addPart morph (morph contentPane)

  lbox = (listBox (array directoryName 'Documents') nil (action 'updateShortcutSelection' this) clr)
  setFont lbox 'Arial'
  shortcutsPane = (scrollFrame lbox clr)
  addPart morph (morph shortcutsPane)
  setGrabRule (morph shortcutsPane) 'ignore'
  select lbox directoryName

  contentPane = (scrollFrame text (color 255 255 255))
  addPart morph (morph contentPane)
  setGrabRule (morph contentPane) 'ignore'

  setMinExtent morph (scale * 200) (scale * 150)
  setExtent morph (scale * 400) (scale * 300)

  return this

}

method updateListSelection FileList {
  file = (selection (contents listPane))
  if (isNil file) {
    setText (contents contentPane) ''
  }
  if ((byteAt directoryName (count directoryName)) != (byteAt '/' 1)) {
    file = (join directoryName '/' file)
  } else {
    file = (join directoryName file)
  }
  str = (readFile file)
  if ((classOf str) == (class 'String')) {
    setText (contents contentPane) str
  }
}

method updateShortcutSelection FileList {
  selection = (selection (contents shortcutsPane))
  if (notNil selection) {
    dir = selection
  } else {
    dir = (selection (contents shortcutsPane))
  }
  if ((classOf dir) == (class 'String')) {
    directoryName = dir
    setCollection (contents listPane) (listFiles directoryName)
    select (contents listPane) nil
    updateListSelection this
  }
}

method makeButton FileList label selector {
  scale = (global 'scale')
  w = (scale * 54)
  h = (scale * 18)
  nbm = (buttonBody this label w h false)
  hbm = (buttonBody this label w h true)
  b = (new 'Trigger' nil (action selector this) nbm hbm hbm)
  setData b label
  setMorph b (newMorph b)
  setCostume (morph b) nbm
  return (morph b)
}

method buttonBody FileList label w h highlight {
  scale = (global 'scale')
  fillColor = (gray 230)
  borderColor = (gray 120)
  textColor = (gray 100)
  border = (scale * 1)
  radius = (scale * 4)
  if (true == highlight) {
    fillColor = (darker fillColor 15)
	textColor = (darker textColor 15)
  }
  bm = (newBitmap w h)
  fillRoundedRect (newShapeMaker bm) (rect 0 0 w h) radius fillColor border borderColor borderColor
  labelBM = (stringImage label 'Arial Bold' (scale * 10) textColor)
  x = ((w - (width labelBM)) / 2)
  y = ((h - (height labelBM)) / 2)
  drawBitmap bm labelBM x y
  return bm
}

method doDelete FileList {
  file = (selection (contents listPane))
  if (isNil file) {
    setText (contents contentPane) ''
  }
  if ((byteAt directoryName (count directoryName)) != (byteAt '/' 1)) {
    file = (join directoryName '/' file)
  } else {
    file = (join directoryName file)
  }
  deleteFile file

  updateShortcutSelection this
}

// Layout

method redraw FileList {
  fixLayout window
  redraw window
  fixLayout this
  fixButtonLayout this
}

method fixLayout FileList {
  packer = (newPanePacker (clientArea window))
  packPanesH packer contentPane '100%'
  packPanesH packer shortcutsPane '30%' listPane '70%'
  packPanesH packer buttonsPane '30%'
  packPanesV packer listPane '40%' contentPane '60%'
  packPanesV packer buttonsPane '10%' shortcutsPane '30%' contentPane '60%'
  finishPacking packer
}

method fixButtonLayout FileList {
  buttons = (parts (morph buttonsPane))

  r = (bounds (morph buttonsPane))
  y = (((height r) / 2) + (top r))
  extraW = (width r)
  for b buttons { extraW += (- (width b)) }
  interButtonSpace = (max 5 (extraW / ((count buttons) + 1)))

  x = (+ (left r) interButtonSpace 1)
  for b buttons {
    setLeft b x
    x += ((width b) + interButtonSpace)
    setYCenter b y
  }
}
