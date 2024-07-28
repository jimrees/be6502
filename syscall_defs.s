.ifndef SYSCALLDEFS_S
        SYSCALLDEFS_S := 1

        ;; The point here is to declare things the ROM provides at
        ;; stable locations.  So, that's what we're going to do with
        ;; a few zeropage locations too -- needed as parts of the api.
        value = $00               ; two bytes
        mod10 = $02               ; two bytes
.global WOZSTART
.global MONCOUT

.macro ALLSYSCALL CALLER
        CALLER CHROUT
        CALLER CHRIN
        CALLER MONRDKEY
        CALLER ANYCNTC
        CALLER SERIAL_CRLF
        CALLER STROUT
        CALLER BYTEIN
        CALLER LOAD
        CALLER SAVE
        CALLER lcd_clear
        CALLER lcd_home
        CALLER lcd_set_position
        CALLER lcd_print_hex8
        CALLER lcd_print_binary8
        CALLER lcd_print_character
        CALLER lcd_print_n_spaces
        CALLER lcd_print_string
        CALLER divide_by_10
        CALLER print_value_in_decimal
        CALLER set_forced_rtsb
        CALLER delayseconds
        CALLER delayticks
        CALLER lcd_read_ac
.endmacro

.endif
