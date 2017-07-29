# Microblocks Serial Protocol (version 2)

This protocol describes how information should flow from the board to the
IDE and the other way around. All messages are encoded into a byte array
and start with a pair of flag bytes that indicate the beginning of a new
message. The second flag byte also indicates whether the message is a
fixed size (4 byte) message or a message with a variable number of data
bytes. The third byte is an OpCode that specifies the message type.
For many messages, the fourth byte is a chunk ID indicating the stack
of blocks that is the subject of the message. That field can also be
used to indicate a pin number or global variable index when we implement
watchers.

Short message format (4 bytes):

[0xF8, 0xFA, OpCode, ChunkID]

Long message format (6 + dataSize bytes):

[0xF8, 0xFB, OpCode, ChunkID, DataSize (2 bytes, LSB first), Data]

## IDE → Board (OpCodes 0x01 to 0x07)

### Store Chunk (OpCode: 0x01; long message)

Set the code for the given chunkID to the given data.

### Delete Chunk (OpCode: 0x02)

Remove the code for the given chunkID. Stop any associated with the given chunkID.
After this operation the chunkID can be recycled.

Note: When deleting a procedure chunk, care must be taken that no call
to that procedure is in progress. It would probably be safest for the IDE
to stop all tasks before deleting a procedure chunk.

### Start Chunk (OpCode: 0x03)

Start a task for the given chunk. If there is already a task for this chunk,
abort and restart it.

### Stop Chunk (OpCode: 0x04)

Stop the task for the given chunk. Do nothing there is no task for the given chunk.

### Start All (OpCode: 0x05)

Start tasks for "when started" hats and start polling "when <condition>" hats.

### Stop All (OpCode: 0x06)

Stop all tasks and stop polling "when <condition>" hats.

### System Reset (OpCode: 0x10)

Stop all tasks and reset the hardware.

### Delete All Chunks (OpCode: 0x11)

Stop all tasks and delete all chunks from the board.


## Board → IDE (OpCodes 0x20 to 0x24)

The board sends these messages when tasks start and stop or when other events
of interest occur. The board sends these messages without being asked and
regardless of whether it is tethered.

### Task Started (OpCode: 0x20)

A task was started for the given chunk.

### Task Error (OpCode: 0x21, long message)

The task associated with the given chunk got an error.
The data part of the message is a one-byte error code.

### Task Done (OpCode: 0x22)

The task for the given chunk completed. It did not return a value.

### Task Returned Value (OpCode: 0x23, long message)

The task for the given chunk completed and returned a value.
The data part of the message consists of a one-byte type flag
followed by the return value. The data types are:

  * integer (type = 1)
  * string (type = 2)

### Console Log String (OpCode: 0x24, long message)

Output the string in the data part of this message to the console. Used for debugging.


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
