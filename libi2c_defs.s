
.global I2C_Init
.global I2C_Clear
.global I2C_Start, I2C_Stop
.global I2C_SendAddr, I2C_SendByte
.global I2C_ReadByte, I2C_ReadHi4
.global I2C_ReadAck, I2C_SendAck, I2C_SendNak

.include "via_defs.s"

I2C_DATABIT     = %00000001
I2C_CLOCKBIT    = %00000010
I2C_DDR         = DDRA
I2C_PORT        = PORTA

;;; Calling this macro instead of jsr'ing to I2C_Start saves 12 cycles from 40
.macro M_I2C_Start
        lda I2C_DDR                ; 4
        and #(~I2C_DATABIT & $ff)  ; +2=6
        sta I2C_DDR                ; +4=10
        and #(~I2C_CLOCKBIT & $ff) ; +2=12
        sta I2C_DDR                ; +4=16
        ora #I2C_DATABIT           ; +2=18
        sta I2C_DDR                ; +4=22
        ora #I2C_CLOCKBIT          ; +2=24
        sta I2C_DDR                ; +4=28
.endmacro
.macro M_I2C_Stop
        lda I2C_DDR             ; 4
        ora #I2C_DATABIT        ; data down +2=6
        sta I2C_DDR             ; +4=10
        and #(~I2C_CLOCKBIT & $ff) ; +2=12
        sta I2C_DDR                ; clock up +4=16
        and #(~I2C_DATABIT & $ff) ; data up +2=18
        sta I2C_DDR               ; +4=22
.endmacro
