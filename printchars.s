.setcpu "65C02"
.debuginfo -
.feature string_escapes on

.include "syscall_defs.s"

.zeropage
        counter = $00

.code
        ;; This steps on X and A registers
        .macro PRINT_STRING location, PRINTER, DELIMITER
        .local start
        .local end
        ldx #0
        start:
        lda location, x
        .if DELIMITER <> 0
        cmp #DELIMITER
        .endif
        beq end
        jsr PRINTER
        inx
        jmp start
        end:
        .endmacro

        .macro PRINT_C_STRING location, PRINTER
        PRINT_STRING location, PRINTER, 0
        .endmacro
        .macro LCD_PRINT_STRING location, DELIMITER
        PRINT_STRING location, lcd_print_character, DELIMITER
        .endmacro
        .macro LCD_PRINT_C_STRING location
        PRINT_STRING location, lcd_print_character, 0
        .endmacro

        ;; 20 - 7e inclusive are the printable ascii chars
        ;; A1 - FF
        lda #$40
        jsr lcd_set_position
        lda #<lcdmessage
        ldy #>lcdmessage
        jsr lcd_print_string

        lda #<serialmessage
        ldy #>serialmessage
        jsr STROUT

        ldy #100
reinit:
        jsr SERIAL_CRLF
        jsr ANYCNTC
        beq gowozstart
        dey
        beq gowozstart

        inc counter
        lda #($40 + 14)
        jsr lcd_set_position
        lda counter
        jsr lcd_print_hex8

        lda #$20
loop:
        cmp #$7f
        beq page2
        jsr CHROUT
        inc
        jmp loop

page2:
        lda #$a1
loop2:
        beq reinit
        jsr CHROUT
        inc
        jmp loop2

gowozstart:
        jmp WOZSTART

lcdmessage:     .asciiz "PRINTCHARS"
serialmessage:     .asciiz "\r\n>> PRINTCHARS <<"
