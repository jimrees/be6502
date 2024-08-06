;;;
;;; This file says these items are defined somewhere.
;;; If linked with the ROM, then yes, they're around here
;;; somewhere.
;;; If for a program, syscalls.o must be included to resolve
;;; locations to stub functions.
.ifndef BIOS_DEFS_S
BIOS_DEFS_S := 1

.global CHROUT, MONCOUT
.global CHRIN, MONRDKEY, BYTEIN
.global LOAD, SAVE
.global ANYCNTC
.global SERIAL_CRLF, CLRRIGHT, CRCLRRIGHT
.global STROUT
.global set_forced_rtsb
.global WOZSTART
.globalzp txDelay

.endif
