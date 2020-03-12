; Sample reference depack code for lzsa: https://github.com/emmanuel-marty/lzsa
; Currently only supports the standard stream data, using blocks and forwards-decompression.
; Emphasis is on correctness rather than speed/size.

;------------------------------------------------------------------------------
; Depack a lzsa stream containing 1 or more lzsa-1 blocks.
; No bounds checking is performed.
; input a0 - start of compressed frame
; input a2 - start of output buffer
; return d0 - 0 for successful output, -1 for bad format.
lzsa_depack_stream:
	cmp.b	#$7b,(a0)+
	bne.s	.bad_format
	cmp.b	#$9e,(a0)+
	bne.s	.bad_format

	move.l	a7,a5
	subq.l	#4,a7
	;read encoding type
	;* V: 3 bit code that indicates which block data encoding is used. 0 is LZSA1 and 2 is LZSA2.
	lea	_decode_block_lzsa1(pc),a1	; a1 = block depacker v1
	moveq	#%00100000,d0
	and.b	(a0)+,d0				; get encoding type ($20 == lzsa2)
	beq.s	.block_loop
	lea	_decode_block_lzsa2(pc),a1	; a1 = block depacker v2
.block_loop:

	;# Frame format
	;Each frame contains a 3-bytes length followed by block data that expands to up to 64 Kb of decompressed data.
	;The block data is encoded either as LZSA1 or LZSA2 depending on the V bits of the traits byte in the header.
	;    0    1    2
	; DSZ0 DSZ1 U|DSZ2
	move.b	(a0)+,-(a5)
	move.b	(a0)+,-(a5)
	move.b	(a0)+,-(a5)			;could test here for the copy block flag
	clr.b	-(a5)
	move.l	(a5)+,d0
	beq.s	.all_done			;zero size == end of data

	; Check compression flag. If set, copy raw data.
	btst	#23,d0
	bne.s	.uncompressed_block

	; Assume the other bits are unset, so no need to mask now.
	lea	(a0,d0.w),a4			; a4 = end of block
	jsr	(a1)					; run block depacker
	bra.s	.block_loop
.all_done:
	addq.l	#4,a7
	moveq	#0,d0				; return success
	rts

.uncompressed_block:
	and.l	#$1ffff,d0			; mask size
.copy_block_loop:
	move.b	(a0)+,(a2)+
	subq.l	#1,d0
	bne.s	.copy_block_loop
	bra.s	.block_loop

.bad_format:
	moveq	#-1,d0				; return failure
	rts
;------------------------------------------------------------------------------
; Depack a single forward-compressed LZSA v1 block.
; a0 = block data
; a2 = output
; a4 = block end
_decode_block_lzsa1:
	moveq	#0,d0				; ensure top bits are clear
;	============ TOKEN ==============
.loop:	
	; order of data:
	; * token: <O|LLL|MMMM>
	; * optional extra literal length
	; * literal values
	; * match offset low
	; * optional match offset high
	; * optional extra encoded match length
	move.b	(a0)+,d0			; d0 = token byte

	moveq	#%01110000,d1
	and.w	d0,d1				; d1 = literal length * 16, 0x0-0x70
	beq.s	.no_literals
	lsr.w	#4,d1				; d1 = literal length, 0x0-0x7
	cmp.b	#7,d1
	bne.s	.copy_literals

;	============ EXTRA LITERAL LENGTH ==============
	add.b	(a0)+,d1			; (we know the original is 7)
	bcc.s	.copy_literals			; 0-248, no carry is set, result 0-255
	beq.s	.copy249

	; carry and not-equal means > 250
	; 250: a second byte follows. The final literals value is 256 + the second byte.
	move.b	(a0)+,d1			; higher byte is 0 from d0
	add.w	#256,d1
	bra.s	.copy_literals
.copy249:
	; 249: a second and third byte follow, forming a little-endian 16-bit value.
	; (note: value is unsigned!)
	; Use 2 bytes as the offset, low-byte first
	move.b	(a0)+,-(a5)
	move.b	(a0)+,-(a5)
	move.w	(a5)+,d1

;	============ LITERAL VALUES ==============
.copy_literals:
	subq.w	#1,d1
.copy_loop:
	move.b	(a0)+,(a2)+
	dbf		d1,.copy_loop
.no_literals:
	cmp.l	a0,a4				; end of block?
	bne.s	.get_match_offset
	rts

;	============ MATCH OFFSET LOW ==============
.get_match_offset:
	moveq	#-1,d2				; make it work for offsets bigger than 32K
	btst	#7,d0				; two-bytes match offset?
	beq.s	.small_offset

	; Use 2 bytes as the offset, low-byte first
	move.b	(a0)+,-(a5)
	move.b	(a0)+,-(a5)
	move.w	(a5)+,d2
	bra.s	.match_offset_done
.small_offset:
	move.b	(a0)+,d2			; d2 = match offset pt 1
.match_offset_done:

;	============ MATCH LENGTH EXTRA ==============
	; Match Length
	moveq	#%00001111,d1
	and.w	d0,d1				; d1 = match length
	addq.w	#3,d1				; d1 = match length +3 (3..18)
	cmp.w	#18,d1
	bne.s	.match_length_done

	; d1.w = 15 here
	add.b	(a0)+,d1			; get next size marker
	bcc.s	.match_length_done	; * 0-237: the value is added to the 15 stored in the token.
	beq.s	.match_length_238	; * 238: a second and third byte follow

	; 239: a second byte follows. The final match length is 256 + the second byte.
	move.b	(a0)+,d1
	add.w	#256,d1
	bra.s	.match_length_done

.match_length_238:
	; 238  a second and third byte follow, forming a little-endian 16-bit value. The final encoded match length is that 16-bit value.
	move.b	(a0)+,-(a5)
	move.b	(a0)+,-(a5)
	move.w	(a5)+,d1

.match_length_done:
.copy_match:
	lea		(a2,d2.l),a3		; a3 = match source (d2.w already negative)
	lsr.w	#1,d1
	bcc.s	.even_match_length
	move.b	(a3)+,(a2)+
.even_match_length:
	subq.w	#1,d1				; -1 for dbf
.copy_match_loop:
	move.b	(a3)+,(a2)+
	move.b	(a3)+,(a2)+
	dbf		d1,.copy_match_loop
	bra.s	.loop

;------------------------------------------------------------------------------
; Depack a single forward-compressed LZSA v2 block.
; a0 = block data
; a2 = output
; a4 = block end
_decode_block_lzsa2:
	move.w	#%11100000,d5
	moveq	#-1,d6				; .b = $80
	moveq	#-1,d4				; d4 = last match offset
	moveq	#-1,d3				; d3 = nybble flag (-1 == read again)
	moveq	#0,d0				; ensure top bits are clear
;	============ TOKEN ==============
.loop:	
	; order of data:
	;* token: <XYZ|LL|MMM>
	;* optional extra literal length
	;* literal values
	;* match offset
	;* optional extra encoded match length

	;7 6 5 4 3 2 1 0
	;X Y Z L L M M M
	move.b	(a0)+,d0			; d0 = token byte

	; Length is built in d1
	moveq	#%011000,d1
	and.w	d0,d1				; d1 = literal length * 8
	beq.s	.no_literals
	lsr.w	#3,d1				; d1 = literal length, 0x0-0x3
	cmp.b	#3,d1				; special literal length?
	bne.s	.copy_literals

;	============ EXTRA LITERAL LENGTH ==============
	bsr	.read_nybble
	add.b	d2,d1				; generate literal length
	cmp.b	#15+3,d1

	;0-14: the value is added to the 3 stored in the token, to compose the final literals length.
	bne.s	.copy_literals

	; Ignore d2. Extra byte follows.
	move.b	(a0)+,d1			; read new length
	; assume: * 0-237: 18 is added to the value (3 from the token + 15 from the nibble), to compose the final literals length. 
	add.b	#18,d1				; assume 0-237
	bcc.s	.copy_literals

	;* 239: a second and third byte follow, forming a little-endian 16-bit value.
	move.b	(a0)+,-(a5)
	move.b	(a0)+,-(a5)
	move.w	(a5)+,d1

;	============ LITERAL VALUES ==============
.copy_literals:
	subq.w	#1,d1
.copy_loop:
	move.b	(a0)+,(a2)+
	dbf		d1,.copy_loop

.no_literals:
	cmp.l	a0,a4				; end of block?
	bne.s	.get_match_offset
	rts

;	============ MATCH OFFSET ==============
.get_match_offset:
;The match offset is decoded according to the XYZ bits in the token
;After all this, d0 is shifted up by 3 bits
	move.w	d0,d1
	moveq	#-1,d2				; offset is "naturally" negative
	add.b	d1,d1				; read top bit
	bcs.s	.matchbits_1
.matchbits_0:
	; top bit 0
	add.b	d1,d1				; read top bit
	bcs.s	.matchbits_01

	;00Z 5-bit offset: read a nibble for offset bits 1-4 and use the inverted bit Z of the token as bit 0 of the offset. set bits 5-15 of the offset to 1.
	bsr	.read_nybble			;d2 = nybble
	eor.b	d6,d1				;read reverse of "Z" bit into carry
	add.b	d1,d1				;reversed bit put in X flag
	addx.b	d2,d2				;shift up and combine carry
	or.b	d5,d2				;ensure top bits are set again
	bra.s	.match_offset_done
.matchbits_01:
	;01Z 9-bit offset: read a byte for offset bits 0-7 and use the inverted bit Z for bit 8 of the offset.
	;set bits 9-15 of the offset to 1.
	add.w	d1,d1				;read reverse of "Z" bit into carry
	clr.b	d1
	eor.w	d1,d2				;flip bit 8 if needed
	move.b	(a0)+,d2			;offset bits 0-7
	bra.s	.match_offset_done

.matchbits_1:
	add.b	d1,d1				; read top bit
	bcs.s	.matchbits_11

	;10Z 13-bit offset: read a nibble for offset bits 9-12 and use the inverted bit Z for bit 8 of the offset, 
	;then read a byte for offset bits 0-7. set bits 13-15 of the offset to 1.
	bsr.s	.read_nybble
	eor.b	d6,d1				;read reverse of "Z" bit into carry
	add.b	d1,d1				;reversed bit put in X flag
	addx.b	d2,d2				;shift up and combine carry
	or.b	d5,d2				;ensure top bits are set again
	lsl.w	#8,d2				;move [0:4] up to [12:8]
	move.b	(a0)+,d2			;read bits 0-7
	sub.w	#$200,d2			;undocumented offset -- add 512 byte offset
	bra.s	.match_offset_done

.matchbits_11:
	add.b	d1,d1				; read top bit
	bcs.s	.matchbits_111
	;110 16-bit offset: read a byte for offset bits 8-15, then another byte for offset bits 0-7.
	;CAUTION This is big-endian!
	move.b	(a0)+,d2			; low part
	lsl.w	#8,d2
	move.b	(a0)+,d2			; high part
	bra.s	.match_offset_done

.matchbits_111:
	;111 repeat offset: reuse the offset value of the previous match command.
	move.l	d4,d2

.match_offset_done:
	move.l	d2,d4				; d4 = previous match
	lea	(a2,d2.l),a3			; a3 = match source (d2.w already negative)

;	============ MATCH LENGTH EXTRA ==============
	; Match Length
	moveq	#%0000111,d1		; clear top bits of length
	and.w	d0,d1				; d1 = match length 0-7
	addq.w	#2,d1				; d1 = match length 2-9
	cmp.w	#2+7,d1
	bne.s	.match_length_done

	; read nybble and add
	bsr	.read_nybble
	;* 0-14: the value is added to the 7 stored in the token, and then the minmatch 
	; of 2 is added, to compose the final match length.
	add.b	d2,d1
	cmp.b	#2+7+15,d1
	bne.s	.match_length_done
	;* 15: an extra byte follows
	;If an extra byte follows here, it can have two possible types of value:
	;* 0-231: 24 is added to the value (7 from the token + 15 from the nibble + minmatch of 2), 
	;to compose the final match length.
	add.b	(a0)+,d1
	bcc.s	.match_length_done

	;* 233: a second and third byte follow, forming a little-endian 16-bit value.
	;*The final encoded match length is that 16-bit value.
	move.b	(a0)+,-(a5)			; low part
	move.b	(a0)+,-(a5)			; high part
	move.w	(a5)+,d1

.match_length_done:
.copy_match:
	; "the encoded match length is the actual match length offset by the minimum, which is 2 bytes"
	lsr.w	#1,d1
	bcc.s	.even_match_length
	move.b	(a3)+,(a2)+
.even_match_length:
	subq.w	#1,d1				; -1 for dbf
.copy_match_loop:
	move.b	(a3)+,(a2)+
	move.b	(a3)+,(a2)+
	dbf		d1,.copy_match_loop
	bra		.loop

; returns next nibble in d2
; nybble status in d3; top bit set means "read next byte"
.read_nybble:
	move.b	d3,d2				; copy buffer contents
	bmi.s	.next_byte			; anything in the buffer?
	moveq	#-1,d3				; flag buffer is empty
	rts
.next_byte:
	; buffer is empty, so prime next
	move.b	(a0)+,d2			; fetch
	moveq	#$f,d3
	and.b	d2,d3				; d3 = remaining bottom 4 bits, with "empty" flag cleared
	lsr.b	#4,d2				; d2 = top 4 bits shifted down (result)
	rts
