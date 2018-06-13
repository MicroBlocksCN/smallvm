// Project.gp - A GP project, including it's pages, media. and notes.

defineClass Project pages images sounds notes projectVars blockSpecs paletteBlocks extraCategories module hash ancestor dependencies thumbnail

method pages Project { return pages }
method images Project { return images }
method sounds Project { return sounds }
method notes Project { return notes }
method setNotes Project s { notes = s }
method blockSpecs Project { return blockSpecs }
method paletteBlocks Project { return paletteBlocks }
method extraCategories Project { return extraCategories }
method projectVars Project s { return projectVars } // needed for reading old projects
method ancestor Project { return ancestor }
method module Project { return module }
method dependencies Project { return dependencies }
method thumbnail Project { return thumbnail }

to emptyProject {
  return (initialize (new 'Project'))
}

method initialize Project {
  pages = (list (newProjectPage (list)))
  images = (list (makeShip this) (makeGPLogo this))
  sounds = (list (makePopSound this))
  notes = ''
  blockSpecs = (dictionary) // op -> blockSpec
  paletteBlocks = (dictionary) // category -> (ordered list of ops)
  extraCategories = (list) // ordered list of category names
  module = (initialize (new 'Module'))
  // This is not exactly right as it has pages data but this ensures
  //  that it has a hash and has a common ancestor that is always identifiable.
  ancestor = (sha256 '')
  hash = (sha256 '')
  dependencies = (list)
  return this
}

method initializeFrom Project project myHash myAncestor {
  pages = (pages project)
  images = (images project)
  sounds = (sounds project)
  notes = (notes project)
  // ???
  if (notNil (blockSpecs project)) { blockSpecs = (blockSpecs project) }
  if (notNil (paletteBlocks project)) { paletteBlocks = (paletteBlocks project) }
  if (notNil (extraCategories project)) { extraCategories = (extraCategories project) }
  hash = myHash
  ancestor = myAncester
  module = (module project)
  dependencies = (dependencies project)
  if (isNil hash) {hash = (sha256 '')}
  if (isNil ancestor) {ancestor = (sha256 '')}
  if (isNil module) {module = (initialize (new 'Module'))}
  if (isNil dependencies) {dependencies = (list)}
  if (notNil (thumbnail project)) {
    thumbnail = (copy (thumbnail project))
  }
  return this
}

// **** Read Project ****

method readProject Project data {
  initialize this
  zip = (read (new 'ZipFile') data)
  scriptData = (extractNestedFile zip 'scripts.txt')
  morphData = (extractNestedFile zip 'objects.gpod')
  if (notNil morphData) {
    if ((version (new 'Serializer') morphData) == 2) {
      return (readProject2 this data) // new format
    }
	if (notNil scriptData) { installScripts this (toString scriptData) }
    project = (read (new 'Serializer') morphData)
  }
  zip = nil
  scriptData = nil
  morphData = nil
  gc

  pages = (list)
  if (isClass project 'Table') { // old format: Table of pages
	for r (rowCount project) {
	  morphsForPage = (list)
	  for m (cellAt project r 'contents') {
		if (not (isAnyClass (handler m) 'ScripterMenuBar' 'Scripter')) {
		  postSerialize m
		  add morphsForPage m
		}
	  }
	  convertToStageCoordinates this morphsForPage
	  add pages (newProjectPage morphsForPage)
	}
  } (isClass project 'Project') {
	pages = (pages project)
	images = (images project)
	sounds = (sounds project)
	notes = (notes project)
	projectVars = (projectVars project)
	if (notNil projectVars) {
	  for v (keys projectVars) {
		setShared v (at projectVars v) module
	  }
	  projectVars = nil
	}
  } else {
	print 'Unknown or obsolete project class:' (className (class project))
  }
  if (isEmpty pages) { pages = (list (newProjectPage (list))) }
  convert this
  clearMethodCaches
  gc
  return this
}

// **** Old project format open/save support ****

method convertToStageCoordinates Project morphList {
  // Convert the given morphs to stage coordinates (i.e. origin at center of stage).

  if (isEmpty morphList) { return }
  overallBounds = (copy (bounds (first morphList)))
  for m morphList { merge overallBounds (bounds m) }
  xCenter = (hCenter overallBounds)
  yCenter = (vCenter overallBounds)
  for m morphList {
	setPosition m ((left m) - xCenter) ((top m) - yCenter)
  }
}

method installScripts Project scriptData {
  cmds = (toList (parse scriptData))
  if (isEmpty cmds) { return }

  myClass = nil
  scripts = (list)
  for cmd cmds {
    if ('defineClass' == (primName cmd)) {
      if (notNil myClass) {
        setScripts myClass (toArray scripts)
      }
      myClass = nil
      scripts = (list)
      args = (argList cmd)
      if ((count args) > 1) {
        callWith 'defineClass' args
        myClass = (class (first args))
        clearCaches myClass
      }
    } else {
      args = (argList cmd)
      if (not (and ('script' == (primName cmd)) ((count args) == 3))) { return (error 'Bad script file') }
      expr = (at args 3)
      if ('method' == (primName expr)) {
		if (isNil myClass) { error 'Implementation error: method script with no class' }
		methodArgs = (argList expr)
		methodName = (first methodArgs)
		methodParams = (copyFromTo methodArgs 2 ((count methodArgs) - 1))
		methodBody = (last methodArgs)
		addMethod myClass methodName methodParams methodBody
      }
      add scripts args
    }
  }
  if (notNil myClass) {
    setScripts myClass scripts
  }
}

method projectData1 Project {
  // Return the serialized data for an old (non-module-based) project.
  objectsToOmit = (dictionary)
  for p pages {
	for m (morphs p) {
	  if (notNil (owner m)) {
		add objectsToOmit (owner m)
	  }
	  preSerialize m
	}
  }
  serializedData = (write (new 'Serializer') this (keys objectsToOmit))
  projectVars = nil

  // make and save zip file
  zip = (create (new 'ZipFile'))
  addFile zip 'objects.gpod' serializedData true
  addFile zip 'scripts.txt' (collectScripts1 this) true
  return (contents zip)
}

method collectScripts1 Project {
  result = (list)
  for cl (classes) {
	if (notNil (scripts cl)) {
	  add result (scriptString cl true)
	}
  }
  return (joinStrings result)
}

// **** New (module-based) project open/save ****

method readProject2 Project data {
  initialize this
  zip = (read (new 'ZipFile') data)
  scriptData = (extractNestedFile zip 'scripts.txt')
  morphData = (extractNestedFile zip 'objects.gpod')
  modules = (dictionary)
  dependencies = (list)

  for f (fileNames zip) {
    if (beginsWith f 'modules/') {
      data = (extractFile zip f)
      data = (stringFromByteRange data 1 (byteCount data))
      atPut modules (stringFromByteRange f ((count 'modules/') + 1) (count f)) data
    } (beginsWith f 'dependencies/') {
      add dependencies (stringFromByteRange f ((count 'dependencies/') + 1) (count f))
    } (or (f == 'thumbnail') (f == 'thumbnail.png')) {
      data = (extractFile zip f)
      if ((count data) > 0) {
		thumbnail = (readFrom (new 'PNGReader') data)
	  }
    } (or (f == 'notes') (f == 'notes.txt')) {
      myNotes = (toString (extractFile zip f))
    }
  }

  if (notNil morphData) {
    project = (read (new 'Serializer2') morphData modules)
  }

  myHash = (toString (extractFile zip 'hash'))
  myAncestor = (toString (extractFile zip 'ancestor'))

  topHash = (toString (extractFile zip 'topHash'))
// Note: The top level module changes often, so comment this out.
// It is also slow and used memory to generate the code of the topLevelModule,
// so commenting this out out also speeds up project loading, especially in browsers.
//  if (topHash != (codeHash (topLevelModule))) {
//	print 'This project was created on a different top level module.'
//  }

  initializeFrom this project myHash myAncestor
  if (isEmpty pages) { pages = (list (newProjectPage (list))) }
  if (notNil scriptData) { installScripts2 this (toString scriptData) }
  if ((count myNotes) > 0) {
    // reading a format where notes is a distinct entry in zip.
    // Otherwise, we keep the one that came in binary of 'project'
    setNotes this myNotes
  } else {
    setNotes this ''
  }
  return this
}

method saveProject Project fName thumb {
  // Save this project to a file with the given name.

  data = (projectData2 this fName thumb)
  writeData this fName data
}

method projectData2 Project fName thumb {
  // Return the serialized data for this project using modules.

  thumbnail = nil
  myNotes = notes
  if (isNil myNotes) { myNotes = '' }
  notes = nil

  png = nil
  if (notNil thumb) {
    png = (encodePNG thumb)
  } else {
	png = '' // needed for hash
  }

  objectsToOmit = (dictionary)
  for p pages {
    for m (morphs p) {
      if (notNil (owner m)) {
        add objectsToOmit (owner m)
      }
      preSerialize m
    }
  }

  oldAncestor = ancestor
  oldHash = hash
  if (isNil oldHash) {
    oldHash = (sha256 '')
  }
  ancestor = nil
  hash = nil

  serializedData = (write (new 'Serializer2') this (keys objectsToOmit))

  // make and save zip file
  zip = (create (new 'ZipFile'))
  objects = (at serializedData 1)
  if (notNil png) {
    addFile zip 'thumbnail.png' png true
  }
  addFile zip 'notes.txt' myNotes true
  addFile zip 'objects.gpod' (at serializedData 1) true
  dict = (at serializedData 2)
  topHash = (at serializedData 3)
  keys = (keys dict)
  for m keys {
    d = (at dict m)
    addFile zip (join 'modules/' m) (at dict m)
    // code for the modules that are found during serialization
  }

  if (notNil dependencies) {
    // dependencies contains list of hashes of projects.
    for m dependencies {
      addFile zip (join 'dependencies/' m) ''
    }
  }

  addFile zip 'topHash' topHash

  data = (dataStream (newBinaryData (+ (byteCount objects) (byteCount oldHash) (byteCount topHash) (byteCount png) (byteCount myNotes))))
  nextPutAll data objects
  nextPutAll data oldHash
  nextPutAll data topHash
  nextPutAll data png
  nextPutAll data myNotes
  data = (contents data)

  ancestor = oldHash
  hash = (sha256 data)
  addFile zip 'hash' hash false
  addFile zip 'ancestor' ancestor false

  notes = myNotes
  thumbnail = thumb
  return (contents zip)
}

method installScripts2 Project scriptData {
  cmds = (toList (parse scriptData))
  if (isEmpty cmds) { return }

  myClass = nil
  scripts = (list)
  for cmd cmds {
    if ('defineClass' == (primName cmd)) {
      if (notNil myClass) {
        setScripts myClass (toArray scripts)
      }
      myClass = nil
      scripts = (list)
      args = (argList cmd)
	  myClass = (classNamed module (first args))
    } else {
      args = (argList cmd)
      if ('script' != (primName cmd)) { return (error 'Bad script file') }
      expr = (last args)
      if ('method' == (primName expr)) {
		if (isNil myClass) { error 'Implementation error: method script with no class' }
		methodArgs = (argList expr)
		methodName = (first methodArgs)
		methodParams = (copyFromTo methodArgs 2 ((count methodArgs) - 1))
		methodBody = (last methodArgs)
		if (isClass methodBody 'Command') {
		  addMethod myClass methodName methodParams methodBody
		}
      }
      if ((count args) == 4) {
		// new external format is: className x y body; remove classname for internal use
		args = (copyFromTo args 2)
	  }
      add scripts args
    }
  }
  if (notNil myClass) {
    setScripts myClass (toArray scripts)
  }
}

method convert Project {
  for cl (classes) {
	if (and (notNil (scripts cl)) ((module cl) == (topLevelModule))) {
	  removeClass (topLevelModule) cl
      setField module 'classes' (copyWith (classes module) cl)
      setField cl 'module' module
    }
  }
}

// server support

method readData Project location {
  if (beginsWith location 'http://') {
    m = (loadModule 'modules/DAVDirectory.gpm')
    u = (url (initialize (new (at m 'URIParser')) location))
    c = (new (at m 'DAVClient'))
    maybeSetAccountFromConfFile c location
    openURL c u
    val = (get c)
    return val
  }
  return (readFile location true)
}

method writeData Project location data {
  if (beginsWith location 'http://') {
    m = (loadModule 'modules/DAVDirectory.gpm')
    u = (url (initialize (new (at m 'URIParser')) location))
    c = (new (at m 'DAVClient'))
    maybeSetAccountFromConfFile c location
    openURL c u
    return (put c data)
  }
  return (writeFile location data)
}

// media

method imageNamed Project imageName {
  for img images {
	if (imageName == (name img)) { return img }
  }
  return nil
}

method soundNamed Project sndName {
  for snd sounds {
	if (sndName == (name snd)) { return snd }
  }
  return nil
}

method imageNames Project imageName {
  result = (list)
  for img images {
	if (notNil (name img)) { add result (name img) }
  }
  return result
}

method soundNames Project imageName {
  result = (list)
  for snd sounds {
	if (notNil (name snd)) { add result (name snd) }
  }
  return result
}

method saveImageAs Project bm name {
  // Add the given bitmap with given name to my images.
  // If name is nil or not a string, generate a unique name.

  if (or (not (isClass name 'String')) ('' == name)) {
  	name = (uniqueNameNotIn (imageNames this) 'snapshot')
  }
  setName bm name
  oldImg = (imageNamed this name)
  if (notNil oldImg) { remove images oldImg }
  add images bm
}

method saveSoundAs Project snd name {
  // Add the given sound with given name to my sounds.
  // If name is nil or not a string, generate a unique name.

  if (or (not (isClass name 'String')) ('' == name)) {
  	name = (uniqueNameNotIn (soundNames this) 'sound')
  }
  if (isClass snd 'Array') {
	snd = (newSound snd 22050 false name)
  }
  if (not (isClass snd)) {
	error 'Saved sound must be a sound object or an array of samples'
  }
  setName snd name
  oldSnd = (soundNamed this name)
  if (notNil oldSnd) { remove sounds oldSnd }
  add sounds snd
}

// extensions

method specsForCategory Project cat {
  result = (list)
  for op (at paletteBlocks cat (array)) {
	spec = (at blockSpecs op)
	if (notNil spec) { add result spec }
  }
  return result
}

method exportToExtensionCategory Project block {
  if (isEmpty extraCategories) { // skip menu if no categories yet
	selectCategoryForBlock this block 'new category...'
	return
  }
  menu = (menu nil (action 'selectCategoryForBlock' this block) true)
  for cat extraCategories {
	addItem menu cat cat
  }
  addLine menu
  addItem menu 'new category...'
  popUpAtHand menu (global 'page')
}

method selectCategoryForBlock Project block cat {
  scripter = (scripter (findProjectEditor))
  if ('new category...' == cat) {
	newCategory = (prompt (global 'page') 'Category name?')
	if ('' == newCategory) { return nil }
	newCategory = (uniqueNameNotIn (devModeCategories scripter) newCategory)
	if (not (contains extraCategories newCategory)) {
	  add extraCategories newCategory
	}
	cat = newCategory
  }
  op = (primName (expression block))
  addSpecToCategory this op (blockSpec block) cat
  developerModeChanged scripter // update palette
}

method addSpecToCategory Project op spec cat {
  atPut blockSpecs op spec
  opsForCat = (at paletteBlocks cat (list))
  atPut paletteBlocks cat opsForCat
  if (not (contains opsForCat op)) {
	add opsForCat op // add op to category
  }
}

method isUserDefinedBlock Project block {
  blockOp = (primName (expression block))
  return (contains blockSpecs blockOp)
}

method showingAnExtensionCategory Project {
  scripter = (scripter (findProjectEditor))
  return (contains paletteBlocks (currentCategory scripter))
}

method removeFromCurrentCategory Project block {
  scripter = (scripter (findProjectEditor))
  opsForCat = (at paletteBlocks (currentCategory scripter) (list))
  blockOp = (primName (expression block))
  remove opsForCat blockOp
  removeEmptyExtraCategories this
}

method blockDeleted Project op {
  remove blockSpecs op
  for opList (values paletteBlocks) {
	remove opList op
  }
  removeEmptyExtraCategories this
}

method removeEmptyExtraCategories Project {
  for k (keys paletteBlocks) {
	if (isEmpty (at paletteBlocks k)) {
	  remove paletteBlocks k
	  remove extraCategories k
	}
  }
  developerModeChanged (scripter (findProjectEditor)) // update palette
}

method importExtension Project extensionName extensionProj {
  callInitializer (module extensionProj)

  // add extension block specs to this project
  extSpecs = (blockSpecs extensionProj)
  for op (keys extSpecs) {
	if (contains blockSpecs op) {
	  print 'Warning: This project already has a block spec for' op
	} else {
	  atPut blockSpecs op (at extSpecs op)
	}
  }

  // add extension blocks to palette
  extBlocks = (paletteBlocks extensionProj)
  for cat (keys extBlocks) {
	opsForCat = (at paletteBlocks cat (list))
	atPut paletteBlocks cat opsForCat
	for op (at extBlocks cat) {
	  if (notNil (functionNamed op (module extensionProj))) {
		// op is a function in the extension module (not just a method), so
		// create a forwarding function that to invoke that function in the module
		oldOp = op
		oldSpec = (at blockSpecs oldOp)
		op = (createForwarderForImportedFunction this op (module extensionProj))
		setField oldSpec 'blockOp' op
		atPut blockSpecs op oldSpec
		remove blockSpecs oldOp
	  }
	  if (not (contains opsForCat op)) {
		add opsForCat op // add op to category
	  }
	}
	if (not (contains extraCategories cat)) {
	  add extraCategories cat
	}
  }

  if (isNil dependencies) {dependencies = (list)}
  extHash = (toString (getField extensionProj 'hash'))
  depIndex = (indexOf dependencies extHash)
  if (isNil depIndex) {
    add dependencies extHash
  }
}

method createForwarderForImportedFunction Project op extension {
  // The given op refers to a generic function in the given extensionModule.
  // Create a forwarding function that extracts the function from the extension
  // module and calls it. Return the op of the new function.

  extensions = (shared 'extensions' module )
  if (isNil extensions) { // create if needed
	extensions = (array)
	setShared 'extensions' extensions module
  }

  extensionIndex = (indexOf extensions extension)
  if (isNil extensionIndex) {
	// add extension to the shared extensions array
	extensions = (copyWith extensions extension)
	setShared 'extensions' extensions module
	extensionIndex = (count extensions)
  }

  // create a function to call function named 'op' in an extension module
  f = (copy (function {
	op = 'nop' // to be filled in with actual op
	extensionIndex = 0 // to be filled in with index of extension in (shared 'extensions')
	extensions = (shared 'extensions')
	if (isNil extensions) { return }
	extensionModule = (at extensions extensionIndex)
	realFunction = (functionNamed op extensionModule)

	argList = (list)
	for i (argCount) { add argList (arg i) }
	return (callWith realFunction (toArray argList))
  }))

  // modify f to fill in the op and extension index
  for b (allBlocks (cmdList f)) {
	if (and ('=' == (primName b)) (8 == (count b))) {
	  varName = (getField b 7)
	  if ('op' == varName) { setField b 8 op }
	  if ('extensionIndex' == varName) { setField b 8 extensionIndex }
	}
  }

  // find an unused name for f and save it in this project's module
  existingNames = (list op)
  for existingFunc (join (functions) (functions module)) {
	add existingNames (functionName existingFunc)
  }
  newOpName = (uniqueNameNotIn existingNames op)
  setField f 'functionName' newOpName
  addFunction module f

  return newOpName
}

// class removal support

method removeClassFromPages Project aClass {
  for p pages {
	morphs = (morphs p)
	newMorphs = (list)
	for m morphs {
	  if (not (isClass (handler m) aClass)) { add newMorphs m }
	}
	setMorphs p (toArray newMorphs)
  }
}

// initial media

method makeShip Project {
  data = 'iVBORw0KGgoAAAANSUhEUgAAACgAAAAeCAYAAABe3VzdAAABmElEQVR4nGNgZ2f/D8V/1dTUDoiLiycw
MDDwMAwWwMnJ+RvJkWAsICDwGejYBTw8PA5AJYwD6kBlZeUOkKO4ZLn+S1aL/eez4P3PzoFwrJSU1COg
mnYWFhblgXIjm6Ki4mWQY0Rihf4r75P7r7BS5r9YhvB/bgUulJBVUVE5LSEhkcpA7yQAjGYzcFRzsv+X
nSIJdiQY75X7LztZ8r9QgMB/TgFOuEP5+Pi+qaurrwQmBR+gdia6OBIW1dwq3P+VtssiHAnFIDHJxoFN
AhhRjQsPWBLAGdW48EAkAVB04YtqXJieSQAR1TH4o3rAkgDJUT0QSYDcqKZnEqA4qmmeBGBRzcHJ8V92
uhRVHQlLAjITJP4LevH/5+TnwNUWIBjV4AKcRxUY1Tsoj2pcWHGLzH/JSmASMOZBSQJD24GDPYqJrvoG
JJOgNB6oELVULWYGe0FNcdTStKojN2rp0lgY7M2twd1gBUZDJ76oHdAm/2DvNA3ubie84y7N+V+iWBSj
LpSRkbkP9EADMAqV6OYoZDDohz4G++ARAFGPsWx+VWYhAAAAAElFTkSuQmCC'
  bm = (readFrom (new 'PNGReader') (base64Decode data))
  setName bm 'ship'
  return bm
}

method makeGPLogo Project {
  bm = (newBitmap 100 100)
  fillRoundedRect (newVectorPen bm) (rect 1 1 99 99) 10 (gray 250) 2 (gray 0)
  setFont 'Verdana' 66
  c = (color 56 191 40)
  drawString bm 'G' c 6 8
  drawString bm 'P' c 55 8
  setName bm 'GP'
  return bm
}

method makePopSound Project {
  samples = (array
  	213 771 1981 3442 5615 7507 9020 9371 8418 5803 1651 -3755 -9633 -15264 -19571
	-22167 -22382 -19995 -15033 -7871 755 9965 18385 24906 28541 28707 24842 17614 7658 -3286
	-14065 -22678 -28163 -29403 -26386 -19143 -8728 3298 15005 24644 30320 31157 26786 17880 5991
	-7094 -19092 -28038 -32290 -31125 -24719 -14194 -991 12514 23933 31199 32740 28983 19881 7350
	-6231 -18353 -26996 -30461 -28311 -20913 -9739 3164 15360 24400 28655 26903 20054 9226 -3471
	-15015 -23705 -27722 -26248 -19720 -9624 2467 13966 22379 26153 24482 18108 8181 -3384 -13821
	-21003 -23858 -21729 -15310 -5391 5312 14763 20776 22257 18740 11086 1027 -9428 -17730 -22292
	-22258 -17199 -8820 1724 11836 19328 22804 21031 14685 5036 -5604 -14991 -21075 -22743 -19526
	-12261 -2384 7845 16250 20936 20938 16235 8061 -1561 -10541 -16767 -18913 -16811 -10836 -2628
	6186 13186 16885 16516 12076 4876 -3497 -10849 -15437 -16395 -13452 -7268 634 8314 13961
	16262 14546 9274 1731 -6254 -12773 -16506 -16376 -12523 -5807 2155 9598 14880 16648 14517
	9110 1619 -6097 -12458 -15830 -15638 -11942 -5627 1865 8852 13783 15568 13804 9034 2394
	-4537 -10213 -13449 -13555 -10650 -5521 689 6546 10803 12408 11178 7484 2292 -3228 -7745
	-10312 -10506 -8276 -4336 461 4905 8028 9128 8008 5035 943 -3246 -6544 -8262 -7973
	-5837 -2356 1572 5083 7410 8010 6788 4041 380 -3356 -6347 -7923 -7802 -6022 -2969
	673 4140 6751 7952 7564 5726 2877 -396 -3353 -5430 -6250 -5756 -4128 -1799 724
	2824 4170 4498 3801 2359 537 -1159 -2403 -2922 -2595 -1577 -225 1166 2199 2583
	2186 1109 -415)
  return (newSound samples 11025 false 'pop')
}

defineClass ProjectPage label morphs

method label ProjectPage { return label }
method setLabel ProjectPage s { label = s }

method morphs ProjectPage { return morphs }
method setMorphs ProjectPage morphList { morphs = (toArray morphList) }

to newProjectPage morphList label {
  if (isNil label) { label = '' }
  result = (new 'ProjectPage')
  setLabel result label
  setMorphs result morphList
  return result
}
