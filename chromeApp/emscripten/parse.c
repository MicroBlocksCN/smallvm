#include <stdio.h>
#include <string.h>
#include "mem.h"
#include "dict.h"
#include "interp.h"
#include "parse.h"

// Temporary class used only within the parser to distinguish quoted and unquoted strings
#define QuotedStringClass BinaryDataClass

// ***** Stream Operations *****

static inline int peek(parser *p) { return (p->bufPos < p->bufSize) ? (p->buf)[p->bufPos] : EOF; }
static inline int peek2(parser *p) { return ((p->bufPos + 1) < p->bufSize) ? (p->buf)[p->bufPos + 1] : EOF; }
static inline int next(parser *p) { return (p->bufPos < p->bufSize) ? (p->buf)[p->bufPos++] : EOF; }

static inline void skip(parser *p, int offset) {
	p->bufPos += offset;
	if (p->bufPos < 0) p->bufPos = 0;
	if (p->bufPos > p->bufSize) p->bufPos = p->bufSize;
}

static inline gp_boolean isNewLine(int c) {
	return (('\n' == c) || ('\r' == c));
}

static void skipNewLine(parser *p) {
	// Consume a line ending and increment lineNumber. Assume stream is
	// positioned at a newline ('\n') or carriage return ('\r') character.
	// Handle lines ending with both '\r' and '\n' in either order.
	int c = next(p);
	if (('\n' == c) && ('\r' == peek(p))) {
		skip(p, 1);
	} else if (('\r' == c) && ('\n' == peek(p))) {
		skip(p, 1);
	}
	p->lineNumber++;
}

// ***** Skipping Whitespace and Comments *****

static void skipRestOfLine(parser *p) {
	// Skip the remainder of the line, but do not consume the line ending.
	int c;
	while ((c = peek(p)) != EOF) {
		if (isNewLine(c)) return;
		skip(p, 1);
	}
}

static void skipWhiteSpace(parser *p) {
	int c;
	while ((c = next(p)) != EOF) {
		if (('/' == c) && ('/' == peek(p))) { skipRestOfLine(p); skipNewLine(p); }
		else if (isNewLine(c)) { skip(p, -1); skipNewLine(p); }
		else if (c > ' ') { skip(p, -1); return; }
	}
}

static void skipSpacesAndTabs(parser *p) {
	int c;
	while ((c = next(p)) != EOF) {
		if (('/' == c) && ('/' == peek(p))) { skipRestOfLine(p); return; }
		if ((' ' != c) && ('\t' != c)) { skip(p, -1); return; }
	}
}

// ***** Error Reporting *****

static void parseError(parser *p, char *problem) {
	printf("%s:%d %s\n", p->fileName, p->lineNumber, problem);
}

// ***** String Allocation *****

static OBJ newOrSharedString(char *s) {
	OBJ strObj = newString(s);
	if (strlen(s) > 30) return(strObj);
	OBJ result = dictAt(sharedStrings, strObj);
	if (!result) {
		dictAtPut(sharedStrings, strObj, strObj);
		result = strObj;
	}
	return result;
}

// ***** Parsing *****

static OBJ readValue(parser *p); // forward reference

static OBJ readString(parser *p) {
	OBJ bufObj = newBinaryObj(StringClass, 5);
	char *buf = obj2str(bufObj);
	uint32 limit = (4 * objWords(bufObj)) - 1;
	uint32 i = 0;
	skip(p, 1); // skip initial quote character
	p->inString = true;
	while (true) {
		int c = next(p);
		if (EOF == c) { p->complete = false; break; }
		if ('\'' == c) {
			if ('\'' == peek(p)) {
				skip(p, 1); // quoted quote character
			} else {
				p->inString = false;
				break;
			}
		}
		if (i >= limit) {
			bufObj = copyObj(bufObj, 4 * objWords(bufObj), 1);
			buf = obj2str(bufObj);
			limit = (4 * objWords(bufObj)) - 1;
		}
		buf[i++] = c;
		if (isNewLine(c)) {
			p->lineNumber++;
			// For lines ending in both cr and lf, consume both chars to avoid incrementing the line number twice.
			if ((c == '\n') && (peek(p) == '\r')) buf[i++] = next(p);
			if ((c == '\r') && (peek(p) == '\n')) buf[i++] = next(p);
		}
	}
	OBJ result = newBinaryObj(QuotedStringClass, (i / 4) + 1);
	memcpy(BODY(result), buf, i);
	return result;
}

static OBJ readSymbol(parser *p) {
	char buf[1001];
	int i = 0;
	while (i < 1000) {
		int c = peek(p);
		if (c <= ' ') break;
		else if ((')' == c) || ('}' == c) || (';' == c) || (EOF == c)) break;
		else buf[i++] = next(p);
	}
	buf[i] = 0;
	if (strcmp("true", buf) == 0) return trueObj;
	if (strcmp("false", buf) == 0) return falseObj;
	if (strcmp("nil", buf) == 0) return nilObj;
	if (strcmp("else", buf) == 0) return trueObj; // for use in "if"
	return newOrSharedString(buf);
}

static inline int isDigit(int c) { return ('0' <= c) && (c <= '9'); }

static OBJ readNum(parser *p) {
	char buf[1001];
	int isFloat = false;
	int i = 0;
	while (i < 1000) {
		int c = peek(p);
		if (isDigit(c) || ('-' == c)) {
			buf[i++] = next(p);
		} else if ('.' == c) {
			buf[i++] = next(p);
			isFloat = true;
		} else if (('e' == c) || ('E' == c)) {
			buf[i++] = next(p);
			c = peek(p);
			if (('+' == c) || ('-' == c)) buf[i++] = next(p);
			isFloat = true;
		} else {
			break;
		}
	}
	buf[i++] = '\0'; // null terminator

	if (isFloat) {
		double f = 0.0;
		if (sscanf(buf, "%lf", &f) != 1) parseError(p, "Bad float");
		return newFloat(f);
	} else {
		int n = 0;
		if (sscanf(buf, "%d", &n) != 1) parseError(p, "Bad integer");
		if ((n < -1073741824) || (n > 1073741823)) {
			parseError(p, "Integer out of range");
			return nilObj;
		}
		return int2obj(n);
	}
}

static int isIn(OBJ s, char *stringList[], int listSizeInBytes) {
	// Return true if s is a String and included in the given list of strings.
	int count = listSizeInBytes / sizeof(char*);
	if (objClass(s) == StringClass) {
		for (int i = 0; i < count; i++) {
			if (strcmp(stringList[i], obj2str(s)) == 0) return true;
		}
	}
	return false;
}

static int isInfixOp(OBJ op) {
	char *infixOps[] = {
		"=", "+=",
		"+", "-", "*", "/", "%",
		"<", "<=", "==", "!=", ">=", ">", "===",
		"&", "|", "^", "<<", ">>", ">>>",
	};
	return isIn(op, infixOps, sizeof infixOps);
}

static int isCallOp(OBJ op) {
	char *callOps[] = {"call", "callWith"};
	return isIn(op, callOps, sizeof callOps);
}

static int isProperName(OBJ op, int index, int argCount) {
	// Return true if the given operation uses the argument at the given index as a proper name such as
	// a variable or function name. Proper names are treated as literal strings, not variable references.
	char *quoteAll[] = { "to", "defineClass", "method" };
	char *quoteFirstArg[] = { "v", "=", "+=", "local", "for", "help", "classComment" };
	if (isIn(op, quoteAll, sizeof quoteAll)) return true;
	if (IS_CLASS(op, StringClass) && strEQ("function", op) && (index < argCount)) return true;
	return (index == 1) && isIn(op, quoteFirstArg, sizeof quoteFirstArg);
}

static OBJ argOrVarRef(parser *p, OBJ arg, OBJ op, int index, int argCount, int lineNum) {
	// If arg is a String and the arg at the given index is not used as a proper name
	// by the given operator, create a variable reference. Otherwise, just return arg.
	// Always convert UnquotedStrings to normal Strings.
	if (IS_CLASS(arg, StringClass)) {
		if (!isProperName(op, index, argCount) && !isInfixOp(arg)) {
			OBJ rObj = newObj(ReporterClass, CmdFieldCount + 1, nilObj);
			CmdPtr r = (CmdPtr)O2A(rObj);
			r->primName = p->cachedGetVarPrim;
			r->args[0] = arg;
			r->lineno = int2obj(lineNum);
			r->fileName = p->cachedFileName;
			return rObj;
		}
	}
	if (IS_CLASS(arg, QuotedStringClass)) SETCLASS(arg, StringClass);
	return arg;
}

static OBJ readCmd(parser *p, gp_boolean isReporter) {
	// Read a command or reporter. Terminate at close paren, close bracket, end of line, or end of file.
	OBJ buf = newArray(10);
	int count = 0;
	int lineNum = p->lineNumber;
	int c = 0;
	if (isReporter && ('(' == peek(p))) skip(p, 1);
	while (true) {
		if (isReporter) skipWhiteSpace(p); else skipSpacesAndTabs(p); // reporters can span lines
		c = peek(p);
		if ((EOF == c) || (isNewLine(c))) break;
		if ((')' == c) || (';' == c) || ('}' == c)) break;
		if (count >= objWords(buf)) { // grow buffer, if necessary
			buf = copyObj(buf, 4 * objWords(buf), 1);
		}
		FIELD(buf, count++) = readValue(p);
	}
	if (isReporter) {
		if (')' == c) {
			skip(p, 1);
		} else {
			p->complete = false;
			if ((';' == c) || ('}' == c)) {
				parseError(p, "Missing ')'");
				skipRestOfLine(p);
			}
			return nilObj;
		}
	} else {
		if (')' == c) {
			parseError(p, "Unexpected ')' encountered");
			skip(p, 1);
		}
	}
	if (count == 0) {
		parseError(p, "Empty command or reporter");
		return nilObj;
	}
	if ((count == 3) && isInfixOp(FIELD(buf, 1)) && !isCallOp(FIELD(buf, 0))) {
		// Convert infix to prefix order (unless command is 'call' or 'callWith')
		OBJ tmp = FIELD(buf, 0);
		FIELD(buf, 0) = FIELD(buf, 1);
		FIELD(buf, 1) = tmp;
	}
	int argCount = count - 1;
	if ((argCount == 0) && (NOT_CLASS(FIELD(buf, 0), StringClass)) && (NOT_CLASS(FIELD(buf, 0), QuotedStringClass))) {
		OBJ literal = FIELD(buf, 0);
		if (IS_CLASS(literal, QuotedStringClass)) SETCLASS(literal, StringClass);
		return literal; // literal value
	}
	if (IS_CLASS(FIELD(buf, 0), QuotedStringClass)) SETCLASS(FIELD(buf, 0), StringClass);
	if (NOT_CLASS(FIELD(buf, 0), StringClass)) {
		parseError(p, "Operator must be a string; missing parentheses around a subexpression?");
		return nilObj;
	}
	OBJ cmdObj = newObj(isReporter ? ReporterClass : CmdClass, CmdFieldCount + argCount, nilObj);
	CmdPtr cmd = (CmdPtr)O2A(cmdObj);
	cmd->primName = FIELD(buf, 0);
	cmd->prim = 0;
	cmd->lineno = int2obj(lineNum);
	cmd->fileName = p->cachedFileName;
	for (int i = 1; i < count; i++) {
		OBJ arg = FIELD(buf, i);
		cmd->args[i - 1] = argOrVarRef(p, arg, cmd->primName, i, argCount, lineNum);
	}
	return cmdObj;
}

static OBJ readCmdList(parser *p) {
	// Read a list of commands.
	gp_boolean hadOpenBracket = false;
	OBJ firstCmd = nilObj;
	OBJ lastCmd = nilObj;
	int c;
	if ('{' == peek(p)) { skip(p, 1); hadOpenBracket = true; }
	while (true) {
		skipWhiteSpace(p);
		c = peek(p);
		if ((EOF == c) || ('}' == c)) break;
		OBJ cmd = readCmd(p, false);
		if (IS_CLASS(cmd, ReporterClass)) SETCLASS(cmd, CmdClass); // if reporter, convert to command
		if (IS_CLASS(cmd, CmdClass)) {
			if (!firstCmd) firstCmd = cmd;
			if (lastCmd) ((CmdPtr)O2A(lastCmd))->nextBlock = cmd;
			lastCmd = cmd;
		} else {
			if (!hadOpenBracket && !firstCmd) return cmd; // return literal value when called from prompt
		}
		if (';' == peek(p)) { skip(p, 1); continue; }
		if (!hadOpenBracket) break;
	}
	if (hadOpenBracket) {
		if ('}' == c) skip(p, 1); else p->complete = false;
	} else {
		if ('}' == c) {
			parseError(p, "Unexpected '}' encountered");
			skip(p, 1);
		}
	}
	return firstCmd;
}

static OBJ readValue(parser *p) {
	int c = peek(p);
	if (EOF == c) {
		p->complete = false;
		return nilObj;
	}
	if (isDigit(c)) return readNum(p);
	else if ((('-' == c) || ('.' == c)) && isDigit(peek2(p))) return readNum(p);
	else if ('\'' == c) return readString(p);
	else if ('(' == c) return readCmd(p, true);
	else if ('{' == c) return readCmdList(p);
	else return readSymbol(p);
}

// ***** File Read Utility *****

static int readFileIntoBuffer(char *fileName, char *buffer, int bufSize) {
	// Read the entire file with the given name into buffer and return the number of bytes read.
	// Return -1 if the file doesn't exist or is too large to fit in the buffer.

	FILE *f = fopen(fileName, "rb"); // 'b' needed to avoid premature EOF on Windows
	if (!f) {
		printf("File not found: %s\n", fileName);
		return -1;
	}
	fseek(f, 0L, SEEK_END);
	long n = ftell(f); // get file size
	fseek(f, 0L, SEEK_SET);
	if (n > bufSize) {
		printf("File too large for buffer: %s (%ld bytes)\n", fileName, n);
		fclose(f);
		return -1;
	}

	int byteCount = fread(buffer, sizeof(char), n, f);
	if (byteCount < n) {
		if (ferror(f)) {
			printf("File read error: %s\n", fileName);
			fclose(f);
			return -1;
		}
	}
	fclose(f);
	return byteCount;
}

// ***** Entry Points *****

gp_boolean parse_atEnd(parser *p) {
	return p->bufPos >= p->bufSize;
}

int parse_firstChar(parser *p) {
	// Return the first non-whitespace character in the string to be parsed.

	skipWhiteSpace(p);
	return peek(p);
}

OBJ parse_nextScript(parser *p, int fromPrompt) {
	// Return the next reporter, command, or command list in the string being parsed.

	// re-initialize these in case GC has run since the last call
	p->cachedFileName = newOrSharedString(p->fileName);
	p->cachedGetVarPrim = newOrSharedString("v"); // cache name of variable reporter primitive (heavily used)

	p->complete = true;
	p->inString = false;

	skipWhiteSpace(p);
	if (p->bufPos >= p->bufSize) return nilObj;

	OBJ prog = readCmdList(p);

	if (p->inString && !fromPrompt) {
		parseError(p, "Missing closing string quote?");
	}
	return p->complete ? prog : nilObj;
}

#define FILE_BUF_SIZE 1000000
static char fileBuffer[FILE_BUF_SIZE];

void parse_runFile(char *fName) {
	int byteCount = readFileIntoBuffer(fName, fileBuffer, FILE_BUF_SIZE);
	if (byteCount > 0) parse_runScriptsInBuffer(fName, fileBuffer, byteCount);
}

void parse_runScriptsInBuffer(char *fName, char *buffer, int bufSize) {
	if (bufSize <= 0) return;
	parser p;
	parse_setSourceString(&p, fName, buffer, bufSize);
	while (true) {
		OBJ prog = parse_nextScript(&p, false);
		if (IS_CLASS(prog, CmdClass) || IS_CLASS(prog, ReporterClass)) {
			currentModule = consoleModule;
			run(prog);
		}
		if (parse_atEnd(&p)) {
			if (!p.complete) printf("Premature end of file; missing '}'? %s\n", fName);
			break;
		}
	}
}

OBJ parse_scriptFromPrompt(parser *p, char *script, int byteCount) {
	// Attempt to parse a command or expression from the GP prompt.
	// Return PARSE_INCOMPLETE if it is not yet complete.

	parse_setSourceString(p, "<prompt>", script, byteCount);
	skipWhiteSpace(p);
	if (p->bufPos >= p->bufSize) return PARSE_INCOMPLETE;
	OBJ prog = parse_nextScript(p, true);
	if (p->complete && ('\'' == script[0]) && IS_CLASS(prog, CmdClass) && (6 == objWords(prog))) {
		// special case: string literal typed at prompt
		prog = FIELD(prog, 0);
	}
	return p->complete ? prog : PARSE_INCOMPLETE;
}

void parse_setSourceString(parser *p, char *fileName, char *s, int byteCount) {
	// Start parsing the given string. Scripts are enumerated by calling parse_nextScript().

	p->buf = (unsigned char *) s;
	p->bufSize = byteCount;
	p->bufPos = 0;
	p->fileName = fileName;
	p->lineNumber = 1;
	p->cachedFileName = newOrSharedString(fileName);
	p->cachedGetVarPrim = newOrSharedString("v"); // cache name of variable reporter primitive (heavily used)
}
