.include "via_defs.s"
;;; Versatile Interface Adapter mapped addresses
VIA_BASE = $6000
PORTB = VIA_BASE + $0
PORTA = VIA_BASE + $1
DDRB = VIA_BASE + $2
DDRA = VIA_BASE + $3
T1CL = VIA_BASE + $4
T1CH = VIA_BASE + $5
T1LL = VIA_BASE + $6
T1LH = VIA_BASE + $7
T2CL = VIA_BASE + $8
T2CH = VIA_BASE + $9
SHIFTR = VIA_BASE + $A
ACR = VIA_BASE + $B   ; [ T1{2} | T2{1} | SR{3} | PB | PA ]
PCR = VIA_BASE + $C   ; [ CB2{3} | CB1{1} | CA2{3} | CA1{1} | PCR ]
IFR = VIA_BASE + $D   ; [ IRQ TIMER1 TIMER2 CB1 CB2 SHIFTREG CA1 CA2 ]
IER = VIA_BASE + $E   ; [ Set/Clr TIMER1 TIMER2 CB1 CB2 SR CA1 CA2 ]
