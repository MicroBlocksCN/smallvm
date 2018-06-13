// a window around a script editor pane

defineClass BlockEditor morph window scripts scriptsFrame

method initialize BlockEditor contents {
  scale = (global 'scale')
  if (not (isClass contents 'Block')) {contents = nil}
  window = (window 'Block Editor')
  morph = (morph window)
  setHandler morph this
  setMinExtent morph (scale * 100) (scale * 150)

  scripts = (newScriptEditor 10 10)
  if (notNil contents) {
    setPosition (morph contents) 10 10
    addPart (morph scripts) (morph contents)
  }
  scriptsFrame = (scrollFrame scripts (gray 220))
  addPart morph (morph scriptsFrame)

  setExtent morph (scale * 250) (scale * 330)
}

method fixLayout BlockEditor {
  fixLayout window
  clientArea = (clientArea window)
  setPosition (morph scriptsFrame) (left clientArea) (top clientArea)
  setExtent (morph scriptsFrame) (width clientArea) (height clientArea)
}

method redraw BlockEditor {
  redraw window
  fixLayout this
}

to openBlockEditor page contents {
  be = (new 'BlockEditor')
  initialize be contents
  setPosition (morph be) (x (hand page)) (y (hand page))
  addPart page be
}
