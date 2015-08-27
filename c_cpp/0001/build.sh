#!/bin/sh
set -e

echo "Begin to compile mytest.cpp"
rm -f *.o
rm -f libcommon*
g++ -fPIC -c -o common.o common.cpp
g++ -shared -fPIC -o libcommon.so common.o
#g++ -shared -fPIC -Wl,-soname,libcommon.so -o libcommon.so common.o
#main.c
g++ -Wl,-rpath=./ -o mytest mytest.cpp -L.  -lcommon -lcrypto
echo "Complile mytest.cpp success"


echo "Begin to compile ptmalloc2, but an old version".
cd ptmalloc2
make shared
echo "Complile ptmalloc2 success"
