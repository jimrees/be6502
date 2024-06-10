        .include "via.s"

;;; Pre-allocate storage for decimal formatter
value = $0200
mod10 = $0202
sensorbytes = $020a             ; SIX bytes, the last byte says we're done

integral_rh      = $020a
decimal_rh       = $020b
integral_temp    = $020c
decimal_temp     = $020d
sensor_checksum  = $020e
sensor_populated = $020f        ; when this becomes non-zero, we're done

tick_counter = $00              ; and 3 more bytes too
charsprinted = $04
ca2_counter = $05

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

        .include "lcd.s"
        .include "macros.s"
        .include "decimalprint.s"

        ;; the count of ticks is in A
        ;; this waits until the tick_counter == the target value
delayticks:
        clc
        adc tick_counter
delay_spin$:
        cmp tick_counter
        bne delay_spin$
        rts

        .macro DHT11_SPIN_WHILE_HIGH
        SPIN_WHILE_BIT_SET PORTA, DHT11_PIN
        .endm

        .macro DHT11_SPIN_WHILE_LOW
        SPIN_WHILE_BIT_CLEAR PORTA, DHT11_PIN
        .endm

        ;; writes to sensorbytes
dht11_readRawData:

        ;; Initiation
        lda #DHT11_MASK         ; pin.mode = OUTPUT
        sta DDRA
        stz PORTA               ; assert LOW
        ;; Do stuff for > 18ms before releasing the pin

        ;; 18000 us - 2 ticks away, but we really want 3 ticks
        ;; but bcs means we keep at it until we exceed.
        lda #3
        jsr delayticks

        stz DDRA                ; release and let the pull up happen

        DHT11_SPIN_WHILE_LOW    ; should be instantaneous
        DHT11_SPIN_WHILE_HIGH

        ;; then these are the 80 & 80 us initial response
        DHT11_SPIN_WHILE_LOW
        DHT11_SPIN_WHILE_HIGH

        ;; so now the first bit is started (low)

        jsr dht11_readByte
        sta sensorbytes
        jsr dht11_readByte
        sta sensorbytes+1
        jsr dht11_readByte
        sta sensorbytes+2
        jsr dht11_readByte
        sta sensorbytes+3
        jsr dht11_readByte
        sta sensorbytes+4
        rts

        ;;
        ;; no arguments, returns byte in A register
        ;;
dht11_readByte:
        ;; preload a 1 into the result byte.  We will know we are done
        ;; when this bit has rolled up into the Carry.
        ldy #1                  ; initial bit

        sei
bitloop$:
        DHT11_SPIN_WHILE_LOW    ; wait for hi

        NOPS 10                 ; delay 30us

        lda PORTA               ; put pin bit into C
        .if DHT11_PIN > 3
        DOTIMES asl,(8-DHT11_PIN)
        .else
        DOTIMES lsr,(DHT11_PIN+1)
        .endif

        tya
        rol                     ; rotate the new bit in, and the high bit to C
        tay

        DHT11_SPIN_WHILE_HIGH   ; wait for the start of the next bit

        bcc bitloop$            ; the top bit was not one yet
        tya
        cli
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

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

reset:
        jsr timer_initialization
        jsr lcd_initialization

        ;; Also trigger CA2 downedges, in independent mode
        stz ca2_counter
        lda #%00000010
        sta PCR
        lda #%10000001          ; enable CA2 interrupts
        sta IER

        ;; Extra pre-loop delay
        lda #"<"
        jsr print_character

        lda #100
        jsr delayticks

        lda #">"
        jsr print_character

loop$:
        ;; 1 second delay
        lda #190
        jsr delayticks

        jsr lcd_clear
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
        PRINT_DEC8 ca2_counter
        stz ca2_counter

fin$:
        jmp loop$

        .align 8                ; avoid page boundary crossings in irq
nmi:
        rti

irq:
        ;; TWO conditions - T1, and CA2
        pha

        ;; CA2 is high priority
        lda IFR
        lsr
        bcc skip_ca2$
        inc ca2_counter
        lda #%01111111
        sta IFR                 ; clear ALL conditions and get out
        pla
        rti

skip_ca2$:
        bit IFR
        bvc skip_timer$

        bit T1CL                ; clear condition
        inc tick_counter        ; increment lsbyte
        bne tick_inc_done$      ; roll up as needed
        inc tick_counter+1
        bne tick_inc_done$
        inc tick_counter+2
        bne tick_inc_done$
        inc tick_counter+3
tick_inc_done$:
skip_timer$:
        pla
        rti

        ;; inc irqcounter
        ;; bit PORTA               ; clear the CA1 condition
        ;; Sample the time since the last interrupt
        ;; ldy #255
        ;; lda #156
        ;; sec
        ;; sbc T1CL
        ;; sty T1CL                ; Close together as possible
        ;;
        ;; The bit in in C, roll everything through - elegant, if expensive
        ;; rol sensorbytes+4
        ;; rol sensorbytes+3
        ;; rol sensorbytes+2
        ;; rol sensorbytes+1
        ;; rol sensorbytes

        ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;; The interrupt & reset vectors
        .org $fffa
        .word nmi
        .word reset
        .word irq
