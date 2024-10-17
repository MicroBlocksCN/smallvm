// MicroBlocksFilePicker.gp
// Dialog box for specifying files for opening or saving in MicroBlocks.
// Note: Replaces the GP FilePicker in the MicroBlocks IDE.

defineClass MicroBlocksFilePicker morph window folderReadout listPane parentButton newFolderButton nameLabel nameField cancelButton okayButton topDir currentDir useEmbeddedFS action forSaving extensions isDone answer onFileSelect onFolderSelect cloudAction

to microBlocksFileToWrite defaultPath extensionList {
  // Ask the user to enter a file name and location for writing. If provided, defaultPath is
  // offered as a starting point. Wait synchronously until a file is specified and return its
  // full path, or the empty string if the user cancels the operation.

  if (and (notNil defaultPath) (endsWith defaultPath 'png') ) {
	lastScriptPicFolder = (lastScriptPicFolder (findProjectEditor))
    if (notNil lastScriptPicFolder) {
      defaultPath = (join lastScriptPicFolder (filePart defaultPath))
    }
  }

  if (and (isClass extensionList 'String') (notNil defaultPath) ((count defaultPath) > 0)) {
	// there is a single extension and the default path is not nil or empty
	extension = extensionList
	if (not (endsWith defaultPath extension)) {
	  // append the extension to the default path
	  defaultPath = (join defaultPath extension)
	}
  }
  fileName = (microBlocksPickFile nil defaultPath extensionList true)
  if (endsWith fileName 'png') {
	 setLastScriptPicFolder (findProjectEditor) (directoryPart fileName)
  }
  return fileName
}

to microBlocksPickFile anAction defaultPath extensionList saveFlag {
  if (isNil saveFlag) { saveFlag = false }
  page = (global 'page')
  if (and (notNil defaultPath) (beginsWith defaultPath '//')) {
	defaultPath = ''
  }
  picker = (initialize (new 'MicroBlocksFilePicker') anAction defaultPath extensionList saveFlag)
  pickerM = (morph picker)
  setPosition pickerM (half ((width page) - (width pickerM))) (40 * (global 'scale'))
  addPart page picker

  if (and saveFlag (isNil anAction)) {
	// modal version -- waits until done and returns result or nil
	setField (hand page) 'lastTouchTime' nil
	while (not (isDone picker)) { doOneCycle page }
	destroy pickerM
	return (answer picker)
  }
}

// function to return the user's MicroBlocks folder

to microblocksFolder {
  if ('iOS' == (platform)) { return '.' }
  path = (userHomePath)

  // Look for <home>/Documents
  if (contains (listDirectories path) 'Documents') {
	path = (join path '/Documents')
  }
  if (not (contains (listDirectories path) 'MicroBlocks')) {
	// create the MicroBlocks folder if it does not already exist
	makeDirectory (join path '/MicroBlocks')
  }
  if (contains (listDirectories path) 'MicroBlocks') {
	path = (join path '/MicroBlocks')
  }
  return path
}

// support for synchronous ("modal") calls

method destroyedMorph MicroBlocksFilePicker { isDone = true }
method isDone MicroBlocksFilePicker { return isDone }
method answer MicroBlocksFilePicker { return answer }

// initialization

method window MicroBlocksFilePicker { return window }

method initialize MicroBlocksFilePicker anAction defaultPath extensionList saveFlag {
  if (isNil defaultPath) { defaultPath = (microblocksFolder) }
  if (isNil saveFlag) { saveFlag = false }
  if (isClass extensionList 'String') { extensionList = (list extensionList) }
  scale = (global 'scale')
  useEmbeddedFS = false

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
  if ('Linux' == (platform)) { setFont lbox 'Arial' 12 }
  listPane = (scrollFrame lbox clr)
  addPart morph (morph listPane)
  setGrabRule (morph listPane) 'ignore'

  addShortcutButtons this
  addFolderReadoutAndParentButton this
  if forSaving { addFileNameField this (filePart defaultPath) }
  okayLabel = 'Open'
  if forSaving { okayLabel = 'Save' }
  okayButton = (textButton this 0 0 okayLabel 'okay' true) // default
  cancelButton = (textButton this 0 0 'Cancel' (action 'destroy' morph))

  setMinExtent morph (520 * scale) (465 * scale)
  setExtent morph (520 * scale) (465 * scale)

  if forSaving {
	defaultPath = (directoryPart defaultPath)
	if (isEmpty defaultPath) { defaultPath = (microblocksFolder) }
	if ('Browser' == (platform)) { defaultPath = 'Downloads' }
  }
  if (and ((count defaultPath) > 1) (endsWith defaultPath '/')) {
	defaultPath = (substring defaultPath 1 ((count defaultPath) - 1))
  }
  if (isOneOf defaultPath 'Examples' 'Libraries') {
	useEmbeddedFS = true
	if ('Browser' == (platform)) { useEmbeddedFS = false }
  }
  isTopLevel = (isNil (findFirst defaultPath '/')) // root folder
  showFolder this defaultPath isTopLevel
  return this
}

method addFolderReadoutAndParentButton MicroBlocksFilePicker {
  scale = (global 'scale')
  x = (110 * scale)
  y = (32 * scale)
  fontName = 'Arial Bold'
  fontSize = (16 * scale)
  if ('Linux' == (platform)) { fontSize = (12 * scale) }
  if ('Browser' == (platform)) {
	fontName = 'Arial'
	fontSize = (16 * scale)
  }

  folderReadout = (newText 'Folder Readout')
  setFont folderReadout fontName fontSize
  setGrabRule (morph folderReadout) 'ignore'
  setPosition (morph folderReadout) x y
  addPart morph (morph folderReadout)

  parentButton = (textButton this 0 0 '<' 'parentFolder')
  parentButtonM = (morph parentButton)
  setTop parentButtonM (y - (4 * scale))
  setLeft parentButtonM (x - ((width parentButtonM) + (18 * scale)))
  addPart morph parentButtonM
}

method addFileNameField MicroBlocksFilePicker defaultName {
  scale = (global 'scale')
  x = (110 * scale)
  y = (32 * scale)
  fontName = 'Arial Bold'
  fontSize = (15 * scale)
  if ('Linux' == (platform)) { fontSize = (12 * scale) }
  if ('Browser' == (platform)) {
	fontName = 'Arial'
	fontSize = (15 * scale)
  }

  // name label
  nameLabel = (newText (localized 'File name:'))
  setFont nameLabel (join fontName ' Bold') fontSize
  setGrabRule (morph nameLabel) 'ignore'
  addPart morph (morph nameLabel)

  // name field
  border = (2 * scale)
  nameField = (newText defaultName)
  setFont nameField fontName fontSize
  setBorders nameField border border true
  setEditRule nameField 'line'
  setGrabRule (morph nameField) 'ignore'
  nameField = (scrollFrame nameField (gray 250) true)
  setExtent (morph nameField) (213 * scale) (18 * scale)
  addPart morph (morph nameField)
}

method addShortcutButtons MicroBlocksFilePicker {
  scale = (global 'scale')
  hidden = (array 'Cloud') // this can be used to hide selected shortcuts

  showMicroBlocks = (and
	(not (contains hidden 'MicroBlocks'))
	('Browser' != (platform)))
  showExamples = (and
	(not (contains hidden 'Examples'))
	(not forSaving)
	(isClass extensions 'Array')
	(contains extensions '.gpp'))
  showLibraries = (and
	(not (contains hidden 'Libraries'))
	(not forSaving)
	(isClass extensions 'Array')
	(contains extensions '.ubl'))
  showDesktop = (not (contains hidden 'Desktop'))
  showDownloads = (and
	(not (contains hidden 'Downloads'))
	('Linux' != (platform)))
  showComputer = (not (contains hidden 'Computer'))

  buttonX = ((left morph) + (17 * scale))
  buttonY = ((top morph) + (60 * scale))

  dy = (66 * scale)
  if showExamples {
	addIconButton this buttonX buttonY 'examplesIcon' (action 'setExamples' this)
	buttonY += dy
  }
  if showLibraries {
	addIconButton this buttonX buttonY 'libsIcon' (action 'setLibraries' this) 'Libraries'
	buttonY += dy
  }
  if showMicroBlocks {
	addIconButton this buttonX buttonY 'microblocksFolderIcon' (action 'setMicroBlocksFolder' this) (filePart (microblocksFolder))
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
	if showComputer {
	  addIconButton this buttonX buttonY 'computerIcon' (action 'setComputer' this)
	  buttonY += dy
	}
  }
  if (and showComputer ('Browser' == (platform))) {
	addIconButton this buttonX buttonY 'computerIcon' (action 'setComputer' this)
	buttonY += dy
  }
  if (and showLibraries (not (contains hidden 'Cloud'))) {
	addIconButton this buttonX buttonY 'cloudIcon' (action 'cloudAction' this) 'Cloud'
	buttonY += dy
  }
  if (and (devMode) showLibraries) {
	addIconButton this buttonX buttonY 'newLibraryIcon' (action 'newLibrary' this) 'New'
	buttonY += dy
  }

  buttonY += (5 * scale)
  newFolderButton = (textButton this buttonX buttonY 'New Folder' 'newFolder')
}

method addIconButton MicroBlocksFilePicker x y iconName anAction label {
  if (isNil label) {
	s = iconName
	if (endsWith s 'Icon') { s = (substring s 1 ((count s) - 4)) }
	s = (join (toUpperCase (substring s 1 1)) (substring s 2))
	label = s
  }
  isChinese = ('简体中文' == (language (authoringSpecs)))
  scale = (global 'scale')
  iconBM = (call iconName (new 'MicroBlocksFilePickerIcons'))
//  iconBM = (scaledIcon this iconName) // don't activate this until warpBitmap works in browsers
  bm = (newBitmap (70 * scale) (50 * scale))
  drawBitmap bm iconBM (half ((width bm) - (width iconBM))) 0
  if (1 == scale) {
	setFont 'Arial Bold' (9 * scale)
  } else {
	setFont 'Arial Bold' (12 * scale)
  }
  if ('Browser' == (platform)) {
	setFont 'Helvetica' (13 * scale)
  }
  if (and isChinese ('Win' == (platform))) {
	setFont 'Arial Bold' (12 * scale)
  }
  labelX = (half ((width bm) - (stringWidth (localized label))))
  labelY = ((height bm) - (fontHeight))
  drawString bm (localized label) (gray 0) labelX labelY

  button = (newButton '' anAction)
  setLabel button bm (transparent) (microBlocksColor 'yellow')
  setPosition (morph button) x y
  addPart morph (morph button)
  return button
}

method scaledIcon MicroBlocksFilePicker iconName {
	// This works on SDL 2.0.10 but warpBitmap has not yet been implemented for browsers.
	scaleFactor = (0.8 * (global 'scale'))
	iconBM = (call iconName (new 'MicroBlocksFilePickerIcons'))
	resultBM = (newBitmap (scaleFactor * (width iconBM)) (scaleFactor * (height iconBM)))
	// warpBitmap args: dstBM srcBM xScale yScale rotation
	warpBitmap resultBM iconBM 0 0 scaleFactor scaleFactor
	return resultBM
}

method textButton MicroBlocksFilePicker x y label selectorOrAction makeDefault {
  if (isClass selectorOrAction 'String') {
	selectorOrAction = (action selectorOrAction this)
  }
  result = (pushButton label selectorOrAction nil (26 * (global 'scale')) makeDefault)
  setPosition (morph result) x y
  addPart morph (morph result)
  return result
}

// actions

method onSelectCloud MicroBlocksFilePicker anAction {
	cloudAction = anAction
}

method cloudAction MicroBlocksFilePicker {
	call cloudAction
}

method onFileSelect MicroBlocksFilePicker anAction {
	onFileSelect = anAction
}

method onFolderSelect MicroBlocksFilePicker anAction {
	onFolderSelect = anAction
}

method setComputer MicroBlocksFilePicker {
  if ('Browser' == (platform)) {
	isDone = true
	removeFromOwner morph
	repeat 10 { // hack: need several cycles to remove MicroBlocksFilePicker when file is double-clicked
		doOneCycle (global 'page')
		waitMSecs 10 // refresh screen
	}
	ext = ''
	if (notNil extensions) { ext = (first extensions) }
	if (beginsWith ext '.') { ext = (substring ext 2) }
	browserReadFile ext
	return
  }
  useEmbeddedFS = false
  showFolder this '/' true
}

method setDesktop MicroBlocksFilePicker {
  useEmbeddedFS = false
  showFolder this (join (userHomePath) '/Desktop') true
}

method setDownloads MicroBlocksFilePicker {
  useEmbeddedFS = false
  showFolder this (join (userHomePath) '/Downloads') true
}

method setExamples MicroBlocksFilePicker {
  useEmbeddedFS = true
  if ('Browser' == (platform)) { useEmbeddedFS = false }
  showFolder this 'Examples' true
}

method setLibraries MicroBlocksFilePicker {
  useEmbeddedFS = true
  if ('Browser' == (platform)) { useEmbeddedFS = false }
  showFolder this 'Libraries' true
}

method setMicroBlocksFolder MicroBlocksFilePicker {
  useEmbeddedFS = false
  showFolder this (microblocksFolder) true
}

method newLibrary MicroBlocksFilePicker {
  scripter = (scripter (findProjectEditor))

  libName = (freshPrompt (global 'page') 'New library name?' '')

  if (libName != '') {
	  lib = (newMicroBlocksModule libName)

	  addLibrary (project scripter) lib
	  updateLibraryList scripter
	  updateBlocks scripter
	  selectLibrary scripter lib

	  showLibraryInfo lib true

	  removeFromOwner morph
	  isDone = true
  }
}

method parentFolder MicroBlocksFilePicker {
  i = (lastIndexOf (letters currentDir) '/')
  if (isNil i) { return }
  newPath = (substring currentDir 1 (i - 1))
  showFolder this newPath false
}

method showFolder MicroBlocksFilePicker path isTop {
  currentDir = path
  if isTop { topDir = path }
  setText folderReadout (localized (filePart path))
  updateParentAndNewFolderButtons this
  setCollection (contents listPane) (folderContents this)
  changeScrollOffset listPane -100000 -100000 // scroll to top-left
  if (notNil onFolderSelect) {
	call onFolderSelect (join path)
  }
}

method folderContents MicroBlocksFilePicker {
  result = (list)
  if useEmbeddedFS {
	dirsAndFiles = (embeddedFilesAndDirs this (join currentDir '/'))
	dirList = (at dirsAndFiles 1)
	fileList = (at dirsAndFiles 2)
  } else {
	dirList = (listDirectories currentDir)
	fileList = (listFiles currentDir)
  }
  for dir (sorted dirList 'caseInsensitiveSort') {
	if (not (beginsWith dir '.')) {
	  add result (array (join '[ ] ' (localized dir)) (join '[ ] ' dir))
	}
  }
  for fn (sorted fileList 'caseInsensitiveSort') {
	if (not (beginsWith fn '.')) {
	  if (or (isNil extensions) (hasExtension fn extensions)) {
		add result (array (localized (withoutExtension fn)) fn)
	  }
	}
  }
  return result
}

method embeddedFilesAndDirs MicroBlocksFilePicker prefix {
  dirsSeen = (dictionary)
  dirList = (list)
  fileList = (list)
  offset = ((count prefix) + 1)
  for fn (listEmbeddedFiles) {
	if (beginsWith fn prefix) {
	  fn = (substring fn offset)
	  i = (findFirst fn '/')
	  if (isNil i) {
		add fileList fn
	  } else {
		dirName = (substring fn 1 (i - 1))
		if (not (contains dirsSeen dirName)) {
		  add dirList dirName
		  add dirsSeen dirName
		}
	  }
	}
  }
  return (list dirList fileList)
}

method newFolder MicroBlocksFilePicker {
  newFolderName = (prompt (global 'page') 'Folder name?')
  if ('' == newFolderName) { return }
  for ch (letters newFolderName) {
    if (notNil (findFirst './\:' ch)) {
      inform 'Folder name cannot contain: .  /  \  or  :'
      return
    }
  }
  newPath = (join currentDir '/' newFolderName)
  makeDirectory newPath
  useEmbeddedFS = false
  showFolder this newPath false
}

method okay MicroBlocksFilePicker {
	answer = ''
	if forSaving {
		answer = (join currentDir '/' (text (contents nameField)))
	} else {
		sel = (selection (contents listPane))
			if (isClass sel 'Array') { sel = (at sel 2) }
			if (notNil sel) {
				if (beginsWith sel '[ ] ') {
					// jump inside folder
					select (contents listPane) sel
					return
				} else {
					answer = (join currentDir '/' sel)
				}
			}
		if (and useEmbeddedFS ('' != answer)) { answer = (join '//' answer) }
		if (and (notNil action) ('' != answer)) {
			removeFromOwner morph
			call action answer
		}
	}
	removeFromOwner morph
	isDone = true
}

method fileOrFolderSelected MicroBlocksFilePicker {
	sel = (selection (contents listPane))
	if (isClass sel 'Array') { sel = (at sel 2) }
	if (beginsWith sel '[ ] ') {
		sel = (substring sel 5)
		if (endsWith sel ':') {
			showFolder this sel true
		} ('/' == currentDir) {
			showFolder this (join currentDir sel) false
		} else {
			showFolder this (join currentDir '/' sel) false
		}
	} else {
		// fill the file name input field with the name of the selected file
		if (notNil nameField) {
			setText (contents nameField) sel
		}
		if (notNil onFileSelect) {
			path = (join currentDir '/' sel)
			if useEmbeddedFS {
				path = (join '//' path)
			}
			call onFileSelect path
		}
	}
}

method fileOrFolderDoubleClicked MicroBlocksFilePicker {
  sel = (selection (contents listPane))
  if (isClass sel 'Array') { sel = (at sel 2) }
  if (beginsWith sel '[ ] ') {
	sel = (substring sel 5)
	if (or (endsWith sel ':')) {
	  showFolder this sel true
	} else {
	  showFolder this (join currentDir '/' sel) false
	}
  } else { // file selected
	if (not forSaving) {
	  answer = (join currentDir '/' sel)
	  if useEmbeddedFS { answer = (join '//' answer) }
	  if (notNil action) { call action answer }
	  removeFromOwner morph
	}
  }
}

method updateParentAndNewFolderButtons MicroBlocksFilePicker {
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

method redraw MicroBlocksFilePicker {
  scale = (global 'scale')
  fixLayout window
  redraw window
  topInset = (24 * scale)
  inset = (6 * scale)
  bm = (costumeData morph)
  fillRect bm (microBlocksColor 'blueGray' 50) inset topInset ((width bm) - (inset + inset)) ((height bm) - (topInset + inset))
  costumeChanged morph
  fixLayout this
}

method fixLayout MicroBlocksFilePicker {
  scale = (global 'scale')

  // file list
  topInset = (60 * scale)
  if 
  bottomInset = (48 * scale)
  leftInset = (113 * scale)
  if (notNil nameLabel) {
    leftInset = (max leftInset ((width (morph nameLabel)) + (23 * scale)))
  }
  rightInset = (20 * scale)
  setPosition (morph listPane) ((left morph) + leftInset) ((top morph) + topInset)
  setExtent (morph listPane) ((width morph) - (leftInset + rightInset)) ((height morph) - (topInset + bottomInset))
  updateSliders listPane

  // parentButton and folder readout
  parentButtonM = (morph parentButton)
  setLeft (morph folderReadout) (left (morph listPane))
  setLeft parentButtonM ((left (morph listPane)) - ((width parentButtonM) + (13 * scale)))

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
  y = ((bottom morph) - (35 * scale))
  x = ((right morph) - ((width (morph okayButton)) + (20 * scale)))
  setPosition (morph okayButton) x y
  x = (x - ((width (morph cancelButton)) + space))
  setPosition (morph cancelButton) x y
}

method listPane MicroBlocksFilePicker { return listPane }

defineClass MicroBlocksFilePickerIcons

method computerIcon MicroBlocksFilePickerIcons {
  data = '
iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAO
xAAADsQBlSsOGwAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAANtSURBVFiF5ZZb
aBxlFMd/c/m+3Z2dJLVoG1MDBaUo8UVBTVNbW4pIRLyXSqBioC9SiVWUesPijVIKKlYKeak1SiFSbdGi
wUJMi9HWVsVgSYu+tCQmIZXs7GYvs3NZH8KumWYvNuxuH/zDPMz/fDPnd5jznW/g/y4FiBhG+NWQFOtz
OV/8G1C9bDY7nEzbbwHxmgE0NZifd7S3dT7ZdV9E19RCwPN8Dh05njk2eOaklUhuqBmA0DV79Oc+2WAa
C4Ku57Gy7QnHcdwewK9SzgTwK3AO5j5BbuKPL1BVpejq3v1fuaPnL3hVSk4sPps9dXpUdT1vMB5PbqoI
UAvZtsPT299Nn/hx5JOrAgDw1+TfrLl3W0ytvLQ2al62lFTKXqIDHDg4wNGBk4yNT9cl+YqW63iwsx0A
XUrJkaOn2Pna87S2ttQF4OLFcd58532kFCiRSDj325kBWq5fXpfkeY2NT3LbnZ1z2zB+6SyqWt928H2f
xmvbuGpNmJdeKnB25DhD3/aRTiUKXtM1y+h8+BluaL25tgC+7/P14Q/ZsnUXS5Y2F/w/z5/m2Je9dG97
DwDPdXGcTNkEQoTR9JJ1FgewM0lQoHnFTQG/deWtDA58BMD33/Xzw1A/qlb65QCe57JuYxer1z3+3wEA
fM9l9+uPBLwcIITEcWyGh/rp2XGAiNFYFiA1a7F3Tzd3dDyErosF8ZIAqqbx7EufBrx47BIH979C1k4j
ZKhicgDDbELVNJxs5soAQEHKcMARMlQx4ZWqJIDnOrz98v0L/Gi0ctVVAdB0wY43Dgc8KzZNX+8L9QEA
UBSl7H01tKhJKEMRnKxNOlX5XzU5GyPneYjL+imv8pu4hIQIsWb9Zj7Y/RTavDng+S5KjsBsyM+BYjug
JICQYXKeR2rWwjCbCr41M0U4YgJw94bNtK99FNexC/Hhoc9QFIWOezbNg13EJNR1wdqNXezd0x2oUFEU
HnhsOwAf977I9NSFwHOu66AAv/z0TcBf3nIjW7buKgpQ9ji+fNbLUARV1QBwHBvPdUpWNl+aLhAiOEPy
x3HZHtB0HU03i8aECC146WKkSikzlpWovLLKsqwEISnTWkND9JaR38+tWn3X7XpjY/Fqq62x8Ul6ntuZ
npiYOgRgmKaxLxo1Zpg78Gp+RaPGjGka+wDjH/YDRFusMm44AAAAAElFTkSuQmCC'
  dataRetina = '
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
AfgXKCaphJhXjRgAAAAASUVORK5CYII='
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method libsIcon MicroBlocksFilePickerIcons {
  data = '
iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAO
nAAADpwBB5RT3QAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAToSURBVFiFvZdb
TBRXHMZ/s8zOzuyyRQSBZUG5o9LW+61oi7Va0mjS1KqNTUvbpOk1qTW2sUk1sTZNa1vBNhp9wJBaU632
obdoLBJERYgVraKGi0hYQLm4uAsLuzDL9KHVBndZGIn9JvMy8/3P95tzzpwzIxBcYYosfyoIwhuqX1Uk
SbotimFNAwP+eo/H028Nt+R6fb4okyR1aQilHo+nGDgNXAW0YdoMKiHYRVmWt6SnJW3YuWOr2W6Pw9Hc
isPRyqXqGr7dVcTOHVtZtHAujY0OzlSep7jklHau6hKqqvolyejo7vaUA/uAUsA3EoAiSdJGsyw9iaBJ
AP5Bpv+4f5e0aOHcIeb8bwqpvlxD4Z5tAQ1pmkZNbQPlFecoK6vkZPlZrbPTOWgNN1f3ePqOqapaBpQD
ziEA4RblYNaUpBWvvJiriKKIpsG7Gwq48tdx4mInDAlZvfZtcp/O4bW81aH79V/dbOugorKKU+Vn1dLS
ir66a41mi0Upcbt7XgZuAghGMcxbWbrbZLdFA9DW3sWcnDfpbL2AIPw3QpqmMSn9MY79/j2TM1NHBXCv
XK5uNm/52n/w8K+NPT296YBmGFD9pnCLctfkaGlnYoJtSDhATW0DmqaRmZFyX+EAERFWtn+5KUxASFUU
0x+AyXCvqbmlg8SJ8QHFZyqrWDBvZgCYXt2pn5oxKTvcrOQHADQ1t5M0MSEQoOIcC+bPGlM4QPXlWmRZ
Iv+Ld+RBtBcCe6C1g8REexCAKhbMmzFmgIrKKubNmUpcbBS9vd5IAdA2b8zjaPGftLU7cbs9yLKMLJvu
FvkHB7l1q4sJ0ePHPAQudzdRkVbWrlrCls+LEIxGUctIT+bjj94jwR43xucbnZpbbrL1swLq6hoRZNmk
nSw5zJTJaf9L+B1duVrH40tWIXq9PuJtsUFNLc01tLU23FeAxTKOlMyZGEVT0Pv2+Di8Xh9iqEYa6y9S
dnwfKWkzsD4UrQvAdbuDspL9vPpWPqJoHNYXEiA7ZxU9PU4iIiYwf9FzugAAinat50ZzLYlJWcN6Al7D
e6XIFvr7vbrDAWSzFZ+vN6QnZA/09bppqD/PtFlL8fb16Arvdjtpa20gKjpwURs1wPEje+lsd1B8pJDi
I4W6ABQlnOzFa4iMsoX0hRyC5SvX8eisp/D1eRj0+xF0HN4+DyVH9/Lb4QI0bfiPpJA9ALD0mdfp9/Yy
bryNhYvXjGQfIlXt57s9H3D92gVS0oIv4yNOQkEQsNnT6XZ36goHEEWJmNhk3K6OYT0jAgC4Xe0oSrhu
AACXqx1FsQ57f8QhOFnyA+UnfiImLokWR42u8J7uLkyyhdSM2foBWhw1HPtlN6raT2SUjYF+L65RrgcG
g0hsfDI5y/Kw2dMwGML0A8TEJZGYnEXT9WqWP//+qILvyD+ocrrkANfrL2BPzAzpHRbAaDQxN/tZrlws
w2bXv1NOm72M6vMlI/pCTkK/OoAhbMRpErzWP7raYR1dzhv8fOgrRFGi/MQhfeGqysWqYhbn5t0/gMEQ
RnLqdPx+Vfc+ECaKrFi5jokpj4wMIEnGXmfXbXNExNB3NWJcDE8sfUlXsB45nV2YJKlXsFotRQ9nZa7e
vm2TkpgQ+D/wINTkaGX9h5/0XaquPQCgKIqyw2xWnPzza/3AT7NZcSqKUgAofwNEK90nvFaEEAAAAABJ
RU5ErkJggg=='
  dataRetina = '
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'
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method desktopIcon MicroBlocksFilePickerIcons {
  data = '
iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAO
xAAADsQBlSsOGwAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAGpSURBVFiF7dM/
SBthHMbxby6XN+a9SyxibZsiOBVKJh1a/yx1KJKlW6E4dC+C2K4tCJau4iR0EbHQyYqgQ0AQFIqKSqm0
xOJUSUxEi96lMV6Su3MQ26EFF3MZvAfe6ffC84H398J1TwCISNnwOixCj1zXCf0dKHa5XP5cLFlvAbNm
gMao/qm7M5F83t8XUYPKn4FtO0zPLp0uLG6sGoVib80AITVopTenRFSX/wyrtk1b4lmlUqkOAs4VdRaA
L8A2nD+Bm9uZQVEC/739fmKumv7x076ico7N3+W19bRSte1F0yw+vRRQi1hWhRdDo6Xlla0PdQEA7OV/
0fN44Fi5/GptcruliZMT64YKMPkxxXxqlUz2wJPyu/GbPEl2AqAKIZidX2P4zStaW+OeAHZ3s4y8G0OI
EIFIpMH9upEifueWJ+UXyWTztD9Inn9D8/A7iuLtOjiOQ6w5Qd2W8CI+wAf4AB/gA3yAD6g/QAhxahgF
z4sNo0BYiFIwGtXub33bvtf1sEONxXRPyjPZPIMvh0u53P40gNR1Oa5p8ghwvTiaJo90XY4D8gxLrakS
AQRhKAAAAABJRU5ErkJggg=='
  dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAd
eQAAHXkBKkJFPwAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAMwSURBVHic7Ztd
SFNhGMd/c5Zfm85pqflFaRqRVFJkaml+ENgXhjddGhikIiF01UVSl110ERhkFxVCEFEIKd2UWC0tw7RM
qTAoKRF0Q7ELdXNdzI317WrbM937gxees7Pn8Hv/nJ33HDgDhUIRzGjc6lVABbAViPxL3ywwArQBU75R
8y85QB9g93CMAYcFfL2GBogHXgOJMTE6SotyiYoM/2OT1WrD9GyQT6PjADZgD9Dta1lfoAGuADUbM1O4
03qetWsMS2qcnZ2ntvEi9+53A7wBtvhO03docJzGia0tZygv2eFR86R5mpy8amy2BYAM4IP3FX1LKJAA
kLEh2ePmOGM0sQY9E5NTAI9wXBwDjQVgAngB3AUeuu8MZXEl0Gh+alwSlQcLabneDuB5gv4jE8gD6nFc
q6qBt+CYvB2g52Ez69OTPD6y3W6n+/kQVqvVa7beZmzczOOnr2hrNzE3Nw+Opbsc6P3vAJYTH0fHqam/
wMDgCMBnYHOIsJNfSU9N4NaNJtYlxYPjJ9sQVAEAGGJ0nKqtcm5WBV0AADtzs51lZlAGEBER5iyjgjIA
d0LdN/r639HWYeLt+1HM5mkpJ59gNEazKSuNIxUFGAy67/bZAXtJ0XZPnwSX7SgtynXVrvsAAK1Wy6ED
ZRTv3UVcXOw/5By4TE5a6Ozq4V7HA2w2m+tzVwB6vY7bNy9TkO/ZA9Fy44mpl6pjJ5mZ+QqAFmgCOHe2
kaqjFYJq/iEtLZnVq1fxoNMEgGsVKCnOF5PyN2Ulha7aFUB4WNgvv7wScZ9r0N8HqACkBaRRAUgLSKMC
kBaQRgUgLSCNCkBaQBoVgLSANCoAaQFpVADSAtKoAKQFpFEBSAtIowKQFpBGBSAtII0KQFpAGhWAtIA0
KgBpAWlUANIC0oQAVgCrLXBfd/c2bnO1hgCfAPoHhsSE/E3fy0Fn+VELpAL5/QNDVB7Zj16v+33nCuDL
2DjHT5xmenoG4KoGMAIDQEp8vJGGumr2Fe3GYIgWFfU2FssUnV3dXGq+xsSEGRxn/jbn/mxgmAB4jdVP
YxjI+jGkCKAOx7+/LAEg6e1hAbqA2sW5AvANHNVzCuI7b40AAAAASUVORK5CYII='
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method downloadsIcon MicroBlocksFilePickerIcons {
	// TODO
	return (desktopIcon this)
}

method examplesIcon MicroBlocksFilePickerIcons {
  data = '
iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAO
xAAADsQBlSsOGwAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAS/SURBVFiFtZd7
bFNVHMc/vW1v29vbFvbQoa4o726y8ZhsjI2XTIliYkAhAYn+IfvHR8Q/1GDEkKD4CELQTIPGICFqFEwI
MahhPDa6joVtYcAezDG2dg9GtnVt161svdc/kEXoxnZx+yb3n3N+v+/vc86595xzdQwvvc1m/URR1FcH
BgbMZpPJbxQNvsFBpT4YDEVk2bq6r68/3mw2dQuCrrinJ/gH4AZqAXUEz2GlG65RlqWd8+elvlWw7yNr
UlIiPl8bzd5WLl6q4/Pd3/DD91+QvTiDpiYfJaXlFJ5yqx5PhRoMhRSzyeQLBENuRVEOAmeAyGgAkiSZ
t5lE43JVVYwAqirMO37soJg2d84dwV8WHKChoYm9uz8c1qytvQNPaTnFZ8s4edqjer2tg1ZZqgmH+/+K
RCJn/p2l7jsAHDb5t+zMlNWbNz5tMRr0qKrK5vxdeK+eQ7KY7yiw8eU3ef65p1j/wpp7DWpIvb1hys5f
wF1yXjl5uiRYdbHGbDaJbn9PcBPQDqAzGvSRuspDolW6Vazjhp+Va96m8UpJjOG02TmcKfyV5EemjAng
bvVHIuze+230q4ID3mCwdxqgCgOD0aHiAF5fB87kh2KSGxqaEEXjfRcHMJtMvP/u63pJsky1Ws0nAJNw
d5CvtQOnMxbAc66CxVkL77v4f6UDXWZGSrbNJu2LAWj2deB0JscClJaTPQ4Ajde8KIrCnl2vmaPR6Pph
ZqCTqckPxySWlFaQlTn/fwOUnqtk8aJUkh6MIxyOTNIB6q4d+Rw7XkpL6w0CgV4sFgsmkziUpCgKnV1+
EuIno9MNu3WMWYFgiMSESbyyKY/3tu/HYDKJHP29jA+2bcXpjB35RKi5uYUdO/cgiiI6i9msVlX8yZSk
BzQbhUM9AEiyQ3Nua9t10jNWowPUUFfNmBNvRsK4T//ChfITKMogAHrBSHrGKrKXvYhoksbsJce5tAEE
A50c+m4byU4XS1ZsYHL8rT2hu7ONs6d+pqW5jpe2fIxsixt/AFVVObj/HabPyiBnxYZhY4oLf6KxoZLN
Wz4d08sqx7mI+QxHUuPfldy82ceS5etHjMlZuYH+vl6uNVwYq+3YAa7WV5Ayd9k9R6bTCaSkLaXhSvn4
A/SG/Ngd8aPG2R0JhHv94w9gs8fj77o+apy/ux2bfXRQzQAzZmVQfbEIVR35xqWqKtVVxcyY/cT4Azin
zUWvN9xzfetryxBFE8mPpo4/AEBW7jo8RYdH7PcUHSYrd50WS20AKWm5BHpu4PPWxvS1+OoIBbqY83jO
xAEIgp60Bauor/bE9F25XEJ6Rh6CoMlSGwDA5LgkmhovoSjRoTZFidJ8rRq7PUGrHQatCYIg0NJcx2fb
1zIp4fZZ0I4SHSB94aqJB9DrRZIfS8WVuoQWby2osHDRM9RcdmOx2DUDaF6Cma5MHI5EytxHyXs2n7w1
+ZS5j+JwJDLTlakZQPN94LZKi49QVPgjAEuf3ERW7lrNHnKcC50oin2NdWfNDodNs8Hg4AAABoNRc67f
H2C6K7dPb7NZXVWXamZlZS4w2O2yJhNB0CMIes3FfS3tvLF1e19b6/UjAJIsy19brVI3t36tJ/yxWqVu
WZYKAOkfzVHeLEHJtboAAAAASUVORK5CYII='
  dataRetina = '
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
tJIAAAAASUVORK5CYII='
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method microblocksFolderIcon MicroBlocksFilePickerIcons {
  data = '
iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAO
xAAADsQBlSsOGwAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAATzSURBVFiF7ZVp
UJR1HMc/z+6yz+6zF4cJBMi1qKCZY2jkoEaOEZPUlJpmM9aMY3lMGjKMTo40luabNB0dKdNCO7RBlDCm
GFPHMR08aShEUpM0jgWVZTn2fHZ74Swpl+DBq74zz4v/7/h+v//zgQeDJIqq7CCTsUqnk6yBJtOOB+Qb
EFJ1ktT4YsZzbUX7vvANGRJsVyqV8xUKxeKgoMCikJDA6uDgwAqTSb+oLxIVIEmSZpWoDnjW5/Oq/AkB
hexyuU60250fAbYufWkGnXRwd/4m3bSpk9iy7SvZarU1azTi+imTU6RXX07XxcfHsDznQ9dfV68/0ZcB
wWTQ75+YMipj3tx0jUqp6EzIspd9Rccch46cLWtpbU+7oydQkrQ1hXs/M01KnYDd4SDGPNHRYXeI+Ts2
MOOVDAGgoLDEt3T5BzWtre1JgKNXAwEqpbO6/Bu1TtJ0S3pkmZhRc9xut2cp4AUQRXHG7JnT07ZtWRsA
sOf7YhYsWkFG+rPOgj15IoDX6yUhaYrT0nhjM3ClC20r8BtQBaBye+QexQFUSiW5K94ULlys2eSPHTp6
Xv3OgjcE//jbvQcQBIHZszJFf6zsVDmCgPr1mVOXdeW02tpcZWcuKGTZe8Rma58lAD7LlQO9rdBdqLfc
ZNpLOVz98yQAHXYH8SNTCVApOVy6lwRzLAA5K9dh0nvJWjKrRx6n083i5Rvtx05UfK3osaIXXK2pJ8Ec
0zn+5fCvmOMicLk9xMdFA7eXv6i4lMyMib3yiGIA63IXaGVZfk3Va1UPsDQ283h4aOe4YN9BRpgjCQjQ
oFDcnsup0+UEBxkwx0X0yRUWGkxHhzNQAHzr17zNwZ/KqK1r6rPJ4XDhkb0YDXq8Xi83b1nR6zS4XB5M
JiMAttY2lAoBrVbslScy4jEyM1JYmbsdlSiq+aHkNKvfz2LYsL5dPyxcu1bLmrWfolarEbQaja/ifCnh
YUMHRdyPunoLTya/gAD42m5VDaq4H/rgRAZ0Cx4FHpqBJsvfHPpxOw11XR++h2SgxdrIrs9zKPxuPbLH
0y1fUriZUyeKKC7Y+GgMXKw8yfWaSqp+P05DQ/dZRsYkARAVnTQgA/0+hLaWGxQXbMBgDGH6jCyUSmW3
GntHK1rJ0G9xfXDi/d+Cy9VnsbX893AljByPwThkQBz64ETu+RT7fF4EQdEtduTnL2lqvIZSoUKW3YQv
2dzNQE+9XdFntvZ6NTu3LsPabLkrLggK3lr4CWHhZrxeD6lpcwiPMN9VY73VwM6ty6i9Xn3/BiKiRjA2
+Xny87I5d6oEWZY7c2pRYva81SiUKiZNndsZl2WZc2Ul5OdlMzY5nYioEX0auOcWJD+TSVTMKI6W7qLs
+H5GjZmCOXECoaExeH0+tBoDssdNneUSl6tOU1lxjJAhkcydv5ahYbH3oh/YIayvvUx15QnKT5fidNvB
B7LHRYBai1YyMnzkeMY8Na3bdvSGfh3COxEeYSY8wozT5cBoDGFYzGgO7t/MwvfyyM/LJmnM5H6L+zEg
A35Ex47maOluLlWfweN28vGqTAAknXHAXPdlIM48jibLNULDY4mKTkIrDVzYj/9/xwq1Wu1oaWkddGGr
1YYoqu1Kg0GXWPFH1fCUp8epjEb9oIj/U9vAu1m59vo6SyGApNfr83Q6qRnwDcan00nNer20DZD+BcCd
6BrJe+ugAAAAAElFTkSuQmCC'
  dataRetina = '
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'
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method homeIcon MicroBlocksFilePickerIcons {
	// TODO
	return (desktopIcon this)
}

method cloudIcon MicroBlocksFilePickerIcons {
  data = '
iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAO
xAAADsQBlSsOGwAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAOYSURBVFiF5ZZd
TFt1GMZ/PS0Helo6vloKCwy2bGYBMhiZY2qMuCyKF5sxc2HLYuRiF5vJoviVOJOp08R4gXrhxJiI2xKj
c1MSG0Ky2EwNFhRGAAljDhWktNRBW1oobTnneLEwXaB0K7Re+CTn6nmT5/c/73ve84f/uzSAXpIyTqSL
aQ+pqpL2jyHIkUikYzYUPgXMJA1gXabx4n01ZXVPHXpEr9MKtwxZVrjQ+t38JXt3pz8wW5s0gDSdNjzU
c1bMNEpLzAVZpqSsPhqNLhwHlDXKDAC9wFW42QLV9etXCIJm2eqPPvlmYWh4VF6jcHwzwUjXz0PCgizb
Z2Zmn4wLkAyFw1GOPtsU+t7Rf+4/AQCYcE9x/55nfEL80uTIaslhbi6cpQP49LN2bO2djDv/Skn4+kIz
e+tqANCJokirrYuTrzZSVFSYEoCxMSdvvPUeopiGRq/PUPu62yksyE9J+KLGnW6q7q27+RnO3BhEEFI7
DoqiYMorQ3cnxd4pF309l/C4f0cjCJgtG9hWvYfs3IJVg8Q9dsflL2lpbkSWF6jc8SgVVbtRFJmW5kY6
Lp9HVVUAZoM+XM7rBIPeuwJYsQXdDhtXfmrjYMMpMk25t3nBwDSfn3mNDaUVuF2/MTkxQnaOFZ/XQ56l
iLp9x7BYS2MGL7YgJkBoLsCHTUdoOPpuzFftm3ZzpvlFHthdT9WOOgRBQFFkBnrt2NtbONTwJvmFGxMD
GOi1MzzoYP/hEzFPsZIGeu30OGw8faxpRYCYM+CddmGxliQUDlBeWYvP58HvW3m5xR5CFSKRUMIAGo2G
9cX30PrFOzj/HL47gD+u93Glq40tW2sSBgB44uArVO98jPNnX2d0pO/OABRFxvb1+zxe/xLFpeWrAtBq
tZRX1rL3wPO0tX6Aoiy90ywBcE+MkJ4uUbJp26rC/61Nm6sRtAI3PGPxAYIBL+uyzGsWvqis7PxlB3IJ
QE5uAZ7JUVR1ra6AoKoKHvcoObnW+AB5lmKMxmx6OtvWDKDbYcOUZSbXXLTEW/ZntO/AC5z7+GWmpyao
qHqYDL0hoeD50Cz9vd9ybfBHDh95e9mamJtwLujH8cNFRq71EI3MJwQgpuvZuHk7ux7cj2Qw3ebFXcXJ
1q1VLIrivN8fSGk4gN8fIF0UQ9rMTMPW/l+ubtm1c7vOZDKmJHzc6eb4cydDLtfkBQDJaJROGwySF1BT
8RgMktdolE4D0t+OiolPtJLckwAAAABJRU5ErkJggg=='
  dataRetina = '
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'
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}

method newLibraryIcon MicroBlocksFilePickerIcons {
  data = '
iVBORw0KGgoAAAANSUhEUgAAACMAAAAjCAYAAAAe2bNZAAAACXBIWXMAABAnAAAQJwFR8a7xAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAABARJREFUWIXtln1M1HUcx1+/33G/23HccccB
hxhNRQWEIsAHkIcawpKHHMLWTMyNJms92dbc2lrTVZabNKgtWy6NRsBWUDFK0B0+jFQEhbDSMhggIHIc
wREQcncd/dFqIx68g2Ot5fvv9/v7ee37+T584J7u6T8sYYG5VGAb0Ouk3wzUAP3uhslUKKRqL5UnGenJ
VmcCHZ3d9qbLV7FabQ8Dze6CyZEkeUVm+hbh2vU2mi997XSw8N1jjoLCo42jo2Ob5/KILoDskuTyinfe
PiDsydvhQuxPpSQniHa7bd18HmdhdiokqaSkuEjYvSvHZRAAURSYmpq/Ex5OrPOoJMlLS4qLhIy0ZAAc
jilkMpHqykLM/V2zhmQeEnEJ2YREzNkVl2HCFArFicLDr/4NAnDSeBZJtPB9yxlSMvag0ehnBEcsAxhr
j7kPRq32anA4HLK6Mxcw1tWDINBvMtPR0U1Z8VsErwrCP2DlrNmB/i4u1lc6DXJXmMnJSXn+U09gMPjR
2d7K0GAv8evXUHDwaaJikmhpquWH1nOzZsfHLKjVM3dswTCiKNqfzM0mIjyEyYlxvr1ykvYbV/jpu9ME
BCynvq6MlasfQj1Lm9QaPbGJrh12Zw4wAAqlitjEHDRaP2qrjlB2/BVkMg+StuSi0y9zqeiiYQD6ettQ
KjXk7z2CxtsX0+0OLMMmLMOmaT6tzrAgQKdhmhtP8E1dOYIoQ+tj4IGoZM6e+hiVSodckqZ5h4ZuszPv
IMuDQpYGZqCvk+hN6awIjuRyw1d0treyak00W7c9g9JTM81bUfoG/X3tSweDKGCzTeIfsILtO15GFEXs
dit2m5U7E2PTrL/b7YiizCUQl2DCIhKoLHuThvpKojemkb79BY6/9yJm080ZXq3OQFrWc0sHsyI4kn37
P6PxQhVN57/k8/JDjAybyHu2yOV2LBrmL4VFJCCXKwAIXhuDYdnsL/CSwvxi7uFU9QdMTIwSGZPK+rjH
qPq0YN6ZRuWlIzUzH73vfe6FaWmsxdNLi843EGPNh5wzfsLknd/IyNmLt7f/rJmrzUZaGmtJzch3L4zd
ZsVHH8jmRx4nNjEbAEEQ0eoMc2Z6uq4xPjrsbAnnYby89dy43sDY6BCrQzewNiyWpvNVDJp75sz03Woj
ZF2c+2E2xWehUCj5+cdGmi/VoNb4crG+cs6PEuDBqGSiNmx1P4ykULIxPguN1o/TNR/xRfkh5JKCpJRc
dD7/wkcJEBoeT2h4vFuK/1PzDuSSJA129/S5pdDN7ltIkmSezzPvtC6K4vM+PtrDr+1/SXl/UOCiQA68
XjgxPDyyz+FwvL8gGACZTLZbrfLMnxKY+w7fRcIUJsuvo0eB0oWu8f/WH7ozRDZHhK3AAAAAAElFTkSu
QmCC'
  dataRetina = '
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
TI/+pAAAAABJRU5ErkJggg=
='
  if (2 == (global 'scale')) { data = dataRetina }
  return (readFrom (new 'PNGReader') (base64Decode data))
}
