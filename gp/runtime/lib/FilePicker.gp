// FilePicker.gp - Dialog box for specifying files for opening or saving.

defineClass FilePicker morph window folderReadout listPane parentButton newFolderButton nameLabel nameField cancelButton okayButton topDir currentDir action forSaving extensions isDone answer

to pickFileToOpen anAction defaultPath extensionList {
  // Pick an existing file to open starting at defaultPath, if provided. If anAction is not
  // nil, invoke it on the full path of the choosen file. If it is nil, wait synchronously
  // until a file is chosen and return its full path, or the empty string if no file is chosen.

  return (pickFile anAction defaultPath extensionList false)
}

to fileToWrite defaultPath extensionList {
  // Ask the user to enter a file name and location for writing. If provided, defaultPath is
  // offered as a starting point. Wait synchronously until a file is specified and return its
  // full path, or the empty string if the user cancels the operation.

  if (and (isClass extensionList 'String') (notNil defaultPath) ((count defaultPath) > 0)) {
	// there is a single extension and the default path is not nil or empty
	extension = extensionList
	if (not (endsWith defaultPath extension)) {
	  // addpend the extension to the default path
	  defaultPath = (join defaultPath extension)
	}
  }
  return (pickFile nil defaultPath extensionList true)
}

to pickFile anAction defaultPath extensionList saveFlag {
  if (isNil saveFlag) { saveFlag = false }
  page = (global 'page')
  picker = (initialize (new 'FilePicker') anAction defaultPath extensionList saveFlag)
  addPart page picker
  pickerM = (morph picker)
  setPosition pickerM (half ((width page) - (width pickerM))) (40 * (global 'scale'))

  if (and saveFlag (isNil anAction)) {
	// modal version -- waits until done and returns result or nil
    setField (hand page) 'lastTouchTime' nil
    while (not (isDone picker)) { doOneCycle page }
    destroy pickerM
    return (answer picker)
  }
}

// function to return the user's GP folder

to gpFolder {
  if ('iOS' == (platform)) { return '.' }
  path = (userHomePath)

  hidden = (global 'hideFolderShortcuts')
  if (and (notNil hidden) (contains hidden 'GP')) { return '/' } // if GP hidden, use computer

  // Look for <home>/Documents
  if (contains (listDirectories path) 'Documents') {
	path = (join path '/Documents')
  }
  if (not (contains (listDirectories path) 'GP')) {
	// create the GP folder if it does not already exist
	makeDirectory (join path '/GP')
  }
  if (contains (listDirectories path) 'GP') {
	path = (join path '/GP')
  }
  return path
}

to gpExamplesFolder {
  return (join (absolutePath '.') '/Examples')
}

// support for synchronous ("modal") calls

method destroyedMorph FilePicker { isDone = true }
method isDone FilePicker { return isDone }
method answer FilePicker { return answer }

// initialization

method initialize FilePicker anAction defaultPath extensionList saveFlag {
  if (isNil defaultPath) { defaultPath = (absolutePath '.') }
  if (isNil saveFlag) { saveFlag = false }
  scale = (global 'scale')

  forSaving = saveFlag
  if forSaving {
	title = 'File Save'
  } else {
	title = 'File Open'
  }
  window = (window title)
  morph = (morph window)
  setHandler morph this
  setClipping morph true
  clr = (gray 250)

  action = anAction
  extensions = extensionList
  topDir = ''
  isDone = false
  answer = ''

  lbox = (listBox (array) nil (action 'fileOrFolderSelected' this) clr)
  onDoubleClick lbox (action 'fileOrFolderDoubleClicked' this)
  setFont lbox 'Arial' 16
  listPane = (scrollFrame lbox clr)
  addPart morph (morph listPane)
  setGrabRule (morph listPane) 'ignore'

  addShortcutButtons this
  addFolderReadoutAndParentButton this
  if forSaving { addFileNameField this (filePart defaultPath) }
  okayButton = (textButton this 0 0 'Okay' 'okay')
  cancelButton = (textButton this 0 0 'Cancel' (action 'destroy' morph))

  setMinExtent morph (460 * scale) (366 * scale)
  setExtent morph (460 * scale) (366 * scale)

  if forSaving {
	defaultPath = (directoryPart defaultPath)
	if (isEmpty defaultPath) { defaultPath = (gpFolder) }
	if ('Browser' == (platform)) { defaultPath = 'Downloads' }
  }
  if (and ((count defaultPath) > 1) (endsWith defaultPath '/')) {
	defaultPath = (substring defaultPath 1 ((count defaultPath) - 1))
  }
  showFolder this defaultPath true
  return this
}

method addFolderReadoutAndParentButton FilePicker {
  scale = (global 'scale')
  x = (110 * scale)
  y = (32 * scale)

  folderReadout = (newText 'Folder Readout')
  setFont folderReadout 'Arial Bold' (16 * scale)
  setGrabRule (morph folderReadout) 'ignore'
  setPosition (morph folderReadout) x y
  addPart morph (morph folderReadout)

  parentButton = (textButton this 0 0 '<' 'parentFolder')
  parentButtonM = (morph parentButton)
  setTop parentButtonM (y + (3 * scale))
  setLeft parentButtonM (x - ((width parentButtonM) + (13 * scale)))
  addPart morph parentButtonM
}

method addFileNameField FilePicker defaultName {
  scale = (global 'scale')
  x = (110 * scale)
  y = (32 * scale)

  // name label
  nameLabel = (newText 'File name:')
  setFont nameLabel 'Arial Bold' (15 * scale)
  setGrabRule (morph nameLabel) 'ignore'
  addPart morph (morph nameLabel)

  // name field
  border = (2 * scale)
  nameField = (newText defaultName)
  setFont nameField 'Arial' (15 * scale)
  setBorders nameField border border true
  setEditRule nameField 'line'
  setGrabRule (morph nameField) 'ignore'
  nameField = (scrollFrame nameField (gray 250) true)
  setExtent (morph nameField) (213 * scale) (18 * scale)
  addPart morph (morph nameField)
}

method addShortcutButtons FilePicker {
  scale = (global 'scale')
  hidden = (global 'hideFolderShortcuts')
  if (isNil hidden) { hidden = (array) }

  showGP = (and
	(not (contains hidden 'GP'))
	('Browser' != (platform)))
  showExamples = (and
	(not (contains hidden 'Examples'))
	(not forSaving)
	(isClass extensions 'Array')
	(contains extensions '.gpp'))
  showDesktop = (not (contains hidden 'Desktop'))
  showDownloads = (and
	(not (contains hidden 'Downloads'))
	('Linux' != (platform)))
  showcComputer = (not (contains hidden 'Computer'))

  buttonX = ((left morph) + (22 * scale))
  buttonY = ((top morph) + (55 * scale))
  dy = (60 * scale)
  if showGP {
	addIconButton this buttonX buttonY 'gpFolderIcon' (action 'setGPFolder' this) 'GP'
	buttonY += dy
  }
  if showExamples {
	addIconButton this buttonX buttonY 'examplesIcon' (action 'setExamples' this)
	buttonY += dy
  }
  if (not (isOneOf (platform) 'Browser' 'iOS')) {
	if showDesktop {
	  addIconButton this buttonX buttonY 'desktopIcon' (action 'setDesktop' this)
	  buttonY += dy
	}
	if showDownloads {
	  addIconButton this buttonX buttonY 'downloadsIcon' (action 'setDownloads' this)
	  buttonY += dy
	}
	if showcComputer {
	  addIconButton this buttonX buttonY 'computerIcon' (action 'setComputer' this)
	  buttonY += dy
	}
  }
  newFolderButton = (textButton this (buttonX + (2 * scale)) buttonY 'New Folder' 'newFolder')
}

method addIconButton FilePicker x y iconName anAction label {
  if (isNil label) {
	s = iconName
	if (endsWith s 'Icon') { s = (substring s 1 ((count s) - 4)) }
	s = (join (toUpperCase (substring s 1 1)) (substring s 2))
	label = s
  }
  scale = (global 'scale')
  iconBM = (scaleAndRotate (call iconName (new 'FilePickerIcons')) (0.75 * scale))
  bm = (newBitmap (62 * scale) (40 * scale))
  drawBitmap bm iconBM (half ((width bm) - (width iconBM))) 0
  setFont 'Arial Bold' (12 * scale)
  labelX = (half ((width bm) - (stringWidth label)))
  labelY = ((height bm) - (fontHeight))
  drawString bm label (gray 0) labelX labelY

  button = (newButton '' anAction)
  setLabel button bm (gray 225) (gray 245)
  setPosition (morph button) x y
  addPart morph (morph button)
  return button
}

method textButton FilePicker x y label selectorOrAction {
  if (isClass selectorOrAction 'String') {
	selectorOrAction = (action selectorOrAction this)
  }
  result = (pushButton label (gray 130) selectorOrAction)
  setPosition (morph result) x y
  addPart morph (morph result)
  return result
}

// actions

method setComputer FilePicker {
  showFolder this '/' true
}

method setDesktop FilePicker {
  showFolder this (join (userHomePath) '/Desktop') true
}

method setDownloads FilePicker {
  showFolder this (join (userHomePath) '/Downloads') true
}

method setExamples FilePicker {
  showFolder this (gpExamplesFolder) true
}

method setGPFolder FilePicker {
  showFolder this (gpFolder) true
}

method parentFolder FilePicker {
  i = (lastIndexOf (letters currentDir) '/')
  if (isNil i) { return }
  newPath = (substring currentDir 1 (i - 1))
  showFolder this newPath false
}

method showFolder FilePicker path isTop {
  currentDir = path
  if isTop { topDir = path }
  setText folderReadout (filePart path)
  newContents = (list)
  for dir (sorted (listDirectories currentDir)) {
	if (not (beginsWith dir '.')) {
	  add newContents (join '[ ] ' dir)
	}
  }
  for fn (sorted (listFiles currentDir)) {
	if (not (beginsWith fn '.')) {
	  if (or (isNil extensions) (hasExtension fn extensions)) {
		add newContents fn
	  }
	}
  }
  updateParentAndNewFolderButtons this
  setCollection (contents listPane) newContents
}

method newFolder FilePicker {
  newFolderName = (prompt (global 'page') 'Folder name?')
  if ('' == newFolderName) { return }
  for ch (letters newFolderName) {
	if (isOneOf ch '.' '/' '\' ':') { error 'Bad folder name' }
  }
  newPath = (join currentDir '/' newFolderName)
  makeDirectory newPath
  showFolder this newPath false
}

method okay FilePicker {
  answer = ''
  if forSaving {
	answer = (join currentDir '/' (text (contents nameField)))
  } else {
	sel = (selection (contents listPane))
	if (and (notNil sel) (not (beginsWith sel '[ ] '))) {
	  answer = (join currentDir '/' sel)
	}
  }
  if (and (notNil action) ('' != answer)) { call action answer }
  isDone = true
  removeFromOwner morph
}

method fileOrFolderSelected FilePicker {
  sel = (selection (contents listPane))
  if (beginsWith sel '[ ] ') {
	sel = (substring sel 5)
	if (or (endsWith sel ':')) {
	  showFolder this sel true
	} else {
	  showFolder this (join currentDir '/' sel) false
	}
  }
}

method fileOrFolderDoubleClicked FilePicker {
  sel = (selection (contents listPane))
  if (beginsWith sel '[ ] ') {
	sel = (substring sel 5)
	if (or (endsWith sel ':')) {
	  showFolder this sel true
	} else {
	  showFolder this (join currentDir '/' sel) false
	}
  } else { // file selected
	if (not forSaving) {
	  if (notNil action) { call action (join currentDir '/' sel) }
	  removeFromOwner morph
	}
  }
}

method updateParentAndNewFolderButtons FilePicker {
  // parent button
  if (and (beginsWith currentDir topDir) ((count currentDir) > (count topDir))) {
	show (morph parentButton)
  } else {
	hide (morph parentButton)
  }

  // new folder button
  if (notNil newFolderButton) {
	if (and forSaving
			('Browser' != (platform))
			(not (contains (splitWith currentDir '/') 'runtime'))
			(currentDir != '/')
	) {
	  show (morph newFolderButton)
	} else {
	  hide (morph newFolderButton)
	}
  }
}

// Layout

method redraw FilePicker {
  scale = (global 'scale')
  fixLayout window
  redraw window
  topInset = (24 * scale)
  inset = (6 * scale)
  bm = (costumeData morph)
  fillRect bm (gray 230) inset topInset ((width bm) - (inset + inset)) ((height bm) - (topInset + inset))
  costumeChanged morph
  fixLayout this
}

method fixLayout FilePicker {
  scale = (global 'scale')

  // file list
  topInset = (55 * scale)
  bottomInset = (40 * scale)
  leftInset = (110 * scale)
  rightInset = (20 * scale)
  setPosition (morph listPane) ((left morph) + leftInset) ((top morph) + topInset)
  setExtent (morph listPane) ((width morph) - (leftInset + rightInset)) ((height morph) - (topInset + bottomInset))

  // nameLabel and nameField
  if (notNil nameLabel) {
	x = ((left morph) + leftInset)
	y = ((bottom morph) - (32 * scale))
	setPosition (morph nameField) x y

	x += (- ((width (morph nameLabel)) + (8 * scale)))
	y = (y - (1 * scale))
	setPosition (morph nameLabel) x y
  }

  // okay and cancel buttons
  space = (10 * scale)
  y = ((bottom morph) - (28 * scale))
  x = ((right morph) - ((width (morph okayButton)) + (25 * scale)))
  setPosition (morph okayButton) x y
  x = (x - ((width (morph cancelButton)) + space))
  setPosition (morph cancelButton) x y
}

defineClass FilePickerIcons

method computerIcon FilePickerIcons {
  data = '
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
L17f2/gXyOtCx6O7RQgAAAAASUVORK5CYII='
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method desktopIcon FilePickerIcons {
  data = '
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
L17f2/gXyOtCx6O7RQgAAAAASUVORK5CYII='
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method downloadsIcon FilePickerIcons {
  data = '
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
QmCC'
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method examplesIcon FilePickerIcons {
  data = '
iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAG3klEQVR4nO2Vy69eVRnGf+9aa+/vOz2n
Pee0tCCltGiBWgNY0MQoGqOGoDEhMmCiIxPjX2BixEvExJg4c2YcOXBiAjpQiSgSjGFEDAFj0UQ5vVku
DW3Pd77LXuu9ODglLS2JiQGZ+EzW3it7rfXs533W+8D/8S5Drp747Hcf+wlw+D+se+bx7zz48NtO4L5v
/fyO5Z0rP733w0eOrS6PMW1IJKIDwsmeeW1a46mnn30K+NIT33vo7NtG4FNf/9kja7tXP3/Tze+5cffu
lesn1SASJRz1gnml9D3rO4SNjXOnzpw+e2Yxmy/+izOf/cMPvvi1N17KGw+t1o8fu+u2Y7tGIy4uKkQw
jkzgaFR29WPm4kgNPnj7/gOfuPPAgeQJBEwUjQIYHRl1IxKIgyfInnGMzaHx6C+fvlaBe7/92A/D9Mur
q7vWRRBEEIIIgQhIIHG5WgEIAYAjJAEiCBEkICQQhIjLEgcOCBcubF6QXJ4DnvnTIw8+XADC/UNfeeBj
u9eWx4g4uNP1HW5OkYwnA4KOTBDknLd3dQMJhIIFEEZtQU6Ci5NzwiwhCYKgqZNC1s5X++SPH/3j5RKE
O69OBmYYgxXEK1IGUhS6MCwyEkbqM30KzDKShSKKaKLFgpI6jMAYEM+kXDAbaJJxDSIFvmj0XWLuRri/
mUDuEtO50xFEErQJ4wg0HBVnpetpgFVHSiChuBYQSDkYcCSMIiNMgoU3wkBRiiXMlG6cqAatvgUBs8DJ
mC9IfU/WgRdePMHLZ04z18pSXmJlZZlbbz3E3hv20iUgGpoSJTJiyslXXuXEP08xmU6YThYsLY1ZW13j
9iO3MV4d0SqkEGq7ioCbo0OjZqeTTAyNX/36Sfbt28tNh95H6jqyKpPFguf/+jfS8Rf5yEfvYUe/TAtn
1hrP/fl5prOBfXuuY339epZGhUErFy5u8cTvn+Iz99/HaFxoAv0o4XalAmaoCKOcCAGX4Ob33szetX1I
QOqMKEvs7pZYXd/J1mTOk799hvs/92k0OY//5ncc3H+QGw4eQIrTIuFiSN+xvuc66HpG2WnRSJ6pgxNm
VyjghjsMVcjheJ/JaYlqICXAhM6VKGBeWFleYd/+m2gR6FQ5eMtt7FpeRcW3ry2CGjQTSjZEjcgdUYPB
lZQy7lcQCHWSC9IFLYLiA2YVs0qRDlqlpREZA28MIogrGoYWRSJQjKSBpIzTCM1IVuoASmbQATGhE6EN
SuibPGDMpZJaJlnC+gwRSE60Zoj05FSxKJgqORdSN6I1BQnMArzStEBnoAaitCHoijDojMGdkhIo1Bz4
lSUIM9SCHIncGR4wN2esTsKJKGiN7fKUjBDMBkNdqFWwS1fSEiRtqBVyVJBE80xoplbQcCI7YfkqD5gh
7oRVZqkjt0a0SnMHV3ICCWNqRoqgRYeZM1eFBK0lBhrigmoDN6RPCEHzRgDeFuS0g8CxNrtWgdnMiVYp
K0rkjEZG50qXg9j+ik4uNR5R3J0cxjA4c2uMFz10hexpe31VbDurEDH60RI2VEiAp2sV6HC69WXCodZG
VgEMk4y0gJRBFDHBQnAcdacNC2xQYodgc6X1QbZgmCmpGKXrUHNmg5LVUSDsLTxgJWjzASjkEKIIdB2t
NXIBDSihIIKrMKuVOgiMO0Zdj0bQotFFR1WDXujKdkhZFaZbC5aXM64GIlcr4NQadH2iWsO8sRhm2Hnb
TjacCCF3hZIKo9IzpuASDM2YWcOHRJd75jNF2xwxZUsKlMRgM5bHHbpoJCnU5Nd2wiwwVKXvwFvHyq5d
3Hr4CHv27GQ2OJMLm2ycOMXWbIKnzMIag4NqIoUwysF0PmW01HH0A+9nfW0NSUu8+sprbJx8iaoJSZkF
jVIveyC94YFJczBDh8QiDdx19zGmMeP4xj84c/ZfNAnuvPsoe9ZX2Tx/jtnWFK8Vb87FzYucf33G3hv3
c8c9x2iLYOPkyxw/fhxNlaNHb2eIOZIS2RPqXO0BZ+SOjkbk1ijScfLMKaIlLJSSCtPNTWaT1zl05DDH
7r6LljMvHf87aSw88NAXEIWXz53m9IkTkApiMC6wOZmwOZniEczMyeq4C2FXxfG0GX1xVJU+RkQOPGYI
YzyDt4bl4ORLJzjbJ9CCliAvlL+88CLiRu4FkyBa0BWlDWAx0I+XwROigarRvF6O41vu/2YK98GH2XRu
w3Jyx9iCBDl1eMypkwTFUIOOwtagFATVtN3bczBKji0yNSkoNMmUJKTizCcLgowoRE7kcYnwbQYCcOi+
bzwAfBVY4n+HX2w88f0fySUj7gT2AWtAfocPduAi8BpwQdhWoWP77/tLhN5JBFCB+aXx3cW/AeX3f9I8
jvGZAAAAAElFTkSuQmCC'
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method gpFolderIcon FilePickerIcons {
  data = '
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'
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method homeIcon FilePickerIcons {
  data = '
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'
  return (readFrom (new 'PNGReader') (base64Decode data))
}
