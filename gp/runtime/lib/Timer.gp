defineClass Timer start splitStart

to newTimer { return (new 'Timer' (time) (time)) }

method reset Timer {
  start = (time)
  splitStart = start
}

method secs Timer {
  now = (time)
  return ((at now 1) - (at start 1))
}

method msecs Timer {
  now = (time)
  secs = ((at now 1) - (at start 1))
  usecs = ((at now 2) - (at start 2))
  return ((1000 * secs) + (truncate (usecs / 1000)))
}

method usecs Timer {
  now = (time)
  secs = ((at now 1) - (at start 1))
  usecs = ((at now 2) - (at start 2))
  return ((1000000 * secs) + usecs)
}

method usecSplit Timer {
  // A 'split' allows a single timer to measure and report the time for
  // subparts of while also keeping track of the total time.
  now = (time)
  secs = ((at now 1) - (at splitStart 1))
  usecs = ((at now 2) - (at splitStart 2))
  splitStart = (time)
  return ((1000000 * secs) + usecs)
}

method msecSplit Timer { return (truncate ((usecSplit this) / 1000)) }

to usecsToRun f args... {
  args = (newArray ((argCount) - 1))
  for i ((argCount) - 1) {
    atPut args i (arg (i + 1))
  }
  t = (newTimer)
  callWith f args
  return (usecs t)
}

to secsSinceMidnight useGMT {
    return ((at (time (useGMT != true)) 1) % (24 * (60 * 60)))
}

to hour useGMT   { return (truncate ((secsSinceMidnight useGMT) / (60 * 60))) }
to minute useGMT { return (truncate (((secsSinceMidnight useGMT) % (60 * 60)) / 60)) }
to second useGMT { return ((secsSinceMidnight useGMT) % 60) }
