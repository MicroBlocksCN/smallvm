// Used to compare morphic rendering to drawing a display list of bitmaps.

defineClass RenderTest displayList

method displayList RenderTest { return displayList }

to newRenderTest {
  return (new 'RenderTest' (list))
}

// Capture the pixels drawn by one frame of the morphic event loop

method capture RenderTest {
  // Build a display list for the current page.

  page = (global 'page')
  displayList = (list)
  draw (morph page) this
  draw (morph (hand page)) this
}

method drawBitmap RenderTest aBitmap x y {
  if (not (isClass aBitmap 'Bitmap')) { error 'not bitmap' }
  add displayList (array aBitmap x y false)
}

method fillRect RenderTest aColor x y w h {
  if (not (isClass aColor 'Color')) { error 'not color' }
  add displayList (array (newBitmap w h aColor) x y false)
}

method warpBitmap RenderTest aBitmap centerX centerY scaleX scaleY rotation {
  if (not (isClass aBitmap 'Bitmap')) { error 'not bitmap' }
  if (0 != rotation)  { error 'non-zero rotation' }
  dstW = (scaleX * (width aBitmap))
  dstH = (scaleY * (height aBitmap))
  scaledBM = (thumbnail aBitmap dstW dstH)
  add displayList (array scaledBM x y false)
}

method countPixels RenderTest {
  // Return the total number of pixels captured.

  count = 0
  for entry displayList {
	bm = (first entry)
	count += ((width bm) * (height bm))
  }
  return count
}

// Benchmarking

method timeDisplayList RenderTest {
  count = 0
  t = (newTimer)
  while ((msecs t) < 1000) {
	for entry displayList {
	  bm = (first entry)
	  x = (at entry 2)
	  y = (at entry 3)
	  drawBitmap nil bm x y
	}
	count += 1
  }
  msecs = (msecs t)
  print 'display list' ((count * 1000) / msecs) 'fps;' count 'frames in' msecs 'msecs'
}

method timeMorphic RenderTest {
  page = (global 'page')
  count = 0
  t = (newTimer)
  while ((msecs t) < 1000) {
	draw (morph page) nil
	draw (morph (hand page)) nil
	count += 1
  }
  msecs = (msecs t)
  print 'morphic' ((count * 1000) / msecs) 'fps;' count 'frames in' msecs 'msecs'
}

method benchmark RenderTest {
  capture this
  timeMorphic this
  timeDisplayList this
}
