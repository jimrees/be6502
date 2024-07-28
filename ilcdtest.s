.setcpu "65C02"
.feature string_escapes on
.include "syscall_defs.s"
        ALLSYSCALL .global

.include "libi2c_defs.s"
.include "libilcd_defs.s"
.include "via_defs.s"

        TICK_COUNTER = 4

.zeropage
TMP_PTR:         .res 2

.macro SERIAL_PSTR name
        lda #< name
        ldy #> name
        jsr STROUT
.endmacro

.code
start:
        jsr lcd_clear
        jsr lcd_read_ac
        jsr serial_print_A_in_hex
        jsr SERIAL_CRLF
        lda #$40
        jsr lcd_set_position
        lda #'*'
        jsr lcd_print_character
        jsr lcd_read_ac
        jsr serial_print_A_in_hex
        jsr SERIAL_CRLF

        jsr I2C_Init
        lda #$FF
        sta LCD_I2C_ADDRESS     ; invalid address
        jsr scan_for_device
        bit LCD_I2C_ADDRESS
        bpl @continue

        SERIAL_PSTR nodeviceresponsed

        brk                     ; fail if we found no device

@continue:
        jsr ilcd_init
        bcc @ok

        SERIAL_PSTR initfail
        brk

@ok:
.macro CREATE_CHAR I,LOC
        lda #< LOC
        sta LCD_CC_ADDRESS
        lda #> LOC
        sta LCD_CC_ADDRESS+1
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

        jsr ilcd_clear
        jsr ilcd_readbusy
        jsr serial_print_A_in_hex
        jsr SERIAL_CRLF
        jsr SERIAL_CRLF

        lda #$0
        jsr ilcd_set_position

        lda #< hellostr
        sta TMP_PTR
        lda #> hellostr
        sta TMP_PTR+1
        ldy #0
@loop:
        lda (TMP_PTR),y
        beq @done
        jsr ilcd_write_char
        iny
        jmp @loop
@done:
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
        jsr ilcd_write_char

.if 1
        jsr ilcd_read_ac
        jsr serial_print_A_in_hex
        jsr SERIAL_CRLF
.endif

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

        lda #'2'
        jsr lcd_print_character

        brk                     ; return to WOZMON

scan_for_device:
        ;; loop through 256 bytes
        ldx #127
@scanloop:
        phx
        jsr I2C_Start           ; initiate
        pla
        sec                     ; read-mode?
        jsr I2C_SendAddr
        jsr I2C_ReadAck         ; result in C
        jsr I2C_Stop

        bcs @no_ack_asserted

        txa
        sta LCD_I2C_ADDRESS     ; save result
        jsr serial_print_A_in_hex
        lda #':'
        jsr CHROUT
        lda #' '
        jsr CHROUT
        SERIAL_PSTR success_message

@no_ack_asserted:
        jsr I2C_Clear
        dex
        bpl @scanloop
        rts

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


.rodata
success_message: .asciiz "Ack asserted!\r\n"
hellostr:       .asciiz "Hello! "
custombytes:    .byte 0,1,2,3,4,5,6,7
initdone:       .asciiz "Init Completed\r\n"
initfail:       .asciiz "Init FAILED\r\n"
nodeviceresponsed:      .asciiz "No Device Responded to Scan\r\n"

bell:    .byte $4, $e, $e, $e,$1f, $0, $4, $0
note:    .byte $2, $3, $2, $e,$1e, $c, $0, $0
clock:   .byte $0, $e,$15,$17,$11, $e, $0, $0
heart:   .byte $0, $a,$1f,$1f, $e, $4, $0, $0
duck:    .byte $0, $c,$1d, $f, $f, $6, $0, $0
check:   .byte $0, $1, $3,$16,$1c, $8, $0, $0
cross:   .byte $0,$1b, $e, $4, $e,$1b, $0, $0
retarrow:.byte $1, $1, $5, $9,$1f, $8, $4, $0
