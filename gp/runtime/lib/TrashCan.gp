// delete morphs by dropping them in a morphic window
// undelete the last one

defineClass TrashCan morph window contents

method initialize TrashCan {
  scale = (global 'scale')
  window = (window 'Trash')
  morph = (morph window)
  setHandler morph this
  setMinExtent morph (scale * 100) (scale * 100)
  setExtent morph (scale * 100) (scale * 100)
}

method fixLayout TrashCan {fixLayout window}

method redraw TrashCan {
  redraw window
  fixLayout this
}

to openTrashCan page contents {
  tc = (new 'TrashCan')
  initialize tc contents
  setPosition (morph tc) (x (hand page)) (y (hand page))
  addPart page tc
}

// events

method wantsDropOf TrashCan aHandler {return true}

method justReceivedDrop TrashCan aHandler {
  emptyTrash this
  contents = aHandler
  hide (morph aHandler)
}

method rightClicked TrashCan aHand {
  popUpAtHand (contextMenu this) (page aHand)
  return true
}


// context menu

method contextMenu TrashCan {
  menu = (menu nil this)
  if (notNil contents) {
    addItem menu 'undelete last' 'undeleteLast'
    addItem menu 'empty trash' 'emptyTrash'
  } else {
    addItem menu '(trash is empty)' 'nop'
  }
  return menu
}

method emptyTrash TrashCan {
  if (notNil contents) {
    destroy (morph contents)
    contents = nil
  }
}

method undeleteLast TrashCan {
  if (notNil contents) {
    show (morph contents)
    grab (morph contents) (hand (global 'page'))
    contents = nil
  }
}
