;;;
;;; This program plays with a DHT22 temperature/humidity sensor with
;;; the dataline attached to PORTA.7 and also CA2 on the VIA.  We need
;;; to be able to drive the pin low, then release it (by switching to
;;; input mode), then sampling timestamps when the line has a
;;; down-edge 42 times after the release.
;;;
;;; The down-edges can be as little as 75usec apart and we cannot
;;; afford to miss any of them.  So the general interrupt handler of
;;; the bios is too slow for this.  So, here we just poll the CA2
;;; condition with interrupts disabled.  During that disabling period,
;;; "forced" RTSB is enabled to avoid missing serial input.
;;;
.setcpu "65C02"
.debuginfo +
.feature string_escapes on

.include "bios_defs.s"          ; CHROUT, CHRIN, ...
.include "via_defs.s"
.include "macros.s"
.include "decimalprint_defs.s"
.include "timer_defs.s"
.include "lcd_defs.s"
.include "syscall_defs.s"
ALLSYSCALL .global

.include "libi2c_defs.s"
.include "libilcd_defs.s"
.include "ansi_defs.s"

        lcd_instruction = $a162

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
correct_checksum: .res 1
loop_counter:     .res 1
divisor:          .res 1
value2:           .res 1
value3:           .res 1
mod22:            .res 1
mod23:            .res 1

DHT_PIN = 7
DHT_MASK = (1<<DHT_PIN)

.code
start:
        jmp init

premessage:     .asciiz "Good Morning"
message:        .asciiz "Temperature & RH"
timeout_message: .asciiz "TIMEOUT "
loopchars:           .byte "|/-",$0
serial_loopchars:      .byte "|/-\\"
uptime:         .asciiz " Uptime: "
days:          .asciiz " days, "
hours:         .asciiz " hours, "
minutes:         .asciiz " minutes, and "
seconds:         .asciiz " seconds.\r\n"
press_key_to_continue:  .asciiz "Press any key to continue..."
ca2_condition_triggered: .asciiz "CA2 Edge Triggered\r\n"

.macro PAUSE_FOR_KEYPRESS
.local @spin, @continue
        SERIAL_PSTR press_key_to_continue
@spin:  jsr BYTEIN
        bcc @spin
        cmp #$03
        bne @continue
        brk
@continue:
        jsr SERIAL_CRLF
.endmacro
.macro SERIAL_PSTR STR
        lda #<STR
        ldy #>STR
        jsr STROUT
.endmacro
.macro LCD_PSTR STR
        lda #<STR
        ldy #>STR
        jsr lcd_print_string
.endmacro
.macro ILCD_PSTR STR
        lda #<STR
        ldy #>STR
        jsr ilcd_print_string
.endmacro
.macro BOTH_PSTR STR
        LCD_PSTR STR
        ILCD_PSTR STR
.endmacro

both_clear:
        jsr lcd_clear
        jmp ilcd_clear
both_set_position:
        pha
        jsr lcd_set_position
        pla
        jmp ilcd_set_position
both_shift_left:
        lda #%00011000
        jsr lcd_instruction
        jmp ilcd_shift_left

both_cursor_right:
        lda #%00010100
        jsr lcd_instruction
        jmp ilcd_cursor_right

both_cursor_left:
        lda #%00010000
        jsr lcd_instruction
        jmp ilcd_cursor_left

both_create_char:
        pha
        jsr lcd_create_char
        pla
        jmp ilcd_create_char

divide_by_divisor:
        pha
        phx
        phy
        ;; Initialize remainder to zero
        stz mod10
        stz mod10 + 1
        stz mod22
        stz mod23
        clc

        ldx #32
@divloop:
        ;; Rotate quotient & remainder
        rol value
        rol value + 1
        rol value2
        rol value3
        rol mod10
        rol mod10 + 1
        rol mod22
        rol mod23

        ;;  a,y = dividend - divisor
        sec
        lda mod10
        sbc divisor
        pha                      ; stash low byte for the moment
        lda mod10 + 1
        sbc #0
        pha                     ; stash middle byte
        lda mod22
        sbc #0
        pha                     ; stash next byte
        lda mod23
        sbc #0
        bcc @ignore_result       ; dividend < divisor
        sta mod23
        pla
        sta mod22
        pla
        sta mod10 + 1
        pla
        sta mod10
        jmp @continue_loop
@ignore_result:
        pla
        pla
        pla
@continue_loop:
        dex
        bne @divloop

        rol value               ; final rotate
        rol value+1
        rol value2
        rol value3
        ply
        plx
        pla
        rts

report_uptime:
        sei
        lda tick_counter
        sta value
        lda tick_counter+1
        sta value+1
        lda tick_counter+2
        sta value2
        lda tick_counter+3
        cli
        sta value3

        lda #100
        sta divisor
        jsr divide_by_divisor
        ;; divide by 60 for minutes/seconds - discard remainder

        lda #60
        sta divisor
        jsr divide_by_divisor
        ;; push seconds somewhere for later display
        lda mod10
        pha                     ; push seconds

        jsr divide_by_divisor
        lda mod10
        pha                 ; push minutes

        lda #24
        sta divisor
        jsr divide_by_divisor
        lda mod10
        pha                  ; push hours

        ;; value contains days
        SERIAL_PSTR uptime
        jsr serial_print_value_in_decimal
        SERIAL_PSTR days

        pla
        sta value
        stz value+1
        jsr serial_print_value_in_decimal
        SERIAL_PSTR hours

        pla                     ; minutes
        sta value
        stz value+1
        jsr serial_print_value_in_decimal
        SERIAL_PSTR minutes

        pla
        sta value
        stz value+1
        jsr serial_print_value_in_decimal
        SERIAL_PSTR seconds
        rts

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

        ;; Serial input will be disabled anyway - tell the other end not to send
        ;; anything to avoid losing bytes.
        lda #80
        jsr set_forced_rtsb

        ;; Initiate the request with a down pulse (>= 18ms for DHT11, > 1ms for DHT22 )
        lda #DHT_MASK         ; pin.mode = OUTPUT
        tsb DDRA              ; so ONLY that pin is outout

        ;; we only need 1ms delay, but here's 10ms
        lda #1
        jsr delayticks

        ;; first downedge in 40us.
        ;; next after that in 160us
        ;; then 80-120 x 40 after that 200 + 4800 = 5000us total max
        ;; set a target time (4-byte?) after the release and sample as we go:

        ldy #(256-42)           ; down-edge counter

        sei                     ; we don't want interrupts to delay sampling of downedges

        ;; But we will lose timer interrupts because we cannot sample the low-order
        ;; counter without clearing the condition.

        ;; 42 downedges expected * ~95 us per = 3990
        ;; So, 4096 should be plenty?

        sec
        lda T1CH
        sbc #17      ; 17 * 256 = 4096 + 256
        bcs @ok      ; still have the carry bit - no correction needed
        adc #x27     ; the tick period is #x2710 cycles, we load with #x270E
@ok:
        tax                     ; store target here

        lda #DHT_MASK
        trb DDRA                ; release and let the pull up happen

@next_bit:
        lda #$01
        sta IFR                 ; clear the condition
@spin_until_ca2:
        cpx T1CH                ; have we reached the timeout
        beq @timeout            ; only when we have an exact match do we call it a timeout.  The duration of the #x39
        bit IFR
        beq @spin_until_ca2

@ca2_triggered:
        lda T1CL                ; sample the timer 4 (14) (this also clears the timer condition)
        sta ca2_buffer-256+42,y ; push into buffer 4 (18)
        iny                     ; increment edge counter 2 (22)
        bne @next_bit           ; keep looping 3 (25)

        lda #$01                ; Clear the final condition
        sta IFR

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

.if 0                           ; debugging - print the intervals
        pha
        sta value
        stz value+1
        jsr serial_print_value_in_decimal
        jsr SERIAL_CRLF
        pla
.endif

        cmp #93                 ; discriminator
        lda ca2_buffer,y        ; for next pass
        iny                     ; 'consume'
        rol sensorbytes+5,x     ; negative index works in zeropage
        bcc @bitloop            ; see if that 1 has reached C yet
        inx
        bmi @byteloop           ; while still negative, keep looping

.if 0                           ; Eliminated when I2C took pin 0 over
        ;; testing - if jumper is set high, it flips bit 0 of the checksum
        lda PORTA
        and #1
        eor sensor_checksum
        sta sensor_checksum
.endif

        ;; confirm checksum
        lda sensorbytes
        clc
        adc sensorbytes+1
        clc
        adc sensorbytes+2
        clc
        adc sensorbytes+3
        sta correct_checksum
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

;;; Debugging
;;; Check if the CA2 condition has triggered when it should not have.
;;; I occassionally get checksum failures and I do not know why - so
;;; I wonder if the I2C code might be messing with PORTA.7
check_ca2:
        lda #01
        bit IFR
        beq @done
        sta IFR
        SERIAL_PSTR ca2_condition_triggered
@done:
        rts

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

init:
        ;; Enable CA2 downedge
        ;; Note that we're not turning on CA2 interrupts.
        sei
        lda PCR
        and #%11110001          ; preserve everything that is not CA2
        ora #%00000010          ; enable the CA2 downedge independent mode
        sta PCR
        cli

        jsr check_ca2

        jsr ansi_init
        ;; zero out ORA while DDRA is also zero.
        jsr I2C_Init

        lda #$3f
        jsr ilcd_set_address
        jsr ilcd_init

        lda #< backslash
        sta value
        lda #> backslash
        sta value+1
        lda #0
        jsr both_create_char

        lda #< checks
        sta value
        lda #> checks
        sta value+1
        lda #1
        jsr both_create_char

        lda #< thermometer
        sta value
        lda #> thermometer
        sta value+1
        lda #2
        jsr both_create_char

        ;; Also trigger CA2 downedges, in independent mode
        stz loop_counter

        jsr SERIAL_CRLF
        jsr both_clear
        BOTH_PSTR premessage

        lda #4                  ; 4 is red
        ldy #0                  ; 0 is black
        jsr ansi_setcolor

        SERIAL_PSTR premessage
        jsr ansi_restore_color
        jsr SERIAL_CRLF

        jsr check_ca2

@loop:
        lda #%00001110          ; display on, cursor on, blink off
        jsr lcd_instruction

        lda #$50
        jsr both_set_position

        ;; move cursor right 15 times
        ldx #7
@currightloop:
        phx
        jsr both_cursor_right
        jsr both_cursor_right
        lda #28
        jsr delayticks
        plx
        dex
        bne @currightloop

        ldx #7
@curleftloop:
        phx
        jsr both_cursor_left
        jsr both_cursor_left
        lda #28
        jsr delayticks
        plx
        dex
        bne @curleftloop

        ;; jsr ansi_clearscr
        jsr both_clear

        lda #$10
        jsr both_set_position

        BOTH_PSTR message

        lda #$50
        jsr both_set_position

        jsr check_ca2

        jsr dht_readRawData
        bpl @no_timeout_error
        jmp @timeout_error
@no_timeout_error:
        php                     ; save status

        lda #2                  ; thermometer
        jsr print_char_to_lcds
        lda #' '
        jsr print_char_to_lcds
        ;; our data should be there:
        lda integral_temp
        bpl @not_negative
        and #$7f
        lda #'-'
        jsr print_char_to_all

@not_negative:

        ;; After stripping the sign bit, the combined 15-bit represented 1/10ths
        ;; of degrees C.  So divide by 10 for the true integer part:
        sta value+1
        lda decimal_temp
        sta value
        jsr divide_by_10
        lda mod10               ; grab the fraction (0..9)
        pha                     ; save it
        jsr both_value_in_decimal ; prints what's stored in value
        lda #'.'
        jsr print_char_to_all
        pla                     ; recover fraction
        clc
        adc #'0'                ; and just print it since we know it can only be 0..9
        jsr print_char_to_all

        lda #' '
        jsr print_char_to_all

        lda integral_rh
        sta value+1
        lda decimal_rh
        sta value
        jsr divide_by_10
        lda mod10
        pha
        jsr both_value_in_decimal

        lda #'.'
        jsr print_char_to_all
        pla
        clc
        adc #'0'
        jsr print_char_to_all
        lda #' '
        jsr print_char_to_all

        plp                     ; restore status from dht_readRawData call
        beq @show_loop_char     ; if Z is set, then all is well.

        lda #'E'                ; Report checksum failure
        jsr print_char_to_all
        lda sensor_checksum
        sta value
        stz value+1
        jsr both_value_in_decimal
        lda #' '
        jsr print_char_to_all

        lda correct_checksum
        sta value
        stz value+1
        jsr serial_print_value_in_decimal
        lda #' '
        jsr CHROUT

        jmp @show_loop_char

@timeout_error:
        BOTH_PSTR timeout_message
        SERIAL_PSTR timeout_message

@show_loop_char:
        lda loop_counter
        inc
        sta loop_counter
        and #3
        tax

        lda loopchars,x
        jsr print_char_to_lcds
        lda #2
        ldy #0
        jsr ansi_setcolor
        lda serial_loopchars,x
        jsr CHROUT
        jsr ansi_restore_color

        lda #1                  ; the hash mark
        jsr print_char_to_lcds

        ;; Now perform the shift from off-screen onto screen
        ldy #16
@ipadloop:
        jsr both_shift_left
        lda #4
        jsr delayticks
        dey
        bne @ipadloop

        jsr check_ca2

        jsr report_uptime

        jsr ANYCNTC
        beq @quit_program
        jmp @loop

@quit_program:
        brk


;;; value must contain the number
;;; A,X,Y will all be trashed.
both_value_in_decimal:
        ;; push digits onto the stack, then unwind to print
        ;; the in the right order.
        lda #0                  ; push a null char on the stack
        pha
@next_digit:
        jsr divide_by_10
        lda mod10
        clc
        adc #'0'
        pha
        ;; If any part of the quotient is > 0, go again.
        lda value
        ora value+1
        bne @next_digit
        pla
@unfold_print_loop:
        jsr print_char_to_all
        pla                     ; pop the next one
        bne @unfold_print_loop  ; if not-null, keep looping

        rts

print_char_to_all:
        pha
        jsr CHROUT
        pla
        jmp print_char_to_lcds

print_char_to_lcds:
        pha
        jsr lcd_print_character
        pla
        jmp ilcd_write_char

lcd_create_char:
        asl                     ; multiply by 8
        asl
        asl
        ora #$40                ; LCD_SETCGRAMADDR
        jsr lcd_instruction
        phy
        ldy #0
@loop:
        lda (value),y
        jsr lcd_print_character
        iny
        cpy #8
        bcc @loop
        ply
        rts

.rodata
backslash:
.byte %00000
.byte %10000
.byte %01000
.byte %00100
.byte %00010
.byte %00001
.byte %00000
.byte %00000
checks:
.byte %10101
.byte %01010
.byte %10101
.byte %01010
.byte %10101
.byte %01010
.byte %10101
.byte %01010
thermometer:
.byte %00100
.byte %01010
.byte %01010
.byte %01110
.byte %11111
.byte %11111
.byte %01110
.byte %00100
.rodata
