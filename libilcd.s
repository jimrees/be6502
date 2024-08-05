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

;;; Source address pointer for strings & custom characters
LCD_STRPTR = value
INST = mod10

.zeropage
LCD_I2C_ADDRESS_W:        .res 1
LCD_I2C_ADDRESS_R:        .res 1

.code

.macro W2A
        lda LCD_I2C_ADDRESS_W   ; +3
.endmacro
.macro R2A
        lda LCD_I2C_ADDRESS_R   ; +3
.endmacro

.macro LCD_I2C_Prefix
        I2C_Prefix W2A          ; +334
.endmacro

.macro LCD_I2C_Restart_W
        I2C_Restart W2A
.endmacro

.macro LCD_I2C_Restart_R
        I2C_Restart R2A
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

.macro STROBE_A_THROUGH
        jsr I2C_SendByte        ; 315
        eor #LCD_EN             ; +2
        jsr I2C_SendByte        ; +315 = 632
.endmacro

; ---------------------------------------------
; Initialise LCD Display
; ---------------------------------------------
ilcd_init:
        ;; Scenarios
        ;; 1) lcd is in 8-bit mode.
        ;; 2) 4-bit mode, no pending nibble.
        ;; 3) 4-bit mode, pending nibble, where prior nibble was the
        ;; command to switch to 8-bit mode.
        ;; 4) 4-bit mode, pending nibble, prior nibble was %0000
        ;; 5) 4-bit mode, any other prior nibble.

        LCD_I2C_Prefix
        lda #(%00110000|LCD_EN) ; set 8-bit mode
        STROBE_A_THROUGH        ; 1) 8-bit, 2) half-way to 8-bit 3) 8-bit 4) 4-bit mode
        eor #LCD_EN             ; restore original
        STROBE_A_THROUGH        ; 1) 8-bit, 2) 8-bit, 3) 8-bit, 4) half-way to 8-bit
        eor #LCD_EN             ; restore original
        STROBE_A_THROUGH        ; All cases in 8-bit mode now.

        lda #(%00100000|LCD_EN) ; switch to 4-bit mode
        STROBE_A_THROUGH
        M_I2C_Stop

        ;; Now full 4-bit mode instructions
        lda #%00101000
        jsr ilcd_instruction ; 4-bit mode, 2 lines, 8x5 font, backlight on

        lda #%00001000
        jsr ilcd_instruction ; turn display off (but backlight on)

        lda #%00000001
        jsr ilcd_instruction ; clear display

        lda #%00000110
        jsr ilcd_instruction ; Increment ap on writes, no SHIFT display

        lda #%00001110
        jmp ilcd_instruction ; Turn display back on, with cursor visible
        ;; implicit return

@init_failed:
        jsr I2C_Clear
        sec
        rts

ilcd_cursor_off:
        lda #%00001100
        jmp ilcd_instruction

ilcd_home:
        lda #%00000010
        jmp ilcd_instruction

ilcd_clear:
        lda #%00000001
        jmp ilcd_instruction

; ---------------------------------------------
; A contains instruction to send
; RS = 0, RW = 0, BT is maintained (always), EN is toggled
; ---------------------------------------------
ilcd_instruction:
        sta INST                ; save full instruction
        jsr ilcd_wait
        LCD_I2C_Prefix
        lda INST                ; fetch instruction
        and #$f0                ; clear low nibble
        ora #(LCD_EN|LCD_BT)    ; set EN & BT
        STROBE_A_THROUGH
        lda INST                ; reload
        asl                     ; move low nibble up high
        asl
        asl
        asl
        ora #(LCD_EN|LCD_BT)    ; set EN
        STROBE_A_THROUGH
        M_I2C_Stop
        rts

; ---------------------------------------------
; A contains data to send
; RS = 1, RW = 0
; ---------------------------------------------
ilcd_write_char:
        pha                     ; +3
        LCD_I2C_Prefix          ; +334=337
        pla                     ; +4=341
        pha                     ; +3=344
        and #$f0                ; +2=346
        ora #(LCD_RS|LCD_EN|LCD_BT) ; +2=348
        STROBE_A_THROUGH        ; +632=980
        pla                     ; +4=984
        asl                     ; +2=986
        asl                     ; +2=988
        asl                     ; +2=990
        asl                     ; +2=992
        ora #(LCD_RS|LCD_BT|LCD_EN) ; +2=994
        STROBE_A_THROUGH        ; +632=1626
        M_I2C_Stop              ; +22=1648
        rts                     ; +12=1660

;;; ---------------------------------------------
;;; Send a string of text to the LCD Display
;;; A = msg low byte
;;; Y = msg high byte
;;; ---------------------------------------------

ilcd_print_string:
        sta LCD_STRPTR          ; +3
        sty LCD_STRPTR + 1      ; +3=6
        jsr ilcd_wait           ; however long...
        ldy #0                  ; 2
        LCD_I2C_Prefix          ; > 300 cycles since it sends a full byte
        lda (LCD_STRPTR),y
        beq @done
@loop:
        pha                         ; +3
        and #$f0                    ; +2
        ora #(LCD_RS|LCD_EN|LCD_BT) ; +2
        STROBE_A_THROUGH            ; +632=639
        pla                         ; +4=643
        asl                         ; +2
        asl                         ; +2
        asl                         ; +2
        asl                         ; +2
        ora #(LCD_RS|LCD_BT|LCD_EN) ; +2=653
        STROBE_A_THROUGH            ; +632=1285
        iny                         ; +2
        lda (LCD_STRPTR),y          ; +4=1291
        bne @loop                   ; +3 (taken, 2 otherwise) = =1294 per char
@done:
        M_I2C_Stop              ; +22
        rts                     ; +12


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

        LCD_I2C_Restart_R
        jsr I2C_ReadHi4
        asl
        asl
        asl
        asl
        sta LCD_STRPTR
        jsr I2C_SendNak         ; this finishes data high

        LCD_I2C_Restart_W       ; switch again to write
        lda #RCMD
        jsr I2C_SendByte
        eor #(%11110000|LCD_EN)
        jsr I2C_SendByte

        LCD_I2C_Restart_R         ; switch again to read
        jsr I2C_ReadHi4
        pha                     ; save low nibble on stack
        jsr I2C_SendNak

        LCD_I2C_Restart_W       ; switch again to write
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
        LCD_I2C_Prefix
        lda #RCMD
        jsr I2C_SendByte
        ora #(%11110000|LCD_EN)
        jsr I2C_SendByte

        LCD_I2C_Restart_R
        jsr I2C_ReadHi4
        pha
        jsr I2C_SendNak

        LCD_I2C_Restart_W
        lda #RCMD
        jsr I2C_SendByte        ; E DOWN
        ora #LCD_EN
        STROBE_A_THROUGH
        M_I2C_Stop
        pla
        asl
        asl
        asl
        asl
        bpl @wreturn
        jmp @spin
@wreturn:
        rts

        ;; used to set position #$40 is useful for going to start of second line
ilcd_set_position:
        ora #%10000000
        jmp ilcd_instruction
ilcd_shift_left:
        lda #%00011000
        jmp ilcd_instruction
ilcd_shift_right:
        lda #%00011100
        jmp ilcd_instruction
ilcd_cursor_left:
        lda #%00010000
        jmp ilcd_instruction
ilcd_cursor_right:
        lda #%00010100
        jmp ilcd_instruction

;;;
;;; The character index is in A
;;; The pointer at VALUE points to 8-bytes of bitmap data
;;; to be transferred to the CGRAM
;;;
ilcd_create_char:
        asl                     ; multiply by 8
        asl
        asl
        ora #$40                ; LCD_SETCGRAMADDR
        jsr ilcd_instruction    ; this forces a wait
        phy
        ldy #0
@loop:
        lda (value),y
        jsr ilcd_write_char
        iny
        cpy #8
        bcc @loop

        lda #0
        jsr ilcd_set_position

        ply
        rts

;;;
;;; For testing - put the LCD into one of 5 flavors of corrupted state
;;; to test that ilcd_init can get it back into action.
;;; The value in A determines the flavor:
;;; 0 - full command to switch into 8-bit mode
;;; 1 - half-command starting as a switch to 8-bit mode
;;; 2 - half-command with a %0000 prefix
;;; 3 - half-command with another prefix innocuous
;;; * - do nothing

ilcd_half_cmd:
        pha
        LCD_I2C_Prefix
        pla
        ora #LCD_EN
        STROBE_A_THROUGH
        M_I2C_Stop
        rts

ilcd_corrupt_state:
        cmp #0
        bne @check2

        ;; put into 8-bit mode, 2-line, same stuff
        lda #%00111000
        jmp ilcd_instruction

@check2:
        dec
        bne @check3
        ;; cmd to go to dangling with 8-bit mode switch pending
        lda #%00110000
        jmp ilcd_half_cmd

@check3:
        dec
        bne @check4
        ;; put into 4-bit dangling mode, with a %0000 prefix
        ;; so that the init command causes a HOME command.
        lda #%00000000
        jmp ilcd_half_cmd

@check4:
        dec
        bne @done
        ;; innocuous command to switch to 4-bit
        lda #%00100000
        jmp ilcd_half_cmd

@done:
        rts
