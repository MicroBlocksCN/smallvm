// Prompter.gp - request text or yes/no input from the user

defineClass Prompter morph window textBox textFrame buttons slider answer isDone callback detailsText detailsFrame

method textBox Prompter {return textBox}
method answer Prompter {return answer}
method isDone Prompter {return isDone}

method initialize Prompter label default editRule anAction details {
  scale = (global 'scale')
  answer = ''
  isDone = false
  if (isNil label) {label = 'Prompter'}
  if (isNil default) {default = ''}
  if (isNil editRule) {editRule = 'line'}
  callback = anAction // optional

  window = (window label)
  clr = (clientColor window)
  border = (border window)
  morph = (morph window)
  setHandler morph this
  minW = (titleBarWidth window)
  fontName = 'Arial'
  fontSize = (14 * (global 'scale'))
  if ('Linux' == (platform)) { fontSize = (11 * (global 'scale')) }

  if (notNil details) {
	  detailsText = (newText details fontName fontSize)
	  setEditRule detailsText 'static'
	  setGrabRule (morph detailsText) 'ignore'
	  detailsFrame = (scrollFrame detailsText (transparent) true)
	  setExtent (morph detailsFrame) minW 0
	  wrapLinesToWidth detailsText (width (morph detailsFrame))
	  setExtent (morph detailsFrame) minW (height (morph detailsText))
	  addPart morph (morph detailsFrame)
	  minW = ((width (morph detailsFrame)) + (border * 8))
  }

  textBox = (newText default fontName fontSize)
  setBorders textBox border border true
  minW = (max minW ((width (morph textBox)) + (60 * scale)))
  setEditRule textBox editRule
  setGrabRule (morph textBox) 'ignore'
  textFrame = (scrollFrame textBox (gray 255) (== editRule 'line'))
  addPart morph (morph textFrame)

  createButtons this

  if (notNil details) {
	  minH = (+ (height buttons) (height (morph textFrame)) (height (morph detailsFrame)) (border * 4))
	  minH = (+ (scale * 100) (height (morph detailsFrame)) border)
  } else {
	  minW = (clamp minW (scale * 250) (scale * 400))
  	  minH = (scale * 100)
  }

  setExtent morph minW minH
  setMinExtent morph (width morph) (height morph)
}

method initializeForConfirm Prompter label question yesLabel noLabel anAction {
  answer = false
  isDone = false
  if (isNil label) {label = 'Confirm'}
  if (isNil question) {question = ''}
  if (isNil yesLabel) {yesLabel = 'Yes'}
  if (isNil noLabel) {noLabel = 'No'}
  callback = anAction // optional

  window = (window (localized label))
  hide (morph (getField window 'resizer'))
  border = (border window)
  morph = (morph window)
  setHandler morph this

  lbl = (getField window 'label')
  fontSize = (16 * (global 'scale'))
  if ('Linux' == (platform)) { fontSize = (13 * (global 'scale')) }
  textFrame = (newText (localized question) (fontName lbl) fontSize (gray 0) 'center')
  addPart morph (morph textFrame)
  createButtons this (localized yesLabel) (localized noLabel)

  textWidth = (width (morph textFrame))
  buttonWidth = (width buttons)
  labelWidth = (width (morph lbl))
  xBtnWidth = (width (morph (getField window 'closeBtn')))
  w = (max textWidth buttonWidth labelWidth)
  setExtent morph (+ w xBtnWidth (4 * border)) (+ (height (morph lbl)) (height (morph textFrame)) (height (bounds buttons)) (8 * border))
  setMinExtent morph (width morph) (height morph)
}

method initializeForInform Prompter label details okLabel {
  isDone = false

  if (isNil label) {label = 'Information'}
  if (isNil okLabel) {okLabel = 'OK'}

  scale = (global 'scale')
  window = (window (localized label))
  border = (border window)
  morph = (morph window)
  setHandler morph this
  minW = (max (titleBarWidth window) (380 * scale))
  lbl = (getField window 'label')
  fontName = 'Arial Bold'
  fontSize = (18 * (global 'scale'))
  if ('Linux' == (platform)) { fontSize = (15 * (global 'scale')) }

  if ((count (lines details)) == 1) { align = 'center' } else { align = 'left' }

  detailsText = (newText (localized details) fontName fontSize (gray 0) align)
  detailsFrame = (scrollFrame detailsText (transparent) true)
  setExtent (morph detailsFrame) minW 0
  wrapLinesToWidth detailsText (width (morph detailsFrame))
  setExtent (morph detailsFrame) minW (height (morph detailsText))
  addPart morph (morph detailsFrame)
  minW = ((width (morph detailsFrame)) + (border * 10))

  createButtons this (localized okLabel) nil true // single button
  minH = (+ (height (morph lbl)) (height (morph detailsFrame)) (height (bounds buttons)) (4 * border))
  setExtent morph minW minH
  setMinExtent morph (width morph) (height morph)
}

to promptForNumber title anAction minValue maxValue currentValue {
  page = (global 'page')
  p = (new 'Prompter')
  initializeForSlider p title anAction minValue maxValue currentValue
  setCenter (morph p) (x (hand page)) (y (hand page))
  keepWithin (morph p) (insetBy (bounds (morph page)) 50)
  addPart (morph page) (morph p)
  if (isNil anAction) {
    setField (hand page) 'lastTouchTime' nil
    while (not (isDone p)) { doOneCycle page }
    destroy (morph p)
    return (answer p)
  }
}

method initializeForSlider Prompter title anAction minValue maxValue currentValue {
  if (isNil title) {title = 'Number?'}
  if (isNil minValue) { minValue = 0 }
  if (isNil maxValue) { maxValue = 100 }
  if (isNil currentValue) { currentValue = 50 }

  answer = currentValue
  isDone = false
  callback = anAction // optional

  window = (window title)
  hide (morph (getField window 'resizer'))
  border = (border window)
  morph = (morph window)
  setHandler morph this

  scale = (global 'scale')
  slider = (slider 'horizontal' (150 * scale) callback (10 * scale) minValue maxValue currentValue)
  setPosition (morph slider) (20 * scale) (35 * scale)
  addPart morph (morph slider)
  createButtons this 'OK' 'Cancel'

  w = ((width (morph slider)) + (20 * scale))
  setExtent morph (+ w (4 * border)) (+ (height (morph slider)) (height (bounds buttons)) (60 * scale))
  setMinExtent morph (width morph) (height morph)
}

method createButtons Prompter okLabel cancelLabel singleButton {
  scale = (global 'scale')
  if (isNil singleButton) { singleButton = false }
  if (isNil okLabel) {okLabel = 'OK'}

  buttons = (newMorph)
  okButton = (pushButton okLabel (action 'accept' this) nil (26 * scale) true) // default
  addPart buttons (morph okButton)

  if (not singleButton) {
	  if (isNil cancelLabel) {cancelLabel = 'Cancel'}
	  cancelButton = (pushButton cancelLabel (action 'cancel' this) nil (26 * scale))
	  addPart buttons (morph cancelButton)
	  setPosition (morph cancelButton) (+ (right (morph okButton)) (border window)) (top (morph okButton))
  }

  setBounds buttons (fullBounds buttons)
  addPart morph buttons
}

method redraw Prompter {
  redraw window
  drawInside this
  fixLayout this
}

method drawInside Prompter {
  scale = (global 'scale')
  cornerRadius = (4 * scale)
  fillColor = (microBlocksColor 'blueGray' 50)
  inset = (5 * scale)
  topInset = (24 * scale)
  w = ((width morph) - (2 * inset))
  h = ((height morph) - (topInset + inset))
  pen = (newVectorPen (costumeData morph) morph)
  fillRoundedRect pen (rect inset topInset w h) cornerRadius fillColor
}

method fixLayout Prompter {
  fixLayout window
  clientArea = (clientArea window)
  border = (border window)
  buttonHeight = (height (bounds buttons))
  hPadding = (3 * border)

  setXCenter buttons (hCenter clientArea)
  setBottom buttons ((bottom clientArea) - border)

  if (notNil detailsFrame) {
  	setLeft (morph detailsFrame) ((left clientArea) + hPadding)
	setTop (morph detailsFrame) ((top clientArea) + (2 * border))
	detailsHeight = (((height clientArea) - (height buttons)) - (5 * border))
	if (notNil textBox) {
		detailsHeight = ((detailsHeight - ((height (morph textBox)))) - border)
	}
	if ((alignment detailsText) == 'center') {
		setExtent (morph detailsFrame) (width (extent detailsText))
		setCenter (morph detailsFrame) (hCenter clientArea) ((vCenter clientArea) - border)
	} else {
		setExtent (morph detailsFrame) ((width clientArea) - (2 * hPadding)) detailsHeight
		wrapLinesToWidth detailsText (width (morph detailsFrame))
	}
  }

  if (notNil textFrame) {
	if (notNil slider) {
		setXCenter (morph slider) (hCenter clientArea)
	} (isNil textBox) { // confirmation dialog
		setBottom (morph textFrame) ((top buttons) - (2 * border))
		setXCenter (morph textFrame) (hCenter clientArea)
	} else { // prompter dialog
		if (notNil detailsText) {
		  textHeight = (height (extent textBox))
		  vPadding = (border * 2)
		} (== 'editable' (editRule textBox)) {
		  textHeight = ((height clientArea) - (+ buttonHeight (border * 2)))
		  vPadding = border
		} (== 'line' (editRule textBox)) {
		  textHeight = (height (extent textBox))
		  vPadding = (((height clientArea) - (+ textHeight buttonHeight border)) / 2)
		}
		setLeft (morph textFrame) ((left clientArea) + hPadding)
		setBottom (morph textFrame) ((top buttons) - vPadding)
		setExtent (morph textFrame) ((width clientArea) - (2 * hPadding)) textHeight
	}
  }
}

method accept Prompter {
  if (notNil slider) {
    answer = (value slider)
  } (isNil textBox) { // confirmation dialog
    answer = true
  } else {
    stopEditing textBox
    answer = (text textBox)
  }
  destroy morph
  if (notNil callback) {
    call callback answer
  }
}

method cancel Prompter {
  if (notNil textBox) {stopEditing textBox}
  if (and (notNil slider) (notNil callback) (notNil answer)) {
    call callback answer // restore the original value
  }
  destroy morph
}

method destroyedMorph Prompter {isDone = true}
method accepted Prompter {accept this}
method cancelled Prompter {cancel this}
