// Exercise the production capability methods without opening a serial port or UI.
method updateConnection SmallRuntime { return 'connected' }
method isWebSerial SmallRuntime { return false }
method connectedToBoard SmallRuntime { return true }
method setTestBoard SmallRuntime type {
    boardType = type
    disconnected = false
}

to testStickS3Capabilities {
    runtime = (new 'SmallRuntime')
    for type (array 'M5StickS3' 'M5StickC+' 'ESP32-S3') {
        setTestBoard runtime type
        if (not (assert (boardIsBLECapable runtime) true 'BLE capability missing')) { return }
        if (not (assert (boardHasFileSystem runtime) true 'filesystem capability missing')) { return }
    }
    setTestBoard runtime 'unknown board'
    if (not (assert (boardIsBLECapable runtime) false 'unknown BLE capability')) { return }
    if (not (assert (boardHasFileSystem runtime) false 'unknown filesystem capability')) { return }
    print 'ide capabilities: PASS'
}

testStickS3Capabilities
