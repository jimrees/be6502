        .org $8000

XAML           = $24            ; Last "opened" location Low
XAMH           = $25            ; Last "opened" location High
STL            = $26            ; Store address Low
STH            = $27            ; Store address High
L              = $28            ; Hex value parsing Low
H              = $29            ; Hex value parsing High
YSAV           = $2A            ; Used to see if hex value is given
MODE           = $2B            ; $00=XAM, $7F=STOR, $AE=BLOCK XAM
charsprinted   = $32
tick_counter   = $33            ; & 4,5,6
value          = $37
IN             = $0200          ; Input buffer

        .macro SERIAL_PRINT_C_STRING,location
        PRINT_STRING \location,echo,0
        .endm

        .org $f000
        .include "via.s"
        .include "macros.s"
        .include "timer.s"
        .include "lcd.s"
        .include "acia.s"

message:        .asciiz "    -WozMon-    "

reset:
        jsr timer_initialization
        jsr lcd_initialization
        jsr serial_initialization
restart:
        jsr lcd_clear
        LCD_PRINT_C_STRING message
        SERIAL_PRINT_C_STRING message
        lda #13
        jsr echo

        lda #$1b                ; starting state, escape
notcr:
        CMP     #$08           ; Backspace key?
        BEQ     backspace      ; Yes.
        CMP     #$1B           ; ESC?
        BEQ     escape         ; Yes.
        cmp     #$03           ; Control-C?
        beq     restart
        INY                    ; Advance text index.
        BPL     nextchar       ; Auto ESC if line longer than 127.

escape:
        LDA     #$5C           ; "\".
        JSR     echo           ; Output it.

getline:
        LDA     #$0D           ; Send CR
        JSR     echo

        LDY     #$01           ; Initialize text index.
backspace:
        DEY                    ; Back up text index.
        BMI     getline        ; Beyond start of line, reinitialize.

nextchar:
        LDA     ACIA_STATUS    ; Check status.
        AND     #$08           ; Key ready?
        BEQ     nextchar       ; Loop until ready.
        LDA     ACIA_DATA      ; Load character. B7 will be '0'.
        STA     IN,Y           ; Add to text buffer.
        JSR     echo           ; Display character.
        CMP     #$0D           ; CR?
        BNE     notcr          ; No.

        jsr lcd_clear
        LCD_PRINT_STRING IN,$0d

        LDY     #$FF           ; Reset text index.
        LDA     #$00           ; For XAM mode.
        TAX                    ; X=0.
        ;;
        ;; Explanation - 00 for XAM mode, 7 & 6 not set
        ;;               74 for STOR is (':' << 1), 7 clear, 6 set.
        ;;               B8 for BLOK is ('.' << 2), 7 set, 6 set.
setblock:
        ASL
setstor:
        ASL                    ; Leaves $7B if setting STOR mode.
        STA     MODE           ; $00 = XAM, $74 = STOR, $B8 = BLOK XAM.
blskip:
        INY                    ; Advance text index.
nextitem:
        LDA     IN,Y           ; Get character.
        CMP     #$0D           ; CR?
        BEQ     getline        ; Yes, done this line.
        CMP     #$2E           ; "."?
        BCC     blskip         ; Skip delimiter.
        BEQ     setblock       ; Set BLOCK XAM mode.
        CMP     #$3A           ; ":"?
        BEQ     setstor        ; Yes, set STOR mode.
        CMP     #$52           ; "R"?
        BEQ     run            ; Yes, run user program.
        STX     L              ; $00 -> L.
        STX     H              ;    and H.
        STY     YSAV           ; Save Y for comparison

nexthex:
        LDA     IN,Y           ; Get character for hex test.
        EOR     #$30           ; Map digits to $0-9.
        CMP     #$0A           ; Digit?
        BCC     dig            ; Yes.
        ORA     #$20           ; if lower case, map to upper case
        ADC     #$88           ; Map letter "A"-"F" to $FA-FF.
        CMP     #$FA           ; Hex letter?
        BCC     nothex         ; No, character not hex.
dig:
        LDX     #$04           ; Shift count.
hexshift:
        ASL     L              ; Shift high L bit into H
        ROL     H              ; Rotate into MSD's.
        DEX                    ; Done 4 shifts?
        BNE     hexshift       ; No, loop.
        AND     #$0F           ; Mask A (for the $FA-$FF case)
        TSB     L              ; OR into L
        INY                    ; Advance text index.
        BNE     nexthex        ; Always taken. Check next character for hex.

nothex:
        CPY     YSAV           ; Check if L, H empty (no hex digits).
        BEQ     escape         ; Yes, generate ESC sequence.

        BIT     MODE           ; Test MODE byte.
        BVC     notstor        ; B6=0 is STOR, 1 is XAM and BLOCK XAM.

        LDA     L              ; LSD's of hex data.
        STA     (STL,X)        ; Store current 'store index'.
        INC     STL            ; Increment store index.
        BNE     nextitem       ; Get next item (no carry).
        INC     STH            ; Add carry to 'store index' high order.
tonextitem:
        JMP     nextitem       ; Get next command item.

run:
        JMP     (XAML)         ; Run at current XAM index.

notstor:
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
        LDA     #$0D           ; CR.
        JSR     echo           ; Output it.
        LDA     XAMH           ; 'Examine index' high-order byte.
        JSR     PRBYTE         ; Output it in hex format.
        LDA     XAML           ; Low-order 'examine index' byte.
        JSR     PRBYTE         ; Output it in hex format.
        LDA     #$3A           ; ":".
        JSR     echo           ; Output it.

PRDATA:
        LDA     #$20           ; Blank.
        JSR     echo           ; Output it.
        LDA     (XAML,X)       ; Get data byte at 'examine index'.
        JSR     PRBYTE         ; Output it in hex format.
XAMNEXT:
        STX     MODE           ; 0 -> MODE (XAM mode).
        LDA     XAML
        CMP     L              ; Compare 'examine index' to hex data.
        LDA     XAMH
        SBC     H
        BCS     tonextitem     ; Not less, so no more data to output.

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
        BCC     echolocal      ; Yes, output it.
        ADC     #$06           ; Add offset for letter.

echo = serial_tx_char

echolocal:
        jmp serial_tx_char

irq:
        bit T1CL                ; clear condition
        inc tick_counter        ; increment lsbyte
        bne timer1_done$        ; roll up as needed
        inc tick_counter+1
        bne timer1_done$
        inc tick_counter+2
        bne timer1_done$
        inc tick_counter+3
timer1_done$:
        rti

  .org $FFFA

        .word   $0F00          ; NMI vector
        .word   reset          ; reset vector
        .word   irq
