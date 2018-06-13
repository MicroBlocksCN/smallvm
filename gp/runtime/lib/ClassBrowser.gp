// Browse a single GP class

defineClass ClassBrowser morph window viewedClass fields fieldsFrame methods methodsFrame scripts scriptsFrame currentFunction editedFunction wasEdited

to browseClass aClass methodName {
  if ('<primitive>' == aClass) {
    showPrimitive (newSystemPalette) methodName
    return
  }
  page = (global 'page')
  brs = (newClassBrowser)
  setPosition (morph brs) (x (hand page)) (y (hand page))
  addPart page brs
  if ('<generic>' == aClass) {
    aClass = (globalBlocksName brs)
  }
  if (aClass == (globalBlocksName brs)) {
    browse brs (globalBlocksName brs) (functionNamed methodName (topLevelModule))
  } (notNil aClass) {
    if (isClass aClass 'String') { aClass = (class aClass) }
    browse brs aClass (methodNamed aClass methodName)
  }
}

to newClassBrowser {
  return (initialize (new 'ClassBrowser'))
}

method initialize ClassBrowser {
  scale = (global 'scale')
  window = (window 'Class Browser')
  bg = (gray 240)
  morph = (morph window)
  setHandler morph this
  setMinExtent morph (scale * 300) (scale * 200)

  fields = (listBox (array) (action 'fieldRepresentation' this) (action 'selectField' this) bg nil nil 230)
  fieldsFrame = (scrollFrame fields bg)
  addPart morph (morph fieldsFrame)

  methods = (listBox (array) 'blockForFunction' (action 'selectMethod' this) bg (action 'blockify' this) nil 230)
  methodsFrame = (scrollFrame methods bg)
  addPart morph (morph methodsFrame)

  scripts = (newScriptEditor 10 10)
  scriptsFrame = (scrollFrame scripts bg)
  addPart morph (morph scriptsFrame)

  wasEdited = false
  setExtent morph (scale * 400) (scale * 300)
  return this
}

method globalBlocksName ClassBrowser { return '<Global Blocks>' }

method classListName ClassBrowser aClass {
  if (aClass == (globalBlocksName this)) {return aClass}
  return (className aClass)
}

method sortedFunctions ClassBrowser {
  return (sorted (functions (topLevelModule)) (function f1 f2 { return ((functionName f1) < (functionName f2)) }))
}

method fixLayout ClassBrowser {
  fieldsWidth = (action 'spaceBoundedBy' window 350 30 (width morph))
  methodsWidth = (action 'width' (morph fieldsFrame))

  fixLayout window
  packer = (newPanePacker (clientArea window) ((border window) / (global 'scale')))
  packPanesH packer fieldsFrame fieldsWidth scriptsFrame 'rest'
  packPanesH packer methodsFrame methodsWidth scriptsFrame 'rest'
  packPanesV packer fieldsFrame '30%' methodsFrame 'rest'
  packPanesV packer scriptsFrame '100%'
  finishPacking packer
}

method redraw ClassBrowser {
  redraw window
  fixLayout this
}

method blockify ClassBrowser aFunction {
  page = (page morph)
  if (isNil (cmdList aFunction)) { return } // empty function
  block = (toBlock (cmdList aFunction))
  setPosition (morph block) (x (hand page)) (y (hand page))
  addPart page block
}

method browse ClassBrowser aClass methodOrName {
  selectMethod this nil
  viewedClass = aClass
  if (aClass == (globalBlocksName this)) {
    setLabelString window 'Global Variables and Blocks'
    setCollection fields (variableNames (sessionModule))
  } else {
    setLabelString window (join 'Class Browser: ' (className aClass))
    setCollection fields (fieldNames aClass)
  }
  setCollection methods (sortedMethods this aClass)
  if (notNil methodOrName) {
    if (isClass methodOrName 'String') {
      select methods (methodNamed aClass methodOrName)
    } else {
      select methods methodOrName
    }
    if (notNil (selectedMorph methods)) {
      scrollIntoView methodsFrame (bounds (selectedMorph methods))
    }
  }
}

method selectField ClassBrowser fieldName {
  if (shiftKeyDown (keyboard (handler (root morph)))) {
    unselectFields this
    return
  }
  setCollection methods (accessors this fieldName)
}

method unselectFields ClassBrowser {
  select fields nil
  mth = (array)
  if (notNil viewedClass) { mth = (sortedMethods this viewedClass) }
  setCollection methods mth
}

method accessors ClassBrowser fieldName {
  result = (list)
  for m (sortedMethods this viewedClass) {
    if (contains (varsUsed m) fieldName) {add result m}
  }
  return (toArray result)
}

method fieldRepresentation ClassBrowser fieldName {
  if (viewedClass == (globalBlocksName this)) {
    return (newReporter 'global' fieldName)
  }
  return (newReporter 'my' fieldName)
}

method sortedMethods ClassBrowser aClass {
  if (aClass == (globalBlocksName this)) {return (sortedFunctions this)}
  return (sorted (methods aClass) (function f1 f2 { return ((functionName f1) < (functionName f2)) }))
}

method selectMethod ClassBrowser aFunction {
  if wasEdited {
  msg = 'This function has been edited.
Save it?'
  if (confirm (page morph) 'Save Changes?' msg) {
      saveEditedFunction this
    }
  }
  currentFunction = aFunction
  editedFunction = nil
  if (notNil currentFunction) { editedFunction = (copy aFunction) }
  wasEdited = false
  refreshEditedFunction this
}

method refreshEditedFunction ClassBrowser {
  removeAllParts (morph scripts)
  if (isNil editedFunction) {return}
  block = (scriptForFunction editedFunction)
  setGrabRule (morph block)'ignore'
  setPosition (morph block) (left (morph scripts)) (top (morph scripts))
  off = ((global 'scale') * 10)
  moveBy (morph block) off off
  addPart (morph scripts) (morph block)
  frame = (handler (owner (morph scripts)))
  setPosition (morph scripts) (left (morph frame)) (top (morph frame))
  updateSliders frame
}

// field unselect

method handDownOn ClassBrowser hand {
  // Unselect the selected field, if any, if user clicks below the last field in fieldsFrame.

  if (containsPoint (bounds (morph fieldsFrame)) (x hand) (y hand)) { unselectFields this }
  return false
}

// top bar menu

method rightClicked ClassBrowser aHand {
  popUpAtHand (contextMenu this) (page aHand)
  return true
}

method contextMenu ClassBrowser {
  menu = (menu nil this)
  addItem menu 'find system block matching...' (action 'findBlock' (newSystemPalette))
  addItem menu 'find primitives matching...' (action 'findPrimitive' (newSystemPalette))
  return menu
}

// context menus

method handleContextRequest ClassBrowser origin {
  if (origin == fieldsFrame) {
    menu = (fieldListContextMenu this)
  } (origin == methodsFrame) {
    menu = (methodListContextMenu this)
  }
  if (notNil menu) {
    popUpAtHand menu (global 'page')
  }
}

method handleListContextRequest ClassBrowser anArray {
  origin = (first anArray)
  dta = (data (last anArray))
  if (origin == fields) {
    menu = (fieldContextMenu this dta)
  } (origin == methods) {
    menu = (methodContextMenu this dta)
  }
  if (notNil menu) {
    popUpAtHand menu (global 'page')
  }
}

method fieldListContextMenu ClassBrowser {
  menu = (menu nil this)
  if (notNil (selection fields)) {
    addLine menu
    addItem menu 'unselect' (action 'unselectFields' this)
  }
  return menu
}

method fieldContextMenu ClassBrowser fieldName {
  menu = (menu nil this)
  addBlock this (toBlock (fieldRepresentation this fieldName)) menu
  if (notNil (selection fields)) {
    addItem menu 'unselect' (action 'unselectFields' this)
  }
  return menu
}

method methodListContextMenu ClassBrowser {
  menu = (menu nil this)
  if (notNil viewedClass) {
    addItem menu 'make a block...' 'makeNewBlock' (join 'add a new method to class ' (classListName this viewedClass))
  }
  return menu
}

method methodContextMenu ClassBrowser aFunction {
  menu = (menu nil this)
  addBlock this (blockForFunction aFunction) menu
  addItem menu 'delete...' (action 'deleteFunction' this aFunction viewedClass)
  addItem menu 'other implementations...' (action 'browseImplementors' this aFunction viewedClass)
  if (notNil viewedClass) {
    addLine menu
    addItem menu 'make a block...' 'makeNewBlock' (join 'add a new method to class ' (classListName this viewedClass))
  }
  return menu
}

method addBlock ClassBrowser aBlock menu {
  addItem menu (fullCostume (morph aBlock)) (action 'grab' this aBlock) 'pick up this block and use it in a script'
}

method grab ClassBrowser aBlock {
  h = (hand (global 'page'))
  setCenter (morph aBlock) (x h) (y h)
  grab h aBlock
}

method makeNewBlock ClassBrowser {
  page = (global 'page')
  if (isNil viewedClass) {return}
  name = (prompt page 'Enter a new block name:' 'myBlock')
  if (name == '') {return}
  if (viewedClass == (globalBlocksName this)) {
    for f (functions (topLevelModule)) {
      if (name == (functionName f)) {
        inform page (join 'a global block named' (newline) name (newline)'already exists')
        return
      }
    }
    func = (defineFunctionInModule (topLevelModule) name)
    setCollection methods (sortedFunctions this)
  } else {
    for f (methods viewedClass) {
      if (name == (functionName f)) {
        inform page (join 'a block named' (newline) name (newline) 'already exists in class' (newline) (className viewedClass))
        return
      }
    }
    func = (addMethod viewedClass name)
    spec = (blockSpecFromStrings name ' ' (join name ' _') (className viewedClass))
    setCollection methods (sortedMethods this viewedClass)
  }
  select methods func
  scrollIntoView methodsFrame (bounds (selectedMorph methods))
}

method deleteFunction ClassBrowser method class {
  if (viewedClass == (globalBlocksName this)) {
    if (confirm (global 'page') nil (join 'Are you sure you want to delete the global block named' (newline) (functionName method) '?')) {
      remove (globalFuncs) (functionName method)
      if (method == (selection methods)) {
        select methods nil
        selectMethod this nil
      }
      setCollection methods (sortedMethods this class)
    }
  } else {
    if (confirm (global 'page') nil (join 'Are you sure you want to delete the block named' (newline) (functionName method) (newline) (join 'from class ' (classListName this class) '?'))) {
      removeMethodNamed class (functionName method)
      if (method == (selection methods)) {
        select methods nil
        selectMethod this nil
      }
      setCollection methods (sortedMethods this class)
    }
  }
}

method browseImplementors ClassBrowser method class {
  name = (functionName method)
  implementors = (implementors name)
  others = (list)
  if (isClass viewedClass 'Class') { selectedClassName = (className viewedClass) }
  for each implementors {
    if (each != selectedClassName) {add others each}
  }
  if (isEmpty others) {
    inform (global 'page') (join name (newline) 'is not implemented' (newline) 'anywhere else')
    return
  }
  menu = (menu (join 'other implementations of' (newline) name) (action 'openBrowserOnOtherImplementation' this name) true) // reverse call
  for each others {
    addItem menu (join each '...') each
  }
  popUpAtHand menu (global 'page')
}

method openBrowserOnOtherImplementation ClassBrowser functionName aClassName {
  browseClass aClassName functionName
}

// reflect user edits

method wasEdited ClassBrowser { return wasEdited }

method functionBodyChanged ClassBrowser {
  wasEdited = true
}

method saveEditedFunction ClassBrowser {
  setField currentFunction 'argNames' (argNames editedFunction)
  updateCmdList currentFunction (cmdList editedFunction)
  editedFunction = (copy currentFunction)
  wasEdited = false
  for item (parts (morph methods)) {
    meth = (data (handler item))
    if (meth == currentFunction) {
      (replaceCostumes (handler item) nil nil nil)
      refresh (handler item)
      if (currentfunction == (selection methods)) {
        selectMethod this currentFunction
      }
    }
  }
  selectMethod this currentFunction
}

method revertEditedFunction ClassBrowser {
  wasEdited = false
  selectMethod this currentFunction
}

// serialization

method preSerialize ClassBrowser { preSerialize scripts }
method postSerialize ClassBrowser { postSerialize scripts }
