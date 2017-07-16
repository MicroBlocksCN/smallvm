/*

    ucompile.js

    a simple byte-code compiler for the µblocks VM


    written by John Maloney, Jens Mönig, and Bernat Romagosa
    jens@moenig.org

    Copyright (C) 2017 by John Maloney, Jens Mönig, Bernat Romagosa

    This file is part of Snap!.

    Snap! is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as
    published by the Free Software Foundation, either version 3 of
    the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.


    prerequisites:
    --------------
    needs blocks.js and objects.js


    toc
    ---
    the following list shows the order in which all constructors are
    defined. Use this list to locate code in this document:

        Compiler


    credits
    -------
    John Maloney designed the original µblocks bytecode system

*/

// Global stuff ////////////////////////////////////////////////////////

/*global modules, CommandBlockMorph, ReporterBlockMorph, ArgMorph,
isNil, isString, contains, console*/

modules.ucompile = '2017-May-30';

var Compiler;

// Compiler ///////////////////////////////////////////////////////

function Compiler() {
    this.globals = {};
}

// Compiler settings

Compiler.prototype.trueObj = 4;
Compiler.prototype.falseObj = 8;

Compiler.prototype.selectors = {
    // maps Snap's selectors to µblocks' ops
    doPauseAll: 'halt',
    // incrementLocal
    // callFunction
    // returnResult
    // waitMicrosOp
    // waitMillisOp
    bubble: 'printIt',
    doStopDevice: 'stopAll',
    reportSum: 'add',
    reportDifference: 'subtract',
    reportProduct: 'multiply',
    reportQuotient: 'divide',
    reportDeviceLessThan: 'lessThan',
    // reportEquals =>
    // reportGreaterThan =>
    reportNewList: 'newArray',
    // newByteArray
    // fillArray
    reportListItem: 'at',
    doReplaceInList: 'atPut'
    // analogReadOp
    // analogWriteOp
    // digitalReadOp
    // digitalWriteOp
    // setLEDOp
    // microsOp
    // millisOp
    // peekOp
    // pokeOp
};

Compiler.prototype.opcodes = {
    halt: 0,
    noop: 1,
    pushImmediate: 2, // true, false, and ints that fit in 24 bits
    pushBigImmediate: 3, // ints that do not fit in 24 bits (and later, floats)
    pushLiteral: 4, // string or array constant from literals frame
    pushVar: 5,
    popVar: 6,
    incrementVar: 7,
    pushArgCount: 8,
    pushArg: 9,
    pushLocal: 10,
    popLocal: 11,
    incrementLocal: 12,
    pop: 13,
    jmp: 14,
    jmpTrue: 15,
    jmpFalse: 16,
    decrementAndJmp: 17,
    callFunction: 18,
    returnResult: 19,
    waitMicrosOp: 20,
    waitMillisOp: 21,
    printIt: 22,
    stopAll: 23,
    add: 24,
    subtract: 25,
    multiply: 26,
    divide: 27,
    lessThan: 28,
    newArray: 29,
    newByteArray: 30,
    fillArray: 31,
    at: 32,
    atPut: 33,
    analogReadOp: 34,
    analogWriteOp: 35,
    digitalReadOp: 36,
    digitalWriteOp: 37,
    setLEDOp: 38,
    microsOp: 39,
    millisOp: 40,
    peekOp: 41,
    pokeOp: 42
};


// Compiler bytecode

Compiler.prototype.bytesFor = function (aBlock) {
    var code = this.instructionsFor(aBlock),
        bytes = [],
        myself = this;
    code.forEach(function (item) {
        if (item instanceof Array) {
            myself.addBytesForInstruction(item, bytes);
        } else if (Number.isInteger(item)) {
            myself.addBytesForInteger(item, bytes);
        } else if (isString(item)) {
            myself.addBytesForStringLiteral(item, bytes);
        } else {
            throw new Error('Instruction must be an Array or String', item);
        }
    });
    return bytes;
};

Compiler.prototype.addBytesForInstruction = function (instr, bytes) {
    // append the bytes for the given instruction to bytes (little endian)
    var arg = instr[1];
    bytes.push(this.opcodes[instr[0]]);
    if ((-8388608 <= arg) && (arg < 8388607)) {
        bytes.push(arg & 255);
        bytes.push((arg >> 8) & 255);
        bytes.push((arg >> 16) & 255);
    } else {
        throw new Error('Argument does not fit in 24 bits');
    }
};

Compiler.prototype.addBytesForInteger = function (n, bytes) {
    // append the bytes for the given instruction to bytes (little endian)
    bytes.push(n & 255);
    bytes.push((n >> 8) & 255);
    bytes.push((n >> 16) & 255);
    bytes.push((n >> 24) & 255);
};

Compiler.prototype.addBytesForStringLiteral = function (s, bytes) {
    // append the bytes for the given string to bytes
    var byteCount = this.byteCount(s),
        wordCount = this.wordCount(s),
        headerWord = (wordCount << 4) | 5,
        i;
    for (i = 0; i < 4; i += 1) { // repeat 4 times
        bytes.push(headerWord & 255);
        headerWord = (headerWord >> 8);
    }
    bytes.push.apply(bytes, this.str2bytes(s));
    for (i = 0; i < (4 - (byteCount % 4)); i += 1) {
        bytes.push(0); // pad with zeroes to next word boundary
    }
};

// Compiler instructions

Compiler.prototype.instructionsFor = function (aBlock) {
    // return an array of instructions for a stack of command blocks
    // or a reporter. Add a "halt" if needed and append any literals
    // (e.g. strings) used.
    var result;
    if (aBlock instanceof CommandBlockMorph) {
        result = this.instructionsForCommandList(aBlock);
    } else if (aBlock instanceof ReporterBlockMorph) {
        // wrap a return statement around the reporter
        result = [];
        result.push.apply(result, this.instructionsForExpression(aBlock));
        result.push(['returnResult', 0]);
    }
    result.push(['halt', 0]);
    if (result.length === 2 &&
        (contains(['halt', 'stopAll', 'doStop', 'doStopDevice'], result[0][0]))
    ) {
        // In general, just looking at the final instructon isn't enough
        // because it could just be the end of a conditional body that is
        // jumped over; in that case, we need the final halt as the jump target.
        result.pop(); // remove the final halt
    }
    this.appendLiterals(result);
    return result;
};

Compiler.prototype.instructionsForCommandList = function (aCmdBlock) {
    var result = [],
        cmd = aCmdBlock;
    while (!isNil(cmd)) {
        result.push.apply(result, this.instructionsForCommand(cmd));
        cmd = cmd.nextBlock();
    }
    return result;
};

Compiler.prototype.instructionsForCommand = function (aBlock) {
    var result = [],
        op = this.selectors[aBlock.selector] || aBlock.selector,
        args = aBlock.inputs();

    switch (op) {
    case 'doSetVar':
        result.push.apply(result, this.instructionsForExpression(args[1]));
        result.push(['popVar', this.globalVarIndex(args[0])]);
        break;
    case 'doChangeVar':
        result.push.apply(result, this.instructionsForExpression(args[1]));
        result.push(['incrementVar', this.globalVarIndex(args[0])]);
        break;
    case 'doReport':
        result.push.apply(result, this.instructionsForExpression(args[0]));
        result.push(['returnResult', 0]);
        break;
    case 'doIf':
        return this.instructionsForIf(args);
    case 'doIfElse':
        return this.instructionsForIfElse(args);
    case 'doForever':
        return this.instructionsForForever(args);
    case 'doRepeat':
        return this.instructionsForRepeat(args);
    case 'receiveCondition':
        return this.instructionsForWhenCondition(args);
    case 'receiveGo':
        return [];
    default:
        return this.primitive(op, args, true);
    }
    return result;
};

Compiler.prototype.instructionsForIf = function (inputs) {
    var test = inputs[0],
        script = inputs[1].evaluate(), // nested block inside the C-slot
        body = this.instructionsForCommandList(script),
        result = [];
    if (test instanceof ArgMorph) {
        if (test.evaluate()) {
            result.push.apply(result, body);
        }
    } else { // reporter
        result.push.apply(result, this.instructionsForExpression(test));
        result.push(['jmpFalse', body.length]);
        result.push.apply(result, body);
    }
    return result;
};

Compiler.prototype.instructionsForIfElse = function (inputs) {
    // +++ under construction: "else" case
    var test = inputs[0],
        trueBody = this.instructionsForCommandList(inputs[1].evaluate()),
        falseBody = this.instructionsForCommandList(inputs[2].evaluate()),
        result = [];
    if (test instanceof ArgMorph) {
        if (test.evaluate()) {
            result.push.apply(result,trueBody);
        } else {
            result.push.apply(result,falseBody);
        }
    } else { // reporter
        result.push.apply(result, this.instructionsForExpression(test));
        result.push(['jmpFalse', trueBody.length]);
        result.push.apply(result, trueBody);
        result.push(['jmp', falseBody.length]);
        result.push.apply(result, falseBody);
    }
    return result;
};

Compiler.prototype.instructionsForForever = function (inputs) {
    var script = inputs[0].evaluate(), // nested block inside the C-slot
        result = this.instructionsForCommandList(script);
    result.push(['jmp', -(result.length + 1)]);
    return result;
};

Compiler.prototype.instructionsForRepeat = function (inputs) {
    var script = inputs[1].evaluate(), // nested block inside the C-slot
        result = this.instructionsForExpression(inputs[0]), // count
        body = this.instructionsForCommandList(script);
    result.push.apply(result,body);
    result.push(['decrementAndJmp', -(body.length + 1)]);
    return result;
};

Compiler.prototype.instructionsForWhenCondition = function (inputs) {
    var result = this.instructionsForExpression(inputs[0]); // eval condition
    result.push(['jumpFalse', -(result.length + 1)]);
    return result;
};

Compiler.prototype.instructionsForExpression = function (expr) {
    var value, op, args;

    // immediate values
    if (expr instanceof ArgMorph) {
        value = expr.evaluate();
        if (value === true) {
            return [['pushImmediate', this.trueObj]];
        }
        if (value === false) {
            return [['pushImmediate', this.falseObj]];
        }
        if (isNil(value)) {
            return [['pushImmediate', 1]]; // the integer zero
        }
        if (Number.isInteger(value)) {
            if ((-8388608 <= value) && (value < 8388607)) {
                return [[
                    'pushImmediate',
                    ((value << 1) | 1) & 0xFFFFFF // value
                ]];
            } else {
                return [
                    // 32-bit integer objects
                    // follows pushBigImmediate instruction
                    ['pushBigImmediate', 0],
                    (value << 1) | 1
                ];
            }
        } if (isString(value)) {
            return [['pushLiteral', value]];
        }
        if (value instanceof Number) {
            throw new Error('Unsupported number type:', value);
        }
    }

    // expressions
    if (expr instanceof ReporterBlockMorph) {
        op = this.selectors[expr.selector] || expr.selector;
        args = expr.inputs();
        if (op === 'reportGetVar') {
            // +++ treated as global, scope needs attn.
            return [['pushVar', this.globalVarIndex(expr.blockSpec)]];
        }
        return this.primitive(op, args, false);
    }

    throw new Error('Unknown expression type:', expr);
};

Compiler.prototype.primitive = function (op, args, isCommand) {
    var result = [],
        isStop = contains(['halt', 'stopAll', 'doStop', 'doStopDevice'], op),
        myself = this;
    if (this.opcodes[op]) {
        args.forEach(function (input) {
            result.push.apply(
                result,
                myself.instructionsForExpression(input)
            );
        });
        result.push([op, args.length]);
        if (isCommand && !isStop) {
            result.push(['pop', 1]);
        }
    } else {
        console.log('Skipping unknown op:', op);
    }
    return result;
};

Compiler.prototype.globalVarIndex = function (varName) {
    var id = this.globals[varName];
    if (id === undefined) {
        id = Object.keys(this.globals).length;
        this.globals[varName] = id;
    }
    return id;
};

Compiler.prototype.appendLiterals = function (instructions) {
    // for now, strings are the only literals.
    // May add literal arrays later.
    var literals = [],
        literalOffsets = {},
        nextOffset = instructions.length,
        myself = this;
    instructions.forEach(function (instr, ip) {
        if (instr instanceof Array && (instr[0] === 'pushLiteral')) {
            var literal = (instr[1]),
                litOffset = literalOffsets[literal];
            if (isNil(litOffset)) {
                litOffset = nextOffset;
                literals.push(literal);
                literalOffsets[literal] = litOffset;
                nextOffset += myself.wordsForLiteral(literal);
            }
            instr[1] = litOffset - (ip + 1); // b/c JS has zero offset arrays
        }
    });
    instructions.push.apply(instructions, literals);
};

Compiler.prototype.wordsForLiteral = function (literal) {
    var headerWords = 1;
    if (isString(literal)) {
        return headerWords + this.wordCount(literal);
    }
    throw new Error('Illegal literal type:', literal);
};

// Compiler conversion

Compiler.prototype.str2bytes = function (str) {
    var bytes = [], i, n;
    for(i = 0, n = str.length; i < n; i += 1) {
        var char = str.charCodeAt(i);
        // bytes.push(char >>> 8, char & 0xFF);
        bytes.push(char & 0x7F);
    }
    return bytes;
};

Compiler.prototype.bytes2str = function (bytes) {
    var chars = [], i, n;
    for(i = 0, n = bytes.length; i < n;) {
        chars.push(((bytes[i++] & 0xff) << 8) | (bytes[i++] & 0xff));
    }
    return String.fromCharCode.apply(null, chars);
};


Compiler.prototype.wordCount = function(aString) {
    return Math.floor((this.byteCount(aString) + 4) / 4);
};

Compiler.prototype.byteCount = function(aString) {
    return this.str2bytes(aString).length;
    // return encodeURI(aString).split(/%..|./).length - 1;
};
