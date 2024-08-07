;;;
;;; Based on the following obfuscated C code which emits a
;;; "Christmas Tree".
;;;
;;; int a[4<<9],i;main(){for(a[40]=1;i++<1620;printf(i%80?"%c":"\n"," .oO"
;;; [a[i]&3]),a[i+79]+=a[i],a[i+81]+=a[i])a[1304]=a[1336]=0;}
;;;
.setcpu "65C02"
.export repeat
.include "syscall_defs.s"
        ALLSYSCALL .global
.bss
.align $100
Array:       .res $800

.zeropage
i_index:   .res 2
addr0:     .res 2
addr2:     .res 2

.macro INDEX_TO_ADDRESS ADDR
        lda i_index
        sta ADDR
        lda i_index+1
        clc
        adc #>Array
        sta ADDR+1
.endmacro

;;; I is a constant
.macro SET_AT_INDEX I, VALUE
        lda #<(Array+I)
        sta addr0
        lda #>(Array+I)
        sta addr0+1
        lda #VALUE
        sta (addr0)
.endmacro

.macro CLEAR_AT_INDEX I
        SET_AT_INDEX I,0
.endmacro

.code
.import __BSS_RUN__, __BSS_SIZE__

start:
        jsr dotree
        jmp WOZSTART

dotree:
        jsr SERIAL_CRLF

        ;; Zero out $800 bytes, or $8 pages
        lda #<__BSS_RUN__
        sta addr0
        lda #>__BSS_RUN__
        sta addr0+1

        ldx #>__BSS_SIZE__
        ldy #0
        lda #0
@clearloop:
        sta (addr0),y
        dey
        bne @clearloop
        inc addr0+1              ; up the page component of the stored address
        dex
        bne @clearloop

        ldy #<__BSS_SIZE__
        beq @skiplsbloop
@clearlsbloop:
        sta (addr0),y
        dey
        bne @clearlsbloop
@skiplsbloop:

        ;; I = 0
        stz i_index
        stz i_index+1

        SET_AT_INDEX 40,1

mainloop:
        ;; if i >= 1620 then exit
        lda i_index
        sec
        sbc #<1620
        lda i_index+1
        sbc #>1620
        bcc @stay_in_loop
        jmp @all_done

@stay_in_loop:
        ;; (set! i (+ i 1))
        clc
        lda i_index
        adc #1
        sta i_index
        lda i_index+1
        adc #0
        sta i_index+1

        ;; (vector-set! a 1304 0)
        ;; (vector-set! a 1336 0)
        CLEAR_AT_INDEX 1304
        CLEAR_AT_INDEX 1336

        ;; i%80 == 0 ?
        ;; Since we know i does not exceed 1620, we can do ... 11 bits only
        lda i_index
        sta addr0
        lda i_index+1
        sta addr0+1

        ;; Shift up 5 times
        asl addr0
        rol addr0+1
        asl addr0
        rol addr0+1
        asl addr0
        rol addr0+1
        asl addr0
        rol addr0+1
        asl addr0
        rol addr0+1

        lda #0                  ; accum
        ldx #11                 ; 11 bits
@modloop:
        asl                     ; residue *= 2
        ;; shift left the value in addr0
        asl addr0
        rol addr0+1
        adc #0                  ; residue += carry
        cmp #80
        bcc @no_sub_needed
        sec
        sbc #80
@no_sub_needed:
        dex
        bne @modloop

        tax                     ; get Z bit set from A
        beq @eighty_columns     ; If we are at 80 columns, newline

        ;; (vector-ref a i)
        INDEX_TO_ADDRESS addr0

        ;; (bitwise-and ... 3)
        lda (addr0)
        and #3

        ;; (vector-ref *character-vector* ...)
        tax
        lda chars,x

        ;; (write-char ...)
        jsr CHROUT
        jmp @accum_steps

@eighty_columns:
        jsr SERIAL_CRLF

@accum_steps:

        lda #79
        jsr accum_step
        lda #81
        jsr accum_step
        jmp mainloop

@all_done:
        jsr SERIAL_CRLF
        rts

accum_step:
        ;;
        ;; (let ((j (+ i A)))
        ;;    (vector-set! a j (+ (vector-ref a j) (vector-ref a i))))
        ;;

        ;; Set up the J address first, since we have A ready to add
        clc
        adc i_index
        sta addr2
        lda i_index+1
        adc #>Array
        sta addr2+1

        ;; Now do the I address
        lda i_index
        sta addr0
        lda i_index+1
        clc
        adc #>Array
        sta addr0+1

        ;; Add A[i] to A[j]
        clc
        lda (addr0)
        adc (addr2)
        sta (addr2)

        rts

.align $100
repeat:
        jsr dotree

        inc chars+1
        inc chars+2
        inc chars+3

        jsr ANYCNTC
        bne repeat
        jmp WOZSTART


chars:     .byte " .oO"
