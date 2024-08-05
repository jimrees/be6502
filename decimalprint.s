.setcpu "65C02"
.debuginfo +
.feature string_escapes on
.include "decimalprint_defs.s"
.include "lcd_defs.s"
.include "syscall_defs.s"

.code
;;; Dividend in value, value+1
;;; Result quotient in value,value+1 + mod10,mod10+1
;;; Modifies flags, value, mod10
divide_by_10:
        pha
        phx
        phy
        ;; Initialize remainder to zero
        stz mod10
        stz mod10 + 1
        clc

        ldx #16
@divloop:
        ;; Rotate quotient & remainder
        rol value
        rol value + 1
        rol mod10
        rol mod10 + 1

        ;;  a,y = dividend - divisor
        sec
        lda mod10
        sbc #10
        tay                     ; stash low byte in y
        lda mod10 + 1
        sbc #0
        bcc @ignore_result       ; dividend < divisor
        sty mod10
        sta mod10 + 1
@ignore_result:
        dex
        bne @divloop

        rol value               ; final rotate
        rol value+1
        ply
        plx
        pla
        rts


;;; value must contain the number
;;; A,X,Y will all be trashed.
print_value_in_decimal:
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
        jsr @retpushed
        pla                     ; pop the next one
        bne @unfold_print_loop  ; if not-null, keep looping

        rts

@retpushed: jmp (fcharprint)


lcd_print_value_in_decimal:
        lda #< lcd_print_character
        sta fcharprint
        lda #> lcd_print_character
        sta fcharprint+1
        jmp print_value_in_decimal

.global CHROUT
serial_print_value_in_decimal:
        lda #< CHROUT
        sta fcharprint
        lda #> CHROUT
        sta fcharprint+1
        jmp print_value_in_decimal
