// CachedTexture
// Browser only!
// Cached texture (i.e. canvas) for fast drawing when a morph is carried by the hand.
//
// John Maloney, June 2021

defineClass CachedTexture morph shadowOffset cachedTexture

to newCachedTexture aHandler {
	return (initialize (new 'CachedTexture') aHandler)
}

method initialize CachedTexture aHandler {
	aMorph = (morph aHandler)
	if (isClass (handler aMorph) 'Block') { fixLayout (handler aMorph) }

	// draw aMorph on the texture
	fb = (expandBy (fullBounds aMorph) 3) // expand so the shadow does not leave a trail in Chrome
	cachedTexture = (newTexture (width fb) (height fb) (gray 0 0))
	ctx = (newGraphicContextOn cachedTexture)
	setOffset ctx (0 - (left fb)) (0 - (top fb))
	fullDrawOn aMorph ctx

	shadowOffset = (7 * (global 'scale'))
	morph = (newMorph this)
	setExtent morph ((width fb) + shadowOffset) ((height fb) + shadowOffset)
	setPosition morph (left fb) (top fb)
	return this
}

method drawOn CachedTexture ctx {
	// always draw with shadow
	shadowColor = (gray 0 60)
	shadowBlur = (1 * (global 'scale'))
	browserSetShadow shadowColor shadowOffset shadowBlur

	drawTexture ctx cachedTexture (left morph) (top morph)
	browserClearShadow
}
