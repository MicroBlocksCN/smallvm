// classes for viewing the contents of a Table

defineClass TableCell morph data isLabel isRowCount

method initialize TableCell cellData width height labelFlag rowCountFlag {
  if (isNil labelFlag) {labelFlag = false}
  if (isNil rowCountFlag) {rowCountFlag = false}
  morph = (newMorph this)
  data = cellData
  isLabel = labelFlag
  isRowCount = rowCountFlag
  setExtent morph width height
  return this
}

method setData TableCell cellData {
  data = cellData
  redrawData this
}

method redraw TableCell {
  bm = (newBitmap (width morph) (height morph))
  setCostume morph bm
  redrawData this
}

method redrawData TableCell {
  bm = (costumeData morph)
  txt = (toString data)

  if (isNil data) {return}
  if isLabel {
    fillPixelsRGBA (pixelData bm) 220 220 220 255
    if isRowCount {
      setFont 'Arial Italic' (* 10 (global 'scale'))
    } else {
      setFont 'Arial Bold' (* 12 (global 'scale'))
    }
  } else {
    fillPixelsRGBA (pixelData bm) 255 255 255 255
    setFont 'Arial' (* 12 (global 'scale'))
  }
  w = (stringWidth txt)
  h = (fontHeight)
  wd = ((width bm) - w)
  x = (max 0 (wd / 2))
  hd = ((height bm) - h)
  y = (max 0 (hd / 2))
  drawString bm txt nil (truncate x) (truncate y) // avoid creating a Color object
  // note: don't propagate the "changed" flag, let the tabe view handle this for all
}


method blankOut TableCell {
  fillPixelsRGBA (pixelData (costumeData morph)) 0 0 0 0
}

defineClass TableView morph data lastChangeCount startCol startRow cellWidth cellHeight padding cols rows rowLabelWidth

method initialize TableView aTable startC startR cellW cellH pad w h {
  if (isNil aTable) {aTable = (table)}
  if (isNil startC) {startC = 1}
  if (isNil startR) {startR = 1}
  if (isNil cellW) {cellW = (100 * (global 'scale'))}
  if (isNil cellH) {cellH = (20 * (global 'scale'))}
  if (isNil pad) {pad = (global 'scale')}
  if (isNil w) {w = (250 * (global 'scale'))}
  if (isNil h) {h = (150 * (global 'scale'))}
  data = aTable
  startCol = startC
  startRow = startR
  cellWidth = cellW
  cellHeight = cellH
  padding = pad
  rowLabelWidth = (rowLabelWidth this)
  morph = (newMorph this)
  setClipping morph true
  setExtent morph w h
  setFPS morph 5
  return this
}

method setData TableView aTable startC startR cellW cellH {
  if (isNil aTable) {aTable = data}
  if (isNil startC) {startC = startCol}
  if (isNil startR) {startR = startRow}
  if (isNil cellW) {cellW = cellWidth}
  if (isNil cellH) {cellH = cellHeight}
  data = aTable
  startCol = startC
  startRow = startR
  cellWidth = cellW
  cellHeight = cellH
  rowLabelWidth = (rowLabelWidth this)
  redraw this true
}

method rowLabelWidth TableView {
  pad = (10 * (global 'scale'))
  setFont 'Arial Bold' (* 12 (global 'scale'))
  return (+ pad (stringWidth (toString (rowCount data))))
}

method vSlider TableView {
  for each (parts morph) {
    hdl = (handler each)
    if (and (isClass hdl 'Slider') ('vertical' == (orientation hdl))) {
      return hdl
    }
  }
  return nil
}

method hSlider TableView {
  for each (parts morph) {
    hdl = (handler each)
    if (and (isClass hdl 'Slider') ('horizontal' == (orientation hdl))) {
      return hdl
    }
  }
  return nil
}

method cells TableView {
  cells = (list)
  for each (parts morph) {
    hdl = (handler each)
    if (isClass hdl 'TableCell') {
      add cells hdl
    }
  }
  return cells
}

method redraw TableView anyway {
  if (isNil anyway) {anyway = false}
  allCols = ((columnCount data) + 1)
  allRows = ((rowCount data) + 1)
  c = (min allCols (ceiling ((+ (width morph) padding (cellWidth - rowLabelWidth)) / (padding + cellWidth))))
  r = (min allRows (ceiling ((height morph) / (padding + cellHeight))))
  if (and (not anyway) (c == cols) (r == rows)) {
    updateSliders this
    return
  }
  cols = c
  rows = r
  startCol = (max 1 (min startCol (allCols - (cols - 2))))
  startRow = (max 1 (min startRow (allRows - (rows - 2))))
  buildMorphs this
}

method redrawData TableView {
  allCols = (columnCount data)
  allRows = (rowCount data)
  if (startCol >= allCols) { startCol = 1 }
  if (startRow >= allRows) { startRow = (max 1 (allRows - 50)) }

  if ((width morph) > (+ rowLabelWidth (allCols * cellWidth))) {startCol = 1}
  if ((height morph) > ((allRows + 1) * cellHeight)) {startRow = 1}
  pidx = 0
  for row rows {
    for col cols {
      pidx += 1
      dataRowIdx = ((startRow + row) - 2)
      dataColIdx = ((col + startCol) - 2)
      cell = (at (parts morph) pidx)
      if (row == 1) {
        if (pidx > 1) {
          if (dataColIdx > allCols) {
            blankOut (handler cell)
          } else {
            setData (handler cell) (at (columnNames data) dataColIdx)
          }
        }
      } (col == 1) {
        if (dataRowIdx > allRows) {
          blankOut (handler cell)
        } else {
          setData (handler cell) dataRowIdx
        }
      } else {
        if (dataColIdx > allCols) {
          blankOut (handler cell)
        } (dataRowIdx > allRows) {
          blankOut (handler cell)
        } else {
          setData (handler cell) (cellAt data dataRowIdx dataColIdx)
        }
      }
    }
  }
  costumeChanged morph
}

method show TableView newCol newRow {
  if (isNil newRow) {newRow = startRow}
  if (isNil newCol) {newCol = startCol}
  if (and (newRow == startRow) (newCol == startCol)) {return}
  startRow = newRow
  startCol = newCol
  redrawData this
}

method buildMorphs TableView {
  sliderTransparency = 180
  hSlider = (hSlider this)
  vSlider = (vSlider this)
  removeAllParts morph
  for row rows {
    for col cols {
      if (col == 1) {
        addPart morph (morph (initialize (new 'TableCell') (rowCount data) rowLabelWidth cellHeight true (row == 1)))
      } else {
        addPart morph (morph (initialize (new 'TableCell') nil cellWidth cellHeight (row == 1) false))
      }
    }
  }
  if (isNil hSlider) {
    hSlider = (slider 'horizontal')
    setAlpha (morph hSlider) sliderTransparency
    setAction hSlider  (action 'scrollToCol' this)
  }
  addPart morph (morph hSlider)
  if (isNil vSlider) {
    vSlider = (slider 'vertical')
    setAlpha (morph vSlider) sliderTransparency
    setAction vSlider  (action 'scrollToRow' this)
  }
  addPart morph (morph vSlider)
  fixLayout this
  redrawData this
}

method fixLayout TableView {
  pidx = 0
  l = (left morph)
  t = (top morph)
  y = padding
  for row rows {
    x = padding
    for col cols {
      pidx += 1
      cell = (at (parts morph) pidx)
      setPosition cell (l + x) (t + y)
      x += padding
      if (col == 1) {
        x += rowLabelWidth
      } else {
        x += cellWidth
      }
    }
    y += cellHeight
    y += padding
  }
  updateSliders this
}

method updateSliders TableView {
  hSlider = (hSlider this)
  vSlider = (vSlider this)

  if (notNil vSlider) {
    if ((height morph) > (((rowCount data) + 1) * cellHeight)) {
      hide (morph vSlider)
    } else {
      show (morph vSlider)
      setRight (morph vSlider) (right morph)
      setTop (morph vSlider) (top morph)
      setHeight (bounds (morph vSlider)) (- (height morph) (height (morph hSlider)))
      redraw vSlider
      ceil = ((rowCount data) - (rows - 3))
      size = (min rows ((ceil - 1) / 2))
      update vSlider 1 ceil startRow size
    }
  }
  if (notNil hSlider) {
    if ((width morph) > (+ rowLabelWidth ((columnCount data) * cellWidth))) {
      hide (morph hSlider)
    } else {
      show (morph hSlider)
      setLeft (morph hSlider) (left morph)
      setBottom (morph hSlider) (bottom morph)
      setWidth (bounds (morph hSlider)) (- (width morph) (width (morph vSlider)))
      redraw hSlider
      ceil = ((columnCount data) - (cols - 3))
      size = (min cols ((ceil - 1) / 2))
      update hSlider 1 ceil startCol size
    }
  }
}

method scrollToCol TableView newCol {
  show this newCol
}

method scrollToRow TableView newRow {
  show this nil newRow
}

method step TableView {
  if (or (isNil data) ((changeCount data) == lastChangeCount)) { return }
  redraw this true
  lastChangeCount = (changeCount data)
}

// events

method swipe TableView x y {
  show this (min ((columnCount data) - (cols - 3)) (max 1 (startCol - x))) (min ((rowCount data) - (rows - 3)) (max 1 (startRow - y)))
  updateSliders this
  return true
}


defineClass TableViewer morph window spreadSheet

method initialize TableViewer contents label cellWidth cellHeight windowWidth windowHeight {
  scale = (global 'scale')
  if (not (isClass contents 'Table')) {contents = (table)}
  if (isNil label) {label = 'Table'}
  if (isNil windowWidth) {windowWidth = (scale * 300)}
  if (isNil windowHeight) {windowHeight = (scale * 200)}
  window = (window label)
  morph = (morph window)
  setHandler morph this
  setMinExtent morph  (scale * 50)
  spreadSheet = (initialize (new 'TableView') contents 1 1 cellWidth cellHeight)
  addPart morph (morph spreadSheet)
  setExtent morph windowWidth windowHeight
}

method fixLayout TableViewer {
  fixLayout window
  clientArea = (clientArea window)
  setPosition (morph spreadSheet) (left clientArea) (top clientArea)
  setExtent (morph spreadSheet) (width clientArea) (height clientArea)
}

method redraw TableViewer {
  redraw window
  fixLayout this
}

method setData TableViewer aTable label startColumn startRow cellWidth cellHeight {
  if (notNil label) {setLabelString window label}
  setData spreadSheet aTable startColumn startRow cellWidth cellHeight
}

to viewTable aTable label cellWidth cellHeight windowWidth windowHeight {
  page = (global 'page')
  tw = (new 'TableViewer')
  initialize tw aTable label cellWidth cellHeight windowWidth windowHeight
//  setPosition (morph tw) (x (hand page)) (y (hand page))
  setPosition (morph tw) 900 50
  addPart page tw
  return tw
}

to testTable {
  persons = (table 'First Name' 'Last Name' 'City' 'Project' 'Other')
  addAll persons (list 'Jens' 'Mönig' 'Gäufelden' 'GP' 'Snap')
  addAll persons (list 'John' 'Maloney' 'Cambridge' 'GP' 'Scratch')
  addAll persons (list 'Yoshiki' 'Ohshima' 'Los Angeles' 'GP' 'Squeak')
  addAll persons (list 'Evelyn' 'Eastmond' 'Cambridge' 'Art' 'Scratch')
  addAll persons (list 'Eric' 'Rosenbaum' 'New York' 'Beetleblocks' 'Scratch')
  addAll persons (list 'Bernat' 'Romagosa' 'Barcelona' 'Beetleblocks' 'Snap4Arduino')
  addAll persons (list 'Duks' 'Koschitz' 'New York' 'Beetleblocks' 'Design')
  addAll persons (list 'Brian' 'Harvey' 'Berkeley' 'Snap' 'Logo')
  addAll persons (list 'Paul' 'Goldenberg' 'Newton' 'BJC' 'Logo')
  addAll persons (list 'Michael' 'Ball' 'Berkeley' 'Snap' 'BJC')
  addAll persons (list 'Dan' 'Garcia' 'Berkeley' 'BJC' 'AP CSP')
  return persons
}

to manyRows {
  tab = (table 'class' 'index' 'field' 'function' 'scripts')
  repeat 2500 {
    for cls (classes) {
      if (isNil (scripts cls)) {
        scr = 0
      } else {
        scr = (count (scripts cls))
      }
      add tab (className cls) (classIndex cls) '' '' scr
      for fld (fieldNames cls) {
        add tab (className cls) (classIndex cls) fld '' scr
      }
      for mth (methods cls) {
        add tab (className cls) (classIndex cls) '' (functionName mth) scr
      }
    }
    for fn (functions) {
      add tab '<generic>' '' '' (functionName fn) 0
    }
  }
  return tab
}
