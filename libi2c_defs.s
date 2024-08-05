
.global I2C_Init
.global I2C_Clear
.global I2C_SendAddr, I2C_SendByte
.global I2C_ReadByte, I2C_ReadHi4
.global I2C_ReadAck, I2C_SendAck, I2C_SendNak

.include "via_defs.s"

I2C_DATABIT     = %00000001
I2C_CLOCKBIT    = %00000010
I2C_DDR         = DDRA
I2C_PORT        = PORTA

;;; Calling this macro instead of jsr'ing to I2C_Start saves 12 cycles from 40
;;; PRECONDITION: both DATA and CLOCK are already high.
.macro M_I2C_Start
        lda I2C_DDR                ; 4
        ora #I2C_DATABIT           ; +2=6
        sta I2C_DDR                ; +4=10
        ora #I2C_CLOCKBIT          ; +2=12
        sta I2C_DDR                ; +4=16
.endmacro

;;; Issue an I2C Stop
;;; PRECONDITION: CLOCK is low.
.macro M_I2C_Stop
        lda I2C_DDR             ; 4
        ora #I2C_DATABIT        ; data down +2=6
        sta I2C_DDR             ; +4=10
        and #(~I2C_CLOCKBIT & $ff) ; +2=12, clock up
        sta I2C_DDR                ; clock up +4=16
        and #(~I2C_DATABIT & $ff) ; data up +2=18, data up
        sta I2C_DDR               ; +4=22
.endmacro

;;; A macro that combines the Start with the send & ack receipt of the address.
;;; PRECONDITION: DATA & CLOCK are high.
.macro I2C_Prefix ADDR_2_A
        M_I2C_Start             ; +16
        ADDR_2_A                ; +3
        jsr I2C_SendByte        ; +315 = 334
.endmacro

;;; PRECONDITION: DATA is high.  CLOCK is low.
;;; A frame restart happens mid-frame while the clock is low.   Used when switching
;;; between reading and writing -- saves the need for a stop sequence.
;;; This macro wraps all that up.  The caller must provide a macro which retrieves the
;;; address (with R/W bit included) into A.
;;; What happens prior must be either the read of a an ACK or the send of a NAK, so
;;; we know DATA must already be high, and we don't have to trouble with raising it.
.macro I2C_Restart ADDR_2_A
        lda #I2C_CLOCKBIT
        trb I2C_DDR
        I2C_Prefix ADDR_2_A
.endmacro

