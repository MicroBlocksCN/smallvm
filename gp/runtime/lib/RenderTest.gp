defineClass RenderTest displayList canvasIDs

method displayList RenderTest { return displayList }

to newRenderTest {
  return (new 'RenderTest' (list))
}

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

method showTexture RenderTest aTexture x y {
if (not (isClass aTexture 'Texture')) { error 'not texture' }
  add displayList (array (toBitmap aTexture) x y true)
}

method createCanvasCache RenderTest n {
  if (isNil n) { n = 1 }
  canvasIDs = (list)
  repeat n {
	for entry displayList {
	  add canvasIDs (bitmap2canvas (first entry))
	}
  }
}

method countPixels RenderTest {
  count = 0
  for entry displayList {
	bm = (first entry)
	count += ((width bm) * (height bm))
  }
  return count
}

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

method timeCanvas RenderTest prim {
  count = 0
  t = (newTimer)
  while ((msecs t) < 1000) {
	for entry displayList {
	  bm = (first entry)
	  x = (at entry 2)
	  y = (at entry 3)
	  call prim bm x y
	}
	count += 1
  }
  msecs = (msecs t)
  print prim ((count * 1000) / msecs) 'fps;' count 'frames in' msecs 'msecs'
}

method timeCachedCanvas RenderTest {
  count = 0
  t = (newTimer)
  while ((msecs t) < 1000) {
	for i (count displayList) {
	  entry = (at displayList i)
	  id = (at canvasIDs i)
	  x = (at entry 2)
	  y = (at entry 3)
	  drawCanvas id x y
	}
	count += 1
  }
  msecs = (msecs t)
  print prim ((count * 1000) / msecs) 'fps;' count 'frames in' msecs 'msecs'
}

method benchmark RenderTest {
  t = (newTimer)
  capture this
  t0 = (msecSplit t)
  createCanvasCache this
  t1 = (msecSplit t)
  print 'capture' t0 'msecs createCanvasCache' t1 'msecs' (count canvasIDs) 'canvases'

  timeMorphic this
  timeDisplayList this
  timeCanvas this 'drawBitmapOnCanvasV1'
//  timeCanvas this 'drawBitmapOnCanvasV2'
  timeCanvas this 'drawBitmapOnCanvasV3'
  timeCanvas this 'drawBitmapOnCanvasV4'
  timeCachedCanvas this
}
