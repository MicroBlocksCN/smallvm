// Displays selectable icons for all instances of a given user-defined class.

defineClass SpriteList morph targetClass selection alignment onSelect lastInstances

method targetClass SpriteList {return targetClass}
method selection SpriteList {return selection}

method initialize SpriteList selectionAction {
  if (isNil selectionAction) {selectionAction = 'showInScripter'}
  onSelect = selectionAction
  morph = (newMorph this)
  setTransparentTouch morph true
  alignment = (newAlignment 'multi-line' (2 * (global 'scale')) 'bounds')
  setMorph alignment morph
  setFPS morph 2
  return this
}

method clear SpriteList {
  targetClass = nil
  selection = nil
  lastInstances = (array)
  removeAllParts morph
}

method setClass SpriteList aClass anInstance {
  targetClass = aClass
  if (notNil anInstance) {selection = anInstance}
  updateContents this (collectInstances this)
}

method step SpriteList {
  newInstances = (collectInstances this)
  if (lastInstances == newInstances) { return }
  lastInstances = newInstances
  updateContents this newInstances
}

method updateContents SpriteList newInstances {
  if (isNil targetClass) {
	removeAllParts morph
	return
  }
  if (not (contains (fieldNames targetClass) 'morph')) { // helper class
	removeAllParts morph
	return
  }

  // make a dictionary mapping instances to their icons
  oldIcons = (dictionary)
  for p (parts morph) {
	icon = (handler p)
	atPut oldIcons (target icon) icon
  }

  // make a dictionary mapping instances to their icons
  removeAllParts morph
  for each newInstances {
	icon = (at oldIcons each)
	if (isNil icon) {
	  icon = (initialize (new 'SpriteIcon') each (action 'select' this each) (action 'isSelected' this each))
	  setGrabRule (morph icon) 'defer'
	}
	addPart morph (morph icon)
  }
  fixLayout this
  refreshAll this
}

method collectInstances SpriteList {
  if (isNil targetClass) { return (array) }
  editor = (ownerThatIsA morph 'ProjectEditor')
  if (notNil editor) { stage = (stage (handler editor)) }
  if (isNil stage) { return (array) }
  result = (list)
  if (isUserDefined targetClass) {
	if (contains (fieldNames targetClass) 'morph') {
	  for m (allMorphs (morph stage) true) { // include hidden sprites
		if (isClass (handler m) targetClass) { add result (handler m) }
	  }
	  for m (allMorphs (morph (hand (global 'page')))) {
		if (isClass (handler m) targetClass) { add result (handler m) }
	  }
	} else {
	  result = (allInstances targetClass)
	}
  } else {
	result = (allInstances targetClass)
  }
  return result
}

method selectFirst SpriteList {
  if (isEmpty (parts morph)) {return nil}
  selection = (target (handler (first (parts morph))))
  refreshAll this
  return selection
}

method refreshAll SpriteList {
  // Update the highlight after the selection has changed.

  for each (parts morph) {refresh (handler each)}
}

method isSelected SpriteList anObject {return (anObject === selection)}

method select SpriteList anObject {
  selection = anObject
  refreshAll this
  call onSelect anObject
}

method redraw SpriteList {fixLayout this}
method fixLayout SpriteList {fixLayout alignment}

method adjustSizeToScrollFrame SpriteList aScrollFrame {
  adjustSizeToScrollFrame alignment aScrollFrame
}
