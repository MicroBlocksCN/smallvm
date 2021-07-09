// a self-updating thumbnail of a morphic handler

defineClass SpriteThumbnail morph target lastTargetCostume

to thumbnailFor aHandler {
  if (isClass aHandler 'Morph') {aHandler = (handler aHandler)}
  return (initialize (new 'SpriteThumbnail') aHandler)
}

method initialize SpriteThumbnail aHandler {
  target = aHandler
  morph = (newMorph this)
  setTransparentTouch morph true
  setWidth (bounds morph) (40 * (global 'scale'))
  setHeight (bounds morph) (40 * (global 'scale'))
  setFPS morph 5
  step this
  return this
}

method step SpriteThumbnail {
  // This is a placeholder during the Morphic rewrite. It responds to costume
  // switches but not to rotation or costume modifications. It will get replaced
  // by a drawOn method and possibly invalidated by the "change" mechanism.

  if (isNil target) { return }
  targetM = (morph target)
  if (lastTargetCostume === (costumeData targetM)) { return }

  side = (min (width morph) (height morph))
  setCostume morph (thumbnail (costumeData targetM) side side)
  lastTargetCostume = (costumeData targetM)
}

method rightClicked SpriteThumbnail {
  popUpAtHand (contextMenu this) (global 'page')
  return true
}

method contextMenu SpriteThumbnail {
  menu = (menu nil this)
  targetM = (morph target)
  addItem menu 'show' 'showTarget' 'unhide and/or move instance onstage'
  addItem menu 'come to front' (action 'comeToFront' (morph target)) 'show this object on top of its siblings'
  addLine menu
  addItem menu 'delete' (action 'destroy' (morph target) false)
  addLine menu
  addItem menu 'scale...' (action 'scalingHandle' target) 'scale this object'
  addItem menu 'rotate...' (action 'rotationHandle' target) 'rotate this object'
  addItem menu 'rotation point...' (action 'pinHandle' target) 'edit the point about which this object rotates'
  if (or ((pinX targetM) != 0) ((pinY targetM) != 0)) {
    addItem menu 'set rotation point to center...' (action 'setPin' targetM 0 0) 'make this object''s rotation point be its center'
  }
  if (rotateWithOwner targetM) {
	addItem menu 'rotate independently' (action 'toggleRotationStyle' targetM) 'keep current orientation instead of rotating with the owner'
  } else {
	addItem menu 'rotate with owner' (action 'toggleRotationStyle' targetM) 'rotate with owner, as if rigidly attached to it'
  }
  addLine menu
  if ((count (parts targetM)) > 0) {
	addLine menu
    addItem menu 'detach all parts (ungroup)' (action 'detachAll' targetM) 'detach all my parts'
  }
  if ('draggableParts' == (grabRule targetM)) {
	addItem menu 'do not allow parts to be dragged in and out' (action 'toggleDraggableParts' targetM)
  } else {
	addItem menu 'allow parts to be dragged in and out' (action 'toggleDraggableParts' targetM)
  }
  return menu
}

method showTarget SpriteThumbnail {
  container = (ownerThatIsA (morph target) 'Stage')
  if (isNil container) {container = (morph (global 'page'))}
  m = (morph target)
  keepWithin m (bounds container)
  setAlpha m 255
  show m
}

// drag/drop

method wantsDropOf SpriteThumbnail aHandler {
  if (aHandler == target) { return false } // reject drop of my target
  oldOwner = (oldOwner (hand (global 'page')))
  return (isClass oldOwner 'Stage')
}

method justReceivedDrop SpriteThumbnail aHandler {
  h = (hand (global 'page'))
  returnGrabbedObjectToOldPosition h aHandler
  addPart (morph target) (morph aHandler)
  setGrabRule (morph aHandler) 'defer'
}
