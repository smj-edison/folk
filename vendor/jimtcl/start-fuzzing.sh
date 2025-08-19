#!/bin/bash

AFL_AUTORESUME=1 afl-fuzz -i fuzzing-corpus -o fuzzing-output -x fuzzing-dictionary.txt -- ./jimsh @@
