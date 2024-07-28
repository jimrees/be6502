.setcpu "65C02"
.feature string_escapes on
.include "via_defs.s"
.include "libi2c_defs.s"

I2C_DATABIT     = %00000100
I2C_CLOCKBIT    = %00000010
I2C_DDR         = DDRA
I2C_PORT        = PORTA

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
; Destroys A
;------------------------------------------------------------------------------
        lda   #I2C_DATABIT  ; Set data bit of the DDR
        tsb   I2C_DDR       ; to make bit an output and pull it down.
    .endmacro


;------------------------------------------------------------------------------
    .macro i2c_clock_up
;------------------------------------------------------------------------------
; Destroys A
;------------------------------------------------------------------------------
        lda   #I2C_CLOCKBIT
        trb   I2C_DDR
    .endmacro


;------------------------------------------------------------------------------
    .macro i2c_clock_down
;------------------------------------------------------------------------------
; Destroys A
;------------------------------------------------------------------------------
        lda   #I2C_CLOCKBIT
        tsb   I2C_DDR
    .endmacro


;------------------------------------------------------------------------------
    .macro i2c_clock_pulse
;------------------------------------------------------------------------------
; Destroys A
;------------------------------------------------------------------------------
        lda   I2C_DDR
        and   #(~I2C_CLOCKBIT & $ff)
        sta   I2C_DDR
        ora   #I2C_CLOCKBIT
        sta   I2C_DDR
    .endmacro


;------------------------------------------------------------------------------
I2C_Start:
;------------------------------------------------------------------------------
; Destroys A, N, Z - preserves C,V
;------------------------------------------------------------------------------
        i2c_data_up
        i2c_clock_up
        i2c_data_down
        i2c_clock_down          ; this does it
        ;; i2c_data_up             ; this is just to get to a known state
        rts

;------------------------------------------------------------------------------
I2C_Stop:
;------------------------------------------------------------------------------
; Destroys A, N, Z.  Preserves C,V
;------------------------------------------------------------------------------
        i2c_data_down           ; yes, necessary
        i2c_clock_up
        i2c_data_up
        ;; i2c_clock_down - it only makes sense to leave clock released
        ;; i2c_data_up - would be superfluous
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
        i2c_data_up         ; Acknowledging consists of pulling it down.
        i2c_clock_pulse     ; Trigger the clock
        ;; i2c_data_up - would be superfluous, though it puts DATABIT in the A reg
        rts


;------------------------------------------------------------------------------
I2C_ReadAck:
;------------------------------------------------------------------------------
; Ack in carry flag (clear means ack, set means nak)
; Destroys A
;------------------------------------------------------------------------------
        i2c_data_up         ; Input
        i2c_clock_up        ; Clock up
        clc                 ; Clear the carry
        lda I2C_PORT        ; Load data from the port
        and #I2C_DATABIT    ; Test the data bit
        beq @skip           ; If zero skip
        sec                 ; Set carry if not zero
@skip:
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
        ;; The above could potentially be interpreted to start a frame
        jsr I2C_Clear
        rts

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
        i2c_data_up             ; Keep data line released so we don't ACK any byte sent by a device.
        ldx #9                  ; Loop 9x to send 9 clock pulses to finish any byte a device might send.
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
        phx                     ; Save X
        pha                     ; Save A
        sta ZP_I2C_DATA         ; Save to variable
        ldx #8                  ; We will do 8 bits.
@loop:
        lda I2C_DDR
        and #(~I2C_DATABIT & $ff)
        sta I2C_DDR
        asl ZP_I2C_DATA ; Get next bit to send and put it in the C flag.
        bcs @continue
        ora #I2C_DATABIT
        sta I2C_DDR
@continue:

        i2c_clock_pulse         ; Pulse the clock
        dex
        bne @loop
        jsr I2C_ReadAck         ; sets Carry
        pla                     ; Restore A
        plx                     ; Restore X
        rts

;------------------------------------------------------------------------------
I2C_ReadByte:
;------------------------------------------------------------------------------
; Start with clock low.  Ends with byte in A.  Do ACK separately.
;------------------------------------------------------------------------------
        i2c_data_up             ; Make sure we're not holding the data line down.  Be ready to input data.
        phx                     ; Save X
        ldx #8                  ; We will do 8 bits.
        lda #I2C_CLOCKBIT       ; Load the clock bit in for initial loop
@loop:
        trb I2C_DDR             ; Clock up
        clc
        lda #I2C_DATABIT
        bit I2C_PORT            ; Check databit
        beq @skip               ; If zero, skip
        sec                     ; Set carry flag
@skip:
        rol ZP_I2C_DATA ; Rotate the carry bit into value / carry cleared by rotated out bit
        i2c_clock_down  ; restores CLOCK_BIT into A
        nop             ; Delay for a few clock cycles
        dex
        bne @loop              ; Go back for next bit if there is one.

        lda ZP_I2C_DATA         ; Load A from local
        plx                     ; Restore variables
        rts

;------------------------------------------------------------------------------
I2C_SendAddr:
;------------------------------------------------------------------------------
; Address in A, carry flag contains read/write flag (read = 1, write 0)
; Return ack in Carry
;------------------------------------------------------------------------------
        rol A                   ; Rotates address 1 bit and puts read/write flag in A
        jmp I2C_SendByte        ; Sends address and returns
