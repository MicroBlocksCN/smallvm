#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mem.h"
#include "embeddedFS.h"
#include "interp.h"
#include "oop.h"
#include "parse.h"

#ifdef EMSCRIPTEN
  #include <emscripten.h>
#elif defined(IOS)
  #include "SDL.h"
  #include "iosOps.h"
#elif defined(_WIN32)
  #include <windows.h>
#endif

/* Variables */

char argv0[1024]; // copy of argv[0]

// ***** Read-Eval Loop *****

#define LINE_SIZE 500
#define BUF_SIZE 10000

static int emptyLine(char *buf, int bufCount) {
	if (bufCount < 2) return false;
	return (buf[bufCount - 2] == '\n') && (buf[bufCount - 1] == '\n');
}

static void readEvalLoop() {
	char line[LINE_SIZE];
	char buf[BUF_SIZE];
	int bufCount = 0;
	parser p;
	OBJ prog;

	while(1) {
		int emptyLineCount = 0;
		buf[0] = 0;
		bufCount = 0;

		if (consoleModule == sessionModule) {
			printf("gp");
		} else {
			// when not in the session module, use module name as prompt
			OBJ modName = FIELD(consoleModule, Module_ModuleName);
			if (IS_CLASS(modName, StringClass) && (strlen(obj2str(modName)) > 0)) {
				printf("%s", obj2str(modName));
			} else {
				printf("unnamed module");
			}
		}
		while ((prog = parse_scriptFromPrompt(&p, buf, bufCount)) == PARSE_INCOMPLETE) {
			printf("> ");
			fflush(stdout);
			while (!fgets(line, LINE_SIZE, stdin)) {
				// if interrupted by a signal (e.g. from profiling timer), try again; otherwise, return
				// (Note: On Windows, control-C makes fgets fail with errno == 0; just try again)
				if (errno && (errno != EINTR)) return;
			}
			strncat(buf, line, BUF_SIZE - bufCount - 1);
			bufCount += strlen(line);
			buf[bufCount] = 0;

			// User can exit multiline input by typing a bunch of blank lines. However, since
			// pasted code may include some blank lines so don't exit after just one or two.
			if (emptyLine(buf, bufCount)) {
				if (++emptyLineCount >= 3) {
					printf("Abandoning multiline input.\n");
					break;
				}
			} else {
				emptyLineCount = 0;
			}
		}
		if (prog == PARSE_INCOMPLETE) continue;

		if (IS_CLASS(prog, CmdClass) || IS_CLASS(prog, ReporterClass)) {
			if (IS_CLASS(prog, CmdClass) &&
				(strEQ("=", ((CmdPtr)O2A(prog))->primName) ||
				 strEQ("+=", ((CmdPtr)O2A(prog))->primName) ||
			 	 strEQ("for", ((CmdPtr)O2A(prog))->primName) )) {
					OBJ varName = ((CmdPtr)O2A(prog))->args[0];
					addModuleVariable(consoleModule, varName, nilObj);
			}
			if (!((CmdPtr)O2A(prog))->nextBlock) SETCLASS(prog, ReporterClass); // return expression value even if user omits parenthesis
			currentModule = consoleModule;
			OBJ result = run(prog);
			if (succeeded()) printlnObj(result);
		} else {
			printlnObj(prog);
		}
	}
}

#ifdef EMSCRIPTEN

// ***** Browser Support *****

static void browserStep() {
	if (currentTask) { // if there is a task, run it for a bit
		stepCurrentTask();
		return;
	}
	printf("GP has crashed. Sadly, newer browsers no longer support the interactive debugger.");
	return; // old code follows

	// collect a command
	char buf[BUF_SIZE];
	int bufCount = 0;
	parser p;
	OBJ prog;

	buf[0] = 0;
	bufCount = 0;
	while ((prog = parse_scriptFromPrompt(&p, buf, bufCount)) == PARSE_INCOMPLETE) {
		char line[LINE_SIZE];
		fgets(line, LINE_SIZE, stdin);
		strncat(buf, line, BUF_SIZE - bufCount);
		bufCount += strlen(line);
		buf[bufCount] = 0;

		// User can exit multiline input by entering a blank line.
		if (emptyLine(buf, bufCount)) {
			printf("Abandoning multiline input.\n");
			buf[0] = 0;
			bufCount = 0;
			continue;
		}
	}

	// start a task to evaluate the command
	if (IS_CLASS(prog, CmdClass) || IS_CLASS(prog, ReporterClass)) {
		if (IS_CLASS(prog, CmdClass) &&
			(strEQ("=", ((CmdPtr)O2A(prog))->primName) ||
			 strEQ("+=", ((CmdPtr)O2A(prog))->primName) ||
			 strEQ("for", ((CmdPtr)O2A(prog))->primName) )) {
				OBJ varName = ((CmdPtr)O2A(prog))->args[0];
				addModuleVariable(sessionModule, varName, nilObj);
		}
		if (!((CmdPtr)O2A(prog))->nextBlock) SETCLASS(prog, ReporterClass); // return expression value even if user omits parenthesis
		currentModule = consoleModule;
		initCurrentTask(prog);
	} else { // print a literal value
		printlnObj(prog);
	}
}

void sortFileList(OBJ fileList) {
	// Sort file list (an array of String object) using bubble sort.

	int n = objWords(fileList);
	for (int j = 0; j < n - 1; j++) {
		for (int i = j + 1; i < n; i++) {
			if (strcmp(obj2str(FIELD(fileList, j)), obj2str(FIELD(fileList, i))) > 0) {
				OBJ tmp = FIELD(fileList, j);
				FIELD(fileList, j) = FIELD(fileList, i);
				FIELD(fileList, i) = tmp;
			}
		}
	}
}

static void loadLibInBrowser() {
	OBJ directoryContents(char *dirName, int listDirectories); // declaration
	OBJ fileList = directoryContents("runtime/lib/", false);

	sortFileList(fileList);
	int fileCount = objWords(fileList);
	int loadedCount = 0;
	for (int i = 0; i < fileCount; i++) {
		char *fileName = obj2str(FIELD(fileList, i));
		char *ext = strstr(fileName, ".gp");
		if (ext && (strlen(ext) == 3)) { // fileNames ends with ".gp"
			char fullFileName[200];
			snprintf(fullFileName, 200, "runtime/lib/%s", fileName);
			parse_runFile(fullFileName);
			loadedCount++;
		}
	}
	printf("Loaded %d library files from embedded file system\n", loadedCount);
	parse_runFile("runtime/startup.gp");
}

#else

// ***** Loading from File System *****

static gp_boolean isGPFile(char *s) {
	int count = strlen(s);
	if (count < 4) return false;
	return (strcmp(s + (count - 3), ".gp") == 0);
}

static void readLibraryFromFileSystem(gp_boolean runStartup) {
	char fName[300];
	int loadedCount = 0;
#ifdef _WIN32
	char entry[200]; // directory entry name
	WIN32_FIND_DATAW info;
	HANDLE hFind = FindFirstFileW(L"runtime\\lib\\*.gp", &info);
	if (INVALID_HANDLE_VALUE != hFind) {
		do {
			if ((info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
				entry[0] = 0; // null terminate in case conversion fails
				WideCharToMultiByte(CP_UTF8, 0, info.cFileName, -1, entry, sizeof(entry), NULL, NULL);
				if (isGPFile(entry)) {
					snprintf(fName, 200, "runtime/lib/%s", entry);
					parse_runFile(fName);
 					loadedCount++;
 				}
			}
		} while (FindNextFileW(hFind, &info) != 0);
	}
	FindClose(hFind);
#else
	DIR *dir = opendir("runtime/lib");
	if (dir) {
		struct dirent *entry;
		while ((entry = readdir(dir))) {
			if ((DT_REG == entry->d_type) && isGPFile(entry->d_name)) {
				snprintf(fName, 300, "runtime/lib/%s", entry->d_name);
 				parse_runFile(fName);
 				loadedCount++;
			}
		}
		closedir(dir);
	}
#endif
	printf("Loaded %d library files from runtime/lib\n", loadedCount);
	if (runStartup) parse_runFile("runtime/startup.gp");
}

#endif // EMSCRIPTEN

// ***** Startup Function *****

static int hasStartupFunction() {
	OBJ primGlobalFuncs(int nargs, OBJ args[]); // declaration
	OBJ functions = primGlobalFuncs(0, NULL);
	for (int i = 0; i < objWords(functions); i++) {
		OBJ fnc = FIELD(functions, i);
		if (fnc) {
			OBJ fName = FIELD(fnc, 0);
			if (IS_CLASS(fName, StringClass) && (strcmp("startup", obj2str(fName)) == 0)) {
				return true;
			}
		}
	}
	return false;
}

// ***** Command Line *****

static gp_boolean processCommandLine(int argc, char *argv[], char *prefix) {
	recordCommandLine(argc, argv);
	if (argc >= 2) {
		char *s = argv[1];
		if ((strcmp("-help", s) == 0) || (strcmp("-h", s) == 0)) {
			printf("GP is a general purpose blocks language for casual programmers\n\n");
			printf("  gp			Run runtime/startup.gp after loading libraries from runtime/lib\n");
			printf("  gp -			Run interactively after loading libraries from runtime/lib\n");
			printf("  gp file1 file2 ...	Run the given GP files in batch mode. Library files must be supplied on the command line.\n\n");
			printf("A hyphen (-) enters interactive mode.\n");
			printf("Arguments after a hyphen (-) or double hyphen (--) are not run as GP files\n");
			printf("  but can be processed by GP code using the commandLine primitive.\n");
			exit(0);
		}
	}

	int interactiveFlag = (argc == 2) && (strcmp(argv[1], "-") == 0);
#ifdef _WIN32
	if (!interactiveFlag) ShowWindow(GetConsoleWindow(), SW_MINIMIZE);
#endif

	if ((argc == 1) || interactiveFlag) {
		// read library if no arguments or just "-"
		#if !defined(EMSCRIPTEN)
			gp_boolean hasEmbeddedLibrary = importLibrary();
			if (!hasEmbeddedLibrary) readLibraryFromFileSystem(true);
		#endif
	}
	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--") == 0) {
			break;
		} else if (strcmp(argv[i], "-") == 0) {
			interactiveFlag = true;
			break;
		} else if (strcmp(argv[i], "-e") == 0) { // use embedded file system
			importLibrary();
		} else if (prefix) {
			// in Emscripten, running under Node, a prefix is needed to access external files
			char externalName[1000];
			snprintf(externalName, 1000, "%s/%s", prefix, argv[i]);
			parse_runFile(externalName);
		} else {
			parse_runFile(argv[i]);
		}
	}
	return interactiveFlag;
}

// ***** Memory Size *****

#if defined(EMSCRIPTEN)
	// iPad mini2 (1 GB memory) works with 80MB, not with 100MB
	// Nexus7 and iPad Pro work with 200MB
	// Decreased memory to 100MB for iOS 10 Safari and Chrome
	#define MEM_SIZE 100
#else
	#define MEM_SIZE 200  // tested with 45; fedora project uses 80MB when ship selected
#endif

// ***** Main *****

int main(int argc, char *argv[]) {
	// Save argv[0]
	strncpy(argv0, argv[0], sizeof(argv0));
	argv0[sizeof(argv0) - 1] = 0; // ensure null termination

	int interactiveFlag = false;
	memInit(MEM_SIZE); // megabytes
	initGP();
	readingLibrary = true;

#if defined(EMSCRIPTEN)
	int isInBrowser = EM_ASM_INT({
		if (ENVIRONMENT_IS_NODE) {
			// when running in Node, mount the external file system as /external
			FS.mkdir('/external');
			FS.mount(NODEFS, { root: '.' }, '/external');
		}
		return !ENVIRONMENT_IS_NODE;
	}, NULL);

	// Load the GP library from the embedded file system if either:
	//	(a) running in the browser, or
	//	(b) running in Node with no command line arguments
	// This allows you load new versions of the library from the file
	// system without recompiling when running in Node, but also allows you
	// to test loading the library from the embedded file system in Node.

	if (isInBrowser || (argc == 1)) {
		loadLibInBrowser();
	} else {
		interactiveFlag = processCommandLine(argc, argv, "/external");
	}
#elif defined(IOS)
	(void) processCommandLine; // reference (not a call) to suppress uncalled function warning
	ios_loadLibrary();
	ios_loadUserFilesAndMainFile();
#else
	interactiveFlag = processCommandLine(argc, argv, NULL);
#endif

	readingLibrary = false;
	collectGarbage(false);

	if (sessionModule == topLevelModule) {
		// An experimental test to see if loading any of library files had not
		// changed sessionModule, which was set in initVMClasses();
		sessionModule = currentModule = consoleModule = newModule("SessionModule");
	}

#ifdef EMSCRIPTEN
	if (isInBrowser) {
		// create a task to run the startup function, if there is one
		if (hasStartupFunction()) {
			parser p;
			char *cmd = "startup";
			OBJ cmdObj = parse_scriptFromPrompt(&p, cmd, strlen(cmd));
			initCurrentTask(cmdObj);
		}
		printf("Welcome to GP!\n");
		emscripten_set_main_loop(browserStep, 0, true); // callback, fps, loopFlag
		return 0; // should not get here
	}
#endif  // EMSCRIPTEN

	if (hasStartupFunction()) {
		parser p;
		char *cmd = "startup";
		OBJ prog = parse_scriptFromPrompt(&p, cmd, strlen(cmd));
		run(prog);
	}
	if (interactiveFlag) {
		printf("Welcome to GP!\n");
		readEvalLoop();
		printf("Goodbye!\n");
	}
	return 0;
}
