
CLOCKS_PER_SECOND = 1000000
TIMER_FREQUENCY = 100           ; 100 ticks/second
CLOCKS_PER_TICK = CLOCKS_PER_SECOND/TIMER_FREQUENCY

timer_initialization:
        ;; Set up repeat mode on a 10,000 frequency
        ;; 9998 = 270e
        stz tick_counter
        stz tick_counter+1
        stz tick_counter+2
        stz tick_counter+3
        lda #%01000000          ; enable continuous mode for timer1
        sta ACR

        lda #<(CLOCKS_PER_TICK-2)
        sta T1CL
        lda #>(CLOCKS_PER_TICK-2)
        sta T1CH
        lda #%11000000          ; turn on timer1 interrupts
        sta IER
        cli                     ; stop masking interrupts
        rts

        ;; this waits until the tick_counter == the target value
        ;; The count of ticks to wait is in A
        ;; Since interrupts are required to get us to the target,
        ;; we might as well use wai in the loop and reduce power
        ;; usage.
delayticks:
        clc
        adc tick_counter
delay_wait$:
        wai
        cmp tick_counter
        bne delay_wait$
        rts

        ;; A is # seconds, up to 255.
        ;; This multiplies by 100, storing the result in the two-byte value buffer
        ;; Then it adds the (atomically-sampled) low two bytes of tick_counter.
        ;; This becomes the target time to wait for.
delayseconds:
        sta value
        stz value+1
        MULTIPLY_BY TIMER_FREQUENCY,value
        lda value
        clc
        sei
        adc tick_counter
        sta value
        lda value+1
        adc tick_counter+1
        cli
        sta value+1
        ;; now [ value+1 value ] are the target time to wait for
ds_wait$:
        wai
        ;; check for value+1 == tick_counter+1, then the low bits
        lda tick_counter+1
        cmp value+1
        bne ds_wait$
        lda tick_counter
        cmp value
        bne ds_wait$
        rts
delayseconds_end: