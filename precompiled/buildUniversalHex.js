var mbUniveralHex = require('@microbit/microbit-universal-hex'),
    fs = require('fs');

var universalHex = mbUniveralHex.createUniversalHex([
  {
    hex: fs.readFileSync('vm_microbitV1.hex').toString(),
    boardId: mbUniveralHex.microbitBoardId.V1,
  },
  {
    hex: fs.readFileSync('vm_microbitV2.hex').toString(),
    boardId: mbUniveralHex.microbitBoardId.V2,
  },
]);

fs.writeFileSync('vm_microbit-universal.hex', universalHex);
