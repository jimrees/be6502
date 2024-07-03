.ifndef ACIA_DEFS_H
ACIA_DEFS_H := 1

.include "timer_defs.s"

ACIA_DATA = $4000
ACIA_STATUS = $4001      ; IRQ DSRB DCDB TXEMPTY RXFULL OVR FERR PERR
ACIA_CMD = $4002
ACIA_CTRL = $4003

BAUD_RATE = 19200

;;; The # CPU clock ticks to wait after transmit of a byte
;;; since the chip won't tell us anything useful.
;;; At 19,200 this is 520 ticks.
;;; The IRQ overhead is 100 cycles because the output
;;; serving occurs later.
DELAY_CLOCKS = ((CLOCKS_PER_SECOND*10)/BAUD_RATE - 95)
.endif
