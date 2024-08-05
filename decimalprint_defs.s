.ifndef DECIMALPRINT_DEFS_S
        DECIMALPRINT_DEFS_S := 1

.global print_value_in_decimal
.global lcd_print_value_in_decimal
.global serial_print_value_in_decimal
.global divide_by_10
.globalzp value, mod10, fcharprint

.macro PRINT_DEC16 address
        sei
        lda address
        ldy address + 1
        cli
        sta value
        sty value + 1
        jsr lcd_print_value_in_decimal
.endmacro

.macro PRINT_DEC8 address
        lda address
        sta value
        stz value + 1
        jsr lcd_print_value_in_decimal
.endmacro

.endif
