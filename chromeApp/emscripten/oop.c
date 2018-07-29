// oop.c - Object-oriented programming support
// John Maloney, November 2013

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "mem.h"
#include "cache.h"
#include "dict.h"
#include "interp.h"
#include "oop.h"

int readingLibrary = false;

// ***** Class Field Names *****

#define ClassFieldCount 7
#define Class_ClassName 0
#define Class_ClassIndex 1
#define Class_FieldNames 2
#define Class_Methods 3
#define Class_Comments 4
#define Class_Scripts 5
#define Class_Module 6

// ***** Helper Functions *****

static gp_boolean argNameConflictsWithFieldName(OBJ classObj, OBJ argNames) {
	int count = objWords(argNames);
	if (!classObj) return false; // function is not a method
	OBJ fieldNames = FIELD(classObj, Class_FieldNames);
	for (int i = 0; i < count; i++) {
		if (indexOfString(FIELD(argNames, i), fieldNames) > -1) return true;
	}
	return false;
}

static void clearCaches() {
	// Clear all Command and Reporter inline caches
	if (readingLibrary) return;

	OBJ obj = objectAfter(nilObj, 0);
	while (obj) {
		int id = CLASS(obj);
		if ((CmdClass == id) || (ReporterClass == id)) {
			((CmdPtr) O2A(obj))->cache = nilObj; // clear the cache
		}
		obj = objectAfter(obj, 0);
	}
}

static inline int argCount(OBJ b) { return (WORDS(b) - CmdFieldCount); }

static OBJ addLocalIfNotPresent(OBJ varName, OBJ argNames, OBJ fields, OBJ locals) {
	if (!locals) return nilObj;
	if (indexOfString(varName, argNames) > -1) return locals;
	if (indexOfString(varName, fields) > -1) return locals;
	if (indexOfString(varName, locals) > -1) return locals;
	return copyArrayWith(locals, varName);
}

static OBJ addReporterLocals(OBJ b, OBJ argNames, OBJ fields, OBJ locals) {
	if (NOT_CLASS(b, ReporterClass)) return locals;
	CmdPtr r = (CmdPtr)O2A(b);
	if (strEQ("v", r->primName)) { // GETVAR
		OBJ varName = r->args[0];
		return addLocalIfNotPresent(varName, argNames, fields, locals);
	}
	int nargs = argCount(b);
	for (int i = 0; i < nargs; i++) {
		locals = addReporterLocals(r->args[i], argNames, fields, locals);
	}
	return locals;
}

static OBJ collectLocals(OBJ cmdList, OBJ argNames, OBJ fields, OBJ locals, OBJ outerLocals) {
	// Return an array containing all local variables in the given command list, or
	// nil if there are variable name conflicts. A local variable is a variable
	// that is neither a parameter name nor a field name. outerLocals contains
	// variables used in enclosing for loops; such variables can't be used
	// as an index variable of an inner for loop. locals contains all the local
	// variables found so far.
	OBJ varName;
	if (isNil(cmdList)) {return locals;}
	for (CmdPtr cmd = (CmdPtr)O2A(cmdList); cmd != NULL; cmd = (CmdPtr)(isNilTrueFalse(cmd->nextBlock) ? NULL : O2A(cmd->nextBlock))) {
		OBJ op = cmd->primName;
		int nargs = argCount(A2O(cmd));
		if ((strEQ("=", op) || strEQ("+=", op)) && (nargs > 0)) {
			varName = cmd->args[0];
			locals = addLocalIfNotPresent(varName, argNames, fields, locals);
			locals = addReporterLocals(cmd->args[1], argNames, fields, locals);
		} else if (strEQ("for", op) && (nargs > 2)) {
			varName = cmd->args[0];
			if (indexOfString(varName, outerLocals) > -1) {
				printf("Error: Variable %s used in nested FOR loops\n", obj2str(varName));
				return nilObj;
			}
			locals = addLocalIfNotPresent(varName, argNames, fields, locals);
			locals = addReporterLocals(cmd->args[1], argNames, fields, locals);
			locals = collectLocals(cmd->args[2], argNames, fields, locals, copyArrayWith(outerLocals, varName));
		} else if (strEQ("function", op) || strEQ("method", op)) {
			// variables inside a function/method body are not visible, so skip them
		} else {
			int nargs = argCount(A2O(cmd));
			for (int i = 0; i < nargs; i++) {
				OBJ arg = cmd->args[i];
				if (IS_CLASS(arg, ReporterClass)) {
					locals = addReporterLocals(arg, argNames, fields, locals);
				} else if (IS_CLASS(arg, CmdClass)) {
					locals = collectLocals(arg, argNames, fields, locals, outerLocals);
				}
			}
		}
		if (!locals) break;
	}
	return locals;
}

static int indexOfObject(OBJ key, OBJ arrayOfObjects, int keyField) {
	// Return the index of the first object whose keyField field matches the key (a string)
	// in an array of objects. Return -1 if there is no match. Skip nil elements.

	if (!arrayOfObjects) return -1;

	if (NOT_CLASS(key, StringClass)) {
		printf("Error: Key must be String; got %s\n", getClassName(key));
		return -1;
	}
	if (NOT_CLASS(arrayOfObjects, ArrayClass) && NOT_CLASS(arrayOfObjects, WeakArrayClass)) {
		printf("Error: indexOfObject expected Array or nil; got %s\n", getClassName(arrayOfObjects));
		return -1;
	}
	char *k = obj2str(key);
	int count = objWords(arrayOfObjects);
	for (int i = 0; i < count; i++) {
		OBJ obj = FIELD(arrayOfObjects, i);
		if (keyField >= objWords(obj)) continue; // nil or object too small
		OBJ s = FIELD(obj, keyField);
		if (IS_CLASS(s, StringClass) && (strcmp(k, obj2str(s)) == 0)) return i;
	}
	return -1;
}

// ***** Class Operations *****

OBJ addClass(OBJ classObj) {
	// Add the given class to the classes Array, making room if necessary, and set the classIndex of class.

	// first, look for an empty slot
	int classesSize = objWords(classes);
	for (int i = 0; i < classesSize; i++) {
		if (!FIELD(classes, i)) {
			FIELD(classObj, 1) = int2obj(i + 1); // classIndex
			FIELD(classes, i) = classObj;
			return classObj;
		}
	}
	// no empty slots; grow the class table and add class to first new slot
	classes = copyArrayWith(classes, classObj);
	FIELD(classObj, 1) = int2obj(classesSize + 1); // classIndex
	return classObj;
}

static OBJ addClassToModule(OBJ classObj, OBJ module) {
	OBJ moduleClasses = FIELD(module, Module_Classes);
	int classesSize = objWords(moduleClasses);
	addClass(classObj);
	FIELD(classObj, Class_Module) = module;
	for (int i = 0; i < classesSize; i++) {
		if (!FIELD(moduleClasses, i)) {
			FIELD(moduleClasses, i) = classObj;
			return classObj;
		}
	}
	// no empty slots; grow the class table and add class to first new slot
	moduleClasses = copyArrayWith(moduleClasses, classObj);
	FIELD(module, Module_Classes) = moduleClasses;
	return classObj;
}

static OBJ createClass(char *className, int fieldCount, char *fieldNames[]) {
	OBJ fields = newArray(fieldCount);
	for (int i = 0; i < fieldCount; i++) {
		FIELD(fields, i) = newString(fieldNames[i]);
	}
	OBJ classObj = classFromIndex(ClassClass); // may be nil during VM class initialization
	OBJ newClass = (classObj) ? newInstance(classObj, 0) : newObj(ClassClass, ClassFieldCount, nilObj);
	FIELD(newClass, Class_ClassName) = newString(className);
	FIELD(newClass, Class_ClassIndex) = nilObj; // filled in later
	FIELD(newClass, Class_FieldNames) = fields;
	FIELD(newClass, Class_Methods) = newArray(0);
	FIELD(newClass, Class_Comments) = newArray(0);
	return newClass;
}

OBJ defineClass(OBJ className, OBJ module) {
	OBJ classObj = classFromNameInModuleNoDelegate(className, module);
	if (classObj) return classObj; // class already exists
	return addClassToModule(createClass(obj2str(className), 0, 0), module);
}

void addField(OBJ classObj, OBJ fieldName) {
	// Assume caller has ensured that c is a class object.
	OBJ fieldNames = FIELD(classObj, Class_FieldNames);
	if (indexOfString(fieldName, fieldNames) > -1) return; // already defined
	fieldNames = copyArrayWith(fieldNames, fieldName);
	FIELD(classObj, Class_FieldNames) = fieldNames;
}

OBJ classFromIndex(int classIndex) {
	int classesSize = objWords(classes);
	if ((classIndex < 1) || (classIndex > classesSize)) return nilObj;
	return FIELD(classes, classIndex - 1);
}

static OBJ classFromName(OBJ className) {
	// Lookup a class by name in the classes array and return the class or nil if not found.
	if (NOT_CLASS(className, StringClass)) {
		printf("Error: Key must be String; got %s\n", getClassName(className));
		return nilObj;
	}
	char *k = obj2str(className);
	int count = objWords(classes);
	for (int i = 0; i < count; i++) {
		OBJ obj = FIELD(classes, i);
		if (0 >= objWords(obj)) continue; // nil or object too small
		OBJ s = FIELD(obj, Class_ClassName);
		if (IS_CLASS(s, StringClass) && (strcmp(k, obj2str(s)) == 0) && (FIELD(obj, Class_Module) == topLevelModule)) return obj;
	}
	return nilObj;
}

OBJ classFromNameInModule(OBJ className, OBJ module) {
	if ((module != nilObj) && (module != topLevelModule)) {
		OBJ moduleClasses = FIELD(module, Module_Classes);
		int i = indexOfObject(className, moduleClasses, 0);
		if (i >= 0) return FIELD(moduleClasses, i);
	}
	return classFromName(className);
}

OBJ classFromNameInModuleNoDelegate(OBJ className, OBJ module) {
	if ((module != nilObj) && (module != topLevelModule)) {
		OBJ moduleClasses = FIELD(module, Module_Classes);
		int i = indexOfObject(className, moduleClasses, 0);
		if (i >= 0) return FIELD(moduleClasses, i);
		return nilObj;
	}
	return classFromName(className);
}

char *getClassName(OBJ obj) {
	OBJ c = classFromIndex(objClass(obj));
	if (!c) return "Unknown class";
	return obj2str(FIELD(c, Class_ClassName));
}

// ***** Modules *****

OBJ newModule(char *moduleName) {
	OBJ module = newInstance(classFromIndex(ModuleClass), 0);
	FIELD(module, Module_ModuleName) = newString(moduleName);
	FIELD(module, Module_Classes) = newArray(0);
	FIELD(module, Module_Functions) = newArray(0);
	FIELD(module, Module_Expanders) = nilObj;
	FIELD(module, Module_VariableNames) = newArray(0);
	FIELD(module, Module_Variables) = newArray(0);
	FIELD(module, Module_Exports) = newDict(4);
	return module;
}

void addModuleVariable(OBJ module, OBJ varName, OBJ value) {
	if (!module) return; // should not happen
	OBJ variableNames = FIELD(module, Module_VariableNames);
	int i = indexOfString(varName, variableNames);
	if (i >= 0) return;
	FIELD(module, Module_VariableNames) = copyArrayWith(variableNames, varName);
	FIELD(module, Module_Variables) = copyArrayWith(FIELD(module, Module_Variables), value);
	clearCaches();
}

// ***** Instance Operations *****

OBJ newInstance(OBJ classOrClassName, int indexableCount) {
	// Return a new instance of the given class or nil if class is not defined.
	// The new instance will have indexableCount indexable fields in addition
	// to any named instance variables it might have.
	OBJ c = classOrClassName;
	if (IS_CLASS(c, StringClass)) c = classFromNameInModule(classOrClassName, currentModule);
	if (NOT_CLASS(c, ClassClass)) return primFailed("Unknown class");

	int classIndex = obj2int(FIELD(c, Class_ClassIndex));
	int instVarCount = objWords(FIELD(c, Class_FieldNames));

	if ((BinaryDataClass == classIndex) ||
		(ExternalReferenceClass == classIndex) ||
		(FloatClass == classIndex) ||
		(StringClass == classIndex)) {
			return primFailed("You cannot use new or newIndexable to instantiate objects containing binary data");
	}
	return newObj(classIndex, instVarCount + indexableCount, nilObj);
}

int getFieldIndex(OBJ obj, OBJ fieldIndexOrName) {
	// Return the zero-based index for the given field of the given object
	// or -1 if the index is out of range or there is no matching field name
	// or the object contains binary data.
	if (isInt(obj) || (obj <= falseObj) || !HAS_OBJECTS(obj)) return -1;

	int classIndex = objClass(obj);
	OBJ classObj = classFromIndex(classIndex);
	if (!classObj) return -1;

	if (isInt(fieldIndexOrName)) { // numeric field index
		int fieldIndex = obj2int(fieldIndexOrName);
		if ((fieldIndex >= 1) && (fieldIndex <= objWords(obj))) return fieldIndex - 1;
	} else if (IS_CLASS(fieldIndexOrName, StringClass)) {
		// look for field name in class field name array
		OBJ fieldNames = FIELD(classObj, Class_FieldNames);
		int i = indexOfString(fieldIndexOrName, fieldNames);
		if (i > -1) return i;
	}
	return -1;
}

// ***** Method Operations *****

OBJ addMethod(OBJ classObj, OBJ functionName, OBJ argNames, OBJ module, OBJ cmdList, int installFlag) {
	if (!isNil(cmdList) && NOT_CLASS(cmdList, CmdClass)) {
		printf("A function body is zero or more commands inside curly braces, such as { print 'hi' }\n");
		return nilObj;
	}
	if (classObj) {
		if (argNameConflictsWithFieldName(classObj, argNames)) {
			printf("Argument names must be different from field names\n");
			return nilObj;
		}
		module = FIELD(classObj, Class_Module);
	}
	if (!module) {
		// should never happen
		module = topLevelModule;
		printf("Warning: Nil module in addMethod; defining function in topLevelModule\n");
	}
	OBJ fieldNames = classObj ? FIELD(classObj, Class_FieldNames) : nilObj;
	OBJ localNames = collectLocals(cmdList, argNames, fieldNames, newArray(0), newArray(0));
	OBJ classIndex = classObj ? FIELD(classObj, Class_ClassIndex) : int2obj(0);

	if (!classObj && ((indexOfString(newString("this"), localNames) > -1) || (indexOfString(newString("this"), argNames) > -1))) {
		printf("You can only use 'this' in a method\n");
		return nilObj;
	}

	OBJ newFunction = newInstance(classFromIndex(FunctionClass), 0);
	FIELD(newFunction, 0) = functionName;
	FIELD(newFunction, 1) = classIndex;
	FIELD(newFunction, 2) = argNames;
	FIELD(newFunction, 3) = localNames;
	FIELD(newFunction, 4) = cmdList;
	FIELD(newFunction, 5) = module;

	if (!installFlag) return newFunction;

	if (classObj) { // install method
		OBJ methods = FIELD(classObj, Class_Methods);
		int i = indexOfObject(functionName, methods, 0);
		if (i >= 0) { // replace an existing method
			FIELD(methods, i) = newFunction;
		} else { // add a new method
			FIELD(classObj, Class_Methods) = copyArrayWith(methods, newFunction);
		}
	} else { // install function
		OBJ moduleFunctions = FIELD(module, Module_Functions);
		int i = indexOfObject(functionName, moduleFunctions, 0);
		if (i >= 0) {
			FIELD(moduleFunctions, i) = newFunction;
		} else {
			FIELD(module, Module_Functions) = copyArrayWith(moduleFunctions, newFunction);
		}
	}
	clearCaches();
	methodCacheClearEntry(functionName);
	return newFunction;
}

static inline OBJ lookupMethod(OBJ functionName, OBJ receiver, int hasReceiver, OBJ module) {
	if (hasReceiver) { // look for a matching expander or method
		int classIndex = objClass(receiver);
		OBJ expanders = FIELD(module, Module_Expanders);
		if (expanders && IS_CLASS(expanders, ArrayClass)) {
			char *fName = obj2str(functionName);
			int count = objWords(expanders);
			for (int i = 0; i < count; i++) {
				OBJ fnc = FIELD(expanders, i);
				if (IS_CLASS(fnc, FunctionClass) && (classIndex == obj2int(FIELD(fnc, 1)))) {
					OBJ s = FIELD(fnc, 0);
					if (IS_CLASS(s, StringClass) && (strcmp(obj2str(s), fName) == 0)) return fnc;
				}
			}
		}
		OBJ classObj = classFromIndex(objClass(receiver));
		OBJ methods = FIELD(classObj, Class_Methods);
		int i = indexOfObject(functionName, methods, 0);
		if (i > -1) return FIELD(methods, i);
	}

	// look for a generic function in the current module
	OBJ moduleFuncs = FIELD(module, Module_Functions);
	int i = indexOfObject(functionName, moduleFuncs, 0);
	if (i > -1) return FIELD(moduleFuncs, i);

	if (module != topLevelModule) { // look in top level module
		moduleFuncs = FIELD(topLevelModule, Module_Functions);
		i = indexOfObject(functionName, moduleFuncs, 0);
		if (i > -1) return FIELD(moduleFuncs, i);
	}

	if (module != sessionModule) { // to support development/debugging, look in session module
		moduleFuncs = FIELD(sessionModule, Module_Functions);
		i = indexOfObject(functionName, moduleFuncs, 0);
		if (i > -1) return FIELD(moduleFuncs, i);
	}

	return nilObj;
}

OBJ findMethod(OBJ functionName, OBJ receiver, int hasReceiver, OBJ module) {
	OBJ classIndex = hasReceiver ? int2obj(objClass(receiver)) : 0;
	OBJ result = methodCacheLookup(functionName, classIndex, module);
	if (result != nilObj) return result;
	result = lookupMethod(functionName, receiver, hasReceiver, module);
	if (result != nilObj) {
		methodCacheAdd(functionName, classIndex, module, result);
	}
	return result;
}

// ***** Utilities *****

OBJ copyArrayWith(OBJ arrayObj, OBJ newElement) {
	int count = objWords(arrayObj);
	OBJ newArray = copyObj(arrayObj, count + 1, 1);
	FIELD(newArray, count) = newElement;
	return newArray;
}

int indexOfString(OBJ key, OBJ arrayOfStrings) {
	// Return the index of the first string matching the given key (a string) in an
	// array of strings. Return -1 if there is no match. Skip non-string elements.

	if (!arrayOfStrings) return -1;
	if (NOT_CLASS(key, StringClass)) return -1;

	if (NOT_CLASS(arrayOfStrings, ArrayClass)) {
		printf("Error: indexOfString expected Array or nil; got %s\n", getClassName(key));
		return -1;
	}
	char *k = obj2str(key);
	int count = objWords(arrayOfStrings);
	for (int i = 0; i < count; i++) {
		OBJ s = FIELD(arrayOfStrings, i);
		if (IS_CLASS(s, StringClass) && (strcmp(k, obj2str(s)) == 0)) return i;
	}
	return -1;
}

// ***** System Initialization *****

static void defineVMClass(char *className, int classIndex, int fieldCount, char *fieldNames[]) {
	// Create a class whose index and format is known to the virtual machine and install
	// it at its classIndex in the classes array.
	OBJ newClass = createClass(className, fieldCount, fieldNames);
	FIELD(newClass, Class_ClassIndex) = int2obj(classIndex);
	classes = copyArrayWith(classes, newClass);
	if (objWords(classes) != classIndex) {
		printf("Implementation error: unexpected class index in defineVMClass()\n");
		exit(-1);
	}
}

static OBJ fixAndCollectVMClasses() {
	// Set the module of all VM classes to topLevelModule and return an array
	// containing all the VM classes.
	int count = objWords(classes);
	OBJ result = newArray(count);
	for (int i = 0; i < count; i++) {
		OBJ cls = FIELD(classes, i);
		FIELD(cls, Class_Module) = topLevelModule;
		FIELD(result, i) = cls;
	}
	return result;
}

void initVMClasses() {
	// Define the classes known the GP virtual machine.

	//classes = newArray(0);
	classes = newObj(WeakArrayClass, 0, nilObj);

	defineVMClass("Nil", NilClass, 0, NULL);
	defineVMClass("Boolean", BooleanClass, 0, NULL);
	defineVMClass("Integer", IntegerClass, 0, NULL);
	defineVMClass("Float", FloatClass, 0, NULL);
	defineVMClass("String", StringClass, 0, NULL);
	defineVMClass("Array", ArrayClass, 0, NULL);
	defineVMClass("BinaryData", BinaryDataClass, 0, NULL);
	defineVMClass("ExternalReference", ExternalReferenceClass, 0, NULL);

	char *listFields[] = {"first", "last", "contents"};
	defineVMClass("List", ListClass, 3, listFields);

	char *dictionaryFields[] = {"tally", "keys", "values"};
	defineVMClass("Dictionary", DictionaryClass, 3, dictionaryFields);

	char *cmdAndReporterFields[] = {"primName", "lineno", "fileName", "cache", "cachedClassID", "nextBlock"};
	defineVMClass("Command", CmdClass, CmdFieldCount, cmdAndReporterFields);
	defineVMClass("Reporter", ReporterClass, CmdFieldCount, cmdAndReporterFields);

	char *classFields[] = {"className", "classIndex", "fieldNames", "methods", "comments", "scripts", "module"};
	defineVMClass("Class", ClassClass, 7, classFields);

	char *functionFields[] = {"functionName", "classIndex", "argNames", "localNames", "cmdList", "module"};
	defineVMClass("Function", FunctionClass, 6, functionFields);

	char *moduleFields[] = {"moduleName", "classes", "functions", "expanders", "variableNames", "variables", "exports", "codeHash"};
	defineVMClass("Module", ModuleClass, 8, moduleFields);

	char *taskFields[] = {"stack", "sp", "fp", "mp", "currentBlock", "nextBlock", "result", "tickLimit", "taskToResume",
		"waitReason", "wakeMSecs", "profileArray", "profileIndex", "errorReason"};
	defineVMClass("Task", TaskClass, 14, taskFields);

	defineVMClass("WeakArray", WeakArrayClass, 0, NULL);

	char *largeIntegerFields[] = {"data", "negative"};
	defineVMClass("LargeInteger", LargeIntegerClass, 2, largeIntegerFields);

	// create and initialize topLevelModule
	topLevelModule = sessionModule = currentModule = consoleModule = newModule("TopLevelModule");
	FIELD(topLevelModule, Module_Classes) = fixAndCollectVMClasses();
}
