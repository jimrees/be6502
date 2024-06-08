
%.bin: %.s
	vasm -c02 -dotdir -Fbin -o $@ $<

%.burn: %.bin
	minipro -u -p AT28C256 -w $<

# Don't delete bin files just because the burn failed.
.PRECIOUS: %.bin

clean:
	$(RM) *.bin
