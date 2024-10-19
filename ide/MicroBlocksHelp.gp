// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksHelp.gp - Help string table.
// John Maloney, November 2021

// PM edited on 2024-06-16

defineClass MicroBlocksHelp opDict

method initialize MicroBlocksHelp {
	// an entry is: op name, Wiki path, description

	opEntries = (array
		// OUTPUT
		(array 'setUserLED' 'output#set-user-led' 'Turn the user LED on or off.')
		(array 'sayIt' 'output#say' 'Display a bubble showing the value.')
		(array 'printIt' 'output#graph' 'Graph the value.')

		// INPUT
		(array 'buttonA' 'input#button-a' 'Report the state of button A ( (-o) or (o-) ).')
		(array 'buttonB' 'input#button-b' 'Report the state of button B ( (-o) or (o-) ).')
		(array 'timer' 'input#timer' 'Report the milliseconds since the timer was last reset.')
		(array 'resetTimer' 'input#reset-timer' 'Reset the timer.')
		(array 'secsOp' 'input#seconds' 'Report the seconds since power up.')
		(array 'millisOp' 'input#milliseconds' 'Report the milliseconds since power up.')
		(array 'microsOp' 'input#microseconds' 'Report the microseconds since power up.')
		(array 'boardType' 'input#board-type' 'Report the board type.')
		(array '[misc:version]' 'input#version' 'Reports firmware version loaded on the board.')
		(array '[misc:bleID]' 'input#BLE-Id' 'Reports the three-letter BLE ID of the board if it supports BLE.')
		(array '[ble:bleConnected]' 'input#BLE-connected' 'Reports (-o) if a BLE client is connected.')

	    (array 'millisSince' 'input#milliseconds' 'Report the milliseconds since the given start milliseconds. Handles clock wrap.')
		(array 'microsSince' 'input#microseconds' 'Report the microseconds since the given start microseconds. Handles clock wrap.')
		(array '[misc:connectedToIDE]' 'input#Connected-to-IDE' 'Reports (-o) if the board is connected to IDE.')

		// PINS
		(array 'digitalReadOp' 'pins#read-digital' 'Report the electrical logic level on a digital pin ( (-o) or (o-) ).')
		(array 'analogReadOp' 'pins#read-analog' 'Report a number proportional to the voltage on an analog pin (0 = ground, 1023 = supply voltage).')
		(array 'digitalWriteOp' 'pins#set-digital' 'Turn a pin on or off ( (-o) or (o-) ).')
		(array 'analogWriteOp' 'pins#set-pin' 'Pulse width modulate (PWM) a pin with the given duty cycle (0 - 1023).')
		(array 'analogPins' 'pins#analog-pins' 'Report number of analog pins on this device.')
		(array 'digitalPins' 'pins#digital-pins' 'Report number of digital pins on this device.')

		// COMM
		(array 'i2cGet' 'comm#i2c-get-device' 'Report the value of a register (0-255) of an I2C device (0-127).')
		(array 'i2cSet' 'comm#i2c-set-device' 'Set an I2C device and register to given value (0-255).')
		(array '[sensors:i2cRead]' 'comm#i2c-device-read' 'Receive multiple bytes from an I2C device.')
		(array '[sensors:i2cWrite]' 'comm#i2c-device-write' 'Send multiple bytes to an I2C device.')
		(array 'spiSend' 'comm#spi-send' 'Send a byte (0-255) to an SPI device.')
		(array 'spiRecv' 'comm#spi-receive' 'Read a byte from an SPI device while sending a zero byte. Report the byte received.')
		(array '[sensors:spiSetup]' 'comm#xxx' 'Set the SPI clock speed, mode, channel (Raspberry Pi only), and bit order.')
		(array '[sensors:spiExchange]' 'comm#xxx' 'Send a byte array via SPI, replacing its contents with the bytes received.')
		(array '[serial:open]' 'comm#serial-open' 'Open the serial port at the given baud rate.')
		(array '[serial:close]' 'comm#serial-close' 'Close the serial port.')
		(array '[serial:read]' 'comm#serial-read' 'Report data received from the serial port (a byte array).')
		(array '[serial:write]' 'comm#serial-write' 'Send a byte array to the serial port.')
		(array '[serial:writeBytes]' 'comm#serial-write-starting-at' 'Send a byte array to the serial port, starting at the given byte.')
		(array '[io:softWriteByte]' 'comm#soft-serial-write' 'Write a byte to the pin at the specified baud rate.')

		// CONTROL
		(array 'whenStarted' 'control#when-started' 'Run when the board powers up or when the IDE start button is clicked.')
		(array 'whenButtonPressed' 'control#when-button-pressed' 'Run when buttons A, B, or A+B are pressed.')
		(array 'forever' 'control#forever' 'Repeat the enclosed blocks indefinitely.')
		(array 'repeat' 'control#repeat' 'Repeat the enclosed blocks the given number of times.')
		(array 'waitMillis' 'control#wait-millisecs' 'Wait the given number of milliseconds.')
		(array 'if' 'control#if' 'Run the first set of blocks whose test condition is (-o) .')
		(array 'whenCondition' 'control#when' 'Run when the condition becomes (-o) .')
		(array 'waitUntil' 'control#wait-until' 'Wait until the condition becomes (-o) .')
		(array 'return' 'control#return' 'Return (report) the given value from a function or script.')
		(array 'whenBroadcastReceived' 'control#when-received' 'Run when the given message is received as a broadcast.')
		(array 'sendBroadcast' 'control#broadcast' 'Broadcast the given message.')
		(array 'comment' 'control#comment' 'Do nothing. Used to add notes and documentation.')
		(array '[data:range]' 'control#range' 'Report a list containing the given range of numbers (with optional increment). Useful in "for" loops.')
		(array 'for' 'control#for' 'Repeat the enclosed blocks with the variable set to the current iteration number or item.')
		(array 'repeatUntil' 'control#repeat-until' 'Repeat the enclosed blocks until the condition becomes (-o) .')
		(array 'stopTask' 'control#stop-this-task' 'Stop this task.')
		(array 'stopAll' 'control#stop-other-tasks' 'Stop all tasks except this one.')
		(array 'waitMicros' 'control#wait-microsecs' 'Wait the given number of microseconds.')
		(array 'getLastBroadcast' 'control#last-message' 'Report the last broadcast message received.')
		(array 'argOrDefault' 'control#arg' 'Report the given argument or defaultValue if the argument was not supplied by the caller.')
		(array 'callCustomCommand' 'control#call-custom-command' 'Call the function with the given name and optional parameter list.')
		(array 'callCustomReporter' 'control#call-custom-reporter' 'Call the function with the given name and optional parameter list and report its return value.')

		// OPERATORS
		(array '+' 'operators#plus' 'Report the sum of the given numbers.')
		(array '-' 'operators#minus' 'Report the first number minus the second.')
		(array '*' 'operators#multiply' 'Report the product of the given numbers.')
		(array '/' 'operators#divide' 'Report the first number divided by the second.')
		(array '%' 'operators#modulus' 'Report the remainder of dividing the first number by the second.')
		(array 'absoluteValue' 'operators#abs' 'Report the absolute value of the given number (always >= 0).')
		(array 'minimum' 'operators#min' 'Report the minimum of the values.')
		(array 'maximum' 'operators#max' 'Report the maximum of the values.')
		(array 'random' 'operators#random' 'Report a randomly chosen number in the given range.')
		(array '<' 'operators#less-than' 'Report (-o) if the first value is less than the second one.')
		(array '<=' 'operators#less-than-or-equal' 'Report (-o) if the first value is less than or equal to the second one.')
		(array '==' 'operators#equal' 'Report (-o) if the two values are equal.')
		(array '!=' 'operators#not-equal' 'Report (-o) if the two values are not equal.')
		(array '>=' 'operators#greater-than-or-equal' 'Report (-o) if the first value is greater than or equal to the second one.')
		(array '>' 'operators#greater-than' 'Report (-o) if the first value is greater than the second one.')
		(array 'booleanConstant' 'operators#boolean-true/false' 'Boolean constant ( (-o) or (o-) ).')
		(array 'not' 'operators#boolean-not' 'Report the logical inverse of a Boolean ( (-o) or (o-) ) value.')
		(array 'and' 'operators#boolean-and' 'Report (-o) if both values are (-o)')
		(array 'or' 'operators#boolean-or' 'Report (-o) if either value is (-o)')
		(array 'isType' 'operators#is-type' 'Report (-o) if first input is a value of the given data type.')
		(array '[data:convertType]' 'operators#convert' 'Convert a value to the given data type.')
		(array 'ifExpression' 'operators#ternary-if' 'If the condition is (-o) report the first alternative otherwise report the second alternative.')
		(array '[misc:rescale]' 'operators#rescale' 'Map a value in the "from" range to the corresponding value in the "to" range.')
		(array 'hexToInt' 'operators#hex' 'Report the numerical value of a hexadecimal string (range: -0x1FFFFFFF to 0x1FFFFFFF)')
		(array '&' 'operators#bitwise-and' 'Report bitwise AND of two numbers.')
		(array '|' 'operators#bitwise-or' 'Report bitwise OR of two numbers.')
		(array '^' 'operators#bitwise-xor' 'Report bitwise XOR (exclusive OR) of two numbers.')
		(array '~' 'operators#bitwise-not' 'Report bitwise inverse of the given number.')
		(array '<<' 'operators#bitwise-left-shift' 'Report the given number shifted left by the given number of bits.')
		(array '>>' 'operators#bitwise-right-shift' 'Report the given number shifted right by the given number of bits (arithmetic shift; sign is maintained).')

		// VARIABLES
		(array 'v' 'variables#xxx' '')
		(array '=' 'variables#set-variable' 'Set a variable to the given value.')
		(array '+=' 'variables#change-variable' 'Change a variable by the given amount.')
		(array 'local' 'variables#initialize-local' 'Create a variable local to the containing script with the given initial value.')

		// DATA
		(array 'at' 'data#item' 'Report the Nth item of a list, string, or byte array.')
		(array 'size' 'data#length-of' 'Report the number of items in a list, string, or byte array.')
		(array '[data:join]' 'data#join' 'Join (concatenate) the given lists, strings, or byte arrays and report the result.')
		(array '[data:makeList]' 'data#list' 'Create and report a short list containing the given items. Length limited by available stack space.')
		(array '[data:addLast]' 'data#add-to-list' 'Add an item to the end of a list.')
		(array 'atPut' 'data#repllace-item' 'Replace the Nth item (or all items) of a list or byte array with the given value.')
		(array '[data:delete]' 'data#delete-item' 'Delete the Nth item (or all items) of a list.')
		(array '[data:find]' 'data#find' 'Find and report the index of an item in a list or a substring within a string. Report -1 if not found.')
		(array '[data:copyFromTo]' 'data#copy' 'Report a copy from the given index through the end (or optional stop index) of the given list, string, or byte array.')
		(array '[data:split]' 'data#split' 'Split the given string with the given delimiter and report the result (a list of strings).')
		(array '[data:joinStrings]' 'data#join-items-of-list' 'Combine the items of a list into a string, optionally separated by a delimiter (e.g. comma).')
		(array '[data:unicodeAt]' 'data#unicode' 'Report the Unicode value ("code point") of the Nth character of the given string.')
		(array '[data:unicodeString]' 'data#string-from-unicode' 'Report a string containing the given Unicode value ("code point") or list of values.')
		(array 'newList' 'data#new-list' 'Report a new list of the given length filled with zero or the optional value.')
		(array '[data:newByteArray]' 'data#new-byte-array' 'Report a new byte array of the given length filled with zero or the optional value.')
		(array '[data:asByteArray]' 'data#as-byte-array' 'Report a byte array containing the UTF-8 bytes of the given string.')
		(array '[data:freeMemory]' 'data#free-memory' 'Report the number of words of memory available. Stop button frees up memory.')

		// BASIC SENSORS LIBRARY
		(array '[sensors:tiltX]' '/libraries#tilt-x-y-z' 'Report x acceleration/tilt (+/-200).')
		(array '[sensors:tiltY]' '/libraries#tilt-x-y-z' 'Report y acceleration/tilt (+/-200).')
		(array '[sensors:tiltZ]' '/libraries#tilt-x-y-z' 'Report z acceleration/tilt (+/-200).')
		(array '[sensors:acceleration]' '/libraries#acceleration' 'Report total acceleration (0-346).')
		(array '[display:lightLevel]' '/libraries#light-level' 	'Report ambient light level (0-1023).')
		(array '[sensors:temperature]' '/libraries#temperature'	'Report ambient temperature in degrees Celsius.')
		(array '[sensors:magneticField]' '/libraries#magnetic-field' 'Report magnetic field strength (0-100000).')
		(array '_setAccelRange' '/libraries#set-acceleration-range'	'Set accelermeter range. Higher ranges are usefl for collisions.')

		// LED DISPLAY LIBRARY
		(array '[display:mbDisplay]' '/libraries#display' 'Display a 5x5 image on the LED display.')
        (array 'led_displayImage' '/libraries' 'Choose an image to show on the LED display')
		(array '[display:mbDisplayOff]' '/libraries#clear-display' 'Clear the LED display (all pixels off).')
		(array '[display:mbPlot]' '/libraries#plot-x-y' 'Turn on the LED at the given row and column (1-5).')
		(array '[display:mbUnplot]' '/libraries#unplot-x-y' 'Turn off the LED at the given row and column (1-5).')
		(array 'displayCharacter' '/libraries#display-character' 'Display a single character on the LED display.')
		(array 'scroll_text' '/libraries#scroll-text' 'Scroll words or numbers across the LED display.')
		(array 'stopScrollingText' '/libraries#stop-scrolling' 'Stop scrolling and clear the display.')
        (array '_set display color' '/libraries#set-display-color' 'Sets the color of the 5x5 square LED pixels to the color selected.')
        (array '_led_image' '/libraries#led-image' 'Reports a number representative of the image drawn on the 5x5 LED panel pixels.')
        (array '_led_namedImage' '/libraries#_led_namedimage' 'Returns the integer value representing the image selected from the drop-down menu.')

		// NEOPIXEL
		(array 'neoPixelAttach' '/libraries#attach-neopixel-led-to-pin' 'Set Neopixel count and pin number.')
		(array 'setNeoPixelColors10' '/libraries#set-neopixels' 'Set the colors of the first ten NeoPixels.')
		(array 'clearNeoPixels' '/libraries#clear-neopixels' 'Turn off all NeoPixels.')
		(array 'neoPixelSetAllToColor' '/libraries#set-all-neopixels-color' 'Set all NeoPixels to the given color.')
		(array 'setNeoPixelColor' '/libraries#set-neopixel-color' 'Set the given NeoPixel to the selected color.')
		(array 'rotateNeoPixelsBy' '/libraries#rotate-neopixels-by' 'Shift/rotate the NeoPixel colors by the given number.')
		(array 'colorFromRGB' '/libraries#color-r-g-b' 'Return a color defined by values of R G B (0-255).')
		(array 'randomColor' '/libraries#random-color' 'Return a random color.')
        (array 'NeoPixel_brighten' '/libraries' 'Brighten a single NeoPixel.')
        (array 'NeoPixel_brighten_all' '/libraries' 'Brighten all NeoPixels.')

		// RADIO
		(array '[radio:sendInteger]' '/libraries#radio-send-number' 'Send a numerical message.')
		(array '[radio:sendString]' '/libraries#radio-send-string' 'Send a text message.')
		(array '[radio:sendPair]' '/libraries#radio-send-pair' 'Send a message containing both short text string and a number.')
		(array '[radio:messageReceived]' '/libraries#radio-message-received' 'Return (-o) when a new radio message is received.')
		(array '[radio:receivedInteger]' '/libraries#radio-last-number' 'Return the number part of the last radio message received.')
		(array '[radio:receivedString]' '/libraries#radio-last-string' 'Return the text part of the last radio message received.')
		(array '[radio:setGroup]' '/libraries#radio-set-group' 'Set the radio group number (0-255).')
		(array '[radio:setPower]' '/libraries#radio-set-power' 'Set the radio transmission power level (0-7).')

		// RINGTONE
		(array 'play ringtone' '/libraries#play-ringtone' 'Play the given ringtone string.')
		(array 'current song name' '/libraries#current-song-name' 'Report the name of the currently playing ringtone song.')

		// SERVO
		(array 'setServoAngle' '/libraries#set-servo-degrees' 'Set the angle of a positional servo.')
		(array 'setServoSpeed' '/libraries#set-servo-speed' 'Set the speed of a continuous rotation servo.')
		(array 'stopServo' '/libraries#servo-stop' 'Stop sending servo control pulses.')

		// TONE
		(array 'play tone' '/libraries#play-note' 'Play the given note in the given octave for milliseconds.')
		(array 'playMIDIKey' '/libraries#play-midi' 'Play the given piano key (0-127) for milliseconds. Middle C is 60.')
		(array 'play frequency' '/libraries#play-frequency' 'Play a note specified in Hertz (Hz). Middle C is ~261 Hz.')
		(array 'startTone' '/libraries#start-tone' 'Starts playing a tone specified in Hertz (Hz).')
		(array 'stopTone' '/libraries#stop-tone' 'Stops playing a note that was started with start tone.')
		(array 'attach buzzer to pin' '/libraries#attach-buzzer' 'Specify the pin used to play tones.')

		// IR Remote
		(array 'receiveIR' '/extension_libraries/irremote#receive-ir-code' 'Wait for an IR message then return its key code.')
		(array 'attachIR' '/extension_libraries/irremote#attach-ir-receiver' 'Set the IR receiver pin.')
		(array 'IR_Transmit' '/extension_libraries/irremote#ir-transmit-device' 'Send an IR command with the given device number and key code.')
		(array 'attachIRTransmitter' '/extension_libraries/irremote#xxx' 'Set the IR transmitter pin.')
		(array '_testIR' '/extension_libraries/irremote#test-ir' 'Wait for an IR message then say its device number and key code received')
		(array '_receiveIRFromDevice' '/extension_libraries/irremote#receive-ir-code-from-device' 'Return the next IR key code from the given device.')

		// PICOBRICKS
		(array 'pb_beep' '/extension_libraries/picobricks#picobricks-beep' 'Make a beep sound from the speaker.')
		(array 'pb_button' 	'/extension_libraries/picobricks#picobricks-button' 'Return (-o) if the button is pressed.')
		(array 'pb_humidity' '/extension_libraries/picobricks#picobricks-humidity' 'Return the relative humidity.')
		(array 'pb_light_sensor' '/extension_libraries/picobricks#picobricks-light-sensor' 'Return the light level (0-100).')
		(array 'pb_potentiometer' '/extension_libraries/picobricks#picobricks-potentiometer' 'Return the potentiometer value (0-1023).')
		(array 'pb_random_color' '/extension_libraries/picobricks#picobricks-random-color' 'Return a random color.')
		(array 'pb_rgb_color' '/extension_libraries/picobricks#picobricks-color' 'Return a color with the given RGB values (0-255).')
		(array 'pb_set_motor_speed'	'/extension_libraries/picobricks#picobricks-set-motor' 'Set the speed of a DC motor (0-100)')
		(array 'pb_set_red_LED' '/extension_libraries/picobricks#picobricks-set-red-led' 'Turn the red LED on (-o) or off (o-) .')
		(array 'pb_set_relay' '/extension_libraries/picobricks#picobricks-set-relay' 'Turn the relay on (-o) or off (o-) .')
		(array 'pb_set_rgb_color' '/extension_libraries/picobricks#picobricks-set-rgb-led-color' 'Set the RGB LED color using the color selector.')
		(array 'pb_temperature' '/extension_libraries/picobricks#picobricks-temperature' 'Return the temperature (Celsius).')
		(array 'pb_turn_off_RGB' '/extension_libraries/picobricks#picobricks-turn-off-rgb-led' 'Turn off the RGB LED.')

		// OLED
		(array 'OLEDInit_I2C' '/extension_libraries/oled#initialize-i2c' 'Initialize an I2C OLED display.')
		(array 'OLEDInit_SPI' '/extension_libraries/oled#initialize-spi' 'Initialize an SPI OLED display.')
		(array 'OLEDwrite' '/extension_libraries/oled#write-' 'Display the given value as a string.')
		(array 'OLEDshowGDBuffer' '/extension_libraries/oled#show-display-buffer' 'Reveal the contents of the virtual buffer if updates were deferred.')
		(array 'OLEDclear' '/extension_libraries/oled#clear-' 'Clear the display.')
		(array 'OLEDcontrast' '/extension_libraries/oled#set-contrast' 'Set the display contrast (1-4).')
		(array 'OLEDdrawCircle' '/extension_libraries/oled#draw-circle' 'Draw a circle with center at x,y.')
		(array 'OLEDdrawImage' '/extension_libraries/oled#draw-image' 'Draw an image at x,y. See OLEDmakeImage.')
		(array 'OLEDdrawLine' '/extension_libraries/oled#draw-line' 'Draw a line between two points.')
		(array 'OLEDdrawRect' '/extension_libraries/oled#draw-rectangle' 'Draw a rectangle at x,y with width and height.')
		(array 'OLEDfillRect' '/extension_libraries/oled#fill-rectangle' 'Draw a filled rectangle at x,y with width and height.')
		(array 'OLEDflip' '/extension_libraries/oled#_flip-display-top' 'Flip which side of the display is the top.')
		(array 'OLEDmakeImage' '/extension_libraries/oled#make-image' 'Make a 5x5 Sprite image for use with OLEDdrawImage.')
		(array 'OLEDpixel' '/extension_libraries/oled#set-pixel' 'Turn the pixel at x,y on (-o) or off (o-) .')
		(array 'OLEDsetVideo' '/extension_libraries/oled/set-videoa' 'Set the display to inverse video or normal mode.')
		(array 'OLEDwru' '/extension_libraries/oled#cursor-location' 'Report the cursor location.')
		(array 'defer display updates' '/extension_libraries/oled#defer-display-updates' 'Delay display updates during pixel level operations.')

		// MAQUEEN
		(array 'Maqueen beep' '/extension_libraries/maqueen/#maqueen-beep' 'Make a beep sound.')
		(array 'Maqueen distance (cm)' '/extension_libraries/maqueen/#maqueen-distance' 'Return the distance to a wall or obstacle.')
		(array 'Maqueen IR keycode' '/extension_libraries/maqueen/#maqueen-ir-keycode' 'Return the last received IR keycode.')
		(array 'Maqueen LED' '/extension_libraries/maqueen/#maqueen-led' 'Turn the left and/or right LEDs on (-o) or off (o-) .')
		(array 'Maqueen line sensor' '/extension_libraries/maqueen/#maqueen-line-sensor' 'Return the given line sensor value ( (-o) or (o-) )')
		(array 'Maqueen motor' '/extension_libraries/maqueen/#maqueen-motor' 'Set the motor directions and speeds.')
		(array 'Maqueen stop motors' '/extension_libraries/maqueen/#maqueen-stop-motors' 'Stop the motors.')
		(array 'Maqueen sees line on left' '/extension_libraries/maqueen/#maqueen-sees-line-on-left' 'Return (-o) if the given line sensor sees a black line.')

		// HUSKYLENS
		(array 'HL set Comms' '/extension_libraries/huskylens#hl-set-comms' 'Sets communication mode of the camera')
		(array 'HL change algorithm' '/extension_libraries/huskylens#hl-change-algorithm' 'Change recognition algorithm.')
		(array 'HL do' '/extension_libraries/huskylens#hl-do' 'Perform maintenance operation.')
		(array 'HL request' '/extension_libraries/huskylens#hl-request' 'Request recognized objects from HuskyLens.')
		(array 'HL request by ID' '/extension_libraries/huskylens#hl-request-by-id' 'Request only one object by id from HuskyLens.')
		(array 'HL get info' '/extension_libraries/huskylens#hl-get-info' 'Get Info details from HuskyData.')
		(array 'HL get block' '/extension_libraries/huskylens#hl-get-block' 'Get Block details from HuskyData.')
		(array 'HL get arrow' '/extension_libraries/huskylens#hl-get-arrow' 'Get Arrow details from HuskyData')
		(array 'HL learn current object as ID' '/extension_libraries/huskylens#hl-learn-as-id' 'Learn recognized object as ID#.')
		(array 'HL learn object as ID' '/extension_libraries/huskylens#hl-learn-as-id-and-name' 'Learn recognized object as ID# and assigns name')
		(array 'HL set CustomName' '/extension_libraries/huskylens#hl-set-custom-name' 'Set custom name for a learned object.')
		(array 'HL write' '/extension_libraries/huskylens#hl-write' 'Write text to HuskyLens screen @ x,y [0,0 is top left].')
		(array 'HL file' '/extension_libraries/huskylens#hl-file' 'Save/Load file to/from SDcard.')

		// WEBSOCKET SERVER
		(array 'start WebSocket server' '/network_libraries/websocket-server#start-websocket-server' 'Start running the WebSocket server.')
		(array '[net:webSocketLastEvent]' '/network_libraries/websocket-server#last-websocket-event' 'Report the last protocol message received.')
		(array 'ws client id' '/network_libraries/websocket-server#client-id-for-websocket-event' 'Report the WebSocket client ID (0-4).')
		(array 'ws event payload' '/network_libraries/websocket-server#payload-for-websocket-event' 'Report the content of the message received.')
		(array 'ws event type' '/network_libraries/websocket-server#type-of-websocket-event' 'Report the WebSocket event type.')
		(array '[net:webSocketSendToClient]' '/network_libraries/websocket-server#send-to-websocket-client'	'Send a message to any client using its client id.')

        // OCTOSTUDIO
        (array 'octoSendBeam' '/network_libraries/' 'Choose a shape that is send to the connected phone(s).')
        (array 'octoBeamReceived' '/network_libraries/' 'Report (-o) if a new beam has been received. Use "Octo last beam" to get its value.')
        (array 'octoLastBeam' '/network_libraries/' 'Report the name of the last shape received.')
        (array 'octoReceiveBeam' '/network_libraries/' 'Report the shape if a new beam has been received.')

        // BLE SCANNER
        (array 'bleScan_scanReceived' '/network_libraries/ble-scanner#scan-received' 'Report (-o) when a BLE scan is detected.')
        (array 'bleScan_RSSI' '/network_libraries/ble-scanner#rssi' 'Report RSSI, ranges from -26 (a few inches) to -100 (40-50 m distance).')
        (array 'bleScan_address' '/network_libraries/ble-scanner#address' 'Report MAC address, a unique 48-bit identifier.')
        (array 'bleScan_addressType' '/network_libraries/ble-scanner#address-type' 'Report address type.')
        (array 'bleScan_deviceName' '/network_libraries/ble-scanner#device-name' 'Report device name.')
        (array 'bleScan_hasType' '/network_libraries/ble-scanner#hastype' 'Report (-o) if device name is type 8 or 9.')

        // BLE SERIAL
        (array '[ble:uartConnected]' '/network_libraries/' 'Report (-o) if BLE serial is connected')
        (array 'bleSerial_readString' '/network_libraries/' 'Returns a string read from the BLE Serial port.')
        (array 'bleSerial_readBytes' '/network_libraries/' 'Returns bytes read from the BLE Serial port.')
        (array 'bleSerial_write' '/network_libraries/' 'Writes any String or ByteArray to the BLE Serial port.')

        // UDP
        (array '[net:udpStart]' '/network_libraries/' '')
        (array '[net:udpStop]' '/network_libraries/' '')
        (array '[net:udpSendPacket]' '/network_libraries/' '')
        (array '[net:udpReceivePacket]' '/network_libraries/' '')
        (array '[net:udpRemoteIPAddress]' '/network_libraries/' '')
        (array '[net:udpRemotePort]' '/network_libraries/' '')

        // WIFI
        (array 'wifiConnect' '/network_libraries/wifi#wifi-connect-to' 'Connect to the local IP network.')
        (array 'wifiCreateHotspot' '/network_libraries/wifi#wifi-create-hotspot' 'Create a hotspot with given credentials.')
        (array 'getIPAddress' '/network_libraries/wifi#ip-address' 'Report acquired IP address.')
        (array '[net:myMAC]' '/network_libraries/wifi#mac-address' 'Report MAC address of the WIFI device.')
        (array '[net:allowWiFiAndBLE]' '/network_libraries/wifi#allow-wifi-while-using-ble' 'Enable simultaneous WIFI & BLE use.')

        //WIFI RADIO
        (array 'wifiRadio_sendNumber' '/network_libraries/wifi-radio#wifi-send-number' 'Send a message containing a number.')
        (array 'wifiRadio_sendString' '/network_libraries/wifi-radio#wifi-send-string' 'Send a text string (up to approx. 800 bytes).')
        (array 'wifiRadio_sendPair' '/network_libraries/wifi-radio#wifi-send-pair' 'Send a message containing both short text string and a number. ')
        (array 'wifiRadio_messageReceived' '/network_libraries/wifi-radio#wifi-message-received' 'Report (-o) when a new wifi message is received.')
        (array 'wifiRadio_receivedInteger' '/network_libraries/wifi-radio#wifi-last-number' 'Report the number part of the last wifi message received. Return zero if the message did not contain a number.')
        (array 'wifiRadio_receivedString' '/network_libraries/wifi-radio#wifi-last-string' 'Report the string part of the last wifi message received. Return the empty string if the message did not contain a string.')
        (array 'wifiRadio_setGroup' '/network_libraries/wifi-radio#wifi-set-group' 'Set the group number (0-255) used to send and receive messages.')

        // PICOBRICKS-mb
        (array 'pbmb_beep' '/extension_libraries/picobricks-mb#picobricks-mb-beep' 'Makes a beep sound from the speaker.')
        (array 'pbmb_humidity' '/extension_libraries/picobricks-mb#picobricks-mb-humidity' 'Returns the humidity percentage value.')
        (array 'pbmb_temperature' '/extension_libraries/picobricks-mb#picobricks-mb-temperature' 'Returns the temperature in Celsius.')
        (array 'pbmb_pir' '/extension_libraries/picobricks-mb#picobricks-mb-pir-detected' 'Returns (-o) if any motion is detected.')
        (array 'pbmb_set_relay' '/extension_libraries/picobricks-mb#picobricks-mb-set-relay' 'Sets the relay as (-o) or (o-)')
        (array 'pbmb_set_motor_speed' '/extension_libraries/picobricks-mb#picobricks-mb-set-motor' 'This module controls the two DC motors (M1, M2).')
        (array 'pbmb_set_servo_angle' '/extension_libraries/picobricks-mb#picobricks-mb-set-servo' 'Sets the servo ANGLE to (0-180).')
        (array 'pbmb_ir_code_received' '/extension_libraries/picobricks-mb#picobricks-mb-ir-code-received' 'Waits until IR code is received, and then returns (-o)')
        (array 'pbmb_ir_code' '/extension_libraries/picobricks-mb#picobricks-mb-ir-code' 'Returns the last IR code detected by the IR sensor.')
        (array 'pbmb_ir_recv_code' '/extension_libraries/picobricks-mb#picobricks-mb-receive-ir-code' 'Waits until IR is (-o) and returns the IR code detected.')
        (array 'pbmb_gest_color' '/extension_libraries/picobricks-mb#picobricks-mb-gs-color' 'Returns color detected as a number derived from RGB values.')
        (array 'pbmb_gest_avail' '/extension_libraries/picobricks-mb#picobricks-mb-gs-detected' 'Returns (-o) or (o-) based on the detected motion over the sensor.')
        (array 'pbmb_gest_lastgest' '/extension_libraries/picobricks-mb#picobricks-mb-gs-last-gesture' 'Returns the last gesture detected.')
        (array 'pbmb_gest_light' '/extension_libraries/picobricks-mb#picobricks-mb-gs-light' 'Returns the light level detected by the sensor.')
        (array 'pbmb_gest_prox' '/extension_libraries/picobricks-mb#picobricks-mb-gs-proximity' 'Indication of how near or far an object is from the sensor (0-255).')
        (array 'pbmb_light_sensor' '/extension_libraries/picobricks-mb#picobricks-mb-light-sensor' 'Returns the light level as a 0-100 percentage value.')
        (array 'pbmb_potentiometer' '/extension_libraries/picobricks-mb#picobricks-mb-potentiometer' 'Returns values 0-1023, representing the voltages of 0-3.3V.')
        (array 'pbmb_button' '/extension_libraries/picobricks-mb#picobricks-mb-pot-button' 'Returns the button status as (-o) or (o-)')
        (array 'pbmb key _ pressed' '/extension_libraries/picobricks-mb#picobricks-mb-touchkey-pressed' 'Returns a (-o) or (o-) for any touchkey detection.')
        (array 'pbmb Last key touched' '/extension_libraries/picobricks-mb#picobricks-mb-last-key-touched' 'Returns the name of last key touch detected.')
        (array '_pbmb_configureTouch' '/extension_libraries/picobricks-mb#_picobricks-mb-configure-touch-options' 'Configures touch sensor area options.')
        (array '_pbmb_Config&CRC' '/extension_libraries/picobricks-mb#_picobricks-mb-show-touch-config&crc' 'Displays the configuration & CRC of the current configuration.')

        // Cutebot Pro
        (array 'cbpro_setWheelSpeed' '/extension_libraries/cutebotpro#cbpro-set-wheel-speed' 'Runs car at specified cm/s speed.')
        (array 'cbpro_wheelSpeed' '/extension_libraries/cutebotpro#cbpro-speed-of-wheel' 'Returns speed of selected wheel in cm/s.')
        (array 'cbpro_stopWheel' '/extension_libraries/cutebotpro#cbpro-stop-wheel' 'Stops selected wheel.')
        (array 'cbpro_stopAll' '/extension_libraries/cutebotpro#cbpro-stop-all' 'Resets all car settings: stops car, stops external motor, turns off all lights.')
        (array 'cbpro_move' '/extension_libraries/cutebotpro#cbpro-move' 'Moves car a specified distance (0-255cm).')
        (array 'cbpro_turn' '/extension_libraries/cutebotpro#cbpro-turn' 'Executes a turn per selected parameters.')
        (array 'cbpro_setHeadlight' '/extension_libraries/cutebotpro#cbpro-set-headlight' 'Sets headlights to specified color.')
        (array 'cbpro_setNeopixels' '/extension_libraries/cutebotpro#cbpro-set-neopixel' 'Sets colors of the selected NeoPixels under the car.')
        (array 'cbpro_distance' '/extension_libraries/cutebotpro#cbpro-distance' 'Returns distance to detected object in cm.')
        (array 'cbpro_trackingSensorState' '/extension_libraries/cutebotpro#cbpro-tracking-state-is' 'Returns (-o) if tracking sensors match the pattern selected.')
        (array 'cbpro_getTrackingState' '/extension_libraries/cutebotpro#cbpro-tracking-state' 'Returns the tracking state of the Line tracking sensors.')
        (array 'cbpro_getTrackingOffset' '/extension_libraries/cutebotpro#cbpro-tracking-offset' 'Returns the tracking offset of the Line tracking sensors.')
        (array 'cbpro_irCodeReceived' '/extension_libraries/cutebotpro#cbpro-ir-code-received' 'Returns (-o) if an IR code is detected.')
        (array 'cbpro_irCode' '/extension_libraries/cutebotpro#cbpro-ir-code' 'Returns the value of the IR code detected.')
        (array 'cbpro_setServoAngle' '/extension_libraries/cutebotpro#cbpro-set-servo-angle' 'Sets selected servo types to set angles.')
        (array 'cbpro_setServoSpeed' '/extension_libraries/cutebotpro#cbpro-set-servo-speed' 'Sets continuous servos to set speed and direction.')
        (array 'cbpro_setMotorPower' '/extension_libraries/cutebotpro#cbpro-set-external-motor-power' 'Runs external motor at specified power % and direction.')
        (array 'cbpro_stopMotor' '/extension_libraries/cutebotpro#cbpro-stop-external-motor' 'Stops external motor.')
        (array 'cbpro_getVersion' '/extension_libraries/cutebotpro#cbpro-version' 'Returns firmware version of the controller.')
        (array '_cbpro_setWheelPower' '/extension_libraries/cutebotpro#_cbpro_setwheel-power' 'Runs car at specified power % and direction.')
        (array '_cbpro_clearEncodersAndOrientation' '/extension_libraries/cutebotpro#_cbpro_clearencodersandorientation' 'Clears encoder value and orientation variables.')
        (array '_cbpro_getOrientation' '/extension_libraries/cutebotpro#_cbpro_getorientation' 'Returns orientation of car.')
        (array '_cbpro_readEncoders' '/extension_libraries/cutebotpro#_cbpro_readencoders' 'Reads encoder values and sets variables _cbpro_leftCount and _cbpro_rightCount.')

		// CoCube
		(array 'CoCube Battery Percentage' '/extension_libraries/cocube#cocube-battery-percentage' 'Returns the battery percentage of CoCube.')
		(array 'CoCube On The Mat' '/extension_libraries/cocube#cocube-on-the-mat' 'Returns (-o) if CoCube on the CoMap.')
		(array 'CoCube Card ID' '/extension_libraries/cocube#cocube-card-id' 'Returns the Index value of CoTag.')
		(array 'CoCube position_X' '/extension_libraries/cocube#cocube-position-x' 'Returns the X coordinate of CoCube.')
		(array 'CoCube position_Y' '/extension_libraries/cocube#cocube-position-y' 'Returns the Y coordinate of CoCube.')
		(array 'CoCube position_Direction' '/extension_libraries/cocube#cocube-position-direction' 'Returns the rotation angle of CoCube (0~359°).')
		(array 'CoCube set TFT backlight' '/extension_libraries/cocube#cocube-set-tft-backlight' 'Turn on/off the TFT backlight.')
		(array 'CoCube draw Aruco Marker on TFT' '/extension_libraries/cocube#cocube-draw-aruco-marker-on-tft' 'Display an ArUco Marker on the TFT screen.')
		(array 'CoCube draw AprilTag on TFT' '/extension_libraries/cocube#cocube-draw-apriltag-on-tft' 'Display an AprilTag Marker on the TFT screen.')
		(array 'CoCube move' '/extension_libraries/cocube#cocube-move' 'Move CoCube at unit/s speed.')
		(array 'CoCube rotate' '/extension_libraries/cocube#cocube-rotate' 'Rotate CoCube at unit/s speed.')
		(array 'CoCube move for millisecs' '/extension_libraries/cocube#cocube-move-for-millisecs' 'Move CoCube at unit/s speed for milliseconds.')
		(array 'CoCube rotate for millisecs' '/extension_libraries/cocube#cocube-rotate-for-millisecs' 'Rotate CoCube at unit/s speed for milliseconds.')
		(array 'CoCube move by step' '/extension_libraries/cocube#cocube-move-by-step' 'Move CoCube at unit/s speed for a specific distance.')
		(array 'CoCube rotate by degree' '/extension_libraries/cocube#cocube-rotate-by-degree' 'Rotate CoCube at unit/s speed for a specific degree.')
		(array 'CoCube set wheel' '/extension_libraries/cocube#cocube-set-wheel' 'Control the speed of the left and right wheels of CoCube separately.')
		(array 'CoCube wheels stop' '/extension_libraries/cocube#cocube-wheels-stop' 'Control CoCube stop.')
		(array 'CoCube wheels break' '/extension_libraries/cocube#cocube-wheels-break' 'Control CoCube break.')
		(array 'CoCube rotate to angle' '/extension_libraries/cocube#cocube-rotate-to-angle' 'Turn to a specific angle.')
		(array 'CoCube rotate to target' '/extension_libraries/cocube#cocube-rotate-to-target' 'Turn to a specific target.')
		(array 'CoCube move to target' '/extension_libraries/cocube#cocube-move-to-target' 'Move to a specific target.')

		// PID
		(array 'pid_computePID' '/extension_libraries/pid#compute-pid' 'Compute the next PID correction for the specified PID loop.')
		(array 'pid_resetPID' '/extension_libraries/pid#reset-pid' 'Reset the specified PID loop.')
		(array 'pid_constrainValue' '/extension_libraries/pid#constrain-value' 'Limit the range of a value, typically a drive signal.')
		(array 'pid_applySign' '/extension_libraries/pid#apply-sign-to-value' 'Apply the sign of one value to another value.')

        // XRP
		(array 'xrp_driveAtSpeed' '/extension_libraries/xrp#drive-at-speed' 'Drive the robot at a specified speed (mm/sec).')
        (array 'xrp_driveDistance' '/extension_libraries/xrp#drive-distance' 'Drive the robot a specified distance (mm) at a specified speed (mm/sec).')
        (array 'xrp_stopWheels' '/extension_libraries/xrp#stop-both-wheels' 'Stop both wheels.')
        (array 'xrp_turnAngle' '/extension_libraries/xrp#turn-angle' 'Turn the robot the specified amount (deg) at the specified speed (deg/sec).')
        (array 'xrp_waitForWheelsToStop' '/extension_libraries/xrp#wait-for-wheels-to-stop' 'Wait for both wheels to stop.')
        (array 'xrp_setServo' '/extension_libraries/xrp#set-servo-to-angle' 'Set the specified servo to the specified angle.')
        (array 'xrp_readRollRate' '/extension_libraries/xrp#read-roll-rate' 'Read roll rate (deg/sec).')
        (array 'xrp_readPitchRate' '/extension_libraries/xrp#read-pitch-rate' 'Read pitch rate (deg/sec).')
        (array 'xrp_readYawRate' '/extension_libraries/xrp#read-yaw-rate' 'Read yaw rate (deg/sec).')
        (array 'xrp_readDistanceSensor' '/extension_libraries/xrp#read-distance-sensor' 'Read the distance sensor (cm).')
        (array 'xrp_readLineSensors' '/extension_libraries/xrp#read-left-right-line-sensors' 'Read the left and right line sensors.')
        (array 'edcmotors_getNumMotors' '/extension_libraries/xrp#get-the-number-of-encoded-dc-motors' 'Get the number of encoded DC motors.')

	)

	opDict = (dictionary)
	for e opEntries {
		atPut opDict (first e) e
	}
	return this
}

method entryForOp MicroBlocksHelp op {
	// Return a help entry, an array of: op name, Wiki path, description.

	if (isNil opDict) { return nil }
	return (at opDict op nil)
}
