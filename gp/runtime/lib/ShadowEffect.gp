// ShadowEffect
// Browser only! Uses DOM Canvas "shadow" effects to draw a dropshadow or highlight around
// a stack of blocks.
//
// John Maloney, May 2021

defineClass ShadowEffect morph targetBlock color offset blur

to newShadowEffect aBlock effectType {
	return (initialize (new 'ShadowEffect') aBlock effectType)
}

method initialize ShadowEffect aBlock effectType {
	morph = (newMorph this)
	acceptEvents morph false
	targetBlock = aBlock
	scale = (global 'scale')
	if ('highlight' == effectType) {
		color = (colorHSV 120 1.0 0.6)
		offset = 0
		blur = (20 * scale)
	} else {
		color = (gray 0 60)
		offset = (7 * scale)
		blur = (1 * scale)
	}
	r = (expandBy (fullBounds (morph targetBlock)) (20 * scale))
	r = (translatedBy r offset)
	setExtent morph (width r) (height r)
	setPosition morph (left r) (top r)
	return this
}

method drawOn ShadowEffect ctx {
	if ('Browser' != (platform)) { return }
	if (notNil (getField ctx 'surface')) { return } // don't draw shadow on surface; very slow!

	blockBodies = (list)
	for m (allMorphs (morph targetBlock)) {
		if (isClass (handler m) 'Block') {
			addFirst blockBodies (handler m)
		}
	}
	browserSetShadow color offset blur
	for b blockBodies { drawOn b ctx }
	browserClearShadow
}
