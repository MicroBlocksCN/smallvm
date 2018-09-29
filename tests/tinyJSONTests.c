#include <stdio.h>
#include <string.h>
#include "tinyJSON.h"

static void printThing(char *p) {
	if (!p) { printf("(NULL pointer)\n"); return; }

	char s[100];
	int type = tjr_type(p);
	switch (type) {
	case tjr_End:
		printf("End\n");
		break;
	case tjr_Array:
		printf("[%d elements]\n", tjr_count(p));
		break;
	case tjr_Object:
		printf("{%d properties}\n", tjr_count(p));
		break;
	case tjr_Number:
		printf("%d\n", tjr_readInteger(p));
		break;
	case tjr_String:
		tjr_readStringInto(p, s, sizeof(s));
		printf("\"%s\"\n", s);
		break;
	case tjr_True:
		printf("true\n");
		break;
	case tjr_False:
		printf("false\n");
		break;
	case tjr_Null:
		printf("null\n");
		break;
	default:
		printf("Error (type = %d)\n", type);
	}
}

static void test1() {
	char json[] = "{ \"shape\": { \"points\": [ { \"x\": 1, \"y\": 2 } { \"x\": 3 \"y\": 4 } ]}}";

	printf("\nTesting tjr_atPath():\n");
 	printThing(tjr_atPath(json, "shape"));
 	printThing(tjr_atPath(json, "shape.points"));
 	printThing(tjr_atPath(json, "shape.points.1"));
 	printThing(tjr_atPath(json, "shape.points.1.x"));
 	printThing(tjr_atPath(json, "shape.points.1.y"));
}

static void test2() {
	// test atIndex

	char json[] = " [ { \"x\": 1, \"y\": 2 }, { \"x\": 3, \"y\": 4 } ]";
	printf("\nAccess %d elements using tjr_atIndex():\n", tjr_count(json));
	for (int i = -1; i < 3; i++) {
		printf("  %d: ", i);
		printThing(tjr_atIndex(json, i));
	}
}

static void test3() {
	// test array enumeration

	char json[] = " [ 1, 2 , 3, null, true, false, 123 , 456.789, -321 , -987e10 , -, 42 ] ";
	printf("\nArray with %d elements:\n", tjr_count(json));
	int type, n = 1;
	char *p = json;
	while (1) {
		p = tjr_nextElement(p);
		if (!p) return;
		printf("  %d: ", n);
		printThing(p);
		n++;
	}
}

static void test4() {
	// test object enumeration

	char json[] = " {\"foo\": 1\"bar\":true , \"alakazameroo\" : false } 18 ";
	printf("\nObject with %d properties:\n", tjr_count(json));
	char fieldName[20];
	char *p = json;
	while (1) {
		p = tjr_nextProperty(p, fieldName, sizeof(fieldName));
		if (!p) return;
		printf("  %s: ", fieldName);
		printThing(p);
	}
}

int main() {
 	test1();
 	test2();
 	test3();
 	test4();
	return 0;
}
