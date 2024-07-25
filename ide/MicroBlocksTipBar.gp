// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Copyright 2019 John Maloney, Bernat Romagosa, and Jens Mönig

// MicroBlocksTipBar.gp - A bar that displays useful information about the item under the mouse
// Bernat Romagosa, November 2021

defineClass MicroBlocksTipBar morph title tipMorph tip contentDict iconsDict help tipColor titleColor bgColor

method initialize MicroBlocksTipBar editor {
	titleColor = (color editor 'blueGray' 50)
	tipColor = (color editor 'blueGray' 300)
	bgColor = (color editor 'blueGray' 850)
	print bgColor
	print tipColor
	print titleColor
	morph = (newMorph this)
	setClipping morph true
	setFPS morph 5

	initContents this
	initIcons this
	help = (initialize (new 'MicroBlocksHelp'))

	titleFontName = 'Arial Bold'
	titleFontSize = (14 * (global 'scale'))
	if ('Linux' == (platform)) { titleFontSize = (12 * (global 'scale')) }
	title = (newText '' titleFontName titleFontSize titleColor 'left' nil 0 0 5 3)
	addPart morph (morph title)

	tip = (newAlignment 'centered-line' 0 'bounds')
	tipMorph = (newMorph tip)
	setMorph tip tipMorph
	addPart morph tipMorph
	return this
}

method helpEntry MicroBlocksTipBar primName { return (entryForOp help primName) }
method title MicroBlocksTipBar { return title }
method setTitle MicroBlocksTipBar aTitle { setText title (localized aTitle) }
method tip MicroBlocksTipBar { return tip }

method setTip MicroBlocksTipBar aTip {
	// Tips can contain icon placeholders, like so:
	// [l] run this block [r] open context menu

	fontName = 'Arial'
	fontSize = (14 * (global 'scale'))
	if ('Linux' == (platform)) { fontSize = (12 * (global 'scale')) }

	removeAllParts tipMorph
	text = ' '
	if (isNil aTip) {
		return
	}
	for word (words (localized aTip)) {
		if (contains (keys iconsDict) word) {
			if ((count text) > 0) {
				addPart tipMorph (morph (newText text fontName fontSize tipColor 'left' nil 0 0 5 3))
				text = ' '
			}
			icon = (newMorph)
			setCostume icon (at iconsDict word)
			setPosition icon 0 0
			addPart tipMorph icon
		} else {
			text = (join text word ' ')
		}
	}
	if ((count text) > 0) {
		addPart tipMorph (morph (newText text fontName fontSize tipColor 'left' nil 0 0 5 3))
	}
	fixLayout tip
}

// drawing

method drawOn MicroBlocksTipBar ctx {
	fillRectangle (getShapeMaker ctx) (bounds morph) bgColor
}

// stepping

method step MicroBlocksTipBar {
	hand = (hand (global 'page'))
	if (and (isClass (grabbedObject hand) 'Block') (isClass (objectAt hand) 'BlocksPalette')) {
		updateTip this (objectAt hand)
	} (isBusy hand) {
		setTitle this ''
		setTip this ''
	} else {
		updateTip this (objectAt hand)
	}
}

method updateTip MicroBlocksTipBar anElement {
	contents = (contentsFor this anElement)
	setTitle this (at contents 1)
	setTip this (at contents 2)
	fixLayout this
}

method fixLayout MicroBlocksTipBar {
	scale = (global 'scale')
	page = (global 'page')
	setExtent morph (width page) (22 * scale)

	setLeft (morph title) ((left morph) + (3 * scale))
	setLeft tipMorph ((right (morph title)) + (1 * scale))

	top = (top morph)
	if ('Linux' != (platform)) { top += (2 * scale) }
	setTop (morph title) top
	setTop tipMorph top
}

// tip Contents

method initContents MicroBlocksTipBar {
	contentDict = (dictionary)
	atPut contentDict 'BooleanSlot' (array 'Boolean Input' '[l] toggle value, or drop a reporter into it.')
	atPut contentDict 'ColorSlot' (array 'Color Input' '[l] change the color, or drop a reporter into it.')
	atPut contentDict 'InputSlot' (array 'Input' '[l] edit its value, or drop a reporter into it.')
	atPut contentDict 'BlockDrawer' (array 'Block Extension' '[l] right arrow to show optional inputs, left arrow to hide.')

	atPut contentDict 'Command' (array 'Command Block' '[l] to run, or drag to build scripts. [r] menu.')
	atPut contentDict 'Hat' (array 'Hat Block' '[l] to run, or drag to build scripts. [r] menu.')
	atPut contentDict 'Reporter' (array 'Reporter Block' '[l] to see value, or drop into an input slot. [r] menu.')
	atPut contentDict 'Script' (array 'Script' '[l] to run. [r] menu.')

	atPut contentDict 'PaneResizer' (array 'Pane Divider' 'Drag to change pane width.')
	atPut contentDict 'Library' (array 'Library' '[l] to show the blocks in this library. [r] menu.')
	atPut contentDict 'BlockCategory' (array 'Block Category' '[l] to show the blocks in this category.')
	atPut contentDict 'BlocksPalette' (array 'Palette' 'Drag blocks from here to build scripts. Drop scripts here to delete them.')

	atPut contentDict 'ScriptEditor' (array 'Scripts Pane' 'Drag blocks here to build scripts. [r] menu.')
}

method contentsFor MicroBlocksTipBar anElement {
	key = (className (classOf anElement))
	if ('Button' == key) {
		return (array 'Button' (hint anElement))
	}
	block = nil
	if ('Block' == key) { block = anElement }
	if ('Text' == key) {
		if (notNil (ownerThatIsA (morph anElement) 'InputSlot')) {
			key = 'InputSlot'
		} (notNil (ownerThatIsA (morph anElement) 'Block')) {
			block = (handler (ownerThatIsA (morph anElement) 'Block'))
		}
	}
	if ('Slider' == key) {
		paneM = (ownerThatIsA (morph anElement) 'ScrollFrame')
		if (notNil paneM) {
			key = (className (classOf (contents (handler paneM))))
		}
	}
	if (notNil block) {
		topBlock = (topBlock block)
		if (and ('hat' == (type block)) (isNil (next block))) {
			key = 'Hat'
		} ('reporter' == (type block)) {
			if (block == topBlock) { // stand-alone reporter
				key = 'Reporter'
			} else { // reporter in a script
				key = 'Script'
			}
		} else {
			if (and (block == topBlock) (isNil (next block))) { // stand-alone command
				key = 'Command'
			} else {
				key = 'Script'
			}
		}
	}
	if (isClass anElement 'CategorySelector') {
		category = (categoryUnderHand anElement)
		items = (collection anElement)
		if (and (notEmpty items) ('Output' == (first items))) {
			key = 'BlockCategory'
		} else {
			key = 'Library'
		}
	}
	content = (at contentDict key)
	if (isNil content) { // no match
		devMode = false
		if devMode { return (array key '') } // show key in tip bar during development
		return (array '' '')
	}
	if (isOneOf key 'Reporter' 'Command' 'Hat') {
 		helpEntry = (helpEntry this (primName (expression block)))
 		if (notNil helpEntry) {
 			if (devMode) {
 				// just show the help string
 				fullDescription = (at helpEntry 3)
 			} else {
 				// show help string and gesture hints
				fullDescription = (join (localized (at helpEntry 3)) '    ' (localized (at content 2)))
 			}
 			content = (copy content)
 			atPut content 2 fullDescription
 		}
 	}
	return content
}

// icons

method initIcons MicroBlocksTipBar {
	iconsDict = (dictionary)
	atPut iconsDict '[l]' (leftClickLogo this)
	atPut iconsDict '[r]' (rightClickLogo this)
	atPut iconsDict '(-o)' (trueLogo this)
	atPut iconsDict '(o-)' (falseLogo this)
}

method rightClickLogo MicroBlocksTipBar {
	dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAABwAAAAkCAYAAACaJFpUAAAACXBIWXMAACRyAAAkcgG1MFKpAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAkhJREFUSInt17trFFEUx/HPLj6jaBJFRcUH
2NpYSFARBB8YiKIIEsTSRyHiX+ALW7EQxRAUIWgK0UL9C6ysRAW1EJOgJIKPqImaKDFrMWfJZPPYzZKx
8gcDe8/9nfOdO3P3XCZnci3BXjRhHVZgQYmnD914jQe4jw9l6o7RIlzCLxRS1w904E1cHRFLewZxEfWV
wrbiYyT34Qq2j7OytBZgB66iP3I/YEs5WHNqVa1YWuldprQMN4ys9uBExk0B+40jFRRuQwvOYidmlcwf
i1qDaChNXoieuKujFcDgu9Hv7hNOYWbKczzmupW8kgsxcbNC2HjA4vUIi1O+toifLwbqIvknlk8DsICn
mBe+lVG7X/IkHQpTyxRg5YAFXE95WyPWDO0xaJxm4B+sD29TxG7B8xhM9j+rBljA5fAujPEzkt3VN0VY
pcCOlL9ftLxhdGUEHMbs8HdhOI9cTGahnOQAEIxcPiNQWvkJBxloQNJl/hmwHUOlwQI6qyhWbtM8FJ0l
1InCjCpARR3GePnDeIWXEyVWu8KpqhOFf7FLR+k/8D9wysrhS/yuy5j1DUN5Sa+rRU2GsPmSA74nb6Qj
bMsQWKz9Ag5Ius2dDIF3g7Ef5uJdBHZlANsdtd9iTjHYGMEv2DyNsI34HLX3lE6ei4mfOCNZebWqiXoD
UfP0RMaTASygF9ewD6sqgKwOb4vkSRVv/kS5xLWSk3rQ2EO119gP0t5xfIO4jTWlxXOTgOslu6oBGyTf
fbXGPuoBfMV7PMFj3DPSUEbpLyCd4FksPh5fAAAAAElFTkSuQmCC'
	data = '
iVBORw0KGgoAAAANSUhEUgAAAA4AAAASCAYAAABrXO8xAAAACXBIWXMAABI5AAASOQEodzeCAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAQBJREFUOI2l07EuBFEUxvGfmdVSoeAlSBD2
Hai1REJJKd6EByCh8AYkhEhQUNlCqdmwG0RjjGLu2DXZzc7El9zk5nznf+45uffS0TA2cYEWXsJq4Rwb
IeePJnCNA8wi7vJizOEQVxjPjRousVWshjucYgURtkNHMazhqAcEX0jxjhMM4RircIaFAWCKN6xjMXSh
WZipH5jiOYzWjAKU9AGLGgtgHJUEcn3L5lQbkJjiI+xj2ZV8lgHn8xNkj+Gp23wt32mHqTrjr/4FJhUL
xEgiPKBeAazjHpZxg5ES0ChusZQHdtGQvcXJHsBU8BrYKZoz2Mcj2jofuR1ie5jOk38AxyA7mTaRsDIA
AAAASUVORK5CYII='
	if (2 == (global 'scale')) { data = dataRetina }
	return (readFrom (new 'PNGReader') (base64Decode data))
}

method leftClickLogo MicroBlocksTipBar {
	dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAABwAAAAkCAYAAACaJFpUAAAACXBIWXMAACRyAAAkcgG1MFKpAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAkVJREFUSInt18uLTnEcx/HXM0lmiEEuRS5l
w0ZZSChZaHLPpSRbkZKFP0DIVlYjkxTJLUmS/8DCSpNihXFpKJdxNy7Dsfh9h+M8z8w8M+ZYzbdOPb/v
9/v7vH+X73N+51fRv03FRqzHPMzA+ELOO3TiPq7jGl4OoFtlk3EMX5Hlnk94iAfxPAxfPucLjmJSvbAV
McIM79GKVTVmlrfxkXMcH6LvCywfCLY9N6uTmFbvKHM2Haf8me22vhKXBuwbdhZio9GCg2jD2TrAu/E9
oEuKwWY8j1HtKoD245W/9+ljHUDYE/mdCltyJAJncr4puFkADRZIWo0Mh3sdE0Pgs1T2MBbtfcAGC5wZ
2h8wAXaESFsu6XQ/sMECSQWYSUXpQjTWRHAhfgwzcF30Owd3otG7qa0DwIYCnBD92kkV+D4XfFwCkLSH
L+AnHoVzTLTLAD7CzwZUQoT0V6gMQawey1BpKDiL7WG3IqAT3f8T2INLZQJJa9uRazfjhuEvmg5ko2oE
3mItFmC+2vvaMwTgbyvOsCzrQFZ6VRZtBDgCHLRV8CZ+TyyZ9Q49DdL7sxlNJcLGSQf8swbcC+fKEoG9
2ndhq/S2uVwi8EowtkAjnoajpQTY6tB+In1RIH2xZVIBLRtG2GK8Du0NxeChCHyW7hCN/wBqCr3u0DzQ
V+K+AGbowglswqw6ILMjt01aqd7B7x2o41xclG49xYO3S/WFtKtG3hecx5yieH9faJOwWbpqLZLufc2q
l7pbOrSf4zZu4WoMpMp+AZVe3/Vj4nt+AAAAAElFTkSuQmCC'
	data = '
iVBORw0KGgoAAAANSUhEUgAAAA4AAAASCAYAAABrXO8xAAAACXBIWXMAABI5AAASOQEodzeCAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAQVJREFUOI2l008rRFEYx/GPe4clsWDByjug
KOY9sLZFYicbJe+EF0DKyh7lX4oNK16BmsxMiMVM1+Ke21zTNWbyq+d0zvP8vs+p53RoqR8buEQNryFq
uMB68PzQGG5xgBnEuVqMWRziBqNZoYRrbCLCEk5x394dW7gKjBUchc4neEOCRgEIx1iGc8xhG+8B6gTO
4wwq4baXHNQJLKESBWgAI78Y29VAHOUSSZcg0inCp/QpvvARomOjPlQxHM6TuX2i+EkEJl16VDX621Os
f4HNHhvEaEZ4RLkHsIwHWMQdBruAhqSTXsgSu3jGKsYLgAmsBc9Oe3Ea+3hCXesj10NuD1OZ+Rsiaz99
cgtWngAAAABJRU5ErkJggg=='
	if (2 == (global 'scale')) { data = dataRetina }
	return (readFrom (new 'PNGReader') (base64Decode data))
}

method trueLogo MicroBlocksTipBar {
	dataRetina = '
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
QmCC'
	data = '
iVBORw0KGgoAAAANSUhEUgAAABoAAAAOCAYAAAAxDQxDAAAACXBIWXMAABMLAAATCwErAKTWAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAlVJREFUOI2VlMFPE0EUxr8322XZsmBLlsYC
lmAgxEJDgopH41EPEtn/wcSIxpsX48lo4s1o4t9g0hI8ePNgTDx4JDWlhcZAONRDuy3ttoWys88DFDBi
d/2dXjLfm2/mZeYjnGF5eXmCiB7LkLwnPDFKHmkIgBCiWzITt1jyVwArmUzmZ3eBuoVlWQ8g8MaJOLw9
u93XMBtwVffcjYkJEz8mMJ4fR3+4H7HhGDRNg+d52Gvswa7YR6Yev8xkMs9OjCzLesjgt9lbWSpeLYKJ
/318BhY/LSKxlcDM1AxM0wQR/SHpdDrYLG6iZtcA4HU6nX5KlmVdZuJC9mY2tHV9y3dMk+uTWPi8gPnU
PIaGhnpqcxs52LYNAs0KInrSjDS5eK3oa0JMSH1LYWx0zNcEAKanpiFIQEr5XkhF3t1N7qo9x3XMcGkY
alNF/GLcVwsAqqrCHDFBCt0QJCnuRJxAjUbVACkEXdcD6QHAGDBATJrwl57C8L/1uRAgWOGSUTUC6ZvR
Jlgy2u12YA/HccDgAyFc8TGRS3SIybfJjts4HDhE6VcpkInruiiXy2DJ35W5ubmCeqA+ckOuUhmr9O4k
oKN1YKwbiEai0LTewZEv5NFqt+B53m0ll8vVkleS5dhO7I5UJdmj9pm8+JtarIbB6iD28/vQ+3WEw+Fz
P+xGYQNVuwoAr1ZXVz+cjaD7TPyueaHJO6mdvrpZDxRB+oCOkejISQTVG3VUKhXg6O28SKfTz4+HccrS
0tKlUCh0FKpSjBP/X6gymBncIqYvruuurK2tbXc1vwHLNft2gdi8QgAAAABJRU5ErkJggg=='
	if (2 == (global 'scale')) { data = dataRetina }
	return (readFrom (new 'PNGReader') (base64Decode data))
}

method falseLogo MicroBlocksTipBar {
	dataRetina = '
iVBORw0KGgoAAAANSUhEUgAAADMAAAAcCAYAAADMW4fJAAAACXBIWXMAACYWAAAmFgGz33QBAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAABSVJREFUWIXFmE1sVFUUx3/nzpuZzsyjbWaE
RqIBonwUCGm6MHGhiYkaE6QJpdUFwRiDC5YmLkS3sEAisjXRaEQWZtIxtmFhWGoMxgQWaNs0xUACCB1m
aOnMtPO+jov5YGgLbTrP8N/d++65/3veuefjHmEVHDhwIGlZ1n5jzFFgH9AJJABZTbYNeCIyo6q3gb9U
ddR13V/GxsYqTxJ67IEOHz7cWa1WT6jqMcAK+7TrQElEzsbj8dPnz59/sNKCFZUZHBwcEpHvqVng4WIR
otEosVgMYwyO4+A4DkEQPCK/QYRtsRgdsj7jBUA5CHgQBNzxPPxHP+dV9WgulxtdTRkZHBw8KSLHWye7
urrYtGkT6XSaWCz2KHEQMDc3x71795iZmWkqFhdhfyrFC9HouhRqoKrKP67LpcVF7vlNtQLgs5GRkVOA
NiYjrYJDQ0OngE8a42Qyya5du9iyZQu2bROJPLIcqFkrkUiQyWTo6enB8zzK5TI+MOk4dEUibFpBbq2w
RNgYidAXj5MU4YbvozUjvN7b21udmJj4bZkyhw4degc42xin02n27t1LMplcO7FlkclkSCaTFItFVJVr
rsvz0ShdxqxbIaid/lnLYotlMe26eICIvLZ79+4rExMTU01lhoeHu1T1d+qOvnHjRnp7ezHrPEAqlSKV
SpHP51HgH89jXzyOtU4fasUGY3jOshh3XRREVd/o7+//6urVq1UDEATBGSAOYNs2O3bsQNokzmQybN26
FYBKEHBpYaE9LVqw2bJ4taMDABF5ZmFh4WMAOXLkSKpSqcwBERGhr68P27ZDIVVVLl++TKVSISLC0c5O
Otu8bg0EwDdzc8zWAk7JcZweUyqV3qV+3TKZTGiKQC04NKzjqzLlOKHtbYCXEs3MYcdisTeNMebDxkxP
T09oZA2k02ksq5Zzp1w31L1fjEabuUVVB4yI7AQwxtDd3R0qGdSsk8lkALjtefiqq0isHSkRMvWwLyJ7
jaqmADo6OtYdvVZDon4dFCgtqRbaRYsPbjZAFFiW2cNE697lEC0DkHwYdXv+H1M8JRjABXBCjDRL0bq3
HfJVbrH0HSMiZYBqtbqs+g0LC/WEKdScNky0+OC/BpgE8H2f+/fvh0oEtcRZKBSAWuaOhKhMKQhaK+mr
xvf9rxujmZmZ0IgaKBaLeJ4HwPY2nwNLMV2rzwAQkVFj2/aPUHv/FAoF5ufnQyNTVa5fvw5ARISdIUZM
H/izWm0M56vV6kVz7ty5soh82yCfnp4OzXdu3rxJpVJ7tvfH46HVZQCXFxeZrV8xETkzNjZWMfXBR8AC
QKlUYmpqCm0zHxQKhaZVEiK8XK9yw8Atz+PXh1V43nGcL6AWmslmsyVjzHvNr/k84+Pj+L6/fKc1IJ/P
Mzk5SYNgwLaJh+T4tzyPn0qlRl8gAN4fHR2dh5aX5vj4+PiePXviwCtQC6fFYpFEIkHHGv+q4zhcu3aN
GzduoKoI8FYyyfYQfCVQ5Uq1yoVymUbWEpHjIyMj3zXWLPtdQ0NDJ1X109a57u7uZkMjuiQiqSqzs7MU
CgXu3r3b9LcY8LZtt93QWKw/vf9YXKTQ0tBQ1eO5XO7z1rUr2v7gwYODxpgfWKXV5Lruisl2gzFsi0bb
bjXN1VtNS8LRjKp+kMvlLiyVeyzbwMDAhmg0egI4Rr0YfcqYB740xpzOZrOllRas+uuGh4cTvu/vF5Gj
wD5V7QIS0m6T4MnwgLvATeBvVf05EolczGazT2wk/AfDzRDiodhsigAAAABJRU5ErkJggg=='
	data = '
iVBORw0KGgoAAAANSUhEUgAAABoAAAAOCAYAAAAxDQxDAAAACXBIWXMAABMLAAATCwErAKTWAAAAGXRF
WHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAj5JREFUOI2VlEFrE1EUhb/7Jpl0aGMwTcF0
J9ZqanGnm4K4cePCRUPJb5AiuHAhrsWNK0uhCP6DphF/gCCiC627Bim2uJC2kSYNRNLOTGbee26aatU2
41k9eOe8cznv3iv8hkqlciGKokVHqRuIeIAAGGNIAgWhgm0t8lJEFpaXl7/176R/mJ2dfaKUeiggo4UC
2WwWpRRBENDe28P3fUqZDNPp9IlGEdDSmnoY9jrWioV71Wr1+ZFRuVx+KiIP8vk8ExMTuK577AFrLbu7
u3zd3GQyleL28PCvCv8BC3wKAt74vgXmV1ZWlqRSqUxrrddG83lKU1OnRtPpdKivrXHL87iayZzKBfgQ
BLwLggiRS0prvaREuDg5OVCYy+UoFou8D0PsQDZcHxrijIg1xtxXwLXC2BipVCqBFIrj43S15nscD+QK
UHJd14E7SkQy2Ww2kQmA53k4StFO2Il5x8HAuLLWYm2SIP6u9n+ggLDb7SYW+L6PNoazSiXit7VGiWwr
a+3HVrNJnCBzgEajwYjjcC7Bnxpr+dzr9Qy8Uq7r3jXWsrGxMTDCTqdDY2eHmUwmUXSrYcgPYySO42dO
vV5vlkqlYd/3Z/b398nlcjiOc0zQH9gv6+tcdl1mPG/gwK4GAW8PDqwoNV+r1V4f8cvl8mOl1COslUKh
wMjhCgrDkHarxcHhCrqSTp9oEgHNOKYeRb2O1iAyX61WX8AfzTM3N3feGLOoRG4CHiL/tVQFQge2YqhZ
axdqtdpW/+4nM5r0sHyILZQAAAAASUVORK5CYII='
	if (2 == (global 'scale')) { data = dataRetina }
	return (readFrom (new 'PNGReader') (base64Decode data))
}
