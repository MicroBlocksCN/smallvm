var mbUniveralHex = require('@microbit/microbit-universal-hex'),
    fs = require('fs');

var universalHex = mbUniveralHex.createUniversalHex([
  {
    hex: fs.readFileSync('vm.microbit.hex').toString(),
    boardId: mbUniveralHex.microbitBoardId.V1,
  },
  {
    hex: fs.readFileSync('vm.microbitV2.hex').toString(),
    boardId: mbUniveralHex.microbitBoardId.V2,
  },
]);

fs.writeFileSync('vm.microbit-universal.hex', universalHex);
