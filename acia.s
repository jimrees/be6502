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

;;; The # CPU clock ticks to wait after transmit of a byte
;;; since the chip won't tell us anything useful.
;;; At 19,200 this is 520 ticks.
DELAY_CLOCKS = (CLOCKS_PER_SECOND*10)/BAUD_RATE

serial_initialization:
        pha
        stz ACIA_STATUS
        BAUD_TO_DIVISOR BAUD_RATE,lda
        sta ACIA_CTRL
        lda #$0b
        sta ACIA_CMD
        lda ACIA_DATA
        ;; jsr serial_tx_delay

        .if 0
        ;; bit 7 is output for bb'ing transmit
        lda #$80
        sta DDRA                ; initialize direction
        sta PORTA               ; initialize to idle
        .endif

        pla
        rts

        .if 0
DELAY_LOOP_COUNT = ((1000000/BAUD_RATE)*10)/5
        .assert DELAY_LOOP_COUNT < 256

        ;; cycles needed are CLOCKS_PER_SECOND*10/BAUD_RATE
        ;; 520 at 19,200 & 1Mhz.
serial_tx_delay:
        pha
        lda #DELAY_LOOP_COUNT
loop$:
        dec                     ; 2
        bne loop$               ; 3
        pla
        rts
        .endif

serial_tx_char:
        ;; The prior stop time must have already occurred
        ;; Do both, just for yucks
        sta ACIA_DATA

        .if DELAY_CLOCKS < 256
        sei
        DOTIMES nop,(DELAY_CLOCKS-10)/2
        cli
        .else
        .if DELAY_CLOCKS < 65536
        ;; Use TIMER2 in one-shot mode.  Check for completion
        ;; in IFR5
        pha
        phy
        lda #<DELAY_CLOCKS
        ldy #>DELAY_CLOCKS
        sta T2CL
        sty T2CH
        ply
        lda #%00100000          ; IFR5
delayspin$:
        bit IFR
        beq delayspin$
        pla
        .else
        .assert 0
        .endif
        .endif
        rts

        .if 0
        ;; BB Transmit Code from PORTA.  Used when I could not figure out
        ;; why I wasn't getting reliable transmit.  Then I tied CTS
        ;; to ground.  Turns out that's obligatory.
        pha
        phx
        sta tmpchar             ; 3
        .if BAUD_RATE > 4800
        sei
        .endif
        stz PORTA               ; reset down - start bit
        ldx #8                  ; 2
write_bit$:
        jsr bit_delay$
        ror tmpchar
        lda #0
        ror                     ; roll the bit into A
        sta PORTA
        dex
        bne write_bit$
        jsr bit_delay$          ; delay for last data bit
        lda #$80
        sta PORTA
        .if BAUD_RATE > 4800
        cli
        .endif
        jsr bit_delay$          ; delay for stop bit
        plx
        pla
        rts

bit_delay$:
        .if BAUD_RATE == 300
        ;; At 300 baud, we need 3333 usecs
        ;; the ticks are once ever 10,000 so we can't depend on that.
        ;; we actually have to spin
        ;; 3333 / 5 = 667 loops
        ;; = 256 * 2 + 155
        ;; 111 * 6
        phy
        phx
        ldy #2
        ldx #0
loop$:
        dex
        bne loop$
        dey
        bne loop$
        ldx #155
loop2$:
        dex
        bne loop2$
        plx
        ply
        .else
        .if BAUD_RATE == 9600
        ;; 104 usecs
        phx
        ldx #13
loop$:
        dex
        bne loop$
        plx
        .else
        .if BAUD_RATE == 19200
        ;; 52 usecs, 12 for jsr/rts at least
        DOTIMES nop,20
        .endif
        .endif
        .endif
        rts
        .endif
