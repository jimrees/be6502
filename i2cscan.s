.setcpu "65C02"
.feature string_escapes on
.include "syscall_defs.s"
        ALLSYSCALL .global

.include "libi2c_defs.s"
.include "macros.s"

.zeropage
TMP_PTR:         .res 2
SAVED_RET:        .res 2

.macro SERIAL_PSTR name
        lda #< name
        ldy #> name
        jsr STROUT
.endmacro

.code
start:
        jsr I2C_Init
        lda #$FF
        sta TMP_PTR             ; invalid address
        jsr scan_for_device
        bit TMP_PTR
        bpl @continue

        SERIAL_PSTR nodeviceresponsed

@continue:
        brk

scan_for_device:
        ;; loop through 256 bytes
        ldx #127
@scanloop:
        M_I2C_Start
        txa
        sec                     ; read-mode
        jsr I2C_SendAddr
        M_I2C_Stop

        bcs @no_ack_asserted

        SERIAL_PSTR success_message
        txa
        sta TMP_PTR     ; save result
        jsr serial_print_A_in_hex
        jsr SERIAL_CRLF

@no_ack_asserted:
        dex
        bpl @scanloop
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

.rodata
success_message: .asciiz "Device responded at address: "
nodeviceresponsed:      .asciiz "No Device Responded to Scan\r\n"
