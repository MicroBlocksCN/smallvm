// Experimental GP PartsBin
//

defineClass PartsBin morph project window listBox listPane titleBox thumbnailPane buttonsPane notePane location selection directory projectNames

to newPartsBin loc proj {
  return (initialize (new 'PartsBin') loc proj)
}

to openPartsBin loc {
  page = (global 'page')
  editor = (findProjectEditor)
  proj = (project editor)
  partsBin = (newPartsBin loc proj)
  addPart page partsBin
  doRefresh partsBin
  setPosition (morph partsBin) (x (hand page)) (y (hand page))
  keepWithin (morph partsBin) (bounds (morph page))
  return partsBin
}

method initialize PartsBin loc proj {
  if (isNil loc) {
    conf = (gpServerConfiguration)
    if (notNil conf) {
      user = (at conf 'username')
      serverDirectory = (at conf 'serverDirectory')
      account = (at conf 'account')
      accountPassword = (at conf 'accountPassword')
      m = (loadModule 'modules/DAVDirectory.gpm')
      loc = (join serverDirectory user '/')
      directory = (new (at m 'DAVClient'))
      setUser directory account
      setPassword directory accountPassword
    }
  }
  if (isNil loc) {
     loc = 'projects/'
  }

  location = loc
  project = proj

  scale = (global 'scale')
  window = (window 'PartsBin')
  morph = (morph window)
  setHandler morph this

  buttonsPane = (newBox (newMorph nil) (gray 10 10 10) nil nil false false)
  addPart (morph buttonsPane) (makeButton this 'Load' 'doLoad')
  addPart (morph buttonsPane) (makeButton this 'Refresh' 'doRefresh')
  addPart morph (morph buttonsPane)

  titleBox = (newText)
  setEditRule titleBox 'static'
  setColor titleBox (color 0 0 0) nil (color 255 255 255)
  addPart morph (morph titleBox)

  setText titleBox location

  listBox = (listBox (array) 'name' (action 'select' this) (color 255 255 255))
  setFont listBox 'Arial' 14
 
  listPane = (scrollFrame listBox (clientColor window))

  addPart morph (morph listPane)

  thumbnailPane = (newBox (newMorph nil) (gray 250) nil nil false false)

  text = (newText)
  setFont text 'Arial' (14 * scale)
  //setEditRule text 'static'
  notePane = (scrollFrame text (color 255 255 255))

  addPart morph (morph thumbnailPane)
  addPart morph (morph notePane)

  setMinExtent morph (scale * 600) (scale * 400)
  setExtent morph (scale * 600) (scale * 400)

  fixLayout this
  return this
}

method isNetworkRepository PartsBin {
  return (and (notNil directory) (beginsWith location 'http'))
}

method listOfProjectNames PartsBin {
  if (isNetworkRepository this) {
    projectNames = (listFiles directory location)
  } else {
    projectNames = (listFiles location)
  }
  result = (list)
  for i (count projectNames) {
    elem = (at projectNames i)
    if ((count elem) > 0) {// ???
      add result elem
    }
  }
  projectNames = result
  return projectNames
}

method updateSelection PartsBin {
 scale = (global 'scale')
 if (isNil selection) {
    setText (contents notePane) ''
  }
  str = (notes selection location)
  if ((classOf str) == (class 'String')) {
    setText (contents notePane) str
  }

  loc = (fullPathIn selection location)
  setText titleBox loc

  thumb = (thumbnail selection loc)
  if (notNil thumb) {
    t = (thumbnail thumb ((400 - 40) * scale) ((300 - 40) * scale))
    setCostume (morph thumbnailPane) t
  } else {
    setCostume (morph thumbnailPane) nil
  }
  fixLayout this
}

method refreshContents PartsBin listOfProjectNames {
  // make a dictionary mapping projectNames to their icons
  oldIcons = (dictionary)
  for p (collection listBox) {
	icon = p
	atPut oldIcons (name icon) icon
  }

  // make a dictionary mapping instances to their icons
  newCollection = (list)
  for each listOfProjectNames {
	icon = (at oldIcons each)
	if (isNil icon) {
	  icon = (initialize (new 'PartsItem') each (action 'select' this each) this)
	}
	add newCollection icon
  }
  setCollection listBox newCollection
  fixLayout this
  gc
}

method makeButton PartsBin label selector {
  if (isClass selector 'String') {
	selector = (action selector this)
  }
  button = (pushButton label (color 130 130 130) selector)
  return (morph button)
}

method doRefresh PartsBin {
  safelyRun (action 'listOfProjectNames' this)
  refreshContents this projectNames
}

method doLoad PartsBin {
  if (isNil selection) {return}

  cacheProject selection location
  importExtension project nil (project selection)
  developerModeChanged (findProjectEditor) // update palette
}

// Layout

method redraw PartsBin {
  fixLayout this
  redraw window
}

method fixLayout PartsBin {
  scale = (global 'scale')
  fixLayout window
  area = (clientArea window)
  w = (width area)
  h = (height area)

  setExtent (morph buttonsPane) 200 40
  setPosition (morph buttonsPane) (left area) (top area)
  fixTitleLayout this

  setExtent (morph listPane) (w * 0.3) (h - 40)
  setPosition (morph listPane) (left area) ((top area) + 40)

  th = (((300 - 40) * scale) + 20)
  setExtent (morph thumbnailPane) ((w * 0.7) - 8) th
  ll = ((((w * 0.7) - 4) - ((400 - 40) * scale)) / 2.0)
  setPosition (morph thumbnailPane) (((left area) + (w * 0.3)) + ll) (((top area) + 40) + 10)

  setExtent (morph notePane) ((w * 0.7) - 8) (((h - th) - 40) - 8)
  setPosition (morph notePane) (((left area) + (w * 0.3)) + 4) ((((top area) + th) + 40) + 4)
  wrapLinesToWidth (contents notePane) (max 100 (((w * 0.7) - 8) - 16))
}

method fixTitleLayout PartsBin {
  area = (clientArea window)
  buttons = (parts (morph buttonsPane))

  r = (bounds (morph buttonsPane))
  y = (((height r) / 2) + (top r))
  extraW = (width r)
  for b buttons { extraW += (- (width b)) }
  interButtonSpace = (max 5 (extraW / ((count buttons) + 1)))

  x = (+ (left r) interButtonSpace 1)
  for b buttons {
    setLeft b x
    x += ((width b) + interButtonSpace)
    setYCenter b y
  }

  setExtent (morph titleBox) ((width area) - (width r)) 40
  setMinWidth titleBox ((((width area) - (width r)) - 10) - 100)
  setPosition (morph titleBox) ((right r) + 100) (top r)
}

method select PartsBin anObject {
  selection = anObject
  updateSelection this
}

method isSelected PartsBin aPartsItem {
  if (isNil selection) {return false}

  return ((name selection) == (name aPartsItem))
}

method selection PartsBin {return selection}

// PartsItem - a list item to represent a part
// name is a project name in string (from the file name for now...) 
// if project is loaded, project is filled in as a cache

defineClass PartsItem name toggle project

method project PartsItem { return project }
method name PartsItem { return name }

method fullPathIn PartsItem location {
  return (join location name)
}

method cacheProject PartsItem location {
  if (isNil project) {
    project = (new 'Project')
    data = (readData project (fullPathIn this location))
    project = (readProject project data)
  }
}

method notes PartsItem location {
  cacheProject this location
  return (notes project)
}

method thumbnail PartsItem location {
  cacheProject this location
  return (thumbnail project)
}

method initialize PartsItem aString onSelect list {
  if (isNil onSelect) {onSelect = 'nop'}
  name = aString
  query = (action 'isSelected' list this)
  toggle = (createToggle this onSelect query aString)
  return this
}

method createToggle PartsItem onSelect query aString {
  scale = (global 'scale')
  clr = (color 255 0 0)
  clr2 = (color 0 255 0)
  size = (scale * 46)
  corner = (scale * 3)
  border = scale

  trigger = (new 'Trigger' nil onSelect)
  m = (newMorph)
  setMorph trigger m
  setWidth (bounds m) size
  setHeight (bounds m) size
  tg = (new 'Toggle' m trigger query 'handEnter')
  setHandler m tg
  refresh tg
  return tg
}

method refresh PartsItem {refresh toggle}
