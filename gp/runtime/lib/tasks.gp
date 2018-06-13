// Tasks and Scheduler

defineClass Task stack sp fp mp currentBlock nextBlock result tickLimit taskToResume waitReason wakeMSecs profileArray profileIndex errorReason topBlock doneAction receiver

classComment Task '
A task ("thread" or "process") represents the suspended execution state of a
GP program in a form that can be examined, manipulated, or resumed. If a set
of tasks takes turns running, then it appears that are all running at once,
even though only one of them is running at any given moment. A TaskMaster
object manages such a set of "concurrent" tasks. Another use of tasks is
debugging: the debugger allows you to examine, step, or resume a task
that encounters an error or halt.

Sometime a task must to wait for something to happen. A task can wait
for either the next display update (useful for animation) or for time
to elapse. Tasks that need to wait for other conditions, for example for
some data to be returned by a hardware device or server, can do so by
repeatedly testing for the desired condition, then waiting for a short
time before testing again. This is sometimes called "polling". Polling
in a loop without a wait would waste processor cycles, but since the
condition test is quick, waiting just a few milliseconds between tests
allows other tasks to run and wastes very few processor cycles.

Key primitives for working with tasks include:

  yield - yield control, allowing other tasks to run
  resume task - resume the given task
  currentTask - return the currently running task
  debugeeTask - the task that most recently encountered an error or halt
'

method stack Task { return stack }
method waitReason Task { return waitReason }
method setWaitReason Task reason { waitReason = reason }
method errorReason Task { return errorReason }

method wakeMSecs Task { return wakeMSecs }
method doneAction Task { return doneAction }
method result Task { return result }
method topBlock Task { return topBlock }
method setTopBlock Task cmd { topBlock = cmd }
method receiver Task { return receiver }

to newTask cmdList targetObj doneAction {
  // Return a new task to run the given command list. The optional doneAction will
  // be called when this task completes, passing the value the task returned, if any.

  topBlock = cmdList

  if (isClass cmdList 'Reporter') {
    cmdList = (newCommand 'return' cmdList)
  }
  if (not (isClass cmdList 'Command')) { // cmdList is function or action
    cmdList = (newCommand 'call' cmdList)
  }

  if (notNil targetObj) {
	func = (functionFor targetObj cmdList)
    cmdList = (newReporter 'call' func targetObj)
  }

  task = (new 'Task')
  stack = (newArray 200)
  atPut stack 1 nil // push nil
  atPut stack 2 100 // push "STOP"
  setField task 'stack' stack
  setField task 'sp' 3
  setField task 'fp' 3
  setField task 'mp' 0
  setField task 'currentBlock' true // must be non-nil
  setField task 'nextBlock' cmdList
  setField task 'topBlock' topBlock
  setField task 'doneAction' doneAction
  setField task 'receiver' targetObj
  return task
}

method runTask Task {
  // For testing. Tasks are usually run only by the task manager.
  taskToResume = (currentTask)
  tickLimit = 1000000
  resume this
  return result
}

method isTerminated Task {
  return (or (isNil currentBlock) ('terminated' == waitReason) ('error' == waitReason))
}

method isRunning Task aBlock rcvr {
  if (or (isNil rcvr) (receiver == rcvr)) {
	if (topBlock == aBlock) { return true }
  }
  return false
}

method caller Task {
  // Return the function that called the current function (or nil).

  lastMP = mp
  if (lastMP > 1) {
	lastMP = (at stack (lastMP + 2))
	return (at stack (lastMP + 1))
  }
  return nil
}

method openDebugger Task {
  page = (global 'page')
  if (isNil page) { return }
  stopAll page
  gc
  stats = (memStats)
  freeMBytes = (((at stats 2) - (at stats 1)) / 1000000) // megabytes
  if (freeMBytes < 15) {
	stack = nil // free my stack
	gc
	inform page (join 'Error: Low memory')
	return
  }
  if ('step' == (lastMethodOrFunction this)) {
	// if an error occurs in the step method for a handler, disable stepping of its morph
	h = (lastReceiver this)
	if (hasField h 'morph') {
	  disableStepping (getField h 'morph')
	}
  }
  result = (safelyRun (action 'addPart' page (new 'Debugger' this)) (action 'id' 'failed'))
  if ('failed' == result) {
	stack = nil // free my stack
	gc
	inform page (join 'Error: ' errorReason)
  }
}

method lastMethodOrFunction Task  {
  // Return the name of the current method or function, or nil if there are no calls on stack.

  if (mp <= 1) { return nil }
  return (functionName (at stack (mp + 1)))
}

method lastReceiver Task {
  // Return the first argument of the most recent call or nil.

  if (mp <= 1) { return nil }
  func = (at stack (mp + 1))
  thisCallFP = (at stack (mp - 1))
  argCount = (((mp - thisCallFP) - 1) - (count (localNames func)))
  if (argCount < 1) { return nil }
  return (at stack thisCallFP)
}

method hasDebugger Task {
  // Return true if this task contains a call with Debugger as the receiver.
  // Used to detect recursive attempts to open a debugger.

  if (isNil stack) { return false }
  thisMP = mp
  while (thisMP > 1) {
    func = (at stack (thisMP + 1))
	if (and (notNil func) (isMethod func)) {
	  fp = (at stack (thisMP - 1))
	  rcvr = (at stack fp)
	  if (isClass rcvr 'Debugger') { return true }
	}
    thisMP = (at stack (thisMP + 2))
  }
  return false
}

to stopTask {
  // Stop the caller's task.
  setField (currentTask) 'waitReason' 'terminated'
  yield // will stop execution, even if not in scheduler
}

method checkTimer Task {
  // Stop waiting if my time has come.
  if (waitReason != 'timer') { return }
  if ((msecsSinceStart) >= wakeMSecs) {
    waitReason = nil // stop waiting
  }
}

to waitSecs secs {
  if (isNil secs) { secs = 0 }
  waitMSecs (1000 * secs)
}

to waitMSecs msecs {
  // Wait for the given number of milliseconds.

  msecs = (truncate msecs)
  if (msecs <= 0) {
	waitForNextFrame
	return
  }

  task = (currentTask)
  if (isNil (getField task 'tickLimit')) { // not in scheduler
    sleep msecs
	return
  }

  now = (msecsSinceStart)
  wakeTime = (now + msecs)
  if (wakeTime < 0) { // clock wrap
    wakeTime = (msecs - ((maxInt) - now))
  }
  setField task 'waitReason' 'timer'
  setField task 'wakeMSecs' wakeTime
  yield
}

to waitForNextFrame {
  // Wait for the next display frame. (Useful for animation.)

  if (isNil (getField (currentTask) 'tickLimit')) {
	return // not in scheduler
  }
  setWaitReason (currentTask) 'display'
  yield
}

defineClass TaskMaster taskList emergencyMemory

to newTaskMaster { return (new 'TaskMaster' (list)) }

method isRunning TaskMaster aBlock rcvr {
  for task taskList {
	if (isRunning task aBlock rcvr) { return true }
  }
  return false
}

method numberOfTasksRunning TaskMaster aBlock rcvr {
  count = 0
  for task taskList {
    if (isRunning task aBlock rcvr) { count += 1 }
  }
  return count
}

method stopRunning TaskMaster aBlock rcvr {
  for task taskList {
	if (isRunning task aBlock rcvr) {
	  setWaitReason task 'terminated'
	}
  }
}

method stopTasksFor TaskMaster rcvr {
  // Stop all tasks for the given receiver.
  if (isNil rcvr) { return }
  for task (copy taskList) {
	if (rcvr == (receiver task)) {
	  setWaitReason task 'terminated'
	}
  }
}

method addTask TaskMaster task { addFirst taskList task }

method wakeUpDisplayTasks TaskMaster {
  // Called once per display cycle loop to wake all tasks waiting on next display frame.

  for task taskList {
    if ('display' == (waitReason task)) { setWaitReason task nil }
  }
}

method stepTasks TaskMaster msecsToStep {
  timer = (newTimer)
  while ((msecs timer) < msecsToStep) {
	ranTask = (stepTasksOnce this timer)
	if (not ranTask) { return }
  }
}

method stepTasksOnce TaskMaster timer {
  // Step all tasks that are not waiting or terminated and remove
  // any terminated tasks from tht task list.
  // Note: Since running a task can spawn new tasks, this method
  // make a copy of the current task list. Any newly launched
  // tasks will get handled by the next call.

  if (isNil emergencyMemory) { emergencyMemory = (newBinaryData 10000) }
  taskListCopy = taskList
  taskList = (list)
  ranTask = false
  for task taskListCopy {
	if ((msecs timer) > 1000) { return ranTask } // emergency stop
    if ('timer' == (waitReason task)) { checkTimer task }
    if (isNil (waitReason task)) { // found runnable task
	  ranTask = true
	  setField task 'taskToResume' (currentTask)
	  setField task 'tickLimit' 1000
	  resume task
 	}
	if (isTerminated task) {
	  if ('error' == (waitReason task)) {
	  emergencyMemory = nil
		openDebugger task
		return true
	  } (notNil (doneAction task)) {
        call (doneAction task) (result task)
	    setField task 'currentBlock' nil
	  }
	} else {
      add taskList task // still active
    }
  }
  return ranTask
}

method stepAllTasksUntilDone TaskMaster {
  // Useful for testing. Step tasks until all tasks have terminated.
  while ((count taskList) > 0) {
    stepTasksOnce this (newTimer)
  }
}

to safelyRun funcOrAction errorFuncOrAction {
  task = (newTask (newReporter 'call' funcOrAction))
  setField task 'tickLimit' 1000000
  setField task 'taskToResume' (currentTask)
  while true {
	resume task
	if ('error' == (waitReason task)) {
	  gcIfNeeded
	  if (notNil errorFuncOrAction) {
		return (call errorFuncOrAction task)
	  }
	  return task
	} (isTerminated task) {
	  return (result task)
	} ('timer' == (waitReason task)) {
	  msecsToWait = ((wakeMSecs task) - (msecsSinceStart))
	  if (msecsToWait > 0) { waitMSecs msecsToWait }
	  setField task 'waitReason' nil
	}
  }
}
