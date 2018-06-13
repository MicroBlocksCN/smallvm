// DropRecord - restores a script / block to how it was
// before a particular block was dropped on it

defineClass DropRecord block target next input

method restore DropRecord aScriptEditor {
  // "undrop"
  if (not (isRestorable this)) {return}
  if ('reporter' == (type block)) {
    if (notNil target) {
      replaceInput target block input
      fixBlockColor target
    }
  } else { // command or hat
    if (isClass target 'Array') { // top of command block
      addPart (morph aScriptEditor) (morph (first target))
    } (isClass target 'CommandSlot') {
      setNested target next
    } (notNil target) { // bottom of command or hat block
      setNext target next
    }
  }
  if (notNil next) {fixBlockColor next}
  fixBlockColor block
  grab aScriptEditor block
}

method isRestorable DropRecord {
  return (and
    (notNil block)
    (or
      (notNil (costume (morph block)))
      (notNil (costumeData (morph block)))
    )
  )
}