        .include "via.s"

loop_counter = $11
tick_counter = $12              ; and 13,14,15

value        = $16
mod10        = $18
tmpchar      = $1a

;;; The rom is mapped to start at $8000
        .org $8000

messagelcd:        .asciiz "Startup"
messageserial:     .asciiz "Startup\r\n"

        .include "acia.s"
        .include "lcd.s"
        .include "macros.s"
        .include "decimalprint.s"
        .include "timer.s"
        .include "pre_uart_serial.s"

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

reset:
        jsr timer_initialization
        jsr lcd_initialization
        jsr serial_initialization
        stz loop_counter

loop$:
        lda ACIA_CMD
        jsr print_binary8
        lda ACIA_CTRL
        jsr print_binary8

        lda #$40
        jsr lcd_set_position
        lda ACIA_STATUS
        pha
        jsr print_binary8

        ;; is a character available?
        pla
        and #$08
        beq nochar$

        lda #8
        jsr print_n_spaces
        lda #$49
        jsr lcd_set_position

        lda ACIA_DATA
        pha
        jsr print_character
        pla

        ;; if CR, then print back CRLF.
        cmp #$d
        beq emit_crlf$

        sta ACIA_DATA           ; transmit
        jsr serial_tx_delay
        jmp nochar$

emit_crlf$:
        sta ACIA_DATA           ; send the CR
        jsr serial_tx_delay
        lda #$a                 ; send the LF
        sta ACIA_DATA
        jsr serial_tx_delay

nochar$:
        lda #" "
        jsr print_character
        inc loop_counter
        PRINT_DEC8 loop_counter
        jsr lcd_home
        jmp loop$

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
