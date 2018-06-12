// explore the GP code base

defineClass Synopsis morph window globals globalsFrame globalScripts localScripts globalScriptsFrame localScriptsFrame classes classesFrame fieldTabs fieldTabsFrame fields fieldsFrame methods methodsFrame functionTabs globalTabs localTabs methodTabs methodTabsFrame globalCode globalCodeFrame localCode localCodeFrame

to newSynopsis {
  syn = (new 'Synopsis')
  initialize syn
  return syn
}

method initialize Synopsis {
  scale = (global 'scale')
  window = (window 'Synopsis')
  border = (border window)
  clr = (clientColor window)
  morph = (morph window)
  setHandler morph this
  setMinExtent morph (scale * 300) (scale * 200)

  functionTabs = (tabBar (array 'text' 'blocks') nil (action 'functionTab' this 'functions'))
  addPart morph (morph functionTabs)

  globals = (listBox (sortedFunctions this) 'functionName'  (action 'selectGlobal' this) clr (action 'blockify' this))
  globalsFrame = (scrollFrame globals clr)
  addPart morph (morph globalsFrame)

  globalTabs = (tabBar (array 'text' 'blocks') nil (action 'tab' this 'global'))
  addPart morph (morph globalTabs)

  globalCode = (newText)
  setEditRule globalCode 'code'
  setGrabRule (morph globalCode) 'ignore'
  setBorders globalCode border border true

  globalCodeFrame = (scrollFrame globalCode clr)
  addPart morph (morph globalCodeFrame)

  globalScripts = (newScriptEditor 10 10)

  classes = (listBox (sortedClasses this) 'className'  (action 'selectClass' this) clr)
  classesFrame = (scrollFrame classes clr)
  addPart morph (morph classesFrame)

  fieldTabs = (tabBar (array 'text' 'blocks') nil (action 'fieldTab' this))
  fieldTabsFrame = (newMorph)
  setClipping fieldTabsFrame true true
  addPart fieldTabsFrame (morph fieldTabs)
  addPart morph fieldTabsFrame

  fields = (listBox (array) 'id' (action 'selectField' this) clr)
  fieldsFrame = (scrollFrame fields clr)
  addPart morph (morph fieldsFrame)

  localTabs = (tabBar (array 'text' 'blocks') nil (action 'tab' this 'local'))
  addPart morph (morph localTabs)

  methodTabs = (tabBar (array 'text' 'blocks') nil (action 'functionTab' this 'methods'))
  methodTabsFrame = (newMorph)
  setClipping methodTabsFrame true true
  addPart methodTabsFrame (morph methodTabs)
  addPart morph methodTabsFrame

  methods = (listBox (array) 'functionName' (action 'selectMethod' this) clr (action 'blockify' this))
  methodsFrame = (scrollFrame methods clr)
  addPart morph (morph methodsFrame)

  localScripts = (newScriptEditor 10 10)

  localCode = (newText)
  setEditRule localCode 'code'
  setGrabRule (morph localCode) 'ignore'
  setBorders localCode border border true

  localCodeFrame = (scrollFrame localCode clr)
  addPart morph (morph localCodeFrame)

  setExtent morph (scale * 400) (scale * 300)

  setFramePadding (alignment functionTabs) (4 * scale)
  fixLayout (alignment functionTabs)
  select functionTabs 'text' true

  setFramePadding (alignment globalTabs) (4 * scale)
  fixLayout (alignment globalTabs)
  select globalTabs 'text' true

  setFramePadding (alignment fieldTabs) (4 * scale)
  fixLayout (alignment fieldTabs)
  select fieldTabs 'text' true

  setFramePadding (alignment methodTabs) (4 * scale)
  fixLayout (alignment methodTabs)
  select methodTabs 'text' true

  setFramePadding (alignment localTabs) (4 * scale)
  fixLayout (alignment localTabs)
  select localTabs 'text' true
}

method sortedFunctions Synopsis {
  return (sorted (functions) (function f1 f2 { return ((functionName f1) < (functionName f2)) }))
}

method sortedClasses Synopsis {
  return (sorted (classes) (function c1 c2 { return ((className c1) < (className c2)) }))
}

method fixLayout Synopsis {
  fixLayout window
  clientArea = (clientArea window)
  border = (border window)

  setPosition (morph functionTabs) (left clientArea) (top clientArea)

  setPosition (morph globalsFrame) (left clientArea) (bottom (morph functionTabs))
  setExtent (morph globalsFrame) (((width clientArea) / 2) - border) ((((height clientArea) / 2) - border) - (height (morph functionTabs)))

  setPosition (morph globalTabs) (left (morph globalsFrame)) (+ (bottom (morph globalsFrame)) border)

  setPosition (morph globalCodeFrame) (left (morph globalsFrame)) (bottom (morph globalTabs))
  setExtent (morph globalCodeFrame) (width (morph globalsFrame)) (((height clientArea) / 2) - (height (morph globalTabs)))

  setPosition (morph classesFrame) (+ (right (morph globalsFrame)) border) (top clientArea)
  setExtent (morph classesFrame) ((width clientArea) / 4) (+ (height (morph globalsFrame)) (height (morph functionTabs)))

  setPosition fieldTabsFrame (+ (right (morph classesFrame)) border) (top clientArea)
  setExtent fieldTabsFrame (((width clientArea) / 4) - border) (height (morph fieldTabs))

  setPosition (morph fieldsFrame) (+ (right (morph classesFrame)) border) (bottom fieldTabsFrame)
  setExtent (morph fieldsFrame) (((width clientArea) / 4) - border) ((((height clientArea) / 5) - border) - (height fieldTabsFrame))

  setPosition methodTabsFrame (+ (right (morph classesFrame)) border) (+ (bottom (morph fieldsFrame)) border)
  setExtent methodTabsFrame (width (morph fieldsFrame)) (height (morph methodTabs))

  setPosition (morph methodsFrame) (+ (right (morph classesFrame)) border) (bottom methodTabsFrame)
  setExtent (morph methodsFrame) (width (morph fieldsFrame)) (- (- (- ((height clientArea) / 2) (height (morph fieldsFrame))) (border * 2)) (height (morph methodTabs)))

  setPosition (morph localTabs) (+ (right (morph globalsFrame)) border) (+ (bottom (morph classesFrame)) border)

  setPosition (morph localCodeFrame) (left (morph localTabs)) (bottom (morph localTabs))
  setExtent (morph localCodeFrame) ((width (morph globalsFrame)) + border) (((height clientArea) / 2) - (height (morph globalTabs)))
}

method redraw Synopsis {
  redraw window
  fixLayout this
}

method selectGlobal Synopsis aFunction {
  setText globalCode (codeFor this aFunction)
  removeAllParts (morph globalScripts)
  if (isVisible (morph globalScripts)) {
    showBlocks this aFunction globalScripts
  }
}

method showBlocks Synopsis aFunction aPane {
  removeAllParts (morph aPane)
  if (isNil aFunction) {return}
  block = (scriptForFunction aFunction)
  setGrabRule (morph block)'ignore'
  setPosition (morph block) (left (morph aPane)) (top (morph aPane))
  off = ((global 'scale') * 10)
  moveBy (morph block) off off
  addPart (morph aPane) (morph block)
  frame = (handler (owner (morph aPane)))
  setPosition (morph aPane) (left (morph frame)) (top (morph frame))
  updateSliders frame
}

method functionTab Synopsis target choice {
  if (target == 'methods') {
    listPane = methods
    frame = methodsFrame
  } (target == 'functions') {
    listPane = globals
    frame = globalsFrame
  }
  if (choice == 'text') {
    setField listPane 'getEntry' 'functionName'
    setField listPane 'normalAlpha' 255
  } (choice == 'blocks') {
    setField listPane 'getEntry' 'blockForFunction'
    setField listPane 'normalAlpha' 230
  }
  updateMorphContents listPane
  sel = (selectedMorph listPane)
  if (notNil sel) {scrollIntoView frame (bounds sel)}
}

method fieldTab Synopsis choice {
  if (choice == 'text') {
    setField fields 'getEntry' 'id'
    setField fields 'normalAlpha' 255
  } (choice == 'blocks') {
    setField fields 'getEntry' (action 'newReporter' 'v')
    setField fields 'normalAlpha' 230
  }
  idx = (selectionIndex fields)
  updateMorphContents fields
  if (notNil idx) {
    select fields (at (collection fields) idx)
    sel = (selectedMorph fields)
    if (notNil sel) {scrollIntoView fieldsFrame (bounds sel)}
  }
}

method tab Synopsis target choice {
  if (target == 'global') {
    frame = globalCodeFrame
    text = globalCode
    scripts = globalScripts
    listPane = globals
  } (target == 'local') {
    frame = localCodeFrame
    text = localCode
    scripts = localScripts
    listPane = methods
  }
  if (choice == 'text') {
    setContents frame text
  } (choice == 'blocks') {
    setContents frame scripts
    if (isEmpty (parts (morph scripts))) {
      showBlocks this (selection listPane) scripts
    }
  }
}

method blockify Synopsis aFunction {
  page = (page morph)
  block = (toBlock (cmdList aFunction))
  setPosition (morph block) (x (hand page)) (y (hand page))
  addPart page block
}

method browse Synopsis aClass {
  select classes aClass
  scrollIntoView classesFrame (bounds (selectedMorph classes))
}

method selectClass Synopsis aClass {
  setCollection fields (fieldNames aClass)
  setCollection methods (sortedMethods this aClass)
}

method selectField Synopsis fieldName {
  if (shiftKeyDown (keyboard (handler (root morph)))) {
    select fields nil
    cls = (selection classes)
    mth = (array)
    if (notNil cls) {mth = (sortedMethods this cls)}
    setCollection methods mth
    return
  }
  setCollection methods (accessors this fieldName)
}

method accessors Synopsis fieldName {
  result = (list)
  for m (sortedMethods this (selection classes)) {
    if (contains (varsUsed m) fieldName) {add result m}
  }
  return (toArray result)
}


method sortedMethods Synopsis aClass {
  return (sorted (methods aClass) (function f1 f2 { return ((functionName f1) < (functionName f2)) }))
}

method selectMethod Synopsis aFunction {
  setText localCode (codeFor this aFunction)
  removeAllParts (morph localScripts)
  if (isVisible (morph localScripts)) {
    showBlocks this aFunction localScripts
  }
  func = (functionNamed (functionName aFunction))
  if (notNil func) {
    select globals func
    scrollIntoView globalsFrame (bounds (selectedMorph globals))
  }
}

method codeFor Synopsis aFunction {
  pp = (new 'PrettyPrinter')
  // parms = ''
  // for each (argNames aFunction) {parms = (join parms ' ' each)}
  // code = (join (functionName aFunction) ' ' parms (newline))
  code = ''
  nb = (cmdList aFunction)
  while (notNil nb) {
    code = (join code (prettyPrint pp nb) (newline))
    nb = (nextBlock nb)
  }
  return code
}

method textChanged Synopsis origin {
  if (origin === globalCode) {
    cmd  = (parse this globalCode)
    if (notNil cmd) {setField (selection globals) 'cmdList' cmd}
    selectGlobal this (selection globals)
  } else {
    cmd  = (parse this localCode)
    if (notNil cmd) {setField (selection methods) 'cmdList' cmd}
    selectMethod this (selection methods)
  }
}

method parse Synopsis aText {
  parsed = (parse (join '{' (text aText) '}'))
  if ((count parsed) != 1) {return nil}
  element = (at parsed 1)
  if (isClass element 'Command') {return element}
  return nil
}

// serialization

method preSerialize Synopsis {
  // Clear the function and classs lists before serializing. We don't want
  // to save them and the environment may be different when deserialized).
  setCollection globals (array)
  setCollection classes (array)

  // depending on the tab settings, some of these components may not be
  // in the morph structure, so call preSerialize manually on them
  preSerialize globalCode
  preSerialize localCode
  preSerialize globalScripts
  preSerialize localScripts
}

method postSerialize Synopsis {
  // Restore the function and classs lists.
  setCollection globals (sortedFunctions this)
  setCollection classes (sortedClasses this)

  // depending on the tabs, some of these components may not be
  // in the morph structure, so call postSerialize manually on them
  postSerialize globalCode
  postSerialize localCode
  postSerialize globalScripts
  postSerialize localScripts
}
