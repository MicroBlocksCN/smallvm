import serial
import time

class MicroblocksMessage:
	def __init__(self):
		self.ser = None
		self._buffer = bytearray()

	def connect(self, port):
		self.ser = serial.Serial(port, 115200)

	def disconnect(self):
		self.ser.close()

	def sendBroadcast(self, aString):
		utf8 = aString.encode('utf-8')
		length = len(utf8) + 1
		bytes = bytearray([251, 27, 0, length % 256, int(length / 256)]) + utf8 + b'\xfe'
		self.ser.write(bytes)

	def receiveBroadcasts(self):
		result = []
		data = self.ser.read()
		if data:
			self._buffer = self._buffer + data
			for msgBytes in self._match(27):
				result.append(msgBytes[4 :].decode("utf-8"))
		return result

	def _match(self, filter="*"):
		buf = self._buffer
		result = []
		bytesRemaining = None
		cmd = None
		msgLen = None
		end = None
		length = len(buf)
		i = 0
		while True:
			while not ((i >= length) or (buf[i] == 250) or (buf[i] == 251)):
				i += 1 # skip to start of next message
			bytesRemaining = length - i
			if (bytesRemaining < 1): # nothing to process
				self._buffer = buf[i :]
				return result
			cmd = buf[i]
			if (cmd == 250) and (bytesRemaining >= 3): # short message (3 bytes)
				if (filter == '*') or (filter == buf[i + 1]):
					result.append(buf[i : i + 3])
				i += 3
			elif (cmd == 251) and (bytesRemaining >= 5): # long message (>= 5 bytes)
				msgLen = (256 * buf[i + 4]) + buf[i + 3]
				end = i + 5 + msgLen
				if end > length: # long message is not yet complete
					self._buffer = buf[i :]
					return result
				if (filter == '*') or (filter == buf[i + 1]):
					result.append(buf[i : end])
				i = end
			else:
				self._buffer = buf[i :]
				return result


m = MicroblocksMessage()
m.connect('/dev/tty.usbmodem2102') # replace the string with micro:bit port

# broadcast messages from Python to MicroBlocks
m.sendBroadcast('sad')
time.sleep(1)
m.sendBroadcast('happy')
time.sleep(1)
m.sendBroadcast('clear')

# receive broadcasts from MicroBlocks
while True:
	for msg in m.receiveBroadcasts():
		print(msg)
