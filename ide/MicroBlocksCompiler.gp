// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksCompiler.gp - A blocks compiler for microBlocks
// John Maloney, April, 2017

defineClass SmallCompiler opcodes primsets argNames localVars trueObj falseObj zeroObj stringClassID

method initialize SmallCompiler {
	initOpcodes this
	initPrimsets this
	argNames = (dictionary)
	localVars = (dictionary)
	falseObj = 0
	trueObj = 4
	zeroObj = ((0 << 1) | 1)
	stringClassID = 4
	return this
}

method dumpTranslationTemplate SmallCompiler {
	result = (list)
	for item (microBlocksSpecs this) {
		if (isClass item 'Array') {
			add result (at item 3)
			add result (at item 3)
			add result ''
		}
	}
	writeFile 'microBlocksTranlationTemplate.txt' (joinStrings result (newline))
}

method microBlocksSpecs SmallCompiler {
	return (array
	'Output'
		(array ' ' 'setUserLED'			'set user LED _' 'bool' true)
		(array ' ' 'sayIt'				'say _ : _ : ...' 'auto auto auto auto auto auto auto auto auto auto' 123 '' '')
		(array ' ' 'printIt'			'graph _ : _ : ...' 'auto auto auto auto auto auto auto auto auto auto' 100)
	'Input'
		(array 'r' 'buttonA'			'button A')
		(array 'r' 'buttonB'			'button B')
		'-'
		(array 'r' 'timer'				'timer')
		(array ' ' 'resetTimer'			'reset timer')
		'-'
		(array 'r' 'secsOp'				'seconds')
		(array 'r' 'millisOp'			'milliseconds')
		(array 'r' 'microsOp'			'microseconds')
		'-'
		(array 'r' 'boardType'			'board type')
		(array 'r' '[misc:version]'		'version')
		'-'
		(array 'r' '[misc:bleID]'		'BLE id')
		(array 'r' '[ble:bleConnected]' 'BLE connected')
	'Input-Advanced'
		(array 'r' 'millisSince'		'milliseconds since _ : end time _' 'num auto' 0 'now')
		(array 'r' 'microsSince'		'microseconds since _ : end time _' 'num auto' 0 'now')
		'-'
		(array 'r' '[misc:connectedToIDE]'	'connected to IDE')
	'Pins'
		(array 'r' 'digitalReadOp'		'read digital pin _ : pull _' 'num menu.pullMenu' 1 'none')
		(array 'r' 'analogReadOp'		'read analog pin _ : pull _' 'num menu.pullMenu' 1 'none')
		'-'
		(array ' ' 'digitalWriteOp'		'set digital pin _ to _' 'num bool' 1 true)
		(array ' ' 'analogWriteOp'		'set pin _ to _' 'num num' 1 1023)
		'-'
		(array 'r' 'analogPins'			'analog pins')
		(array 'r' 'digitalPins'		'digital pins')
	'Comm'
		(array 'r' 'i2cGet'				'i2c get device _ register _' 'num num')
		(array ' ' 'i2cSet'				'i2c set device _ register _ to _' 'num num num')
		'-'
		(array ' ' '[sensors:i2cRead]'	'i2c device _ read list _' 'num auto')
		(array ' ' '[sensors:i2cWrite]'	'i2c device _ write list _ : stop _' 'num auto bool')
		'-'
		(array 'r' '[sensors:i2cExists]' 'i2c device _ exists?' 'num')
		'-'
		(array ' ' 'spiSend'				'spi send _' 'num' 0)
		(array 'r' 'spiRecv'				'spi receive')
		(array ' ' '[sensors:spiSetup]'		'spi setup speed _ : mode _ : rpi channel _ : bit order _' 'num num num str' 1000000 0 0 'MSB')
		(array ' ' '[sensors:spiExchange]'	'spi exchange bytes _' 'auto' 'aByteArray')
		'-'
		(array ' ' '[serial:open]'			'serial open _ baud' 'num' 9600)
		(array ' ' '[serial:close]'			'serial close')
		(array 'r' '[serial:read]'			'serial read')
		(array ' ' '[serial:write]'			'serial write _' 'auto' 'anIntegerStringListOrByteArray')
		(array 'r' '[serial:writeBytes]'	'serial write _ starting at _' 'auto num' 'aStringListOrByteArray' 1)
		'-'
		(array ' ' '[io:softWriteByte]'		'soft serial write byte _ pin _ baud _' 'num num num' '85' 2 9600)
	'Control'
		(array 'h' 'whenStarted'		'when started')
		(array 'h' 'whenButtonPressed'	'when button _ pressed' 'menu.buttonMenu' 'A')
		(array ' ' 'forever'			'forever _' 'cmd')
		(array ' ' 'repeat'				'repeat _ _' 'num cmd' 10)
		(array ' ' 'waitMillis'			'wait _ millisecs' 'num' 500)
		'-'
		(array ' ' 'if'					'if _ _ : else if _ _ : ...' 'bool cmd bool cmd')
		'-'
		(array 'h' 'whenCondition'		'when _' 'bool')
		(array ' ' 'waitUntil'			'wait until _' 'bool')
		'-'
		(array ' ' 'return'				'return _' 'auto' 0)
		'-'
		(array 'h' 'whenBroadcastReceived'	'when _ received' 'str.broadcastMenu' 'go!')
		(array ' ' 'sendBroadcast'		'broadcast _' 'str.broadcastMenu' 'go!' '')
		'-'
		(array ' ' 'comment'			'comment _' 'str' 'How this works...')
		(array 'r' '[data:range]'		'range _ to _ : by _' 'num num num' 1 10 2)
		(array ' ' 'for'				'for _ in _ _' 'var num cmd' 'i' 10)
		(array ' ' 'repeatUntil'		'repeat until _ _' 'bool cmd' false)
		'-'
		(array ' ' 'stopTask'			'stop this task')
		(array ' ' 'stopAll'			'stop other tasks')
	'Control-Advanced'
		(array ' ' 'waitMicros'			'wait _ microsecs' 'num' 1000)
		'-'
		(array 'r' 'getLastBroadcast'	'last message')
		(array 'r' 'argOrDefault'		'arg _ default _' 'num auto' 1 'default')
		'-'
		(array ' ' 'callCustomCommand'	'call _ : with _' 'str.functionNameMenu str' 'function name' 'parameter list')
		(array 'r' 'callCustomReporter'	'call _ : with _' 'str.functionNameMenu str' 'function name' 'parameter list')
	'Operators'
		(array 'r' '+'					'_ + _' 'num num' 10 2)
		(array 'r' '-'					'_ − _' 'num num' 10 2)
		(array 'r' '*'					'_ × _' 'num num' 10 2)
		(array 'r' '/'					'_ / _' 'num num' 10 2)
		(array 'r' '%'					'_ mod _' 'num num' 10 2)
		'-'
		(array 'r' 'absoluteValue'		'abs _ ' 'num' -10)
		(array 'r' 'minimum'			'min _ _ : _ : ...' 'num num num' 1 2)
		(array 'r' 'maximum'			'max _ _ : _ : ...' 'num num num' 1 2)
		(array 'r' 'random'				'random _ to _' 'num num' 1 10)
		'-'
		(array 'r' '<'					'_ < _' 'num num' 3 4)
		(array 'r' '<='					'_ <= _' 'num num' 3 4)
		(array 'r' '=='					'_ = _' 'auto auto' 3 4)
		(array 'r' '!='					'_ ≠ _' 'auto auto' 3 4)
		(array 'r' '>='					'_ >= _' 'num num' 3 4)
		(array 'r' '>'					'_ > _' 'num num' 3 4)
		'-'
		(array 'r' 'booleanConstant'	'_' 'bool' true)
		(array 'r' 'not'				'not _' 'bool' true)
		(array 'r' 'and'				'_ and _' 'bool bool' true false)
		(array 'r' 'or'					'_ or _ ' 'bool bool' true false)
		'-'
		(array 'r' 'isType'				'_ is a _' 'auto menu.typesMenu' 123 'number')
		(array 'r' '[data:convertType]'	'convert _ to _' 'auto menu.typesMenu' 123 'number')
	'Operators-Advanced'
		(array 'r' 'ifExpression'		'if _ then _ else _' 'bool auto auto' true 1 0)
		'-'
		(array 'r' '[misc:rescale]'		'rescale _ from ( _ , _ ) to ( _ , _ )' 'num num num num num' 3 0 10 0 100)
		(array 'r' '[misc:sqrt]'		'sqrt _' 'num' 9)
		(array 'r' 'hexToInt'			'hex _' 'str' '3F')
		'-'
		(array 'r' '&'					'_ & _' 'num num' 1 3)
		(array 'r' '|'					'_ | _' 'num num' 1 2)
		(array 'r' '^'					'_ ^ _' 'num num' 1 3)
		(array 'r' '~'					'~ _' 'num' 1 3)
		(array 'r' '<<'					'_ << _' 'num num' 3 2)
		(array 'r' '>>'					'_ >> _' 'num num' -100 2)
	'Variables'
		(array 'r' 'v'					'_' 'menu.allVarsMenu' 'n')
		(array ' ' '='					'set _ to _' 'menu.allVarsMenu auto' 'n' 0)
		(array ' ' '+='					'change _ by _' 'menu.allVarsMenu num' 'n' 1)
		(array ' ' 'local'				'initialize local _ to _' 'var auto' 'var' 0)
	'Data'
		(array 'r' 'at'					'item _ of _' 'auto.itemOfMenu str' 1 'Rosa')
		(array 'r' 'size'				'length of _' 'str' 'Rosa')
		(array 'r' '[data:join]'		'join _ _ : _ : ...' 'str str str' 'micro' 'blocks')
		'-'
		(array 'r' '[data:makeList]'	'list : _ : ...' 'auto auto auto' 'cat' 'dog' 'bird')
		(array ' ' '[data:addLast]'		'add _ to list _' 'auto auto' 'fish')
		'-'
		(array ' ' 'atPut'				'replace item _ of list _ with _' 'auto.replaceItemMenu str auto' 1 nil 10)
		(array ' ' '[data:delete]'		'delete item _ of list _' 'auto.replaceItemMenu str' 1)
		'-'
		(array 'r' '[data:find]'		'find _ in _ : starting at _' 'auto str num' 'a' 'cat' 1)
		(array 'r' '[data:copyFromTo]'	'copy _ from _ : to _' 'str num num' 'smiles' 2 5)
		'-'
		(array 'r' '[data:split]'		'split _ by _' 'str str' 'A,B,C' ',')
		(array 'r' '[data:joinStrings]'	'join items of list _ : separator _' 'auto str' 'a list of strings' ' ')
	'Data-Advanced'
		(array 'r' 'newList'				'new list length _ : with all _' 'num auto' 10 0)
		(array 'r' '[data:newByteArray]'	'new byte array _ : with all _' 'num num' 5 0)
		'-'
		(array 'r' '[data:unicodeAt]'		'unicode _ of _' 'num str' 2 'cat')
		(array 'r' '[data:unicodeString]'	'string from unicode _' 'num' 65)
		'-'
		(array 'r' '[data:asByteArray]'		'as byte array _' 'auto' 'aByteListOrString')
		'-'
		(array 'r' '[data:freeMemory]'		'free memory')

	// The following block specs allow primitives to be rendered correctly
	// even if the primitive spec was not included in the project or library.
	// This allows MicroBlocks to correctly render scripts in older projects.

	'Prims-Deprecated (not in palette)'
		(array 'r' 'newArray'				'new list length _' 'num' 10)
		(array ' ' 'fillArray'				'fill list _ with _' 'str auto' nil 0)
		(array ' ' 'fillList'				'fill list _ with _' 'str auto' nil 0)
	'Prims-Display (not in palette)'
		(array ' ' '[display:mbDisplay]'	'display _' 'microbitDisplay')
		(array ' ' '[display:mbDisplayOff]'	'clear display')
		(array ' ' '[display:mbPlot]'		'plot x _ y _' 'num num' 3 3)
		(array ' ' '[display:mbUnplot]'		'unplot x _ y _' 'num num' 3 3)
		(array ' ' '[display:mbDrawShape]'		'draw shape _ at x _ y _' 'num num num' 31 1 1)
		(array 'r' '[display:mbShapeForLetter]'	'shape for letter _' 'str' 'A')
		(array ' ' '[display:mbEnableDisplay]'	'enable LED display _' 'bool' false)
		(array ' ' '[display:neoPixelSetPin]'	'set NeoPixel pin _ is RGBW _' 'auto bool' '' false)
		(array ' ' '[display:neoPixelSend]'		'send NeoPixel rgb _' 'num' 5)
	'Prims-Sensing (not in palette)'
		(array 'r' '[sensors:acceleration]'	'acceleration')
		(array 'r' '[display:lightLevel]'	'light level')
		(array 'r' '[sensors:temperature]'	'temperature (°C)')
		(array 'r' '[sensors:tiltX]'		'tilt x')
		(array 'r' '[sensors:tiltY]'		'tilt y')
		(array 'r' '[sensors:tiltZ]'		'tilt z')
		(array 'r' '[sensors:microphone]'	'microphone')
		(array ' ' '[sensors:i2cSetClockSpeed]'	'set i2c clock speed _' 'num' 400000)
		(array ' ' '[sensors:i2cSetPins]'	'set i2c pins SDA _ SCL _' 'num num' 4 5)
	'Prims-Variables (not in palette)'
		(array 'r' '[vars:varExists]'	'variable named _ exists?' 'str' 'var')
		(array 'r' '[vars:varNamed]'	'value of variable named _' 'str' 'var')
		(array ' ' '[vars:setVarNamed]'	'set variable named _ to _' 'str auto' 'var' 0)
	'Prims-JSON (not in palette)'
		(array 'r' '[misc:jsonGet]'		'json _ . _' 'str str' '{ "x": 1, "y": [41, 42, 43] }' 'y.2')
		(array 'r' '[misc:jsonCount]'	'json count _ . _' 'str str' '[1, [4, 5, 6, 7], 3]' '')
		(array 'r' '[misc:jsonValueAt]'	'json value _ . _ at _' 'str str num' '{ "x": 1, "y": 42 }' '' 2)
		(array 'r' '[misc:jsonKeyAt]'	'json key _ . _ at _' 'str str num' '{ "x": 1, "y": 42 }' '' 2)
	'Prims-Binary Data (not in palette)'
		(array 'r' '[misc:byteCount]'	'byte count _' 'str' 'binary data')
		(array 'r' '[misc:byteAt]'		'byte _ of _' 'num str' 1 'binary data')
	'Prims-Advanced (not in palette)'
		(array ' ' 'noop'				'no op')
		(array ' ' 'ignoreArgs'			'ignore : _ : ...' 'auto' 0)
		(array 'r' 'pushArgCount'		'arg count')
		(array 'r' 'getArg'				'arg _' 'num' 0)
		(array 'r' 'longMult'			'( _ * _ ) >> _' 'num num num' 1024 2048 10)
		(array 'r' '[misc:sin]'			'fixed sine _' 'num' 9000)

		(array 'r' '[sensors:touchRead]' 'capacitive sensor _' 'num' 1)
		(array 'r' '[sensors:readDHT]'	'read DHT data pin _' 'num' 1)

		(array 'r' '[io:hasTone]'		'has tone support')
		(array ' ' '[io:playTone]'		'play tone pin _ frequency _' 'num num' 0 440)
		(array ' ' '[io:dacInit]'		'init DAC pin _ sample rate _' 'num num' 25 11025)
		(array 'r' '[io:dacWrite]'		'DAC write _ : starting at _' 'num num' 128 1)

		(array 'r' '[io:hasServo]'		'has servo support')
		(array ' ' '[io:setServo]'		'set servo pin _ to _ usecs' 'num num' 0 1500)

		(array 'r' '[net:hasWiFi]'		'has WiFi support')
		(array ' ' '[net:startWiFi]'	'start WiFi _ password _ : be hotspot _ : IP _ gateway _ subnet _' 'auto auto bool auto auto auto' 'SSID' 'MyPassword' true '192.168.1.42' '192.168.1.1' '255.255.255.0')
		(array ' ' '[net:stopWiFi]'		'stop WiFi')
		(array 'r' '[net:wifiStatus]'	'WiFi status')
		(array 'r' '[net:myIPAddress]'	'my IP address')
		(array 'r' '[net:myMAC]'		'my MAC address')

		(array 'r' '[net:startSSIDscan]'		'scan SSID list')
		(array 'r' '[net:getSSID]'				'get SSID number _' 'num' 1)

		(array ' ' '[net:httpConnect]'			'connect to http܃// _ : port _' 'auto num' 'microblocks.fun' 80)
		(array 'r' '[net:httpIsConnected]'		'is HTTP connected?')
		(array ' ' '[net:httpRequest]'			'_ request http܃// _ / _ : body _' 'menu.requestTypes auto auto str' 'GET' 'microblocks.fun' 'example.txt' '')
		(array 'r' '[net:httpResponse]'			'HTTP response')
		(array ' ' '[net:httpClose]'			'close HTTP connection')
		(array ' ' '[net:startHttpServer]'		'start HTTP server')
		(array ' ' '[net:stopHttpServer]'		'stop HTTP server')
		(array 'r' '[net:httpServerGetRequest]'	'HTTP server request : binary data _ : port _' 'bool num' false 8080)
		(array ' ' '[net:respondToHttpRequest]'	'respond _ to HTTP server request : with body _ : and headers _' 'auto str str' '200 OK' 'Welcome to the MicroBlocks HTTP server' 'Content-Type: text/plain')

		(array ' ' '[net:udpStart]'				'UDP start port _' 'auto' 5000)
		(array ' ' '[net:udpStop]'				'UDP stop')
		(array ' ' '[net:udpSendPacket]'		'UDP send packet _ to ip _ port _' 'auto auto num' 'Hello!' '255.255.255.255' 5000)
		(array 'r' '[net:udpReceivePacket]'		'UDP receive packet : binary data _' 'bool' false)
		(array 'r' '[net:udpRemoteIPAddress]'	'UDP remote IP address')
		(array 'r' '[net:udpRemotePort]'		'UDP remote port')

		(array ' ' '[tft:setBacklight]'		'set TFT backlight _ (0-10)' 'num' 10)
		(array ' ' '[tft:getWidth]'			'TFT width')
		(array ' ' '[tft:getHeight]'		'TFT height')
		(array ' ' '[tft:setPixel]'			'set TFT pixel x _ y _ to _' 'num num num' 50 32 16711680)
		(array ' ' '[tft:line]'				'draw line on TFT from x _ y _ to x _ y _ color _' 'num num num num num' 12 8 25 15 255)
		(array ' ' '[tft:rect]'				'draw rectangle on TFT at x _ y _ width _ height _ color _ : filled _' 'num num num num num bool' 10 10 40 30 65280 false)
		(array ' ' '[tft:roundedRect]'		'draw rounded rectangle on TFT at x _ y _ width _ height _ radius _ color _ : filled _' 'num num num num num num bool' 10 10 40 30 8 12255317 false)
		(array ' ' '[tft:circle]'			'draw circle on TFT at x _ y _ radius _ color _ : filled _' 'num num num num bool' 60 100 30 65535 false)
		(array ' ' '[tft:triangle]'			'draw triangle on TFT at x _ y _ , x _ y _ , x _ y _ color _ : filled _' 'num num num num num num num bool' 20 20 30 80 60 5 5592354 false)
		(array ' ' '[tft:text]'				'write _ on TFT at x _ y _ color _ : scale _ wrap _ : bg color _' 'str num num color num bool color' 'Hello World!' 0 80 16777215 1 false 16777215)
		(array ' ' '[tft:drawBitmap]'		'draw bitmap _ palette _ on TFT at x _ y _' 'str str num num' 'aBitmap' 'a list of colors' 10 10)
		(array ' ' '[tft:deferUpdates]'		'defer TFT display updates')
		(array ' ' '[tft:resumeUpdates]'	'resume TFT display updates')

		(array ' ' '[tft:mergeBitmap]'		'mergeBitmap _ width _ buffer _ scale _ alphaIndex _ destX _ destY _' 'auto num auto num num num num')
		(array ' ' '[tft:drawBuffer]'		'drawBuffer _ palette _ scale _ : srcX _ srcY _ copyWidth _ copyHeight _' 'auto auto num num num num num')

		(array 'r' '[tft:tftTouched]'		'TFT touched')
		(array 'r' '[tft:tftTouchX]'		'TFT touch X position')
		(array 'r' '[tft:tftTouchY]'		'TFT touch Y position')
		(array 'r' '[tft:tftTouchPressure]'	'TFT touch pressure')

		(array ' ' '[file:open]'			'open file _' 'str')
		(array ' ' '[file:close]'			'close file _' 'str')
		(array ' ' '[file:delete]'			'delete file _' 'str')
		(array 'r' '[file:endOfFile]'		'end of file _' 'str')
		(array 'r' '[file:readLine]'		'next line of file _' 'str')
		(array 'r' '[file:readBytes]'		'next _ bytes of file _ : starting at _' 'num str num' 100 '' 0)
		(array 'r' '[file:readInto]'		'read into _ from file _' 'str str' 'a ByteArray' '')
		(array 'r' '[file:readPosition]'	'read position of file _' 'str')
		(array ' ' '[file:setReadPosition]'	'set read position _ of file _' 'num str')
		(array ' ' '[file:appendLine]'		'append line _ to file _' 'str str')
		(array ' ' '[file:appendBytes]'		'append bytes _ to file _' 'str str')
		(array 'r' '[file:fileSize]'		'size of file _' 'str')
		(array ' ' '[file:startList]'		'start file list _' 'str' 'dir')
		(array 'r' '[file:nextInList]'		'next file in list')
		(array 'r' '[file:systemInfo]'		'file system info')

		(array ' ' '[radio:sendInteger]'			'radio send number _' 'num' 123)
		(array ' ' '[radio:sendString]'				'radio send string _' 'str' 'Hello!')
		(array ' ' '[radio:sendPair]'				'radio send pair _ = _' 'str num' 'light' 10)
		(array 'r' '[radio:messageReceived]'		'radio message received?')
		(array 'r' '[radio:receivedInteger]'		'radio last number')
		(array 'r' '[radio:receivedString]'			'radio last string')
		(array 'r' '[radio:receivedMessageType]'	'radio last message type')
		(array ' ' '[radio:setGroup]'				'radio set group _' 'num' 0)
		(array ' ' '[radio:setChannel]'				'radio set channel (0-83) _' 'num' 7)
		(array ' ' '[radio:setPower]'				'radio set power (0-7) _' 'num' 4)
		(array 'r' '[radio:signalStrength]'			'radio last signal strength')
		(array 'r' '[radio:packetReceive]'			'radio receive packet _' 'str' '32-element list')
		(array ' ' '[radio:packetSend]'				'radio send packet _' 'str' '32-element list')
		(array ' ' '[radio:disableRadio]'			'disable radio')

		(array ' ' '[1wire:init]'			'oneWire init pin _' 'num' 0)
		(array ' ' '[1wire:scanStart]'		'oneWire scan start')
		(array 'r' '[1wire:scanNext]'		'oneWire scan next _' 'str' 'addressByteArray')
		(array ' ' '[1wire:select]'			'oneWire select address _' 'str' 'addressByteArray')
		(array ' ' '[1wire:selectAll]'		'oneWire select all')
		(array ' ' '[1wire:writeByte]'		'oneWire write byte _ : power _' 'num bool' 0 false)
		(array 'r' '[1wire:readByte]'		'oneWire read byte')
		(array 'r' '[1wire:crc8]'			'oneWire crc8 _ : byte count _' 'str num' 'aByteArray' 8)
		(array 'r' '[1wire:crc16]'			'oneWire crc16 _ : byte count _' 'str num' 'aByteArray' 8)

		(array ' ' '[ble:uartStart]' 'start BLE serial')
		(array ' ' '[ble:uartStop]' 'stop BLE serial')
		(array 'r' '[ble:uartConnected]' 'BLE serial connected?')
		(array 'r' '[ble:uartRead]' '_BLE serial read as bytes _' 'bool' false)
		(array ' ' '[ble:uartWrite]' '_BLE serial write _ (max 240) starting at _' 'str num' 'aStringOrByteArray' 1)
	)
}

method initMicroBlocksSpecs SmallCompiler {
	authoringSpecs = (authoringSpecs)
	if (isEmpty (specsFor authoringSpecs 'Output')) {
		clear authoringSpecs
		addSpecs authoringSpecs (microBlocksSpecs this)
	}
}

method opcodes SmallCompiler { return opcodes }

method initOpcodes SmallCompiler {
	// Initialize the opcode dictionary. Note: This must match the opcode table in interp.c!

	opcodeDefinitions = '
		halt 0
		noop 1
		pushImmediate 2		// true, false, and ints that fit in 24 bits
		pushBigImmediate 3	// ints that do not fit in 24 bits
		pushLiteral 4		// string or array constant from literals frame
		pushVar 5
		storeVar 6
		incrementVar 7
		pushArgCount 8
		pushArg 9
		storeArg 10
		incrementArg 11
		pushLocal 12
		storeLocal 13
		incrementLocal 14
		pop 15
		jmp 16
		jmpTrue 17
		jmpFalse 18
		decrementAndJmp 19
		callFunction 20
		returnResult 21
		waitMicros 22
		waitMillis 23
		sendBroadcast 24
		recvBroadcast 25
		stopAll 26
		forLoop 27
		initLocals 28
		getArg 29
		getLastBroadcast 30
		jmpOr 31
		jmpAnd 32
		minimum 33
		maximum 34
		< 35
		<= 36
		== 37
		!= 38
		>= 39
		> 40
		not 41
		+ 42
		- 43
		* 44
		/ 45
		% 46
		absoluteValue 47
		random 48
		hexToInt 49
		& 50
		| 51
		^ 52
		~ 53
		<< 54
		>> 55
		longMult 56
		isType 57
		waitUntil 58
		ignoreArgs 59
		newList 60
	RESERVED 61
		fillList 62
		at 63
		atPut 64
		size 65
	RESERVED 66
	RESERVED 67
	RESERVED 68
	RESERVED 69
		millisOp 70
		microsOp 71
		timer 72
		resetTimer 73
		sayIt 74
		printIt 75
		boardType 76
		comment 77
		argOrDefault 78
	RESERVED 79
		analogPins 80
		digitalPins 81
		analogReadOp 82
		analogWriteOp 83
		digitalReadOp 84
		digitalWriteOp 85
		digitalSet 86
		digitalClear 87
		buttonA 88
		buttonB 89
		setUserLED 90
		i2cSet 91
		i2cGet 92
		spiSend 93
		spiRecv 94
	RESERVED 95
	RESERVED 96
		secsOp 97
		millisSince 98
		microsSince 99
	RESERVED 100
	RESERVED 101
	RESERVED 102
	RESERVED 103
	RESERVED 104
	RESERVED 105
	RESERVED 106
	RESERVED 107
	RESERVED 108
	RESERVED 109
	RESERVED 110
	RESERVED 111
	RESERVED 112
	RESERVED 113
	RESERVED 114
	RESERVED 115
	RESERVED 116
	RESERVED 117
	RESERVED 118
	RESERVED 119
	RESERVED 120
	RESERVED 121
		commandPrimitive 122
		reporterPrimitive 123
		callCustomCommand 124
		callCustomReporter 125
		callCommandPrimitive 126
		callReporterPrimitive 127
		metadata 240'
	opcodes = (dictionary)
	for line (lines opcodeDefinitions) {
		words = (words line)
		if (and ((count words) > 1) ('RESERVED' != (first words))) {
			atPut opcodes (at words 1) (toInteger (at words 2))
		}
	}

	// renamed opcodes:
	atPut opcodes 'newArray' 60
	atPut opcodes 'fillArray' 62
}

method initPrimsets SmallCompiler {
	// Initialize the primitive set table, which maps a primitive set name to its index.
	// NOTE: The primitive set order must match PrimitiveSetIndex enum in interp.c!

	primSetNames = '
		vars
		data
		misc
		io
		sensors
		serial
		display
		file
		net
		ble
		radio
		tft
		hid
		camera
		1wire'

	primsets = (dictionary)
	primSetIndex = 0
	for primSetName (copyFromTo (lines primSetNames) 2) {
		primSetName = (trim primSetName)
		atPut primsets primSetName primSetIndex
		primSetIndex += 1
	}
}

// instruction generation: entry point

method instructionsFor SmallCompiler aBlockOrFunction {
	// Return a list of instructions for the given block, script, or function.
	// Add a 'halt' if needed and append any literals (e.g. strings) used.

	if (and (isClass aBlockOrFunction 'Block') (isPrototypeHat aBlockOrFunction)) {
		// function definition hat: get its function
		aBlockOrFunction = (function (editedPrototype aBlockOrFunction))
	}

	argNames = (dictionary)
	if (isClass aBlockOrFunction 'Function') {
		func = aBlockOrFunction
		for a (argNames func) {
			atPut argNames a (count argNames)
		}
		cmdOrReporter = (cmdList func)
		if (isNil cmdOrReporter) { // a function hat without any blocks
			cmdOrReporter = (newCommand 'noop')
		}
	} (or (isClass aBlockOrFunction 'Command') (isClass aBlockOrFunction 'Reporter')) {
		cmdOrReporter = aBlockOrFunction
	} else {
		cmdOrReporter = (expression aBlockOrFunction)
	}

	assignFunctionIDs (smallRuntime)
	collectVars this cmdOrReporter

	result = (list (array 'initLocals' (count localVars)))
	if (isClass cmdOrReporter 'Command') {
		op = (primName cmdOrReporter)
		if ('whenCondition' == op) {
			addAll result (instructionsForWhenCondition this cmdOrReporter)
		} ('whenButtonPressed' == op) {
			addAll result (instructionsForCmdList this (nextBlock cmdOrReporter))
			add result (array 'halt' 0)
		} ('whenStarted' == op) {
			addAll result (instructionsForCmdList this (nextBlock cmdOrReporter))
			add result (array 'halt' 0)
		} ('whenBroadcastReceived' == op) {
			addAll result (instructionsForExpression this (first (argList cmdOrReporter)))
			add result (array 'recvBroadcast' 1)
			addAll result (instructionsForCmdList this (nextBlock cmdOrReporter))
			add result (array 'halt' 0)
		} (isClass aBlockOrFunction 'Function') {
			if (or ('noop' != (primName cmdOrReporter)) (notNil (nextBlock cmdOrReporter))) {
				if (isEmpty (argNames func)) {
					add result (array 'pushLiteral' (functionName func))
					add result (array 'recvBroadcast' 1)
				}
				addAll result (instructionsForCmdList this cmdOrReporter)
			}
			add result (array 'pushImmediate' falseObj)
			add result (array 'returnResult' 0)
		} else {
			addAll result (instructionsForCmdList this cmdOrReporter)
			add result (array 'halt' 0)
		}
	} else {
		addAll result (instructionsForCmdList this (newReporter 'return' cmdOrReporter))
	}
	if (and
		((count result) == 2)
		(isOneOf (first (first result)) 'halt' 'stopAll')) {
			// In general, just looking at the final instructon isn't enough because
			// it could just be the end of a conditional body that is jumped
			// over; in that case, we need the final halt as the jump target.
			removeLast result // remove the final halt
	}
	appendLiterals this result
	appendDecompilerMetadata this aBlockOrFunction result
	return result
}

// instruction generation: when hat block

method instructionsForWhenCondition SmallCompiler cmdOrReporter {
	condition = (instructionsForExpression this (first (argList cmdOrReporter)))
	body = (instructionsForCmdList this (nextBlock cmdOrReporter))
	result = (list)

	// wait until condition becomes true
	addAll result (instructionsForExpression this 10)
	add result (array 'waitMillis' 1)
	addAll result condition
	add result (array 'jmpFalse' (0 - ((count condition) + 3)))

	addAll result body

	// loop back to condition test
	add result (array 'jmp' (0 - ((count result) + 1)))
	return result
}

// instruction generation: command lists and control structures

method instructionsForCmdList SmallCompiler cmdList {
	result = (list)
	cmd = cmdList
	while (notNil cmd) {
		addAll result (instructionsForCmd this cmd)
		cmd = (nextBlock cmd)
	}
	return result
}

method instructionsForCmd SmallCompiler cmd {
	result = (list)
	op = (primName cmd)
	args = (argList cmd)
	if (isOneOf op '=' 'local') {
		addAll result (instructionsForExpression this (at args 2))
		add result (setVar this (first args))
	} ('+=' == op) {
		addAll result (instructionsForExpression this (at args 2))
		add result (incrementVar this (first args))
	} ('return' == op) {
		if (0 == (count args)) {
			add result (array 'pushImmediate' zeroObj)
		} else {
			addAll result (instructionsForExpression this (at args 1))
		}
		add result (array 'returnResult' 0)
	} ('stopTask' == op) {
		add result (array 'halt' 0)
	} ('forever' == op) {
		return (instructionsForForever this args)
	} ('if' == op) {
		return (instructionsForIf this args)
	} ('repeat' == op) {
		return (instructionsForRepeat this args)
	} ('repeatUntil' == op) {
		return (instructionsForRepeatUntil this args)
	} ('waitUntil' == op) {
		return (instructionsForWaitUntil this args)
	} ('for' == op) {
		return (instructionsForForLoop this args)
	} (and ('digitalWriteOp' == op) (isClass (first args) 'Integer') (isClass (last args) 'Boolean')) {
		pinNum = ((first args) & 255)
		if (true == (last args)) {
			add result (array 'digitalSet' pinNum)
		} else {
			add result (array 'digitalClear' pinNum)
		}
		return result
	} ('sendBroadcastSimple' == op) {
		return (primitive this 'sendBroadcast' args true)
	} ('comment' == op) {
		// skip comments; do not generate any code
		// xxx remove this case later to store comments (once the VM supports them)
	} ('ignoreArgs' == op) {
		for arg args {
			addAll result (instructionsForExpression this arg)
		}
		add result (array 'ignoreArgs' (count args))
		return result
	} (isOneOf op 'callCustomCommand' 'callCustomReporter') {
		for arg args {
			addAll result (instructionsForExpression this arg)
		}
		add result (array op (count args))
		if ('callCustomCommand' == op) {
			add result (array 'pop' 1) // discard the return value
		}
		return result
	} (isFunctionCall this op) {
		return (instructionsForFunctionCall this op args true)
	} else {
		return (primitive this op args true)
	}
	return result
}

method instructionsForIf SmallCompiler args {
	result = (list)
	jumpsToFix = (list)
	i = 1
	while (i < (count args)) {
		finalCase = ((i + 2) >= (count args)) // true if this is the final case in the if statement
		test = (at args i)
		body = (instructionsForCmdList this (at args (i + 1)))
		if (or (true != test) (not finalCase) (i == 1)) {
			addAll result (instructionsForExpression this test)
			offset = (count body)
			if (not finalCase) { offset += 1 }
			add result (array 'jmpFalse' offset)
		}
		addAll result body
		if (not finalCase) {
			jumpToEnd = (array 'jmp' (count result)) // jump offset to be fixed later
			add jumpsToFix jumpToEnd
			add result jumpToEnd
		}
		i += 2
	}
	instructionCount = (count result)
	for jumpInstruction jumpsToFix {
		atPut jumpInstruction 2 (instructionCount - ((at jumpInstruction 2) + 1)) // fix jump offset
	}
	return result
}

method instructionsForForever SmallCompiler args {
	result = (instructionsForCmdList this (at args 1))
	add result (array 'jmp' (0 - ((count result) + 1)))
	return result
}

method instructionsForRepeat SmallCompiler args {
	result = (instructionsForExpression this (at args 1)) // loop count
	body = (instructionsForCmdList this (at args 2))
	add result (array 'jmp' (count body))
	addAll result body
	add result (array 'decrementAndJmp' (0 - ((count body) + 1)))
	return result
}

method instructionsForRepeatUntil SmallCompiler args {
	result = (list)
	conditionTest = (instructionsForExpression this (at args 1))
	body = (instructionsForCmdList this (at args 2))
	add result (array 'jmp' (count body))
	addAll result body
	addAll result conditionTest
	add result (array 'jmpFalse' (0 - (+ (count body) (count conditionTest) 1)))
	return result
}

method instructionsForWaitUntil SmallCompiler args {
	result = (list)
	conditionTest = (instructionsForExpression this (at args 1))
	addAll result conditionTest
	add result (array 'waitUntil' (0 - (+ (count conditionTest) 1)))
	return result
}

method instructionsForForLoop SmallCompiler args {
	result = (instructionsForExpression this (at args 2))
	loopVarIndex = (at localVars (first args))
	body = (instructionsForCmdList this (at args 3))
	addAll result (array
		(array 'pushImmediate' falseObj) // this will be N, the total loop count
		(array 'pushImmediate' falseObj) // this will be a decrementing loop counter
		(array 'jmp' (count body)))
	addAll result body
	addAll result (array
		(array 'forLoop' loopVarIndex)
		(array 'jmp' (0 - ((count body) + 2)))
		(array 'pop' 3))
	return result
}

// instruction generation: expressions

method instructionsForExpression SmallCompiler expr {
	// immediate values
	if (true == expr) {
		return (list (array 'pushImmediate' trueObj))
	} (false == expr) {
		return (list (array 'pushImmediate' falseObj))
	} (isNil expr) {
		return (list (array 'pushImmediate' zeroObj))
	} (isClass expr 'Integer') {
		if (and (-4194304 <= expr) (expr <= 4194303)) { // 23-bit encoded as 24 bit int object
			return (list (array 'pushImmediate' (((expr << 1) | 1) & (hex 'FFFFFF')) ))
		} else {
			// pushBigImmediate instruction followed by a 4-byte integer object
			return (list (array 'pushBigImmediate' 0) expr)
		}
	} (isClass expr 'String') {
		return (list (array 'pushLiteral' expr))
	} (isClass expr 'Float') {
		error 'Floats are not supported'
	} (isClass expr 'Color') {
		return (instructionsForExpression this (pixelRGB expr))
	}

	// expressions
	op = (primName expr)
	args = (argList expr)
	if ('v' == op) { // variable
		return (list (getVar this (first args)))
	} ('booleanConstant' == op) {
		if (first args) {
			return (list (array 'pushImmediate' trueObj))
		} else {
			return (list (array 'pushImmediate' falseObj))
		}
	} ('colorSwatch' == op) {
		c = (color (at args 1) (at args 2) (at args 3))
		return (instructionsForExpression this (pixelRGB c))
	} ('and' == op) {
		return (instructionsForAnd this args)
	} ('or' == op) {
		return (instructionsForOr this args)
	} ('ifExpression' == op) {
		return (instructionsForIfExpression this args)
	} (isFunctionCall this op) {
		return (instructionsForFunctionCall this op args false)
	} else {
		return (primitive this op args false)
	}
}

method instructionsForAnd SmallCompiler args {
	tests = (list)
	totalInstrCount = 0
	for expr args {
		instrList = (instructionsForExpression this expr)
		add tests instrList
		totalInstrCount += ((count instrList) + 1)
	}
	totalInstrCount += -1 // no jump required after final arg

	result = (list)
	for i (count tests) {
		addAll result (at tests i)
		if (i < (count tests)) {
			add result (array 'jmpAnd' (totalInstrCount - ((count result) + 1)))
		}
	}
	return result
}

method instructionsForOr SmallCompiler args {
	tests = (list)
	totalInstrCount = 0
	for expr args {
		instrList = (instructionsForExpression this expr)
		add tests instrList
		totalInstrCount += ((count instrList) + 1)
	}
	totalInstrCount += -1 // no jump required after final arg

	result = (list)
	for i (count tests) {
		addAll result (at tests i)
		if (i < (count tests)) {
			add result (array 'jmpOr' (totalInstrCount - ((count result) + 1)))
		}
	}
	return result
}

method instructionsForAndOLD SmallCompiler args { // xxx remove later
	tests = (list)
	totalInstrCount = 3 // final three instructions
	for expr args {
		instrList = (instructionsForExpression this expr)
		add tests instrList
		totalInstrCount += ((count instrList) + 1)
	}
	result = (list)
	for t tests {
		addAll result t
		add result (array 'jmpFalse' (totalInstrCount - ((count result) + 2)))
	}
	add result (array 'pushImmediate' trueObj) // all conditions were true: push result
	add result (array 'jmp' 1) // skip over false case
	add result (array 'pushImmediate' falseObj) // some condition was false: push result
	return result
}

method instructionsForOrOLD SmallCompiler args { // xxx remove later
	tests = (list)
	totalInstrCount = 3 // final three instructions
	for expr args {
		instrList = (instructionsForExpression this expr)
		add tests instrList
		totalInstrCount += ((count instrList) + 1)
	}
	result = (list)
	for t tests {
		addAll result t
		add result (array 'jmpTrue' (totalInstrCount - ((count result) + 2)))
	}
	add result (array 'pushImmediate' falseObj) // all conditions were false: push result
	add result (array 'jmp' 1) // skip over true case
	add result (array 'pushImmediate' trueObj) // some condition was true: push result
	return result
}

method instructionsForIfExpression SmallCompiler args {
	trueCase = (instructionsForExpression this (at args 2))
	falseCase = (instructionsForExpression this (at args 3))
	add falseCase (array 'jmp' (count trueCase))

	result = (instructionsForExpression this (first args)) // test
	add result (array 'jmpTrue' (count falseCase))
	addAll result falseCase
	addAll result trueCase
	return result
}

// instruction generation utility methods

method primitive SmallCompiler op args isCommand {
	result = (list)
	if ('print' == op) { op = 'printIt' }
	if (contains opcodes op) {
		for arg args {
			addAll result (instructionsForExpression this arg)
		}
		add result (array op (count args))
	} (and (beginsWith op '[') (endsWith op ']')) {
		// named primitives of the form '[primSetName:primName]'
		i = (findFirst op ':')
		if (notNil i) {
			primSetName = (substring op 2 (i - 1))
			primName = (substring op (i + 1) ((count op) - 1))
			add result (array 'pushLiteral' primSetName)
			add result (array 'pushLiteral' primName)
			for arg args {
				addAll result (instructionsForExpression this arg)
			}
			if isCommand {
				add result (array 'callCommandPrimitive' ((count args) + 2))
			} else {
				add result (array 'callReporterPrimitive' ((count args) + 2))
			}
		}
	} else {
		print 'Skipping unknown op:' op
		if (not isCommand) {
			add result (array 'pushImmediate' zeroObj) // missing reporter; push dummy result
		}
	}
	return result
}

method primitiveNEW SmallCompiler op args isCommand {
	result = (list)
	if ('print' == op) { op = 'printIt' }
	if (contains opcodes op) {
		for arg args {
			addAll result (instructionsForExpression this arg)
		}
		add result (array op (count args))
	} (and (beginsWith op '[') (endsWith op ']')) {
		// named primitives of the form '[primSetName:primName]'
		i = (findFirst op ':')
		if (notNil i) {
			primSetName = (substring op 2 (i - 1))
			primName = (substring op (i + 1) ((count op) - 1))
			for arg args {
				addAll result (instructionsForExpression this arg)
			}
			if isCommand {
				add result (array 'commandPrimitive' primName primSetName (count args))
			} else {
				add result (array 'reporterPrimitive' primName primSetName (count args))
			}
		}
	} else {
		print 'Skipping unknown op:' op
		if (not isCommand) {
			add result (array 'pushImmediate' zeroObj) // missing reporter; push dummy result
		}
	}
	return result
}

// Variables

method collectVars SmallCompiler cmdOrReporter {
	sharedVars = (allVariableNames (project (scripter (smallRuntime))))

	localVars = (dictionary)
	todo = (list cmdOrReporter)
	while ((count todo) > 0) {
		cmd = (removeFirst todo)
		if (isOneOf (primName cmd) 'local' 'for') {
			// explicit local variables and 'for' loop indexes are always local
			varName = (first (argList cmd))
			if (contains argNames varName) {
				print 'Warning: Local variable overrides parameter:' varName
			}
			if (not (contains localVars varName)) {
				atPut localVars varName (count localVars)
			}
		} (isOneOf (primName cmd) 'v' '=' '+=') {
			// undeclared variables that are not global (shared) are treated as local
			varName = (first (argList cmd))
			if (not (or
				(contains sharedVars varName)
				(contains argNames varName)
				(contains localVars varName))) {
					atPut localVars varName (count localVars)
			}
		}
		for arg (argList cmd) {
			if (isAnyClass arg 'Command' 'Reporter') {
				add todo arg
			}
		}
		if (notNil (nextBlock cmd)) { add todo (nextBlock cmd) }
	}
}

method getVar SmallCompiler varName {
	if (notNil (at localVars varName)) {
		return (array 'pushLocal' (at localVars varName))
	} (notNil (at argNames varName)) {
		return (array 'pushArg' (at argNames varName))
	}
	globalID = (globalVarIndex this varName)
	if (notNil globalID) { return (array 'pushVar' globalID) }
}

method setVar SmallCompiler varName {
	if (notNil (at localVars varName)) {
		return (array 'storeLocal' (at localVars varName))
	} (notNil (at argNames varName)) {
		return (array 'storeArg' (at argNames varName))
	}
	globalID = (globalVarIndex this varName)
	if (notNil globalID) { return (array 'storeVar' globalID) }
}

method incrementVar SmallCompiler varName {
	if (notNil (at localVars varName)) {
		return (array 'incrementLocal' (at localVars varName))
	} (notNil (at argNames varName)) {
		return (array 'incrementArg' (at argNames varName))
	}
	globalID = (globalVarIndex this varName)
	if (notNil globalID) { return (array 'incrementVar' globalID) }
}

method globalVarIndex SmallCompiler varName {
	varNames = (allVariableNames (project (scripter (smallRuntime))))
	id = (indexOf varNames varName)
	if (isNil id) {
		error 'Unknown variable' varName
	}
	if (id >= 100) { error 'Id' id 'for variable' varName 'is out of range' }
	return (id - 1) // VM uses zero-based index
}

// function calls

method isFunctionCall SmallCompiler op {
	return (notNil (lookupChunkID (smallRuntime) op))
}

method instructionsForFunctionCall SmallCompiler op args isCmd {
	result = (list)
	callee = (lookupChunkID (smallRuntime) op)
	for arg args {
		addAll result (instructionsForExpression this arg)
	}
	add result (array 'callFunction' (((callee & 255) << 8) | ((count args) & 255)))
	if isCmd { add result (array 'pop' 1) } // discard the return value
	return result
}

// literal values (strings and large integers )

method appendLiterals SmallCompiler instructions {
	// For now, strings and integers too large for pushImmediate are the only literals.
	// Perhaps add support for constant literal arrays later.

	literals = (list)
	literalOffsets = (dictionary)
	nextOffset = (count instructions)
	for ip (count instructions) {
		instr = (at instructions ip)
		if (and (isClass instr 'Array') (isOneOf (first instr) 'pushLiteral' 'commandPrimitive' 'reporterPrimitive')) {
			literal = (at instr 2)
			litOffset = (at literalOffsets literal)
			if (isNil litOffset) {
				litOffset = nextOffset
				add literals literal
				atPut literalOffsets literal litOffset
				nextOffset += (wordsForLiteral this literal)
			}
			atPut instr 2 (litOffset - ip)
			if (isOneOf (first instr) 'commandPrimitive' 'reporterPrimitive') {
				primNameLiteralOffset = ((at instr 2) & 511)
				primSetIndex = ((at primsets (at instr 3)) & 127)
				argCount = ((at instr 4) & 255)
				instrArgs = (((primSetIndex << 17) | (primNameLiteralOffset << 8)) | argCount)
				atPut instr 2 instrArgs
			}
			atPut instructions ip (copyWith (at instructions ip) literal) // retain literal string for use by "show instructions"
		}
	}
	addAll instructions literals
}

method wordsForLiteral SmallCompiler literal {
	headerWords = 1
	if (isClass literal 'String') {
		return (headerWords + (floor (((byteCount literal) + 4) / 4)))
	}
	error 'Illegal literal type:' literal
}

// metadata for the deompiler

method appendDecompilerMetadata SmallCompiler aBlockOrFunction instructionList {
	// Append a tab-delimited list of local variables to instructionList.
	// This string is part of the optional metadata used by the decompiler.

	// the 'metadata' pseudo instruction marks the start of the decompiler meta data
	add instructionList (array 'metadata' 0)

	// add local variable names
	varNames = (list)
	for pair (sortedPairs localVars) {
		if (isClass (last pair) 'String') { // skip if non-string (can happen due to syntax error)
			add varNames (copyReplacing (last pair)) '	' ' ' // replace tabs with spaces in var name
		}
	}
	add instructionList (joinStrings varNames (string 9)) // tab delimited string

	// add function info
	if (isClass aBlockOrFunction 'Function') {
		add instructionList (metaInfoForFunction (project (scripter (smallRuntime))) aBlockOrFunction)
		argNames = (argNames aBlockOrFunction)
		if (notEmpty argNames) {
			add instructionList (joinStrings argNames (string 9)) // tab delimited string
		}
	}
}

// binary code generation

method addBytesForInstructionTo SmallCompiler instr bytes {
	// Append the bytes for the given instruction to bytes (little endian).

	opcode = (at opcodes (first instr))
	if (isNil opcode) { error 'Unknown opcode:' (first instr) }
	add bytes opcode
	arg = (at instr 2)
	if (not (and (-16777216 <= arg) (arg <= 16777215))) {
		error 'Argument does not fit in 24 bits'
	}
	add bytes (arg & 255)
	add bytes ((arg >> 8) & 255)
	add bytes ((arg >> 16) & 255)
}

method addBytesForIntegerLiteralTo SmallCompiler n bytes {
	// Append the bytes for the given integer to bytes (little endian).
	// Note: n is converted to a integer object, the equivalent of ((n << 1) | 1)

	add bytes (((n << 1) | 1) & 255)
	add bytes ((n >> 7) & 255)
	add bytes ((n >> 15) & 255)
	add bytes ((n >> 23) & 255)
}

method addBytesForStringLiteral SmallCompiler s bytes {
	// Append the bytes for the given string to bytes.

	byteCount = (byteCount s)
	wordCount = (floor ((byteCount + 4) / 4))
	headerWord = ((wordCount << 4) | stringClassID);
	repeat 4 { // add header bytes, little endian
		add bytes (headerWord & 255)
		headerWord = (headerWord >> 8)
	}
	for i byteCount {
		add bytes (byteAt s i)
	}
	repeat (4 - (byteCount % 4)) { // pad with zeros to next word boundary
		add bytes 0
	}
}
