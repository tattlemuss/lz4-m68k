; depack a lzsa stream containing 1 or more lzsa-1 blocks.
; input a0 - start of compressed frame
; input a2 - start of output buffer
lzsa1_depack_frame:
	addq.l	#3,a0		; skip stream header

.block_loop:
	moveq	#0,d0
	move.b	(a0)+,d0
	lsl.w	#8,d0
	move.b	(a0)+,d0
	ror.w	#8,d0
	bne.s	.run_block
	rts
.run_block:
	addq.l	#1,a0		; TODO needs bit 16 / flags (ignore)
	lea	(a0,d0.w),a4	; a4 = end of block

	moveq	#0,d0		; ensure top bits are clear
;	============ TOKEN ==============
.loop:	
	; order of data:
	; * token: <O|LLL|MMMM>
	; * optional extra literal length
	; * literal values
	; * match offset low
	; * optional match offset high
	; * optional extra encoded match length
	move.b	(a0)+,d0	; d0 = token byte

	move.w	d0,d1
	and.w	#%01110000,d1	; d1 = literal length * 16, 0x0-0x70
	beq.s	.no_literals
	lsr.w	#4,d1		; d1 = literal length * 16, 0x0-0x7
	cmp.b	#7,d1
	bne.s	.copy_literals

;	============ EXTRA LITERAL LENGTH ==============
	add.b	(a0)+,d1	; (we know the original is 7)
	bcc.s	.copy_literals	; 0-248, no carry is set, result 0-255
	beq.s	.copy249

	; carry and not-equal means > 250
	; 250: a second byte follows. The final literals value is 256 + the second byte.
	move.b	(a0)+,d1	; higher byte is 0 from d0
	add.w	#256,d1
	bra.s	.copy_literals
.copy249:
	; 249: a second and third byte follow, forming a little-endian 16-bit value.
	; (note: value is unsigned!)
	; Use 2 bytes as the offset, low-byte first
	move.b	(a0)+,d1
	lsl.w	#8,d1
	move.b	(a0)+,d1
	ror.w	#8,d1		; compensate for little-endian

;	============ LITERAL VALUES ==============
.copy_literals:
	move.b	(a0)+,(a2)+
	subq.w	#1,d1
	bne.s	.copy_literals

.no_literals:
	cmp.l	a0,a4		; end of block?
	beq.s	.block_loop

;	============ MATCH OFFSET LOW ==============
.get_match_offset:
	moveq	#-1,d2		; make it work for offsets bigger than 32K
	btst	#7,d0		; two-bytes match offset?
	beq.s	.small_offset

	; Use 2 bytes as the offset, low-byte first
	; TESTED
	move.b	(a0)+,d2
	lsl.w	#8,d2
	move.b	(a0)+,d2
	ror.w	#8,d2		; compensate for little-endian
	bra.s	.match_offset_done
.small_offset:
	; TESTED
	move.b	(a0)+,d2	; d2 = match offset pt 1
.match_offset_done:
;	============ MATCH LENGTH EXTRA ==============
	; Match Length
	move.w	d0,d1
	and.w	#%00001111,d1	; d1 = match length
	cmp.w	#15,d1
	bne.s	.match_length_done

	move.b	(a0)+,d1	; get next size marker
	cmp.b	#238,d1
	beq.s	.length_2byte

	cmp.b	#239,d1
	bne.s	.length_simple

	; TESTED
	; 239: a second byte follows. The final match length is 256 + the second byte.
	move.b	(a0)+,d1
	add.w	#256-3,d1
	bra.s	.match_length_done

.length_2byte:
	; 238  a second and third byte follow, forming a little-endian 16-bit value. The final encoded match length is that 16-bit value.
	move.b	(a0)+,d1
	lsl.w	#8,d1
	move.b	(a0)+,d1
	ror.w	#8,d1		; compensate for little-endian
	subq.w	#3,d1		; compensate for next -3 in .copy_match
	bra.s	.match_length_done
.length_simple:
	add.w	#15,d1

.match_length_done:

.copy_match:
	addq.w	#3-1,d1		; +3 for constants, -1 for dbf
	; " the encoded match length is the actual match length offset by the minimum, which is 3 bytes"
	lea	(a2,d2.l),a3	; a3 = match source (d2.w already negative)
.copy_match_loop:
	move.b	(a3)+,(a2)+
	dbf	d1,.copy_match_loop
	bra	.loop
.all_done:
	rts