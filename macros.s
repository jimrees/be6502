.ifndef REES_MACROS_H
        REES_MACROS_H := 1

.macro DOTIMES OP,n
.if n = 0
.else
.if (n .MOD 2) = 0
        DOTIMES OP,(n/2)
        DOTIMES OP,(n/2)
.else
        OP
        DOTIMES OP,(n/2)
        DOTIMES OP,(n/2)
.endif
.endif
.endmacro

.macro NOPS n
        DOTIMES nop,n
.endmacro

.macro SPIN_WHILE_BIT_SET LOCATION, BIT
.local @loop
.if BIT = 7
@loop:
        bit LOCATION
        bmi @loop
.else
.if BIT = 6
@loop:
        bit LOCATION
        bvs @loop
.else
        lda #(1<<BIT)
@loop:
        bit LOCATION
        bne @loop
.endif
.endif
.endmacro

.macro SPIN_WHILE_BIT_CLEAR LOCATION, BIT
.local @loop
.if BIT = 7
@loop: bit LOCATION
        bpl @loop
.else
.if BIT = 6
@loop:
        bit LOCATION
        bvc @loop
.else
        lda #(1<<BIT)
@loop:
        bit LOCATION
        beq @loop
.endif
.endif
.endmacro

.macro MULTIPLY_BY N,DST
.if N=1
.else
.if (N .MOD 2)=0
        asl DST
        rol DST+1
        MULTIPLY_BY N/2,DST
.else
        lda DST+1
        pha
        lda DST
        pha
        MULTIPLY_BY (N -1),DST
        pla
        clc
        adc DST
        sta DST
        pla
        adc DST+1
        sta DST+1
.endif
.endif
.endmacro
.endif
