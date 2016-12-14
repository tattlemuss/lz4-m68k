; Simple test code for m68k assembler version of lz4 decompressor.
	opt		d+,s+

POISON_VALUE	equ	$55555555

start:
	pea	string(pc)
	move.w	#9,-(a7)
	trap	#1
	addq.l	#6,a7

	lea	compressed,a0
	lea	compressed_end,a1
	lea	output,a2
	
	; Poison registers
	move.l	#POISON_VALUE,d0
	move.l	d0,d1
	move.l	d0,d2
	move.l	d0,d3
	move.l	d0,d4
	move.l	d0,d5
	move.l	d0,d6
	move.l	d0,d7
	move.l	d0,a3
	move.l	d0,a4
	move.l	d0,a5
	move.l	d0,a6	
	bsr	lz4_depack

	pea	string2(pc)
	move.w	#9,-(a7)
	trap	#1
	addq.l	#6,a7

	move.w	#8,-(a7)	;wait for key
	trap	#1
	addq.l	#2,a7

	clr.w	-(a7)
	trap	#1

string:		dc.b	'starting depack...',13,10,0
string2:	dc.b	'depack complete',0
		even

		include	'lz4.s'

		section data
; This is a version of the Gutenberg Press version of "Pride and Prejudice"
; from http://www.gutenberg.org/cache/epub/42671/pg42671.txt packed with
; the stock lz4 executable from https://github.com/lz4/lz4 using
; the "-9" option.
; The data start and end were found by inspection.
compressed	equ		*+11
		incbin	'pg42671.txt.lz4'
compressed_end	equ		*-8

		section	bss
; Uncompressed output buffer
output:		ds.b	1024*1024

