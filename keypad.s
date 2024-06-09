;;;
;;; Keypad - using the 4x4 membrane pad that came with the raspberrypi tutorial kit
;;; The 8 signals are wired to PORTA, all are pulled high with 1K resistors.
;;; The timer interrupts are used to do matrix scans once every 62ms.
;;; The scan code is nasty
;;;

;;; Versatile Interface Adapter mapped addresses
PORTB = $6000
PORTA = $6001
DDRB = $6002
DDRA = $6003
T1CL = $6004
T1CH = $6005
T1LL = $6006
T1LH = $6007
ACR = $600B
PCR = $600C       ; [ CB2{3} | CB1{1} | CA2{3} | CA1{1} | PCR ]
IFR = $600D       ; [ IRQ TIMER1 TIMER2 CB1 CB2 SHIFTREG CA1 CA2 ]
IER = $600E       ; [ Set/Clr TIMER1 TIMER2 CB1 CB2 SR CA1 CA2 ]
;;; Pre-allocate storage for decimal formatter
value = $0200
mod10 = $0202
counter = $0204
timercount = $0206
bigloopcounter = $0208
clicksuntilca1_reenable = $00   ; 1 byte allocate from zeropage

;;; One byte State 0: whatever we read gets printed, and we move to state 1.  If no
;;; buttons were pressed, we stay in state 0 State 1: scan, if nothing down, move
;;; to state 2, else stay in state 1 State 2: scan, if nothing down, move to state
;;; 0, else move to state 1 (if we need more states, they behave just like state 2)
numericpadstate = $01

;;; Temporary variable needed because 3 registers is not enough
bitvar = $02
columnmask = $03

;;; Track how many chars printed.  When we reach 16, then switch to scrolling
;;; mode.  That has other weird side effects on the two rows.
charsprinted = $04

;;; Display control bits - where they live on PORTB
E  = %01000000
RW = %00100000
RS = %00010000

        .macro PRINT_DEC16,address
        sei
        lda \address
        ldy \address + 1
        cli
        sta \value
        sty \value + 1
        jsr print_value_in_decimal
        .endm

;;; The rom is mapped to start at $8000
        .org $8000

;;; String to display on LCD.  Note padding to 40 characters - this
;;; is how to wrap around to the second row.
;;; message:        asciiz "Hello, world!                           "

rc_chars:        .byte "147*2580369#ABCD"

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
        pha
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

        lda charsprinted
        inc
        sta charsprinted
        cmp #16
        bne pc_done
        ;; turn on display shift
        lda #%00000111          ; inc/shift cursor, display shift
        jsr lcd_instruction
pc_done:
        pla                     ; preserve argument
        rts

;;; value must contain the number
;;; A,X,Y will all be trashed.
print_value_in_decimal:
        lda #0                  ; push a null char on the stack
        pha

divide_do:
        ;; Initialize remainder to zero
        stz mod10
        stz mod10 + 1
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
        bne divide_do

        pla                     ; we know there's at least one
unfold_print_loop:
        jsr print_character
        pla                     ; pop the next one
        bne unfold_print_loop   ; if not-null, keep looping

        rts

lcd_initialization:
        ;; Do a delay spin to let the reset button de-bounce
        ;; before hitting the LCD with commands.
        ;; 0x7f * 0xff = 32385 repetitions * minium 5 cycles per iteration
        ;; at 1MHz, ~0.2 seconds
        ldx #$7f
        ldy #$ff
spin:
        dey                     ; 2 cycles
        bne spin                ; 3 cycles - branch is taken
        dex
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
        stz charsprinted

        rts

reset:
        stz counter
        stz counter + 1
        stz timercount
        stz timercount + 1
        stz bigloopcounter
        stz bigloopcounter + 1
        stz clicksuntilca1_reenable
        stz clicksuntilca1_reenable + 1
        stz numericpadstate
        stz charsprinted

        ;; Set the data direction bits for the ports
        lda #%11111111
        sta DDRB

        jsr lcd_initialization

        ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        lda #%00000000
        sta PCR                 ; negative active edge for CA1

        ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;; Set up Timer
        lda #$ff                ; populate timer1 counter & latches to 65535
        sta T1CL                ; At 1Mhz, this means ~16/second
        sta T1CH
        sta T1LL
        sta T1LH

        lda #%11000000          ; set timer1 for continuous interrupts + PB7
        sta ACR

        lda #%11000000          ; enable Timer1 interrupts
        sta IER

        cli
        ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        lda #%11110000          ; assert columns, not rows
        sta DDRA

loop:
        ;; Pins 0..3 rows
        ;; Pins 4..7 columns
        ;; The idea is that if we assert low on ONE column bit
        ;; then wherever a row's bit is reading low, that intersection
        ;; is a pressed button.
        ;; It turns out we can set DDRA once, with all columns asserted
        ;; and all rows passive.
        ;; All bits are pulled high by resistors, though now I realize
        ;; I can yank the ones for the columns because I'm always driving
        ;; them.

        ;; pre-push a null char
        ldx #0
        phx
        ;; Set up the initial column mask, with ONE bit low
        lda #%11101111          ; column 0 setup, a single 0 bit
        sta columnmask

column_loop:
        lda columnmask
        sta PORTA               ; assert just the one bit low

        ldy #4                  ; set up loop counter
        lda PORTA               ; read the state
        sta bitvar              ; save in bitvar (we are out of registers)
row_loop:
        ror bitvar              ; Move the next bit into carry
        bcs not_pressed         ; if carry set, then this key is not pressed
        lda rc_chars,x          ; else fetch the char and push
        pha
not_pressed:
        inx                     ; increment the index
        dey                     ; decrement the 4-bit counter
        bne row_loop            ; ..and loop

        rol columnmask          ; shift the mask left
        bcs column_loop         ; when the zero hits carry, we're done

        ;; Now process what we scanned, depending on the current
        ;; state.
        ;; Do decide that "1" is followed by another "1", we need
        ;; to see that "1" not pressed in at least 1 cycle.
        ;; If debouncing is an issue, we may need more than 1 cycle.
        ;; This algorithm requires the whole pad to scan empty
        ;; to be able to promote into the next state value, else
        ;; return to state 1 waiting for an empty scan.

        lda numericpadstate
        bne not_state_0
        pla
        beq skip_print          ; and stay in state0
unfold_print_loop2:
        jsr print_character
        pla
        bne unfold_print_loop2
        lda #1
        sta numericpadstate
        jmp skip_print
not_state_0:
        pla
        beq promote_to_higher_state
unfold_noprint_loop:
        pla
        bne unfold_noprint_loop
        lda #1
        sta numericpadstate     ; go back to state 1
        jmp skip_print
promote_to_higher_state:
        lda numericpadstate
        inc
        and #1                  ; goes to 0 after 1
        sta numericpadstate
skip_print:
        ;; Do scans once every timer interrupt
        wai
        jmp loop

nmi:
        rti

irq:
        pha

        ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;; Check if the ca1 bit is set in BOTH the conditions and enables
        lda #%00000010
        and IFR                 ; condition
        and IER                 ; enabled
        beq ca1_done            ; skip this section if not

        inc counter             ; increment counter
        bne counter_nr
        inc counter + 1
counter_nr:

        lda #%00000010          ; debounce method - disable this interrupt
        sta IER
        lda #3
        sta clicksuntilca1_reenable

ca1_done:

        ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        lda #%01000000          ; check if timer1 is active
        bit IFR                 ; and with current conditions
        beq t1_done             ; skip if not
        bit T1CL                ; clear condition

        lda clicksuntilca1_reenable ; are we pending a re-enable?
        beq skip_reenable           ; skip if not
        dec clicksuntilca1_reenable ; now re-enable?
        bne skip_reenable           ; skip if not
        lda #%10000010              ; re-enable
        bit PORTA                   ; clear the condition if it exists
        sta IER                     ; and enable
skip_reenable:

        inc timercount          ; Increment timer counter
        bne t1_done
        inc timercount + 1
t1_done:

        pla                     ; restore & return
        rti

        ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;; The interrupt & reset vectors
        .org $fffa
        .word nmi
        .word reset
        .word irq
