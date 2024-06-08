;;; Versatile Interface Adapter mapped addresses
PORTB = $6000
PORTA = $6001
DDRB = $6002
DDRA = $6003
PCR = $600C       ; [ CB2{3} | CB1{1} | CA2{3} | CA1{1} | PCR ]
IFR = $600D       ; [ IRQ TIMER1 TIMER2 CB1 CB2 SHIFTREG CA1 CA2 ]
IER = $600E       ; [ Set/Clr TIMER1 TIMER2 CB1 CB2 SR CA1 CA2 ]
;;; Pre-allocate storage for decimal formatter
value = $0200
mod10 = $0202
counter = $0204

;;; Display control bits - where they live on PORTB
E  = %01000000
RW = %00100000
RS = %00010000

;;; The rom is mapped to start at $8000
        .org $8000

;;; The test value of the number to print in decimal
number:  .word 31415

;;; String to display on LCD.  Note padding to 40 characters - this
;;; is how to wrap around to the second row.
message:        asciiz "Hello, world!                           "

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

reset:
        lda #0
        sta counter
        sta counter + 1

        ;; Set the data direction bits for the ports
        lda #%11111111
        sta DDRB

        lda #%00000001          ; only an LED on PORTA-0 currently
        sta DDRA

        ;; Do a delay spin to let the reset button de-bounce
        ;; before hitting the LCD with commands.
        ;; 0x7f * 0xff = 32385 repetitions * minium 5 cycles per iteration
        ;; at 1MHz, ~0.2 seconds
        ldx #$7f
        jsr update_led_on_x_change ; blink LED
        ldy #$ff
spin:
        dey                     ; 2 cycles
        bne spin                ; 3 cycles - branch is taken
        dex
        jsr update_led_on_x_change ; blink LED
        bne spin

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

        lda #%00000000
        sta PCR                 ; negative active edge for CA1

        lda #%10000010          ; enable CA1 interrupts
        sta IER
        cli
loop:
        lda #%00000010          ; home
        jsr lcd_instruction

        ;; Print the message, it's too bad there's no obvious
        ;; way to pass an address of a message to a general print
        ;; routine - the address byte could be stored on the stack
        ;; I suppose, and consumed by the routine?
        ldx #0
mloopstart:
        lda message,x
        beq mloopend
        jsr print_character
        inx
        jmp mloopstart
mloopend:

        ;; Print number in decimal
        ;; Initialize value to the number to be converted
        ;; Grab counter *atomically* with interrupts disabled
        ;; so we only get a consistent value
        sei                     ; disable interrupts
        lda counter
        ldy counter + 1
        cli                     ; re-enable interrupts
        sta value
        sty value + 1
        lda #0                  ; push a null char on the stack
        pha

divide:
        ;; Initialize remainder to zero
        lda #0
        sta mod10
        sta mod10 + 1
        clc

        ldx #16
divloop:
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
        bcc ignore_result       ; dividend < divisor
        sty mod10
        sta mod10 + 1
ignore_result:
        dex
        bne divloop

        rol value               ; final rotate
        rol value+1

        lda mod10

        clc
        adc #"0"
        pha

        ;; are we done?
        lda value
        ora value+1
        bne divide

        pla                     ; we know there's at least one
unfold_print_loop:
        jsr print_character
        pla                     ; pop the next one
        bne unfold_print_loop   ; if not-null, keep looping

        jmp loop

nothing_more_to_do:
        jmp nothing_more_to_do

nmi:
        inc counter
        bne exit_nmi
        inc counter + 1
exit_nmi:
        rti

irq:
        phx
        phy

        inc counter
        bne exit_irq
        inc counter + 1
exit_irq:

        ldy #$6f
        ldx #$ff
debounce_delay:
        dex
        bne debounce_delay
        dey
        bne debounce_delay

        bit PORTA               ; clears the interrupt?
        ply
        plx
        rti

        ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;; The interrupt & reset vectors
        .org $fffa
        .word nmi
        .word reset
        .word irq
