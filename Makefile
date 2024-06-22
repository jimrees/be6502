
%.bin: %.s decimalprint.s lcd.s macros.s pre_uart_serial.s via.s acia.s timer.s
	vasm -L $*.list -esc -wdc02 -dotdir -Fbin -o $@ $<

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
