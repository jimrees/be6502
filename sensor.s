        .include "via.s"

;;; For simplicity, this is a full page.  More complex code could
;;; reduce it to 4 slots probably, if needed.  If reduced, it could
;;; be moved to the zeropage as well.
ca2_buffer = $0200

tick_counter = $00              ; and 3 more bytes too
charsprinted = $04
loop_counter = $05

sensorbytes      = $06          ; SIX bytes, the last byte says we're done
integral_rh      = $06
decimal_rh       = $07
integral_temp    = $08
decimal_temp     = $09
sensor_checksum  = $0a
value            = $0b
mod10            = $0d
ca2_producer     = $0f

last_down_edge_lsb = $0b

DHT11_PIN = 7
DHT11_MASK = (1<<DHT11_PIN)

;;; Display control bits - where they live on PORTB
E  = %01000000
RW = %00100000
RS = %00010000

;;; The rom is mapped to start at $8000
        .org $8000

;;; String to display on LCD.  Note padding to 40 characters - this
;;; is how to wrap around to the second row.
message:        asciiz "Temperature & RH                        "
timeout_message asciiz "TIMEOUT "
spaces:         asciiz "                   "
loopchars:      .byte "|/-",$a4

        .include "lcd.s"
        .include "macros.s"
        .include "decimalprint.s"

;;;
;;; writes to sensorbytes
;;; sets A to:
;;;    #0 for success
;;;    #-1 for timeout
;;;    #+1 for checksum error
;;; The N & Z bits are set accordingly.
;;;
dht11_readRawData:
        ;; Preload each byte with 1
        ;; As bits comes in, they are rol'ed in from the right.
        ;; When the carry bit gets set as a result of this roll,
        ;; that tells us we're done with this byte.
        lda #1
        sta sensorbytes
        sta sensorbytes+1
        sta sensorbytes+2
        sta sensorbytes+3
        sta sensorbytes+4

        ;; Initiate the request with a long down pulse (>= 18ms)
        lda #DHT11_MASK         ; pin.mode = OUTPUT
        sta DDRA                ; so ONLY that pin is outout
        stz PORTA               ; assert LOW (1 downedge)
        lda #3
        jsr delayticks

        ;; Reset buffer index to 0.  This should be safe while we're
        ;; holding the line down.
        stz ca2_producer
        stz DDRA                ; release and let the pull up happen

        ;; wait for ca2_producer to become non-zero
        ldy #2           ; # tries
dhresponse_wait$:
        wai
        lda ca2_producer
        bne dhresponse_edge_detected$
        dey
        bne dhresponse_wait$
        lda #-1                 ; sets the N-bit, signals timeout
        rts

dhresponse_edge_detected$:
        ldy #1                    ; index! set to 1
        ;;
        ;; The 80/80 cycle from DHT.  We could add time-out logic
        ;; here too, but we already got the initial response.
        ;; Anything that would lock up this loop is rare enough to
        ;; merit the big RESET button.
        ;;
        .macro DHT11_WAIT_UNTIL_DOWNEDGE
        ;; pre-condition Y is the current consumer buffer index
        ifrwait\@$:
        cpy ca2_producer
        bne out\@$
        wai
        jmp ifrwait\@$
        out\@$:
        .endm

        DHT11_WAIT_UNTIL_DOWNEDGE ; when DHT's first bit is initiated
        lda ca2_buffer+1
        iny

        ldx #-5                 ; initialize outer loop counter
byteloop$:
bitloop$:
        DHT11_WAIT_UNTIL_DOWNEDGE
        sec
        sbc ca2_buffer,y
        cmp #99
        lda ca2_buffer,y        ; for next pass
        iny                     ; 'consume'
        rol sensorbytes+5,x     ; negative index works in zeropage
        bcc bitloop$            ; see if that 1 has reached C yet
        inx
        bmi byteloop$           ; while still negative, keep looping

        ;; testing - if jumper is set high, it flips bit 0 of the checksum
        lda PORTA
        and #1
        eor sensor_checksum
        sta sensor_checksum

        ;; confirm checksum
        lda sensorbytes
        clc
        adc sensorbytes+1
        clc
        adc sensorbytes+2
        clc
        adc sensorbytes+3
        cmp sensor_checksum
        bne ck_bad_checksum$
        lda #0
        rts
ck_bad_checksum$
        lda #1                 ; clears N & Z, signalling checksum error
        rts

timer_initialization:
        ;; Set up repeat mode on a 10,000 frequency
        ;; 9998 = 270e
        stz tick_counter
        stz tick_counter+1
        stz tick_counter+2
        stz tick_counter+3
        lda #%01000000          ; enable continuous mode for timer1
        sta ACR
        lda #$0e
        sta T1CL
        lda #$27
        sta T1CH
        lda #%11000000          ; turn on timer1 interrupts
        sta IER
        cli                     ; stop masking interrupts
        rts

        ;; this waits until the tick_counter == the target value
        ;; The count of ticks to wait is in A
        ;; Since interrupts are required to get us to the target,
        ;; we might as well use wai in the loop and reduce power
        ;; usage.
delayticks:
        clc
        adc tick_counter
delay_wait$:
        wai
        cmp tick_counter
        bne delay_wait$
        rts

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

reset:
        jsr timer_initialization
        jsr lcd_initialization

        ;; Also trigger CA2 downedges, in independent mode
        stz loop_counter
        lda #%00000010
        sta PCR
        lda #%10000001
        sta IER                 ; enable CA2 interrupts
        lda #%00000001
        sta IFR                 ; clear any current condition

        ;; Extra pre-loop delay
        lda #"."
        jsr print_character

        lda #55
        jsr delayticks

        lda #"."
        jsr print_character

        lda #55
        jsr delayticks

        lda #"."
        jsr print_character
loop$:
        lda #180
        jsr delayticks

        jsr lcd_home
        PRINT_C_STRING message

        jsr dht11_readRawData
        bmi timeout_error$
        php                     ; save status

        ;; our data should be there:
        PRINT_DEC8 integral_temp
        lda #"."
        jsr print_character
        PRINT_DEC8 decimal_temp
        lda #" "
        jsr print_character
        PRINT_DEC8 integral_rh
        lda #" "
        jsr print_character
        ;; Skip the fraction for humidity
        ;; lda #"."
        ;; jsr print_character
        ;; PRINT_DEC8 decimal_rh

        plp                     ; restore status from dht11_readRawData call
        beq show_loop_char$     ; if Z is set, then all is well.

        lda #"E"                ; Report checksum failure
        jsr print_character
        PRINT_DEC8 sensor_checksum
        lda #" "
        jsr print_character
        jmp show_loop_char$

timeout_error$:
        PRINT_C_STRING timeout_message

show_loop_char$:
        lda loop_counter
        inc
        sta loop_counter
        and #3
        tax
        lda loopchars,x
        jsr print_character

        PRINT_C_STRING spaces

        jmp loop$

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        .align 8                ; avoid page boundary crossings in irq
nmi:
        rti

irq:
        pha                     ; A is needed in all paths
        lda #%00000001          ; CA2
        bit IFR                 ; has CA2 triggered?
        beq ca2_done$           ; if not skip down

;;; Code for CA2
        sta IFR                 ; clear the condition
        lda T1CL                ; grab the timestamp
        phx                     ; Need another register
        ldx ca2_producer        ; get the next index
        sta ca2_buffer,x        ; store stamp in buffer
        inx                     ; increment and write-back the index
        stx ca2_producer
        plx                     ; restore x
ca2_done$:

        lda #%01000000          ; TIMER1
        bit IFR                 ; has the timer triggered?
        beq timer1_done$        ; if not skip down

;;; Code for TIMER1
        bit T1CL                ; clear condition
        inc tick_counter        ; increment lsbyte
        bne timer1_done$      ; roll up as needed
        inc tick_counter+1
        bne timer1_done$
        inc tick_counter+2
        bne timer1_done$
        inc tick_counter+3
timer1_done$:

        pla                     ; restore
        rti

        ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;; The interrupt & reset vectors
        .org $fffa
        .word nmi
        .word reset
        .word irq
