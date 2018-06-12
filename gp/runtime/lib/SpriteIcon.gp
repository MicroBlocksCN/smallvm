// SpriteIcon - a library icon of a user-defined class

defineClass SpriteIcon morph target toggle thumb

method target SpriteIcon { return target }

method initialize SpriteIcon aHandler onSelect query {
  if (isNil onSelect) {onSelect = 'nop'}
  if (isNil query) {query = (function {return false})}
  target = aHandler
  scale = (global 'scale')
  toggle = (createToggle this onSelect query)
  morph = (morph toggle)
  setHandler morph this
  if (hasField target 'morph') {
	addPart morph (morph (thumbnailFor target))
  } else {
	box = (newBox nil (gray 200) 0 0 false false)
	w =  (40 * (global 'scale'))
	setExtent (morph box) w w
	addPart morph (morph box)
  }
  fixLayout this
  return this
}

method createToggle SpriteIcon onSelect query {
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

method fixLayout SpriteIcon {
  setCenter (first (parts morph)) (hCenter (bounds morph)) (vCenter (bounds morph))
}

method handDownOn SpriteIcon aHand {return (handDownOn toggle aHand)}
method handEnter SpriteIcon aHand {handEnter toggle aHand}
method handLeave SpriteIcon aHand {handLeave toggle aHand}
method clicked SpriteIcon {return (clicked toggle)}
method doubleClicked SpriteIcon {return (doubleClicked toggle)}
method setHint SpriteIcon aStringOrNil {setHint toggle aStringOrNil}
method rightClicked SpriteIcon {return (rightClicked toggle)}
method refresh SpriteIcon {refresh toggle}
