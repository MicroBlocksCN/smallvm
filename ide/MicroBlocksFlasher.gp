// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksFlasher.gp - An interface to esptool to flash Espressif boards
// Bernat Romagosa, September 2019

defineClass MicroBlocksFlasher overlay morph paddle1 paddle2 rotation commands currentCommandPID label sublabel destroyAtMs selector boardName

to newFlasher actionSelector board {
  return (initialize (new 'MicroBlocksFlasher') actionSelector board)
}

method initialize MicroBlocksFlasher actionSelector board {
  selector = actionSelector
  boardName = board
  overlay = (newBox nil (gray 100))
  morph = (morph overlay)
  setTransparency (morph overlay) 30

  paddle1 = (newBox nil (gray 200) 10)
  paddle2 = (newBox nil (gray 200) 10)
  rotation = 0

  scale = (global 'scale')
  label = (newText (localized 'Uploading...') 'Arial' (18 * scale) (gray 200))
  addPart morph (morph label)

  sublabel = (newText (localized '(press ESC to cancel)') 'Arial' (12 * scale) (gray 170))
  addPart morph (morph sublabel)

  addPart morph (morph paddle1)
  addPart (morph paddle1) (morph paddle2)

  redraw this

  return this
}

method redraw MicroBlocksFlasher {
  setExtent (morph overlay) (width (bounds (morph (global 'page')))) (height (bounds (morph (global 'page'))))
  gotoCenterOf (morph overlay) (morph (global 'page'))
  setExtent (morph paddle1) 100 20
  setExtent (morph paddle2) 20 100
  gotoCenterOf (morph paddle1) (morph (global 'page'))
  gotoCenterOf (morph paddle2) (morph (global 'page'))
  gotoCenterOf (morph label) (morph (global 'page'))
  gotoCenterOf (morph sublabel) (morph (global 'page'))
  moveBy (morph label) 0 80
  moveBy (morph sublabel) 0 110
  redraw overlay
  redraw paddle1
}

method step MicroBlocksFlasher {
  if (notNil destroyAtMs) {
    setTransparency (morph paddle1) ((transparency (morph paddle1)) + 5)
    setTransparency (morph paddle2) ((transparency (morph paddle2)) + 5)
    setTransparency (morph overlay) ((transparency (morph overlay)) + 5)
    if ((msecsSinceStart) > destroyAtMs) {
      removeFlasher (smallRuntime)
    }
  }
  rotation = (rotation - 1)
  rotateAndScale (morph paddle1) rotation
  redraw this
  processStatus = (execStatus currentCommandPID)
  if (notNil processStatus) {
    if (processStatus == 1) {
      setText label (localized 'An error occurred!')
      setColor label (color 255 50 50)
      removePart morph (morph sublabel)
      destroyAtMs = ((msecsSinceStart) + 3000)
      print (join 'Command ' (joinStrings (first commands) ' ') ' failed')
    } else {
      removeFirst commands
      if (isEmpty commands) {
        setText label (localized 'Done!')
        setColor label (gray 50)
        removePart morph (morph sublabel)
        destroyAtMs = ((msecsSinceStart) + 1000)
      } else {
        currentCommandPID = (call (new 'Action' 'exec' (first commands)))
      }
    }
  }
}

method destroy MicroBlocksFlasher {
  destroy morph
}

method start MicroBlocksFlasher {
  call selector this
}

method repartitionFlash MicroBlocksFlasher {
  setText label (localized 'Wiping board...')

  copyEspToolToDisk this
  copyEspFilesToDisk this

  esptool = (join (tmpPath this) (esptoolCommandName this))
  tmpPath = (tmpPath this)
  commands = (list
    (array esptool '-b' '921600' 'write_flash' '0x0e00' (join tmpPath 'boot_app0.bin'))
    (array esptool '-b' '921600' 'write_flash' '0x1000' (join tmpPath 'bootloader_dio_80m.bin'))
    (array esptool '-b' '921600' 'write_flash' '0x8000' (join tmpPath 'partitions.bin')))
  currentCommandPID = (call (new 'Action' 'exec' (first commands)))
}

method flashVM MicroBlocksFlasher {
  setText label (localized 'Uploading MicroBlocks to board...')

  copyEspToolToDisk this
  copyVMtoDisk this

  esptool = (join (tmpPath this) (esptoolCommandName this))
  address = '0x10000' // for ESP32-based boards
  if (boardName == 'ESP8266') { address = '0' }
  commands = (list (array esptool '-b' '921600' 'write_flash' address (join (tmpPath this) 'vm')))
  currentCommandPID = (call (new 'Action' 'exec' (first commands)))
}

method tmpPath MicroBlocksFlasher {
  if (or ('Mac' == (platform)) ('Linux' == (platform))) {
    return '/tmp/'
  } else { // Windows
    return (join (userHomePath) '/AppData/Local/Temp/')
  }
}

method copyEspToolToDisk MicroBlocksFlasher {
  if ('Mac' == (platform)) {
    esptoolData = (readEmbeddedFile 'esptool/esptool' true)
    destination = (join (tmpPath this) 'esptool')
  } ('Linux' == (platform)) {
    esptoolData = (readEmbeddedFile 'esptool/esptool.py')
    destination = (join (tmpPath this) 'esptool.py')
  } ('Win' == (platform)) {
    esptoolData = (readEmbeddedFile 'esptool/esptool.exe' true)
    destination = (join (tmpPath this) 'esptool.exe')
  }
  writeFile destination esptoolData
  setFileMode destination (+ (7 << 6) (5 << 3) 5) // set executable bits
}

method copyVMtoDisk MicroBlocksFlasher {
  if (boardName == 'ESP8266') {
    vmData = (readEmbeddedFile 'precompiled/vm.ino.nodemcu.bin' true)
  } (boardName == 'ESP32') {
    vmData = (readEmbeddedFile 'precompiled/vm.ino.esp32.bin' true)
  } (boardName == 'Citilab ED1') {
    vmData = (readEmbeddedFile 'precompiled/vm.ino.citilab-ed1.bin' true)
  } (boardName == 'M5Stack-Core') {
    vmData = (readEmbeddedFile 'precompiled/vm.ino.m5stack.bin' true)
  }
  writeFile (join (tmpPath this) 'vm') vmData
}

method copyEspFilesToDisk MicroBlocksFlasher {
  for fn (array 'boot_app0.bin' 'bootloader_dio_80m.bin' 'ed1_1000.bin' 'ed1_8000.bin' 'ed1_E00.bin' 'partitions.bin') {
    fileData = (readEmbeddedFile (join 'esp32/' fn) true)
    writeFile (join (tmpPath this) fn) fileData
  }
}

method esptoolCommandName MicroBlocksFlasher {
  if ('Mac' == (platform)) {
    return 'esptool'
  } ('Linux' == (platform)) {
    return 'esptool.py'
  } ('Win' == (platform)) {
    return 'esptool.exe'
  }
  return ''
}
