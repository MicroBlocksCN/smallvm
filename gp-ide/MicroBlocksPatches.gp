// MicroBlocksPatches.gp - This file patches/replaces methods in GP's normal class library
// with versions that support MicroBlocks (possibly making them no longer work correctly in
// the normal GP IDE.
//
// This file must be processed *after* the normal GP library has been read with a command like:
//
//	./gp runtime/lib/* microBlocks/GP-IDE/* -
//
// John Maloney, January, 2018

method clicked Block hand {
  runtime = (smallRuntime)
  topBlock = (topBlock this)
  if (isRunning runtime topBlock) {
	stopRunningChunk runtime (chunkIdFor runtime topBlock)
  } else {
	evalOnArduino runtime topBlock
  }
}

method contextMenu Block {
  if (isPrototype this) {return nil}
  menu = (menu nil this)
// MicroBlocks menu additions:
addItem menu 'show instructions' (action 'showInstructions' (smallRuntime) this)
addItem menu 'show compiled bytes' (action 'evalOnArduino' (smallRuntime) this true)
addLine menu

  isInPalette = ('template' == (grabRule morph))
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

  if (not isInPalette) {
    addLine menu
    addItem menu 'delete' 'delete'
  }
  return menu
}
