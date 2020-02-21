; Simple test code for m68k assembler version of lz4 decompressor.
	opt		d+,s+

POISON_VALUE	equ	$55555555

start:
	pea	string(pc)
	move.w	#9,-(a7)
	trap	#1
	addq.l	#6,a7

	lea	compressed,a0
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
	bsr	lz4_depack_frame

	pea	string2(pc)
	move.w	#9,-(a7)
	trap	#1
	addq.l	#6,a7

	; save file
	move.l	a2,d0
	sub.l	#output,d0			;calculate output length
	lea	output,a0
	bsr	write_file

	move.w	#8,-(a7)			;wait for key
	trap	#1
	addq.l	#2,a7

	clr.w	-(a7)
	trap	#1

string:		dc.b	'starting depack...',13,10,0
string2:	dc.b	'depack complete',0
		even

; a0 = save address
; d0 = save length
write_file:
	movem.l	d0/a0,-(a7)
	move.w	#0,-(a7)			;attr
	pea	output_filename			;filename
	move.w	#60,-(a7)			;fcreate
	trap	#1
	addq.l	#8,a7
	move.w	d0,d7				; d7 handle

	movem.l	(a7)+,d0/a0

	move.l	a0,-(a7)			;target buffer
	move.l	d0,-(a7)			;buffer size
	move.w	d7,-(a7)			;handle
	move.w	#$40,-(a7)			;fwrite
	trap	#1	
	lea	12(a7),a7

	move.w	d7,-(a7)			;handle
	move.w	#$3e,-(a7)			;CLOSE
	trap	#1
	addq.l	#4,a7
	moveq	#0,d0
	rts



		include	'lz4.s'

		section data
output_filename:
		dc.b	"output.dat",0
		even

; This is a version of the Gutenberg Press version of "Pride and Prejudice"
; from http://www.gutenberg.org/cache/epub/42671/pg42671.txt packed with
; the stock lz4 executable from https://github.com/lz4/lz4 using
; the "-9" option.
compressed:	incbin	'pg42671.txt.lz4'

		section	bss
; Uncompressed output buffer
output:		ds.b	1024*1024

