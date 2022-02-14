// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksHelp.gp - Help string table.
// John Maloney, November 2021

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
		(array 'millisOp' 'input#milliseconds' 'Report the milliseconds since power up.')
		(array 'microsOp' 'input#microseconds' 'Report the microseconds since power up.')
		(array 'boardType' 'input#board-type' 'Report the board type.')

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
		(array '[sensors:spiSetup]' 'comm#xxx' 'Set the SPI clock speed and mode.')
		(array '[sensors:spiExchange]' 'comm#xxx' 'Send a byte array via SPI, replacing its contents with the bytes received.')
		(array '[serial:open]' 'comm#serial-open' 'Open the serial port at the given baud rate.')
		(array '[serial:close]' 'comm#serial-close' 'Close the serial port.')
		(array '[serial:read]' 'comm#serial-read' 'Report data received from the serial port (a byte array).')
		(array '[serial:write]' 'comm#serial-write' 'Send a byte array to the serial port.')

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
		(array 'whenBroadcastReceived' 'control#when-received' 'Run when the given message is broadcast.')
		(array 'sendBroadcast' 'control#broadcast' 'Broadcast the given message.')
		(array 'comment' 'control#comment' 'Do nothing. Used to add notes and documentation.')
		(array 'for' 'control#for' 'Repeat the enclosed blocks with the variable set to the current iteration number or item.')
		(array 'repeatUntil' 'control#repeat-until' 'Repeat the enclosed blocks until the condition becomes (-o) .')
		(array 'stopTask' 'control#stop-this-task' 'Stop this task.')
		(array 'stopAll' 'control#stop-other-tasks' 'Stop all tasks except this one.')
		(array 'waitMicros' 'control#wait-microsecs' 'Wait the given number of microseconds.')
		(array 'getLastBroadcast' 'control#last-message' 'Report the last broadcast message received.')
		(array 'callCustomCommand' 'control#xxx' 'Call the function with the given name and optional parameter list.')
		(array 'callCustomReporter' 'control#xxx' 'Call the function with the given name and optional parameter list and report its return value.')

		// OPERATORS
		(array '+' 'operators#' 'Report the sum of the given numbers.')
		(array '-' 'operators#' 'Report the first number minus the second.')
		(array '*' 'operators#' 'Report the product of the given numbers.')
		(array '/' 'operators#' 'Report the first number divided by the second.')
		(array '%' 'operators#modulus' 'Report the remainder of dividing the first number by the second.')
		(array 'absoluteValue' 'operators#' 'Report the absolute value of the given number (always >= 0).')
		(array 'minimum' 'operators#' 'Report the minimum of the values.')
		(array 'maximum' 'operators#' 'Report the maximum of the values.')
		(array 'random' 'operators#random' 'Report a randomly chosen number in the given range.')
		(array '<' 'operators#' 'Report (-o) if the first value is less than the second one.')
		(array '<=' 'operators#' 'Report (-o) if the first value is less than or equal to the second one.')
		(array '==' 'operators#' 'Report (-o) if the two values are equal.')
		(array '!=' 'operators#' 'Report (-o) if the two values are not equal.')
		(array '>=' 'operators#' 'Report (-o) if the first value is greater than or equal to the second one.')
		(array '>' 'operators#' 'Report (-o) if the first value is greater than the second one.')
		(array 'booleanConstant' 'operators#boolean-true/false' 'Boolean constant ( (-o) or (o-) ).')
		(array 'not' 'operators#boolean-not' 'Report the logical inverse of a Boolean ( (-o) or (o-) ) value.')
		(array 'and' 'operators#boolean-and' 'Report (-o) if both values are (-o)')
		(array 'or' 'operators#boolean-or' 'Report (-o) if either value is (-o)')
		(array 'isType' 'operators#is-type' 'Report (-o) if first input is a value of the given data type.')
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
		(array '[data:asByteArray]' 'data#as-byte-array' 'Report a byte array cointaining the UTF-8 bytes of the given string.')
		(array '[data:freeMemory]' 'data#free-memory' 'Report the number of words of memory available. Stop button frees up memory.')
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
