// interp.c - Simple interpreter for the GP language
// John Maloney, September 2013

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include "mem.h"
#include "cache.h"
#include "dict.h"
#include "interp.h"
#include "oop.h"

// Primitive Dictionary

OBJ primitiveDictionary = nilObj;

// Interpreter State

OBJ vmRoots;
OBJ emptyArray;
OBJ sharedStrings;
OBJ classes;
OBJ eventKeys;
OBJ currentTask = nilObj;
OBJ debugeeTask = nilObj; // discarded by GC

OBJ currentModule = nilObj;
OBJ sessionModule = nilObj;
OBJ topLevelModule = nilObj;
OBJ consoleModule = nilObj;

struct timeval startTime;
int profileTick = 0;

static gp_boolean stopFlag;
static gp_boolean errorFlag;
static gp_boolean gcPrimitiveCalled = false;
static int ticks = 0;
static int tickLimit = 0;

// Task Fields

#define Task_Stack 0
#define Task_SP 1
#define Task_FP 2
#define Task_MP 3
#define Task_CurrentBlock 4
#define Task_NextBlock 5
#define Task_Result 6
#define Task_TickLimit 7
#define Task_TaskToResume 8
#define Task_WaitReason 9
#define Task_WakeMSecs 10
#define Task_ProfileArray 11
#define Task_ProfileIndex 12
#define Task_ErrorReason 13

// Stack Headroom

#define StackExtra 50

// Heavily used primitives inlined into the dispatch loop

OBJ primAdd(int nargs, OBJ args[]);
OBJ primSub(int nargs, OBJ args[]);
OBJ primLess(int nargs, OBJ args[]);

// Intitialization

static void interruptHandler(int sig) {
	// Stop GP program when Ctrl-C pressed.
	if (SIGINT == sig) {
		if (IS_CLASS(currentTask, TaskClass)) {
			// clear Task_TaskToResume to suppress the GP debugger
			FIELD(currentTask, Task_TaskToResume) = nilObj;
		}
		printf("\n");
		failure("User interrupt. (Type \"exit\" to quit GP.)"); // stop the GP program, but don't exit
	}
}

#ifdef _WIN32
#include <windows.h>
static BOOL WINAPI winInterruptHandler(DWORD type) {
	if (CTRL_C_EVENT == type) {
		interruptHandler(SIGINT);
		return TRUE;
	}
	return FALSE;
}
#endif

void initGP() {
	gettimeofday(&startTime, NULL);
	srand(startTime.tv_usec);

	vmRoots = newArray(30); // vmRoots must be first object, so it doesn't move when memory is compacted

	emptyArray = newObj(ArrayClass, 0, nilObj); // shared canonical empty array
	sharedStrings = newDict(10000);
	initVMClasses();
	eventKeys = newArray(0);
	loadPrimitivePlugins();
	initPrimitiveTable();
	methodCacheClear();

#if defined(_WIN32)
	SetConsoleCtrlHandler((PHANDLER_ROUTINE) winInterruptHandler, TRUE);
	timeBeginPeriod(1); // use finer-grained scheduler resolution
#elif defined(EMSCRIPTEN)
	// do nothing; control-C interrupts are not supported
	(void) interruptHandler; // reference to suppress compiler warning
#else
	signal(SIGINT, interruptHandler);
#endif
}

// GC Support

void saveVMRoots() {
	// Save object references cached as C variables into the vmRoots array.
	// 0-9 reserved for interpreter state
	FIELD(vmRoots, 10) = emptyArray;
	FIELD(vmRoots, 11) = sharedStrings;
	FIELD(vmRoots, 12) = classes;
	FIELD(vmRoots, 13) = eventKeys;
	FIELD(vmRoots, 14) = topLevelModule;
	FIELD(vmRoots, 15) = sessionModule;
	FIELD(vmRoots, 16) = currentModule;
	FIELD(vmRoots, 17) = consoleModule;
	FIELD(vmRoots, 18) = currentTask;
	FIELD(vmRoots, 19) = methodCache;
	FIELD(vmRoots, 20) = primitiveDictionary;
}

void restoreVMRoots() {
	// Restore object references cached as C variables from the vmRoots array.
	// 0-9 reserved for interpreter state
	emptyArray = FIELD(vmRoots, 10);
	sharedStrings = FIELD(vmRoots, 11);
	classes = FIELD(vmRoots, 12);
	eventKeys = FIELD(vmRoots, 13);
	topLevelModule = FIELD(vmRoots, 14);
	sessionModule = FIELD(vmRoots, 15);
	currentModule = FIELD(vmRoots, 16);
	consoleModule = FIELD(vmRoots, 17);
	currentTask = FIELD(vmRoots, 18);
	methodCache = FIELD(vmRoots, 19);
	primitiveDictionary = FIELD(vmRoots, 20);
}

// Helper Functions

static inline gp_boolean isReporter(OBJ obj) {
	return (IS_CLASS(obj, ReporterClass));
}

static inline int argCount(ADDR a) {
	return (a[1] - CmdFieldCount);
}

static inline OBJ stackptr2offset(ADDR sp) {
	return int2obj(sp ? ((sp - BODY(FIELD(currentTask, Task_Stack))) + 1) : 0);
}

static inline ADDR offset2stackptr(OBJ offset) {
	return (offset == 1) ? 0 : BODY(FIELD(currentTask, Task_Stack)) + obj2int(offset) - 1;
}

void yield() { stopFlag = true; }
int succeeded() { return !errorFlag; }

void stop() {
	stopFlag = true;
	errorFlag = true;
}

void failure(char *reason) {
	stop();
	printf("%s\n", reason);
	if (currentTask) FIELD(currentTask, Task_ErrorReason) = newString(reason);
}

OBJ lastReceiver(int mpIndex) {
	// Return the receiver of the most recent method call (skipping any intervening
	// function calls) on the current stack or nil if there are no method calls.

	ADDR base = BODY(FIELD(currentTask, Task_Stack)) - 1;
	while (mpIndex) {
		OBJ functionOrMethod = base[mpIndex + 1];
		int classID = obj2int(FIELD(functionOrMethod, 1));
		if (classID && (base[mpIndex] > 0)) { // this is a method with > 0 args
			int argsIndex = obj2int(base[mpIndex - 1]);
			return base[argsIndex]; // return the first argument (i.e. the receiver)
		}
		mpIndex = obj2int(base[mpIndex + 2]);
	}
	return nilObj;
}

static inline OBJ moduleOfFunction(OBJ func) {
	OBJ result = (func ? FIELD(func, 5) : nilObj);
	if (!result) result = topLevelModule;
	return result;
}

// Variable Reference Type Bits

#define ARG_REF 1024
#define LOCAL_REF 2048
#define FIELD_REF 4096
#define MODULE_REF 8192
#define BAD_REF 16384
#define UNBOUND_REF (16384 | 1)

// Variable Operations

static OBJ variableBinding(OBJ varName, ADDR mp) {
	// Return a variable binding for the given variable in the current method.
	// A binding is an integer object where a high bit indicates the reference
	// type and value & 0x3FF is the index.
	int i;

	if (NOT_CLASS(varName, StringClass)) return int2obj(BAD_REF);

	if (mp) { // inside a method call
		OBJ method = *(mp + 1);

		i = indexOfString(varName, FIELD(method, 2)); // argNames
		if (i > -1) return int2obj(ARG_REF | i);

		i = indexOfString(varName, FIELD(method, 3)); // localNames
		if (i > -1) return int2obj(LOCAL_REF | i);

		OBJ classObj = classFromIndex(obj2int(FIELD(method, 1)));
		if (classObj) {
			OBJ fieldNames = FIELD(classObj, 2);
			i = indexOfString(varName, fieldNames);
			if (i > -1) return int2obj(FIELD_REF | i);
		}
		return int2obj(UNBOUND_REF);
	} else {
		OBJ module = currentModule;
		OBJ moduleVarNames = FIELD(module, Module_VariableNames);
		i = indexOfString(varName, moduleVarNames);
		if (i >= 0) return int2obj(MODULE_REF | i);
		return int2obj(UNBOUND_REF);
	}
}

static void reportBadVarRef(OBJ varName, int varBinding) {
	if (UNBOUND_REF == varBinding) {
		char reason[200];
		sprintf(reason, "Unknown variable: %s", obj2str(varName));
		failure(reason);
	} else {
		failure("The variable name must be a string.");
	}
}

static inline OBJ getVar(OBJ varName, int varBinding, ADDR mp) {
	int i = varBinding & 0x3FF;

	if (BAD_REF & varBinding) {
		reportBadVarRef(varName, varBinding);
		return nilObj;
	}

	if (MODULE_REF & varBinding) {
		OBJ module = mp ? moduleOfFunction(*(mp + 1)) : currentModule;
		OBJ moduleVarNames = FIELD(module, Module_VariableNames);
		i = indexOfString(varName, moduleVarNames);
		if (i < 0) return nilObj;
		OBJ moduleVars = FIELD(module, Module_Variables);
		return FIELD(moduleVars, i);
	}

	int nargs = obj2int(*mp);
	ADDR base = offset2stackptr(*(mp - 1));

	if (LOCAL_REF & varBinding) {
		return *(mp - i - 2);
	} else if (ARG_REF & varBinding) {
		if (i < nargs) return *(base + i);
		else {
			OBJ method = *(mp + 1);
			int paramCount = WORDS(FIELD(method, 2));
			return (i < paramCount) ? *(base + i) : nilObj;
		}
	} else if (FIELD_REF & varBinding) {
		if (nargs < 1) return nilObj; // no receiver
		OBJ receiver = *base; // first arg is the receiver
		return FIELD(receiver, i);
	}
	return nilObj;
}

static inline void setVar(OBJ varName, int varBinding, ADDR mp, OBJ newValue) {
	int i = varBinding & 0x3FF;

	if (BAD_REF & varBinding) {
		reportBadVarRef(varName, varBinding);
		return;
	}

	if (MODULE_REF & varBinding) {
		OBJ module = mp ? moduleOfFunction(*(mp + 1)) : currentModule;
		OBJ moduleVarNames = FIELD(module, Module_VariableNames);
		i = indexOfString(varName, moduleVarNames);
		if (i < 0) return;
		OBJ moduleVars = FIELD(module, Module_Variables);
		FIELD(moduleVars, i) = newValue;
		return;
	}
	int nargs = obj2int(*mp);
	ADDR base = offset2stackptr(*(mp - 1));

	if (LOCAL_REF & varBinding) {
		*(mp - i - 2) = newValue;
	} else if (ARG_REF & varBinding) {
		if (i < nargs) *(base + i) = newValue;
		else {
			OBJ method = *(mp + 1);
			int paramCount = WORDS(FIELD(method, 2));
			if (i < paramCount) *(base + i) = newValue;
		}
	} else if (FIELD_REF & varBinding) {
		if (nargs < 1) return; // no receiver
		OBJ receiver = *base; // first arg is the receiver
		FIELD(receiver, i) = newValue;
	}
}

static void* findPrim(OBJ primOrFunctionName, OBJ receiver, int hasReceiver) {
	if (NOT_CLASS(primOrFunctionName, StringClass)) {
		failure("Non-string primitive name");
		printlnObj(primOrFunctionName);
		return (void*) NOOP;
	}

	// first, look for a user-defined function or method with the given name
	if (findMethod(primOrFunctionName, receiver, hasReceiver, currentModule)) return (void*) CALL;

	// then, look for a primitive with the given name
	OBJ primRef = dictAt(primitiveDictionary, primOrFunctionName);
	if (primRef != nilObj) return *((ADDR*) BODY(primRef));
// Old:
// 	PrimEntry *entry = primLookup(obj2str(primOrFunctionName));
// 	if (entry) return (void*) entry->primFunc;

	char err[200];
	sprintf(err, "Undefined function: %s", obj2str(primOrFunctionName));
	failure(err);
	return (void*) NOOP;
}

static gp_boolean growStack(int entriesNeeded, ADDR *sp, ADDR *fp, ADDR *mp, ADDR *stackEnd) {
	OBJ oldStack = FIELD(currentTask, Task_Stack);
	int growBy = WORDS(oldStack);
	if (growBy > 10000000) growBy = 10000000;
	if (growBy < entriesNeeded) growBy += entriesNeeded;
	int newSize = WORDS(oldStack) + growBy;
	if (!canAllocate(newSize + 1000000)) {
		failure("Could not grow stack; infinite recursion?");
		return false;
	}
	OBJ newStack = copyObj(oldStack, newSize, 1);
	// printf("grow %d -> %d growBy %d sp %d\n", WORDS(oldStack), WORDS(newStack), growBy, (*sp - BODY(oldStack)) + 1);
	*sp = BODY(newStack) + (*sp - BODY(oldStack));
	*fp = BODY(newStack) + (*fp - BODY(oldStack));
	*mp = *mp ? BODY(newStack) + (*mp - BODY(oldStack)) : NULL;
	*stackEnd = BODY(newStack) + WORDS(newStack);
	FIELD(currentTask, Task_Stack) = newStack;
	return true;
}

static void saveStack(CmdPtr b, CmdPtr nextBlock, OBJ result, ADDR sp, ADDR fp, ADDR mp) {
	if (!currentTask) return;

	// clear the stack above stack pointer
	// Note: this could be done by adding knowledge of task stacks to the
	// garbage collector, but its nice not to see garbage above the stack
	// pointer when inspecting a stack from GP.
	OBJ stack = FIELD(currentTask, Task_Stack);
	ADDR end = BODY(stack) + WORDS(stack);
	memset(sp, 0, (end - sp) * sizeof(OBJ));

	FIELD(currentTask, Task_SP) = stackptr2offset(sp);
	FIELD(currentTask, Task_FP) = stackptr2offset(fp);
	FIELD(currentTask, Task_MP) = stackptr2offset(mp);
	FIELD(currentTask, Task_CurrentBlock) = (isNil(b) ? 0 : A2O(b));
	FIELD(currentTask, Task_NextBlock) = (isNil(nextBlock) ? 0 : A2O(nextBlock));
	FIELD(currentTask, Task_Result) = result;
	if (errorFlag) {
		FIELD(currentTask, Task_WaitReason) = newString("error");
		debugeeTask = currentTask;
	}
	stopFlag = false;
}

void showStack(ADDR sp, ADDR fp, ADDR mp) {
	// Low level stack dump for interpreter debugging.
	// xxx May need to be updated since stack->task rework.
	ADDR stackBase = O2A(FIELD(currentTask, Task_Stack));
	ADDR ptr = sp - 1;
	printf("%s\t-\n", ((sp == fp) ? "sp/fp:" : "sp:"));
	while (ptr >= stackBase) {
		if (fp == ptr) {
			printf((mp == fp) ? "mp/fp:\t" : "fp:\t");
		} else if (mp == ptr) printf("mp:\t");
		else printf("\t");

		OBJ v = *ptr--;
		if ((v > 1000000) && !isInt(v)) {
			if (CmdClass == objClass(v)) printf("%s:%d: {%s}\n", obj2str(((CmdPtr)O2A(v))->fileName), obj2int(((CmdPtr)O2A(v))->lineno), obj2str(((CmdPtr)O2A(v))->primName));
			else if (ReporterClass == objClass(v)) printf("(%s)\n", obj2str(((CmdPtr)O2A(v))->primName));
			else printlnObj(v);
		} else printf("%u\n", v);
	}
	printf("-----[stack base = %p]-----\n", stackBase);
}

// Browser support

void initCurrentTask(OBJ prog) {
	// Create a task
	OBJ stack = newArray(200);
	FIELD(stack, 0) = nilObj;
	FIELD(stack, 1) = STOP;
	OBJ task = newInstance(newString("Task"), 0);

	FIELD(task, Task_Stack) = stack;
	FIELD(task, Task_SP) = int2obj(3);
	FIELD(task, Task_FP) = int2obj(3);
	FIELD(task, Task_MP) = int2obj(0);
	FIELD(task, Task_CurrentBlock) = trueObj; // must be non-nil
	FIELD(task, Task_NextBlock) = prog;
	FIELD(task, Task_Result) = nilObj;
	FIELD(task, Task_TickLimit) = int2obj(0);

	currentTask = task;
}

void stepCurrentTask() {
	char *waitReason = "running";
	OBJ waitReasonObj = FIELD(currentTask, Task_WaitReason);
	if (IS_CLASS(waitReasonObj, StringClass)) waitReason = obj2str(waitReasonObj);

	if (strcmp("timer", waitReason) == 0) {
		OBJ primMSecsSinceStart(int nargs, OBJ args[]); // declare primitive reference

		int wakeMSecs = obj2int(FIELD(currentTask, Task_WakeMSecs));
		int currentMSecs = obj2int(primMSecsSinceStart(0, NULL));
		if (currentMSecs < wakeMSecs) return; // keep waiting
		FIELD(currentTask, Task_WaitReason) = nilObj;
	} else if (strcmp("terminated", waitReason) == 0) {
		printf("Task terminated\n");
		currentTask = nilObj;
	} else if (strcmp("error", waitReason) == 0) {
		// Note: error message already printed
		currentTask = nilObj;
	} else if (!FIELD(currentTask, Task_NextBlock)) {
		// normal completion; print the result
		printlnObj(FIELD(currentTask, Task_Result));
		currentTask = nilObj;
	}
	if (currentTask) run(currentTask);
}

// Profiling

#define MAX_PROFILE_DEPTH 100 // maximum stack depth to record in profile

static void logProfileData(OBJ block, ADDR mp) {
	if (!currentTask) return;
	OBJ profileArray = FIELD(currentTask, Task_ProfileArray);
	OBJ profileIndex = FIELD(currentTask, Task_ProfileIndex);
	if (NOT_CLASS(profileArray, ArrayClass) || !isInt(profileIndex)) return;

	int end = objWords(profileArray);
	int i = obj2int(profileIndex) - 1; // convert to 0-based index
	if ((i < 0) || ((i + 2) > end)) return; // profile index out of range

	FIELD(profileArray, i++) = block;
	FIELD(profileArray, i++) = int2obj(profileTick); // tick count
	if ((i + MAX_PROFILE_DEPTH) < end) end = i + MAX_PROFILE_DEPTH;
	while (mp && (i < end)) {
		OBJ method = *(mp + 1);
		FIELD(profileArray, i++) = method;
		mp = offset2stackptr(*(mp + 2));
	}
	FIELD(currentTask, Task_ProfileIndex) = int2obj(i + 1); // convert to 1-based index
}

// Interpreter Entry Point

OBJ run(OBJ startBlockOrTask) {
	ADDR sp;	// stack pointer: points one index past the top of stack
	ADDR fp;	// frame pointer: points to the first argument on the stack
	ADDR mp;	// method pointer: most recent user-defined method/function frame or NULL

	CmdPtr nextBlock = NULL; // the next block to execute
	CmdPtr b = NULL;		// current block as CmdPtr
	int nargs = 0;			// current block's argument count
	ADDR args = NULL;		// current block's argument list
	OBJ result;				// result of the last block execution

	errorFlag = false;
	stopFlag = false;
	ticks = 0;
	tickLimit = 0;
	result = nilObj;

	if (IS_CLASS(startBlockOrTask, TaskClass)) {
		currentTask = startBlockOrTask;
		goto installStackAndResume;
	}

	// Create a task
	currentTask = newInstance(newString("Task"), 0);
	OBJ stack = newArray(200);
	FIELD(currentTask, Task_Stack) = stack;
	ADDR stackEnd = BODY(stack) + WORDS(stack);
	sp = BODY(stack);
	*sp++ = nilObj;
	*sp++ = STOP;
	fp = sp;
	mp = NULL;
	nextBlock = (CmdPtr)O2A(startBlockOrTask);

	while ((b = nextBlock)) {
	runCommands:
		// Start argument evaluation of a command block
		fp = sp;
		nargs = argCount((ADDR)b);
		args = &(b->args[0]);
	continueArgEvalution:
		while ((sp - fp) < nargs) { // push block arguments
			OBJ arg = args[sp - fp];
			if (sp > fp) {
				// if this is not the first argument check for short-circuit AND or OR
				OBJ tmp = *(sp - 1);
				if ((tmp == falseObj) && ((b->prim == (PrimPtr) primLogicalAnd) || (!b->prim && strEQ("and", b->primName)))) {
					goto execute; // short-circuit AND
				}
				if ((tmp == trueObj) && ((b->prim == (PrimPtr) primLogicalOr) || (!b->prim && strEQ("or", b->primName)))) {
					goto execute; // short-circuit OR
				}
			}
			if ((sp + nargs + StackExtra) > stackEnd) {
				if (!growStack(nargs, &sp, &fp, &mp, &stackEnd)) goto suspend;
			}
			if (isReporter(arg)) {
				CmdPtr rArg = (CmdPtr)O2A(arg);
				if ((((void*)GETVAR) == rArg->prim) && rArg->cache) { // important optimization
					*sp++ = getVar(rArg->args[0], obj2int(rArg->cache), mp);
					continue;
				}
				// save the old evaluation state, then make this reporter the new current block
				*sp++ = stackptr2offset(fp);
				*sp++ = A2O(b);
				fp = sp;
				b = (CmdPtr)O2A(arg);
				nargs = argCount(O2A(arg));
				args = &(b->args[0]);
			} else {
				*sp++ = arg;
			}
		}
	execute:
		// The following code executes a block. If necessary, it looks up and caches the
		// primitive to be executed, either a function pointer or a GP integer indicating
		// an action dispatched via the switch statement below.

		args = fp; // evaluated arguments on stack
		if (!b->prim || (nargs && (obj2int(b->classIDCache) != objClass(args[0])) &&
						((b->prim > (void*) NOT_NIL) || (b->prim < (void*) STOP)) )) {
			// Look up the primitive if either b->prim is NULL OR
			// the receiver class has changed and p->prim is not a
			// primitive that is independent of the receiver:
			b->prim = findPrim(b->primName, args[0], (nargs != 0));
			b->cache = nilObj;
			b->classIDCache = int2obj(nargs ? objClass(args[0]) : 0);
		}
		// Uncomment the following line to trace the interpreter:
		// printf("%s -> %d\n", obj2str(b->primName), (int) b->prim);
		result = nilObj;
		nextBlock = (CmdPtr)(isReporter(A2O(b)) ? 0 : isNil(b->nextBlock) ? 0 : O2A(b->nextBlock));
		switch ((long) b->prim) {
			case GETVAR:
				if (!b->cache) b->cache = variableBinding(args[0], mp);
				result = getVar(args[0], obj2int(b->cache), mp);
				break;
			case ARG_COUNT:
				result = mp ? *mp : int2obj(0);
				break;
			case GETARG:
			{
				int i = obj2int(args[0]);
				if (mp && (1 <= i) && (i <= obj2int(*mp))) {
					// result = (OBJ) *(((OBJ) offset2stackptr(*(mp - 1))) + i - 1);
					result = *(offset2stackptr(*(mp - 1)) + i - 1);
				} else {
					result = nilObj; // not in a call or arg index out of range
				}
				break;
			}
			case APPLY:
				if (nargs > 0) {
					OBJ op = args[0];
					if (!((IS_CLASS(op, StringClass) || IS_CLASS(op, FunctionClass)))) {
						failure("First argument of 'call' must be a String or Function");
						break;
					}

					// remove the first argument (the operator), leaving other args on stack
					for (int i = 1; i < nargs; i++) fp[i - 1] = fp[i];
					nargs--;
					sp--;

					b = (CmdPtr)O2A(cloneObj(A2O(b))); // replace b with copy we can modify

					if (IS_CLASS(op, StringClass)) {
						b->primName = op;
						b->cache = nilObj;
					} else {
						b->prim = (void*)CALL;
						b->cache = op; // function object
						currentModule = moduleOfFunction(op);
						b->classIDCache = int2obj(nargs ? objClass(args[0]) : 0);
					}
					goto execute;
				}
				break;
			case APPLY_TO_ARRAY:
				if (nargs >= 2) {
					OBJ op = args[0];
					OBJ argArray = args[1];
					if (!((IS_CLASS(op, StringClass) || IS_CLASS(op, FunctionClass)))) {
						failure("First argument of 'callWith' must be a String or Function");
						break;
					}
					if (NOT_CLASS(argArray, ArrayClass)) {
						failure("Second argument of 'callWith' must be an Array");
						break;
					}
					nargs = WORDS(argArray);
					if ((sp + nargs + StackExtra) > stackEnd) {
						if (!growStack(nargs, &sp, &fp, &mp, &stackEnd)) goto suspend;
					}
					// replace args with contents of the argument array
					nargs = WORDS(argArray);
					sp = fp;
					for (int i = 0; i < nargs; i++) *sp++ = FIELD(argArray, i);

					b = (CmdPtr)O2A(cloneObj(A2O(b))); // replace b with copy we can modify

					if (IS_CLASS(op, StringClass)) {
						b->primName = op;
						b->cache = nilObj;
					} else {
						b->prim = (void*)CALL;
						b->cache = op; // function object
						currentModule = moduleOfFunction(op);
						b->classIDCache = int2obj(nargs ? objClass(args[0]) : 0);
					}
					goto execute;
				}
				break;
			case CALL: // call a user-defined method
				if (!b->cache) {
					b->cache = findMethod(b->primName, args[0], (nargs != 0), currentModule);
					b->classIDCache = nargs ? int2obj(objClass(args[0])) : int2obj(0);
				}
				if (b->cache) {
					OBJ method = b->cache;
					if ((FIELD(method, 1) > int2obj(0)) && (nargs < 1)) {
						failure("A method call must have at least one argument");
						break;
					}
					if (NOT_CLASS(FIELD(method, 4), CmdClass)) break; // nil command list
					if ((sp + nargs + StackExtra) > stackEnd) {
						if (!growStack(nargs, &sp, &fp, &mp, &stackEnd)) goto suspend;
					}
					int i = WORDS(FIELD(method, 2)) - nargs; // number of formal minus actual args
					while (i-- > 0) *sp++ = nilObj; // initialize any unsuppied named args to nil
					i = objWords(FIELD(method, 3)); // number of local variables
					while (i-- > 0) *sp++ = nilObj; // initialize local variables to nil
					*sp++ = stackptr2offset(fp);
					*sp++ = int2obj(nargs); // <- mp points here during the call
					*sp++ = method;
					*sp++ = stackptr2offset(mp); // old mp
					mp = (sp - 3);
					currentModule = moduleOfFunction(method);
					*sp++ = A2O(b);
					*sp++ = isReporter(A2O(b)) ? REPORTER_END : CMD_END;
					b = (CmdPtr)O2A(FIELD(method, 4)); // cmdList
					goto runCommands;
				}
				break;
			case IF:
				// arbitrary number of if/elseif (condition-action pairs) clauses
				for (int i = 0; i < (nargs - 1); i += 2) {
					// find first true condition
					if (trueObj == args[i]) {
						if (IS_CLASS(b->args[i + 1], CmdClass)) {
							sp = fp; // clear arguments
							*sp++ = A2O(b);
							*sp++ = IF;
							nextBlock = (CmdPtr)O2A(b->args[i + 1]);
							fp = sp;
							break;
						} else {
							if (nilObj != b->args[i + 1]) failure("Bad command list in 'if'");
							break;
						}
					}
				}
				break;
			case REPEAT:
			{
				OBJ tmp = args[0];
				if (IS_CLASS(tmp, FloatClass)) tmp = int2obj((int) evalFloat(tmp));
				if (isInt(tmp)) {
					if (NOT_CLASS(b->args[1], CmdClass)) break; // empty cmdList
					if (obj2int(tmp) <= 0) break;
					sp = fp; // clear arguments
					*sp++ = tmp; // loop counter
					*sp++ = A2O(b);
					*sp++ = REPEAT;
					nextBlock = (CmdPtr)O2A(b->args[1]);
					fp = sp;
				} else {
					failure("First argument of 'repeat' must be an integer or float");
				}
				break;
			}
			case ANIMATE:
				if (IS_CLASS(b->args[0], CmdClass)) {
					sp = fp; // clear arguments
					*sp++ = A2O(b);
					*sp++ = ANIMATE;
					nextBlock = (CmdPtr)O2A(b->args[0]);
					fp = sp;
				}
				break;
			case WHILE:
				if ((trueObj == args[0]) && IS_CLASS(b->args[1], CmdClass)) {
					sp = fp; // clear arguments
					*sp++ = A2O(b);
					*sp++ = WHILE;
					nextBlock = (CmdPtr)O2A(b->args[1]);
					fp = sp;
				}
				break;
			case WAIT_UNTIL:
				sp = fp; // clear arguments
				if (falseObj == args[0]) {
					nextBlock = b; // restart this block
					FIELD(currentTask, Task_WaitReason) = newString("display");
					yield();
				}
				break;
			case FOR:
				if (NOT_CLASS(args[0], StringClass)) {
					failure("First argument of 'for' must be a variable name");
				} else {
					if ((nargs < 3) || (NOT_CLASS(b->args[2], CmdClass))) break; // empty or missing command list
					OBJ limit = args[1];
					if (IS_CLASS(limit, FloatClass)) limit = int2obj((int) evalFloat(limit));
					if (isInt(limit)) {
						if (obj2int(limit) <= 0) break; // limit <= 0
						OBJ tmp = variableBinding(args[0], mp);
						setVar(args[0], obj2int(tmp), mp, int2obj(1)); // initial index = 1
						sp = fp; // clear arguments
						*sp++ = tmp; // variable binding
						*sp++ = limit;
						*sp++ = int2obj(1); // index
						*sp++ = A2O(b);
						*sp++ = FOR;
						nextBlock = (CmdPtr)O2A(b->args[2]);
						fp = sp;
					} else if (IS_CLASS(limit, ArrayClass) || IS_CLASS(limit, ListClass)) { // iterate over an array
						OBJ array = limit;
						int index = 0;
						limit = int2obj(WORDS(array));
						if (IS_CLASS(array, ListClass)) {
							OBJ list = array;
							index = obj2int(FIELD(list, 0)) - 1;
							limit = FIELD(list, 1);
							array = FIELD(list, 2);
						}
						if (index >= obj2int(limit)) break; // empty array or list
						OBJ tmp = variableBinding(args[0], mp);
						setVar(args[0], obj2int(tmp), mp, FIELD(array, index)); // first element
						sp = fp; // clear arguments
						*sp++ = array;
						*sp++ = tmp; // variable binding
						*sp++ = limit;
						*sp++ = int2obj(index); // current index (zero-based)
						*sp++ = A2O(b);
						*sp++ = FOR_EACH;
						nextBlock = (CmdPtr)O2A(b->args[2]);
						fp = sp;
					} else {
						failure("Second argument of 'for' must be an integer, float, or array");
					}
				}
				break;
			case UNINTERRUPTEDLY:
				if (IS_CLASS(b->args[0], CmdClass)) {
					sp = fp; // clear arguments
					*sp++ = int2obj(tickLimit);
					*sp++ = A2O(b);
					*sp++ = UNINTERRUPTEDLY;
					tickLimit = 0;
					nextBlock = (CmdPtr)O2A(b->args[0]);
					fp = sp;
				}
				break;
			case SETVAR:
				if (!b->cache) b->cache = variableBinding(args[0], mp);
				setVar(args[0], obj2int(b->cache), mp, args[1]);
				break;
			case LOCALVAR:
				if (nargs > 1) {
					// may have 2 or 3 args; first arg is variable last is value
					if (!b->cache) b->cache = variableBinding(args[0], mp);
					setVar(args[0], obj2int(b->cache), mp, args[nargs - 1]);
				}
				break;
			case CHANGEBY:
			{
				if (!b->cache) b->cache = variableBinding(args[0], mp);
				int i = obj2int(b->cache);
				OBJ tmp = getVar(args[0], i, mp);
				if (tmp == nilObj) tmp = int2obj(0);
				if (bothInts(tmp, args[1])) {
					tmp = int2obj(obj2int(tmp) + obj2int(args[1]));
					setVar(args[0], i, mp, tmp);
				} else {
					tmp = newFloat(evalFloat(tmp) + evalFloat(args[1]));
					if (!errorFlag) setVar(args[0], i, mp, tmp);
				}
				break;
			}
			case RETURN:
				if (nargs > 0) result = args[0];
				if (mp == NULL) break; // not inside a method; do nothing
				sp = mp + 5;
				nextBlock = (CmdPtr) nilObj;
				goto handleNextAction;
				break;
			case GC:
				debugeeTask = nilObj; // clear debugeeTask
				gcPrimitiveCalled = gcNeeded = true;
				break;
			case CURRENT_TASK:
				{
					int oldStopFlag = stopFlag;
					saveStack(b, nextBlock, result, sp, fp, mp); // clears stopFlag
					stopFlag = oldStopFlag;
					result = currentTask;
				}
				break;
			case RESUME:
				if ((nargs < 1) || NOT_CLASS(args[0], TaskClass)) {
					failure("First argument of resume must be a Task");
					break;
				}
				OBJ taskToResume = args[0];
				if (FIELD(taskToResume, 3) == nilObj) break; // no block; task is terminated

				saveStack(b, nextBlock, result, sp, fp, mp); // clears stopFlag
				currentTask = taskToResume;
				debugeeTask = nilObj;
				errorFlag = false;
				stopFlag = ((nargs > 1) && (args[1] == trueObj)); // if second arg is true, single step
				ticks = 0;

			installStackAndResume:
			{
				if (NOT_CLASS(currentTask, TaskClass)) {
					failure("Bad task in resume");
					break;
				}
				OBJ newStack = FIELD(currentTask, Task_Stack);
				if (NOT_CLASS(newStack, ArrayClass) || (WORDS(newStack) < 5)) {
					failure("Task has bad stack in resume");
					break;
				}
				FIELD(newStack, 1) = STOP; // ensure task has the correct STOP action
				stackEnd = BODY(newStack) + WORDS(newStack);
				sp = offset2stackptr(FIELD(currentTask, Task_SP));
				fp = offset2stackptr(FIELD(currentTask, Task_FP));
				mp = offset2stackptr(FIELD(currentTask, Task_MP));
				currentModule = mp ? moduleOfFunction((OBJ)*(mp + 1)) : currentModule;

				b = (CmdPtr)(isNil(FIELD(currentTask, Task_CurrentBlock)) ? 0 : O2A(FIELD(currentTask, Task_CurrentBlock)));
				nextBlock = (CmdPtr)(isNil(FIELD(currentTask, Task_NextBlock)) ? 0 : O2A(FIELD(currentTask, Task_NextBlock)));

				result = FIELD(currentTask, Task_Result);
				OBJ tmp = FIELD(currentTask, Task_TickLimit);
				tickLimit = isInt(tmp) ? obj2int(tmp) : 0;
				goto resume;
				break;
			}
			case IS_NIL:
				result = (args[0] == nilObj) ? trueObj : falseObj;
				break;
			case NOT_NIL:
				result = (args[0] != nilObj) ? trueObj : falseObj;
				break;
			case LAST_RECEIVER:
				result = lastReceiver(obj2int(stackptr2offset(mp)));
				break;
			case ADD:
				if (nargs == 2) {
					OBJ arg1 = args[0];
					OBJ arg2 = args[1];
					if (bothInts(arg1, arg2)) {
						result = int2obj(obj2int(arg1) + obj2int(arg2)); // common case: 2 int args
						break;
					}
				}
				result = primAdd(nargs, args);
				break;
			case SUB:
				if (nargs == 2) {
					OBJ arg1 = args[0];
					OBJ arg2 = args[1];
					if (bothInts(arg1, arg2)) {
						result = int2obj(obj2int(arg1) - obj2int(arg2)); // common case: 2 int args
						break;
					}
				}
				result = primSub(nargs, args);
				break;
			case LESS:
				if (nargs == 2) {
					OBJ arg1 = args[0];
					OBJ arg2 = args[1];
					if (bothInts(arg1, arg2)) {
						result = (obj2int(arg1) < obj2int(arg2)) ? trueObj :falseObj; // common case: 2 int args
						break;
					}
				}
				result = primLess(nargs, args);
				break;
			case NOOP:
				break;
			default:
#ifdef EMSCRIPTEN
				if (b->prim < (void*)STOP) result = ((PrimPtr)(b->prim))(nargs, args);
#else
				if (b->prim > (void*)NOOP) result = ((PrimPtr)(b->prim))(nargs, args);
#endif
		}
		if (gcNeeded) {
			// GC is inlined so interpreter state can be saved/restored
			// save interpreter state
			FIELD(vmRoots, 0) = stackptr2offset(sp);
			FIELD(vmRoots, 1) = stackptr2offset(fp);
			FIELD(vmRoots, 2) = stackptr2offset(mp);
			FIELD(vmRoots, 3) = stackptr2offset(stackEnd);
			FIELD(vmRoots, 4) = (isNil(b) ? 0 : A2O(b));
			FIELD(vmRoots, 5) = (isNil(nextBlock) ? 0 : A2O(nextBlock));
			FIELD(vmRoots, 6) = result;

			// clear the stack above sp to avoid holding onto otherwise unreferenced objects
			ADDR tmpPtr = sp;
			while (tmpPtr < stackEnd) *tmpPtr++ = nilObj;

			int reclaimed = collectGarbage(nargs && (args[0] == trueObj));

			// restore interpreter state
			sp = offset2stackptr(FIELD(vmRoots, 0));
			fp = offset2stackptr(FIELD(vmRoots, 1));
			mp = offset2stackptr(FIELD(vmRoots, 2));
			stackEnd = offset2stackptr(FIELD(vmRoots, 3));
			b = (CmdPtr)O2A(FIELD(vmRoots, 4));
			nextBlock = (CmdPtr)(isNil(FIELD(vmRoots, 5)) ? 0 : O2A(FIELD(vmRoots, 5)));
			result = FIELD(vmRoots, 6);

			if (gcPrimitiveCalled) result = int2obj(reclaimed);
			gcPrimitiveCalled = gcNeeded = false;
		}
		if (profileTick) {
			logProfileData(A2O(b), mp);
			profileTick = 0;
		}

		if (stopFlag) {
	suspend:
			saveStack(b, nextBlock, result, sp, fp, mp);
			if (FIELD(currentTask, Task_TaskToResume)) {
				currentTask = FIELD(currentTask, Task_TaskToResume);
				errorFlag = false;
				stopFlag = false;
				goto installStackAndResume;
			}
			if (errorFlag) {
				if (b->fileName) printf("Stopped at (%s:%d)\n    %s", obj2str(b->fileName), obj2int(b->lineno), obj2str(b->primName));
				for (int i = 0; i < nargs; i++) {
					printf(" ");
					printObj(args[i], 0);
				}
				printf("\n");
				printf("To debug, type: db = (debug)\n");
			}
			currentModule = sessionModule;
			return result;
		}
	resume:
		sp = fp; // clear arguments
		if (nextBlock) continue; // continue to the next block

		// Reporter: pop old state, push result, and continue with argument evaluation
		if (isReporter(A2O(b))) {
			OBJ maybeB = *(--sp);
			if (maybeB == STOP) {
				saveStack(NULL, NULL, result, sp + 1, sp + 1, mp);
				if (FIELD(currentTask, Task_TaskToResume)) {
					currentTask = FIELD(currentTask, Task_TaskToResume);
					goto installStackAndResume;
				}
				currentModule = sessionModule;
				return result;
			}
			b = (CmdPtr)O2A(maybeB);
			fp = offset2stackptr(*(sp - 1));
			*(sp - 1) = result; // push return value
			nargs = argCount((ADDR)b);
			args = &(b->args[0]);
			if ((result == trueObj) && !(nargs & 1)) { // possible true case in an IF
				if ((b->prim == (void*)IF) || (!b->prim && strEQ("if", b->primName))) goto execute;
			}
			goto continueArgEvalution;
		}
	handleNextAction:
		// The following code decides what to do when nextBlock is nil (i.e. at the end of a command list)
		while (!nextBlock) {
			b = (CmdPtr)O2A(*(sp - 2));
			switch (*(sp - 1)) {
				case STOP:
					saveStack(NULL, NULL, result, sp, fp, mp);
					if (FIELD(currentTask, Task_TaskToResume)) {
						currentTask = FIELD(currentTask, Task_TaskToResume);
						goto installStackAndResume;
					}
					currentModule = sessionModule;
					return nilObj;
				case IF:
					nextBlock = (CmdPtr)(isNil(b->nextBlock) ? 0 : O2A(b->nextBlock));
					sp -= 2;
					break;
				case REPEAT:
					if ((*(sp - 3) -= 2) > 1) { // restart loop body if loopCounter > 0 (decrement and are test done as GP integers)
						nextBlock = (CmdPtr)O2A(b->args[1]);
						if (tickLimit && (ticks++ > tickLimit)) { fp = sp; goto suspend; }
					} else { // exit the loop
						nextBlock = (CmdPtr)(isNil(b->nextBlock) ? 0 : O2A(b->nextBlock));
						sp -= 3;
					}
					break;
				case ANIMATE:
					nextBlock = b; // restart while to re-evaluate the condition
					sp -= 2;
					FIELD(currentTask, Task_WaitReason) = newString("display");
					yield();
					break;
				case WHILE:
					nextBlock = b; // restart while to re-evaluate the condition
					sp -= 2;
					if (tickLimit && (ticks++ > tickLimit)) { fp = sp; goto suspend; }
					break;
				case FOR:
				{
					if ((*(sp - 3) += 2) <= *(sp - 4)) { // restart loop body if loopCounter <= limit
						int i = obj2int(*(sp - 5)); // saved variable binding
						setVar(b->args[0], i, mp, *(sp - 3));
						nextBlock = (CmdPtr)O2A(b->args[2]);
						if (tickLimit && (ticks++ > tickLimit)) { fp = sp; goto suspend; }
					} else { // exit the loop
						nextBlock = (CmdPtr)(isNil(b->nextBlock) ? 0 : O2A(b->nextBlock));
						sp -= 5;
					}
					break;
				}
				case FOR_EACH:
				{
					if ((*(sp - 3) += 2) < *(sp - 4)) { // restart loop body if loopCounter < array size
						int i = obj2int(*(sp - 5)); // saved variable binding
						OBJ array = *(sp - 6);
						setVar(b->args[0], i, mp, FIELD(array, obj2int(*(sp - 3))));
						nextBlock = (CmdPtr)O2A(b->args[2]);
						if (tickLimit && (ticks++ > tickLimit)) { fp = sp; goto suspend; }
					} else { // exit the loop
						nextBlock = (CmdPtr)(isNil(b->nextBlock) ? 0 : O2A(b->nextBlock));
						sp -= 6;
					}
					break;
				}
				case UNINTERRUPTEDLY:
					tickLimit = obj2int(*(sp - 3));
					nextBlock = (CmdPtr)(isNil(b->nextBlock) ? 0 : O2A(b->nextBlock));
					sp -= 3;
					fp = sp;
					break;
				case CMD_END:
					sp = offset2stackptr(*(mp - 1)); // restore pre-call sp
					mp = offset2stackptr(*(mp + 2));
					currentModule = mp ? moduleOfFunction(*(mp + 1)) : consoleModule;
					nextBlock = (CmdPtr)(isNil(b->nextBlock) ? 0 : O2A(b->nextBlock));
					result = nilObj;
					if (stopFlag) { fp = sp; goto suspend; }
					break;
				case REPORTER_END:
					sp = offset2stackptr(*(mp - 1)); // restore pre-call sp
					mp = offset2stackptr(*(mp + 2));
					currentModule = mp ? moduleOfFunction(*(mp + 1)) : consoleModule;
					if (stopFlag) { fp = sp; goto suspend; }
					OBJ maybeB = *(--sp);
					if (maybeB == STOP) {
						saveStack(NULL, NULL, result, sp + 1, sp + 1, mp);
						if (FIELD(currentTask, Task_TaskToResume)) {
							currentTask = FIELD(currentTask, Task_TaskToResume);
							goto installStackAndResume;
						}
						currentModule = sessionModule;
						return result;
					}
					b = (CmdPtr)O2A(maybeB);
					fp = offset2stackptr(*(sp - 1));
					*(sp - 1) = result; // push return value
					nargs = argCount((ADDR)b);
					args = &(b->args[0]);
					goto continueArgEvalution;
				default:
					printf("VM bug: unknown blockEndAction %d sp %d\n", *(sp - 1), (int)stackptr2offset(sp));
					debugeeTask = currentTask;
					currentTask = nilObj;
					currentModule = sessionModule;
					return nilObj; // shouldn't happen; stack bug?
			}
		}
	}
	currentModule = sessionModule;
	return nilObj;
}
