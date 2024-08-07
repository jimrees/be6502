.setcpu "65C02"
.debuginfo +
.feature string_escapes on

.include "bios_defs.s"
.include "acia_defs.s"
.ifdef HARDWARE_FLOW_CONTROL
.include "via_defs.s"
.endif

ACIA_BASE = $4000
ACIA_DATA = ACIA_BASE + $0
ACIA_STATUS = ACIA_BASE + $1 ; IRQ DSRB DCDB TXEMPTY RXFULL OVR FERR PERR
ACIA_CMD = ACIA_BASE + $2
ACIA_CTRL = ACIA_BASE + $3

BAUD_RATE = 19200

;;; The # CPU clock ticks to wait after transmit of a byte
;;; since the chip won't tell us anything useful.
;;; At 19,200 this is 520 ticks.
;;; The IRQ overhead is 100 cycles because the output
;;; serving occurs later.
DELAY_CLOCKS = ((CLOCKS_PER_SECOND*10)/BAUD_RATE - 60)

;;; ACIA_STATUS
;;; [ PMC2 | PME | REM | TIC1 | TIC0 | IRD | DTR |
;;; Parity Mode Control:
;;; 00 Odd parity transmitted/received
;;; 01 Even parity transmitted/received
;;; 10 Mark Parity transmitted - no checks
;;; 11 Space Parity transmitted - no checks
;;; Parity Mode:
;;; 0 - disabled, no bit generated, no checks
;;; 1 - enabled, see above
;;; Receiver Echo Mode
;;; 0 - no echo
;;; 1 - received chars will be transmitted - TIC1,0 must be zero.

;;; Transmitter Interrupt Control
;;; 00 RTSB = High, no interrupts
;;; 01 RTSB = Low, interrupts enabled
;;; 10 RTSB = Low, interrupts disabled
;;; 11 RTSB = Low, interrupts disabled, and transmit BREAK on TxD (?)

;;; So, toggling TIC1 (#%1000) is how I keep transmit interrupts off and still
;;; drive RTSB on/off.  So, I need to run that line.

;;; Receiver Interrupt Request Disabled
;;; 0 IRQB enabled
;;; 1 IRQB disabled

;;; Data Terminal Ready
;;; 0 DTRB high
;;; 1 DTRB low

;;;  we we're using 10 RTSB LOW and DTR LOW (which is irrelevant)

.macro BAUD_TO_DIVISOR B, LOAD
.if B = 50
        LOAD %10000
.elseif B = 75
        LOAD %10001
.elseif B = 150
        LOAD %10101
.elseif B = 300
        LOAD %10110
.elseif B = 60
        LOAD %10111
.elseif B = 1200
        LOAD %11000
.elseif B = 1800
        LOAD %11001
.elseif B = 2400
        LOAD %11010
.elseif B = 3600
        LOAD %11011
.elseif B = 4800
        LOAD %11100
.elseif B = 7200
        LOAD %11101
.elseif B = 9600
        LOAD %11110
.elseif B = 19200
        LOAD %11111
.endif
.endmacro

.macro LOAD_IMMEDIATE_TO_A V
        lda #V
.endmacro

.code
.proc serial_initialization
        pha
        stz ACIA_STATUS
        BAUD_TO_DIVISOR ::BAUD_RATE,LOAD_IMMEDIATE_TO_A
        sta ACIA_CTRL

        lda #$09                ; no parity, no echo, rx interrupts
        sta ACIA_CMD

        lda ACIA_STATUS         ; resets any interrupt conditions

        ;; Initialize TIMER2 functionality for serial output
        lda #<DELAY_CLOCKS
        sta txDelay
        lda #>DELAY_CLOCKS
        sta txDelay+1
        lda #%10100000          ; turn on timer2 interrupts
        sta IER

.ifdef HARDWARE_FLOW_CONTROL
        ;; RTSB goes out PORTB.7
        ;; Enable output on that bit only, and drive it low
        lda #%10000000
        trb PORTB
        tsb DDRB

        ;; CTS comes in from CB1 for positive edge, CB2 for negative edge.
        lda PCR
        and #%00001111
        ora #%00110000
        sta PCR
        lda #%10011000          ; enable both CB1,CB2 interrupts
        sta IER
.endif

        pla
        rts
.endproc
