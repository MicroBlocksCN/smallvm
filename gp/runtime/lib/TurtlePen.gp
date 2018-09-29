// TurtlePen
// graphics primitives for Morphs

defineClass TurtlePen canvas pen color size xPos yPos heading isDown

to newTurtlePen aBitmap {
  return (new 'TurtlePen' aBitmap (newVectorPen aBitmap) (color) 1 0 0 0.0 false)
}
method alpha TurtlePen {return (alpha color)}
method setAlpha TurtlePen a {setAlpha color a}
method setColor TurtlePen aColor {color = aColor}
method color TurtlePen {return color}
method canvas TurtlePen {return canvas}

method setCanvas TurtlePen aBitmap {
  canvas = aBitmap
  setField pen 'bitmap' aBitmap
}

method setLineWidth TurtlePen aNumber {size = aNumber}

// turtle graphics

method isDown TurtlePen {return isDown}
method down TurtlePen {isDown = true}
method up TurtlePen {isDown = false}

method x TurtlePen {return xPos}
method y TurtlePen {return yPos}
method setX TurtlePen num {xPos = num}
method setY TurtlePen num {yPos = num}

method goto TurtlePen newX newY {
  drawLine this xPos yPos newX newY
  xPos = newX
  yPos = newY
}

method move TurtlePen n {
  newX = (xPos + (n * (cos heading)))
  newY = (yPos + (n * (sin heading)))
  goto this newX newY
}

method direction TurtlePen {return heading}
method setDirection TurtlePen num {heading = (num % 360)}
method turn TurtlePen degrees {setDirection this (heading + degrees)}

method turnTo TurtlePen x y {
  deltaX = ((toFloat x) - (toFloat xPos))
  deltaY = ((toFloat y) - (toFloat yPos))
  setDirection this (atan deltaY deltaX)
}

// shapes

method drawLine TurtlePen x0 y0 x1 y1 {
  beginPath pen x0 y0
  addSegment pen x0 y0 x1 y1
  stroke pen color size 0 1
}
