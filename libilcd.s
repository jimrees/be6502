.setcpu "65C02"
.feature string_escapes on
.include "syscall_defs.s"
        ALLSYSCALL .global

.include "libilcd_defs.s"
.include "libi2c_defs.s"
.include "via_defs.s"

LCD_RS = %00000001
LCD_RW = %00000010
LCD_EN = %00000100
LCD_BT = %00001000

.zeropage
;;; Source address pointer for strings & custom characters
LCD_CC_ADDRESS:
LCD_STRPTR:               .res 2

;;; A place to stash the current instruction/char while writing the 4-bit halves.
INST:                     .res 1

LCD_I2C_ADDRESS_W:        .res 1
LCD_I2C_ADDRESS_R:        .res 1

.code


.macro LCD_I2C_Prefix
        M_I2C_Start
        lda LCD_I2C_ADDRESS_W
        jsr I2C_SendByte
.endmacro

.macro LCD_I2C_RPrefix
        M_I2C_Start
        lda LCD_I2C_ADDRESS_R
        jsr I2C_SendByte
.endmacro

;;;
;;; A is the incoming 7-bit address
;;;
ilcd_set_address:
        asl
        sta LCD_I2C_ADDRESS_W
        ora #1
        sta LCD_I2C_ADDRESS_R
        rts

; ---------------------------------------------
; Initialise LCD Display
; ---------------------------------------------
ilcd_init:
        LCD_I2C_Prefix
        bcs @init_failed

        lda #%11000100
        ldx #6
@fsetloop:
        jsr I2C_SendByte
        bcs @init_failed
        eor #LCD_EN
        dex
        bne @fsetloop

        lda #%00100100
        jsr I2C_SendByte
        bcs @init_failed

        eor #LCD_EN
        jsr I2C_SendByte
        bcs @init_failed
        M_I2C_Stop

        ;; Now 4-bit mode instructions
        lda #%00101000
        jsr ilcd_instruction ; Set to 2 lines, 8x5 font, backlight on

        lda #%00001000
        jsr ilcd_instruction ; turn display off (but backlight on)

        lda #%00000001
        jsr ilcd_instruction ; clear display
        jsr ilcd_wait

        lda #%00000110
        jsr ilcd_instruction ; Increment cursor, do not shift display

        lda #%00001101
        jsr ilcd_instruction ; Turn display on

        rts

@init_failed:
        jsr I2C_Clear
        sec
        rts

ilcd_cursor_off:
        lda #%00001100
        jsr ilcd_instruction
        rts

ilcd_home:
        lda #%00000010
        jsr ilcd_instruction
        jsr ilcd_wait
        rts

ilcd_clear:
        lda #%00000001
        jsr ilcd_instruction
        jsr ilcd_wait
        rts

; ---------------------------------------------
; A contains instruction to send
; RS = 0, RW = 0, BT is maintained (always), EN is toggled
; ---------------------------------------------
ilcd_instruction:
        sta INST                ; save full instruction
        ;; jsr ilcd_wait
        LCD_I2C_Prefix
        lda INST                ; fetch instruction
        and #$f0                ; clear low nibble
        ora #(LCD_EN|LCD_BT)    ; set EN & BT
        jsr I2C_SendByte        ; send it
        eor #LCD_EN             ; toggle EN
        jsr I2C_SendByte        ; send it
        lda INST                ; reload
        asl                     ; move low nibble up high
        asl
        asl
        asl
        ora #(LCD_EN|LCD_BT)    ; set EN
        jsr I2C_SendByte        ; send
        eor #LCD_EN             ; toggle EN
        jsr I2C_SendByte        ; send with EN low
        M_I2C_Stop
        rts

; ---------------------------------------------
; A contains data to send
; RS = 1, RW = 0
; ---------------------------------------------
.macro ILCD_WRITE_CHAR REGETCH
        and #$f0
        ora #(LCD_RS|LCD_EN|LCD_BT)
        jsr I2C_SendByte
        eor #LCD_EN             ; toggle EN
        jsr I2C_SendByte
        REGETCH
        asl
        asl
        asl
        asl
        ora #(LCD_RS|LCD_BT|LCD_EN)
        jsr I2C_SendByte
        eor #LCD_EN
        jsr I2C_SendByte
.endmacro

.macro INST2A
        lda INST
.endmacro

ilcd_write_char:
        sta INST
        LCD_I2C_Prefix
        lda INST
        ILCD_WRITE_CHAR INST2A
        M_I2C_Stop
        rts

;;; ---------------------------------------------
;;; Send a string of text to the LCD Display
;;; A = msg low byte
;;; Y = msg high byte
;;; ---------------------------------------------

.macro LSYCH
        lda (LCD_STRPTR),y
.endmacro

ilcd_print_string:
        sta LCD_STRPTR
        sty LCD_STRPTR + 1
        ldy #0
        LCD_I2C_Prefix
        lda (LCD_STRPTR),y
        beq @end_lcd_message
@loop:
        ILCD_WRITE_CHAR LSYCH
        iny
        lda (LCD_STRPTR),y
        bne @loop
@end_lcd_message:
        M_I2C_Stop              ; valid - I guess!
        rts


;;; ------------------------------------------------
;;; Stops on A
;;;
        RCMD = LCD_RW | LCD_BT
ilcd_read_ac:
        LCD_I2C_Prefix
        lda #RCMD
        jsr I2C_SendByte
        eor #(%11110000|LCD_EN)
        jsr I2C_SendByte
        LCD_I2C_RPrefix
        jsr I2C_ReadHi4
        asl
        asl
        asl
        asl
        sta LCD_STRPTR
        jsr I2C_SendNak
        LCD_I2C_Prefix          ; switch again to write
        lda #RCMD
        jsr I2C_SendByte
        eor #(%11110000|LCD_EN)
        jsr I2C_SendByte
        LCD_I2C_RPrefix         ; switch again to read
        jsr I2C_ReadHi4
        pha                     ; save low nibble on stack
        jsr I2C_SendNak
        LCD_I2C_Prefix          ; switch again to write
        lda #RCMD
        jsr I2C_SendByte
        ;; jsr I2C_Stop            ; phew!
        M_I2C_Stop
        pla                     ; restore low nibble and downshift
        and #$0f
        ora LCD_STRPTR
        and #$7F                ; clear any busy bit
        rts

ilcd_wait:
@spin:
        jsr ilcd_readbusy
        bpl @done
        phy
        lda #< busyspin
        ldy #> busyspin
        jsr STROUT
        ply
        jmp @spin
@done:
        rts

ilcd_readbusy:
        LCD_I2C_Prefix
        lda #RCMD
        jsr I2C_SendByte
        ora #(%10000000|LCD_EN)
        jsr I2C_SendByte
        LCD_I2C_RPrefix
        jsr I2C_ReadHi4
        pha
        jsr I2C_SendNak
        LCD_I2C_Prefix
        lda #RCMD
        jsr I2C_SendByte        ; E DOWN
        ora #LCD_EN
        jsr I2C_SendByte        ; E UP
        eor #LCD_EN
        jsr I2C_SendByte        ; E DOWN to complete transaction
        M_I2C_Stop
        pla
        asl
        asl
        asl
        asl
        rts

        ;; used to set position #$40 is useful for going to start of second line
ilcd_set_position:
        ora #%10000000
        jsr ilcd_instruction
        rts

ilcd_create_char:
        asl                     ; multiply by 8
        asl
        asl
        ora #$40                ; LCD_SETCGRAMADDR
        jsr ilcd_instruction
        phy
        ldy #0
@loop:
        lda (LCD_CC_ADDRESS),y
        jsr ilcd_write_char
        iny
        cpy #8
        bcc @loop
        ply
        rts

.rodata
busyspin: .asciiz "BSPIN!\r\n"
