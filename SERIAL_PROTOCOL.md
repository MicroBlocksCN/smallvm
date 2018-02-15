# Microblocks Serial Protocol (version 2.07)

This protocol describes how information flows from the
board to the IDE and the other way around. All messages
are encoded into a byte array and start with a flag
byte that indicates the beginning of a new message. The
flag byte also indicates whether the message is fixed size
(3 bytes) or variable size. The second byte is an OpCode that
specifies the message type. For many messages, the third
byte is a ChunkID indicating the stack of blocks that is
the subject of the message.

If message framing is lost, perhaps because a byte was dropped,
the receiver discards incoming bytes until it sees one of the two
start flag bytes (0xFA or 0xFB) followed by an OpCode byte in
the range [1..0x1F]. Assuming byte values are uniformly distributed,
there is a 0.08% chance of falsely detecting a message start sequence.
In reality, the flag bytes were chosen to be uncommon; they are
not in the range of 7-bit ASCII and they are illegal byte values
in UTF-8 encoded strings. Thus, it is fairly likely that a legal
start sequence is, indeed, the beginning of a message.

The baud rate is 115.2 kbaud.

**Short message format (3 bytes):**

[0xFA, OpCode, ChunkOrVariableOrCommentID]

**Long message format (5 + dataSize bytes):**

[0xFB, OpCode, ChunkOrVariableOrCommentID, DataSize-LSB, DataSize-MSB, ...data...]

The data size field specifies the number of data bytes. It is encoded as two bytes, least significant byte first.

The incoming message buffer on the board sets a practical upper
limit on the data size of long messages. This sets the upper limit on the size of a single compiled chunk or source attribute.

**Terminator Byte**

To help the board detect dropped bytes, all long messages sent to the board
end with the terminator byte 0xFE. The data size field includes this terminator byte.
Dropped bytes in messages from the board to the IDE have not (so far) been a problem,
so long messages sent from the board to the IDE do not have a termination byte.

<br>
## IDE → Board (OpCodes 0x01 to 0x0F)

### Chunk Code (OpCode: 0x01; long message; bidirectional)

Body contains the binary code for the given chunkID.
This message is also used to return chunk code to the IDE
in response to the Get All Code message.

### Delete Chunk (OpCode: 0x02)

Delete the code for the given chunkID. Stop any running
task associated with the given chunkID. After this operation
the chunkID can be recycled.

Note: When deleting a procedure chunk, care must be taken
that no call to that procedure is in progress. It might
be best for the IDE to stop all tasks before
deleting a procedure chunk.

### Start Chunk (OpCode: 0x03)

Start a task for the given chunk. If there is already a task
for this chunk, abort and restart it.

### Stop Chunk (OpCode: 0x04)

Stop the task for the given chunk. Do nothing there is no task
for the given chunk.

### Start All (OpCode: 0x05)

Start tasks for "when started" hats and start polling
"when *condition*" hats.

### Stop All (OpCode: 0x06)

Stop all tasks and stop polling "when *condition*" hats.

### Get Variable Value (OpCode: 0x07)

Request the value for the variable given by the ID field.
The value is sent to the IDE with the Variable Value message.

### Set Variable Value (OpCode: 0x08; long message)

Set the value for the given variable to the value in the body.

The body consists of a one-byte type flag followed by the actual value.
The supported data types are:

  * integer (type = 1): 4-byte signed integer, LSB first
  * string (type = 2):  the remainder of the message body is a UTF-8 string
  * boolean (type = 3): 1-byte, 0 for false, 1 for true

### *Reserved* (OpCode 0x09)

Reserved for a future IDE->Board message.

### Delete Variable (OpCode: 0x0A)

Delete the given variable.

### Delete Comment (OpCode: 0x0B)

Delete the comment with the given ID.

### Get Virtual Machine Version (OpCode: 0x0C)

Request the virtual machine version and board type.
The result is sent to the IDE with the Virtual Machine Version message.

### Get All Code (OpCode: 0x0D)

Request all stored code, including both binary code and attributes such as source strings and variable names, to be sent to the IDE.

### Delete All Code (OpCode: 0x0E)

Stop all tasks and delete all code and code attributes from the board.

### System Reset (OpCode: 0x0F)

Stop all tasks and reset/restart the hardware.

Note: With the interim RAM-based chunk storage
implementation, this will also delete all chunks.
However, when persistent chunk storage is
implemented, it will just reset the hardware;
the program will persist.

<br>
## Board → IDE (OpCodes 0x10 to 0x16)

The board sends task status change and output messages
without being asked and regardless of whether it is tethered.

### Task Started (OpCode: 0x10)

A task was started for the given chunk.

### Task Done (OpCode: 0x11)

The task for the given chunk completed. It did not return a value.

### Task Returned Value (OpCode: 0x12, long message)

The task for the given chunk completed and returned the value in the body of this message.
The value is encoded the same as in the Set Variable Value message.

### Task Error (OpCode: 0x13, long message)

The task associated with the given chunk got an error.
The data part of the message is a one-byte error code followed
by a four-byte integer that encodes the current chunkID (which may be
a procedure chunk, not necessarily the top-level chunk for the task),
and the IP address within that chunk. The format is:

	[IP within chunk (high 24-bits)][chunk ID (low 8-bits)]

The list of errors will grow as new features are added to the virtual machine.
The error codes are defined by the source code file interp.h.

### Output Value (OpCode: 0x14, long message)

Outputs the value in the data part of this message. The value is
encoded the same was as the Task Returned Value message.

### Variable Value (OpCode: 0x15, long message)

Return the value of the given variable in the data part of this message.
The variable is given by the ID field.
The value is encoded the same as in the Set Variable Value message.

### Virtual Machine Version (OpCode: 0x16, long message)

Return the version string in the body of this message.

### *Reserved* (OpCodes 0x17-0x19)

Reserved for additional Board → IDE messages.

<br>
## Bidirectional (OpCode: 0x1A to 0x1F)

### Ping (OpCode: 0x1A)

When the IDE sends a Ping message, and the board responds with a Ping message.
This exchange is used to make sure that the board is still connected.

### Broadcast (OpCode: 0x1B, long message)

Transmit a broadcast message from board to IDE or vice versa.
The body of the message is the broadcast string.

### Chunk Attribute (OpCode: 0x1C, long message)

The body of the message is an attribute for chunk with the given ID.
The first byte of the body is the attribute type, current:

  * 0: the chunk position in the scripting pane. Body is four bytes encoding two unsigned, 16-bit integers, LSB first, for the x and y offset
  * 1: snap source code (body is a string )
  * 2: GP source code (body is a string)

### Variable Name (OpCode: 0x1D, long message)

The name of the variable with the given ID. Body is a string.

### Comment (OpCode: 0x1E, long message)

A comment the given ID. Body is a string.

### Comment Position (OpCode: 0x1F, long message)

The offset of the comment with the given ID in the scripting pane.
The position is encoded as 4 bytes in the same manner as the chunk position attribute.

<br>
## IDE → Bridge, Bridge → IDE

0xFF is reserved for all messages between the bridge and the IDE.

In this case, the message data will be a JSON object of the form:

    { selector: aMethorSelector, arguments: [ arg1, arg2, ... ] }.

### Get Serial Port List (selector: getSerialPortList)

### Serial Port List Response (selector: getSerialPortListResponse)

### Serial Connect Request (selector: serialConnect)

### Serial Connect Response (selector: serialConnectResponse)

### Serial Disconnect Request (selector: serialDisconnect)

### Serial Disconnect Response (selector: serialDisconnectResponse)
