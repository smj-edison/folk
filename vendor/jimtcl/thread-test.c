#include <pthread.h>

#include "jim.h"

void* thread(void *arg)
{
    Jim_Obj *objPtr = (Jim_Obj *)arg;
    Jim_Interp *interp = Jim_CreateInterp();

    for (int i = 0; i < 10000; i++) {
        Jim_Obj *argv[] = {
            Jim_NewStringObj(interp, "incr", -1),
            Jim_ListGetIndex(interp, objPtr, i % 4)
        };

        Jim_EvalObjVector(interp, 2, argv);
    }

    return NULL;
}

int main()
{
    int threadCount = 32;
    pthread_t threads[threadCount];

    Jim_Obj *args[] = {
        Jim_NewStringObjNoInterp("foo", -1),
        Jim_NewStringObjNoInterp("bar", -1),
        Jim_NewStringObjNoInterp("baz", -1),
        Jim_NewStringObjNoInterp("qux", -1),
    };
    Jim_Obj *argsObj = Jim_NewListObjNoInterp(args, sizeof(args)/sizeof(args[0]));

    for (size_t i = 0; i < threadCount; i++) {
        pthread_create(&threads[i], NULL, thread, argsObj);
    }

    for (size_t i = 0; i < threadCount; i++) {
        pthread_join(threads[i], NULL);
    }

    return 0;
}