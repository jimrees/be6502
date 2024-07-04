
clean:
	$(RM) $(filter-out bios.map,$(wildcard *.map)) $(wildcard *.prog)
	$(RM) *.o *.list *.woz *.prog bin2ld bin2xm *.of64

%.o: %.s $(wildcard *_defs.s)
	ca65 -D HARDWARE_FLOW_CONTROL=1 --list-bytes 255 --verbose -l $*.list $<

bios.bin: bios.cfg bios.o wozmon.o msbasic/tmp/msbasic.o lcd.o acia.o timer.o decimalprint.o via.o xmodem.o
	ld65 -Ln bios.map -C bios.cfg -o bios $(filter %.o,$^)

christmas.prog: christmas.o syscalls.o prog.cfg
printchars.prog: printchars.o syscalls.o prog.cfg
sensor.prog: sensor.o via.o syscalls.o prog.cfg
xmodem.prog: xmodem.o syscalls.o xmodem.cfg

msbasic/tmp/msbasic.o:
	$(MAKE) -C msbasic

msbasic/tmp/msbasic.prog: msbasic/tmp/msbasic.o syscalls.o basic.cfg

%.burn: %.bin
	minipro -p AT28C256 -uPw $<

%.verify: %.bin
	minipro -p AT28C256 --verify $<


%.prog: %.o
	ld65 -Ln $*.map -C $(filter %.cfg,$^) -o $* $(filter %.o,$^)

%.copy: %.prog bin2ld
	./bin2ld 0x0500 $< | pbcopy

%.of64: %.prog bin2xm
	./bin2xm 0x0500 $< > $@

bin2ld: bin2ld.cpp
	c++ -std=c++20 -O1 -o $@ $<

bin2xm: bin2xm.cpp
	c++ -std=c++20 -O1 -o $@ $<

# Don't delete bin files just because the burn failed.
.PRECIOUS: %.bin %.o %.prog bin2ld bin2xm
