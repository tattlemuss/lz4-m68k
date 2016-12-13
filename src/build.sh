#!/usr/bin/env sh
# Build script to build using vasm (http://sun.hasenbraten.de/vasm/) for Atari platforms.
vasmm68k_mot test.s -devpac -Felf -o test.o
vlink test.o -b ataritos -o test.prg
