
%.bin: %.s
	vasm -L $*.list -wdc02 -dotdir -Fbin -o $@ $<

%.list: %.bin
	@true

%.burn: %.bin
	minipro -u -p AT28C256 -w $<

%.verify: %.bin
	minipro -u -p AT28C256 --verify $<

# Don't delete bin files just because the burn failed.
.PRECIOUS: %.bin

clean:
	$(RM) *.bin *.list
