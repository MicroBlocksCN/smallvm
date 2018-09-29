defineClass Action function arguments

method function Action { return function }
method arguments Action { return arguments }

classComment Action '
An Action combines a function with zero or more arguments.
The Action can be invoked, possibly with some additonal
arguments, using "call" or "callWith" method, as if it
were a normal function or function name.'

to action func args... {
  // Create an Action that combines the given function and arguments.
  // The function can be either the name of a function or (less commonly)
  // an actual function object, or even another Action object.

  argList = (list)
  for i (argCount) {
    if (i > 1) { add argList (arg i) }
  }
  return (new 'Action' func (toArray argList))
}

method call Action args... {
  // Return the result of calling the Action's function on its
  // arguments and zero or more additional arguments.

  if ((argCount) == 1) {
    return (callWith function arguments)
  }
  allArgs = (toList arguments)
  for i (argCount) {
    if (i > 1) { add allArgs (arg i) }
  }
  return (callWith function (toArray allArgs))
}

method callWith Action argsArray {
  allArgs = (join arguments argsArray)
  return (callWith function allArgs)
}
