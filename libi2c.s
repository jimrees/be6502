;;; Compliments from whoever I snarfed this code from on the internet.
;;; I have trimmed it down a lot to save cycles.
.setcpu "65C02"
.feature string_escapes on
.include "via_defs.s"
.include "libi2c_defs.s"
.include "macros.s"

.zeropage
ZP_I2C_DATA:    .res 1

.code

;;;------------------------------------------------------------------------------
.macro i2c_data_up
;;;------------------------------------------------------------------------------
;;; Destroys A
;;;------------------------------------------------------------------------------
        lda   #I2C_DATABIT  ; Clear data bit of the DDR
        trb   I2C_DDR       ; to make bit an input and let it float up.
.endmacro

;;;------------------------------------------------------------------------------
.macro i2c_data_down
;;;------------------------------------------------------------------------------
;;; Destroys A, 8 cycles
;;;------------------------------------------------------------------------------
        lda   #I2C_DATABIT  ; Set data bit of the DDR
        tsb   I2C_DDR       ; to make bit an output and pull it down.
.endmacro

;;;------------------------------------------------------------------------------
.macro i2c_clock_up
;;;------------------------------------------------------------------------------
;;; Destroys A, 8 cycles
;;;------------------------------------------------------------------------------
        lda   #I2C_CLOCKBIT     ; 2 cycles
        trb   I2C_DDR           ; 6 cycles
.endmacro


;;;------------------------------------------------------------------------------
.macro i2c_clock_down
;;;------------------------------------------------------------------------------
;;; Destroys A, 8 cycles
;;;------------------------------------------------------------------------------
        lda   #I2C_CLOCKBIT     ; +2
        tsb   I2C_DDR           ; +6
.endmacro

;------------------------------------------------------------------------------
    .macro i2c_clock_pulse
;------------------------------------------------------------------------------
;;; Destroys A
;------------------------------------------------------------------------------
.if 0
        ;; 16 cycle version - same as the third here below
        i2c_clock_up
        i2c_clock_down
.elseif 1
        ;; 14 cycles
        lda #I2C_CLOCKBIT       ; 2
        trb I2C_DDR             ; 6
        tsb I2C_DDR             ; 6
.else
        lda   I2C_DDR                ; 4 cycles
        and   #(~I2C_CLOCKBIT & $ff) ; CLOCK UP +2 = 6
        sta   I2C_DDR                ; +4 = 10
        ora   #I2C_CLOCKBIT          ; CLOCK DOWN +2 = 12
        sta   I2C_DDR                ; +4 = 16 ;-(
.endif
.endmacro

;------------------------------------------------------------------------------
    .macro A_bit_to_C MASK
;------------------------------------------------------------------------------
;;; Destroys A
;;; Returns next input in C
;;; It shifts A the # times needed to move the correct bit from A into C.
;;; It is assumed MASK is a power of two, or zero
;------------------------------------------------------------------------------
.if MASK == 0
.else
.if MASK <= 8
        lsr                     ; +2
        A_bit_to_C (MASK/2)
.else
        asl
        A_bit_to_C ((MASK*2)&255)
.endif
.endif

;------------------------------------------------------------------------------
    .macro i2c_input_bit_to_C
;------------------------------------------------------------------------------
;;; Destroys A, N, Z
;;; Returns next input in C
;;; It shifts A the # times needed to move the database into C.
;------------------------------------------------------------------------------
        lda I2C_PORT            ; +4
        A_bit_to_C I2C_DATABIT  ; +2=6, for I2C_DATABIT==1
.endmacro

;------------------------------------------------------------------------------
I2C_SendAck:
;------------------------------------------------------------------------------
;;; Destroys A
;------------------------------------------------------------------------------
        i2c_data_down       ; Acknowledge.  The ACK bit in I2C is the 9th bit of a "byte".
        i2c_clock_pulse     ; Trigger the clock
        i2c_data_up         ; End with data up
        rts

;------------------------------------------------------------------------------
I2C_SendNak:
;------------------------------------------------------------------------------
;;; Destroys A
;------------------------------------------------------------------------------
.if 0
        i2c_data_up         ; Acknowledging consists of pulling it down. +8
        i2c_clock_pulse     ; Trigger the clock +16
        ;; i2c_data_up - would be superfluous, though it puts DATABIT in the A reg
.else
        ;; Saves 2 cycles
        lda I2C_DDR                ; +4
        and #(~I2C_DATABIT & $ff) ; data up +2
        sta I2C_DDR               ; +4
        and #(~I2C_CLOCKBIT & $ff) ; CLOCK UP +2
        sta I2C_DDR                ; +4
        ora #I2C_CLOCKBIT          ; CLOCK DOWN +2
        sta I2C_DDR                ; +4
.endif
        rts

;------------------------------------------------------------------------------
I2C_ReadAck:
;------------------------------------------------------------------------------
;;; Returns Ack in carry flag (clear means ack, set means nak)
;;; Destroys A
;------------------------------------------------------------------------------
        i2c_data_up             ; +8
        i2c_clock_up            ; +8
        i2c_input_bit_to_C      ; +6
        i2c_clock_down      ; Bring the clock down, +8, 30 + 12
        rts


;;;------------------------------------------------------------------------------
I2C_Init:
;;;------------------------------------------------------------------------------
;;; This will correctly preserve ORA/ORB for other devices, but it will also
;;; drive pins that perhaps should not be driven - but only for 10 cycles.
;;; The BIOS could use a facility to manage ORA/ORB values.
;;;------------------------------------------------------------------------------
        ;; power-on for the 6522 is zero for ORA and DDR.  We should be fine.
        ;; But since this code might be called in cases other than hw reset...
        lda #(I2C_CLOCKBIT|I2C_DATABIT)
        trb I2C_DDR             ; release and GO HIGH
        jsr I2C_Clear
        rts

;;;------------------------------------------------------------------------------
I2C_Clear:
;;;------------------------------------------------------------------------------
;;; This clears any unwanted transaction that might be in progress, by giving
;;; enough clock pulses to finish a byte and not acknowledging it.
;;; Destroys  A
;;;------------------------------------------------------------------------------
        phx                     ; Save X
        M_I2C_Start
        M_I2C_Stop
        i2c_data_up ; Keep data line released so we don't ACK any byte sent by a device.
        ldx #9 ; Loop 9x to send 9 clock pulses to finish any byte a device might send.
        lda #I2C_CLOCKBIT
@do:
        trb I2C_DDR             ; Clock up
        tsb I2C_DDR             ; Clock down
        dex
        bne @do
        plx                     ; Restore X
        M_I2C_Start
        M_I2C_Stop
        rts

;;;------------------------------------------------------------------------------
I2C_SendByte:
;;;------------------------------------------------------------------------------
;;; Sends the byte in A
;;; Returns the Ack in C (clear means ack, set means nak)
;;; Preserves A,X,Y - sets C
;;;------------------------------------------------------------------------------
        pha                     ; +3

        ;; only the DDR is manipulated
        ;; change the databit, write to port
        ;; change the clock bit (if needed)
        ;; change it back

        sta ZP_I2C_DATA         ; stash +3
        lda I2C_DDR             ; pre-fetch

.macro SENDONEBIT
.local send_zero
.local do_pulse
        asl ZP_I2C_DATA             ; +5
        bcc send_zero               ; +2/3
        and #(~I2C_DATABIT & #xff)  ; +2
        sta I2C_DDR                 ; +4
        bra do_pulse                ; +2/3
send_zero:
        ora #I2C_DATABIT            ; +2
        sta I2C_DDR                 ; +4
do_pulse:
        and #(~I2C_CLOCKBIT & #xff) ; +2
        sta I2C_DDR                 ; +4
        ora #I2C_CLOCKBIT           ; +2
        sta I2C_DDR                 ; +4
.endmacro

        DOTIMES 8,SENDONEBIT
        ;; Now to read the ACK, release the dataline, then pulse the clock
        and #(~I2C_DATABIT & #xff)  ; release, as if sending 1
        sta I2C_DDR
        and #(~I2C_CLOCKBIT & #xff) ; +2
        sta I2C_DDR                 ; +4
        i2c_input_bit_to_C          ; +6
        lda I2C_DDR
        ora #I2C_CLOCKBIT           ; clock down
        sta I2C_DDR

        pla                     ; +4
        rts                     ;

;;;------------------------------------------------------------------------------
I2C_ReadByte:
;;;------------------------------------------------------------------------------
;;; Start with clock low.  Ends with byte in A.  Do ACK separately.
;;;------------------------------------------------------------------------------
        ;; data must already be up
        ;; i2c_data_up             ; Make sure we're not holding the data line down.
        lda #I2C_CLOCKBIT       ; +2 Load the clock bit in for initial loop
.macro RB_SINGLESTEP
        trb I2C_DDR             ; clock up, +6
        i2c_input_bit_to_C      ; +6
        rol ZP_I2C_DATA         ; +5
        i2c_clock_down          ; +8 guarantees I2C_CLOCKBIT in A again, 25 total
.endmacro
        DOTIMES RB_SINGLESTEP,8 ; +25*8 = 202
        lda ZP_I2C_DATA         ; +4=206 Load A from local
        rts                     ; ?

;;;------------------------------------------------------------------------------
I2C_ReadHi4:
;;;------------------------------------------------------------------------------
;;; Start with clock low.  Ends with bits in low part of A.  Do ACK separately.
;;;------------------------------------------------------------------------------
        ;; the thing prior to ReadHi4 was either a previous NAK or a previous
        ;; ack by the slave of the address.   In both cases, data line must be
        ;; up - so there's no need to do it again.
        lda #I2C_CLOCKBIT       ; +2 Pre-load the clock bit in for initial loop
        DOTIMES RB_SINGLESTEP,4 ; +4*25=102

.if 1
        phx                        ; +3
        lda I2C_DDR                ; +4=106
        and #(~I2C_CLOCKBIT & $ff) ; +2=108
        tax                        ; +2=110
        sta I2C_DDR                ; +4=114
        stx I2C_DDR                ; +4=118
        sta I2C_DDR                ; +4=122
        stx I2C_DDR                ; +4=126
        sta I2C_DDR                ; +4=130
        stx I2C_DDR                ; +4=134
        sta I2C_DDR                ; +4=138
        stx I2C_DDR                ; +4=142
        plx                        ; +4=149
.else
        trb I2C_DDR
        tsb I2C_DDR
        trb I2C_DDR
        tsb I2C_DDR
        trb I2C_DDR
        tsb I2C_DDR
        trb I2C_DDR
        tsb I2C_DDR             ; +6x8 = 150
.endif
        lda ZP_I2C_DATA         ; +3=152 Load A from local
        rts

;;;------------------------------------------------------------------------------
I2C_SendAddr:
;;;------------------------------------------------------------------------------
;;; Address in A, carry flag contains read/write flag (read = 1, write 0)
;;; Return ack in Carry
;;;------------------------------------------------------------------------------
        rol A                   ; Rotates address 1 bit and puts read/write flag in A
        jmp I2C_SendByte        ; Sends address and returns
