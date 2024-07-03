.ifndef TIMER_DEFS_H
        TIMER_DEFS_H := 1
        CLOCKS_PER_SECOND = 1000000
        TIMER_FREQUENCY = 100           ; 100 ticks/second
        CLOCKS_PER_TICK = CLOCKS_PER_SECOND/TIMER_FREQUENCY

;;; .import delayseconds, delayticks

.endif
