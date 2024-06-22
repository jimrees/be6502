;;; This was the spinning code
;;; that worked, but was highly sensitive to correct timing
;;; and dependent on the clock rate and predictable execution
;;; times.   This alignment avoids the extra cycle required
;;; when branches cross page boundaries.

        .align 8
run_spinny_serial_demo:
        lda #%00000001
        sta DDRA                ; bit 1 is tx, 6 rx, others passive

        ldy #0
outmsgloop$:
        lda messageserial,y
        beq donemsgloop$
        sta tmpchar
        sei                     ; don't let a timer confuse us

        lda #1
        sta PORTA               ; serial idle prior to start
        jsr bit_delay$
        jsr bit_delay$

        lda #$01                ; Pin 1
        trb PORTA

        ldx #8                  ; 8-bit counter
write_bit$:
        jsr bit_delay$
        ror tmpchar             ; shift out the next bit
        bcs send_1$
        trb PORTA
        jmp tx_done$
send_1$:
        tsb PORTA
tx_done$:
        dex
        bne write_bit$

        jsr bit_delay$
        tsb PORTA                ; Send stop bit
        jsr bit_delay$

        ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        cli

        iny
        jmp outmsgloop$
donemsgloop$:

        lda #$40
        jsr lcd_set_position

        sei

rx_wait$:
        bit PORTA               ; put porta.6 into O
        bvs rx_wait$
        jsr half_bit_delay$

        lda #$80                ; pre-set only the high bit
read_bit$:
        jsr bit_delay$
        bit PORTA
        bvs one_bit$
        clc
        jmp rotate_in$
one_bit$:
        sec
rotate_in$:
        ror
        bcc read_bit$

        cmp #"\r"                         ; carriage return
        beq cr_received$
        jsr print_character
        cli
        sei
        jmp rx_wait$

cr_received$:
        cli
        rts

bit_delay$:
        phx
        ldx #13
bit_delay_1$:
        dex
        bne bit_delay_1$
        plx
        rts


half_bit_delay$:
        phx
        ldx #6
half_bit_delay_1$:
        dex
        bne half_bit_delay_1$
        plx
        rts
