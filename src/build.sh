#!/usr/bin/env sh
# Build script to build using vasm (http://sun.hasenbraten.de/vasm/) for Atari platforms.
vasmm68k_mot lz4_test.s -devpac -Felf -o lz4_test.o
vlink lz4_test.o -b ataritos -o lz4_test.prg

vasmm68k_mot lzsa_test.s -devpac -Felf -o lzsa_test.o
vlink lzsa_test.o -b ataritos -o lzsa_test.prg

