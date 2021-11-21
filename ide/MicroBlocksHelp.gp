// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksHelp.gp - Help string tables for MicroBlocks.
// John Maloney, November 2021

defineClass MicroBlocksHelp opDict

method initialize MicroBlocksHelp {
	// an entry is: op name, Wiki path, description

	opEntries = (array
		// OUTPUT
		(array 'setUserLED' 'output#set-user-led' 'Turns on or off the user LED.')
		(array 'sayIt' 'output#say' 'Displays a bubble with the given value(s).')
		(array 'printIt' 'output#graph' 'Graphs the given value(s) in the data graph display panel.')

		// INPUT
		(array 'buttonA' 'input#button-a' 'Returns the state of button A. (-o) pressed, (o-) not pressed.')
		(array 'buttonB' 'input#button-b' 'Returns the state of button B. (-o) pressed, (o-) not pressed.')
		(array 'timer' 'input#timer' 'Returns the milliseconds since the last timer reset.')
		(array 'resetTimer' 'input#reset-timer' 'Resets the timer to zero. (milliseconds and microseconds blocks not affected)')
		(array 'millisOp' 'input#milliseconds' 'Returns the milliseconds since the board was powered up or hardware reset.')
		(array 'microsOp' 'input#microseconds' 'Returns the microseconds since the board was powered up or hardware reset.')
		(array 'boardType' 'input#board-type' 'Returns the type of this board. eg.: micro:bit, ESP32, or Clue.')

		// PINS
		(array 'digitalReadOp' 'pins#read-digital' 'Returns the value, ( (-o) or (o-) ) of the given digital pin.')
		(array 'analogReadOp' 'pins#read-analog' 'Returns the value (0 - 1023) of the given analog pin.')
		(array 'digitalWriteOp' 'pins#set-digital' 'Sets the value ( (-o) or (o-) ) of the given digital pin.')
		(array 'analogWriteOp' 'pins#set-pin' 'Sets the PWM duty cycle (0 - 1023) of the given analog pin. Reset the board to stop PWM output.')
		(array 'analogPins' 'pins#analog-pins' 'Returns the total number of analog pins supported by this device.')
		(array 'digitalPins' 'pins#digital-pins' 'Returns the total number of digital pins supported by this device.')

		// COMM
		(array 'i2cGet' 'comm#i2c-get-device' 'Return the value of the given register (0-255) of the given I2C device (0-127).')
		(array 'i2cSet' 'comm#i2c-set-device' 'Writes an 8-bit byte (0-255) to the given I2C device and register.')
		(array '[sensors:i2cRead]' 'comm#i2c-device-read' 'Receives multiple bytes from the given I2C device.')
		(array '[sensors:i2cWrite]' 'comm#i2c-device-write' 'Sends multiple bytes to the given I2C device.')
		(array 'spiSend' 'comm#spi-send' 'Sends a byte (0-255) to the SPI bus.')
		(array 'spiRecv' 'comm#spi-receive' 'Reads a byte from the SPI bus while sending a zero byte. Returns the received byte.')
		(array '[sensors:spiSetup]' 'comm#xxx' 'Set the SPI clock speed and mode.')
		(array '[sensors:spiExchange]' 'comm#xxx' 'Send the bytes of the given byte array via SPI and replace them with the bytes received.')
		(array '[serial:open]' 'comm#serial-open' 'Opens the serial port at the specified baud rate.')
		(array '[serial:close]' 'comm#serial-close' 'Closes the serial port.')
		(array '[serial:read]' 'comm#serial-read' 'Receives data from the serial port. Returns a byte array.')
		(array '[serial:write]' 'comm#serial-write' 'Sends a byte array to the serial port.')

		// CONTROL
		(array 'whenStarted' 'control#when-started' 'Runs the blocks below when the board is powered up or when the IDE start button is clicked.')
		(array 'whenButtonPressed' 'control#when-button-pressed' 'Runs the blocks below when buttons A, B, or A+B are pressed.')
		(array 'forever' 'control#forever' 'Runs the enclosed blocks over and over, indefinitely.')
		(array 'repeat' 'control#repeat' 'Runs the enclosed blocks the given number of times.')
		(array 'waitMillis' 'control#wait-millisecs' 'Waits the given number of milliseconds before proceeding.')
		(array 'if' 'control#if' 'Runs the first set of blocks whose test condition is true.')
		(array 'whenCondition' 'control#when' 'Runs the blocks below when the given condition becomes true.')
		(array 'waitUntil' 'control#wait-until' 'Waits until the given condition becomes true before execution proceeds to the next block in the sequence.')
		(array 'return' 'control#return' 'Stops execution of the script and returns the given value as a result.')
		(array 'whenBroadcastReceived' 'control#when-received' 'Runs the blocks below when the given message is broadcast. (The message is a fixed string.)')
		(array 'sendBroadcast' 'control#broadcast' 'Broadcasts the given message.')
		(array 'comment' 'control#comment' 'This block does not do anything. It is used to add notes and documentation to scripts.')
		(array 'for' 'control#for' 'Runs the enclosed blocks the given number of times with the given variable set to the iteration number.')
		(array 'repeatUntil' 'control#repeat-until' 'Runs the enclosed blocks until the given condition becomes true.')
		(array 'stopTask' 'control#stop-this-task' 'Stops running this script. If the script is a function, stop the entire chain of functions that called it.')
		(array 'stopAll' 'control#stop-other-tasks' 'Stops all running scripts except the one that ran this block.')
		(array 'waitMicros' 'control#wait-microsecs' 'Waits the given number of microseconds before proceeding.')
		(array 'getLastBroadcast' 'control#last-message' 'Reports the last message received as a result of a broadcast block.')
		(array 'callCustomCommand' 'control#xxx' '')
		(array 'callCustomReporter' 'control#xxx' '')

		// OPERATORS
		(array '+' 'operators#' 'Returns the sum of the given numbers.')
		(array '-' 'operators#' 'Returns the first number minus the second.')
		(array '*' 'operators#' 'Returns the product of the given numbers.')
		(array '/' 'operators#' 'Returns the first number divided by the second. The second number must not be zero.')
		(array '%' 'operators#modulus' ' Returns the remainder of dividing the first number by the second.  The second number must not be zero.')
		(array 'absoluteValue' 'operators#' ' Returns the magnitude of the given number (always >= 0). ')
		(array 'minimum' 'operators#' ' Returns the smaller of the values. ')
		(array 'maximum' 'operators#' ' Returns the larger of the values. ')
		(array 'random' 'operators#random' ' Returns a randomly chosen number between the first and second values. ')
		(array '<' 'operators#' ' Returns (-o) if the first value is smaller than the second one. ')
		(array '<=' 'operators#' ' Returns (-o) if the first value is smaller than or equal to the second one. ')
		(array '==' 'operators#' ' Returns (-o) if both values are equal. ')
		(array '!=' 'operators#' ' Returns (-o) if the two values are not equal. ')
		(array '>=' 'operators#' ' Returns (-o) if the first value is greater than or equal to the second one. ')
		(array '>' 'operators#' ' Returns (-o) if the first value is greater than the second one. ')
		(array 'booleanConstant' 'operators#boolean-true/false' ' Boolean Constant: (-o) or (o-) depending on the position of the selector. ')
		(array 'not' 'operators#boolean-not' ' Returns the logical inverse of the given boolean (e.g. "not (-o) " returns (o-) ) ')
		(array 'and' 'operators#boolean-and' ' Returns (-o) only if both values are (-o) .')
		(array 'or' 'operators#boolean-or' ' Returns (-o) if either or both values are (-o) . ')
		(array 'isType' 'operators#is-type' ' Returns (-o) if first input is a value of the given data type.')
		(array 'hexToInt' 'operators#hex' ' Returns the value of the given hexadecimal string (range: -0x1FFFFFFF to 0x1FFFFFFF)')
		(array '&' 'operators#bitwise-and' ' Returns the bitwise AND of two numbers. ')
		(array '|' 'operators#bitwise-or' ' Returns the bitwise OR of two numbers. ')
		(array '^' 'operators#bitwise-xor' ' Returns the bitwise XOR (exclusive OR) of two numbers. ')
		(array '~' 'operators#bitwise-not' ' Returns the bitwise NOT (inverse) of the given number. ')
		(array '<<' 'operators#bitwise-left-shift' ' Returns the LEFT SHIFT of the given number by the given amount. ')
		(array '>>' 'operators#bitwise-right-shift' ' Returns the RIGHT SHIFT (arithmetic) of the given number by the given amount. ')

		// VARIABLES
		(array 'v' 'variables#xxx' '')
		(array '=' 'variables#set-variable' 'Sets a variable to the given value.')
		(array '+=' 'variables#change-variable' 'Changes the value of a variable by the given amount.')
		(array 'local' 'variables#initialize-local' 'Creates a local variable initialized to the given value. The variable is only visible in the containing script.')

		// DATA
		(array 'at' 'data#item' 'Returns the Nth item of a list, string, or byte array.')
		(array 'size' 'data#length-of' 'Returns the number of items in a list, string, or byte array.')
		(array '[data:join]' 'data#join' 'Joins (concatenates) strings, lists or byte arrays and returns the result.')
		(array '[data:makeList]' 'data#list' 'Returns a short list containing the given items.')
		(array '[data:addLast]' 'data#add-to-list' 'Adds an item to the end of a list.')
		(array 'atPut' 'data#repllace-item' 'Replaces the Nth item of a list with the given value. Can also replace all items with a value.')
		(array '[data:delete]' 'data#delete-item' 'Deletes the Nth item of a list. The resulting list is reduced in size. Can also delete all items.')
		(array '[data:find]' 'data#find' 'Returns the location of a substring within a string or an item in a list. Returns -1 if not found.')
		(array '[data:copyFromTo]' 'data#copy' 'Returns a copy of a list, string, or byte array containing the items in the given index range.')
		(array '[data:split]' 'data#split' 'Returns a list of strings created of splitting the given string by a delimiter string. ')
		(array '[data:joinStrings]' 'data#join-items-of-list' 'Combines the items of a list into a string, optionally separated by a delimiter.')
		(array '[data:unicodeAt]' 'data#unicode' 'Returns the Unicode value ("code point") of the Nth character of the given string.')
		(array '[data:unicodeString]' 'data#string-from-unicode' 'Returns a string containing the given Unicode value ("code point") or list of Unicode values.')
		(array 'newList' 'data#new-list' 'Returns a new list of the given length. All items are set to zero or the optional value.')
		(array '[data:newByteArray]' 'data#new-byte-array' 'Returns a new byte array of the given length. All byte are set to zero or the optional value.')
		(array '[data:asByteArray]' 'data#as-byte-array' 'Returns a byte array of the string in the input area.')
		(array '[data:freeMemory]' 'data#free-memory' 'Returns the number of 32-bit words of dynamic memory available. The IDE Stop button clears all variables and frees up memory.')
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
