.setcpu "65C02"
.debuginfo +
.feature string_escapes on
.include "bios_defs.s"

.export XAML,XAMH   ; so Xmodem can write here from the loaded address

.ZEROPAGE
XAML:   .res 1      ; Last "opened" location Low
XAMH:   .res 1      ; Last "opened" location High
STL:    .res 1      ; Store address Low
STH:    .res 1      ; Store address High
L:      .res 1      ; Hex value parsing Low
H:      .res 1      ; Hex value parsing High
YSAV:   .res 1      ; Used to see if hex value is given
MODE:   .res 1      ; $00=XAM, $7F=STOR, $AE=BLOCK XAM

.segment "XMBSS"
IN:     ; Input buffer, shared with XModem

.segment "WOZMON"
.export WOZSTART
.import XModem
WOZSTART:
        ;; In case a program forgot to release forced_rtsb
        lda #0
        jsr set_forced_rtsb
        jmp ESCAPE

NOTCR:
        CMP     #$08           ; Backspace key?
        BEQ     BACKSPACE      ; Yes.
        CMP     #$15           ; ^U
        BNE     NOESCAPE         ; Yes.
        JSR     CRCLRRIGHT       ; emits cr & clears right and sets Y to -1
NOESCAPE:
        INY                    ; Advance text index.
        BPL     NEXTCHAR       ; Auto ESC if line longer than 127.

ESCAPE:
        LDA     #$5C           ; "\".
        JSR     ECHO           ; Output it.

GETLINE:
        JSR     SERIAL_CRLF
GETLINE_NOCRLF:
        LDY     #$01           ; Initialize text index.
BACKSPACE:
        DEY                    ; Back up text index.
        BMI     GETLINE_NOCRLF ; Beyond start of line, reinitialize.
        JSR     CLRRIGHT

NEXTCHAR:
        JSR     CHRIN
        BCC     NEXTCHAR
        STA     IN,Y           ; Add to text buffer.
        CMP     #$0D           ; CR?
        BNE     NOTCR          ; No.

        LDY     #$FF           ; Reset text index.
        LDA     #$00           ; For XAM mode.
        TAX                    ; X=0.
        ;;
        ;; Explanation - 00 for XAM mode, 7 & 6 not set
        ;;               74 for STOR is (':' << 1), 7 clear, 6 set.
        ;;               B8 for BLOK is ('.' << 2), 7 set, 6 set.
SETBLOCK:
        ASL
SETSTOR:
        ASL                    ; Leaves $7B if setting STOR mode.
        STA     MODE           ; $00 = XAM, $74 = STOR, $B8 = BLOK XAM.
BLSKIP:
        INY                    ; Advance text index.
NEXTITEM:
        LDA     IN,Y           ; Get character.
        CMP     #$0D           ; CR?
        BEQ     GETLINE        ; Yes, done this line.
        CMP     #'.'           ; "."?
        BCC     BLSKIP         ; Skip delimiter.
        BEQ     SETBLOCK       ; Set BLOCK XAM mode.
        CMP     #':'           ; ":"?
        BEQ     SETSTOR        ; Yes, set STOR mode.
        CMP     #'R'           ; "R"?
        BEQ     WOZRUN         ; Yes, run user program.
        CMP     #'X'           ; "X"?
        BNE     @SKIPX
        JMP     XModem         ; Run the Xmodem receiver
@SKIPX:
        STX     L              ; $00 -> L.
        STX     H              ;    and H.
        STY     YSAV           ; Save Y for comparison

NEXTHEX:
        LDA     IN,Y           ; Get character for hex test.
        EOR     #$30           ; Map digits to $0-9.
        CMP     #$0A           ; Digit?
        BCC     DIG            ; Yes.
        ORA     #$20           ; if lower case, map to upper case
        ADC     #$88           ; Map letter "A"-"F" to $FA-FF.
        CMP     #$FA           ; Hex letter?
        BCC     NOTHEX         ; No, character not hex.
DIG:
        LDX     #$04           ; Shift count.
HEXSHIFT:
        ASL     L              ; Shift high L bit into H
        ROL     H              ; Rotate into MSD's.
        DEX                    ; Done 4 shifts?
        BNE     HEXSHIFT       ; No, loop.
        AND     #$0F           ; Mask A (for the $FA-$FF case)
        TSB     L              ; OR into L
        INY                    ; Advance text index.
        BNE     NEXTHEX        ; Always taken. Check next character for hex.

NOTHEX:
        CPY     YSAV           ; Check if L, H empty (no hex digits).
        BEQ     ESCAPE         ; Yes, generate ESC sequence.

        BIT     MODE           ; Test MODE byte.
        BVC     NOTSTOR        ; B6=0 is STOR, 1 is XAM and BLOCK XAM.

        LDA     L              ; LSD's of hex data.
        STA     (STL,X)        ; Store current 'store index'.
        INC     STL            ; Increment store index.
        BNE     NEXTITEM       ; Get next item (no carry).
        INC     STH            ; Add carry to 'store index' high order.
TONEXTITEM:
        JMP     NEXTITEM       ; Get next command item.

WOZRUN:
        JMP     (XAML)         ; Run at current XAM index.

NOTSTOR:
        BMI     XAMNEXT        ; B7 = 0 for XAM, 1 for BLOCK XAM.

        LDX     #$02           ; Byte count.
SETADR:
        LDA     L-1,X          ; Copy hex data to
        STA     STL-1,X        ;  'store index'.
        STA     XAML-1,X       ; And to 'XAM index'.
        DEX                    ; Next of 2 bytes.
        BNE     SETADR         ; Loop unless X = 0.

NXTPRNT:
        BNE     PRDATA         ; NE means no address to print.
        JSR     SERIAL_CRLF

        ;; Check for ^C
        JSR     ANYCNTC
        beq     LWOZSTART

        LDA     XAMH           ; 'Examine index' high-order byte.
        JSR     PRBYTE         ; Output it in hex format.
        LDA     XAML           ; Low-order 'examine index' byte.
        JSR     PRBYTE         ; Output it in hex format.
        LDA     #$3A           ; ":".
        JSR     ECHO           ; Output it.

PRDATA:
        LDA     #$20           ; Blank.
        JSR     ECHO           ; Output it.
        LDA     (XAML,X)       ; Get data byte at 'examine index'.
        JSR     PRBYTE         ; Output it in hex format.
XAMNEXT:
        STX     MODE           ; 0 -> MODE (XAM mode).
        LDA     XAML
        CMP     L              ; Compare 'examine index' to hex data.
        LDA     XAMH
        SBC     H
        BCS     TONEXTITEM     ; Not less, so no more data to output.

        INC     XAML
        BNE     MOD16CHK       ; Increment 'examine index'.
        INC     XAMH

MOD16CHK:
        LDA     XAML           ; Check low-order 'examine index' byte
        AND     #$0F           ; For MOD 16 = 0
        BPL     NXTPRNT        ; Always taken.

PRBYTE:
        PHA                    ; Save A for LSD.
        LSR
        LSR
        LSR                    ; MSD to LSD position.
        LSR
        JSR     PRHEX          ; Output hex digit.
        PLA                    ; Restore A.

PRHEX:
        AND     #$0F           ; Mask LSD for hex print.
        ORA     #$30           ; Add "0".
        CMP     #$3A           ; Digit?
        BCC     ECHOLOCAL      ; Yes, output it.
        ADC     #$06           ; Add offset for letter.

ECHO = CHROUT

ECHOLOCAL:
        JMP     ECHO
LWOZSTART:
        JMP     WOZSTART
