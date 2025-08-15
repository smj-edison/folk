#ifndef __JIM_PRIV__H
#define __JIM_PRIV__H

#include <stdatomic.h>

#include "jim.h"

typedef struct Jim_Obj {
    char *bytes; /* string representation buffer. NULL = no string repr. */
    const struct Jim_ObjType *typePtr; /* object type. */
    atomic_int refCount; /* reference count */
    int length; /* number of bytes in 'bytes', not including the null term. */
    unsigned long long interpId; /* parent interpreter */
    /* Internal representation union */
    union {
        /* integer number type */
        jim_wide wideValue;
        /* generic integer value (e.g. index, return code) */
        int intValue;
        /* double number type */
        double doubleValue;
        /* Generic pointer */
        void *ptr;
        /* Generic two pointers value */
        struct {
            void *ptr1;
            void *ptr2;
        } twoPtrValue;
        /* Generic pointer, int, int value */
        struct {
            void *ptr;
            int int1;
            int int2;
        } ptrIntValue;
        /* Variable object */
        struct {
            struct Jim_VarVal *vv;
            unsigned long callFrameId; /* for caching */
            int global; /* If the variable name is globally scoped with :: */
        } varValue;
        /* Command object */
        struct {
            struct Jim_Obj *nsObj;
            struct Jim_Cmd *cmdPtr;
            unsigned long procEpoch; /* for caching */
        } cmdValue;
        /* List object */
        struct {
            struct Jim_Obj **ele;    /* Elements vector */
            int len;        /* Length */
            int maxLen;        /* Allocated 'ele' length */
        } listValue;
        /* dict object */
        struct Jim_Dict *dictValue;
        /* String type */
        struct {
            int maxLength;
            int charLength;     /* utf-8 char length. -1 if unknown */
        } strValue;
        /* Reference type */
        struct {
            unsigned long id;
            struct Jim_Reference *refPtr;
        } refValue;
        /* Source type */
        struct {
            struct Jim_Obj *fileNameObj;
            int lineNumber;
        } sourceValue;
        /* Dict substitution type */
        struct {
            struct Jim_Obj *varNameObjPtr;
            struct Jim_Obj *indexObjPtr;
        } dictSubstValue;
        struct {
            int line;
            int argc;
        } scriptLineValue;
    } internalRep;
} Jim_Obj;

/* simple bump allocator for temp objects */
#define JIM_TEMP_LIST_SIZE (512 * 1024)
typedef struct Jim_TempList {
    size_t length;
    Jim_Obj objects[JIM_TEMP_LIST_SIZE];
} Jim_TempList;

#endif
