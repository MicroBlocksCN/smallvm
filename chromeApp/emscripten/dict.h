// dict.h - Dictionary operations for the virtual machine
// John Maloney, February 2014

OBJ newDict(int capacity);
OBJ dictAt(OBJ dict, OBJ k);
OBJ dictAtPut(OBJ dict, OBJ k, OBJ newValue);
int dictCount(OBJ dict);
gp_boolean dictHasKey(OBJ dict, OBJ k);
