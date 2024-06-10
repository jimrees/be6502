        .include "via.s"

;;; Pre-allocate storage for decimal formatter
value = $0200
mod10 = $0202

tick_counter = $00              ; and 3 more bytes too
charsprinted = $04
ca2_counter = $05

sensorbytes      = $06          ; SIX bytes, the last byte says we're done
integral_rh      = $06
decimal_rh       = $07
integral_temp    = $08
decimal_temp     = $09
sensor_checksum  = $0a
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
spinchars:      .byte "|/-\"

        .include "lcd.s"
        .include "macros.s"
        .include "decimalprint.s"

        .macro DHT11_SPIN_UNTIL_DOWNEDGE
        lda #%00000001
        ifrspin\@$ :
        bit IFR
        beq ifrspin\@$
        sta IFR
        .endm

        ;; writes to sensorbytes
dht11_readRawData:
        ;; Preload with 1 each byte
        lda #1
        sta sensorbytes
        sta sensorbytes+1
        sta sensorbytes+2
        sta sensorbytes+3
        sta sensorbytes+4

        ;; Initiation
        lda #DHT11_MASK         ; pin.mode = OUTPUT
        sta DDRA
        stz PORTA               ; assert LOW (1 downedge)
        ;; Delay >= 18ms before releasing the pin
        lda #3
        jsr delayticks

        ;; block interrupts so timing isn't screwed up
        lda #%00000001
        sta IFR                 ; clear the downedge condition
        stz DDRA                ; release and let the pull up happen
        DHT11_SPIN_UNTIL_DOWNEDGE ; when DHT takes over
        DHT11_SPIN_UNTIL_DOWNEDGE ; when DHT's first bit is initiated
        ldy T1CL                ; sample the clock, and stash it
        sty last_down_edge_lsb

        ldx #-5
byteloop$:
bitloop$:
        DHT11_SPIN_UNTIL_DOWNEDGE
        tya                     ; put prior time in A reg
        ldy T1CL                ; sample the new time
        sty last_down_edge_lsb  ; save it
        sec
        sbc last_down_edge_lsb
        cmp #99
        rol sensorbytes+5,x
        bcc bitloop$
        inx
        bmi byteloop$
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
delayticks:
        clc
        adc tick_counter
delay_spin$:
        cmp tick_counter
        bne delay_spin$
        rts

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

reset:
        jsr timer_initialization
        jsr lcd_initialization

        ;; Also trigger CA2 downedges, in independent mode
        stz ca2_counter
        lda #%00000010
        sta PCR

        ;; Extra pre-loop delay
        lda #"<"
        jsr print_character

        lda #110
        jsr delayticks

        lda #">"
        jsr print_character

loop$:
        ;; The chip needs time between pollings
        lda #180
        jsr delayticks

        jsr lcd_home
        PRINT_C_STRING message

        jsr dht11_readRawData

        ;; our data should be there:
        PRINT_DEC8 integral_temp
        lda #"."
        jsr print_character
        PRINT_DEC8 decimal_temp
        lda #" "
        jsr print_character
        PRINT_DEC8 integral_rh
        ;; Skip the fraction for humidity
        ;; lda #"."
        ;; jsr print_character
        ;; PRINT_DEC8 decimal_rh
        lda #" "
        jsr print_character

        lda sensorbytes
        clc
        adc sensorbytes+1
        clc
        adc sensorbytes+2
        clc
        adc sensorbytes+3

        cmp sensor_checksum
        beq ck_ok$

        lda #"E"
        jsr print_character
        PRINT_DEC8 sensor_checksum
        jmp fin$

ck_ok$:
        lda #"C"
        jsr print_character

        lda ca2_counter
        inc
        sta ca2_counter
        and #3
        tax
        lda spinchars,x
        jsr print_character

fin$:
        jmp loop$

        .align 8                ; avoid page boundary crossings in irq
nmi:
        rti

irq:
        bit T1CL                ; clear condition
        inc tick_counter        ; increment lsbyte
        bne tick_inc_done$      ; roll up as needed
        inc tick_counter+1
        bne tick_inc_done$
        inc tick_counter+2
        bne tick_inc_done$
        inc tick_counter+3
tick_inc_done$:
        rti

        ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;; The interrupt & reset vectors
        .org $fffa
        .word nmi
        .word reset
        .word irq
