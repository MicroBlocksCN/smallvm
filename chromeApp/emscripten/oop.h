// oop.h - Object-oriented programming support
// John Maloney, November 2013

// Class Operations

OBJ addClass(OBJ classObj);
OBJ defineClass(OBJ className, OBJ module);
void addField(OBJ classObj, OBJ fieldName);
char *getClassName(OBJ obj);

// Class Lookup

OBJ classFromIndex(int classIndex);
OBJ classFromNameInModule(OBJ className, OBJ module);
OBJ classFromNameInModuleNoDelegate(OBJ className, OBJ module);

// Instance Operations

OBJ newInstance(OBJ classOrClassName, int indexableCount);
int getFieldIndex(OBJ obj, OBJ fieldIndexOrName);

// Method Operations

OBJ addMethod(OBJ classObj, OBJ functionName, OBJ argNames, OBJ module, OBJ cmdList, int installFlag);
OBJ findMethod(OBJ functionName, OBJ receiver, int hasReceiver, OBJ module);

// Module Fields

#define Module_ModuleName 0
#define Module_Classes 1
#define Module_Functions 2
#define Module_Expanders 3
#define Module_VariableNames 4
#define Module_Variables 5
#define Module_Exports 6
#define Module_CodeHash 7

// Module Operations

OBJ newModule(char *moduleName);
void addModuleVariable(OBJ module, OBJ varName, OBJ value);

// Utilities

OBJ copyArrayWith(OBJ arrayObj, OBJ newElement);
int indexOfString(OBJ key, OBJ arrayOfStrings);

// System Initialization

extern int readingLibrary;
void initVMClasses();
