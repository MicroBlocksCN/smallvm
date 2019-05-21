reload '../ide/MicroBlocksAppMaker.gp'
reload '../ide/MicroBlocksCompiler.gp'
reload '../ide/MicroBlocksDataGraph.gp'
reload '../ide/MicroBlocksEditor.gp'
reload '../ide/MicroBlocksRuntime.gp'
reload '../ide/MicroBlocksScripter.gp'
reload '../ide/MicroBlocksThingServer.gp'
reload '../ide/MicroBitDisplaySlot.gp'
reload '../ide/MicroBlocksPatches.gp'

to startup {
	setGlobal 'server' (newMicroBlocksThingServer)
	run (global 'server')
}
