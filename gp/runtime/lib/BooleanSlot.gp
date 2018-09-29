// editable bool slot for blocks

defineClass BooleanSlot morph toggle contents

to newBooleanSlot default {
  if (isNil default) {default = false}
  return (initialize (new 'BooleanSlot') default)
}

to booleanConstant b { return b }

method initialize BooleanSlot default {
  scale = (global 'scale')
  contents = default
  corner = 5
  toggle = (toggleButton (action 'switch' this) (action 'contents' this) (scale * 20) (scale * 13) (scale * corner) (max 1 (scale / 2)) false false)
  morph = (morph toggle)
  setHandler morph this
  return this
}

method setContents BooleanSlot bool {
  if (not (isClass bool 'Boolean')) {return}
  contents = bool
  refresh toggle
  raise morph 'inputChanged' this
}

method contents BooleanSlot {return contents}

method switch BooleanSlot {
  if (not (isClass contents 'Boolean')) { contents = false }
  setContents this (not contents)
}

// events

method handDownOn BooleanSlot aHand {return (handDownOn toggle aHand)}
method clicked BooleanSlot aHand {return (clicked toggle aHand)}

// keyboard accessibility hooks

method trigger BooleanSlot {
  clicked toggle
}

method setToFalse BooleanSlot {
  setContents this false
  refresh toggle
}
