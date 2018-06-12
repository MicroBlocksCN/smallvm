// Debugger - Can be used from either the command line or a morphic UI.

defineClass Debugger debugeeTask vars morph window reasonText reasonPane buttonsPane callsFrame codeFrame fileAndLineFrame varsFrame valueFrame originalCmds

method stack Debugger { return (stack debugeeTask) }

to debug {
  comment 'To debug the last error, make an debugger instance like this:
	  db = (debug)
	and invoke debugging commands on db (use "cmds db" to list the debugging commands).'

  if (isNil (debugeeTask)) {
	print 'There is no debugee task to debug.'
	return
  }
  db = (new 'Debugger' (debugeeTask))
  gc
  cmds db
  calls db
  if (notNil (global 'page')) { addPart (global 'page') db }
  return db
}

to printStackTrace aTask {
  db = (new 'Debugger' aTask)
  calls db
}

method cmds Debugger {
  print 'Welcome to the GP debugger! Commands:'
  print '  cmds db - print this list of debugger commands'
  print '  calls db - print the call stack'
  print '  receiver db - returns the last receiver object'
  print '  arg db - returns the specified arg on the last frame'
  print '  show db [n] - show the N-th stack frame (frame 1 (the default) is the most recently called function)'
  print '  proceed db - continue from the point where execution was halted'
  print '  singleStep db - execute the next command and stop'
  print '  restart db n - restart the N-th function call'
  print '  showStack db - show the stack as a bunch of numbers (very low level)'
}

method calls Debugger {
  frames = (frameList this)
  b = (getField debugeeTask 'currentBlock')
  if (isNil b) {
    print 'Debuggee is done.'
    return
  }
  print '-------------'
  if (isEmpty frames) {
    print 'Top level.'
  }
  frameCount = (count frames)
  if (frameCount > 100) {
	print '(Big stack; showing only the last 100 frames)'
	startFrame = (frameCount - 100)
	for i (range startFrame (count frames)) {
	  printCall this (at frames i)
	}
  } else {
	for i (count frames) {
	  printCall this (at frames i)
	}
  }
  printCurrentBlock this
  print '-------------'
}

method show Debugger n {
  stack = (stack debugeeTask)
  frames = (frameList this)
  if ((count frames) == 0) {
    print 'No function calls on debugee stack.'
	return
  }
  if (isNil n) { n = 1 }
  n = (clamp n 1 (count frames))
  mp = (at frames n)
  print '-----' n '-----'
  printCall this mp

  func = (at stack (mp + 1))
  argNames = (argNames func)
  localNames = (localNames func)

  fp = (at stack (mp - 1))
  argCount = (((mp - fp) - 1) - (count localNames))
  if (argCount > 0) { print ' Arguments:' }
  for i argCount {
    arg = (at stack ((fp + i) - 1))
	if (i <= (count argNames)) {
	  print '  ' (at argNames i) ':' arg
    } else {
	  print '  ' i ':' arg
    }
  }

  localCount = (count localNames)
  if (localCount > 0) { print ' Locals:' }
  for i localCount {
    v = (at stack ((mp - i) - 1))
	print '  ' (at localNames i) ':' v
  }
  print '-------------'
}

method receiver Debugger {
  stack = (stack debugeeTask)
  if (isNil stack) { return nil }
  mp = (getField debugeeTask 'mp')
  fp = (at stack (mp - 1))
  return (at stack fp)
}

method arg Debugger n {
  if (isNil n) { n = 1 }
  stack = (stack debugeeTask)
  mp = (getField debugeeTask 'mp')
  if (0 == mp) {
	print 'No calls on stack.'
	return
  }
  fp = (at stack (mp - 1))
  func = (at stack (mp + 1))
  localNames = (localNames func)
  argCount = (((mp - fp) - 1) - (count localNames))
  if (or (n < 1) (n > argCount)) {
	print 'The argument index must be 1 to' argCount
	return
  }
  return (at stack (fp + (n - 1)))
}

method singleStep Debugger {
  resumeDebuggee this true
  calls this
}

method proceed Debugger {
  resumeDebuggee this
  calls this
}

method resumeDebuggee Debugger doSingleStep {
  setField debugeeTask 'waitReason' nil
  setField debugeeTask 'taskToResume' (currentTask)
  resume debugeeTask doSingleStep
}

method restart Debugger n {
  frames = (frameList this)
  if ((count frames) == 0) {
    print 'No function calls on debugee stack.'
	return
  }
  mp = (at frames n)
  func = (at (stack debugeeTask) (mp + 1))
  sp = (mp + 5)

  setField debugeeTask 'sp' sp
  setField debugeeTask 'fp' sp
  setField debugeeTask 'mp' mp
  setField debugeeTask 'currentBlock' true // must be non-nil
  setField debugeeTask 'nextBlock' (cmdList func)
  resumeDebuggee this
  calls this
}

method showStack Debugger {
  stack = (stack debugeeTask)
  sp = (getField debugeeTask 'sp')
  for i sp {
    print (join '' i ':') (carefulPrint this (at stack i))
  }
}

method printCurrentBlock Debugger {
  // Print the block that just executed (or failed).

  stack = (stack debugeeTask)
  b = (getField debugeeTask 'currentBlock')
  if (isNil b) { return }
  sp = (getField debugeeTask 'sp')
  i = (getField debugeeTask 'fp')
  out = (list '  -> ')
  add out (fileAndLine this b)
  add out (primName b)
  while (i < sp) {
    add out (join ' ' (carefulPrint this (at stack i)))
	i += 1
  }
  print (joinStrings out)
}

method printCall Debugger mp {
  // Print the call name, fileName and lineNumber, and arguments.
  print (callString this mp true)
}

method callString Debugger mp showFileAndLine {
  // Return a string containing the call name, fileName and lineNumber, and arguments.

  stack = (stack debugeeTask)
  b = (at stack (mp + 3))
  args = (argsForCall this mp)
  out = (list)
  if showFileAndLine { add out (fileAndLine this b) }
  add out (withUserSpec this (toString (primName b)))

  for i (count args) { add out (join ' ' (carefulPrint this (at args i))) }
  return (joinStrings out)
}

method withUserSpec Debugger op {
  editor = (findProjectEditor)
  if (notNil editor) {
	spec = (at (blockSpecs (project editor)) op)
	if (notNil spec) { return (first (specs spec)) }
  }
  return op
}

method fileAndLine Debugger b {
  return (join '(' (filePart (fileName b)) ':' (lineno b) ') ')
}

method argsForCall Debugger mp {
  // Argument list for the given method or function call frame.

  stack = (stack debugeeTask)
  func = (at stack (mp + 1))
  localNames = (localNames func)

  fp = (at stack (mp - 1))
  argCount = (((mp - fp) - 1) - (count localNames))
  args = (list)
  for i argCount { add args (at stack ((fp + i) - 1)) }
  return args
}

method carefulPrint Debugger obj {
  if (and (isClass obj 'String') ((byteCount obj) < 100)) { return obj }
  if (implements obj 'toString') { // don't trust object's toString method
    return (join '<' (className (classOf obj)) '>')
  }
  return (toString obj) // primitive toString
}

method frameList Debugger {
  // List of call frames (i.e. mp values) for the function/method call stack.

  stack = (stack debugeeTask)
  if (isNil stack) { return (array) }
  frames = (list)
  mp = (getField debugeeTask 'mp')
  while (mp > 1) {
    add frames mp
    mp = (at stack (mp + 2))
  }
  frames = (reversed (toArray frames))
  return frames
}

// Morphic UI support starts here

method morph Debugger {
  // Build the UI when the debugger is first added to a page.
  if (isNil morph) {
    buildUI this
    updateStack this
  }
  return morph
}

method buildUI Debugger {
  scale = (global 'scale')
  window = (window 'Debugger')
  morph = (morph window)
  setHandler morph this
  setFPS morph 1
  clr = (clientColor window)
  fontSize = 15

  reasonPane = (newBox nil (gray 250) nil nil false false)
  addPart morph (morph reasonPane)

  buttonsPane = (newBox nil (gray 250) nil nil false false)
  addPart morph (morph buttonsPane)

  reasonText = (newText 'Reason:' 'Arial' (scale * fontSize))
  setEditRule reasonText 'static'
  addPart morph (morph reasonText)

//   addPart (morph buttonsPane) (makeButton this 'Enter' 'doEnter')
//   addPart (morph buttonsPane) (makeButton this 'Exit' 'doExit')
  addPart (morph buttonsPane) (makeButton this 'Step' 'doStep')
  addPart (morph buttonsPane) (makeButton this 'Resume' 'doGo')

  lbox = (listBox (array) nil (action 'selectCall' this) clr)
  setFont lbox 'Arial' fontSize
  callsFrame = (scrollFrame lbox clr)
  addPart morph (morph callsFrame)

  codePane = (newScriptEditor 10 10)
  codeFrame = (scrollFrame codePane (gray 220))
  addPart morph (morph codeFrame)

  fileAndLineFrame = (makeDBTextBox this clr)
  setEditRule fileAndLineFrame 'static'
  addPart morph (morph fileAndLineFrame)

  lbox = (listBox (array) nil (action 'selectVar' this) clr (action 'inspectVar' this))
  setFont lbox 'Arial' fontSize
  varsFrame = (scrollFrame lbox clr)
  addPart morph (morph varsFrame)

  valueFrame = (scrollFrame (makeDBTextBox this) clr)
  addPart morph (morph valueFrame)

  setMinExtent morph (scale * 400) (scale * 300)
  setExtent morph (scale * 450) (scale * 500)
  setPosition morph 5 (scale * 25)
  if (notNil (global 'page')) {
	setXCenter morph (hCenter (bounds (morph (global 'page'))))
  }
}

// button actions

method doEnter Debugger { stepTask this }
method doExit Debugger { stepTask this (findMP this true) }
method doStep Debugger {
  if (shiftKeyDown (keyboard (global 'page'))) {
	stepTask this // enter
  } else {
	stepTask this (findMP this false)
  }
}

method doGo Debugger {
  page = (handler (root morph))
  destroy morph
  setField debugeeTask 'waitReason' nil
  setField debugeeTask 'taskToResume' nil
  addTask (getField page 'taskMaster') debugeeTask
}

method stepTask Debugger targetMP {
  timer = (newTimer)
  setField debugeeTask 'errorReason' nil
  resumeDebuggee this true
  if (notNil targetMP) {
	while ((getField debugeeTask 'mp') > targetMP) {
      resumeDebuggee this true
	  if ((msecs timer) > 2000) {
		updateStack this
		setText reasonText 'Step timed out. Looping?'
		return
	  }
    }
  }
  updateStack this
  updateSelectedVar this
}

method updateSelectedVar Debugger {
  varList = (contents varsFrame)
  selectedVar = (selection varList)
  if (and (notNil selectedVar) (contains (collection varList) selectedVar)) {
	select varList selectedVar
  } else {
	select varList nil
  }
}

method findMP Debugger forExit {
  frames = (frameList this)
  if (isEmpty frames) { return nil }
  callIndex = (selectionIndex (contents callsFrame))
  if (isNil callIndex) { callIndex = (count frames) }
  if forExit {
    if (callIndex <= 1) { return nil }
    callIndex += -1
  }
  return (at frames callIndex)
}

method updateStack Debugger {
  updateReason this
  calls = (list)
  frames = (frameList this)
  if ((count frames) > 100) {
	print 'Large stack; showing only the first 100 frames'
	frames = (copyFromTo frames 1 100)
  }
  b = nil
  if (notNil debugeeTask) { b = (getField debugeeTask 'currentBlock') }
  if (isNil b) {
    add calls 'Debuggee is done.'
  } (isEmpty frames) {
    add calls 'No calls on stack'
  } else {
    for i (count frames) {
      add calls (callString this (at frames i) false)
    }
  }
  callsList = (contents callsFrame)
  setCollection callsList calls
  if (not (isEmpty calls)) {
	select callsList (last calls)
  }
}

method updateReason Debugger {
  reason = (errorReason debugeeTask)
  stack = (stack debugeeTask)
  fp = (getField debugeeTask 'fp')
  sp = (getField debugeeTask 'sp')
  if (isNil reason) {
  	setText reasonText ''
  	return
  } ('Halted' == reason) {
	cmd = (getField debugeeTask 'currentBlock')
	if ('error' == (primName cmd)) { reason = 'Error' }
	if (sp > fp) {
	  reasonStrings = (list (join reason ':'))
	  for i (range (getField debugeeTask 'fp') ((getField debugeeTask 'sp') - 1)) {
		add reasonStrings (carefulPrint this (at stack i))
	  }
	  reason = (joinStrings reasonStrings ' ')
	}
  } (beginsWith reason 'Undefined function: ') {
	reason = (join (substring reason 21) ' is not defined')
	if (sp > fp) {
	  firstArg = (at stack fp)
	  reason = (join reason ' for ' firstArg)
	}
  } else {
	reason = (join 'Primitive failed: ' reason)
  }
  setText reasonText (join reason (newline) '(To ignore, just close this window by clicking on the "X".)')
}

method selectCall Debugger ignored {
  showCallIndex this (selectionIndex (contents callsFrame))
}

method showCallIndex Debugger callIndex {
  setCollection (contents varsFrame) (array)
//  select (contents varsFrame) nil
  setText (contents valueFrame) ''
  setText fileAndLineFrame ''

  scriptsPane = (morph (contents codeFrame))
  removeAllParts scriptsPane

  vars = (dictionary)
  allVarNames = (list)

  frames = (frameList this)
  if (isEmpty frames) { return }
  mp = (at frames callIndex)

  stack = (stack debugeeTask)
  func = (at stack (mp + 1))
  showCode this func callIndex
  argNames = (argNames func)
  localNames = (localNames func)

  fp = (at stack (mp - 1))
  rcvr = (at stack fp)
  argCount = (((mp - fp) - 1) - (count localNames))
  for i argCount {
	if (i <= (count argNames)) {
	  varName = (at argNames i)
    } else {
	  varName = (join 'arg' i)
    }
    varIndex = ((fp + i) - 1)
    atPut vars varName varIndex
    add allVarNames varName
  }
  for i (count localNames) {
	varName = (at localNames i)
	varIndex = ((mp - i) - 1)
	atPut vars varName varIndex
	add allVarNames varName
  }
  allVarNames = (sorted allVarNames)
  if (contains allVarNames 'this') {
	remove allVarNames 'this'
	addFirst allVarNames 'this'
  }
  setCodeContext (contents valueFrame) rcvr
  setCollection (contents varsFrame) allVarNames
  updateSelectedVar this
}

method showCode Debugger func callIndex {
  scriptsPane = (morph (contents codeFrame))
  removeAllParts scriptsPane
  scrollToX codeFrame 0
  scrollToY codeFrame 0

  originalCmds = (copy (cmdList func))
  blockList = (toBlock (cmdList func))
  if (== 'hat' (type blockList)) {
    hat = blockList
  } else {
    hat = (block 'hat' (color 140 0 140) 'define' (blockPrototypeForFunction func))
    setNext hat blockList
  }
  bnds = (bounds scriptsPane)
  setPosition (morph hat) ((left bnds) + 20) ((top bnds) + 20)
  addPart scriptsPane (morph hat)

  updateSliders codeFrame

  // highlight
  currentBlock = (getCurrentBlock this callIndex)
  for m (allMorphs (morph blockList)) {
    if (isClass (handler m) 'Block') {
      if (currentBlock === (expression (handler m))) {
        setField (handler m) 'color' (color 230 230 0)
        redraw (handler m)
        for each (parts m) {
          if (isClass (handler each) 'CommandSlot') {
            setField (handler each) 'color' (color 230 230 0)
            redraw (handler each)
          }
        }
      }
    }
  }

  // update file and line number
  s = 'NO BLOCK'
  if (notNil currentBlock) {
    s = (filePart (fileName currentBlock))
	if (isNil s) { s = '<prompt>' }
	if (endsWith s '.gp') { s = (substring s 1 ((count s) - 3)) }
    s = (join s ':' (lineno currentBlock))
  }
  setText fileAndLineFrame s
}

method getCurrentBlock Debugger callIndex {
  stack = (stack debugeeTask)
  sp = (getField debugeeTask 'sp')
  frames = (frameList this)
  if (callIndex >= (count frames)) {
	b = (getField debugeeTask 'currentBlock')
	if (and (isNil b) (sp > 2)) {
	  b = (at stack (sp - 2))
	  if (not (isAnyClass b 'Command' 'Reporter')) {
		b = (getField debugeeTask 'nextBlock')
	  }
	}
  } else {
    callerMP = (at frames (callIndex + 1))
    b = (at stack (callerMP + 3))
  }
  return b
}

method selectVar Debugger varName {
  stack = (stack debugeeTask)
  varValue = (at stack (at vars varName))
  setText (contents valueFrame) (toString varValue)
}

method inspectVar Debugger varName {
  stack = (stack debugeeTask)
  varValue = (at stack (at vars varName))
  ins = (inspectorOn varValue)
  page = (handler (root morph))
  setPosition (morph ins) (x (hand page)) (y (hand page))
  addPart (morph page) (morph ins)
}

method makeButton Debugger label selector {
  scale = (global 'scale')
  w = (scale * 65)
  h = (scale * 23)
  nbm = (buttonBody this label w h false)
  hbm = (buttonBody this label w h true)
  b = (new 'Trigger' nil (action selector this) nbm hbm hbm)
  setData b label
  setMorph b (newMorph b)
  setCostume (morph b) nbm
  setGrabRule (morph b) 'ignore'
  return (morph b)
}

method buttonBody Debugger label w h highlight {
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
  fillRoundedRect (newShapeMaker bm) (rect 0 0 (width bm) (height bm)) radius fillColor border borderColor borderColor
  labelBM = (stringImage label 'Arial Bold' (scale * 14) textColor)
  x = ((w - (width labelBM)) / 2)
  y = ((h - (height labelBM)) / 2)
  drawBitmap bm labelBM x y
  return bm
}

method makeDBTextBox Debugger clr {
  textBox = (newText)
  setFont textBox nil ((global 'scale') * 15)
  setBorders textBox 5 5 true
  setEditRule textBox 'code'
  setGrabRule (morph textBox) 'ignore'
  if (notNil clr) { setColor textBox nil nil clr }
  return textBox
}

method redraw Debugger {
  fixLayout window
  redraw window
  fixLayout this
  fixButtonLayout this
}

method fixLayout Debugger {
  packer = (newPanePacker (clientArea window))
  packPanesH packer reasonPane '100%'
  packPanesH packer callsFrame 220 buttonsPane '100%'
  packPanesH packer callsFrame 220 codeFrame '100%'
  packPanesH packer fileAndLineFrame 220 valueFrame '100%'
  packPanesH packer varsFrame 220
  packPanesV packer reasonPane 40 callsFrame '100%' fileAndLineFrame 24 varsFrame 105
  packPanesV packer reasonPane 40 buttonsPane 37 codeFrame '100%' valueFrame 105
  finishPacking packer
  scale = (global 'scale')
  bnds = (bounds (morph window))
  setPosition (morph reasonText) ((left bnds) + (10 * scale)) ((top bnds) + (25 * scale))
}

method fixButtonLayout Debugger {
  buttons = (parts (morph buttonsPane))

  r = (bounds (morph buttonsPane))
  extraW = (width r)
  for b buttons { extraW += (- (width b)) }
  interButtonSpace = (max 5 (extraW / ((count buttons) + 1)))

  x = (+ (left r) interButtonSpace 1)
  y = ((top r) + ((global 'scale') * 7))
  for b buttons {
    setPosition b x y
	x += ((width b) + interButtonSpace)
  }
}

// code edit propagation

method step Debugger {
  // If the users has edited the current script, notify the ProjectEditor, if any.

  if (notNil originalCmds) {
	scriptsPane = (morph (contents codeFrame))
	hat = nil
	for m (parts scriptsPane) {
	  h = (handler m)
	  if (and (isClass h 'Block') ('hat' == (type h))) { hat = h }
	}
	if (and (notNil hat) (notNil (next hat))) {
	  body = (expression (next hat))
	  if (not (body == originalCmds)) {
		editor = (findProjectEditor)
		if (notNil editor) {
		  restoreScripts (scripter editor)
		}
		originalCmds = (copy body)
	  }
	}
  }
}
