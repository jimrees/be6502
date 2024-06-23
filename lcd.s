;;; Display control bits - where they live on PORTB
E  = %01000000
RW = %00100000
RS = %00010000

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

        ;; used to set position #$40 is useful for going to start of second line
lcd_set_position:
        ora #%10000000
        jsr lcd_instruction
        rts

lcd_initialization:
        ;; LCD owns all of PORTB, but bit 7 is unused. Unclear how we
        ;; might "share" it for others.
        lda #%11111111
        sta DDRB

        ;; Do a delay to let the reset button de-bounce
        ;; 0.2 seconds = 200ms = 20 ticks
        lda #((200 * TIMER_FREQUENCY) / 1000)
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
        .macro PRINT_STRING,location,PRINTER,DELIMITER
        ldx #0
        \start\@$ :
        lda \location,x
        .if \DELIMITER != 0
        cmp #\DELIMITER
        .endif
        beq \end\@$
        jsr \PRINTER
        inx
        jmp \start\@$
        \end\@$ :
        .endm

        .macro PRINT_C_STRING,location,PRINTER
        PRINT_STRING \location,\PRINTER,0
        .endm
        .macro LCD_PRINT_STRING,location,DELIMITER
        PRINT_STRING \location,print_character,\DELIMITER
        .endm
        .macro LCD_PRINT_C_STRING,location
        PRINT_STRING \location,print_character,0
        .endm


print_hex_nibble:
        clc
        cmp #10
        bcs alpha$
        adc #"0"
        jsr print_character
        rts
alpha$:
        adc #("A" - 10 - 1)
        jsr print_character
        rts

;;; A is loaded with a byte, print it
print_hex8:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr print_hex_nibble
        pla
        and #%00001111
        jsr print_hex_nibble
        rts


print_binary8:
        phx
        phy
        ldx #8
pbloop$:
        asl                     ; set the C flag
        tay
        lda #"0"
        adc #0                  ; adds 1 if C is set
        jsr print_character
        tya
        dex
        bne pbloop$
        ply
        plx
        rts

print_n_spaces:
        phx
        tax
loop$:
        lda #" "
        jsr print_character
        dex
        bne loop$

        plx
        rts
