.setcpu "65C02"
.feature string_escapes on
.include "syscall_defs.s"
        ALLSYSCALL .global

.include "libi2c_defs.s"
.include "libilcd_defs.s"
.include "via_defs.s"
.include "macros.s"
.include "lcd_defs.s"

        TICK_COUNTER = 4

.zeropage
TMP_PTR:         .res 2
SAVED_RET:        .res 2
NEXT_CORRUPT:   .res 1

.macro SERIAL_PSTR name
        lda #< name
        ldy #> name
        jsr STROUT
.endmacro

.macro ILCD_PSTR_AY name
        lda #< name
        ldy #> name
        jsr ilcd_print_string
.endmacro

.macro PAUSE_FOR_KEYPRESS
.local @spin, @continue
        SERIAL_PSTR press_key_to_continue
@spin:  jsr BYTEIN
        bcc @spin
        cmp #$03
        bne @continue
        brk
@continue:
.endmacro

        lcd_initialization = $a22b

.code
start:
        jsr lcd_initialization  ; hit reset!
        lda #< hellostr
        ldy #> hellostr
        jsr lcd_print_string
        lda #$40
        jsr lcd_set_position
        lda #'*'
        jsr lcd_print_character

        lda #%11111000
        trb NEXT_CORRUPT

        jsr I2C_Init
        lda #$3f
        jsr ilcd_set_address
        jsr ilcd_init
        bcc @ok

        SERIAL_PSTR initfail
        brk

@ok:
.macro CREATE_CHAR I,LOC
        lda #< LOC
        sta value
        lda #> LOC
        sta value+1
        lda #I
        jsr ilcd_create_char
.endmacro
        CREATE_CHAR 0,bell
        CREATE_CHAR 1,note
        CREATE_CHAR 2,clock
        CREATE_CHAR 3,heart
        CREATE_CHAR 4,duck
        CREATE_CHAR 5,check
        CREATE_CHAR 6,cross
        CREATE_CHAR 7,retarrow

        SERIAL_PSTR initdone

@mainloop:
        jsr ilcd_home

        ILCD_PSTR_AY hellostr

        lda TICK_COUNTER
        jsr ilcd_print_A_in_hex
        lda T1CH
        jsr ilcd_print_A_in_hex

        lda #< custombytes
        sta TMP_PTR
        lda #> custombytes
        sta TMP_PTR+1
        lda #$40
        jsr ilcd_set_position

        ldy #0
@loop2:
        lda (TMP_PTR),y
        phy
        jsr ilcd_write_char

.if 1
        jsr ilcd_read_ac
        jsr serial_print_A_in_hex
        jsr SERIAL_CRLF
.endif
        ply
        iny
        cpy #8
        bcc @loop2

        lda #' '
        jsr ilcd_write_char
        lda TICK_COUNTER
        jsr ilcd_print_A_in_hex
        lda T1CH
        jsr ilcd_print_A_in_hex

        jsr ilcd_read_ac
        jsr serial_print_A_in_hex
        jsr SERIAL_CRLF

        jsr ANYCNTC
        beq @abort
        jmp @mainloop
@abort:

        lda #< goodbye
        ldy #> goodbye
        jsr lcd_print_string

        SERIAL_PSTR sending_corruption
        lda NEXT_CORRUPT
        sta value
        stz value+1
        jsr serial_print_value_in_decimal
        jsr SERIAL_CRLF

        lda NEXT_CORRUPT
        jsr lcd_corrupt_state
        lda NEXT_CORRUPT
        jsr ilcd_corrupt_state

        inc NEXT_CORRUPT
        brk                     ; return to WOZMON

serial_print_value_in_decimal:
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
        jsr CHROUT
        pla                     ; pop the next one
        bne @unfold_print_loop  ; if not-null, keep looping
        rts

lcd_print_value_in_decimal:
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
        jsr ilcd_write_char
        pla                     ; pop the next one
        bne @unfold_print_loop  ; if not-null, keep looping
        rts

serial_print_hex_nibble:
        cmp #10
        bcs @alpha
        clc
        adc #'0'
        jsr CHROUT              ; the system calls expect a jsr call!
        rts
@alpha:
        clc
        adc #('A'-10)
        jsr CHROUT
        rts

serial_print_A_in_hex:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr serial_print_hex_nibble
        pla
        and #$f
        jmp serial_print_hex_nibble

ilcd_print_hex_nibble:
        cmp #10
        bcs @alpha
        clc
        adc #'0'
        jsr ilcd_write_char
        rts
@alpha:
        clc
        adc #('A'-10)
        jsr ilcd_write_char
        rts

ilcd_print_A_in_hex:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr ilcd_print_hex_nibble
        pla
        and #$f
        jmp ilcd_print_hex_nibble


E  = %01000000
RW = %00100000
RS = %00010000
.macro DISP_SEND_INS_NIBBLE
        tax
        lda #%01111111
        trb PORTB
        txa
        tsb PORTB               ; Set all the bits
        lda #E
        tsb PORTB               ; strobe E up & down
        trb PORTB
.endmacro

lcd_wait:
        pha                     ; save A
        phx                     ; save X

        ;; Change pins 0-4 to read
        lda #%00001111
        trb DDRB

        ;; Set up with atomic operations to avoid touching bit7
        lda #(E|RS)             ; clear E & RS
        trb PORTB
        lda #RW                 ; set RW
        tsb PORTB

@lcdbusy:
        lda #E
        tsb PORTB               ; E UP
        ldx PORTB               ; read high nibble
        trb PORTB               ; E DOWN
        tsb PORTB               ; E UP
        trb PORTB               ; E DOWN
        txa
        and #%00001000          ; check busy bit
        bne @lcdbusy

        ;; Change pins 0-4 to write
        lda #%00001111
        tsb DDRB

        plx
        pla
        rts

lcd_instruction:
        jsr lcd_wait
        phx                     ; save X
        pha                     ; save A
        lsr
        lsr
        lsr
        lsr                     ; move high bit to low
        DISP_SEND_INS_NIBBLE
        pla
        and #%00001111          ; now the low bits
        DISP_SEND_INS_NIBBLE
        plx
        rts

lcd_corrupt_state:
        dec
        bne @check2
        ;; put into 8-bit mode, 2-line, same stuff
        lda #%00111000
        jmp lcd_instruction
@check2:
        dec
        bne @check3
        ;; put into 4-bit dangling mode, switching to 8-bit
        lda #%00000011
        DISP_SEND_INS_NIBBLE
        rts
@check3:
        dec
        bne @check4
        ;; put into 4-bit dangling mode, with a %0000 prefix
        lda #%00000000
        DISP_SEND_INS_NIBBLE
        rts
@check4:
        dec
        bne @done
        ;; put into 4-bit dangling mode with a command to switch to 4-bit
        lda #%00000010
        DISP_SEND_INS_NIBBLE
@done:
        rts

.rodata
success_message: .asciiz "Ack asserted!\r\n"
hellostr:       .asciiz "Hello! "
goodbye:       .asciiz " GoodBye! "
custombytes:    .byte 0,1,2,3,4,5,6,7
initdone:       .asciiz "Init Completed\r\n"
initfail:       .asciiz "Init FAILED\r\n"
nodeviceresponsed:      .asciiz "No Device Responded to Scan\r\n"
sending_corruption:     .asciiz "Sending mode to corrupt main lcd: "
press_key_to_continue:  .asciiz "\r\nPress any key to continue..."

bell:
.byte %00000100
.byte %00001110
.byte %00001110
.byte %00001110
.byte %00011111
.byte %00000000
.byte %00000100
.byte %00000000
note:
.byte %00000010
.byte %00000011
.byte %00000010
.byte %00001110
.byte %00011110
.byte %00011000
.byte %00000000
.byte %00000000

clock:   .byte $0, $e,$15,$17,$11, $e, $0, $0
heart:   .byte $0, $a,$1f,$1f, $e, $4, $0, $0
duck:    .byte $0, $c,$1d, $f, $f, $6, $0, $0
check:   .byte $0, $1, $3,$16,$1c, $8, $0, $0
cross:   .byte $0,$1b, $e, $4, $e,$1b, $0, $0
retarrow:.byte $1, $1, $5, $9,$1f, $8, $4, $0
