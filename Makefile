AS=asl
P2BIN=p2bin
SRC=patch.s
BSPLIT=bsplit
MAME=mame

ASFLAGS=-i . -n -U

.PHONY: all clean prg.bin prg.o

all: prg.bin

prg.orig:
	stat prg0.bin
	stat prg1.bin
	$(BSPLIT) c prg0.bin prg1.bin prg.orig

prg.o: prg.orig
	$(AS) $(SRC) $(ASFLAGS) -o prg.o

prg.bin: prg.o
	$(P2BIN) $< $@ -r \$$-0xFFFFF
	$(BSPLIT) s prg.bin prg0.bin prg1.bin

clean:
	@-rm -f prg0.bin
	@-rm -f prg1.bin
	@-rm -f prg.o
	$(BSPLIT) s prg.orig prg0.bin prg1.bin
