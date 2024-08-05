.setcpu "65C02"
.debuginfo +
.feature string_escapes on

.include "bios_defs.s"
.include "timer_defs.s"
.include "via_defs.s"
.include "acia_defs.s"
.include "lcd_defs.s"
.include "syscall_defs.s"

ALLSYSCALL .global

.import COLD_START

.segment "BIOSZP" : zeropage
START_OF_ZERO_INIT:
loc_value:      .res 2          ; aka value
loc_mod10:      .res 2          ; aka mod10
loc_tick_counter:.res 4         ; used by the timer interrupt
loc_fcharprint: .res 2          ; used by decimalprint
loc_tmp0:       .res 1
loc_tmp1:       .res 1
loc_tmp2:       .res 1
loc_tmp3:       .res 1

txDelay:        .res 2          ; tune-able value for ACIA output delay
o_busy:         .res 1          ; serial interrupt managemetn [BUSY ...]
iproducer_ptr:  .res 1
iconsumer_ptr:  .res 1
oproducer_ptr:  .res 1
oconsumer_ptr:  .res 1

.ifdef HARDWARE_FLOW_CONTROL
ctsb_state:     .res 1 ; [CTSB ...]
forced_rtsb:    .res 1 ; [FORCED ...]
.endif

END_OF_ZERO_INIT:

.assert loc_value = value, error, "loc_value != value"
.assert loc_mod10 = mod10, error, "loc_mod10 != mod10"
.assert loc_tick_counter = tick_counter, error, "loc_tick_counter != tick_counter"
.assert loc_fcharprint = fcharprint, error, "loc_fcharprint != fcharprint"
.assert loc_tmp0 = tmp0, error, "loc_tmp0 != tmp0"
.assert loc_tmp1 = tmp1, error, "loc_tmp1 != tmp1"
.assert loc_tmp2 = tmp2, error, "loc_tmp2 != tmp2"
.assert loc_tmp3 = tmp3, error, "loc_tmp3 != tmp3"

.segment "BIOS_BUFFERS"
;;; As circular buffers indexed by an 8-bit value, these must be page-aligned
.align 256
input_buffer:   .res $100
output_buffer:  .res $100

;;; Use our own code segment to guarantee AAA_GO_BASIC shows up at $8000
.segment "BIOS_CODE"

AAA_GO_BASIC:
        jmp COLD_START

LOAD:
SAVE:
        rts

;;; walk from [iconsumer_ptr to iproducer_ptr) looking for ^C
;;; If found, it will remove it from the input buffer.
;;; Returns Z set if true, and A = $03
;;; Modified:  A & flags

;;; This is pretty complex.  Shifting the input buffer down means
;;; moving the producer pointer, owned by the interrupt handler.
;;; So disabling interrupts at some point is crucial to maintain
;;; consistent state.  But if we disabled interrupts for the entire
;;; time of shifting 250+ bytes down, we will lose input characters
;;; for sure.  So, we have to be clever and only use sei/cli sparingly.

ANYCNTC:
        phx                     ; save X
        phy                     ; save Y
        ldx iconsumer_ptr

        ;; special case - the first char - avoid a mega shift
        lda #0                  ; a value which is not ^c
        cpx iproducer_ptr
        beq @done               ; empty input buffer
        lda input_buffer,x      ; read the first char
        cmp #$03                ; check for ^c
        bne @not_first_char     ; keep searching

        inc iconsumer_ptr       ; consume it!
        jmp @done               ; and exit, A is still the ^c

@not_first_char:
        inx                     ; move up

@searchloop:
        cpx iproducer_ptr       ; have we reached the end?
        beq @done               ; if so, then leave, A is the last char read
        lda input_buffer,x      ; read
        inx                     ; next index
        cmp #$03                ; ^c?
        bne @searchloop         ; if not loop again

        ;; We have found a ^C at index x-1
        ;; Consume it from the buffer, by sliding later
        ;; characters down.  Let Y be the source index.
        txa                     ; index to a
        tay                     ; a to y
        dey                     ; make y the index holding ^c
@shiftloop:
        sei                     ; force iproducer_ptr to stay put for a moment
        cpx iproducer_ptr       ; is the higher index the end of buffer?
        beq @done_shift         ; if so exit the loop
        cli                     ; re-enable interrupts
        lda input_buffer,x      ; fetch the higher value
        sta input_buffer,y      ; store in prior
        inx                     ; inc both indices
        iny
        jmp @shiftloop          ; and loop again

@done_shift:
        sty iproducer_ptr       ; this would be same as dec iproducer_ptr
        cli                     ; re-enable interrupts
        lda #$03                ; reload 03 for successful comparison
@done:
        ply
        plx                     ; restore X
        cmp #$03                ; set Z accordingly
        rts

;;; BYTEIN
;;; Consumes an input byte from the buffer if present.
;;; Sets C true if present & consumed, else C = 0.
;;; Return the byte (if it exists) in A.
;;; Modifies flags
;;;
BYTEIN:
        lda iproducer_ptr
        cmp iconsumer_ptr
        bne @key_was_pressed    ; if none, we can return failure right away
        clc
        rts
@key_was_pressed:

.ifdef HARDWARE_FLOW_CONTROL
        ;; If #buffers chars is < 128, call CLEAR_RTSB_A
        ;; Note we didn't do this in the zero case above, but one would expect
        ;; that between the time the buffer reached 127 bytes and now, CLEAR_RTSB_A
        ;; would have been called 127 times already.
        bmi @skip_flow_reenable
        bit forced_rtsb
        bmi @skip_flow_reenable
        CLEAR_RTSB_A
@skip_flow_reenable:
.endif

        phx
        ldx iconsumer_ptr
        lda input_buffer,x
        inc iconsumer_ptr

        sec                     ; indicate success
        plx                     ; restore X
        rts


;;;
;;; CHRIN - reads a character, if available from the input buffer.
;;; If successful, the character will be echo'd back to the output buffer,
;;; it will be returned in the A register, and the Carry flag will be set.
;;; If unsuccessful, the carry flag will be cleared.
;;;
CHRIN:
        jsr BYTEIN
        bcc @noecho
        jsr CHROUT
        sec
@noecho:
        rts

;;;
;;; MONRDKEY - spins on CHRIN until a character is available
;;; Modified - A, flags
;;;
MONRDKEY:
        jsr CHRIN
        bcc MONRDKEY
        rts

;;;
;;; Output a character.  Must return it in A as well.
;;; Modifies flags.
;;;
MONCOUT:
CHROUT:
        phx
        pha

        ;; a full buffer is one where consumer = producer - 255
        ;; which is the same as producer + 1.
        ldx oproducer_ptr
        inx
@wait_for_space:
        cpx oconsumer_ptr       ; while buffer is full
        beq @wait_for_space     ; spin...

        ldx oproducer_ptr       ; push onto queue
        sta output_buffer,x
        inc oproducer_ptr

        ;; Restart sending if !busy and ctsb_state wouldn't prohibit it
        ;; This evaluation & state change requires atomicity w.r.t. an irq.
        ldx #$80                ; prepare a busy flag for below
        sei                     ; block interrupts
        lda o_busy
.ifdef HARDWARE_FLOW_CONTROL
        ora ctsb_state
.endif
        bmi @return_from_chrout

        stx o_busy              ; set the busy bit
        cli

        ldx oconsumer_ptr
        lda output_buffer,x
        inc oconsumer_ptr
        sta ACIA_DATA
        ldx txDelay
        stx T2CL
        ldx txDelay+1
        stx T2CH                ; starts that timer

@return_from_chrout:
        cli
        pla
        plx
        rts

;;; Real simple - CR, LF
SERIAL_CRLF:
        pha
        lda #$0d
        jsr CHROUT
        lda #$0a
        jsr CHROUT
        pla
        rts

;;; Helpers to WozMon, for line editing, backspace & kill line.
;;; What really needs to be done is to implement a common line editor
;;; for both wozmon and basic and anyone else who wants to use it.
cr_clear_right_data:  .byte "\r"
clear_right_data:     .asciiz "\x1b[K"

CLRRIGHT:
        phy
        phx
        lda #<clear_right_data
        ldy #>clear_right_data
        jsr STROUT
        plx
        ply
        rts

CRCLRRIGHT:
        phx
        lda #<cr_clear_right_data
        ldy #>cr_clear_right_data
        jsr STROUT
        ldy #$ff                ; see wozmon for why this is done!
        plx
        rts

;;;
;;; Prints a null-terminated string via CHROUT
;;; A is the low half of the pointer, Y the high half
;;; Modifies A, Y, flags, and returnL, returnL+1
STROUT:
        sta tmp0
        sty tmp1
        ldy #0
@loop:
        lda (tmp0),y
        beq @end_of_string
        jsr CHROUT
        iny
        jmp @loop
@end_of_string:
        rts

;;; Must only be called from a MKSYSCALL stub location
;;; The original caller used JSR to the syscall.
;;; The stub also pushed A.
;;; This climbs the stack and patches the original JSR call
;;; so that future calls go direct.
;;; The destination target address is stored in tmp0/tmp1
syscallpatchngo:
        phx
        tsx                     ; fetch the stack index
        inx                     ; increment X index by 3
        inx
        inx
        lda $0100,x             ; read the low byte of the retaddr from the stack
        sec                     ; prepare for subtraction
        sbc #1                  ; minus 1
        sta tmp2
        inx
        lda $0100,x             ; read the high byte of the retaddr from the stack
        sbc #0                  ; finish the subtraction in the high byte
        sta tmp3
        plx                     ; done with X
        phy                     ; Y needed for sta (tmp2),y
        ldy #0
        lda tmp0
        sta (tmp2),y
        lda tmp1
        iny
        sta (tmp2),y
        ply
        pla                     ; restore A (pushed by caller)
        jmp (tmp0)              ; luckily this requires no registers

;;;
;;; A flag to force RTSB.  A program may have a need to abuse the system and block
;;; interrupts for, say, 4000us, in which case input from serial would be lost.
;;; This should mitigate that loss.  The timer tick we might be late in processing
;;; but we'll catch up.
;;;
;;; 'A' register is the new value for forced_rtsb ($80 for rtsb, $00 for not)
;;; Modifies A, flags.
;;; If clearing, the outgoing rtsb signal will be restored according to the size
;;; of the input buffer.
set_forced_rtsb:
        sta forced_rtsb
        ora #0
        bpl @clear
        SET_RTSB_A
        rts
@clear:
        lda iproducer_ptr
        cmp iconsumer_ptr
        bmi @skip_flow_reenable
        CLEAR_RTSB_A
@skip_flow_reenable:
        rts

WELCOME_MESSAGE:   .asciiz "    Welcome"
RESET:
        ;; Zero out all BIOS ZP variables
        ldx #0
@clearzp:
        stz START_OF_ZERO_INIT,x
        inx
        cpx #(END_OF_ZERO_INIT - START_OF_ZERO_INIT)
        bne @clearzp

        jsr timer_initialization
        jsr serial_initialization

        cli                     ; allow lcd to use timer

        jsr lcd_initialization
        lda #<WELCOME_MESSAGE
        ldy #>WELCOME_MESSAGE
        jsr lcd_print_string

brkcmd:
        cli
        ldx #$ff
        txs
        jmp WOZSTART

IRQ:
        pha
        phx

        ;; was this actually a BRK?
        tsx
        lda $0103,x
        bit #$10
        bne brkcmd

;;;
;;; The most urgent thing to check for is an input character
;;;
        lda ACIA_STATUS         ; clear condition
        bit #$08                ; check for character available
        beq @nochar

        lda ACIA_DATA
        ldx iproducer_ptr
        sta input_buffer,x
        inx

.ifdef HARDWARE_FLOW_CONTROL
        ;; forced rtsb might already be on - but this will do no harm
        txa
        sbc iconsumer_ptr       ; save 2 cycles and don't worry about carry
        cmp #240
        bcc @not_too_full
        SET_RTSB_A
@not_too_full:
.endif

        stx iproducer_ptr
@nochar:

;;;
;;; Next see if the output timer (Timer2) expired, so we can send the
;;; next char.
;;;
        lda IFR
        bit #%00100000          ; check if T2 is lit
        beq @t2done
        bit T2CL                ; clear interrupt
        stz o_busy              ; reset busy state
@t2done:

;;;
;;; Send the next char from the output buffer, if possible
;;;
;;; If plausible that ctsb changed even on THIS interrupt, but that's okay
;;; we'll catch it on the next character.  It's more important to get to this
;;; early in the irq
;;;

        ;; this code should be run separately, as if we restore flags
        ;; jump to a routine, which rts's.  We might have to set a flag
        ;; to say it's still on the stack so we don't put it back on
        ;; during the next interrupt

        lda o_busy
.ifdef HARDWARE_FLOW_CONTROL
        ora ctsb_state
.endif
        bmi @nosend

        ldx oconsumer_ptr
        cpx oproducer_ptr
        beq @nosend

        lda output_buffer,x
        sta ACIA_DATA
        ldx txDelay
        stx T2CL
        ldx txDelay+1
        stx T2CH                ; starts that timer
        lda #$80
        sta o_busy
        inc oconsumer_ptr
@nosend:


        ;; Quicken the exit given that the next two are rare
        lda IFR
        bit #%01011000          ; combine T1/CB1/CB2
        beq @irq_done

;;;
;;; Timer1 - the 4-byte tick counter
;;;
        bit #%01000000          ; check if timer1 is lit
        beq @t1done
        bit T1CL                ; clear T1 condition
        inc tick_counter
        bne @t1done
        inc tick_counter+1
        bne @t1done
        inc tick_counter+2
        bne @t1done
        inc tick_counter+3
@t1done:

;;;
;;; CTSB change - CB1 & CB2 of VIA
;;;
.ifdef HARDWARE_FLOW_CONTROL
        ;; Decide if CTSB has triggered or released first
        and #%00011000          ; Grab BOTH CB1/CB2 types
        beq @nocb1cb2
        ;; cb1 for UP, cb2 for down
        ;; %00010000 ==> UP
        ;; %00001000 ==> DOWN
        ;; %00011000 ==> no change
        cmp #%00011000          ; if both edges detected...
        beq @out                ; ...no change
        asl
        asl
        asl
        sta ctsb_state          ; use the CB1 value
@out:
        lda #%00011000
        sta IFR                 ; clear either/both interrupts
@nocb1cb2:
.endif

@irq_done:
        plx
        pla
        rti

NMI:    rti

.segment "SYSCALLSTUBS"
;;; The idea here is to have stable addresses for common API functions called
;;; by programs loaded into RAM.  This way when the BIOS is updated, the ram
;;; programs do not require re-linking.
;;; These stubs are at stable 16-byte aligned locations.  They patch the caller's
;;; jsr code so that future calls are more direct.

.macro MKSYSCALL TARGET
.export .ident(.concat("SYS_",.string(TARGET)))
.align 16, $00
.ident(.concat("SYS_",.string(TARGET))):
        pha
        lda #<TARGET
        sta tmp0
        lda #>TARGET
        sta tmp1
        jmp syscallpatchngo
        jmp TARGET              ; alternate re-jump point if you don't want the patch
.endmacro

        ALLSYSCALL MKSYSCALL

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "RESETVEC"
.word   NMI, RESET, IRQ
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

