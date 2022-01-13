INCLUDE "hardware.inc"
INCLUDE "esp.inc"

xCOORD EQU $C003
yCOORD EQU $C004

SECTION "Interupt VBLANK", ROM0[$40]
jp VBlankHandler

SECTION "Interupt STAT", ROM0[$48]
        jp STATHandler

SECTION "Header", ROM0[$100]

EntryPoint:
        di
        jp Start

REPT $150 - $104
    db 0
ENDR

SECTION "Sprite Data", ROM0
Sprites:
.Sprite1
        ;; Remember that this number format hides the weirdness of tile data.
        ;; `31333332 is the same as %11111110 10111111. This is not obvious.
        dw `31333332
        dw `30303030
        dw `03030303
        dw `03030303
        dw `03030303
        dw `03030303
        dw `03030303
        dw `33333333
        
.AtSymbol
        dw `00000000
        dw `00333000
        dw `03000300
        dw `30033030
        dw `30303030
        dw `30030300
        dw `03000000
        dw `00333000
.Heart
        ;; Colour 2 is used to toggle filled/empty heart.
        dw `33333333
        dw `30030033
        dw `02202203
        dw `02222203
        dw `02222203
        dw `30222033
        dw `33020333
        dw `33303333

.ArrowR
        dw `33333333
        dw `00113333
        dw `00111333
        dw `00111133
        dw `00111113
        dw `00111133
        dw `00111333
        dw `00113333

SECTION "Game code", ROM0

Start:
.waitVBlank
        ld a, [rLY]
        cp 144 ; Check if the LCD is past VBlank
        jr c, .waitVBlank
        xor a ; ld a, 0 
        ld [rLCDC], a
        
        ld hl, $8000
        ld de, Sprites.ArrowR
        ld b, 16
        call memcpy

        call clearOAM

        ;; Load OAM data for sprite.
        ld hl, $FE00            ; OBJ space
        ld a, 151               ; y position
        ld [hli], a
        ld a, 110               ; x position
        ld [hli], a
        ld a, 0
        ld [hli], a
        ld a, 0
        ld [hli], a

        ;; Set sprite palette 0.
        ld hl, rOBP0
        ld [hl], %11100000

        ;; copy the font
        ld hl, $9000
        ld de, FontTiles
        ld bc, FontTilesEnd - FontTiles
.copyFont
        ld a, [de] ; Grab 1 byte from the source
        ld [hli], a ; Place it at the destination, incrementing hl
        inc de ; Move to next byte
        dec bc ; Decrement count
        ld a, b ; Check if count is 0, since `dec bc` doesn't update flags
        or c
        jr nz, .copyFont

        ld hl, $9C00
        xor a
        ld d, 20
        ld e, 18
.setupMap
        ld [hli], a
        inc a
        ;jp z, .doNormalStuff
        dec d
        jr nz, .setupMap
        ld bc, 12
        add hl, bc
        ld d, 20
        dec e
        jr nz, .setupMap

.doNormalStuff
        ld hl, $9400
        ld de, Sprites.AtSymbol
        ld b, 16
        call memcpy

        ;; copy connecting string
        ld hl, $98E4 ; This will print the string roughly in the center
        ld de, ConnectingString

.copyString
        ld a, [de]
        ld [hli], a
        inc de
        and a ; Check if the byte we just copied is zero
        jr nz, .copyString ; Continue if it's not

        ; place window
        ld hl, $ff4b
        ld [hl], 7
        ld hl, $ff4a
        ld [hl], 135

        ; Set some display registers

.startish
        ; Set background and window pallet
        ld a, %11100100
        ld [rBGP], a
        
        ; Scroll to 0,0
        xor a ; ld a, 0
        ld [rSCY], a
        ld [rSCX], a

        ;; Turn on LCD with sprites off and background on.
        ld a, %11000001
        ld [rLCDC], a


        ;; Turn on interupts for vblank.
        ;; My vblank interupt handler is just RETI.
        ;; This lets me use HALT to wait for vblank.
        ld hl, rIE
        ld [hl], IEF_VBLANK
        ei

        ld hl, $98EF
        ld d, 20

IF (DEF(EMU))
        jp .toSkipESP
ENDC
.waitConnect
        ;; Check if the ESP is ready once a frame.
        ;; Blink the last period in the "Connecting.." string every 20 frames.
        EspReadyToA
        and 1
        jr z, .connected
        halt ; wait for vblank
        dec d
        jr nz, .waitConnect
        ld d, 20
        ld a, [hl]
        ;; $2E is the "." character in the tilemap. Doing an xor will change the
        ;; value to either 0 or $2E. The 0 tile is a blank tile. 
        xor $2E
        ld [hl], a

        jr .waitConnect

.connected
        ld hl, $98E4
        ld de, ConnectedString
.copyConnectedString
        ld a, [de]
        ld [hli], a
        inc de
        and a ; Check if the byte we just copied is zero
        jr nz, .copyConnectedString
        ;; ready is 0

        FromEspToA ; ignore the value
 :      ; loop until ready is 1
        EspReadyToA
        and 1
        jr z, :-

        ;; wait 60 frames.
        ;; This is to keep "Conected!!" on the screen long enough to be read.
        ld d, 60
:
        halt
        dec d
        jr nz, :-

        ;; Display "Loading.." and blink the last "." while waiting for ready.
        ld hl, $98E4
        ld de, LoadingString
        call HaltAndCopyString

        ld d, 20
        ld hl, $98EE
:
        EspReadyToA
        and 1
        jr z, :+  ; 0 here is ready
        halt 
        dec d
        jr nz, :-
        ld d, 20
        ld a, [hl]
        xor $2E
        ld [hl], a
        jr :-
:       ;; done waiting

        ld hl, $98E4
        ld de, Strings.Clear
        call HaltAndCopyString
        halt 

.toSkipESP
        di
        ld a, IEF_LCDC;IEF_VBLANK | IEF_LCDC
        ;ld a, IEF_LCDC |IEF_VBLANK
        ld [rIE], a
        ld a, 56;95;60  ; change in STATHandler if changed
        ld [rLYC], a
        ld a, %11011001
        ld [rLCDC], a
        ld a, STATF_MODE10
        ld [rSTAT], a
        ei

        ld e, 0 ;; this is the status bit right now... I hope
.loadTiles

        ld hl, $8000
        ;ld bc, 5760/128
        ld b, 5760/32
        ;ld bc, $0081
        ;ld de, 0
:
;ld a, [rSTAT]
;and 3
REPT 32
        FromEspToA
        nop
        nop 
        nop
        nop
        nop 
        nop
        nop
        nop 
        nop
        nop
        nop 
        nop
        nop
        nop 
        nop
        nop
        ld [hli], a
ENDR

;ld a, P1F_GET_DPAD
;;ld a, %00101111
;ld [rP1], a
;ld a, [$FF80]
;ld c, a
;ld a, [rP1]
;and c
;ld c, a
;ld a, [rP1]
;and c
;ld c, a
;ld a, [rP1]
;and c
;ld [$FF80], a
;;ld a, %00011111
;ld a, P1F_GET_BTN
;ld [rP1], a
;ld a, [$FF81]
;ld c, a
;ld a, [rP1]
;and c
;ld c, a
;ld a, [rP1]
;and c
;ld c, a
;ld a, [rP1]
;and c
;ld [$FF81], a
;ld a, P1F_GET_NONE

        dec b
        jp nz, :-
        ;dec bc
        ;ld a, b
        ;or c
        ;jp nz, :-
        ;ld c, $FF
        ;dec b
        ;jr nz, :-

.doneLoading
        ;halt 

        ld hl, rLY
        ld a, 144
:
        cp [hl]
        jr nz, :-
        
        ;ld a, [$FF80]
        ;swap a
        ;and %11110000
        ;ld b, a
        ;ld a, [$FF81]
        ;and %00001111
        ;or b
        ;cpl

        ld a, 0
        ToEspFromA
:
        ;jp :-
        ;jp .loadTiles
IF (DEF(EMU))
        ld hl, $A000
        inc [hl]
        jr :+
ENDC
        EspReadyToA
        and 1
        ld b, a
        cp e
        jr z, :-
        ld e, b

        ld a, P1F_GET_DPAD
        ld [rP1], a
        ld a, [rP1]
        ld a, [rP1]
        ld a, [rP1]
        swap a
        and %11110000
        ld b, a
        ld a, P1F_GET_BTN
        ld [rP1], a
        ld a, [rP1]
        ld a, [rP1]
        ld a, [rP1]
        and %00001111
        or b
        cpl
        ToEspFromA
:

        EspReadyToA
        and 1
        ld b, a
        cp e
        jr z, :-
        ld e, b



:
        ld hl, rLY
        ld a, 8
:
        cp [hl]
        jr nz, :-
        jp .loadTiles
;9813 9820


gameloop:       
.gameloop

        ;; Read d-pad.
        ld HL, rP1
        ld a, %00100000
        ld [hl], a
        ld c, [hl]
        ld [hl], $FF
        ;; check left
        ld a, c
        and %00000010
        jr nz, .checkRight

.checkRight

        ld a, c
        and %00000001
        jr nz, .checkA

        ;; Turn the Object/sprite layer on.
        ;; This displays the arrow sprite.
        ;; Once it's visible there's no way to turn it off right now. This is a
        ;; lazy way to get very minimal UI.
        ld a, %11100011
        ld [rLCDC], a

.checkA

        ;; Read action buttons
        ld HL, rP1
        ld a, %00010000
        ld a, %11011111
        ld [hl], a
        ld c, [hl]
        ld [hl], $FF

        ;; check A
        ld a, c
        and %00000001
        jr nz, .AisNotPressed
        ;; A is pressed.
        ;; Check if already pressed
        ld hl, $C000
        ld a, [hl]
        cp 0
        jp nz, gameloop

        ;; wasn't already pressed
        ;; mark as pressed
        ld [hl], 1

        ;; do stuff

        ld a, "L"
        ToEspFromA  ; The ESP ignores this.
:
        halt 
        EspReadyToA
        and 1
        jp nz, :-

        FromEspToA
        halt 
        ld a, %11000100
        ld [rBGP], a
        jp gameloop

.AisNotPressed

        ;; mark A as not pressed first
        ld hl, $C000
        ld [hl], 0

        jp gameloop


VBlankHandler:
        reti

STATHandler:
        push af
        ldh a, [rSTAT]
        bit 2, a
        jr z, :+

        ldh a, [rLCDC]
        ;xor %00010000
        ;and %11101111
        res 4, a
        ldh [rLCDC], a
:
        ld a, [rLY]
        cp 144
        jr nz, :+
        ldh a, [rLCDC]
        set 4, a
        ldh [rLCDC], a
:


        ;; wait till hblank
        ldh a, [rSTAT]
        ; only check bit 1 since modes 2 -> 3 -> 0
        ; so bit 1 is the important one.
        bit 1, a 
        jr nz, :-




        pop af
        reti 

        ;push af
        ;ld a, IEF_VBLANK
        ;ld [rIE], a
        ;pop af
        ;ei 
        ;halt 
        ;ret
        
        push af
        ldh a, [rSTAT]
        bit 3, a ; if the hblank stat interupt was set we're in hblank
        jr z, :+
        ;; switch to OAM interupt
        ld a, STATF_MODE10
        ldh [rSTAT], a
        pop af
        reti

:       ; not hblank so is OAM search
        ldh a, [rSTAT]
        bit 2, a
        jr z, :+

        ; switch bg tiles
        ldh a, [rLCDC]
        and %11101111
        ldh [rLCDC], a
:
        ;; switch to hblank interupt
        ld a, STATF_MODE00
        ldh [rSTAT], a

        pop af
        ei
        halt
        reti 
        ;; no reti because the hblank interupt will reti 


SECTION "Font", ROM0

        FontTiles:
        INCBIN "font.chr"
        FontTilesEnd:


SECTION "copy string function", ROM0
HaltAndCopyString:
        halt
CopyString:
        ;; copy a 0 terminated string
        ;; from de to hl
        ;; doesn't check screen size
        ld a, [de]
        ld [hli], a
        inc de
        and a
        jr nz, CopyString
        ret

SECTION "Connecting string", ROM0

ConnectingString:
        db "Connecting..", 0

SECTION "Connected string", rom0

ConnectedString:
        db "Connected!!!", 0

SECTION "strings", ROM0

LoadingString:
Strings:
        db "  Loading.. ", 0
.Twitter
        db "  Twitter!  ", 0
.Clear
        db "            ", 0

SECTION "tile data", ROM0
TileData:
        ;INCBIN "tile_data.bin"
TileDataEnd: