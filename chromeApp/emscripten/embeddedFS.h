// embeddedFS.h
// John Maloney, April, 2016

OBJ appPath();
OBJ embeddedFileList(FILE *f);
OBJ extractEmbeddedFile(FILE *f, char *fileName, int isBinary);
gp_boolean importLibrary();
FILE * openAppFile();
