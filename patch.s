; Modifying Battle Garegga to run properly on clone bareggabl hardware
; Michael Moffitt 2018
; mikejmoffitt@gmail.com
;
; The "1945 II (nidai)" hack of Battle Garegga comes on a bootleg PCB that
; approximates the Battle Garegga hardware fairly well:
;   * full sound hardware (Z80, YM2151 clone, OKI6295 clone, NMK banking)
;   * CPU clocks match original hardware CPU clocks
;   * FPGAs used to replicate sprite and tilemap hardware
;   * text overlay engine done in discrete logic
;
; The bootleg hardware only has a few flaws, and they can almost entirely be
; mitigated in software:
;   * Sprites seem to update one frame before the background
;   * Graphic gp9001 planes seem to have arbitrary static x/y offsets
;   * Sprites are a few pixels "low" (to the left, in hardware)
;   * Overlay text layer is a few pixels too "high" (to the right, in hardware)
;     and it does not scroll at all.
;
; 1) Correcting the sprite lead / background "lag":
;
; Nearly all bootleg boards that use FPGAs to recreate sprite logic from this
; era do so by implementing a basic double-buffered framebuffer blitter, and
; some glue logic to interface with the original game's sprite registers
; and layout information. Sometimes this comes with a vblank time penalty,
; slowing down the game (M-STREET Street Fighter 2 bootleg, for example).
; This board doesn't have such a penalty. While the sprites seem to be double
; buffered, causing a frame of delay, the original Garegga hardware has *two*
; frames of sprite delay.
;
; In Garegga, the software delays background scroll updates by two frames in
; order to compensate for the sprite delay, so as to ensure that sprites and
; backdrop planes aren't wobbling out of sync with each other. However, as
; this bootleg by some miracle has one frame less of sprite delay, the sprites
; are actually *leading* the backdrop by one frame, as the BG update delay
; mechanism is still intact in the game.
;
; This is kind of a flaw, as it is an innacuracy, but this can be rectified
; in software by simply removing one stage of the backdrop scroll update
; delay. This is implemented using a short FIFO in RAM; all we have to do is
; skip one stage of the FIFO.
;
; 2) Correcting the layer X/Y offsets
;
; Another common trait of '90s arcade bootleg boards is that the tile engine
; seems to have each layer slightly offset from where they should be. For some
; games this is not so noticeable, but for any game that expects alignment
; between the layers and combines them, this can be problematic (again, look
; at M-STREET). Following the trend, this board does this too. Why this seems
; so common is a mystery, but I suspect that the tile engine spends time
; filling a line buffer by going through layers sequentially, and a timing
; mistake results in this offset.
;
; I don't know if the original Garegga board's GP9001 chip *also* has some
; layer offsets like this, but the convenient fact is that Garegga holds a
; table in ROM containing static X and Y offsets, which are applied to the
; layer scroll values. As a result, all we have to do is tweak these values
; to correct the layer offsets.
;
; There is a snag, and that is that that the sprite layer doesn't obey the
; scroll register writes, at least on this bootleg hardware. So, that leads
; us to part three:
;
; 3) Correcting the sprite X/Y offsets
; Since the bootleg GP9001 (and maybe the real thing) doesn't respond to the
; strange sprite scroll registers, we've got to fix this one by actually
; modifying the positions of the sprites we put down. This game was
; programmed by sane people, so almost all manipulation of sprite RAM is
; done through re-use of routines, so the changelist for this one is
; actually very small. It comes with a small performance penalty, but
; this is hard to avoid.
;
; More information on the sprite RAM is below.
;
; 4) Correcting the text layer offsets and scrolling
; Unfortunately, this one's not too exciting. The text layer is completely
; static on the bootleg hardware, and is off by a few pixels towards the top
; of the screen. The solution here is to "deal with it". The only graphical
; error this introduces is on the title screen, where the text doesn't scroll
; in with the planes like it should, and the planes' propellers are in the
; wrong spots slightly. In-game, the slight offest is not jarring, and is not
; problematic enough to warrant an in-depth fix. This one can't be fixed in
; software, so the solution would be to RE the discrete logic / PAL circuit
; used to generate this tile plane and offset the starting Hcount value by
; a little bit. It's more work than it's worth, so this remains the largest
; bug with the bgareggabl hardware.
;
; A hotfix is in place to just make the title screen not scroll downwards,
; and instead have it remain static down below. This isn't as fun as the
; original design, but it looks stupid on the bootleg hardware to have a
; bunch of floating propellers descend onto some stationary aircraft.
;
; Writing to the text scroll MMIO makes garbage appear on the left side
; of the screen, so writes to it have been disabled.
;
; SPRITE RAM CACHE:
; Sprites are set up in memory starting at $100530 in four word structures.
; They correspond directly with the gp9001's sprite registers, but are not
; represented in the same order.
; Remember that this is a vertical game, so X and Y appear to be swapped, with
; (0, 0) being the bottom-left corner of the monitor.
; Sprites are offset such that position 0 puts them 8 pixels off-screen.
; Positions are signed with two's complement.
;
; Offset $0 - X
; ---- ---- ---- xxxx = Sprite X size ((n-1) * 8px)
; ---- ---- -??? ---- = Unknown
; xxxx xxxx x--- ---- = X position
;
; Offset $1 - Y
; ---- ---- ---- xxxx = Sprite Y size ((n-1) * 8px)
; ---- ---- -??? ---- = Unknown
; xxxx xxxx x--- ---- = Y position
; 
; Offsets $2 and $3 correspond with GP9001 sprite RAM entries $0 and $1.
; We are only concerned with X and Y position so this is enough information.
;
; Sprite data is written at:
; $01439C - during test menu sprite check
; $0042D8 - in-game, title screen, character select
	CPU 68000
	PADDING OFF
	ORG		$000000
	BINCLUDE	"prg.orig"

; Plane offsets to add to the scroll base table

; Enable this section to have it act like the boot board does
;SC_BG_X =  0
;SC_BG_Y = -2 ; 2 ; used for the clouds in stage 2?
;SC_FG_X =  4 ; -4
;SC_FG_Y = -2 ; 2 ; used for the land in stage 2
;SC_TX_X =  8 ;-8
;SC_TX_Y = -2 ; 2 ; used for the lake in stage 2
;SC_SP_X =  4 ;-4
;SC_SP_Y =  0
;TXT_X   =  -2; 2

; This is for static shifting of all elements at once.
STATIC_X = 0
STATIC_Y = 0

; Enable this section to fix the game running on boot hardware
SC_BG_X =  0
SC_BG_Y =  2 ; used for the clouds in stage 2?
SC_FG_X =  -4
SC_FG_Y =  2 ; used for the land in stage 2
SC_TX_X = -8
SC_TX_Y =  2 ; used for the lake in stage 2
SC_SP_X =  0
SC_SP_Y =  0 ; Not usable, not respected by gp9001 boot and maybe real thing
TXT_X   =  2 ; gp9001 boot does not respect this.

; Sprite offsets
SPRITE_X = 4
SPRITE_Y = 0

SCR_TABLE = $1000CE
GP9001_SCROLL_BASE = $580
TXT_SCROLL_BASE = $5A0

; Skip Raizing! screen
skip_raizing_screen:
	ORG $000336
;	bra.s	$00033C

; Force region to Japan
region_force_nippon:
	ORG $012D18
	andi.w #$000C, d0

; Skip the checksum screen
skip_cksum_screen:
	ORG $0002BA
;	nop
;	nop

; Skip the license screen
skip_license_screen:
	ORG $000310
;	nop
;	nop
;	nop

; Show "OK" after calculating ROM checksum
cksum_show_ok:
	ORG $015C32
	bra.w	$015B08

; On a failed checksum, still continue past the checksum screen
skip_bad_cksum:
	ORG $015A08
	rts

; Disable text overlay line scroll
txt_scrl_disable:
	ORG $001DAE
	rts

	ORG $001DC6
	rts

	ORG $001DF8
	rts

; Disable scrolling on the title screen
title_scroll_disable:
	ORG $00F732
	move.w	#$0000, ($10C9EA).l

	ORG $00F7B4
	move.l	#$00000000, ($1000C0).l

; Modifying the scroll base table to compensate for shortcomings in the
; bootleg tile engine.
scroll_base_table:
	ORG GP9001_SCROLL_BASE
	; BG X
	dc.w	$0000
	dc.w	$01D6 + SC_BG_X + STATIC_X
	; BG Y
	dc.w	$0001
	dc.w	$01EF + SC_BG_Y + STATIC_Y
	; FG X
	dc.w	$0002
	dc.w	$01D8 + SC_FG_X + STATIC_X
	; FG Y
	dc.w	$0003
	dc.w	$01EF + SC_FG_Y + STATIC_Y
	; TX X
	dc.w	$0004
	dc.w	$01DA + SC_TX_X + STATIC_X
	; TX Y
	dc.w	$0005
	dc.w	$01EF + SC_TX_Y + STATIC_Y
; Sprites verified not to work on the bootleg hardware.
	; SP X
;	dc.w	$0006
;	dc.w	$01D4 + SC_SP_X + STATIC_X
	; SP Y
;	dc.w	$0007
;	dc.w	$01F7 + SC_SP_Y + STATIC_Y

; Modifies the sprite routine to offset sprites' X and Y by the adjustment amount

sprite_fix_hook:
	ORG $0042C0
	bra.w sprite_fix_shift

; Putting this tiny sprite hack bit into some empty memory
	ORG $008388
sprite_fix_shift:
	IF SPRITE_X
	addi.w	#(SPRITE_X << 7), d0
	ENDIF
	IF STATIC_Y
	addi.w	#(SPRITE_Y << 7), d1
	ENDIF
	andi.b	#$80, d0 ; These were andi.w #$FF80
	andi.b	#$80, d1

	; Rather than jump back to the old copy loop, it's duplicated here to
	; save a second control flow change
.copy_top:
	; Sprite metadata
	move.w	(a0)+, d7	; Write meta-data to sprite RAM
	bpl.b	.end		; Abort if this sprite isn't visible
	add.w	d5, d7		; Get metadata params (flip, palette, etc)
	move.w	d7, (a1)+	; Commit to sprite table

	; Sprite vram tile ID
	move.w	(a0)+, (a1)+	; Copy sprite #, etc directly

	; Sprite position data
	move.w	d0, d7		; Put X position into D7 high 9 bits
	add.w	(a0)+, d7	; Put sprite X size and mapping X offset
	move.w	d7, (a1)+	; Commit to sprite table

	; Position data II (Y)
	move.w	d1, d7		; Put Y position into D7 high 9 bits
	add.w	(a0)+, d7	; Put sprite Y size and mapping Y offset
	move.w	d7, (a1)+	; Commit to sprite table
	dbf	d2, .copy_top
	bne.s	.copy_top
.end:
	rts

; This would fix the position of the overlay text, but it is fixed in place
; on the battle garegga boot hardware, and this does not work.
text_scroll_offset:
	;ORG TXT_SCROLL_BASE
	;dc.w	$1D4 +  TXT_X

; TODO: Remove text layer scroll, it's fucking up the left side of the screen
remove_text_scrolling:


	; There is a set of small 3-state queues held in RAM for scroll
	; updates. The sprite hardware has two frames of lag (one from
	; sprite DMA, one from the double-buffered framebuffer). As a
	; workaround Battle Garegga (and probably all games with gp9001)
	; delays updates to the backdrop scroll offests.
	; At $1000CE is a table of short FIFOS used to let scroll updates
	; happen two frames after being set.
	; Where $04 is the final value sent to the scroll registers, and
	; $00 is the scroll value given from the game, the delay is done
	; like so:
	; $02 --> $04
	; $00 --> $02

; Removes one frame of backdrop update delay.
bg_scroll_1f_delay:
	ORG $006280
	lea	(SCR_TABLE).l, a0
	move.w	$00(a0), $04(a0) ; Normally the game would copy $02 --> $04
	move.w	$08(a0), $0C(a0)
	move.w	$10(a0), $14(a0)
	move.w	$18(a0), $1C(a0)
	move.w	$20(a0), $24(a0)
	move.w	$28(a0), $2C(a0)
	move.b	2(a4), 4(a4) ; Normally 3 --> 4
	bra.s	$0062DA ; Skip over what would be the second delay iteration
