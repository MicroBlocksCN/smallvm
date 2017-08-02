# Microblocks Serial Protocol (version 2.02)

This protocol describes how information flows from the
board to the IDE and the other way around. All messages
are encoded into a byte array and start with a flag
byte that indicates the beginning of a new message. The
flag byte also indicates whether the message is fixed size
(3 bytes) or variable size. The second byte is an OpCode that
specifies the message type. For many messages, the third
byte is a ChunkID indicating the stack of blocks that is
the subject of the message. That field is also used to indicate
a pin number or global variable index to support watchers.

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

[0xFA, OpCode, ChunkID]

**Long message format (5 + dataSize bytes):**

[0xFB, OpCode, ChunkID, DataSize-LSB, DataSize-MSB, ...data...]

The data size field specifies the number of data bytes. It is encoded as two bytes, least significant byte first.

The incoming message buffer on the board sets a practical upper
limit on the data size. All boards should be able receive messages with at least 250 bytes of data. This sets the upper limit on the size of a single compiled chunk.

<br>
## IDE → Board (OpCodes 0x01 to 0x1F)

### Store Chunk (OpCode: 0x01; long message)

Set the code for the given chunkID to the given data.

### Delete Chunk (OpCode: 0x02)

Remove the code for the given chunkID. Stop any running
task associated with the given chunkID. After this operation
the chunkID can be recycled.

Note: When deleting a procedure chunk, care must be taken
that no call to that procedure is in progress. It would
probably be safest for the IDE to stop all tasks before
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

### Request Digital Pin (OpCode: 0x07)

Request the value of a digital pin specified by the ChunkID field.

### Request Analog Pin (OpCode: 0x08)

Request the value of the analog pin specified by the ChunkID field.

### Request Variable (OpCode: 0x09)

Request the value of the global variable whose index is
specified by the ChunkID field.

### Reserved (OpCodes 0x0A-0x0D)

Reserved for additional non-system messages.

### Delete All Chunks (OpCode: 0x0E)

Stop all tasks and delete all chunks from the board.

### System Reset (OpCode: 0x0F)

Stop all tasks and reset the hardware.

Note: With the interim RAM-based chunk storage
implementation, this will also delete all chunks.
However, when persistent chunk storage is
implemented, it will just reset the hardware;
the program will persist.

<br>
## Board → IDE (OpCodes 0x10 to 0x1F)

The board sends task status change and
console log messages without being asked and
regardless of whether it is tethered.
The board sends pin and variable values only in
response to requests from the IDE.

### Task Started (OpCode: 0x10)

A task was started for the given chunk.

### Task is Polling (OpCode: 0x11)

The given chunk is a "when *condition*" hat that is
polling (i.e. testing its condition).

Note: When the condition becomes true, a "Task Started"
message will be sent. When that task completes and the
chunk returns to the polling state, a "Task is Polling"
message is sent. This allows the IDE to show the difference
between stopped, polling, and running (e.g. with different
colored highlights around the block stack).

### Task Done (OpCode: 0x12)

The task for the given chunk completed. It did not return a value.

### Task Returned Value (OpCode: 0x13, long message)

The task for the given chunk completed and returned a value.
The data part of the message consists of a one-byte type flag
followed by the return value. The current type flags are:

  * integer (type = 1; data is 4-byte signed integer, LSB first)
  * boolean (type = 2; data is 1-byte, 0 for false, 1 for true)
  * string (type = 3; data is a UTF-8 string)

### Task Error (OpCode: 0x14, long message)

The task associated with the given chunk got an error.
The data part of the message is a one-byte error code.

### Console Log String (OpCode: 0x15, long message)

Logs the string in the data part of this message to the
console. Used for debugging.

### Reserved (OpCode 0x16)

Reserved for a future Board → IDE message.

### Digital Pin Value (OpCode: 0x17, long message)

Returns the boolean value of the digital pin
specified by the ChunkID field. Data is a type and
value as described in "Task Returned Value".

### Analog Pin Value (OpCode: 0x18, long message)

Returns the integer value of the analog pin
specified by the ChunkID field. Data is a type and
value as described in "Task Returned Value".

### Variable Value (OpCode: 0x19, long message)

Returns the value of the global variable whose index is
specified by the ChunkID field. Data is a type and
value as described in "Task Returned Value".

### Reserved (OpCodes 0x1A-0x1F)

Reserved for additional Board → IDE messages.
