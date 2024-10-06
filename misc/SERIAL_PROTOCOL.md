# Microblocks Serial Protocol (version 2.09)

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

[0xFA, OpCode, ChunkOrVariableID]

**Long message format (5 + dataSize bytes):**

[0xFB, OpCode, ChunkOrVariableID, DataSize-LSB, DataSize-MSB, ...data...]

The data size field specifies the number of data bytes. It is encoded as two bytes, least significant byte first.

The incoming message buffer on the board sets a practical upper
limit on the data size of long messages. This sets the upper limit on the size of a single compiled chunk or source attribute.

**Terminator Byte**

To help the board detect dropped bytes, all long messages sent to the board
end with the terminator byte 0xFE. The data size field includes this terminator byte.
Dropped bytes in messages from the board to the IDE have not (so far) been a problem,
so long messages sent from the board to the IDE do not have a termination byte.


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

As a short message, request the value for the variable given by the ID field.
As a long message, request the value for the variable with the name given in the
body.

The value is sent to the IDE with the Variable Value message.

### Set Variable Value (OpCode: 0x08; long message)

Set the value for the given variable to the value in the body.

The body consists of a one-byte type flag followed by the actual value.
The supported data types are:

  * integer (type = 1): 4-byte signed integer, LSB first
  * string (type = 2):  the remainder of the message body is a UTF-8 string
  * boolean (type = 3): 1-byte, 0 for false, 1 for true

### Get Variable Names (OpCode 0x09)

Report the names of all variables.
Results are sent to the IDE as a sequence of Variable Name messages.

### Clear Variables (OpCode: 0x0A)

Clear all variable name records.
This message is sent by the IDE when a variable is deleted, followed
by a sequence of Variable Name messages to record the new variable bindings,
if any.

### Get CRC (OpCode: 0x0B)

Request the CRC-32 (cyclic redundancy check) of the given chunk. Board responds with a Chunk CRC message.

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

Outputs the value in the data part of this message.
The value is encoded the same as in the Set Variable Value message.

### Variable Value (OpCode: 0x15, long message)

Return the value of the given variable in the data part of this message.
The variable is given by the ID field.
The value is encoded the same as in the Set Variable Value message.

### Virtual Machine Version (OpCode: 0x16, long message)

Return the version string in the body of this message.

### Chunk CRC (OpCode: 0x17, long message)

Return the four-byte CRC-32 (cyclic redundancy check) of the given chunk.

### *Reserved* (OpCodes 0x18-0x19)

Reserved for additional Board → IDE messages.


## Bidirectional (OpCode: 0x1A to 0x1F)

### Ping (OpCode: 0x1A)

When the IDE sends a Ping message, and the board responds with a Ping message.
This exchange is used to make sure that the board is still connected.

### Broadcast (OpCode: 0x1B, long message)

Transmit a broadcast message from board to IDE or vice versa.
The body of the message is the broadcast string.

### Chunk Attribute (OpCode: 0x1C, long message)

[Deprecated; support has been removed.]

The body of the message is an attribute for chunk with the given ID.
The first byte of the body is the attribute type, current:

  * 0: the chunk position in the scripting pane. Body is four bytes encoding two unsigned, 16-bit integers, LSB first, for the x and y offset
  * 1: snap source code (body is a string )
  * 2: GP source code (body is a string)

### Variable Name (OpCode: 0x1D, long message)

The name of the variable with the given ID. Body is a string.

### Extended Message (OpCode: 0x1E, long message)

The ID specifies the extended message type. The format depends on the message type:

  * 1: set the per-byte delay for 'say' and 'graph' blocks. Body is one-byte value in the range 1-50.

### Enable BLE (OpCode: 0x1F)

Sent from IDE to board to enable or disable the ability to connect to the board via BLE.
If the third byte of this message is 0, BLE connections are disabled. If non-zero, they are enabled.
Ignored by boards that do not support BLE.

### Chunk Code 16-bit (OpCode: 0x20; long message; bidirectional)

Body contains the 16-bit binary code for the given chunkID.
This message is also used to return chunk code to the IDE
in response to the Get All Code message.


### *Reserved* (OpCodes 0x20-0x25)

Reserved for additional Bidirectional messages.


## CRC Exchange

### Get All CRCs (OpCode: 0x26, IDE → Board)

Ask the board to send the CRC's for all chunks.

### All CRCs (OpCode: 0x27, Board → IDE)

A message containing the CRCs for all chunks on the board.

Each CRC record is 5 bytes: <chunkID (one byte)><CRC (four bytes)>


## File Transfer Messages (OpCode: 200 to 205)

### Delete File (OpCode: 200, long message) (IDE → Board)

Delete a file. Message body is the file name.

### List Files (OpCode: 201) (IDE → Board)

Send a sequence of File Info messages for the files on the board.

### File Info (OpCode: 202, long message) (Board → IDE)

File info List Files. Body contains the file size (4-byte int) followed by the file name.

### Start Reading File from Board (OpCode: 203, long message) (IDE → Board)

Tell the board to send a file.
Body contains the a randomly chosen transfer ID (4-byte int) followed by the file name.
File contents are sent to the board as a sequence of file chunks

### Start Writing File to Board (OpCode: 204, long message) (IDE → Board)

Tell the board to prepare to receive a file.
Body contains the a randomly chosen trasfer ID (4-byte int) followed by the file name.
File contents are sent to the board as a sequence of file chunks

### File Chunk (OpCode: 205, long message) (bidirectional)

One chunk of a file.
Body contains: transfer ID (4-byte int), byte offset (4-byte int), followed by the data bytes.
The final chunk in the sequence contains no data bytes, indicating the end of the file.
