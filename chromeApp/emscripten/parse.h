// parse.h - GP parser
// John Maloney, October 2013

// Value returned when input from prompt is incomplete
#define PARSE_INCOMPLETE ((OBJ) -2)

typedef struct _parser {
	gp_boolean complete;
	gp_boolean inString;
	int bufSize;
	int bufPos;
	unsigned char *buf;
	char *fileName;
	int lineNumber;
	OBJ cachedFileName;
	OBJ cachedGetVarPrim;
} parser;

gp_boolean parse_atEnd(parser *p);
int parse_firstChar(parser *p);
OBJ parse_nextScript(parser *p, gp_boolean fromPrompt);
void parse_runFile(char *fName);
void parse_runScriptsInBuffer(char *fName, char *buffer, int bufSize);
OBJ parse_scriptFromPrompt(parser *p, char *script, int byteCount);
void parse_setSourceString(parser *p, char *fileName, char *s, int byteCount);
