// ImageBox - Simple bitmap display morph.

defineClass ImageBox morph

method bitmap ImageBox { return (costumeData morph) }
method setBitmap ImageBox newBitmap { setCostume morph newBitmap }

to newImageBox optionalBitmap {
	return (initialize (new 'ImageBox') optionalBitmap)
}

method initialize ImageBox optionalBitmap {
	morph = (newMorph this)
	//  setHandler morph this // xxx needed?
	if (isNil optionalBitmap) {
		optionalBitmap = (newBitmap 24 24 (gray 100))
	}
	setBitmap this optionalBitmap
	return this
}
