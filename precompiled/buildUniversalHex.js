var mbUniveralHex = require('@microbit/microbit-universal-hex'),
    fs = require('fs');

fs.writeFileSync(
    'vm_microbit-universal.hex',
    mbUniveralHex.createUniversalHex([
        {
            hex: fs.readFileSync('vm_microbitV1.hex').toString(),
            boardId: mbUniveralHex.microbitBoardId.V1,
        },
        {
            hex: fs.readFileSync('vm_microbitV2.hex').toString(),
            boardId: mbUniveralHex.microbitBoardId.V2,
        }
    ])
);

fs.writeFileSync(
    'vm_calliope-universal.hex', 
    mbUniveralHex.createUniversalHex([
        {
            hex: fs.readFileSync('vm_calliope.hex').toString(),
            boardId: 0x9900,
        },
        {
            hex: fs.readFileSync('vm_calliopeV3.hex').toString(),
            boardId: 0x9903,
        },
    ])
);

