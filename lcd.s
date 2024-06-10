
;;; This depends on via.h having been included

;;; lcd_wait should be safe in either 8-bit or 4-bit modes
;;; In 8-bit mode, we are pulling only the high 4 bits anyway
;;; (due to how the lcd is wired from the VIA), and then end
;;; up in the low 4 bits of PORTB - so in 8-bit mode, we're just
;;; reading twice and ignoring the second read.
lcd_wait:
        pha                     ; save A
        lda #%11110000          ; LCD data is input
        sta DDRB
lcdbusy:
        lda #RW                 ; Set up for the read command
        sta PORTB
        lda #(RW | E)           ; strobe E high
        sta PORTB
        lda PORTB               ; read high nibble
        pha                     ; ...and put on stack
        lda #RW                 ; strobe E down
        sta PORTB
        lda #(RW | E)           ; strobe E up to trigger the second read
        sta PORTB
        lda PORTB               ; read low nibble
        pla                     ; recover high nibble
        and #%00001000          ; check busy bit
        bne lcdbusy

        ;; Strobe E back down to tell lcd to stop driving the pins
        lda #RW
        sta PORTB

        lda #%11111111          ; PORTB back to all output
        sta DDRB
        pla
        rts

        ;; If reads were supported, this 3 write sequence would seem
        ;; silly, but in fact it's necessary for the device to be able
        ;; to reliably distinguish reads & writes and we don't end up
        ;; with bus contention.
        ;; The data isn't necessary until the strobe-up, but the RS/RWB
        ;; must be established for at least 40ns.
        .macro DISP_SEND_INS_NIBBLE
        sta PORTB               ; Set up RS/RWB, the data is along for the ride
        ora #E                  ; Now strobe E up
        sta PORTB               ;
        eor #E                  ; Strobe E down to latch the data/command
        sta PORTB               ;
        .endm

lcd_instruction:
        jsr lcd_wait
        pha                     ; save A
        lsr
        lsr
        lsr
        lsr                     ; move high bit to low
        DISP_SEND_INS_NIBBLE
        pla
        and #%00001111          ; now the low bits
        DISP_SEND_INS_NIBBLE
        rts

print_character:
        jsr lcd_wait
        pha                     ; save A
        lsr                     ; downshift for high nibble
        lsr
        lsr
        lsr
        ora #RS                 ; merge RS/~RWB in to the command
        DISP_SEND_INS_NIBBLE
        pla                     ; restore data
        and #%00001111          ; isolate low nibble
        ora #RS                 ; include #RS
        DISP_SEND_INS_NIBBLE
        inc charsprinted
        rts

lcd_clear:
        lda #%00000001
        jsr lcd_instruction
        rts

lcd_home:
        lda #%00000010
        jsr lcd_instruction
        rts

;;; Helper routine for de-bounce spin to tell the user that
;;; activity is happening.  The low bit of PORTA is connected
;;; to an LED.  This essentially takes bit #5 of X and puts
;;; it out to the LED, for a blinking indicator during the
;;; spin.
update_led_on_x_change:
        php                     ; preserve condition bits
        txa                     ; Grab X
        lsr                     ; >>5
        lsr
        lsr
        lsr
        lsr
        sta PORTA               ; set led per X.bit #5
        plp                     ; restore condition bits
        rts

lcd_initialization:
        ;; LCD owns all of PORTB, but bit 7 is unused. Unclear how we
        ;; might "share" it for others.
        lda #%11111111
        sta DDRB

        ;; Do a delay to let the reset button de-bounce
        ;; 0.2 seconds = 200ms = 20 ticks
        lda #20
        jsr delayticks

        ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        ;; Be clever - to get to 4-bit mode reliably, first go into
        ;; 8-bit mode.  This command does so in both 4-bit parts
        lda #%00110011          ; go to 8-bit mode
        jsr lcd_instruction

        lda #%00000010          ; go to 4-bit mode, with ONE E-cycle
        DISP_SEND_INS_NIBBLE

        ;; Now the LCD should be in 4-bit mode

        lda #%00101000          ; 4-bit/2-line/5x8
        jsr lcd_instruction

        lda #%00001110          ; display on, cursor on, blink off
        jsr lcd_instruction

        lda #%00000110          ; inc/shift cursor, no display shift
        jsr lcd_instruction

        lda #%00000001          ; clear screen
        jsr lcd_instruction
        stz charsprinted

        rts




        ;; This steps on X and A registers
        .macro PRINT_C_STRING,location
        ldx #0
        \start\@$ :
        lda \location,x
        beq \end\@$
        jsr print_character
        inx
        jmp \start\@$
        \end\@$ :
        .endm
