.ifndef ACIA_DEFS_H
ACIA_DEFS_H := 1

.include "timer_defs.s"
.include "via_defs.s"

.global ACIA_DATA
.global ACIA_STATUS      ; IRQ DSRB DCDB TXEMPTY RXFULL OVR FERR PERR
.global ACIA_CMD
.global ACIA_CTRL

.global serial_initialization

.macro SET_RTSB_A
        lda #$80
        tsb PORTB
.endmacro

.macro CLEAR_RTSB_A
        lda #$80
        trb PORTB
.endmacro

.endif
