defineClass Gradient morph color steps stepSize

to newGradient aColor stepCount stepHeight {
	gradient = (initialize (new 'Gradient'))
	if (notNil aColor) { setField gradient 'color' aColor }
	if (notNil stepCount) { setField gradient 'steps' stepCount }
	setExtent (morph gradient) 200 (stepCount * (global 'scale'))
	redraw gradient
	return gradient
}

method initialize Gradient {
	morph = (newMorph)
	color = (color 0 0 0)
	steps = 10
	stepSize = 2
	redraw this
	return this
}

method morph Gradient { return morph }
method steps Gradient { return steps }
method stepSize Gradient { return stepSize }

method redraw Gradient {
	scale = (global 'scale')
	stripeColor = (copy color)
	w = (width morph)
	l = (left morph)
	t = (top morph)
	bm = (newBitmap (w * scale) (* steps scale stepSize))
	ctx = (newGraphicContextOn bm)
	for i steps {
		setAlpha stripeColor (floor ((255 / steps) * (i - 1)))
		fillRect ctx stripeColor 0 (* (i - 1) scale stepSize) w (scale * stepSize) 3
	}
	setCostume morph bm
}
