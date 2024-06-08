
        .org $8000

reset:  lda #$ff
        sta $6002
        lda #$50
loop:
        sta $6000
        ror
        jmp loop

        .org $fffc
        .word reset
        .word $0000
