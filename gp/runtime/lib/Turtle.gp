// Turtle.gp - Minimal turtle
// John Maloney, March 2014

defineClass Turtle morph x y direction penDown penSize penColor

to newTurtle {
  turtle = (initialize (new 'Turtle'))
  setField turtle 'morph' (newMorph turtle)
  setGrabRule (getField turtle 'morph') 'handle'
  redraw turtle
  return turtle
}

method initialize Turtle {
  x = 0
  y = 0
  direction = 0
  penDown = false
  penSize = 3
  penColor = (color)
  return this
}

method redraw Turtle {
  scale = (global 'scale')
  r = (scale * 15)
  bm = (newBitmap (2 * r) (2 * r))
  shapeMaker = (newShapeMaker bm)
  drawCircle shapeMaker r r (r - 5) (color 0 0 250)
  pen = (pen shapeMaker)
  beginPath pen r r
  setHeading pen direction
  forward pen r
  stroke pen (color 255 0 0) (2 * scale)
  setCostume morph bm
}

method grab Turtle aBlock {
  h = (hand (handler (root morph)))
  setCenter (morph aBlock) (x h) (y h)
  grab h aBlock
}

method justDropped Turtle {
  x = (left morph)
  y = (top morph)
}

// context menu

method rightClicked Turtle aHand {
  popUpAtHand (turtleMenu this) (page aHand)
  return true
}

method turtleMenu Turtle {
  menu = (menu 'Turtle' this)
  addBlock this (toBlock (newCommand 'forward' this 50)) menu
  addBlock this (toBlock (newCommand 'turn' this 15)) menu
  addBlock this (toBlock (newReporter 'direction' this)) menu
  addBlock this (toBlock (newCommand 'clear' this)) menu
  addBlock this (toBlock (newCommand 'penDown' this)) menu
  addBlock this (toBlock (newCommand 'penUp' this)) menu
  addBlock this (toBlock (newCommand 'setPenSize' this 5)) menu
  addBlock this (toBlock (newCommand 'setPenColor' this (color 0 0 200))) menu
  addBlock this (toBlock (newCommand 'repeat' 10 nil)) menu
  addBlock this (toBlock (newCommand 'animate' nil)) menu
  return menu
}

method addBlock Turtle aBlock menu {
  addItem menu (fullCostume (morph aBlock)) (action 'grab' this aBlock)
}

// block ops

method forward Turtle n {
  oldX = x
  oldY = y
  x += (n * (cos direction))
  y += (n * (sin direction))
  setPosition morph x y
  if penDown { drawTrail this oldX oldY }
}

method turn Turtle degrees {
  direction = ((direction + degrees) % 360)
  redraw this
}

method direction Turtle {return direction}
method clear Turtle {penClear morph}
method penDown Turtle {penDown = true}
method penUp Turtle {penDown = false}
method setPenSize Turtle n {penSize = (max n 1)}
method setPenColor Turtle c {penColor = c}

method drawTrail Turtle startX startY {
  if (or (not penDown) (isNil (owner morph))) {return}
  r = ((width morph) / 2)
  startPos = (penPosition (owner morph) startX startY)
  endPos = (penPosition (owner morph) (left morph) (top morph))
  pen = (newVectorPen (requirePenTrails (owner morph)))
  beginPath pen ((first startPos) + r) ((last startPos) + r)
  lineTo pen ((first endPos) + r) ((last endPos) + r)
  stroke pen penColor penSize 1 1
  changed (owner morph)
}
