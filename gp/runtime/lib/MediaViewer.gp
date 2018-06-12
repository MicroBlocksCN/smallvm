// MediaViewer.gp - Media and Notes viewer for use in ProjectEditor

defineClass MediaViewer morph project type listFrame notesFrame resizer

method type MediaViewer { return type }

to newMediaViewer aProject viewerType {
  return (initialize (new 'MediaViewer') aProject viewerType)
}

method initialize MediaViewer aProject viewerType {
  scale = (global 'scale')
  project = aProject
  type = viewerType
  morph = (newMorph this)
  if ('Images' == viewerType) {
	addImportButton this 'image'
	addPaintButton this
	addMediaList this (images project)
  } ('Sounds' == viewerType) {
	addImportButton this 'sound'
	addMediaList this (sounds project)
  } ('Notes' == viewerType) {
	addNotes this
  }
  setMinExtent morph (scale * 235) (scale * 200)
  resizer = (resizeHandle this 'horizontal')
  return this
}

// notes

method saveNotes MediaViewer {
  if (notNil notesFrame) {
    setNotes project (contentsWithoutCRs (contents notesFrame))
  }
}

method redraw MediaViewer {
  fillColor = (gray 220)
  borderColor = (gray 150)
  borderWidth = (2 * (global 'scale'))
  bm = (newBitmap (width morph) (height morph) fillColor)
  outlineRectangle (newShapeMaker bm) (rect 0 0 (width morph) (height morph)) borderWidth borderColor
  setCostume morph bm
  fixLayout this
}

method addImportButton MediaViewer mediaType {
  if ('Browser' == (platform)) { return } // import on browser is via drag-n-drop
  scale = (global 'scale')
  label = (join 'Add ' mediaType ' from file')
  btn = (pushButton label (gray 120) (action 'importMediaFile' this mediaType))
  setPosition (morph btn) (12 * scale) (15 * scale)
  addPart morph (morph btn)
}

method addPaintButton MediaViewer {
  scale = (global 'scale')
  label = (join 'Paint new image')
  btn = (pushButton label (gray 120) (action 'openPaintEditor' this))
  setPosition (morph btn) (140 * scale) (15 * scale)
  if ('Browser' == (platform)) { setPosition (morph btn) (12 * scale) (15 * scale) }
  addPart morph (morph btn)
}

method addMediaList MediaViewer mediaItems {
  menuIcon = (menuIcon this)
  soundIcon = (soundIcon this)
  listFrame = (scrollFrame (newBox) (gray 240))
  contentsM = (morph (contents listFrame))
  setExtent contentsM 0 0
  for el mediaItems {
	item = (intialize (new 'MediaItem') el menuIcon soundIcon)
	addPart contentsM (morph item)
  }
  fixLayout this
  addPart morph (morph listFrame)
}

method addNotes MediaViewer {
  scale = (global 'scale')
  textBox = (newText '' 'Arial' (18 * scale))
  setEditRule textBox 'editable'
  setGrabRule (morph textBox) 'ignore'
  setBorders textBox 10 10
  notesFrame = (scrollFrame textBox (gray 235))
  setPosition (morph notesFrame) (10 * scale) (10 * scale)
  setExtent (morph notesFrame) 500 800
  setText textBox (notes project)
  addPart morph (morph notesFrame)
}

method importMediaFile MediaViewer mediaType {
  editor = (projectEditor this)
  if (notNil editor) { importMediaFile editor mediaType }
}

method textChanged MediaViewer txt {
  if (notNil notesFrame) {
	rightMargin = (5 * (global 'scale'))
	wrapLinesToWidth (contents notesFrame) (max 100 ((width (morph notesFrame)) - rightMargin))
	saveNotes this
  }
  itemM = (ownerThatIsA (morph txt) 'MediaItem')
  if (notNil itemM) { // edit name of a media item
	item = (item (handler itemM))
	setName item (text txt)
  }
}

// editors

method openPaintEditor MediaViewer {
  editor = (projectEditor this)
  if (isNil editor) { return }
  openPaintEditorOn origImg (action 'saveEditedImage' editor)
}

method projectEditor MediaViewer {
  editor = (ownerThatIsA morph 'ProjectEditor')
  if (isNil editor) { return nil }
  return (handler editor)
}

// layout

method fixLayout MediaViewer {
  scale = (global 'scale')
  border = (2 * scale)
  rightMargin = (5 * scale)

  if (notNil resizer) {
	setRight (morph resizer) ((right morph) - border)
	setBottom (morph resizer) ((bottom morph) - border)
	addPart morph (morph resizer) // bring to front
  }
  if (notNil listFrame) {
	  m = (morph listFrame)
	  setInsetInOwner m border (40 * scale)
	  setExtent m ((right morph) - ((left m) + border)) ((bottom morph) - ((top m) + border))
	  fixListItemLayout this
  }
  if (notNil notesFrame) {
	  m = (morph notesFrame)
	  setInsetInOwner m border border
	  setExtent m ((right morph) - ((left m) + border)) ((bottom morph) - ((top m) + border))
	  wrapLinesToWidth (contents notesFrame) (max 100 ((width m) - rightMargin))
  }
  if (notNil (morph resizer)) {
	size = (10 * scale)
    setLeft (morph resizer) ((right morph) - border)
    setTop (morph resizer) (top morph)
    setExtent (morph resizer) size (height morph)
    drawPaneResizingCostumes resizer
  }
  editor = (projectEditor this)
  if (notNil editor) { fixLayout editor }
}

method fixListItemLayout MediaViewer {
  itemWidth = (max 100 (width (morph listFrame)))
  listContents = (morph (contents listFrame))
  y = (top listContents)
  for itemM (parts listContents) {
	setItemWidth (handler itemM) itemWidth
	setPosition itemM (left listContents) y
	y += ((height (fullBounds itemM)) + 5)
  }
  updateSliders listFrame
}

method menuIcon MediaViewer {
  data = '
AAAAAAAAAAAAAgMAAAc/e6zP7f397c+sej8HAAADAgAAAAAAAAAAAAAAAAAAAAAABQAAKYzd///////9
/f//////3YwpAAAFAAAAAAAAAAAAAAAAAAACAgAZl/v///z3+v////////r3/P//+5cZAAICAAAAAAAA
AAAAAAADAABc7v//9vv////45dzc5fj////79v//7lwAAAMAAAAAAAAAAAADAACa///3/P//0IdIIg4G
Bg4iSIfQ///89///mgAAAwAAAAAAAAADAAC1//z4//+8SQIAAAAAAAAAAAAAAkm9///4/P+1AAADAAAA
AAACAAC1//r6/+lUAAAABAQDAgICAgMEBAAAAFTp//r6/7UAAAIAAAAAAgCa//n7/8IXAAEEAQAAAAAA
AAAAAAABBAEAF8L/+/n/mgACAAAABQBc//z6/7UAAAYBAAAAAAAAAAAAAAAAAAABBgAAtf/6/P9cAAUA
AgAZ7v/4/8IAAAUAAAAAAAAAAAAAAAAAAAAAAAAFAADC//j/7hkAAgMAl//3/+kXAAUBAwMDAwMDAwMD
AwMDAwMDAwMDAgUAF+n/9/+XAAMAKPv//P9UAAYAAAAAAAAAAAAAAAAAAAAAAAAAAAAABwBU//z/+ykA
AIv/9v+9AAECAGOajpGQkJCQkJCQkJCQkJCQkJKMFgADAL3/9v+MAAfd//v/SQAEAgC5////////////
/////////////ykABwBJ//v/3Qc///z/0AEAAQIAuf////////////////////////8pAAQAAtD//P8/
e//3/4YABAABAGSajpGQkJCQkJCQkJCQkJCQkJKMFgABBACH//f/eqz/+v9IAAQAAAEAAAAAAAAAAAAA
AAAAAAAAAAAAAAABAAQASP/6/6zP///4IgADAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQADACL4///P
7f//5g4AAgABAGSajpGRkZGRkZGRkZGRkZGRkJOMFgABAgAO5f//7f39/9wFAAIAAgC6////////////
/////////////ykAAwEABtz//f39/f/cBgACAAIAuv////////////////////////8pAAMBAAbc//39
7f//5g4AAgABAGSajpGRkZGRkZGRkZGRkZGRkJOMFgABAgAO5v//7c////giAAMAAAEAAAAAAAAAAAAA
AAAAAAAAAAAAAAABAAMAIvj//8+s//r/SAAEAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAEj/+v+s
e//3/4YABAABAGWckJOTk5OTk5OTk5OTk5OTkpSOFgABBACH//f/e0D//P/QAQABAgC5////////////
/////////////ykABAAC0P/8/z8H3f/7/0kABAIAuf////////////////////////8pAAcASf/7/90H
AIz/9v+8AAECAGSajpGRkZGRkZGRkZGRkZGRkJKMFgADAL3/9v+MAAAo+//8/1QABgAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAHAFT//P/7KAADAJf/9//pFwAFAQMDAwMDAwMDAwMDAwMDAwMDAwIFABfp//f/lwAD
AgAZ7v/4/8IAAAUAAAAAAAAAAAAAAAAAAAAAAAAFAADC//j/7hkAAgAFAFz//Pr/tQAABgEAAAAAAAAA
AAAAAAAAAAEGAAC1//r8/1wABQAAAAIAmv/5+//CFwABBAEAAAAAAAAAAAAAAQQBABfC//v5/5oAAgAA
AAACAAC1//r6/+lUAAAABAQDAgICAgMEBAAAAFTp//r6/7QAAAIAAAAAAAMAALX//Pj//7xJAQAAAAAA
AAAAAAABSbz///j8/7UAAAMAAAAAAAAAAwAAmv//9/z//9CGSCIOBgYOIkiH0P///Pf//5oAAAMAAAAA
AAAAAAADAABc7v//9vv////45dzc5fj////79v//7lwAAAMAAAAAAAAAAAAAAAICABmX+////Pf6////
////+vf8///7lxkAAgIAAAAAAAAAAAAAAAAAAAUAACiM3f///////f3//////92LKAAABQAAAAAAAAAA
AAAAAAAAAAAAAgMAAAdAe6zP7f397c+se0AHAAADAgAAAAAAAAAAAA=='
  bm = (newBitmap 40 40)
  applyAlphaChannel bm (base64Decode data) (gray 130)
  return bm
}

method soundIcon MediaViewer {
  data = '
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAgAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB
BAAABAEAAAAAAAAAAAAAAAAAAAAAAAABBAMEAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAgAACAkAAAEAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAwAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAHrg4nsAAAEAAAAAAAAAAAAAAAAA
AAEAAGW2mB0ABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFAACk
/////2IABAAAAAAAAAAAAAAAAAAAAwB9////4BIAAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAABQAOwv/6/Pf/qwADAAAAAAAAAAAAAAAAAAIABuD/9/f/tQAAAQAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAUAJdz/+v//+/+sAAIAAAAAAAAAAAAAAAAA
AgAE2//8//r/dgAFAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEEAD3w//r/
///7/6sAAwAAAAAAAAAAAAAAAAAABABx//z//f/8KQAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAACAgBb///6//////v/rAADAAAAAAAAAAAAAQQCAwMAAACo//r/+v/AAAABAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwAAev//+///////+/+sAAMAAAAAAAAAAAEAAAAA
AAICAA3k//z/+/9jAAUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAUAAJf//vz/////
///7/6wAAwAAAAAAAAABAABqvqUoAAMFAEv//v/8/+QNAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAFAAe5//z+//////////v/rAADAAAAAAAAAAMAev///+oYAAMDAKD/+v/6/3oABAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABQAbz//6////////////+/+sAAMAAAAAAAACAALa//j3
/7QAAAQAG/H//f3/5xQAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQUANOv/+v//////////
///7/6wAAwAAAAAAAAEAANH//P/7/2YABAUAe//6//v/egAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAICAE34//r///////////////v/rAADAAAAAAAAAAQAZP/8//z/6REABAAR5//9/P/bBgACAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADAABv///7////////////////+/+sAAMAAAADBAIAAQEAp//6
//r/iwAEBAB7//v//P9UAAQAAAAAAAAAAAIEAwMDAwMDAwMDAwMDAwMDBgAAif///P//////////////
///7/6wAAwABAQAAAAIAAwAY8P/9/f/0IAAFABrw//77/68AAgAAAAAAAAADAAAAAAAAAAAAAAAAAAAA
AAAAA63//P3///////////////////v/rAACAQAALEMLAAMABQBw//v/+/+PAAMEAJv/+v7/8x8AAwAA
AAAAAQAQMS8vMDAwMDAwMDAwMC8wLjPC//v+////////////////////+/+sAAMBAIn//9wpAAMBAAbZ
//z9/+sSAAYAQf/+/vz/ZgAEAAAAAAIAV+v//f7+/v7+/v7+/v7+/v79///7////////////////////
///7/6wABgBA///5/8kAAAEEAGf//P/7/2QABgAF2f/8+/+vAAEBAAACAB35////////////////////
/////f////////////////////////v/rAAHAG3/+f/6/2EABAIAC+L//fv/vQABBACR//v9/+gSAAIA
AAQASf/6/v7+/v7+/v7+/v7+/v7+/v7/////////////////////////+/+sAAYAM////vz/1gYAAQQA
jP/6/v/2JAAHAEv//v7+/0AABAAABABI//7/////////////////////////////////////////////
///7/6wAAwMAm//6//z/XAAEAwA2///+/P9nAAYAF+v//vv/dwAFAAAEAEj//f//////////////////
//////////////////////////////v/rAACAwAh9f/++/+6AAECAATV//z7/6YAAgEAwP/7+/+nAAMA
AAQASP/9////////////////////////////////////////////////+/+sAAMAAwCW//v+//kkAAMD
AJX/+/z/2gcABQCP//r8/88AAAEABABI//3/////////////////////////////////////////////
///7/6wAAwAEADj///78/2MABAQAW//9/f/5JQAHAGP//P3/6hQAAgAEAEj//f//////////////////
//////////////////////////////v/rAADAAEAAdP//Pv/ogADAwAu/P/+/f9IAAgAQP///f/8LAAD
AAQASP/9////////////////////////////////////////////////+/+sAAMAAAQAl//7/P/QAgAD
ABDk//37/2oACAAn+//9//9DAAQABABI//3/////////////////////////////////////////////
///7/6wAAwAABQBj//v+/+wZAAMAAMz//Pr/hgAHABbu//z9/1YABAAEAEj//f//////////////////
//////////////////////////////v/rAADAAAEAD7//v7//TAABAEAtv/7+/+aAAYACuH//Pz/ZgAE
AAQASP/9////////////////////////////////////////////////+/+sAAMAAAMAKvz//f//PwAE
AwCn//v7/6cABQAF2f/8/P9wAAQABABI//3/////////////////////////////////////////////
///7/6wAAwAAAwAh9f/9/v9JAAQDAKD/+/v/rgAEAALV//z8/3YABAAEAEj//f//////////////////
//////////////////////////////v/rAADAAADACH2//3+/0gABAMAoP/7+/+tAAQAAtX//Pz/dgAE
AAQASP/9////////////////////////////////////////////////+/+sAAMAAAMALP3//f//PgAE
AgCp//v7/6UABQAF2v/8/P9vAAQABABI//3/////////////////////////////////////////////
///7/6wAAwAABABC//7+//stAAMBALn/+/v/mAAGAAzj//z8/2QABAAEAEj//f//////////////////
//////////////////////////////v/rAADAAAFAGn/+/3/6RUAAwABz//8+v+DAAcAGO///P3/VAAE
AAQASP/9////////////////////////////////////////////////+/+sAAMAAAQAn//7/P/KAAAD
ABPo//37/2YACAAq/f/9//9AAAQABABI//3/////////////////////////////////////////////
///7/6wAAwACAAba//36/5sAAwMAMv7//v7/RAAIAET//v3/+ykAAwAEAEj//f//////////////////
//////////////////////////////v/rAADAAQARP///vz/WQAEBABj//39//YgAAcAaf/8/f/nEAAC
AAQASP/9////////////////////////////////////////////////+/+sAAMAAwCl//v9//QcAAMC
AJ7/+/z/1QMABQCV//r8/8sAAAEABABH//3/////////////////////////////////////////////
///7/6wAAgQAL/7//vv/rgACAgAJ3f/8+/+eAAMAAMb//Pv/oQADAAAEAEv//f//////////////////
//////////////////////////////v/rAADAQCv//v//f9NAAQEAED//v79/10ABwAc8P/++/9wAAUA
AAMANf/9+fv6+vr6+vr6+vr6+vr6+vv/////////////////////////+/+sAAYAN/////v/yQAAAQQA
mP/6/v/xHQAHAFT//f7//zoABAAAAQAApP////////////////////////7+////////////////////
///7/6wABwBV//n8+/9NAAQCABXs//37/7IAAgMAnP/7/P/hDAACAAAAAQACYI+LjIyMjIyMjIyMjIyM
jYar///8//////////////////////v/rAAFABfw////tAABAAQAdv/8//z/WAAGAArg//z7/6cAAgAA
AAAAAQAAAAAAAAAAAAAAAAAAAAAAAABw///7////////////////////+/+sAAIDAD7L5qcRAAICABDm
//38/+AJAAYATP/9/v3/WwAEAAAAAAAAAQQEBAQEBAQEBAQEBAQEBAQFAgBX/v/6////////////////
///7/6wAAwACAAAPAAACAAUAgv/6//v/gAAEAwCn//v+/+0YAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAABBAA16//5//////////////////v/rAADAAADAAACAgAEACj7//79/+kVAAUAJfj//vr/owADAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABQAh2P/6////////////////+/+sAAMAAAABAgAAAQAAvf/7
//r/eQAEBACL//v//f9HAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABQAKuv/7/v//////////
///7/6wAAwAAAAAAAAAEAHP/+//7/9sGAAQAG/H//fz/0QAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAABQAAoP///f////////////v/rAADAAAAAAAAAQAAyP/8//z/UAAEBACN//r//P9qAAQAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAfv//+///////////+/+sAAMAAAAAAAAAAgC2//b4
/58AAgQAKPr//vz/3QsAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgEAYf//+v//////
///7/6wAAwAAAAAAAAADADn1///MCQADAQC1//v/+/9oAAUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAQQAQ/X/+v////////v/rAADAAAAAAAAAAACACV4aAwAAgUAXv/8//z/1wMAAQAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAUAKN7/+v//////+/+sAAMAAAAAAAAAAAACAAAA
AAIDAB3y//3//f9QAAUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAUAE8j/+/7/
///7/6wAAwAAAAAAAAAAAAADBQUBAQAAvv/6//r/rgACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAUAAqr//f3///v/qwADAAAAAAAAAAAAAAAAAAADAH//+v/8//AaAAMAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAIz///z/+/+uAAIAAAAAAAAAAAAAAAAA
AQAA0P/8//v/XwAFAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMAAG7/
//n1/50ABAAAAAAAAAAAAAAAAAABAQC7//b5/54AAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAIDAE35///4MQADAAAAAAAAAAAAAAAAAAADADv1///BBAACAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEEACqNjiwAAgAAAAAAAAAAAAAAAAAA
AAACACJxXgcAAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAE
AAAAAAIAAAAAAAAAAAAAAAAAAAAAAAACAAAAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAADBAQDAAAAAAAAAAAAAAAAAAAAAAAAAAADBQUBAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=='
  bm = (newBitmap 80 80)
  applyAlphaChannel bm (base64Decode data) (gray 90)
  return bm
}

defineClass MediaItem morph item menuButton

method item MediaItem { return item }

method intialize MediaItem imageOrSound menuIcon soundIcon {
  // scale = (global 'scale')
  morph = (newMorph this)
  item = imageOrSound
  addThumbnail this soundIcon
  addMenuButton this menuIcon
  addNameLine this
  addDetailsLine this
  return this
}

method addThumbnail MediaItem soundIcon {
  scale = (global 'scale')
  if (isClass item 'Sound') {
	if (isNil soundIcon) { return }
	thumbnail = soundIcon
  } else {
	thumbnail = (thumbnail item 80 80)
  }
  m = (newMorph)
  setCostume m thumbnail
  if (isClass item 'Sound') {
	setHandler m (new 'Trigger' m (action 'toggleSound' this))
	setTransparentTouch m true
  } (isClass item 'Bitmap') {
	setHandler m (new 'Trigger' m (action 'setImage' this))
	setTransparentTouch m true
  }
  if (scale != 2) { setScale m (scale / 2) }
  setPosition m (10 * scale) (10 * scale)
  addPart morph m
}

method addNameLine MediaItem {
  scale = (global 'scale')
  fontSize = (15 * scale)
  textBox = (newText (name item) 'Arial' fontSize)
  setEditRule textBox 'line'
  setPosition (morph textBox) (60 * scale) (14 * scale)
  addPart morph (morph textBox)
}

method addDetailsLine MediaItem {
  scale = (global 'scale')
  fontSize = (11 * scale)
  if (isClass item 'Bitmap') {
	byteCount = (byteCount (pixelData item))
	details = (join '' (width item) 'x' (height item))
  } (isClass item 'Sound') {
	byteCount = (4 * (count (samples item)))
	secs = ((count (samples item)) / (samplingRate item))
	details = (join (toString secs 2) ' seconds')
  } else {
	byteCount = 0
	details = ''
  }
  if (byteCount < 1000) {
	sizeString = (join '  (' byteCount ' bytes)')
  } else {
	sizeString = (join '  (' (round (byteCount / 1000)) ' kb)')
  }
  if (isClass item 'Sound') {
	rate = (truncate ((samplingRate item) / 1000))
	sizeString = (join sizeString ' ' rate 'k')
  }
  line1 = (newText (join details sizeString) 'Arial' fontSize)
  setEditRule line1 'static'
  setPosition (morph line1) (61 * scale) (32 * scale)
  addPart morph (morph line1)
}

// thumbnail click actions

method toggleSound MediaItem {
  if (not (isClass item 'Sound')) { return }
  mixer = (soundMixer (global 'page'))
  if (isPlaying mixer item) {
	removeSound mixer item
  } else {
	addSound mixer item
  }
}

method setImage MediaItem {
  if (not (isClass item 'Bitmap')) { return }
  editor = (projectEditor this)
  if (isNil editor) { return nil }
  scripter = (scripter editor)
  if (and (notNil scripter) (notNil (targetObj scripter))) {
	m = (morph (targetObj scripter))
	p = (rotationCenter m)
	penWasDown = (isPenDown m)
	if penWasDown { penUp m }
	setCostume m item
	placeRotationCenter m (first p) (last p)
	if penWasDown { penDown m }
  }
}

// menu

method addMenuButton MediaItem soundIcon {
  scale = (global 'scale')
  menuButton = (new 'Trigger' (newMorph) (action 'contextMenu' this))
  setHandler (morph menuButton) menuButton
  m = (morph menuButton)
  setTransparentTouch m true
  setCostume m soundIcon
  if (scale != 2) { setScale m (scale / 2) }
  setPosition m (200 * scale) (10 * scale)
  addPart morph m
}

method contextMenu MediaItem {
  menu = (menu nil this)
  if (isClass item 'Bitmap') {
  	addItem menu 'edit' 'editItem'
  }
  addItem menu 'export' 'export'
  addLine menu
  addItem menu 'delete' 'delete'
  popUpAtHand menu (global 'page')
}

method editItem MediaItem {
  editor = (projectEditor this)
  if (isNil editor) { return }
  if (isClass item 'Bitmap') {
	openPaintEditorOn item (action 'saveEditedImage' editor)
  }
}

method export MediaItem {
 if (isClass item 'Bitmap') {
	fName = (fileToWrite (name item) '.png')
	if ('' == fName) { return }

	ppi = (prompt (global 'page') 'Pixels per inch:' '100')
	if ('' == ppi) { ppi = '100' }

	data = (encodePNG item (toInteger ppi))
	if (not (endsWith fName '.png')) { fName = (join fName '.png') }
	writeFile fName data
  } (isClass item 'Sound') {
	fName = (fileToWrite (name item) '.wav')
	if ('' == fName) { return }

	if (not (endsWith fName '.wav')) { fName = (join fName '.wav') }
	writeFile fName (encodeWAV item)
  }
}

method delete MediaItem {
  editor = (projectEditor this)
  if (isNil editor) { return }
  if (isClass item 'Bitmap') { remove (images (project editor)) item }
  if (isClass item 'Sound') { remove (sounds (project editor)) item }
  refreshTab editor
}

method projectEditor MediaItem {
  editor = (ownerThatIsA morph 'ProjectEditor')
  if (isNil editor) { return nil }
  return (handler editor)
}

// layout

method setItemWidth MediaItem newWidth {
  // Set my bounds width and update my menu button position.
  // Called when MediaList layout changes.
  scale = (global 'scale')
  setExtent morph newWidth nil
  m = (morph menuButton)
  setPosition m ((right morph) - ((width m) + (18 * scale))) (top m)
}
