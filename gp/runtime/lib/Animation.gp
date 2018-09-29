// Animation.gp - An animation acts like a Schedule object.

// Example: Animate morph m from left = 0 to 1000 over half a second:
//   addSchedule (global 'page') (newAnimation 0 1000 500 (action 'setLeft' m))

defineClass Animation startValue endValue duration setter doneAction isDone useFloats startMSecs

to newAnimation startValue endValue duration setter doneAction useFloats {
  if (isNil setter) { setter = 'print' }
  if (isNil useFloats) { useFloats = false }
  result = (new 'Animation')
  setField result 'startValue' startValue
  setField result 'endValue' endValue
  setField result 'duration' (max duration 1)
  setField result 'setter' setter
  setField result 'doneAction' doneAction
  setField result 'isDone' false
  setField result 'useFloats' useFloats
  return result
}

method isDone Animation { return isDone }
method useFloats Animation { return useFloats }
method setUseFloats Animation flag { useFloats = flag }
method op Animation { return (function setter) }

method step Animation {
  if (isNil startMSecs) {
	startMSecs = (toFloat (msecsSinceStart))
  }
  if isDone { return }
  t = (((msecsSinceStart) - startMSecs) / duration)
  if (t > 1) {
	call setter endValue
	if (notNil doneAction) { call doneAction }
	isDone = true
  } else {
	// Cubic, slow-out animation (i.e. start fast and decellerate)
	frac = (1.0 - t) // remaining time fraction; goes from 0 to 1
	delta = (endValue - startValue)
	currentValue = (startValue + (delta * (1.0 - (* frac frac frac))))
	if (not useFloats) { currentValue = (toInteger currentValue) }
	call setter currentValue
  }
}
