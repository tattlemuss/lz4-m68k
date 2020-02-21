; Simple test code for m68k assembler version of lz4 decompressor.
	opt		d+,s+

POISON_VALUE	equ	$55555555

start:
	pea	string(pc)
	move.w	#9,-(a7)
	trap	#1
	addq.l	#6,a7

	move.w	#8,-(a7)			;wait for key
	trap	#1
	addq.l	#2,a7

	lea	compressed_1,a0
	bsr	unpack_wrapper
	move.l	a2,d0
	sub.l	#unpacked,d0			;calculate output length
	lea	output_filename_1,a0
	bsr	write_file

	lea	compressed_2,a0
	bsr	unpack_wrapper
	move.l	a2,d0
	sub.l	#unpacked,d0
	lea	output_filename_2,a0
	bsr	write_file

	lea	compressed_3,a0
	bsr	unpack_wrapper
	move.l	a2,d0
	sub.l	#unpacked,d0
	lea	output_filename_3,a0
	bsr	write_file

	lea	compressed_4,a0
	bsr	unpack_wrapper
	move.l	a2,d0
	sub.l	#unpacked,d0			;calculate output length
	lea	output_filename_4,a0
	bsr	write_file

	move.w	#8,-(a7)			;wait for key
	trap	#1
	addq.l	#2,a7

	clr.w	-(a7)
	trap	#1

; a0 = packed data
unpack_wrapper:
	lea	unpacked,a2
	; Poison registers
	move.l	#POISON_VALUE,d0
	move.l	d0,d1
	move.l	d0,d2
	move.l	d0,d3
	move.l	d0,d4
	move.l	d0,d5
	move.l	d0,d6
	move.l	d0,d7

	move.l	d0,a1
	
	move.l	d0,a3
	move.l	d0,a4
	move.l	d0,a5
	move.l	d0,a6	
	bsr	lzsa_depack_stream

	pea	string2(pc)
	move.w	#9,-(a7)
	trap	#1
	addq.l	#6,a7
	rts

string:		dc.b	'starting depack...',13,10,0
string2:	dc.b	'depack complete',13,10,0
		even

; a0 = filename
; d0 = save length
write_file:
	movem.l	d0/a0,-(a7)
	move.w	#0,-(a7)			;attr
	pea	(a0)				;filename
	move.w	#60,-(a7)			;fcreate
	trap	#1
	addq.l	#8,a7
	move.w	d0,d7				; d7 handle

	movem.l	(a7)+,d0/a0

	move.l	#unpacked,-(a7)			;target buffer
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
		include	'lzsa.s'

		section data
output_filename_1:	dc.b	"bit_v1.dat",0
output_filename_2:	dc.b	"bit_v2.dat",0
output_filename_3:	dc.b	"pg_v1.dat",0
output_filename_4:	dc.b	"pg_v2.dat",0
			even

; Custom test file with a very long match length which failed on some lz4 depackers.
compressed_1:	incbin	'BITBEND.lzsa'
compressed_2:	incbin	'BITBEND.lzsa2'
; This is a version of the Gutenberg Press version of "Pride and Prejudice"
; from http://www.gutenberg.org/cache/epub/42671/pg42671.txt packed with the packer.
compressed_3:	incbin	'pg42671.txt.lzsa'
compressed_4:	incbin	'pg42671.txt.lzsa2'

		section	bss
; Uncompressed output buffer
unpacked:	ds.b	1024*1024

