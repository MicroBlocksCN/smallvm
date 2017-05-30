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

modules.upatch = '2017-May-30';


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

// SpriteIconMorph

SpriteMorph.prototype.blocks.analogReadOp = {
    only: SpriteMorph,
    type: 'reporter',
    category: 'sensing',
    spec: 'read analog pin %n',
    defaults: [1]
};
SpriteMorph.prototype.blocks.analogWriteOp = {
    only: SpriteMorph,
    type: 'command',
    category: 'sensing',
    spec: 'set analog pin %n to %n',
    defaults: [1, 1023]
};
SpriteMorph.prototype.blocks.digitalReadOp = {
    only: SpriteMorph,
    type: 'reporter',
    category: 'sensing',
    spec: 'read digital pin %n',
    defaults: [1]
};
SpriteMorph.prototype.blocks.digitalWriteOp = {
    only: SpriteMorph,
    type: 'command',
    category: 'sensing',
    spec: 'set digital pin %n to %b',
    defaults: [1, true]
};
SpriteMorph.prototype.blocks.setLEDOp = {
    only: SpriteMorph,
    type: 'command',
    category: 'sensing',
    spec: 'set user LED %b',
    defaults: [true]
};
SpriteMorph.prototype.blocks.microsOp = {
    only: SpriteMorph,
    type: 'reporter',
    category: 'sensing',
    spec: 'micros'
};
SpriteMorph.prototype.blocks.millisOp = {
    only: SpriteMorph,
    type: 'reporter',
    category: 'sensing',
    spec: 'millis'
};
SpriteMorph.prototype.blocks.noop = {
    only: SpriteMorph,
    type: 'command',
    category: 'sensing',
    spec: 'no op'
};
SpriteMorph.prototype.blocks.peekOp = {
    only: SpriteMorph,
    type: 'reporter',
    category: 'sensing',
    spec: 'memory at %n',
    defaults: [0]
};
SpriteMorph.prototype.blocks.pokeOp = {
    only: SpriteMorph,
    type: 'command',
    category: 'sensing',
    spec: 'set memory at %n to %n',
    defaults: [0, 0]
};
SpriteMorph.prototype.blocks.waitMicrosOp = {
    only: SpriteMorph,
    type: 'command',
    category: 'control',
    spec: 'wait %n microsecs',
    defaults: [10000]
};
SpriteMorph.prototype.blocks.waitMillisOp = {
    only: SpriteMorph,
    type: 'command',
    category: 'control',
    spec: 'wait %n millisecs',
    defaults: [500]
};
SpriteMorph.prototype.blocks.doStopDevice = {
    only: SpriteMorph,
    type: 'command',
    category: 'control',
    spec: 'stop all %stop'
},
SpriteMorph.prototype.blocks.reportDeviceLessThan = {
    only: SpriteMorph,
    type: 'predicate',
    category: 'operators',
    spec: '%n < %n',
    defaults: [3, 4]
};
SpriteMorph.prototype.blocks.newArray = {
    only: SpriteMorph,
    type: 'reporter',
    category: 'lists',
    spec: 'new array %n',
    defaults: [10]
};
SpriteMorph.prototype.blocks.newByteArray = {
    only: SpriteMorph,
    type: 'reporter',
    category: 'lists',
    spec: 'new byte array %n',
    defaults: [10]
};
SpriteMorph.prototype.blocks.fillArray = {
    only: SpriteMorph,
    type: 'command',
    category: 'lists',
    spec: 'fill %l with %n',
    defaults: [null, 0]
};


SpriteMorph.prototype.blockTemplates = function (category) {
    var blocks = [], myself = this, varNames, button,
        cat = category || 'motion', txt,
        inheritedVars = this.inheritedVariableNames();

    function block(selector, isGhosted) {
        if (StageMorph.prototype.hiddenPrimitives[selector]) {
            return null;
        }
        var newBlock = SpriteMorph.prototype.blockForSelector(selector, true);
        newBlock.isTemplate = true;
        if (isGhosted) {newBlock.ghost(); }
        return newBlock;
    }

    function variableBlock(varName) {
        var newBlock = SpriteMorph.prototype.variableBlock(varName);
        newBlock.isDraggable = false;
        newBlock.isTemplate = true;
        if (contains(inheritedVars, varName)) {
            newBlock.ghost();
        }
        return newBlock;
    }

    function watcherToggle(selector) {
        if (StageMorph.prototype.hiddenPrimitives[selector]) {
            return null;
        }
        var info = SpriteMorph.prototype.blocks[selector];
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
        if (this.isDevice) {
            nop();
        } else {
            blocks.push(block('forward'));
            blocks.push(block('turn'));
            blocks.push(block('turnLeft'));
            blocks.push('-');
            blocks.push(block('setHeading'));
            blocks.push(block('doFaceTowards'));
            blocks.push('-');
            blocks.push(block('gotoXY'));
            blocks.push(block('doGotoObject'));
            blocks.push(block('doGlide'));
            blocks.push('-');
            blocks.push(block('changeXPosition'));
            blocks.push(block('setXPosition'));
            blocks.push(block('changeYPosition'));
            blocks.push(block('setYPosition'));
            blocks.push('-');
            blocks.push(block('bounceOffEdge'));
            blocks.push('-');
            blocks.push(watcherToggle('xPosition'));
            blocks.push(block('xPosition', this.inheritsAttribute('x position')));
            blocks.push(watcherToggle('yPosition'));
            blocks.push(block('yPosition', this.inheritsAttribute('y position')));
            blocks.push(watcherToggle('direction'));
            blocks.push(block('direction', this.inheritsAttribute('direction')));
        }

    } else if (cat === 'looks') {

        if (this.isDevice) {
            blocks.push(block('bubble'));
        } else {
            blocks.push(block('doSwitchToCostume'));
            blocks.push(block('doWearNextCostume'));
            blocks.push(watcherToggle('getCostumeIdx'));
            blocks.push(block('getCostumeIdx', this.inheritsAttribute('costume #')));
            blocks.push('-');
            blocks.push(block('doSayFor'));
            blocks.push(block('bubble'));
            blocks.push(block('doThinkFor'));
            blocks.push(block('doThink'));
            blocks.push('-');
            blocks.push(block('changeEffect'));
            blocks.push(block('setEffect'));
            blocks.push(block('clearEffects'));
            blocks.push('-');
            blocks.push(block('changeScale'));
            blocks.push(block('setScale'));
            blocks.push(watcherToggle('getScale'));
            blocks.push(block('getScale', this.inheritsAttribute('size')));
            blocks.push('-');
            blocks.push(block('show'));
            blocks.push(block('hide'));
            blocks.push('-');
            blocks.push(block('comeToFront'));
            blocks.push(block('goBack'));
        }

    // for debugging: ///////////////

        if (this.world().isDevMode) {
            blocks.push('-');
            txt = new TextMorph(localize(
                'development mode \ndebugging primitives:'
            ));
            txt.fontSize = 9;
            txt.setColor(this.paletteTextColor);
            blocks.push(txt);
            blocks.push('-');
            blocks.push(block('reportCostumes'));
            blocks.push('-');
            blocks.push(block('log'));
            blocks.push(block('alert'));
            blocks.push('-');
            blocks.push(block('doScreenshot'));
        }

    /////////////////////////////////

    } else if (cat === 'sound') {

        if (this.isDevice) {
            nop();
        } else {
            blocks.push(block('playSound'));
            blocks.push(block('doPlaySoundUntilDone'));
            blocks.push(block('doStopAllSounds'));
            blocks.push('-');
            blocks.push(block('doRest'));
            blocks.push('-');
            blocks.push(block('doPlayNote'));
            blocks.push('-');
            blocks.push(block('doChangeTempo'));
            blocks.push(block('doSetTempo'));
            blocks.push(watcherToggle('getTempo'));
            blocks.push(block('getTempo'));
        }

    // for debugging: ///////////////

        if (this.world().isDevMode) {
            blocks.push('-');
            txt = new TextMorph(localize(
                'development mode \ndebugging primitives:'
            ));
            txt.fontSize = 9;
            txt.setColor(this.paletteTextColor);
            blocks.push(txt);
            blocks.push('-');
            blocks.push(block('reportSounds'));
        }

    } else if (cat === 'pen') {

        if (this.isDevice) {
            nop();
        } else {
            blocks.push(block('clear'));
            blocks.push('-');
            blocks.push(block('down'));
            blocks.push(block('up'));
            blocks.push('-');
            blocks.push(block('setColor'));
            blocks.push(block('changeHue'));
            blocks.push(block('setHue'));
            blocks.push('-');
            blocks.push(block('changeBrightness'));
            blocks.push(block('setBrightness'));
            blocks.push('-');
            blocks.push(block('changeSize'));
            blocks.push(block('setSize'));
            blocks.push('-');
            blocks.push(block('doStamp'));
            blocks.push(block('floodFill'));
        }

    } else if (cat === 'control') {

        if (this.isDevice) {
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
        } else {

            blocks.push(block('receiveGo'));
            blocks.push(block('receiveKey'));
            blocks.push(block('receiveInteraction'));
            blocks.push(block('receiveCondition'));
            blocks.push(block('receiveMessage'));
            blocks.push('-');
            blocks.push(block('doBroadcast'));
            blocks.push(block('doBroadcastAndWait'));
            blocks.push(watcherToggle('getLastMessage'));
            blocks.push(block('getLastMessage'));
            blocks.push('-');
            blocks.push(block('doWarp'));
            blocks.push('-');
            blocks.push(block('doWait'));
            blocks.push(block('doWaitUntil'));
            blocks.push('-');
            blocks.push(block('doForever'));
            blocks.push(block('doRepeat'));
            blocks.push(block('doUntil'));
            blocks.push('-');
            blocks.push(block('doIf'));
            blocks.push(block('doIfElse'));
            blocks.push('-');
            blocks.push(block('doReport'));
            blocks.push('-');
        /*
        // old STOP variants, migrated to a newer version, now redundant
            blocks.push(block('doStopBlock'));
            blocks.push(block('doStop'));
            blocks.push(block('doStopAll'));
        */
            blocks.push(block('doStopThis'));
            blocks.push(block('doStopOthers'));
            blocks.push('-');
            blocks.push(block('doRun'));
            blocks.push(block('fork'));
            blocks.push(block('evaluate'));
            blocks.push('-');
        /*
        // list variants commented out for now (redundant)
            blocks.push(block('doRunWithInputList'));
            blocks.push(block('forkWithInputList'));
            blocks.push(block('evaluateWithInputList'));
            blocks.push('-');
        */
            blocks.push(block('doCallCC'));
            blocks.push(block('reportCallCC'));
            blocks.push('-');
            blocks.push(block('receiveOnClone'));
            blocks.push(block('createClone'));
            blocks.push(block('removeClone'));
            blocks.push('-');
            blocks.push(block('doPauseAll'));
        }

    } else if (cat === 'sensing') {

        if (this.isDevice) {
            blocks.push(block('analogReadOp'));
            blocks.push(block('analogWriteOp'));
            blocks.push('-');
            blocks.push(block('digitalReadOp'));
            blocks.push(block('digitalWriteOp'));
            blocks.push('-');
            blocks.push(block('setLEDOp'));
            blocks.push('-');
            blocks.push(block('microsOp'));
            blocks.push(block('millisOp'));
            blocks.push('-');
            blocks.push(block('noop'));
            blocks.push('-');
            blocks.push(block('peekOp'));
            blocks.push(block('pokeOp'));
        } else {
            blocks.push(block('reportTouchingObject'));
            blocks.push(block('reportTouchingColor'));
            blocks.push(block('reportColorIsTouchingColor'));
            blocks.push('-');
            blocks.push(block('doAsk'));
            blocks.push(watcherToggle('getLastAnswer'));
            blocks.push(block('getLastAnswer'));
            blocks.push('-');
            blocks.push(watcherToggle('reportMouseX'));
            blocks.push(block('reportMouseX'));
            blocks.push(watcherToggle('reportMouseY'));
            blocks.push(block('reportMouseY'));
            blocks.push(block('reportMouseDown'));
            blocks.push('-');
            blocks.push(block('reportKeyPressed'));
            blocks.push('-');
            blocks.push(block('reportDistanceTo'));
            blocks.push('-');
            blocks.push(block('doResetTimer'));
            blocks.push(watcherToggle('getTimer'));
            blocks.push(block('getTimer'));
            blocks.push('-');
            blocks.push(block('reportAttributeOf'));

            if (SpriteMorph.prototype.enableFirstClass) {
                blocks.push(block('reportGet'));
            }
            blocks.push('-');

            blocks.push(block('reportURL'));
            blocks.push('-');
            blocks.push(block('reportIsFastTracking'));
            blocks.push(block('doSetFastTracking'));
            blocks.push('-');
            blocks.push(block('reportDate'));
        }

    // for debugging: ///////////////

        if (this.world().isDevMode) {

            blocks.push('-');
            txt = new TextMorph(localize(
                'development mode \ndebugging primitives:'
            ));
            txt.fontSize = 9;
            txt.setColor(this.paletteTextColor);
            blocks.push(txt);
            blocks.push('-');
            blocks.push(watcherToggle('reportThreadCount'));
            blocks.push(block('reportThreadCount'));
            blocks.push(block('colorFiltered'));
            blocks.push(block('reportStackSize'));
            blocks.push(block('reportFrameCount'));
        }

    } else if (cat === 'operators') {
        if (this.isDevice) {
            blocks.push(block('reportSum'));
            blocks.push(block('reportDifference'));
            blocks.push(block('reportProduct'));
            blocks.push(block('reportQuotient'));
            blocks.push('-');
//+++            blocks.push(block('reportLessThan'));
            blocks.push(block('reportDeviceLessThan'));
        } else {
            blocks.push(block('reifyScript'));
            blocks.push(block('reifyReporter'));
            blocks.push(block('reifyPredicate'));
            blocks.push('#');
            blocks.push('-');
            blocks.push(block('reportSum'));
            blocks.push(block('reportDifference'));
            blocks.push(block('reportProduct'));
            blocks.push(block('reportQuotient'));
            blocks.push('-');
            blocks.push(block('reportModulus'));
            blocks.push(block('reportRound'));
            blocks.push(block('reportMonadic'));
            blocks.push(block('reportRandom'));
            blocks.push('-');
            blocks.push(block('reportLessThan'));
            blocks.push(block('reportEquals'));
            blocks.push(block('reportGreaterThan'));
            blocks.push('-');
            blocks.push(block('reportAnd'));
            blocks.push(block('reportOr'));
            blocks.push(block('reportNot'));
            blocks.push(block('reportBoolean'));
            blocks.push('-');
            blocks.push(block('reportJoinWords'));
            blocks.push(block('reportTextSplit'));
            blocks.push(block('reportLetter'));
            blocks.push(block('reportStringSize'));
            blocks.push('-');
            blocks.push(block('reportUnicode'));
            blocks.push(block('reportUnicodeAsLetter'));
            blocks.push('-');
            blocks.push(block('reportIsA'));
            blocks.push(block('reportIsIdentical'));

            if (true) { // (Process.prototype.enableJS) {
                blocks.push('-');
                blocks.push(block('reportJSFunction'));
            }
        }

    // for debugging: ///////////////

        if (this.world().isDevMode) {
            blocks.push('-');
            txt = new TextMorph(localize(
                'development mode \ndebugging primitives:'
            ));
            txt.fontSize = 9;
            txt.setColor(this.paletteTextColor);
            blocks.push(txt);
            blocks.push('-');
            blocks.push(block('reportTypeOf'));
            blocks.push(block('reportTextFunction'));
        }

    /////////////////////////////////

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

        if (this.isDevice) {
            nop();
        } else {
            blocks.push(block('doShowVar'));
            blocks.push(block('doHideVar'));
        }

        blocks.push(block('doDeclareVariables'));

    // inheritance:

        if (StageMorph.prototype.enableInheritance) {
            blocks.push('-');
            blocks.push(block('doDeleteAttr'));
        }

    ///////////////////////////////

        blocks.push('=');

        if (this.isDevice) {
            blocks.push(block('newArray'));
            blocks.push(block('newByteArray'));
            blocks.push('-');
            blocks.push(block('fillArray'));
            blocks.push('-');
            blocks.push(block('reportListItem'));
            blocks.push('-');
            blocks.push(block('doReplaceInList'));
        } else {
            blocks.push(block('reportNewList'));
            blocks.push('-');
            blocks.push(block('reportCONS'));
            blocks.push(block('reportListItem'));
            blocks.push(block('reportCDR'));
            blocks.push('-');
            blocks.push(block('reportListLength'));
            blocks.push(block('reportListContainsItem'));
            blocks.push('-');
            blocks.push(block('doAddToList'));
            blocks.push(block('doDeleteFromList'));
            blocks.push(block('doInsertInList'));
            blocks.push(block('doReplaceInList'));
        }

    // for debugging: ///////////////

        if (this.world().isDevMode) {
            blocks.push('-');
            txt = new TextMorph(localize(
                'development mode \ndebugging primitives:'
            ));
            txt.fontSize = 9;
            txt.setColor(this.paletteTextColor);
            blocks.push(txt);
            blocks.push('-');
            blocks.push(block('reportMap'));
            blocks.push('-');
            blocks.push(block('doForEach'));
            blocks.push(block('doShowTable'));
        }

    /////////////////////////////////

        blocks.push('=');

        if (StageMorph.prototype.enableCodeMapping) {
            blocks.push(block('doMapCodeOrHeader'));
            blocks.push(block('doMapValueCode'));
            blocks.push(block('doMapListCode'));
            blocks.push('-');
            blocks.push(block('reportMappedCode'));
            blocks.push('=');
        }

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

SpriteIconMorph.prototype.userMenu = function () {
    var menu = new MenuMorph(this),
        myself = this;
    if (this.object instanceof StageMorph) {
        menu.addItem(
            'pic...',
            function () {
                var ide = myself.parentThatIsA(IDE_Morph);
                ide.saveCanvasAs(
                    myself.object.fullImageClassic(),
                    this.object.name,
                    true
                );
            },
            'open a new window\nwith a picture of the stage'
        );
        return menu;
    }
    if (!(this.object instanceof SpriteMorph)) {return null; }

    // +++
    menu.addItem(
        (this.object.isDevice ? "disable" : "enable") + " µblocks",
        function () {myself.object.toggleDevice(); }
    );

    menu.addItem("show", 'showSpriteOnStage');
    menu.addLine();
    menu.addItem("duplicate", 'duplicateSprite');
    menu.addItem("delete", 'removeSprite');
    menu.addLine();
    if (StageMorph.prototype.enableInheritance) {
        menu.addItem("parent...", 'chooseExemplar');
    }
    if (this.object.anchor) {
        menu.addItem(
            localize('detach from') + ' ' + this.object.anchor.name,
            function () {myself.object.detachFromAnchor(); }
        );
    }
    if (this.object.parts.length) {
        menu.addItem(
            'detach all parts',
            function () {myself.object.detachAllParts(); }
        );
    }
    menu.addItem("export...", 'exportSprite');
    return menu;
};

SpriteMorph.prototype.toggleDevice = function () {
    var ide = this.parentThatIsA(IDE_Morph);
    this.isDevice = !this.isDevice;
    if (ide) {
        ide.flushBlocksCache();
        ide.refreshPalette();
    }
};

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
    if (myself.scriptTarget().isDevice) {
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

