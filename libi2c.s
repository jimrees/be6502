.setcpu "65C02"
.feature string_escapes on
.include "via_defs.s"
.include "libi2c_defs.s"
.include "macros.s"

.zeropage
ZP_I2C_DATA:    .res 1

.code

;------------------------------------------------------------------------------
.macro i2c_data_up
;------------------------------------------------------------------------------
; Destroys A
;------------------------------------------------------------------------------
        lda   #I2C_DATABIT  ; Clear data bit of the DDR
        trb   I2C_DDR       ; to make bit an input and let it float up.
.endmacro

;------------------------------------------------------------------------------
.macro i2c_data_down
;------------------------------------------------------------------------------
; Destroys A, 8 cycles
;------------------------------------------------------------------------------
        lda   #I2C_DATABIT  ; Set data bit of the DDR
        tsb   I2C_DDR       ; to make bit an output and pull it down.
.endmacro

;------------------------------------------------------------------------------
.macro i2c_clock_up
;------------------------------------------------------------------------------
; Destroys A, 8 cycles
;------------------------------------------------------------------------------
        lda   #I2C_CLOCKBIT     ; 2 cycles
        trb   I2C_DDR           ; 6 cycles
.endmacro


;------------------------------------------------------------------------------
.macro i2c_clock_down
;------------------------------------------------------------------------------
; Destroys A, 8 cycles
;------------------------------------------------------------------------------
        lda   #I2C_CLOCKBIT
        tsb   I2C_DDR
.endmacro

;------------------------------------------------------------------------------
    .macro i2c_clock_pulse
;------------------------------------------------------------------------------
; Destroys A
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
I2C_Start:
;------------------------------------------------------------------------------
; Destroys A, N, Z - preserves C,V
;------------------------------------------------------------------------------
.if 0
        ;; 32 cycles
        i2c_data_up
        i2c_clock_up
        i2c_data_down
        i2c_clock_down
.else
        ;; this saves 4 cycles.
        lda I2C_DDR                ; 4
        and #(~I2C_DATABIT & $ff)  ; +2=6
        sta I2C_DDR                ; +4=10
        and #(~I2C_CLOCKBIT & $ff) ; +2=12
        sta I2C_DDR                ; +4=16
        ora #I2C_DATABIT           ; +2=18
        sta I2C_DDR                ; +4=22
        ora #I2C_CLOCKBIT          ; +2=24
        sta I2C_DDR                ; +4=28
.endif
        rts

;------------------------------------------------------------------------------
I2C_Stop:
;------------------------------------------------------------------------------
; Destroys A, N, Z.  Preserves C,V
;------------------------------------------------------------------------------
.if 0
        ;; 24 cycles
        i2c_data_down
        i2c_clock_up
        i2c_data_up
.else
        ;; Saves 2 cycles
        lda I2C_DDR             ; 4

        ora #I2C_DATABIT        ; data down +2=6
        sta I2C_DDR             ; +4=10

        and #(~I2C_CLOCKBIT & $ff) ; +2=12
        sta I2C_DDR                ; clock up +4=16

        and #(~I2C_DATABIT & $ff) ; data up +2=18
        sta I2C_DDR               ; +4=22
.endif
        rts

;------------------------------------------------------------------------------
I2C_SendAck:
;------------------------------------------------------------------------------
; Destroys A
;------------------------------------------------------------------------------
        i2c_data_down       ; Acknowledge.  The ACK bit in I2C is the 9th bit of a "byte".
        i2c_clock_pulse     ; Trigger the clock
        i2c_data_up         ; End with data up
        rts

;------------------------------------------------------------------------------
I2C_SendNak:
;------------------------------------------------------------------------------
; Destroys A
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
; Ack in carry flag (clear means ack, set means nak)
; Destroys A
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
        i2c_clock_down      ; Bring the clock down
        rts


;------------------------------------------------------------------------------
I2C_Init:
;------------------------------------------------------------------------------
; Destroys A
;------------------------------------------------------------------------------
        lda #(I2C_CLOCKBIT | I2C_DATABIT)
        tsb I2C_DDR
        trb I2C_PORT
        ;; The above could potentially start a frame, so run clear to be safe
        jmp I2C_Clear

;------------------------------------------------------------------------------
I2C_Clear:
;------------------------------------------------------------------------------
; This clears any unwanted transaction that might be in progress, by giving
; enough clock pulses to finish a byte and not acknowledging it.
; Destroys  A
;------------------------------------------------------------------------------
        phx                     ; Save X
        jsr I2C_Start
        jsr I2C_Stop
        i2c_data_up ; Keep data line released so we don't ACK any byte sent by a device.
        ldx #9 ; Loop 9x to send 9 clock pulses to finish any byte a device might send.
        lda #I2C_CLOCKBIT
@do:
        trb I2C_DDR             ; Clock up
        tsb I2C_DDR             ; Clock down
        dex
        bne @do
        plx                     ; Restore X
        jsr I2C_Start
        jmp I2C_Stop            ; (JSR, RTS)

;------------------------------------------------------------------------------
I2C_SendByte:
;------------------------------------------------------------------------------
; Sends the byte in A
; Preserves A,X,Y - sets C
;------------------------------------------------------------------------------
.if I2C_DATABIT = 1
        pha
        eor #$ff                ; flip all bits
        sta ZP_I2C_DATA         ; stash

        ;; this preserves other bits in DDRA, but only if no interrupt ever touches
        ;; them.  If true atomicity of changes to DDRA is needed, one would need to
        ;; either tsb for a 0 bit or trb for 1 bit meaning conditional branching.

.macro SB_SINGLE_BIT
        lda I2C_DDR             ; +4
        lsr                     ; +2
        asl ZP_I2C_DATA         ; +5
        rol                     ; +2
        sta I2C_DDR             ; +4 = 18
        i2c_clock_pulse         ; +14 = 32
.endmacro
        DOTIMES SB_SINGLE_BIT,8
        jsr I2C_ReadAck
        pla
.else
        phx                     ; Save X +3
        pha                     ; Save A +3
        sta ZP_I2C_DATA         ; Save to variable +4
        ldx #8                  ; We will do 8 bits. +2 = 12
@loop:
        i2c_data_up     ; +8
        asl ZP_I2C_DATA ; Get next bit to send and put it in the C flag. +6
        bcs @continue   ; +3
        i2c_data_down   ; +8
@continue:
        i2c_clock_pulse         ; Pulse the clock +16
        dex
        bne @loop
        jsr I2C_ReadAck         ; sets Carry
        pla                     ; Restore A
        plx                     ; Restore X
.endif
        rts

;------------------------------------------------------------------------------
I2C_ReadByte:
;------------------------------------------------------------------------------
; Start with clock low.  Ends with byte in A.  Do ACK separately.
;------------------------------------------------------------------------------
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

;------------------------------------------------------------------------------
I2C_ReadHi4:
;------------------------------------------------------------------------------
;;; Start with clock low.  Ends with byte in A.  Do ACK separately.
;;; Trashes the X register too.
;------------------------------------------------------------------------------
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

;------------------------------------------------------------------------------
I2C_SendAddr:
;------------------------------------------------------------------------------
; Address in A, carry flag contains read/write flag (read = 1, write 0)
; Return ack in Carry
;------------------------------------------------------------------------------
        rol A                   ; Rotates address 1 bit and puts read/write flag in A
        jmp I2C_SendByte        ; Sends address and returns
