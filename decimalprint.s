        .macro PRINT_DEC16,address
        sei
        lda \address
        ldy \address + 1
        cli
        sta value
        sty value + 1
        jsr print_value_in_decimal
        .endm

        .macro PRINT_DEC8,address
        lda \address
        sta value
        stz value + 1
        jsr print_value_in_decimal
        .endm


;;; value must contain the number
;;; A,X,Y will all be trashed.
print_value_in_decimal:
        lda #0                  ; push a null char on the stack
        pha

divide_do$:
        ;; Initialize remainder to zero
        lda #0
        sta mod10
        sta mod10 + 1
        clc

        ldx #16
divloop$:
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
        bcc ignore_result$       ; dividend < divisor
        sty mod10
        sta mod10 + 1
ignore_result$:
        dex
        bne divloop$

        rol value               ; final rotate
        rol value+1

        lda mod10

        clc
        adc #"0"
        pha

        ;; are we done?
        lda value
        ora value+1
        bne divide_do$

        pla                     ; we know there's at least one
unfold_print_loop$:
        jsr print_character
        pla                     ; pop the next one
        bne unfold_print_loop$  ; if not-null, keep looping

        rts
