PORTB = $6000
PORTA = $6001
DDRB = $6002
DDRA = $6003
E  = %10000000
RW = %01000000
RS = %00100000

        .macro LCD_INSTRUCTION
        sta PORTB
        lda #0
        sta PORTA
        lda #E
        sta PORTA
        lda #0
        sta PORTA
        .endm

        .macro PRINT_CHARACTER
        sta PORTB
        lda #RS
        sta PORTA
        lda #(E|RS)
        sta PORTA
        lda #RS
        sta PORTA
        .endm

        .org $8000

reset:
        ldx #$ff
        txs

        ;; Set the data direction bits for the ports
        lda #%11111111
        sta DDRB
        lda #%11100000
        sta DDRA

        lda #%00111000          ; 8-bit,2 lines, 2lines, 5x8 font
        LCD_INSTRUCTION

        lda #%00001110          ; display on, cursor on, blink off
        LCD_INSTRUCTION

        lda #%00000110          ; inc/shift cursor, no display shift
        LCD_INSTRUCTION

        ; lda #%00000001          ; clear screen
        ; LCD_INSTRUCTION

        lda #"H"
        PRINT_CHARACTER

        lda #"e"
        PRINT_CHARACTER

        lda #"l"
        PRINT_CHARACTER

        lda #"l"
        PRINT_CHARACTER

        lda #"o"
        PRINT_CHARACTER

        lda #" "
        PRINT_CHARACTER

        lda #"W"
        PRINT_CHARACTER

        lda #"o"
        PRINT_CHARACTER

        lda #"r"
        PRINT_CHARACTER

        lda #"l"
        PRINT_CHARACTER

        lda #"d"
        PRINT_CHARACTER

        lda #"!"
        PRINT_CHARACTER

loop:
        jmp loop

        .org $fffc
        .word reset
        .word $0000
