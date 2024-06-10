        .macro DOTIMES,OP,n
        .if \n == 0
        .else
        .if (\n % 2) == 0
        DOTIMES \OP,(\n/2)
        DOTIMES \OP,(\n/2)
        .else
        \OP
        DOTIMES \OP,(\n/2)
        DOTIMES \OP,(\n/2)
        .endif
        .endif
        .endm

        .macro NOPS,n
        DOTIMES nop,\n
        .endm

        .macro SPIN_WHILE_BIT_SET, LOCATION, BIT
        .if \BIT == 7
        \@$ : bit \LOCATION
        bmi \@$
        .else
        .if \BIT == 6
        \@$ : bit \LOCATION
        bvs \@$
        .else
        lda #(1<<\BIT)
        \@$ : bit \LOCATION
        bne \@$
        .endif
        .endif
        .endm

        .macro SPIN_WHILE_BIT_CLEAR, LOCATION, BIT
        .if \BIT == 7
        \@$ : bit \LOCATION
        bpl \@$
        .else
        .if \BIT == 6
        \@$ : bit \LOCATION
        bvc \@$
        .else
        lda #(1<<\BIT)
        \@$ : bit \LOCATION
        beq \@$
        .endif
        .endif
        .endm
