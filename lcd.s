.setcpu "65C02"
.debuginfo +
.feature string_escapes on
.include "via_defs.s"
.include "lcd_defs.s"
.include "bios_defs.s"

;;; Display control bits - where they live on PORTB
E  = %01000000
RW = %00100000
RS = %00010000

.code

;;; lcd_wait should be safe in either 8-bit or 4-bit modes In 8-bit
;;; mode, we are pulling only the high 4 bits anyway (due to how the
;;; lcd is wired from the VIA), and then end up in the low 4 bits of
;;; PORTB - so in 8-bit mode, we're just reading twice and ignoring
;;; the second read.
lcd_wait:
        pha                     ; save A
        phx                     ; save X

        ;; Change pins 0-4 to read
        lda #%00001111
        trb DDRB

        ;; Set up with atomic operations to avoid touching bit7
        lda #(E|RS)             ; clear E & RS
        trb PORTB
        lda #RW                 ; set RW
        tsb PORTB

@lcdbusy:
        lda #E
        tsb PORTB               ; E UP
        ldx PORTB               ; read high nibble
        trb PORTB               ; E DOWN
        tsb PORTB               ; E UP
        trb PORTB               ; E DOWN
        txa
        and #%00001000          ; check busy bit
        bne @lcdbusy

        ;; Change pins 0-4 to write
        lda #%00001111
        tsb DDRB

        plx
        pla
        rts

        ;; If reads were supported, this 3 write sequence would seem
        ;; silly, but in fact it's necessary for the device to be able
        ;; to reliably distinguish reads & writes and we don't end up
        ;; with bus contention.
        ;; The data isn't necessary until the strobe-up, but the RS/RWB
        ;; must be established for at least 40ns.
.macro DISP_SEND_INS_NIBBLE
        tax
        lda #%01111111
        trb PORTB
        txa
        tsb PORTB               ; Set all the bits
        lda #E
        tsb PORTB               ; strobe E up & down
        trb PORTB
.endmacro

lcd_instruction:
        jsr lcd_wait
        phx                     ; save X
        pha                     ; save A
        lsr
        lsr
        lsr
        lsr                     ; move high bit to low
        DISP_SEND_INS_NIBBLE
        pla
        and #%00001111          ; now the low bits
        DISP_SEND_INS_NIBBLE
        plx
        rts

lcd_print_character:
        jsr lcd_wait
        phx
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
        plx
        rts

lcd_print_string:
        sta tmp0
        sty tmp1
        ldy #0
@loop:
        lda (tmp0),y
        beq @end_of_string
        jsr lcd_print_character
        iny
        jmp @loop
@end_of_string:
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
        ;; LCD owns PORTB 0..6, set them all to write
        lda #%01111111
        tsb DDRB

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

        rts

        ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        .macro CMP_IF_NONZERO DELIMITER
        .if DELIMITER = 0
        .else
        cmp #DELIMITER
        .endif
        .endmacro

        ;; This steps on X and A registers
        .macro PRINT_STRING location, PRINTER, DELIMITER
        .local start
        .local end
        ldx #0
        start:
        lda location, x
        CMP_IF_NONZERO DELIMITER
        beq end
        jsr PRINTER
        inx
        jmp start
        end:
        .endmacro

lcd_print_hex_nibble:
        clc
        cmp #10
        bcs @alpha
        adc #'0'
        jsr lcd_print_character
        rts
@alpha:
        adc #('A' - 10 - 1)
        jsr lcd_print_character
        rts

;;; A is loaded with a byte, print it
lcd_print_hex8:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr lcd_print_hex_nibble
        pla
        and #%00001111
        jsr lcd_print_hex_nibble
        rts

lcd_print_binary8:
        phx
        phy
        ldx #8
@pbloop:
        asl                     ; set the C flag
        tay
        lda #'0'
        adc #0                  ; adds 1 if C is set
        jsr lcd_print_character
        tya
        dex
        bne @pbloop
        ply
        plx
        rts


lcd_print_n_spaces:
        phx
        tax
@loop:
        lda #' '
        jsr lcd_print_character
        dex
        bne @loop

        plx
        rts
