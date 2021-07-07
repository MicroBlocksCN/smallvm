Files and folders:
  emscripten - GP source code and Emscripten build script
  MicroBlocks - set of files for the Chromebook app
  MicroBlocks.zip - zipped MicroBlocks folder for Chrome Web Store
  webapp - set of files for the browser web app

Assuming the emscripten environment is set up, running the buildEmcc.sh script in the emscripten folder will compile the GP code, build the embedded file system, and copy the resulting WASM files into both the MicroBlocks and webapp folders.
