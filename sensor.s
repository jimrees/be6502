.setcpu "65C02"
.debuginfo +
.feature string_escapes on
.include "syscall_defs.s"
.export lcd_print_character
.exportzp tick_counter

.include "via.s"
.include "macros.s"
.include "decimalprint_defs.s"
.include "timer_defs.s"

.import delayseconds, delayticks

;;; For simplicity, this is a full page.  More complex code could
;;; reduce it to 4 slots probably, if needed.  If reduced, it could
;;; be moved to the zeropage as well.
.bss
.align 256
ca2_buffer:      .res 256

.zeropage
sensorbytes:
integral_rh:      .res 1
decimal_rh:       .res 1
integral_temp:    .res 1
decimal_temp:     .res 1
sensor_checksum:  .res 1
timeout_target:   .res 1
loop_counter:     .res 1

DHT_PIN = 7
DHT_MASK = (1<<DHT_PIN)

.code
start:
        jmp init


premessage:     .asciiz "Good Morning"
message:        .asciiz "Temperature & RH"
timeout_message: .asciiz "TIMEOUT "
loopchars:      .byte "|/-",$a4

;;;
;;; writes to sensorbytes
;;; sets A to:
;;;    #0 for success
;;;    #-1 for timeout
;;;    #+1 for checksum error
;;; The N & Z bits are set accordingly.
;;;
dht_readRawData:
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
        lda #DHT_MASK         ; pin.mode = OUTPUT
        tsb DDRA                ; so ONLY that pin is outout
        trb PORTA               ; assert LOW (1 downedge)

        lda #((20 * TIMER_FREQUENCY) / 1000) + 1
        jsr delayticks

        ;; first downedge in 40us.
        ;; next after that in 160us
        ;; then 80-120 x 40 after that 200 + 4800 = 5000us total max
        ;; set a target time (4-byte?) after the release and sample as we go:

        lda #80
        jsr set_forced_rtsb

        lda #$01
        sta IFR                 ; clear the current CA2 condition

        ldy #(256-42)           ; down-edge counter

        sei

        ;; 5000us total should be the max.  Timeout at ~8192
        sec
        lda T1CH
        sbc #(8192/256)         ; plenty of time
        sta timeout_target

        lda #DHT_MASK
        trb DDRA                ; release and let the pull up happen

@next_bit:

.if 0
;;; If we have to spin anyway, might as well just spin on the signal bit
;;; and forget about downedge detection.
;;; But be careful -- we have to be "on it" as each half of the pulse is
;;; that much shorter -- the up-part of a 0-bit is only 26 cycles!
@spin_until_up:
        lda #DHT_MASK
        bit PORTA
        bne @spin_up_reached
        lda T1CH
        cmp timeout_target
        bne @spin_until_up
        jmp @timeout

@spin_up_reached:
@spin_until_down:
        lda #DHT_MASK
        bit PORTA
        beq @downspin_reached
        lda T1CH
        cmp timeout_target
        bne @spin_until_down
        jmp @timeout
@downspin_reached:
.else

@spin_until_ca2:
        lda T1CH
        cmp timeout_target
        beq @timeout
        lda #01
        bit IFR
        beq @spin_until_ca2
        sta IFR                 ; clear the condition
.endif

        lda T1CL                ; sample the timer 4 (14) (this clear interrupt)
        sta ca2_buffer-256+42,y ; push into buffer 4 (18)
        iny                     ; decrement edge counter 2 (22)
        bne @next_bit           ; keep looping 3 (25)

        cli                     ; restore interrupts

        lda #0
        jsr set_forced_rtsb     ; re-enable RTSB

        ldx #(256-5)            ; initialize outer loop counter
        ldy #1
        lda ca2_buffer,y        ; preload the 2nd stamp
        iny
@byteloop:
@bitloop:
        sec
        sbc ca2_buffer,y
        cmp #99
        lda ca2_buffer,y        ; for next pass
        iny                     ; 'consume'
        rol sensorbytes+5,x     ; negative index works in zeropage
        bcc @bitloop            ; see if that 1 has reached C yet
        inx
        bmi @byteloop           ; while still negative, keep looping

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
        bne @ck_bad_checksum
        lda #0
        rts
@ck_bad_checksum:
        lda #1                 ; clears N & Z, signalling checksum error
        rts

@timeout:
        cli
        lda #0
        jsr set_forced_rtsb     ; re-enable RTSB
        lda #$ff                ; return timeout, try again
        rts

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

init:
        ;; jsr timer_initialization - not needed.  bios already has done this
        ;; jsr lcd_initialization - not needed

        ;; Also trigger CA2 downedges, in independent mode
        stz loop_counter

        jsr SERIAL_CRLF

        ;; Enable CA2 downedge
        ;; Note that we're not turning on CA2 interrupts.
        sei
        lda PCR
        and #%11110001          ; preserve everything that is not CA2
        ora #%00000010          ; enable the CA2 downedge independent mode
        sta PCR
        cli

        jsr lcd_clear
        lda #<premessage
        ldy #>premessage
        jsr lcd_print_string

@loop:
        lda #2
        jsr delayseconds

        jsr lcd_clear
        lda #<message
        ldy #>message
        jsr lcd_print_string
        lda #40
        jsr lcd_set_position

        jsr dht_readRawData
        bmi @timeout_error
        php                     ; save status

        ;; our data should be there:
        lda integral_temp
        bpl @not_negative
        and #$7f
        lda #'-'
        jsr lcd_print_character
@not_negative:

        ;; After stripping the sign bit, the combined 15-bit represented 1/10ths
        ;; of degrees C.  So divide by 10 for the true integer part:
        sta value+1
        lda decimal_temp
        sta value
        jsr divide_by_10
        lda mod10               ; grab the fraction (0..9)
        pha                     ; save it
        jsr print_value_in_decimal ; prints what's stored in value
        lda #'.'
        jsr lcd_print_character
        pla                     ; recover fraction
        clc
        adc #'0'                ; and just print it since we know it can only be 0..9
        jsr lcd_print_character

        lda #' '
        jsr lcd_print_character

        lda integral_rh
        sta value+1
        lda decimal_rh
        sta value
        jsr divide_by_10
        lda mod10
        pha
        jsr print_value_in_decimal
        lda #'.'
        jsr lcd_print_character
        pla
        clc
        adc #'0'
        jsr lcd_print_character
        lda #' '
        jsr lcd_print_character

        plp                     ; restore status from dht_readRawData call
        beq @show_loop_char     ; if Z is set, then all is well.

        lda #'E'                ; Report checksum failure
        jsr lcd_print_character
        PRINT_DEC8 sensor_checksum
        lda #' '
        jsr lcd_print_character
        jmp @show_loop_char

@timeout_error:
        lda #<timeout_message
        ldy #>timeout_message
        jsr lcd_print_string

@show_loop_char:
        lda loop_counter
        inc
        sta loop_counter
        and #3
        tax
        lda loopchars,x
        jsr lcd_print_character

        jsr ANYCNTC
        beq @quit_program
        jmp @loop

@quit_program:
        jmp WOZSTART
