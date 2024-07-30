.setcpu "65C02"
.feature string_escapes on
.include "syscall_defs.s"
        ALLSYSCALL .global

.include "macros.s"
.include "via_defs.s"

        TICK_COUNTER = 4

.zeropage
TMP_PTR:         .res 2
SAVED_RET:        .res 2

.macro SERIAL_PSTR name
        lda #< name
        ldy #> name
        jsr STROUT
.endmacro

.code

;;;
;;; Unrelated test program for verifying the cycle counts of
;;; various opcodes.
;;;
.macro BNE_TAKEN
.local foof
        bne foof
foof:
.endmacro
.macro BEQ_NOT_TAKEN
.local foof
        beq foof
foof:
.endmacro
.macro JSR_M
.local foof
        jsr foof
foof:
.endmacro
.macro JMP_M
.local foof
        jmp foof
foof:
.endmacro
.macro SBC_M_GEN
        sbc T1CH
.endmacro

.macro ASL_ZP_GEN
        asl TMP_PTR
.endmacro

.macro NOP_GEN
        nop
.endmacro

.macro TIME_IT GEN, COUNT, MESSAGE
.local wait_for_thirty_eight
        ;; pha - 3 cycles
        ;; pla - 4 cycles
        ;; {lda,sta} ZP - 3 cycles
        ;; {lda,sta} GEN - 4 cycles
        ;; {tsb,trb} GEN - 6 cycles, presumbly 5 cycles for a zp read-modify-write
        ;; asl ZP
        ;; {cli,sei,sec,clc} - 2 cycles
        ;; {and #foo} - 2 cycles
        ;; jsr by itself, 6 cycles
        ;; {jsr/rts combo} - 12 cycles
        ;; jmp - 3 cycles
        ;; bne - taken 3 cycles
        ;; beq - not taken 2 cycles

        ;; Pull the return address and stash it somewhere safe
        pla
        sta SAVED_RET
        pla
        sta SAVED_RET+1

        lda #38
        sta TMP_PTR+1
wait_for_thirty_eight:
        cmp T1CH
        bne wait_for_thirty_eight
        lda T1CL
        sta TMP_PTR             ; +4

        lda #1
        sec
        DOTIMES GEN,COUNT

        sec                     ; +2
        lda TMP_PTR             ; +4
        sbc T1CL                ; +4
        sta value
        lda TMP_PTR+1
        sbc T1CH
        sta value+1

        SERIAL_PSTR MESSAGE
        jsr serial_print_value_in_decimal
        jsr SERIAL_CRLF

        ;; Restore the return address on the stack
        lda SAVED_RET+1
        pha
        lda SAVED_RET
        pha
.endmacro

start:
        TIME_IT ASL_ZP_GEN, 1000, aslmessage
        TIME_IT NOP_GEN, 1000, nopmessage
        TIME_IT SBC_M_GEN, 1000, sbcmessage
        brk                     ; return to WOZMON

aslmessage:     .asciiz "ASL: "
nopmessage:     .asciiz "NOP: "
sbcmessage:     .asciiz "SBC: "

serial_print_value_in_decimal:
        ;; push digits onto the stack, then unwind to print
        ;; the in the right order.
        lda #0                  ; push a null char on the stack
        pha
@next_digit:
        jsr divide_by_10
        lda mod10
        clc
        adc #'0'
        pha
        ;; If any part of the quotient is > 0, go again.
        lda value
        ora value+1
        bne @next_digit
        pla
@unfold_print_loop:
        jsr CHROUT
        pla                     ; pop the next one
        bne @unfold_print_loop  ; if not-null, keep looping
        rts
