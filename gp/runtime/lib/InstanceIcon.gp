// InstanceIcon.gp - reprepesents a non-morphic object instance in the instances pane

defineClass InstanceIcon morph target toggle thumb

method target InstanceIcon { return target }

method initialize InstanceIcon aHandler onSelect query {
  if (isNil onSelect) {onSelect = 'nop'}
  if (isNil query) {query = (function {return false})}
  target = aHandler
  scale = (global 'scale')
  toggle = (createToggle this onSelect query)
  morph = (morph toggle)
  setHandler morph this
  addPart morph (morph (thumbnailFor aHandler))
  fixLayout this
  return this
}

method createToggle InstanceIcon onSelect query {
  scale = (global 'scale')
  clr = (gray 200)
  size = (scale * 46)
  corner = (scale * 3)
  border = scale
  fbm = (buttonBitmap nil (color 0 0 0 0) size size false corner border false true)
  pbm = (buttonBitmap nil clr size size false corner border false false)
  tbm = (buttonBitmap nil clr size size false corner border true false)
  trigger = (new 'Trigger' nil onSelect fbm tbm pbm)
  m = (newMorph)
  setMorph trigger m
  setWidth (bounds m) size
  setHeight (bounds m) size
  tg = (new 'Toggle' m trigger query 'handEnter')
  setHandler m tg
  refresh tg
  return tg
}

method fixLayout InstanceIcon {
  setCenter (first (parts morph)) (hCenter (bounds morph)) (vCenter (bounds morph))
}

method handDownOn InstanceIcon aHand {return (handDownOn toggle aHand)}
method handEnter InstanceIcon aHand {handEnter toggle aHand}
method handLeave InstanceIcon aHand {handLeave toggle aHand}
method clicked InstanceIcon {return (clicked toggle)}
method doubleClicked InstanceIcon {return (doubleClicked toggle)}
method setHint InstanceIcon aStringOrNil {setHint toggle aStringOrNil}
method rightClicked InstanceIcon {return (rightClicked toggle)}
method refresh InstanceIcon {refresh toggle}
