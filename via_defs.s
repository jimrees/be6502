.ifndef VIA_DEFS_S
        VIA_DEFS_S := 1
;;; Versatile Interface Adapter mapped addresses
.global PORTB
.global PORTA
.global DDRB
.global DDRA
.global T1CL
.global T1CH
.global T1LL
.global T1LH
.global T2CL
.global T2CH
.global SHIFTR
.global ACR           ; [ T1{2} | T2{1} | SR{3} | PB | PA ]
.global PCR           ; [ CB2{3} | CB1{1} | CA2{3} | CA1{1} | PCR ]
.global IFR           ; [ IRQ TIMER1 TIMER2 CB1 CB2 SHIFTREG CA1 CA2 ]
.global IER           ; [ Set/Clr TIMER1 TIMER2 CB1 CB2 SR CA1 CA2 ]
.endif
