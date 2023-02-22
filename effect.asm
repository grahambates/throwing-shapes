		incdir	"./include"
		include	"hw.i"

		ifd	BOOT
		dc.b	"DOS",0					; BB_ID - Always has to be DOS\0
		dc.l	$54a6b95c				; BB_CHKSUM - Fix up after assembling
		dc.l	880					; BB_DOSBLOCK - Rootblock location for DOS disks
		else
		; Startup code when testing as exe
		code_c
		xdef	_start
_start:
		include	"PhotonsMiniWrapper1.04!.S"
		endc


********************************************************************************
* Constants:
********************************************************************************

; Palette:
COL00 = $345
COL01 = $3a9
COL02 = $fa6
COL03 = $e75
COL04 = $fed
COL05 = $e9a
COL06 = $bef
COL07 = $fc7

; Display window:
DIW_W = 256
DIW_H = 256
BPLS = 3
SCROLL = 0							; enable playfield scroll
INTERLEAVED = 0
DPF = 0								; enable dual playfield

; Screen buffer:
SCREEN_W = DIW_W
SCREEN_H = DIW_H/2						; bottom half is mirrored

DMA_SET = DMAF_SETCLR!DMAF_MASTER!DMAF_RASTER!DMAF_COPPER!DMAF_BLITTER

C = bltcon0

;-------------------------------------------------------------------------------
; Derived

SCREEN_BW = SCREEN_W/16*2					; byte-width of 1 bitplane line
SCREEN_BPL = SCREEN_BW*SCREEN_H					; bitplane offset (non-interleaved)
SCREEN_SIZE = SCREEN_BW*SCREEN_H*BPLS				; byte size of screen buffer
DIW_BW = DIW_W/16*2
DIW_XSTRT = ($242-DIW_W)/2
DIW_YSTRT = ($158-DIW_H)/2
DIW_XSTOP = DIW_XSTRT+DIW_W
DIW_YSTOP = DIW_YSTRT+DIW_H-1
DIW_STRT = (DIW_YSTRT<<8)!DIW_XSTRT
DIW_STOP = ((DIW_YSTOP-256)<<8)!(DIW_XSTOP-256)
DDF_STRT = ((DIW_XSTRT-17)>>1)&$00fc-SCROLL*8
DDF_STOP = ((DIW_XSTRT-17+(((DIW_W>>4)-1)<<4))>>1)&$00fc
BPLCON0V = BPLS<<(12+DPF)!DPF<<10!$200


********************************************************************************
* Entry point:
********************************************************************************

Demo:
		lea	Vars(pc),a5
		lea	custom+C,a6
; Init copper
		lea	Cop(pc),a4
		move.l	a4,cop1lc-C(a6)
		move.w	#DMA_SET,dmacon-C(a6)
; Load palette
		lea	color00-C(a6),a4
		move.l	#COL00<<16!COL01,(a4)+
		move.l	#COL02<<16!COL03,(a4)+
		move.l	#COL04<<16!COL05,(a4)+
		move.l	#COL06<<16!COL07,(a4)+
; Set up blitter
		ifnd	BOOT
		move.l	#-1,bltafwm-C(a6)
		clr.l	bltamod-C(a6)
		clr.l	bltcmod-C(a6)
		endc

********************************************************************************
; Init audio
;-------------------------------------------------------------------------------
; Set pointer and length for our square wave across all channels:
		lea	Wave(pc),a0
		lea	aud0lch-C(a6),a1
		moveq	#3,d7
.chan:
		move.l	a0,(a1)+				; aud0lch
		move.w	#4,(a1)					; aud0len
		lea	12(a1),a1
		dbf	d7,.chan
		; Only enable DMA for the first two channels for now
		move.w	#DMAF_SETCLR!DMAF_AUD0!DMAF_AUD1!DMAF_MASTER,dmacon-C(a6)


********************************************************************************
MainLoop:
;-------------------------------------------------------------------------------

		move.w	(a5),d5					; d5 = current frame
		add.w	#1,(a5)					; Increment Frame

; Swap buffers:
		movem.l	DrawBuffer-Vars(a5),a0-a1
		exg	a0,a1
		movem.l	a0-a1,DrawBuffer-Vars(a5)
; Set bpl pointers in copper
		ifd	BOOT
		; Skip setting high word for fixed address in bootblock
		lea	CopBplPt+6(pc),a2
		moveq	#BPLS-1,d0
.bpll:		move.w	a1,(a2)
		else
		; Need to write both regs for BSS address in exe
		lea	CopBplPt+2(pc),a2
		moveq	#BPLS-1,d0
.bpll:		move.l	a1,d1
		swap	d1
		move.w	d1,(a2)					; high word of address
		move.w	a1,4(a2)				; low word of address
		endc
		addq.w	#8,a2					; next copper instruction
		lea	SCREEN_BPL(a1),a1			; next bpl ptr
		dbf	d0,.bpll

; Clear screen
		move.l	#$01000000,(a6)
		move.l	a0,bltdpt-C(a6)
		move.w	#SCREEN_H*BPLS*64+SCREEN_BW/2,bltsize-C(a6)

;================================================================================
; Audio:
;--------------------------------------------------------------------------------
; Sound consists of a single pattern per channel. Channels are one octave apart.
; Values in the patterns map to notes in a scale and are then transposed to give
; a chord progression.

		lea	aud0per-C(a6),a1
		lea	Pattern(pc),a2				; Put this in its own register so we can post-increment it
		moveq	#$3,d6					; Constant for AND when unpacking notes - saves a byte compared to immediate value
		moveq	#3,d7					; This will be the iterator for channels, but can use as a constant for now

		move.w	d5,d3					; d3 = chord index
		lsr	#7,d3					;    = (frame/128)&3
		and.w	d7,d3
		move.b	Chords-Vars(a5,d3.w),d3			; d3 = chord value

.chan:
		moveq	#0,d0					; d0 = volume (default off)
		; Find note in pattern
		move.w	d5,d2					; d2 = note index in pattern
		lsr	#3,d2					;    = (frame/8)&7
		and.w	#7,d2
		move.w	(a2)+,d1				; d1 = pattern
		; Notes use 2 bits, so unpack the current value by shifting and masking the pattern wor
		add.w 	d2,d2
		lsr.l	d2,d1					; d1 = note value
		and.l	d6,d1					;    = (pattern>>(index*2))&$f
		beq.s	.setVol					; Skip to volume if note==0 (off)
		moveq	#64,d0					; volume on
		; Lookup and set period for note value
		add.w	d3,d1					; Transpose note value to apply chord
		move.b	Periods-Vars(a5,d1.w),d1		; d1 = period for note
		lsl.w	d7,d1					; shift for octave
		add.w	d1,d1
		move.w	d1,(a1)					; set audxper
		; Set volume
.setVol		move.w	d0,2(a1)				; set audxvol
		lea	16(a1),a1				; next chan registers
		dbf	d7,.chan

;================================================================================
; Effect:
;--------------------------------------------------------------------------------
; The main effect consists of a sequence of shapes generated from frames in a
; 'munching squares' animation.
; We have 3 bitplanes, which progress through the sequence at increasing rates.
; One is filled vertically with the blitter and the other two horizontally.
; The bitplanes are enabled over time, in sync with the audio channels.
; The intersection of the bitplanes is what gives the additional colours/shapes.

;-------------------------------------------------------------------------------
; Toogle between two masks for frame number used in XOR:
; Mask 1:
		; This only includes 'whole' shapes in the sequence
		move.w	#$c0,d6					; d6 = frame mask
; Mask 2:
		btst	#11,d5					; 10 set
		beq.s	.s0					; &&
		btst	#8,d5					; 8 clear
		bne.s	.s0
		; This includes some 'jaggy' intermediate steps
		move.w	#$f0,d6
.s0

; Wait for clear to finish before drawing
		bsr	WaitBlitterC

;-------------------------------------------------------------------------------
; BPL 0
		move.w	d5,d0
		lsr	d0
		move.l	a0,a4					; a4 = draw screen - Draw trashes this!
		bsr.s	Draw
		move.l	a4,a0
		; Vertical Fill
		lea	SCREEN_BW(a0),a1
		move.w	#$d3c,(a6)				; xor, bltcon1 is already 0 from clear
		movem.l	a0/a1,bltapt-C(a6)
		move.l	a1,bltbpt-C(a6)
		move.w	#(SCREEN_H-1)*64+SCREEN_BW/2,bltsize-C(a6)

;-------------------------------------------------------------------------------
; BPL 1
		cmp.w	#1536,d5				; Delay visibility till frame
		blt.s	.s2
		move.w	#DMAF_SETCLR!DMAF_AUD3!DMAF_MASTER,dmacon-C(a6) ; Enable audio channel 3
		move.w	d5,d0
		lea	SCREEN_BW*SCREEN_H(a4),a0
		bsr.s	Draw
.s2

;-------------------------------------------------------------------------------
; BPL 2
		cmp.w	#512,d5					; Delay visibility till frame
		blt.s	.s3
		move.w	#DMAF_SETCLR!DMAF_AUD2!DMAF_MASTER,dmacon-C(a6) ; Enable audio channel 2
		move.w	d5,d0
		add.w	d0,d0
		lea	SCREEN_BW*SCREEN_H*2(a4),a0
		bsr.s	Draw


;-------------------------------------------------------------------------------
; Fill horizontal BPL 1/2
		subq	#2,a0					; Leave in position for descending fill
		bsr	WaitBlitterC
		move.l	#$09f0000a,(a6)				; inclusive fill
		move.l	a0,bltapt-C(a6)
		move.l	a0,bltdpt-C(a6)
		move.w	#SCREEN_H*2*64+SCREEN_BW/2,bltsize-C(a6)
.s3

;================================================================================
; Wait EOF
		bsr	WaitBlitterC
		move.w	#$138,d7
.wait		cmp.b	vhposr-C(a6),d7
		bne.s	.wait

		bra.w	MainLoop
;-------------------------------------------------------------------------------


********************************************************************************
* Routines:
********************************************************************************

WaitBlitterC:
.b:		btst	#DMAB_BLITTER,dmaconr-C(a6)
		bne.s	.b
		rts

********************************************************************************
Draw:
; d0.l - Frame (t)
; d6.l - Frame Mask
; a0.l - Draw buffer
;-------------------------------------------------------------------------------
; Plots pixels using the 'munching squares' x=t^y formula.
; We only want to show key frames in this sequence with distinct shapes, not the
; full animation, so the frame number (t) has a mask applied.
;-------------------------------------------------------------------------------
		and.l	d6,d0					; long to avoid ext after divide
		moveq	#SCREEN_H-1,d7
.l:
		move.w	d7,d1
		eor.w	d0,d1					; x = t ^ y
		; Plot
		move.w	d1,d2					; byte offset
		lsr.w	#3,d2
		move.w	d1,d3					; bit to set
		not.w	d3
		bset.b	d3,(a0,d2.w)
		; Plot inverse (mirror)
		neg.w	d2
		bset.b	d1,SCREEN_BW-1(a0,d2.w)
		lea	SCREEN_BW(a0),a0			; next line
		dbf	d7,.l
		rts


********************************************************************************
* Data
********************************************************************************

;--------------------------------------------------------------------------------
; Main copper list:
Cop:
		dc.w	diwstrt,DIW_STRT
		dc.w	diwstop,DIW_STOP
		dc.w	ddfstrt,DDF_STRT
		dc.w	ddfstop,DDF_STOP
CopBplPt:
		rept	BPLS*2
		dc.w	bpl0pt+REPTN*2,$9
		endr
CopBplCon:
		dc.w	bplcon0,BPLCON0V
		dc.w	bpl1mod,0
		dc.w	bpl2mod,0
		; Mirror screen at 50%
		dc.w	(DIW_YSTRT+SCREEN_H-1)<<8+5,$fffe
		dc.w	bpl1mod,-SCREEN_BW*2
		dc.w	bpl2mod,-SCREEN_BW*2

		dc.l	-2


********************************************************************************
Vars:
********************************************************************************

VBlank		dc.w	0
DrawBuffer:	dc.l	Screen
ViewBuffer:	dc.l	Screen+SCREEN_SIZE

Chords:
		; Chord progression used to transpose note values
		dc.b	0,4,5,2
Periods:
		dc.b	0
		; Only need to store the period values for the key and range we're using
		dc.b	226,214,190,170,160,143,127,113
		even
Pattern:
; We can pack 4 note values per byte
ROW		macro
		dc.b	\8<<6!\7<<4!\6<<2!\5,\4<<6!\3<<4!\2<<2!\1
		endm
		; One 8 step pattern per channel:
		ROW	1,0,0,0,0,0,0,0
		ROW	3,0,3,0,0,0,0,0
		ROW	1,0,0,0,3,0,0,3
		ROW	1,3,0,1,3,0,0,3
Wave:
		; Simple square wave
		dc.b	127,127,127,127,-127,-127,-127,-127

		; Free space!
		dc.w $dead,$beef,$c0de

********************************************************************************
* Memory
********************************************************************************
		ifd	BOOT
; Use a fixed address for screen buffer in bootblock
Screen = $90000
		else
; Use BSS for testing with exe
		bss_c
Screen:		ds.b	SCREEN_SIZE*2
		endc
