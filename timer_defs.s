.ifndef TIMER_DEFS_H
        TIMER_DEFS_H := 1
        CLOCKS_PER_SECOND = 1000000
        TIMER_FREQUENCY = 100           ; 100 ticks/second
        CLOCKS_PER_TICK = CLOCKS_PER_SECOND/TIMER_FREQUENCY

.global delayseconds
.global delayticks
.global timer_initialization    ; only for bios!
.globalzp tick_counter          ; allocated in the bios only

.endif
