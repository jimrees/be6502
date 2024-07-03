
%.o: %.s
	ca65 -D HARDWARE_FLOW_CONTROL=1 --list-bytes 255 --verbose -l $*.list $<

bios.bin: bios.o wozmon.o msbasic/tmp/msbasic.o lcd.o acia.o timer.o decimalprint.o
	ld65 -Ln bios.map -C bios.cfg -o $@ $^

msbasic/tmp/msbasic.o:
	$(MAKE) -C msbasic

christmas.prog: christmas.o

sensor.prog: sensor.o decimalprint.o timer.o

%.prog: %.o
	ld65 -Ln $*.map -C prog.cfg -o $* $^

%.burn: %.bin
	minipro -u -p AT28C256 -w $<

%.verify: %.bin
	minipro -p AT28C256 --verify $<

%.bin: %.o
	ld65 -Ln $*.vmap -C bios.cfg -o $@ $<

%.list: %.o
	@true

%.woz: %.bin bin2ld
	./bin2ld 0x1000 $*.bin > $@

%.copy: %.prog
	$(MAKE) bin2ld
	./bin2ld 0x1000 $< | pbcopy

# Don't delete bin files just because the burn failed.
.PRECIOUS: %.bin %.o

clean:
	$(RM) *.bin *.list

bind2ld: bin2ld.cpp
	c++ -O1 -o $@ $<
