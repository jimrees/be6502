.ifndef LCD_DEFS_S
        LCD_DEFS_S := 1

;;; Link with lcd.o when building the bios.
;;; Link with syscalls.o when building a loadable program.

.global lcd_print_character
.global lcd_clear
.global lcd_home
.global lcd_set_position
.global lcd_initialization
.global lcd_print_binary8
.global lcd_print_hex8
.global lcd_print_n_spaces
.global lcd_print_string

.endif
