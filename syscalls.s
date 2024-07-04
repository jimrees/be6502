
.include "syscall_defs.s"

.macro NEXTADDR NAME
.export NAME
NAME: .res 16
.endmacro

.segment "DUMMY" : absolute
.org $F000

        ALLSYSCALL NEXTADDR

;;; WOZ is special for no particular reason
.export WOZSTART = $FF00

;;; Same as CHROUT
.export MONCOUT = CHROUT
