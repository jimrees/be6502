.setcpu "65C02"
.debuginfo +
.feature string_escapes on

.export SERIAL_CRLF
.export CHRIN, CHROUT, MONCOUT, MONRDKEY, STROUT, LOAD, SAVE
.export ANYCNTC, AAA_GO_BASIC, DOPRASTAT
.export input_buffer, output_buffer, irqHook, defaultIRQHook
.export returnL, tick_counter, txDelay

.import COLD_START
.import WOZSTART
.import serial_initialization
.import lcd_home, lcd_print_binary8, lcd_clear, lcd_print_character
.import lcd_set_position, lcd_initialization, lcd_print_hex8, lcd_print_n_spaces
.import lcd_print_string
.import timer_initialization

.include "via.s"
.include "acia_defs.s"

.segment "BIOSZP" : zeropage
START_OF_ZERO_INIT:
tick_counter:   .res 4          ; used by the timer interrupt

o_busy:         .res 1          ; serial interrupt managemetn [BUSY ...]
.ifdef HARDWARE_FLOW_CONTROL
ctsb_state:     .res 1 ; [CTSB ...]
forced_rtsb:    .res 1 ; [FORCED ...]
.endif

returnL:        .res 2          ; used primarily by syscallpatchngo, but also for general use as a 2-byte temporary

patchAddr:      .res 2
iproducer_ptr:  .res 1
iconsumer_ptr:  .res 1
oproducer_ptr:  .res 1
oconsumer_ptr:  .res 1
END_OF_ZERO_INIT:
txDelay:        .res 2          ; tune-able value for ACIA output delay
irqHook:        .res 2
.segment "BIOS_BUFFERS"
;;; As circular buffers indexed by an 8-bit value, these must be page-aligned
.align 256
input_buffer:   .res $100
output_buffer:  .res $100

.segment "BIOS_CODE"

.macro SET_RTSB_A
        lda #$80
        tsb PORTB
.endmacro

.macro CLEAR_RTSB_A
        lda #$80
        trb PORTB
.endmacro

;;; A hack so that 8000R always gets to Basic
AAA_GO_BASIC:
        jmp COLD_START

;;; Called from BASIC to print ACIA_STATUS on the lcd
DOPRASTAT:
        pha
        jsr lcd_home
        lda ACIA_STATUS
        jsr lcd_print_binary8

.ifdef HARDWARE_FLOW_CONTROL
        lda #' '
        jsr lcd_print_character
        lda ctsb_state
        jsr lcd_print_hex8
.endif

        pla
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

;;; CHRIN
;;; Consumes an input character from the buffer if present.
;;; Sets C true if present & consumed, else C = 0.
;;; Return the character (if it exists) in A.
;;; Modifies A, flags
;;;
CHRIN:
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

        jsr CHROUT              ; echo

        sec                     ; indicate success
        plx                     ; restore X
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

;;;
;;; Prints a null-terminated string via CHROUT
;;; A is the low half of the pointer, Y the high half
;;; Modifies A, Y, flags, and returnL, returnL+1
STROUT:
        sta returnL
        sty returnL+1
        ldy #0
@loop:
        lda (returnL),y
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
syscallpatchngo:
        phx
        tsx                     ; fetch the stack index
        txa                     ; transfer to A
        clc                     ; clear carry for addition
        adc #3                  ; back up to the low byte
        tax                     ; save to x index
        lda $0100,x             ; read the low byte of the retaddr from the stack
        sec                     ; prepare for subtraction
        sbc #1                  ; minus 1
        sta returnL
        inx
        lda $0100,x             ; read the high byte of the retaddr from the stack
        sbc #0                  ; finish the subtraction in the high byte
        sta returnL+1
        plx                     ; done with X
        phy                     ; Y needed for sta (returnL),y
        ldy #0
        lda patchAddr
        sta (returnL),y
        lda patchAddr+1
        iny
        sta (returnL),y
        ply
        pla                     ; restore A (pushed by caller)
        jmp (patchAddr)         ; luckily this requires no registers


restore_default_irq_hook:
        pha
        lda #<defaultIRQHook
        sta irqHook
        lda #>defaultIRQHook
        sta irqHook+1
        pla
        rts

;;;
;;; A&Y contain a pointer to the new hook
;;; The old hook is returned in A/Y
install_irq_hook:
        pha
        phy
        ;; copy current hook elsewhere temporarily
        lda irqHook
        sta returnL
        lda irqHook+1
        sta returnL+1

        ;; install the new hook
        ply
        sty irqHook+1
        pla
        sta irqHook

        lda returnL
        ldy returnL+1
        rts

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

        jsr restore_default_irq_hook
        jsr timer_initialization
        jsr lcd_initialization

        lda #'.'
        jsr lcd_print_character

        jsr serial_initialization

        lda #'.'
        jsr lcd_print_character

        cli                     ; enable interrupts

        jsr lcd_clear
        lda #<WELCOME_MESSAGE
        ldy #>WELCOME_MESSAGE
        jsr lcd_print_string

        jmp WOZSTART

IRQ:
        pha
        phx

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
        ;; jmp (irqHook)  - possibly too expensive
        rti

defaultIRQHook:
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
        sta patchAddr
        lda #>TARGET
        sta patchAddr+1
        jmp syscallpatchngo
        jmp TARGET              ; alternate re-jump point if you don't want the patch
.endmacro

        MKSYSCALL CHROUT
        MKSYSCALL CHRIN
        MKSYSCALL ANYCNTC
        MKSYSCALL lcd_clear
        MKSYSCALL lcd_home
        MKSYSCALL lcd_set_position
        MKSYSCALL lcd_print_hex8
        MKSYSCALL lcd_print_binary8
        MKSYSCALL lcd_print_character
        MKSYSCALL lcd_print_n_spaces
        MKSYSCALL SERIAL_CRLF
        MKSYSCALL STROUT
        MKSYSCALL lcd_print_string
        MKSYSCALL restore_default_irq_hook
        MKSYSCALL install_irq_hook
        MKSYSCALL set_forced_rtsb

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "RESETVEC"
.word   NMI, RESET, IRQ
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

