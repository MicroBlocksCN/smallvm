// Readout  - mixin to readout and manipulate the value of a field

defineClass Readout name target field widget setter value

to readout name target field widget setter {
  return (new 'Readout' name target field widget setter)
}

method morph Readout {return (morph widget)}
method name Readout {return name}

method update Readout {
  if (isAnyClass target 'Dictionary' 'List') {
	v = (at target field)
  } else {
	v =  (getField target field)
  }
  if (v != value) {
    value = v
    call setter widget v
    changed (morph widget)
  }
}
