.setcpu "65C02"
.debuginfo -
.feature string_escapes on

.include "syscall_defs.s"
        ALLSYSCALL .global

.zeropage
counter:

.code
        ;; 20 - 7e inclusive are the printable ascii chars
        ;; A1 - FF
        stz counter
        lda #$40
        jsr lcd_set_position
        lda #<lcdmessage
        ldy #>lcdmessage
        jsr lcd_print_string

        lda #<serialmessage
        ldy #>serialmessage
        jsr STROUT

reinit:
        jsr SERIAL_CRLF
        jsr ANYCNTC
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
serialmessage:  .asciiz "\r\n>> PRINTCHARS <<"
