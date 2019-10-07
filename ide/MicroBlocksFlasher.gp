// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksFlasher.gp - An interface to esptool to flash Espressif boards
// Bernat Romagosa, September 2019

defineClass MicroBlocksFlasher overlay morph paddle1 paddle2 rotation commands currentCommandPID label sublabel destroyAtMs selector arguments boardName

to newFlasher actionSelector args board {
  return (initialize (new 'MicroBlocksFlasher') actionSelector args board)
}

method initialize MicroBlocksFlasher actionSelector args board {
  selector = actionSelector
  arguments = args
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
        currentCommandPID = (callWith 'exec' (first commands))
      }
    }
  }
}

method destroy MicroBlocksFlasher {
  destroy morph
}

method start MicroBlocksFlasher {
  callWith selector (join (array this) arguments)
}

method flashVM MicroBlocksFlasher wipeFlashFlag downloadLatest {
  if wipeFlashFlag {
    setText label (localized 'Wiping board...')
  } else {
    setText label (localized 'Uploading MicroBlocks to board...')
  }

  copyEspToolToDisk this
  copyEspFilesToDisk this
  if downloadLatest {
    downloadVMtoDisk this
  } else {
    copyVMtoDisk this
  }

  esptool = (join (tmpPath this) (esptoolCommandName this))
  tmpPath = (tmpPath this)

  commands = (list
    (array
      esptool '-b' '921600' 'write_flash'
        '0x1000' (join tmpPath 'bootloader_dio_40m.bin')
        '0x8000' (join tmpPath 'partitions.bin')
        '0xe000' (join tmpPath 'boot_app0.bin')
        '0x10000' (join tmpPath 'vm')))

  if (boardName == 'ESP8266') {
    commands = (list
      (array
        esptool '-b' '921600' 'write_flash' '0' (join tmpPath 'vm')))
  }

  if wipeFlashFlag {
    addFirst commands (array esptool 'erase_flash')
  }

  currentCommandPID = (callWith 'exec' (first commands))
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
    embeddedFileName = 'esptool/esptool'
    esptoolFileName = 'esptool'
    isBinary = true
  } ('Linux' == (platform)) {
    embeddedFileName = 'esptool/esptool.py'
    esptoolFileName = 'esptool.py'
    isBinary = false
  } ('Win' == (platform)) {
    embeddedFileName = 'esptool/esptool.exe'
    esptoolFileName = 'esptool.exe'
    isBinary = true
  }
  if (not (contains (listFiles (tmpPath this)) esptoolFileName)) {
    esptoolData = (readEmbeddedFile embeddedFileName isBinary)
    destination = (join (tmpPath this) esptoolFileName)
    writeFile destination esptoolData
    setFileMode destination (+ (7 << 6) (5 << 3) 5) // set executable bits
  }
}

method vmNameForCurrentBoard MicroBlocksFlasher {
  d = (dictionary)
  atPut d 'ESP8266' 'vm.ino.nodemcu.bin'
  atPut d 'IOT-BUS' 'vm.ino.iot-bus.bin'
  atPut d 'ESP32' 'vm.ino.esp32.bin'
  atPut d 'Citilab ED1' 'vm.ino.citilab-ed1.bin'
  atPut d 'M5Stack-Core' 'vm.ino.m5stack.bin'
  return (at d boardName)
}

method copyVMtoDisk MicroBlocksFlasher {
  vmData = (readEmbeddedFile (join 'precompiled/' (vmNameForCurrentBoard this)) true)
  writeFile (join (tmpPath this) 'vm') vmData
}

method downloadVMtoDisk MicroBlocksFlasher {
  runtime = (smallRuntime)
  vmPath = (join (latestReleasePath runtime) (vmNameForCurrentBoard this))
  response = (httpGetBinary 'gpblocks.org' vmPath)
  (writeFile
    (join (tmpPath this) 'vm')
    (httpBody response))
}

method copyEspFilesToDisk MicroBlocksFlasher {
  tmpFiles = (listFiles (tmpPath this))
  for fn (array 'boot_app0.bin' 'bootloader_dio_40m.bin' 'partitions.bin') {
    if (not (contains tmpFiles fn)) {
      fileData = (readEmbeddedFile (join 'esp32/' fn) true)
      writeFile (join (tmpPath this) fn) fileData
    }
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
