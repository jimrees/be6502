
clean:
	$(RM) $(filter-out bios.map,$(wildcard *.map)) $(wildcard *.prog)
	$(RM) *.o *.list *.woz *.prog bin2ld

%.o: %.s $(wildcard *_defs.s)
	ca65 -D HARDWARE_FLOW_CONTROL=1 --list-bytes 255 --verbose -l $*.list $<

bios.bin: bios.o wozmon.o msbasic/tmp/msbasic.o lcd.o acia.o timer.o decimalprint.o via.o
	ld65 -Ln bios.map -C bios.cfg -o $@ $^

christmas.prog: christmas.o syscalls.o prog.cfg
printchars.prog: printchars.o syscalls.o prog.cfg
sensor.prog: sensor.o via.o syscalls.o prog.cfg

msbasic/tmp/msbasic.o:
	$(MAKE) -C msbasic

msbasic/tmp/msbasic.prog: msbasic/tmp/msbasic.o syscalls.o basic.cfg

%.prog: %.o
	ld65 -Ln $*.map -C $(filter %.cfg,$^) -o $* $(filter %.o,$^)

%.burn: %.bin
	minipro -p AT28C256 -uPw $<

%.verify: %.bin
	minipro -p AT28C256 --verify $<

%.bin: %.o
	ld65 -Ln $*.vmap -C bios.cfg -o $@ $<

%.list: %.o
	@true

%.woz: %.bin bin2ld
	./bin2ld 0x0500 $*.bin > $@

%.copy: %.prog
	$(MAKE) bin2ld
	./bin2ld 0x0500 $< | pbcopy

# Don't delete bin files just because the burn failed.
.PRECIOUS: %.bin %.o

bind2ld: bin2ld.cpp
	c++ -O1 -o $@ $<
