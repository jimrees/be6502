ACIA_DATA = $4000
ACIA_STATUS = $4001             ; IRQ DSRB DCDB TXEMPTY RXFULL OVR FERR PERR
ACIA_CMD = $4002
ACIA_CTRL = $4003

        .macro BAUD_TO_DIVISOR,B,LOAD
        .if \B == 50
        \LOAD #%10000
        .else
        .if \B == 75
        \LOAD #%10001
        .else
        .if \B == 150
        \LOAD #%10101
        .else
        .if \B == 300
        \LOAD #%10110
        .else
        .if \B == 600
        \LOAD #%10111
        .else
        .if \B == 1200
        \LOAD #%11000
        .else
        .if \B == 1800
        \LOAD #%11001
        .else
        .if \B == 2400
        \LOAD #%11010
        .else
        .if \B == 3600
        \LOAD #%11011
        .else
        .if \B == 4800
        \LOAD #%11100
        .else
        .if \B == 7200
        \LOAD #%11101
        .else
        .if \B == 9600
        \LOAD #%11110
        .else
        .if \B == 19200
        \LOAD #%11111
        .endif
        .endif
        .endif
        .endif
        .endif
        .endif
        .endif
        .endif
        .endif
        .endif
        .endif
        .endif
        .endif
        .endm

BAUD_RATE = 19200

serial_initialization:
        pha
        stz ACIA_STATUS
        BAUD_TO_DIVISOR BAUD_RATE,lda
        sta ACIA_CTRL
        lda #$0b
        sta ACIA_CMD
        lda ACIA_DATA
        pla
        rts

        ;; cycles needed are CLOCKS_PER_SECOND*10/BAUD_RATE
        ;; 520 at 19,200 & 1Mhz.
serial_tx_delay:
        pha
        lda #((CLOCKS_PER_SECOND/BAUD_RATE)*10)/5
loop$:
        dec                     ; 2
        bne loop$               ; 3
        pla
        rts
