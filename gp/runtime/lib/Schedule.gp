defineClass Schedule action when repeat timer

to schedule action inMsecs repeat {
  if (isNil inMsecs) {inMsecs = 0} // immediately, i.e. at the next step
  if (isNil repeat) {repeat = 1}
  return (new 'Schedule' action inMsecs repeat (newTimer))
}

method op Schedule {
  // Return the function name of my first action.
  if (isClass action 'Array') {
	return (function (first action))
  }
  return (function action)
}

method args Schedule {
  // Return the arguments to the function name of my first action.
  return (arguments action)
}

method step Schedule {
  if (or (isDone this) (when > (msecs timer))) {return}
  if (isClass action 'Array') {
    for each action {call each}
  } else {
    call action
  }
  if (isClass repeat 'Integer') {
    repeat += -1
  }
  reset timer
}

method isDone Schedule {
  return (or
    (repeat == 0)
    (and
      (isAnyClass repeat 'Action' 'Function' 'String')
      (not (call repeat))
    )
  )
}
