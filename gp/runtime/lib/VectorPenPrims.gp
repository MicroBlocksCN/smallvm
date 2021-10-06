// VectorPenPrims.gp -- Wrapper for fast version of VectorPen implemented as primitives.

defineClass VectorPenPrims

to newVectorPenPrims { return (new 'VectorPenPrims') }

method x VectorPenPrims { return (pathX) }
method y VectorPenPrims { return (pathY) }
method setClipRect VectorPenPrims aRect { pathSetClipRect aRect }
method setHeading VectorPenPrims degrees { pathSetHeading degrees }
method setOffset VectorPenPrims x y { pathSetOffset x y }
method beginPath VectorPenPrims x y { pathBeginPath x y }
method beginPathFromCurrentPostion VectorPenPrims { pathBeginPathFromHere }
method lineTo VectorPenPrims x y { pathLineTo x y }

method goto VectorPenPrims x y {
  // For compatability with Pen
  pathLineTo x y
}

method forward VectorPenPrims dist curvature {
	if (isNil curvature) { curvature = 0 }
	pathForward dist curvature
}

method turn VectorPenPrims degrees radius {
	if (isNil radius) { radius = 0 }
	pathTurn degrees radius
}

method stroke VectorPenPrims borderColor borderWidth {
	if (isNil borderWidth) { borderWidth = 1 }
	pathStroke borderColor borderWidth
}

method fill VectorPenPrims fillColor {
	pathFill fillColor
}

method fillAndStroke VectorPenPrims fillColor borderColor borderWidth {
	if (isNil borderColor) { borderColor = (gray 0) }
	if (isNil borderWidth) { borderWidth = 1 }

	pathFillAndStroke fillColor borderColor borderWidth
}

// FakeVectorPen does nothing. It is used for performance testing.

defineClass FakeVectorPen

to newFakeVectorPen { return (new 'FakeVectorPen') }

method x FakeVectorPen { }
method y FakeVectorPen { }
method setClipRect FakeVectorPen aRect { }
method setHeading FakeVectorPen degrees { }
method setOffset FakeVectorPen x y { }
method beginPath FakeVectorPen x y { }
method beginPathFromCurrentPostion FakeVectorPen { }
method lineTo FakeVectorPen x y { }
method goto FakeVectorPen x y { }
method forward FakeVectorPen dist curvature { }
method turn FakeVectorPen degrees radius { }
method stroke FakeVectorPen borderColor borderWidth { }
method fill FakeVectorPen fillColor { }
method fillAndStroke FakeVectorPen fillColor borderColor borderWidth { }
