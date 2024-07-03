.ifndef SYSCALLDEFS_S
        SYSCALLDEFS_S := 1

;;; Should I have some sort of version check?

        CHROUT = $F000
        CHRIN = $F010
        ANYCNTC = $F020
        lcd_clear = $F030
        lcd_home = $F040
        lcd_set_position = $F050
        lcd_print_hex8 = $F060
        lcd_print_binary8 = $F070
        lcd_print_character = $F080
        lcd_print_n_spaces = $F090
        SERIAL_CRLF = $F0A0
        STROUT = $F0B0
        lcd_print_string = $F0C0
        restore_default_irq_hook = $F0D0
        install_irq_hook = $F0E0
        set_forced_rtsb = $F0F0
        WOZSTART = $FF00
        tick_counter = $00
.endif
