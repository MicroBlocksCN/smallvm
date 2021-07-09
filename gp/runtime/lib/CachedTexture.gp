// CachedTexture
// Browser only!
// Cached texture (i.e. canvas) for fast drawing when a morph is carried by the hand.
//
// John Maloney, June 2021

defineClass CachedTexture morph cachedTexture

to newCachedTexture aHandler {
	return (initialize (new 'CachedTexture') aHandler)
}

method initialize CachedTexture aHandler {
	aMorph = (morph aHandler)
	if (isClass (handler aMorph) 'Block') { fixLayout (handler aMorph) }

	// draw aMorph on the texture
	fb = (fullBounds aMorph)
	cachedTexture = (newTexture (width fb) (height fb) (gray 0 0))
	ctx = (newGraphicContextOn cachedTexture)
	setOffset ctx (0 - (left fb)) (0 - (top fb))
	fullDrawOn aMorph ctx

	morph = (newMorph this)
	setExtent morph (width fb) (height fb)
	setPosition morph (left fb) (top fb)
	return this
}

method drawOn CachedTexture ctx {
	scale = (global 'scale')

	// always draw with shadow
	shadowColor = (gray 0 60)
	shadowOffset = (7 * scale)
	shadowBlur = (1 * scale)
	browserSetShadow shadowColor shadowOffset shadowBlur

	drawTexture ctx cachedTexture (left morph) (top morph)
	browserClearShadow
}
