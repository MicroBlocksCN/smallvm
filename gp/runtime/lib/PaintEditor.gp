defineClass PaintEditor morph window saveAction canvas brushButton eraseButton bucketButton colorButton sizeButton

// To do:
//  [ ] set color (use a color swatch?)
//  [ ] set pen/eraser size
//  [ ] update pen/eraser display when size/color/mode changes
//  [ ] crop image when saving?
//  [ ] center image on canvas when editing
//  [ ] deal with rotation center
//  [ ] revert (or undo/redo?)
//  [ ] round pen
//  [ ] make system windows stay at page level when dropped on ProjectEditor
//  [ ] tweak window resize handle offset
//  [x] edit command in images tab
//  [x] save
//  [x] put in a system window

// addPart (global 'page') (morph (initialize (new 'PaintEditor')))

to openPaintEditorOn aBitmap actionOnSave {
  paintEditor = (initialize (new 'PaintEditor') aBitmap actionOnSave)
  pageM = (morph (global 'page'))
  gotoCenterOf (morph paintEditor) pageM
  addPart pageM (morph paintEditor)
  return paintEditor
}

method initialize PaintEditor originalImg actionOnSave {
  scale = (global 'scale')
  window = (window 'Interim Paint Editor')
  morph = (morph window)
  setHandler morph this
  setClipping morph true
  canvas = (initialize (new 'PaintEditorCanvas') 800 500)
  setPosition (morph canvas) (80 * scale) (35 * scale)
  addPart morph (morph canvas)
  setContents canvas originalImg
  setMinExtent morph (898 * scale) (570 * scale)
  setExtent morph (898 * scale) (570 * scale)
  addModeButtons this
  addSaveCancelButtons this
  saveAction = actionOnSave
  setMode this 'paintBrush' brushButton
  setBrushSize this (5 * scale)
  return this
}

// construction

method addModeButtons PaintEditor {
  scale = (global 'scale')
  buttonX = ((left morph) + (22 * scale))
  buttonY = ((top morph) + (35 * scale))
  dy = (50 * scale)
  brushButton = (addIconButton this buttonX buttonY 'paintBrush' (action 'setMode' this 'paintBrush'))
  buttonY += dy
  eraseButton = (addIconButton this buttonX buttonY 'eraser' (action 'setMode' this 'eraser'))
  buttonY += dy
  bucketButton = (addIconButton this buttonX buttonY 'paintBucket' (action 'setMode' this 'paintBucket'))
  buttonY += (70 * scale)
  colorButton = (addIconButton this buttonX buttonY 'chooseColor' (action 'chooseColor' this))
  buttonY += dy
  sizeButton = (addIconButton this buttonX buttonY 'brushSize' (action 'brushSizeMenu' this))
}

method addIconButton PaintEditor x y iconName action {
  scale = (global 'scale')
  size = (40 * scale)
  iconBM = (scaleAndRotate (call iconName (new 'PaintEditorIcons')) scale)
  button = (newButton '' action)
  setLabel button iconBM (gray 160) (gray 240) size size
  setPosition (morph button) x y
  addPart morph (morph button)
  return button
}

method addSaveCancelButtons PaintEditor {
  scale = (global 'scale')
  buttonX = ((right morph) - (20 * scale))
  buttonY = ((bottom morph) - (25 * scale))
  dx = (-10 * scale)

  b = (textButton this 0 0 'Save' 'saveAndClose')
  buttonX += (0 - (width (morph b)))
  setPosition (morph b) buttonX buttonY

  b = (textButton this 0 0 'Cancel' (action 'destroy' morph))
  buttonX += (dx - (width (morph b)))
  setPosition (morph b) buttonX buttonY
}

method textButton PaintEditor x y label selectorOrAction {
  if (isClass selectorOrAction 'String') {
	selectorOrAction = (action selectorOrAction this)
  }
  result = (pushButton label (gray 130) selectorOrAction)
  setPosition (morph result) x y
  addPart morph (morph result)
  return result
}

// actions

method saveAndClose PaintEditor {
  scale = (global 'scale')
  bm = (contents canvas)
  cropped = (cropTransparent bm)
  if (1 != scale) {
	cropped = (scaleAndRotate cropped (1.0 / scale))
  }
  setName cropped (name bm)
  if (notNil saveAction) { call saveAction cropped }
  removeFromOwner morph
}

method setMode PaintEditor newMode button {
  setOn brushButton false
  setOn bucketButton false
  setOn eraseButton false
  setOn button true
  setMode canvas newMode
  updateBrushButton this
}

method chooseColor PaintEditor button {
  colorPicker = (newColorPicker (action 'setPaintColor' this) (color canvas))
  addPart (global 'page') (morph colorPicker)
}

method setPaintColor PaintEditor newColor {
  setColor canvas newColor
  updateBrushButton this
}

method brushSizeMenu PaintEditor button {
  menu = (menu 'Brush size:' (action 'setBrushSize' this) true)
  for item (array 1 2 3 4 5 7 10 15 20 30 40 60 90 120 160) {
	addItem menu item
  }
  popUpAtHand menu (global 'page')
}

method setBrushSize PaintEditor newSize {
  setLineWidth (pen canvas) (2 * newSize)
  updateBrushButton this
}

method updateBrushButton PaintEditor {
  scale = (global 'scale')
  radius = (13 * scale)
  c = (color canvas)
  if ('eraser' == (mode canvas)) { c = (gray 250) }
  textColor = (gray 0)
  if ((brightness c) < 0.85) { textColor = (gray 255) }
  bm = (newBitmap (2 * radius) (2 * radius))
  drawCircle (newShapeMaker bm) radius radius radius c
  setFont 'Arial Bold' (13 * scale)
  sizeLabel = (toString (half (lineWidth (pen canvas))))
  drawString bm sizeLabel textColor (radius - (half (stringWidth sizeLabel))) (6 * scale)
  b = sizeButton
  setLabel b bm (gray 160) (gray 240) (width (morph b)) (height (morph b))
}

// drawing

method redraw PaintEditor {
  fixLayout window
  drawFrame this
}

method drawFrame PaintEditor {
  scale = (global 'scale')
  cornerRadius = (4 * scale)
  fillColor = (gray 200)
  borderW = (6 * scale)
  borderColor = (gray 80)
  w = (width morph)
  h = (height morph)
  bm = (newBitmap w h)
  pen = (newVectorPen bm)
  fillRoundedRect pen (rect 0 0 w h) cornerRadius fillColor borderW borderColor
  fillRoundedRect pen (rect 0 12 w (18 * scale)) 0 borderColor 0 borderColor
  drawCheckboard this bm
  setCostume morph bm
}

method drawCheckboard PaintEditor bm {
  squareSize = (4 * (global 'scale'))
  canvasRect = (translatedBy (bounds (morph canvas)) (- (left morph)) (- (top morph)))

  // fill with white
  fillRect bm (gray 255) (left canvasRect) (top canvasRect) (width canvasRect) (height canvasRect)

  // draw dark squares
  lineStartsDark = false
  y = (top canvasRect)
  while ((y + squareSize) <= (bottom canvasRect)) {
	isDark = lineStartsDark
	x = (left canvasRect)
	while ((x + squareSize) <= (right canvasRect)) {
	  if isDark {
		fillRect bm (gray 240) x y squareSize squareSize
	  }
	  isDark = (not isDark)
	  x += squareSize
	}
	lineStartsDark = (not lineStartsDark)
	y += squareSize
  }
}

defineClass PaintEditorCanvas morph bitmap pen paintColor mode lastX lastY undoHistory

method initialize PaintEditorCanvas w h {
  scale = (global 'scale')
  bitmap = (newBitmap (w * scale) (h * scale) (gray 250))
  morph = (newMorph this)
  setTransparentTouch morph true
  setGrabRule morph 'ignore'
  setCostume morph bitmap
  pen = (newPen bitmap)
  paintColor = (color 0 0 200)
  undoHistory = (list)
  mode = 'paintBrush'
  return this
}

method color PaintEditorCanvas { return paintColor }
method setColor PaintEditorCanvas color { paintColor = color }
method contents PaintEditorCanvas { return bitmap }
method mode PaintEditorCanvas { return mode }
method setMode PaintEditorCanvas newMode { mode = newMode }
method pen PaintEditorCanvas { return pen }

method setContents PaintEditorCanvas img {
  scale = (global 'scale')
  fill bitmap (transparent)
  if (notNil img) {
	if (1 == scale) {
	  scaled = img
	} else {
	  scaled = (scaleAndRotate img scale)
	}
	x = (max 0 (half ((width bitmap) - (width scaled))))
	y = (max 0 (half ((height bitmap) - (height scaled))))
	drawBitmap bitmap scaled x y
	setName bitmap (name img)
  }
  costumeChanged morph
}

// events

method handDownOn PaintEditorCanvas hand {
  if ('paintBucket' == mode) {
	fillArea this hand
	return true
  }
  up pen
  movePenToHand this hand
  if ('eraser' == mode) {
	setColor pen (transparent)
  } else {
	setColor pen paintColor
  }
  down pen
  focusOn hand this
  return true
}

method handMoveFocus PaintEditorCanvas hand {
  movePenToHand this hand
}

method movePenToHand PaintEditorCanvas hand {
  p = (normal morph (x hand) (y hand))
  newX = (toInteger ((first p) + ((normalWidth morph) / 2)))
  newY = (toInteger ((last p) + ((normalHeight morph) / 2)))
  goto pen newX newY
  costumeChanged morph
}

method fillArea PaintEditorCanvas hand {
  p = (normal morph (x hand) (y hand))
  seedX = (toInteger ((first p) + ((normalWidth morph) / 2)))
  seedY = (toInteger ((last p) + ((normalHeight morph) / 2)))
  floodFill bitmap seedX seedY paintColor
  costumeChanged morph
}

defineClass PaintEditorIcons

method chooseColor PaintEditorIcons {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABUAAAASCAYAAAC0EpUuAAAAAXNSR0IArs4c6QAAAVlpVFh0WE1MOmNv
bS5hZG9iZS54bXAAAAAAADx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9
IlhNUCBDb3JlIDUuNC4wIj4KICAgPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8x
OTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICAgICAgPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9
IiIKICAgICAgICAgICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFkb2JlLmNvbS90aWZmLzEuMC8iPgog
ICAgICAgICA8dGlmZjpPcmllbnRhdGlvbj4xPC90aWZmOk9yaWVudGF0aW9uPgogICAgICA8L3JkZjpE
ZXNjcmlwdGlvbj4KICAgPC9yZGY6UkRGPgo8L3g6eG1wbWV0YT4KTMInWQAAAilJREFUOBGFlItOwzAM
Rd2tMBggHkLw/5/BDyHWPQpsLWzQlnOdhL1BmyU3cU99bSdZ+/zU2o3Z8szs1dY2t9w6u2aFTTf8RT8E
lCy9mZ1/mEfcxohLa3wjt+XYrPW/LVlaYHqndGiHd4INzTr8b1xA9o5NWK3NMlzysUus45fZijc/C9MH
4P5CZ/gTYC3bDvR8gH7xCMihU7OrudmARwG1JawF6MihSvwTI84zHdkp0HOeVIIVtpMp0BWSBJR8idiA
7mdKvI0R1TjwnidB0bIjvyFQQFUkQKVX8ndqmjIN0DuCKg/cqilNUk077AE3QfdqmuSrUappgfTGHvEi
dFO+oGSZIVJugh6VnzIt7AKohuwAVN0HmgOVuw89Kr/+FzpgGg9CPyoyYUxqPqecZCpBhdzGPT0R0GAV
w58CWF7gh9iwXBPXx/JxlDJhgt+ZZEnZnLkwmJShoSslQ6d4nRKaoD7I1ZIOzJhP9ClZXkTo9DQUnXx8
PNTJgFdqgqJ1xq6KroGOpzDNdmhuFaFxPCYoO9TJIIwdQcuodydTlUCZFi7/bZ1pifTjUF5pkT+jRn9k
OkRCT7eG15T4V+SoppKvmgb5OklRfsv8TDm2SutApjqFAzrSU01fYk0XkORuz5zwEdoBLCn8kUwlv88R
zQT1TLlqar4u+alR6XT8dr/jCiyxBI3d32xUh0aHevd7NBRaynRfPjANw5yrMMmP3VcltKRL8ou5EfQH
SfiMVe7b97UAAAAASUVORK5CYII='
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method eraser PaintEditorIcons {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABkAAAASCAYAAACuLnWgAAAAAXNSR0IArs4c6QAAAVlpVFh0WE1MOmNv
bS5hZG9iZS54bXAAAAAAADx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9
IlhNUCBDb3JlIDUuNC4wIj4KICAgPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8x
OTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICAgICAgPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9
IiIKICAgICAgICAgICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFkb2JlLmNvbS90aWZmLzEuMC8iPgog
ICAgICAgICA8dGlmZjpPcmllbnRhdGlvbj4xPC90aWZmOk9yaWVudGF0aW9uPgogICAgICA8L3JkZjpE
ZXNjcmlwdGlvbj4KICAgPC9yZGY6UkRGPgo8L3g6eG1wbWV0YT4KTMInWQAAASxJREFUOBGdVCGShDAQ
HE7lHBKLRCJjkUgkFolEYpFIvoDkCfyHHxxujoYim90qkslOFQVFetLT05NEFByKQ1K0zkPgRHVdc1EU
LA0ixWma8o+UJo5j3raN1nUVpUTRLzH/UZIkIjxprbltW6mAEztN04nPsszfXhDkeS4mOCrnYRgMHh1w
SgGg6zqT4PsAwbIsBgYVSjkGpaqqIJMxEE3TGIK+7xl7PKqAgtApGsfxjQCT9UgAD0JahGJsgrIszwIf
CZAAEmnAA7sgTBT+PRLAJHsqfETYbJ5nA0P/nQSoHj2UBlryaTK68KjgMggmyR9bAdrlNPliliuAUlvx
PeYOBffSdyQ4dLj87l0873ASnOLLR8/Wr+VwEtGl9yKgSGCaBT/Qimjf9yNPHv8WUzPBF5/BMAAAAABJ
RU5ErkJggg=='
  return (readFrom (new 'PNGReader') (base64Decode data))
}


method paintBrush PaintEditorIcons {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABsAAAARCAYAAAAsT9czAAAAAXNSR0IArs4c6QAAAVlpVFh0WE1MOmNv
bS5hZG9iZS54bXAAAAAAADx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9
IlhNUCBDb3JlIDUuNC4wIj4KICAgPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8x
OTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICAgICAgPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9
IiIKICAgICAgICAgICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFkb2JlLmNvbS90aWZmLzEuMC8iPgog
ICAgICAgICA8dGlmZjpPcmllbnRhdGlvbj4xPC90aWZmOk9yaWVudGF0aW9uPgogICAgICA8L3JkZjpE
ZXNjcmlwdGlvbj4KICAgPC9yZGY6UkRGPgo8L3g6eG1wbWV0YT4KTMInWQAAAP9JREFUOBHNVD0PgyAQ
xcahY9nsqBtu7ebaEX+vbP0LXd1krBsdu9k+kzOINC2GNF5C4A7u3ruPkLBIIqUc2lvLunu3iFjXNTPG
LOyrDADKs3zwCe6wVgV2nTYBdBLiPxmhpNFKB9afehQdCGA+2RRQ6k6XrYOprT/M01anc3EsmDgLppRK
JmPIwVcq2Fw79F+HwcsEGfl+ApA9lyWjDLM8Y5zzuBnRMIAEraqqZiUOqdr4Vl4kxV3sBEJ7cPC3w46c
wLS5NqTOdgxADBl7Bra+HrkgmDj87LrX3l5/I5QCCI/cwLYjBqHX/WhaCwTn9MD303TZAO4ZIFpp1xyk
vwDHG1SI5cichgAAAABJRU5ErkJggg=='
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method paintBucket PaintEditorIcons {
  data = '
iVBORw0KGgoAAAANSUhEUgAAABYAAAAZCAYAAAA14t7uAAAAAXNSR0IArs4c6QAAAVlpVFh0WE1MOmNv
bS5hZG9iZS54bXAAAAAAADx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9
IlhNUCBDb3JlIDUuNC4wIj4KICAgPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8x
OTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4KICAgICAgPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9
IiIKICAgICAgICAgICAgeG1sbnM6dGlmZj0iaHR0cDovL25zLmFkb2JlLmNvbS90aWZmLzEuMC8iPgog
ICAgICAgICA8dGlmZjpPcmllbnRhdGlvbj4xPC90aWZmOk9yaWVudGF0aW9uPgogICAgICA8L3JkZjpE
ZXNjcmlwdGlvbj4KICAgPC9yZGY6UkRGPgo8L3g6eG1wbWV0YT4KTMInWQAAAO5JREFUSA2t1dsOwiAM
BmAwu8D3f1h3h6vwh1LbUqYkhqNfC26Y07KUOpacebR/anGUINm/hVuINT4Heczd//U24Vi2lN4GXGqt
r/CWgrBE15kHYImm1DL38cPf2zeK9YTn/DSfcTfj1ZnO87QDfMwfz84UGaOecYyWqmS8Rq8jgPCpNVy8
+z5KIBDeRhQekGXso/iyVyMorekZx1FkxREEw1yH4ygAreYozbOj0JbHxho639UXfGYZLca1VRpKMz3j
e7iFMpiae7iHCjiOr1AFXuMR1IBtPIrSsZLiFHrGW4n9Q/t3tAg0rkIx4Xbf1i9wePyJEZEAAAAASUVO
RK5CYII='
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method brushSize PaintEditorIcons {
  bm = (newBitmap 26 26)
  drawCircle (newShapeMaker bm) 13 13 13 (gray 80)
  return bm
}
