// To test it:
// ./gp-linux64bit runtime/lib/* renderScript.gp - --scriptString "script nil 10 10 { whenStarted; '[display:mbDisplayOff]'; forever { setUserLED true; waitMillis 200; setUserLED false; waitMillis 200; } }" --fileName 'script.png' --scale 4

to startup {
	scriptString = (at (commandLine) ((indexOf (commandLine) '--scriptString') + 1))
	fileName = (at (commandLine) ((indexOf (commandLine) '--fileName') + 1))
	scale = (at (commandLine) ((indexOf (commandLine) '--scale') + 1))
	script = (last (argList (last (parse scriptString))))
	setGlobal 'scale' 2
	block = (toBlock (last (argList (last (parse scriptString)))))
	fixBlockColor block
	exportAsImageScaled block (toNumber scale) nil fileName
	exit
}
