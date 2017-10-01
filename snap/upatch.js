/*

    upatch.js

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


    credits
    -------
    John Maloney designed the original 𝝁blocks bytecode system

*/

// Global stuff ////////////////////////////////////////////////////////

/*global modules, CommandBlockMorph, ReporterBlockMorph, BlockMorph,
DialogBoxMorph, contains, List, SpriteMorph, localize,
StageMorph, MenuMorph, IDE_Morph, ToggleMorph, nop, TextMorph, PushButtonMorph,
VariableDialogMorph, BlockDialogMorph, Color, TableDialogMorph, HatBlockMorph,
SyntaxElementMorph, BlockEditorMorph, InputSlotMorph, RingMorph,
ReporterSlotMorph, CommandSlotMorph, SpriteIconMorph, Compiler*/

modules.upatch = '2017-September-29';

var DeviceMorph;

// *************************************************************************
/*
    monkey-patching Snap! to test and debug the compiler
*/
// *************************************************************************

function listify (array) {
    var result = new List(array),
        i, el;
    for (i = 1; i <= result.length(); i += 1) {
        el = result.at(i);
        if (el instanceof Array) {
            result.put(listify(el), i);
        }
    }
    return result;
}

DeviceMorph.prototype = new SpriteMorph();
DeviceMorph.prototype.constructor = DeviceMorph;
DeviceMorph.uber = SpriteMorph.prototype;

function DeviceMorph(globals) {
    this.init(globals);
};

DeviceMorph.prototype.init = function (globals) {
    DeviceMorph.uber.init.call(this, globals);
    this.name = localize('Device');
    this.watcherValues = {};
};

DeviceMorph.prototype.initBlocks = function (globals) {
    DeviceMorph.prototype.blocks = {
        bubble: {
            type: 'command',
            category: 'looks',
            spec: 'say %s',
            defaults: [localize('Hello!')]
        },
        analogReadOp: {
            only: DeviceMorph,
            type: 'reporter',
            category: 'sensing',
            spec: 'read analog pin %n',
            defaults: [1]
        },
        analogWriteOp: {
            only: DeviceMorph,
            type: 'command',
            category: 'sensing',
            spec: 'set analog pin %n to %n',
            defaults: [1, 1023]
        },
        digitalReadOp: {
            only: DeviceMorph,
            type: 'predicate',
            category: 'sensing',
            spec: 'read digital pin %n',
            defaults: [1]
        },
        digitalWriteOp: {
            only: DeviceMorph,
            type: 'command',
            category: 'sensing',
            spec: 'set digital pin %n to %b',
            defaults: [1, true]
        },
        setLEDOp: {
            only: DeviceMorph,
            type: 'command',
            category: 'sensing',
            spec: 'set user LED %b',
            defaults: [true]
        },
        microsOp: {
            only: DeviceMorph,
            type: 'reporter',
            category: 'sensing',
            spec: 'micros'
        },
        millisOp: {
            only: DeviceMorph,
            type: 'reporter',
            category: 'sensing',
            spec: 'millis'
        },
        i2cSet: {
            only: DeviceMorph,
            type: 'command',
            category: 'sensing',
            spec: 'i2c set device %n register %n to %n',
            defaults: [0, 0, 0]
        },
        i2cGet: {
            only: DeviceMorph,
            type: 'reporter',
            category: 'sensing',
            spec: 'i2c get device %n register %n',
            defaults: [0, 0]
        },
        noop: {
            only: DeviceMorph,
            type: 'command',
            category: 'sensing',
            spec: 'no op'
        },
        peekOp: {
            only: DeviceMorph,
            type: 'reporter',
            category: 'sensing',
            spec: 'memory at %n',
            defaults: [0]
        },
        pokeOp: {
            only: DeviceMorph,
            type: 'command',
            category: 'sensing',
            spec: 'set memory at %n to %n',
            defaults: [0, 0]
        },
        receiveGo: {
            type: 'hat',
            category: 'control',
            spec: 'when %greenflag clicked'
        },
        receiveCondition: {
            type: 'hat',
            category: 'control',
            spec: 'when %greenflag clicked'
        },
        waitMicrosOp: {
            only: DeviceMorph,
            type: 'command',
            category: 'control',
            spec: 'wait %n microsecs',
            defaults: [10000]
        },
        waitMillisOp: {
            only: DeviceMorph,
            type: 'command',
            category: 'control',
            spec: 'wait %n millisecs',
            defaults: [500]
        },
        doForever: {
            type: 'command',
            category: 'control',
            spec: 'forever %c'
        },
        doRepeat: {
            type: 'command',
            category: 'control',
            spec: 'repeat %n %c',
            defaults: [10]
        },
        doIf: {
            type: 'command',
            category: 'control',
            spec: 'if %b %c'
        },
        doIfElse: {
            type: 'command',
            category: 'control',
            spec: 'if %b %c else %c'
        },
        doReport: {
            type: 'command',
            category: 'control',
            spec: 'report %s'
        },
        doStopDevice: {
            only: DeviceMorph,
            type: 'command',
            category: 'control',
            spec: 'stop all %stop'
        },
        reportSum: {
            type: 'reporter',
            category: 'operators',
            spec: '%n + %n'
        },
        reportDifference: {
            type: 'reporter',
            category: 'operators',
            spec: '%n \u2212 %n',
            alias: '-'
        },
        reportProduct: {
            type: 'reporter',
            category: 'operators',
            spec: '%n \u00D7 %n',
            alias: '*'
        },
        reportQuotient: {
            type: 'reporter',
            category: 'operators',
            spec: '%n / %n' // '%n \u00F7 %n'
        },
        reportDeviceLessThan: {
            only: DeviceMorph,
            type: 'predicate',
            category: 'operators',
            spec: '%n < %n',
            defaults: [3, 4]
        },
        doSetVar: {
            type: 'command',
            category: 'variables',
            spec: 'set %var to %s',
            defaults: [null, 0]
        },
        doChangeVar: {
            type: 'command',
            category: 'variables',
            spec: 'change %var by %n',
            defaults: [null, 1]
        },
        doDeclareVariables: {
            type: 'command',
            category: 'other',
            spec: 'script variables %scriptVars'
        },
        newArray: {
            only: DeviceMorph,
            type: 'reporter',
            category: 'lists',
            spec: 'new array %n',
            defaults: [10]
        },
        newByteArray: {
            only: DeviceMorph,
            type: 'reporter',
            category: 'lists',
            spec: 'new byte array %n',
            defaults: [10]
        },
        fillArray: {
            only: DeviceMorph,
            type: 'command',
            category: 'lists',
            spec: 'fill %l with %n',
            defaults: [null, 0]
        },
        reportListItem: {
            type: 'reporter',
            category: 'lists',
            spec: 'item %idx of %l',
            defaults: [1]
        },
         doReplaceInList: {
            type: 'command',
            category: 'lists',
            spec: 'replace item %idx of %l with %s',
            defaults: [1, null, localize('thing')]
        }
    };
};

DeviceMorph.prototype.initBlocks();

DeviceMorph.prototype.blockTemplates = function (category) {
    var blocks = [], myself = this, varNames, button,
        cat = category || 'sensing', txt,
        inheritedVars = this.inheritedVariableNames();

    function block(selector, isGhosted) {
        if (StageMorph.prototype.hiddenPrimitives[selector]) {
            return null;
        }
        var newBlock = DeviceMorph.prototype.blockForSelector(selector, true);
        newBlock.isTemplate = true;
        if (isGhosted) {newBlock.ghost(); }
        return newBlock;
    }

    function variableBlock(varName) {
        var newBlock = DeviceMorph.prototype.variableBlock(varName);
        newBlock.isDraggable = false;
        newBlock.isTemplate = true;
        if (contains(inheritedVars, varName)) {
            newBlock.ghost();
        }
        return newBlock;
    }

    function watcherToggle(selector) {
        /*if (DeviceMorph.prototype.hiddenPrimitives[selector]) {
            return null;
        }*/
        var info = DeviceMorph.prototype.blocks[selector];
        return new ToggleMorph(
            'checkbox',
            this,
            function () {
                myself.toggleWatcher(
                    selector,
                    localize(info.spec),
                    myself.blockColor[info.category]
                );
            },
            null,
            function () {
                return myself.showingWatcher(selector);
            },
            null
        );
    }

    function variableWatcherToggle(varName) {
        return new ToggleMorph(
            'checkbox',
            this,
            function () {
                myself.toggleVariableWatcher(varName);
            },
            null,
            function () {
                return myself.showingVariableWatcher(varName);
            },
            null
        );
    }

    function helpMenu() {
        var menu = new MenuMorph(this);
        menu.addItem('help...', 'showHelp');
        return menu;
    }

    function addVar(pair) {
        var ide;
        if (pair) {
            if (myself.isVariableNameInUse(pair[0], pair[1])) {
                myself.inform('that name is already in use');
            } else {
                ide = myself.parentThatIsA(IDE_Morph);
                myself.addVariable(pair[0], pair[1]);
                if (!myself.showingVariableWatcher(pair[0])) {
                    myself.toggleVariableWatcher(pair[0], pair[1]);
                }
                ide.flushBlocksCache('variables'); // b/c of inheritance
                ide.refreshPalette();
            }
        }
    }

    if (cat === 'motion') {
        nop();
    } else if (cat === 'looks') {
        blocks.push(block('bubble'));
    } else if (cat === 'sound') {
        nop();
    } else if (cat === 'pen') {
        nop();
    } else if (cat === 'control') {
        blocks.push(block('receiveGo'));
        blocks.push(block('receiveCondition'));
        blocks.push('-');
        blocks.push(block('waitMicrosOp'));
        blocks.push(block('waitMillisOp'));
        blocks.push('-');
        blocks.push(block('doForever'));
        blocks.push(block('doRepeat'));
        blocks.push(block('doIf'));
        blocks.push(block('doIfElse'));
        blocks.push('-');
        blocks.push(block('doReport'));
        blocks.push('-');
        blocks.push(block('doStopDevice'));
    } else if (cat === 'sensing') {
        blocks.push(block('analogReadOp'));
        blocks.push(block('analogWriteOp'));
        blocks.push('-');
        blocks.push(block('digitalReadOp'));
        blocks.push(block('digitalWriteOp'));
        blocks.push('-');
        blocks.push(block('setLEDOp'));
        blocks.push('-');
        blocks.push(watcherToggle('microsOp'));
        blocks.push(block('microsOp'));
        blocks.push(watcherToggle('millisOp'));
        blocks.push(block('millisOp'));
        blocks.push('-');
        blocks.push(block('i2cSet'));
        blocks.push(block('i2cGet'));
        blocks.push('-');
        blocks.push(block('noop'));
        blocks.push('-');
        blocks.push(block('peekOp'));
        blocks.push(block('pokeOp'));
    } else if (cat === 'operators') {
        blocks.push(block('reportSum'));
        blocks.push(block('reportDifference'));
        blocks.push(block('reportProduct'));
        blocks.push(block('reportQuotient'));
        blocks.push('-');
        blocks.push(block('reportDeviceLessThan'));
    } else if (cat === 'variables') {

        button = new PushButtonMorph(
                null,
                function () {
                    new VariableDialogMorph(
                        null,
                        addVar,
                        myself
                        ).prompt(
                            'Variable name',
                            null,
                            myself.world()
                        );
                },
                'Make a variable'
            );
        button.userMenu = helpMenu;
        button.selector = 'addVariable';
        button.showHelp = BlockMorph.prototype.showHelp;
        blocks.push(button);

        if (this.deletableVariableNames().length > 0) {
            button = new PushButtonMorph(
                    null,
                    function () {
                        var menu = new MenuMorph(
                            myself.deleteVariable,
                            null,
                            myself
                        );
                        myself.deletableVariableNames().forEach(function (name) {
                            menu.addItem(name, name);
                        });
                        menu.popUpAtHand(myself.world());
                    },
                    'Delete a variable'
                );
            button.userMenu = helpMenu;
            button.selector = 'deleteVariable';
            button.showHelp = BlockMorph.prototype.showHelp;
            blocks.push(button);
        }

        blocks.push('-');

        varNames = this.variables.allNames();
        if (varNames.length > 0) {
            varNames.forEach(function (name) {
                blocks.push(variableWatcherToggle(name));
                blocks.push(variableBlock(name));
            });
            blocks.push('-');
        }

        blocks.push(block('doSetVar'));
        blocks.push(block('doChangeVar'));

        blocks.push(block('doDeclareVariables'));

        blocks.push('=');

        blocks.push(block('newArray'));
        blocks.push(block('newByteArray'));
        blocks.push('-');
        blocks.push(block('fillArray'));
        blocks.push('-');
        blocks.push(block('reportListItem'));
        blocks.push('-');
        blocks.push(block('doReplaceInList'));

        blocks.push('=');

        button = new PushButtonMorph(
                null,
                function () {
                    var ide = myself.parentThatIsA(IDE_Morph),
                    stage = myself.parentThatIsA(StageMorph);
                    new BlockDialogMorph(
                        null,
                        function (definition) {
                            if (definition.spec !== '') {
                                if (definition.isGlobal) {
                                    stage.globalBlocks.push(definition);
                                } else {
                                    myself.customBlocks.push(definition);
                                }
                                ide.flushPaletteCache();
                                ide.refreshPalette();
                                new BlockEditorMorph(definition, myself).popUp();
                            }
                        },
                        myself
                        ).prompt(
                            'Make a block',
                            null,
                            myself.world()
                        );
                },
                'Make a block'
            );
        button.userMenu = helpMenu;
        button.selector = 'addCustomBlock';
        button.showHelp = BlockMorph.prototype.showHelp;
        blocks.push(button);
    }
    return blocks;
};

DeviceMorph.prototype.drawNew = function () {
    var context, w, h, n, n2, l;

    this.image = newCanvas(this.extent());

    w = this.image.width;
    h = this.image.height;
    n = this.image.width / 6;
    n2 = n / 2;
    l = Math.max(w / 20, 0.5);
    context = this.image.getContext('2d');

    context.fillStyle = 'rgba(200,200,200,1)';

    context.beginPath();
    context.moveTo(n + l, n);
    context.lineTo(n * 2, n);
    context.lineTo(n * 2.5, n * 1.5);
    context.lineTo(n * 3.5, n * 1.5);
    context.lineTo(n * 4, n);
    context.lineTo(n * 5 - l, n);
    context.lineTo(n * 4, n * 3);
    context.lineTo(n * 4, n * 4 - l);
    context.lineTo(n * 2, n * 4 - l);
    context.lineTo(n * 2, n * 3);
    context.closePath();
    context.fill();

    context.beginPath();
    context.moveTo(n * 2.75, n + l);
    context.lineTo(n * 2.4, n);
    context.lineTo(n * 2.2, 0);
    context.lineTo(n * 3.8, 0);
    context.lineTo(n * 3.6, n);
    context.lineTo(n * 3.25, n + l);
    context.closePath();
    context.fill();

    context.beginPath();
    context.moveTo(n * 2.5, n * 4);
    context.lineTo(n, n * 4);
    context.lineTo(n2 + l, h);
    context.lineTo(n * 2, h);
    context.closePath();
    context.fill();

    context.beginPath();
    context.moveTo(n * 3.5, n * 4);
    context.lineTo(n * 5, n * 4);
    context.lineTo(w - (n2 + l), h);
    context.lineTo(n * 4, h);
    context.closePath();
    context.fill();

    context.beginPath();
    context.moveTo(n, n);
    context.lineTo(l, n * 1.5);
    context.lineTo(l, n * 3.25);
    context.lineTo(n * 1.5, n * 3.5);
    context.closePath();
    context.fill();

    context.beginPath();
    context.moveTo(n * 5, n);
    context.lineTo(w - l, n * 1.5);
    context.lineTo(w - l, n * 3.25);
    context.lineTo(n * 4.5, n * 3.5);
    context.closePath();
    context.fill();
};


// Watchers

DeviceMorph.prototype.watcherGetterForSelector = function (selector) {
    // Watcher getter factory
    return function () {
        var ide = this.parentThatIsA(IDE_Morph),
            watcher = this.watcherFor(ide.stage, selector);

        if (!watcher) { return; }
        if (!watcher.id) {
            watcher.id = ide.lastStackId;
            ide.lastStackId += 1;
            ide.postal.sendMessage(
                'storeChunk',
                watcher.id,
                new Compiler().bytesFor(this.blockForSelector(selector))
            );
        }

        // we send two messages to get the next value, but display the last one
        ide.postal.sendMessage('startChunk', watcher.id);

        // check out Protocol >> dispatcher >> taskReturned to understand where
        // this values come from
        return this.watcherValues[selector];
    }
};

['microsOp', 'millisOp'].forEach(function (selector) {
    DeviceMorph.prototype[selector] =
        DeviceMorph.prototype.watcherGetterForSelector(selector);
});

// BlockMorph menu:

BlockMorph.prototype.userMenu = function () {
    var menu = new MenuMorph(this),
        world = this.world(),
        myself = this,
        shiftClicked = world.currentKey === 16,
        proc = this.activeProcess(),
        vNames = proc && proc.context && proc.context.outerContext ?
                proc.context.outerContext.variables.names() : [],
        alternatives,
        field,
        rcvr,
        top;

    function addOption(label, toggle, test, onHint, offHint) {
        var on = '\u2611 ',
            off = '\u2610 ';
        menu.addItem(
            (test ? on : off) + localize(label),
            toggle,
            test ? onHint : offHint
        );
    }

    function renameVar() {
        var blck = myself.fullCopy();
        blck.addShadow();
        new DialogBoxMorph(
            myself,
            myself.userSetSpec,
            myself
        ).prompt(
            "Variable name",
            myself.blockSpec,
            world,
            blck.fullImage(), // pic
            InputSlotMorph.prototype.getVarNamesDict.call(myself)
        );
    }

    // +++
    if (myself.scriptTarget() instanceof DeviceMorph) {
        menu.addItem('show instructions...', function () {
            var codes = listify(new Compiler().instructionsFor(this));
            new TableDialogMorph(codes).popUp(this.world());
        });
        menu.addItem('show bytecode...', function () {
            var codes = listify(new Compiler().bytesFor(this));
            new TableDialogMorph(codes).popUp(this.world());
        });
        if (shiftClicked) {
            menu.addItem(
                'log bytecode...',
                function () {
                    var codes = new Compiler().bytesFor(this),
                        txt = '';
                    codes.forEach(function (byte) {
                        txt += byte;
                        txt += ' ';
                    });
                    console.log(txt);
                },
                null,
                new Color(100, 0, 0)
            );
        }
        menu.addLine();
    }

    menu.addItem(
        "help...",
        'showHelp'
    );
    if (shiftClicked) {
        top = this.topBlock();
        if (top instanceof ReporterBlockMorph) {
            menu.addItem(
                "script pic with result...",
                function () {
                    top.exportResultPic();
                },
                'open a new window\n' +
                    'with a picture of both\nthis script and its result',
                new Color(100, 0, 0)
            );
        }
    }
    if (this.isTemplate) {
        if (this.parent instanceof SyntaxElementMorph) { // in-line
            if (this.selector === 'reportGetVar') { // script var definition
                menu.addLine();
                menu.addItem(
                    'rename...',
                    function () {
                        myself.refactorThisVar(true); // just the template
                    },
                    'rename only\nthis reporter'
                );
                menu.addItem(
                    'rename all...',
                    'refactorThisVar',
                    'rename all blocks that\naccess this variable'
                );
            }
        } else { // in palette
            if (this.selector === 'reportGetVar') {
                if (!this.isInheritedVariable()) {
                    addOption(
                        'transient',
                        'toggleTransientVariable',
                        myself.isTransientVariable(),
                        'uncheck to save contents\nin the project',
                        'check to prevent contents\nfrom being saved'
                    );
                    menu.addLine();
                    menu.addItem(
                        'rename...',
                        function () {
                            myself.refactorThisVar(true); // just the template
                        },
                        'rename only\nthis reporter'
                    );
                    menu.addItem(
                        'rename all...',
                        'refactorThisVar',
                        'rename all blocks that\naccess this variable'
                    );
                }
            } else if (this.selector !== 'evaluateCustomBlock') {
                menu.addItem(
                    "hide",
                    'hidePrimitive'
                );
            }

            // allow toggling inheritable attributes
            if (StageMorph.prototype.enableInheritance) {
                rcvr = this.scriptTarget();
                field = {
                    xPosition: 'x position',
                    yPosition: 'y position',
                    direction: 'direction',
                    getScale: 'size',
                    getCostumeIdx: 'costume #'
                }[this.selector];
                if (field && rcvr && rcvr.exemplar) {
                    menu.addLine();
                    if (rcvr.inheritsAttribute(field)) {
                        menu.addItem(
                            'disinherit',
                            function () {
                                rcvr.shadowAttribute(field);
                            }
                        );
                    } else {
                        menu.addItem(
                            localize('inherit from') + ' ' + rcvr.exemplar.name,
                            function () {
                                rcvr.inheritAttribute(field);
                            }
                        );
                    }
                }
            }

            if (StageMorph.prototype.enableCodeMapping) {
                menu.addLine();
                menu.addItem(
                    'header mapping...',
                    'mapToHeader'
                );
                menu.addItem(
                    'code mapping...',
                    'mapToCode'
                );
            }
        }
        return menu;
    }
    menu.addLine();
    if (this.selector === 'reportGetVar') {
        menu.addItem(
            'rename...',
            renameVar,
            'rename only\nthis reporter'
        );
    } else if (SpriteMorph.prototype.blockAlternatives[this.selector]) {
        menu.addItem(
            'relabel...',
            function () {
                myself.relabel(
                    SpriteMorph.prototype.blockAlternatives[myself.selector]
                );
            }
        );
    } else if (this.isCustomBlock && this.alternatives) {
        alternatives = this.alternatives();
        if (alternatives.length > 0) {
            menu.addItem(
                'relabel...',
                function () {myself.relabel(alternatives); }
            );
        }
    }

    menu.addItem(
        "duplicate",
        function () {
            var dup = myself.fullCopy(),
                ide = myself.parentThatIsA(IDE_Morph),
                blockEditor = myself.parentThatIsA(BlockEditorMorph);
            dup.pickUp(world);
            // register the drop-origin, so the block can
            // slide back to its former situation if dropped
            // somewhere where it gets rejected
            if (!ide && blockEditor) {
                ide = blockEditor.target.parentThatIsA(IDE_Morph);
            }
            if (ide) {
                world.hand.grabOrigin = {
                    origin: ide.palette,
                    position: ide.palette.center()
                };
            }
        },
        'make a copy\nand pick it up'
    );
    if (this instanceof CommandBlockMorph && this.nextBlock()) {
        menu.addItem(
            (proc ? this.fullCopy() : this).thumbnail(0.5, 60),
            function () {
                var cpy = myself.fullCopy(),
                    nb = cpy.nextBlock(),
                    ide = myself.parentThatIsA(IDE_Morph),
                    blockEditor = myself.parentThatIsA(BlockEditorMorph);
                if (nb) {nb.destroy(); }
                cpy.pickUp(world);
                if (!ide && blockEditor) {
                    ide = blockEditor.target.parentThatIsA(IDE_Morph);
                }
                if (ide) {
                    world.hand.grabOrigin = {
                        origin: ide.palette,
                        position: ide.palette.center()
                    };
                }
            },
            'only duplicate this block'
        );
    }
    menu.addItem(
        "delete",
        'userDestroy'
    );
    menu.addItem(
        "script pic...",
        function () {
            var ide = myself.parentThatIsA(IDE_Morph) ||
                myself.parentThatIsA(BlockEditorMorph).target.parentThatIsA(
                    IDE_Morph
            );
            ide.saveCanvasAs(
                myself.topBlock().scriptPic(),
                ide.projetName || localize('Untitled') + ' ' +
                    localize('script pic'),
                true // request new window
            );
        },
        'open a new window\nwith a picture of this script'
    );
    if (proc) {
        if (vNames.length) {
            menu.addLine();
            vNames.forEach(function (vn) {
                menu.addItem(
                    vn + '...',
                    function () {
                        proc.doShowVar(vn);
                    }
                );
            });
        }
        proc.homeContext.variables.names().forEach(function (vn) {
            if (!contains(vNames, vn)) {
                menu.addItem(
                    vn + '...',
                    function () {
                        proc.doShowVar(vn);
                    }
                );
            }
        });
        return menu;
    }
    if (this.parent.parentThatIsA(RingMorph)) {
        menu.addLine();
        menu.addItem("unringify", 'unringify');
        top = this.topBlock();
        if (this instanceof ReporterBlockMorph ||
                (!(top instanceof HatBlockMorph))) {
            menu.addItem("ringify", 'ringify');
        }
        return menu;
    }
    if (this.parent instanceof ReporterSlotMorph
            || (this.parent instanceof CommandSlotMorph)
            || (this instanceof HatBlockMorph)
            || (this instanceof CommandBlockMorph
                && (this.topBlock() instanceof HatBlockMorph))) {
        return menu;
    }
    menu.addLine();
    menu.addItem("ringify", 'ringify');
    if (StageMorph.prototype.enableCodeMapping) {
        menu.addLine();
        menu.addItem(
            'header mapping...',
            'mapToHeader'
        );
        menu.addItem(
            'code mapping...',
            'mapToCode'
        );
    }
    return menu;
};

BlockMorph.prototype.originalFullCopy = BlockMorph.prototype.fullCopy;
BlockMorph.prototype.fullCopy = function () {
    var copy = this.originalFullCopy();
    copy.stackId = null;
    return copy;
};

// Evaluate on board
ThreadManager.prototype.startProcess = function (
    block,
    receiver,
    isThreadSafe,
    exportResult, // bool
    callback,
    isClicked,
    rightAway
) {
    var top = block.topBlock(),
        active = this.findProcess(top, receiver),
        newProc, ide, codes;
    if (active) {
        if (isThreadSafe) {
            return active;
        }
        active.stop();
        this.removeTerminatedProcesses();
    }

    if (receiver instanceof DeviceMorph) {
        ide = receiver.parentThatIsA(IDE_Morph);

        if (isNil(block.getHighlight())) {
            codes = (new Compiler().bytesFor(top));

            if (isNil(block.stackId)) {
                block.stackId = ide.lastStackId;
                ide.lastStackId += 1;
            }

            ide.postal.sendMessage('storeChunk', block.stackId, codes);
            ide.postal.sendMessage('startChunk', block.stackId);
        } else {
            ide.postal.sendMessage('stopChunk', block.stackId);
        }
    } else {
        newProc = new Process(top, receiver, callback, rightAway);
        newProc.exportResult = exportResult;
        newProc.isClicked = isClicked || false;
        if (!newProc.homeContext.receiver.isClone) {
            top.addHighlight();
        }
        this.processes.push(newProc);
        if (rightAway) {
            newProc.runStep();
        }
        return newProc;
    }
};

IDE_Morph.prototype.stopAllScripts = function () {
    if (this.stage.enableCustomHatBlocks) {
        this.stage.threads.pauseCustomHatBlocks =
            !this.stage.threads.pauseCustomHatBlocks;
    } else {
        this.stage.threads.pauseCustomHatBlocks = false;
    }
    this.controlBar.stopButton.refresh();
    this.stage.fireStopAllEvent();
    this.postal.protocol.clearBuffer();
    this.postal.sendMessage('stopAll');
};

// Just a decorator to be made "native" when µBlocks becomes part of Snap!
IDE_Morph.prototype.originalInit = IDE_Morph.prototype.init;
IDE_Morph.prototype.init = function (isAutoFill) {
    var myself = this;

    this.originalInit(isAutoFill);

    this.lastStackId = 0;
    this.postal = new Postal('ws://localhost:9999/', this);
};

IDE_Morph.prototype.findStackOrWatcher = function (taskId) {
    var object;
    this.stage.children.forEach(function (morph) {
        if ((morph instanceof DeviceMorph) && !object) {
            morph.scripts.children.forEach(function (child) {
                if (child instanceof BlockMorph && child.stackId == taskId) {
                    object = child;
                    return;
                }
            });
        } else if (morph instanceof WatcherMorph) {
            if (morph.id == taskId) {
                object = morph;
                return;
            }
        }
    });

    return object;
};

IDE_Morph.prototype.settingsMenu = function () {
    var menu,
        stage = this.stage,
        world = this.world(),
        myself = this,
        pos = this.controlBar.settingsButton.bottomLeft(),
        shiftClicked = (world.currentKey === 16);

    function addPreference(label, toggle, test, onHint, offHint, hide) {
        var on = '\u2611 ',
            off = '\u2610 ';
        if (!hide || shiftClicked) {
            menu.addItem(
                (test ? on : off) + localize(label),
                toggle,
                test ? onHint : offHint,
                hide ? new Color(100, 0, 0) : null
            );
        }
    }

    menu = new MenuMorph(this);
    menu.addItem('Language...', 'languageMenu');
    menu.addItem(
        'Zoom blocks...',
        'userSetBlocksScale'
    );
    menu.addItem(
        'Stage size...',
        'userSetStageSize'
    );
    if (shiftClicked) {
        menu.addItem(
            'Dragging threshold...',
            'userSetDragThreshold',
            'specify the distance the hand has to move\n' +
                'before it picks up an object',
            new Color(100, 0, 0)
        );
    }
    menu.addLine();
    /*
    addPreference(
        'JavaScript',
        function () {
            Process.prototype.enableJS = !Process.prototype.enableJS;
            myself.currentSprite.blocksCache.operators = null;
            myself.currentSprite.paletteCache.operators = null;
            myself.refreshPalette();
        },
        Process.prototype.enableJS,
        'uncheck to disable support for\nnative JavaScript functions',
        'check to support\nnative JavaScript functions'
    );
    */
    if (isRetinaSupported()) {
        addPreference(
            'Retina display support',
            'toggleRetina',
            isRetinaEnabled(),
            'uncheck for lower resolution,\nsaves computing resources',
            'check for higher resolution,\nuses more computing resources'
        );
    }
    addPreference(
        'Input sliders',
        'toggleInputSliders',
        MorphicPreferences.useSliderForInput,
        'uncheck to disable\ninput sliders for\nentry fields',
        'check to enable\ninput sliders for\nentry fields'
    );
    if (MorphicPreferences.useSliderForInput) {
        addPreference(
            'Execute on slider change',
            'toggleSliderExecute',
            ArgMorph.prototype.executeOnSliderEdit,
            'uncheck to suppress\nrunning scripts\nwhen moving the slider',
            'check to run\nthe edited script\nwhen moving the slider'
        );
    }
    addPreference(
        'Turbo mode',
        'toggleFastTracking',
        this.stage.isFastTracked,
        'uncheck to run scripts\nat normal speed',
        'check to prioritize\nscript execution'
    );
    addPreference(
        'Visible stepping',
        'toggleSingleStepping',
        Process.prototype.enableSingleStepping,
        'uncheck to turn off\nvisible stepping',
        'check to turn on\n visible stepping (slow)',
        false
    );
    menu.addLine(); // everything visible below is persistent
    addPreference(
        'Blurred shadows',
        'toggleBlurredShadows',
        useBlurredShadows,
        'uncheck to use solid drop\nshadows and highlights',
        'check to use blurred drop\nshadows and highlights',
        true
    );
    addPreference(
        'Zebra coloring',
        'toggleZebraColoring',
        BlockMorph.prototype.zebraContrast,
        'uncheck to disable alternating\ncolors for nested block',
        'check to enable alternating\ncolors for nested blocks',
        true
    );
    addPreference(
        'Dynamic input labels',
        'toggleDynamicInputLabels',
        SyntaxElementMorph.prototype.dynamicInputLabels,
        'uncheck to disable dynamic\nlabels for variadic inputs',
        'check to enable dynamic\nlabels for variadic inputs',
        true
    );
    addPreference(
        'Prefer empty slot drops',
        'togglePreferEmptySlotDrops',
        ScriptsMorph.prototype.isPreferringEmptySlots,
        'uncheck to allow dropped\nreporters to kick out others',
        'settings menu prefer empty slots hint',
        true
    );
    addPreference(
        'Long form input dialog',
        'toggleLongFormInputDialog',
        InputSlotDialogMorph.prototype.isLaunchingExpanded,
        'uncheck to use the input\ndialog in short form',
        'check to always show slot\ntypes in the input dialog'
    );
    addPreference(
        'Plain prototype labels',
        'togglePlainPrototypeLabels',
        BlockLabelPlaceHolderMorph.prototype.plainLabel,
        'uncheck to always show (+) symbols\nin block prototype labels',
        'check to hide (+) symbols\nin block prototype labels'
    );
    addPreference(
        'Virtual keyboard',
        'toggleVirtualKeyboard',
        MorphicPreferences.useVirtualKeyboard,
        'uncheck to disable\nvirtual keyboard support\nfor mobile devices',
        'check to enable\nvirtual keyboard support\nfor mobile devices',
        true
    );
    addPreference(
        'Clicking sound',
        function () {
            BlockMorph.prototype.toggleSnapSound();
            if (BlockMorph.prototype.snapSound) {
                myself.saveSetting('click', true);
            } else {
                myself.removeSetting('click');
            }
        },
        BlockMorph.prototype.snapSound,
        'uncheck to turn\nblock clicking\nsound off',
        'check to turn\nblock clicking\nsound on'
    );
    addPreference(
        'Animations',
        function () {myself.isAnimating = !myself.isAnimating; },
        myself.isAnimating,
        'uncheck to disable\nIDE animations',
        'check to enable\nIDE animations',
        true
    );
    addPreference(
        'Cache Inputs',
        function () {
            BlockMorph.prototype.isCachingInputs =
                !BlockMorph.prototype.isCachingInputs;
        },
        BlockMorph.prototype.isCachingInputs,
        'uncheck to stop caching\ninputs (for debugging the evaluator)',
        'check to cache inputs\nboosts recursion',
        true
    );
    addPreference(
        'Rasterize SVGs',
        function () {
            MorphicPreferences.rasterizeSVGs =
                !MorphicPreferences.rasterizeSVGs;
        },
        MorphicPreferences.rasterizeSVGs,
        'uncheck for smooth\nscaling of vector costumes',
        'check to rasterize\nSVGs on import',
        true
    );
    addPreference(
        'Flat design',
        function () {
            if (MorphicPreferences.isFlat) {
                return myself.defaultDesign();
            }
            myself.flatDesign();
        },
        MorphicPreferences.isFlat,
        'uncheck for default\nGUI design',
        'check for alternative\nGUI design',
        false
    );
    addPreference(
        'Nested auto-wrapping',
        function () {
            ScriptsMorph.prototype.enableNestedAutoWrapping =
                !ScriptsMorph.prototype.enableNestedAutoWrapping;
            if (ScriptsMorph.prototype.enableNestedAutoWrapping) {
                myself.removeSetting('autowrapping');
            } else {
                myself.saveSetting('autowrapping', false);
            }
        },
        ScriptsMorph.prototype.enableNestedAutoWrapping,
        'uncheck to confine auto-wrapping\nto top-level block stacks',
        'check to enable auto-wrapping\ninside nested block stacks',
        true
    );
    addPreference(
        'Project URLs',
        function () {
            myself.projectsInURLs = !myself.projectsInURLs;
            if (myself.projectsInURLs) {
                myself.saveSetting('longurls', true);
            } else {
                myself.removeSetting('longurls');
            }
        },
        myself.projectsInURLs,
        'uncheck to disable\nproject data in URLs',
        'check to enable\nproject data in URLs',
        true
    );
    addPreference(
        'Sprite Nesting',
        function () {
            SpriteMorph.prototype.enableNesting =
                !SpriteMorph.prototype.enableNesting;
        },
        SpriteMorph.prototype.enableNesting,
        'uncheck to disable\nsprite composition',
        'check to enable\nsprite composition',
        true
    );
    addPreference(
        'First-Class Sprites',
        function () {
            SpriteMorph.prototype.enableFirstClass =
                !SpriteMorph.prototype.enableFirstClass;
            myself.currentSprite.blocksCache.sensing = null;
            myself.currentSprite.paletteCache.sensing = null;
            myself.refreshPalette();
        },
        SpriteMorph.prototype.enableFirstClass,
        'uncheck to disable support\nfor first-class sprites',
        'check to enable support\n for first-class sprite',
        true
    );
    addPreference(
        'Keyboard Editing',
        function () {
            ScriptsMorph.prototype.enableKeyboard =
                !ScriptsMorph.prototype.enableKeyboard;
            if (ScriptsMorph.prototype.enableKeyboard) {
                myself.removeSetting('keyboard');
            } else {
                myself.saveSetting('keyboard', false);
            }
        },
        ScriptsMorph.prototype.enableKeyboard,
        'uncheck to disable\nkeyboard editing support',
        'check to enable\nkeyboard editing support',
        true
    );
    addPreference(
        'Table support',
        function () {
            List.prototype.enableTables =
                !List.prototype.enableTables;
            if (List.prototype.enableTables) {
                myself.removeSetting('tables');
            } else {
                myself.saveSetting('tables', false);
            }
        },
        List.prototype.enableTables,
        'uncheck to disable\nmulti-column list views',
        'check for multi-column\nlist view support',
        true
    );
    if (List.prototype.enableTables) {
        addPreference(
            'Table lines',
            function () {
                TableMorph.prototype.highContrast =
                    !TableMorph.prototype.highContrast;
                if (TableMorph.prototype.highContrast) {
                    myself.saveSetting('tableLines', true);
                } else {
                    myself.removeSetting('tableLines');
                }
            },
            TableMorph.prototype.highContrast,
            'uncheck for less contrast\nmulti-column list views',
            'check for higher contrast\ntable views',
            true
        );
    }
    addPreference(
        'Live coding support',
        function () {
            Process.prototype.enableLiveCoding =
                !Process.prototype.enableLiveCoding;
        },
        Process.prototype.enableLiveCoding,
        'EXPERIMENTAL! uncheck to disable live\ncustom control structures',
        'EXPERIMENTAL! check to enable\n live custom control structures',
        true
    );
    menu.addLine(); // everything below this line is stored in the project
    addPreference(
        'Thread safe scripts',
        function () {stage.isThreadSafe = !stage.isThreadSafe; },
        this.stage.isThreadSafe,
        'uncheck to allow\nscript reentrance',
        'check to disallow\nscript reentrance'
    );
    addPreference(
        'Prefer smooth animations',
        'toggleVariableFrameRate',
        StageMorph.prototype.frameRate,
        'uncheck for greater speed\nat variable frame rates',
        'check for smooth, predictable\nanimations across computers',
        true
    );
    addPreference(
        'Flat line ends',
        function () {
            SpriteMorph.prototype.useFlatLineEnds =
                !SpriteMorph.prototype.useFlatLineEnds;
        },
        SpriteMorph.prototype.useFlatLineEnds,
        'uncheck for round ends of lines',
        'check for flat ends of lines'
    );
    addPreference(
        'Codification support',
        function () {
            StageMorph.prototype.enableCodeMapping =
                !StageMorph.prototype.enableCodeMapping;
            myself.currentSprite.blocksCache.variables = null;
            myself.currentSprite.paletteCache.variables = null;
            myself.refreshPalette();
        },
        StageMorph.prototype.enableCodeMapping,
        'uncheck to disable\nblock to text mapping features',
        'check for block\nto text mapping features',
        false
    );
    addPreference(
        'Inheritance support',
        function () {
            StageMorph.prototype.enableInheritance =
                !StageMorph.prototype.enableInheritance;
            myself.currentSprite.blocksCache.variables = null;
            myself.currentSprite.paletteCache.variables = null;
            myself.refreshPalette();
        },
        StageMorph.prototype.enableInheritance,
        'uncheck to disable\nsprite inheritance features',
        'check for sprite\ninheritance features',
        false
    );
    addPreference(
        'Persist linked sublist IDs',
        function () {
            StageMorph.prototype.enableSublistIDs =
                !StageMorph.prototype.enableSublistIDs;
        },
        StageMorph.prototype.enableSublistIDs,
        'uncheck to disable\nsaving linked sublist identities',
        'check to enable\nsaving linked sublist identities',
        true
    );
    addPreference(
        'Enable µBlocks devices',
        'toggleMicroBlocks',
        IDE_Morph.prototype.microBlocksEnabled,
        'uncheck to disable\nsupport for µBlocks devices',
        'check to enable\nsupport for µBlocks devices',
        true
    );
 
    menu.popup(world, pos);
};

IDE_Morph.prototype.toggleMicroBlocks = function () {
    IDE_Morph.prototype.microBlocksEnabled = !IDE_Morph.prototype.microBlocksEnabled;
    if (IDE_Morph.prototype.microBlocksEnabled) {
        this.saveSetting('ublocks', true);
        if (this.devicebutton) {
            this.devicebutton.show();
        }
    } else {
        this.removeSetting('ublocks');
        if (this.devicebutton) {
            this.devicebutton.hide();
        }
    }
};

IDE_Morph.prototype.originalApplySavedSettings = IDE_Morph.prototype.applySavedSettings;
IDE_Morph.prototype.applySavedSettings = function () {
    this.originalApplySavedSettings();
    if (this.getSetting('ublocks')) {
        this.toggleMicroBlocks();
    }
};

IDE_Morph.prototype.originalCreateCorralBar = IDE_Morph.prototype.createCorralBar;
IDE_Morph.prototype.createCorralBar = function () {
    var padding = 5,
        colors = [
            this.groupColor,
            this.frameColor.darker(50),
            this.frameColor.darker(50)
        ];

    this.originalCreateCorralBar();

    this.devicebutton = new PushButtonMorph(
        this,
        "newDevice",
        new SymbolMorph("robot", 15)
    );
    this.devicebutton.corner = 12;
    this.devicebutton.color = colors[0];
    this.devicebutton.highlightColor = colors[1];
    this.devicebutton.pressColor = colors[2];
    this.devicebutton.labelMinExtent = new Point(36, 18);
    this.devicebutton.padding = 0;
    this.devicebutton.labelShadowOffset = new Point(-1, -1);
    this.devicebutton.labelShadowColor = colors[1];
    this.devicebutton.labelColor = this.buttonLabelColor;
    this.devicebutton.contrast = this.buttonContrast;
    this.devicebutton.drawNew();
    this.devicebutton.hint = "add a µBlocks device";
    this.devicebutton.fixLayout();
    this.devicebutton.setCenter(this.corralBar.center());
    this.devicebutton.setLeft(
        this.corralBar.left() + padding + this.devicebutton.width() * 2 + padding * 2
    );
    this.corralBar.add(this.devicebutton);

    if (!IDE_Morph.prototype.microBlocksEnabled) {
        this.devicebutton.hide();
    }
};

IDE_Morph.prototype.newDevice = function () {
    this.postal.sendJsonMessage('getSerialPortList');
};

IDE_Morph.prototype.serialConnect = function (portPath) {
    // We ask the postal service to deliver a serialConnect message to the serial plugin.
    // When we get a response telling us the connection was successful, we will run
    // IDE_Morph >> serialConnected
    this.postal.sendJsonMessage('serialConnect', portPath);
};

IDE_Morph.prototype.serialConnected = function (success) {
    var world = this.world(),
        dialog = new DialogBoxMorph(),
        pic = new Morph(),
        device;

    pic.setColor(new Color(0,0,0,0));
    pic.texture = 'ublocks.png';
    pic.setExtent(new Point(128, 128));

    if (success) {
        device = new DeviceMorph(this.globalVariables);
        device.name = this.newSpriteName(device.name);

        this.stage.add(device);
        this.sprites.add(device);
        this.corral.addSprite(device);
        this.selectSprite(device);

        device.fps = 5;

        dialog.inform(
            'Connection successful', 
            'µBlocks device successfully added.\n' + 
            'Happy hopping!', 
            world, 
            pic
        );

        this.flushBlocksCache();
        this.refreshPalette();
    } else {
        dialog.inform(
            'Connection failed',
            'Could not find a µBlocks device.\n' + 
            'Please make sure a device is connected\n' +
            'and the µBlocks VM is loaded into it.',
            world,
            pic
        );
    }
};

IDE_Morph.prototype.serialDisconnected = function (success) {
    if (success) {
        this.inform('Disconnected', 'µBlocks device disconnected.');
        this.flushBlocksCache();
        this.refreshPalette();
    } else {
        this.inform('Disconnection failed', 'Could not disconnect from µBlocks device.');
    }
};

IDE_Morph.prototype.createSpriteBar = function () {
    // assumes that the categories pane has already been created
    var rotationStyleButtons = [],
        thumbSize = new Point(45, 45),
        nameField,
        padlock,
        thumbnail,
        tabCorner = 15,
        tabColors = this.tabColors,
        tabBar = new AlignmentMorph('row', -tabCorner * 2),
        tab,
        symbols = ['\u2192', '\u21BB', '\u2194'],
        labels = ['don\'t rotate', 'can rotate', 'only face left/right'],
        myself = this;

    if (this.spriteBar) {
        this.spriteBar.destroy();
    }

    this.spriteBar = new Morph();
    this.spriteBar.color = this.frameColor;
    this.add(this.spriteBar);

    function addRotationStyleButton(rotationStyle) {
        var colors = myself.rotationStyleColors,
            button;

        button = new ToggleButtonMorph(
            colors,
            myself, // the IDE is the target
            function () {
                if (myself.currentSprite instanceof SpriteMorph) {
                    myself.currentSprite.rotationStyle = rotationStyle;
                    myself.currentSprite.changed();
                    myself.currentSprite.drawNew();
                    myself.currentSprite.changed();
                }
                rotationStyleButtons.forEach(function (each) {
                    each.refresh();
                });
            },
            symbols[rotationStyle], // label
            function () {  // query
                return myself.currentSprite instanceof SpriteMorph
                    && myself.currentSprite.rotationStyle === rotationStyle;
            },
            null, // environment
            localize(labels[rotationStyle])
        );

        button.corner = 8;
        button.labelMinExtent = new Point(11, 11);
        button.padding = 0;
        button.labelShadowOffset = new Point(-1, -1);
        button.labelShadowColor = colors[1];
        button.labelColor = myself.buttonLabelColor;
        button.fixLayout();
        button.refresh();
        rotationStyleButtons.push(button);
        button.setPosition(myself.spriteBar.position().add(2));
        button.setTop(button.top()
            + ((rotationStyleButtons.length - 1) * (button.height() + 2))
            );
        myself.spriteBar.add(button);
        if (myself.currentSprite instanceof StageMorph
                || myself.currentSprite instanceof DeviceMorph) {
            button.hide();
        }
        return button;
    }

    addRotationStyleButton(1);
    addRotationStyleButton(2);
    addRotationStyleButton(0);
    this.rotationStyleButtons = rotationStyleButtons;

    thumbnail = new Morph();
    thumbnail.setExtent(thumbSize);
    thumbnail.image = this.currentSprite.thumbnail(thumbSize);
    thumbnail.setPosition(
        rotationStyleButtons[0].topRight().add(new Point(5, 3))
    );
    this.spriteBar.add(thumbnail);

    if (!this.currentSprite instanceof DeviceMorph) {
        thumbnail.fps = 3;

        thumbnail.step = function () {
            if (thumbnail.version !== myself.currentSprite.version) {
                thumbnail.image = myself.currentSprite.thumbnail(thumbSize);
                thumbnail.changed();
                thumbnail.version = myself.currentSprite.version;
            }
        };
    }

    nameField = new InputFieldMorph(this.currentSprite.name);
    nameField.setWidth(100); // fixed dimensions
    nameField.contrast = 90;
    nameField.setPosition(thumbnail.topRight().add(new Point(10, 3)));
    this.spriteBar.add(nameField);
    nameField.drawNew();
    nameField.accept = function () {
        var newName = nameField.getValue();
        myself.currentSprite.setName(
            myself.newSpriteName(newName, myself.currentSprite)
        );
        nameField.setContents(myself.currentSprite.name);
    };
    this.spriteBar.reactToEdit = nameField.accept;

    // padlock
    padlock = new ToggleMorph(
        'checkbox',
        null,
        function () {
            myself.currentSprite.isDraggable =
                !myself.currentSprite.isDraggable;
        },
        localize('draggable'),
        function () {
            return myself.currentSprite.isDraggable;
        }
    );
    padlock.label.isBold = false;
    padlock.label.setColor(this.buttonLabelColor);
    padlock.color = tabColors[2];
    padlock.highlightColor = tabColors[0];
    padlock.pressColor = tabColors[1];

    padlock.tick.shadowOffset = MorphicPreferences.isFlat ?
            new Point() : new Point(-1, -1);
    padlock.tick.shadowColor = new Color(); // black
    padlock.tick.color = this.buttonLabelColor;
    padlock.tick.isBold = false;
    padlock.tick.drawNew();

    padlock.setPosition(nameField.bottomLeft().add(2));
    padlock.drawNew();
    this.spriteBar.add(padlock);
    if (this.currentSprite instanceof StageMorph ||
            this.currentSprite instanceof DeviceMorph) {
        padlock.hide();
    }

    // tab bar
    tabBar.tabTo = function (tabString) {
        var active;
        myself.currentTab = tabString;
        this.children.forEach(function (each) {
            each.refresh();
            if (each.state) {active = each; }
        });
        active.refresh(); // needed when programmatically tabbing
        myself.createSpriteEditor();
        myself.fixLayout('tabEditor');
    };

    tab = new TabMorph(
        tabColors,
        null, // target
        function () {tabBar.tabTo('scripts'); },
        localize('Scripts'), // label
        function () {  // query
            return myself.currentTab === 'scripts';
        }
    );
    tab.padding = 3;
    tab.corner = tabCorner;
    tab.edge = 1;
    tab.labelShadowOffset = new Point(-1, -1);
    tab.labelShadowColor = tabColors[1];
    tab.labelColor = this.buttonLabelColor;
    tab.drawNew();
    tab.fixLayout();
    tabBar.add(tab);

    if (this.currentSprite instanceof DeviceMorph) {
        // We haven't implemented any extra tabs for devices yet
        /*
        tab = new TabMorph(
                tabColors,
                null, // target
                function () {tabBar.tabTo('monitor'); },
                localize('Monitor'),
                function () {  // query
                    return myself.currentTab === 'monitor';
                }
                );
        tab.padding = 3;
        tab.corner = tabCorner;
        tab.edge = 1;
        tab.labelShadowOffset = new Point(-1, -1);
        tab.labelShadowColor = tabColors[1];
        tab.labelColor = this.buttonLabelColor;
        tab.drawNew();
        tab.fixLayout();
        tabBar.add(tab);
        */
    } else {
        tab = new TabMorph(
                tabColors,
                null, // target
                function () {tabBar.tabTo('costumes'); },
                localize(this.currentSprite instanceof SpriteMorph ?
                    'Costumes' : 'Backgrounds'
                    ),
                function () {  // query
                    return myself.currentTab === 'costumes';
                }
                );
        tab.padding = 3;
        tab.corner = tabCorner;
        tab.edge = 1;
        tab.labelShadowOffset = new Point(-1, -1);
        tab.labelShadowColor = tabColors[1];
        tab.labelColor = this.buttonLabelColor;
        tab.drawNew();
        tab.fixLayout();
        tabBar.add(tab);

        tab = new TabMorph(
                tabColors,
                null, // target
                function () {tabBar.tabTo('sounds'); },
                localize('Sounds'), // label
                function () {  // query
                    return myself.currentTab === 'sounds';
                }
                );
        tab.padding = 3;
        tab.corner = tabCorner;
        tab.edge = 1;
        tab.labelShadowOffset = new Point(-1, -1);
        tab.labelShadowColor = tabColors[1];
        tab.labelColor = this.buttonLabelColor;
        tab.drawNew();
        tab.fixLayout();
        tabBar.add(tab);
    }

    tabBar.fixLayout();
    tabBar.children.forEach(function (each) {
        each.refresh();
    });
    this.spriteBar.tabBar = tabBar;
    this.spriteBar.add(this.spriteBar.tabBar);

    this.spriteBar.fixLayout = function () {
        this.tabBar.setLeft(this.left());
        this.tabBar.setBottom(this.bottom());
    };
};
