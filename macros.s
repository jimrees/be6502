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


        .macro MULTIPLY_BY,N,DST
        .if \N==1
        .else
        .if (\N %2)==0
        asl \DST
        rol \DST+1
        MULTIPLY_BY \N/2,\DST
        .else
        lda \DST+1
        pha
        lda \DST
        pha
        MULTIPLY_BY (\N -1),\DST
        pla
        clc
        adc \DST
        sta \DST
        pla
        adc \DST+1
        sta \DST+1
        .endif
        .endif
        .endm
