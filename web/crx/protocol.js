var protocol = {
    0x75: {
        description: "A thread has just started running",
        origin: "board",
        carriesData: false
    },
    0x7D: {
        description: "A thread has just stopped running",
        origin: "board",
        carriesData: true
    },
    0x7E: {
        description: "An error has occurred inside a thread",
        origin: "board",
        carriesData: true,
        dataDescriptor: {
            0xD0: "Division by zero",
            0x6E: "Generic Error"
        }
    },
    0x7C: {
        description: "The IDE wants to kill a thread",
        origin: "ide",
        carriesData: false
    },
    0x5A: {
        description: "The IDE wants to stop all threads",
        origin: "ide",
        carriesData: false
    },
    0x1A: {
        description: "The IDE requests the value of a variable",
        origin: "ide",
        carriesData: false
    },
    0x10: {
        description: "The IDE requests the state of an I/O pin",
        origin: "ide",
        carriesData: false
    },
    0xB5: {
        description: "The board sends back the value of a variable or an I/O pin",
        origin: "board",
        carriesData: true
    },
    0x5C: {
        description: "A script is sent to the board",
        origin: "ide",
        carriesData: true
    }
}
