.include "via_defs.s"
;;; Versatile Interface Adapter mapped addresses
PORTB = $6000
PORTA = $6001
DDRB = $6002
DDRA = $6003
T1CL = $6004
T1CH = $6005
T1LL = $6006
T1LH = $6007
T2CL = $6008
T2CH = $6009
SHIFTR = $600A
ACR = $600B           ; [ T1{2} | T2{1} | SR{3} | PB | PA ]
PCR = $600C           ; [ CB2{3} | CB1{1} | CA2{3} | CA1{1} | PCR ]
IFR = $600D           ; [ IRQ TIMER1 TIMER2 CB1 CB2 SHIFTREG CA1 CA2 ]
IER = $600E           ; [ Set/Clr TIMER1 TIMER2 CB1 CB2 SR CA1 CA2 ]
