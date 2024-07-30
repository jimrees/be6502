
clean:
	$(RM) $(filter-out bios.map,$(wildcard *.map)) $(wildcard *.prog)
	$(RM) *.o *.list *.prog bin2ld bin2xm *.o64 *.vice *.map
	$(MAKE) -C msbasic clean

#ASSEMBLER_LISTINGS=--list-bytes 255 --verbose -l $*.list

%.o: %.s $(wildcard *_defs.s)
	ca65 -D REES=1 -D HARDWARE_FLOW_CONTROL=1 $(ASSEMBLER_LISTINGS) $<

################################################################
# Build/burn/verify the bios

bios.bin: bios.cfg bios.o wozmon.o msbasic/tmp/msbasic.o lcd.o acia.o timer.o decimalprint.o via.o xmodem.o
	ld65 -Ln bios.map -C bios.cfg -o bios $(filter %.o,$^)

%.burn: %.bin
	minipro -p AT28C256 -uPw $<

%.verify: %.bin
	minipro -p AT28C256 --verify $<

################################################################

christmas.o64: christmas.o prog.cfg
printchars.o64: printchars.o prog.cfg
sensor.o64: sensor.o via.o prog.cfg
ilcdtest.o64: ilcdtest.o libi2c.o libilcd.o via.o prog.cfg
i2cscan.o64: i2cscan.o libi2c.o via.o prog.cfg
timeop.o64: timeop.o via.o prog.cfg

msbasic/tmp/msbasic.o: ALWAYS
	$(MAKE) -C msbasic

msbasic.o64: msbasic/tmp/msbasic.o basic.cfg


#VERBOSE=-v
#GEN_VICE=-Ln $*.vice
#GEN_MAP=-m $*.map

%.o64: o64header.o syscalls.o
	@test $(words $(filter %.cfg,$^)) = 1 || (echo $@ needs a single .cfg file in its dependencies ; false)
	ld65 $(VERBOSE) $(GEN_VICE) $(GEN_MAP) -C $(filter %.cfg,$^) -o $* $(filter %.o,$^)

# obsolete
%.copy: %.prog bin2ld
	./bin2ld 0x0500 $< | pbcopy

#%.o64: %.prog bin2xm
#	./bin2xm 0x0500 $< > $@

#bin2ld: bin2ld.cpp
#	c++ -std=c++20 -O1 -o $@ $<

#bin2xm: bin2xm.cpp
#	c++ -std=c++20 -O1 -o $@ $<

# Don't delete bin files just because the burn failed.
.PRECIOUS: %.bin %.o %.prog bin2ld bin2xm
.PHONY: ALWAYS
ALWAYS:
	@true
