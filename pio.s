        .include "via.s"

charsprinted = $10
loop_counter = $11
tick_counter = $12              ; and 03, 04, 05

value        = $16
mod10        = $18
tmpchar      = $1a

;;; The rom is mapped to start at $8000
        .org $8000

messagelcd:        .asciiz "Startup"
messageserial:     .asciiz "Startup\r\n"

        .include "lcd.s"
        .include "macros.s"
        .include "decimalprint.s"
        .include "timer.s"
        .include "pre_uart_serial.s"

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

reset:
        ;; Pre-load low 4 ram addresses to be sure we disambiguate from
        ;; ACIA.
        lda #$5a
        sta 0
        lda #$01
        sta 1
        lda #$23
        sta 2
        lda #$45
        sta 3

        jsr timer_initialization
        jsr lcd_initialization
        stz loop_counter

        PRINT_C_STRING messagelcd
        lda #1
        jsr delayseconds

again$:
        jsr run_spinny_serial_demo
        jsr lcd_clear
        jmp again$

nmi:
        rti

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
        .if 0
        ;; 600Mhz clock, bit 0 makes a 300Mhz wave for external clock mode
        pha
        lda PORTA
        eor #1
        sta PORTA
        pla
        .endif
        rti

        ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;; The interrupt & reset vectors
        .org $fffa
        .word nmi
        .word reset
        .word irq
