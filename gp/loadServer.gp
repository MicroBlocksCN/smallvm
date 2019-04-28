reload '../ide/MicroBlocksAppMaker.gp'
reload '../ide/MicroBlocksCompiler.gp'
reload '../ide/MicroBlocksConnector.gp'
reload '../ide/MicroBlocksEditor.gp'
reload '../ide/MicroBlocksHTTPServer.gp'
reload '../ide/MicroBlocksRuntime.gp'
reload '../ide/MicroBlocksScripter.gp'
reload '../ide/MicroBlocksPatches.gp'

to startup {
	setGlobal 'server' (newMicroBlocksHTTPServer)
	restart (global 'server')
}
