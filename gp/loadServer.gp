reload '../ide/MicroBlocksAppMaker.gp'
reload '../ide/MicroBlocksCompiler.gp'
reload '../ide/MicroBlocksConnector.gp'
reload '../ide/MicroBlocksEditor.gp'
reload '../ide/MicroBlocksRuntime.gp'
reload '../ide/MicroBlocksScripter.gp'
reload '../ide/MicroBlocksPatches.gp'

to startup {
	setGlobal 'server' (newMicroBlocksConnector)
	restart (global 'server')
}
