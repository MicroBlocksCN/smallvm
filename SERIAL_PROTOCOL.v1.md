# µBlocks serial protocol

The protocol describes how information should flow from the board to the IDE and the other way around. All messages are encoded into a byte array and start with an OpCode that specifies what kind of information we're dealing with. The following byte encodes the ID of the object that the message either originated from or is directed to.

Message format:

[Operation Code, Object ID, Data Size (2 bytes), Data]

### A thread has just started running.

Direction: Board → IDE

OpCode: 0x75 (mnemonic: 7hread 5tarted)

This message carries no data.

### A thread has just stopped running.

Direction: Board → IDE

OpCode: 0x7D (mnemonic: 7hread Died)

If the thread has a value to report, it's carried along in the return message. Otherwise, the data size bytes will be zero.

### An error has occurred inside a thread.

Direction: Board → IDE

OpCode: 0x7E (mnemonic: 7hread Error)

This message carries the error code back to the IDE.

### The IDE wants to kill a thread.

Direction: IDE → Board

OpCode: 0x7C (mnemonic: 7hread Cancel)

This message carries no data.

### The IDE wants to stop all threads

Direction: IDE → Board

OpCode: 0x5A (mnemonic: 5top All)

### The IDE requests the value of a variable

Direction: IDE → Board

OpCode: 0x1A (mnemonic: 1DE Asks)

This message carries no data.

### The IDE requests the state of an I/O pin

Direction: IDE → Board

OpCode: 0x10 (mnemonic: I/O)

This message carries no data.

### The board sends back the value of a variable or an I/O pin

Direction: Board → IDE

OpCode: 0xB5 (mnemonic: Board Sends)

This message carries the value back to the IDE.

### A script is sent to the board

Direction: IDE → Board

OpCode: 0x5C (mnemonic: Script Contents)

This message carries the whole script ByteCode as data.

## Example Use Cases

### Running a script

1) IDE → Board : [0x5C, 0x01, 0x14, 0x02, 0x00, 0x05, 0x00, 0x02, 0x0F, 0x42, 0x40, ...] →  The script contents are being sent to the board.

2) Board → IDE : [0x75, 0x01] → The thread corresponding to script 0x01 has just started. The interpreter will start the script after sending this message.

3) Board → IDE : [0x7D, 0x01, 0x00, 0x00] → The thread corresponding to script 0x01 has just died and it didn't return any value.

### Running a script that divides by zero

1) IDE → Board : [0x5C, 0x02, 0x...] → The script contents are being sent to the board.

2) Board → IDE : [0x75, 0x02] → The thread corresponding to script 0x02 has just started. The interpreter will start the script after sending this message.

3) Board → IDE : [0x7E, 0x02, 0x00, 0x01, 0xD0] → An error has occurred while running thread corresponding to script 0x02. Its error code is 0xD0.

### Requesting the value of a reporter

1) IDE → Board : [0x5C, 0x03, 0x08, 0x00, 0x02...] → The script contents are being sent to the board.

2) Board → IDE : [0x75, 0x03] → The thread corresponding to script 0x03 has just started. The interpreter will start the script after sending this message.

3) Board → IDE : [0x7D, 0x03, 0x00, 0x01, 0x30] → The thread corresponding to script 0x03 has just died. It returned one single byte with value 0x30.
