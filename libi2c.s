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
        lda   #I2C_CLOCKBIT
        tsb   I2C_DDR
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
;;; Ack in carry flag (clear means ack, set means nak)
;;; Destroys A
;------------------------------------------------------------------------------
        i2c_data_up             ; +8
        i2c_clock_up            ; +8
.if I2C_DATABIT = 1
        ;; Saves 5 or 6 cycles
        ;; databit ==> C
        lda I2C_PORT            ; +4
        ror                     ; +2
.else
        clc                 ; Clear the carry +2
        lda I2C_PORT        ; Load data from the port +4
        and #I2C_DATABIT    ; Test the data bit +2
        beq @skip           ; If zero skip +{2,3}
        sec                 ; Set carry if not zero +2
@skip:
.endif
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
;;; Preserves A,X,Y - sets C
;;;------------------------------------------------------------------------------
        pha                     ; +3
        phx                     ; +3
        sta ZP_I2C_DATA         ; stash +3

        ldx #8   ; +2 = 11
        ;; The prior operation had to be an ACK/NAK or a start
        ;; the known initial value of data is HIGH (released)
@hiloop:
        asl ZP_I2C_DATA         ; 2
        bcc @switch_to_low      ; 3 if taken
        i2c_clock_pulse         ; 14
        dex                     ; 2
        bne @hiloop             ; 3 if taken
        jmp @finish             ; 3

@loloop:
        asl ZP_I2C_DATA         ; 2
        bcs @switch_to_high     ; 3 if taken
        i2c_clock_pulse         ; 14
        dex                     ; 2
        bne @loloop             ; 3 if taken
        jmp @finish             ; 3

@switch_to_low:
        lda #I2C_DATABIT        ; 2
        tsb I2C_DDR             ; 6
        i2c_clock_pulse         ; 14
        dex                     ; 2
        bne @loloop             ; 3 if taken
        jmp @finish             ; 3

@switch_to_high:
        lda #I2C_DATABIT        ; 2
        trb I2C_DDR             ; 6
        i2c_clock_pulse         ; 14
        dex                     ; 2
        bne @hiloop             ; 3 if taken

@finish:
        jsr I2C_ReadAck         ; +42
        plx                     ; +4
        pla                     ; +4
        rts                     ;

;;;------------------------------------------------------------------------------
I2C_ReadByte:
;;;------------------------------------------------------------------------------
;;; Start with clock low.  Ends with byte in A.  Do ACK separately.
;;;------------------------------------------------------------------------------
        ;; data must already be up
        ;; i2c_data_up             ; Make sure we're not holding the data line down.
        lda #I2C_CLOCKBIT       ; Load the clock bit in for initial loop
.macro RB_SINGLESTEP
.local skip
        trb I2C_DDR             ; clock up
        clc
        lda #I2C_DATABIT
        bit I2C_PORT            ; check databit
        beq skip
        sec
skip:   rol ZP_I2C_DATA
        i2c_clock_down
        ;; nop
        ;; nop
.endmacro
        DOTIMES RB_SINGLESTEP,8
        lda ZP_I2C_DATA         ; Load A from local
        rts

;;;------------------------------------------------------------------------------
I2C_ReadHi4:
;;;------------------------------------------------------------------------------
;;; Start with clock low.  Ends with byte in A.  Do ACK separately.
;;; Trashes the X register too.
;;;------------------------------------------------------------------------------
        ;; the thing prior to ReadHi4 was either a previous NAK or a previous
        ;; ack by the slave of the address.   In both cases, data line must be
        ;; up - so there's no need to do it again.
        ;; i2c_data_up             ; Make sure we're not holding the data line down.
        lda #I2C_CLOCKBIT       ; Load the clock bit in for initial loop
.macro RH4_SINGLESTEP
.local skip
        trb I2C_DDR             ; clock up
        clc
        lda #I2C_DATABIT
        bit I2C_PORT            ; check databit
        beq skip
        sec
skip:   rol ZP_I2C_DATA
        i2c_clock_down
        ;; nop
        ;; nop
.endmacro
        DOTIMES RH4_SINGLESTEP,4
        ;; now just pulse the clock 4 times - this hack here saves 8 cycles over
        ;; just doing trb/tsb, but trashes X
.if 1
        ;;phx                        ; +3
        lda I2C_DDR                ; +4
        and #(~I2C_CLOCKBIT & $ff) ; +2
        tax                        ; +2
        sta I2C_DDR                ; -2 (4 cycles vs 6 for tsb)
        stx I2C_DDR                ; -2
        sta I2C_DDR                ; -2
        stx I2C_DDR                ; -2
        sta I2C_DDR                ; -2
        stx I2C_DDR                ; -2
        sta I2C_DDR                ; -2
        stx I2C_DDR                ; -2
        ;plx                        ; +4
.else
        trb I2C_DDR
        tsb I2C_DDR
        trb I2C_DDR
        tsb I2C_DDR
        trb I2C_DDR
        tsb I2C_DDR
        trb I2C_DDR
        tsb I2C_DDR
.endif
        lda ZP_I2C_DATA            ; Load A from local
        rts

;;;------------------------------------------------------------------------------
I2C_SendAddr:
;;;------------------------------------------------------------------------------
;;; Address in A, carry flag contains read/write flag (read = 1, write 0)
;;; Return ack in Carry
;;;------------------------------------------------------------------------------
        rol A                   ; Rotates address 1 bit and puts read/write flag in A
        jmp I2C_SendByte        ; Sends address and returns
