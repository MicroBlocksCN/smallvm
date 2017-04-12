// SmallVMBlockPatch.gp
// Patches Block context menu to add 'eval on Arduino' and 'compile'
// John Maloney, April 2017

// context menu

method contextMenu Block {
  if (isPrototype this) {return nil}
  menu = (menu nil this)
  isInPalette = ('template' == (grabRule morph))
// xxx
addItem menu 'eval on Arduino' 'evalOnArduino'
addItem menu 'compile' 'compile'
addLine menu

  addItem menu 'explore result' 'explore'
  if (canShowMonitor this) {
    addItem menu 'monitor' 'addMonitor'
  }
  addLine menu
  if (isVariadic this) {
    if (canExpand this) {addItem menu 'expand' 'expand'}
    if (canCollapse this) {addItem menu 'collapse' 'collapse'}
    addLine menu
  }
  if (and isInPalette (isRenamableVar this)) {
    addItem menu 'rename...' 'userRenameVariable'
    addLine menu
  }
  addItem menu 'duplicate' 'grabDuplicate' 'just this one block'
  if (and ('reporter' != type) (notNil (next this))) {
    addItem menu '...all' 'grabDuplicateAll' 'duplicate including all attached blocks'
  }
  addItem menu 'copy to clipboard' 'copyToClipboard'
  if (notNil (findDefinition this true)) {
    addItem menu 'show definition...' 'findDefinition'
  }
  if isInPalette {
	proj = (project (findProjectEditor))
	if (isUserDefinedBlock proj this) {
	  addLine menu
	  if (showingAnExtensionCategory proj this) {
		addItem menu 'remove from palette' (action 'removeFromCurrentCategory' proj this)
	  } else {
		addItem menu 'export to palette...' (action 'exportToExtensionCategory' proj this)
	  }
	}
  }
  if (devMode) {
    addLine menu
    addItem menu 'implementations...' 'browseImplementors'
    addItem menu 'text code...' 'editAsText'
  }

  if (not isInPalette) {
    addLine menu
    addItem menu 'delete' 'delete'
  }
  return menu
}

// xxx
method compile Block { compileSmallVM expression }
method evalOnArduino Block { evalOnArduino expression }

