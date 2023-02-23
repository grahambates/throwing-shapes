source = effect.asm
program = out/throwing-shapes
BINDIR = ~/projects/vscode-amiga-debug/bin/darwin

ELF2HUNK =  $(BINDIR)/elf2hunk
FSUAE = $(BINDIR)/fs-uae/fs-uae
VASM = $(BINDIR)/vasmm68k_mot
MKADF = ~/amiga/bin/mkadf

VASMFLAGS = -m68000 -x -opt-size
UAEFLAGS = --amiga_model=A500 --floppy_drive_0_sounds=off

# Executable preview

exe: $(program).exe

run: exe
	$(FSUAE) $(UAEFLAGS) --hard_drive_1=./out

$(program).exe: $(program).elf
	$(info Elf2Hunk $(@))
	$(ELF2HUNK) $< $@ -s -v

$(program).elf: $(source)
	$(info Assembling $<)
	$(VASM) $(VASMFLAGS) -Felf -dwarf=3 -o $@ $<

$(program).d: $(source)
	$(info Building dependencies for $<)
	$(VASM) $(VASMFLAGS) -depend=make -quiet -o $(program).elf $< > $@
	$(VASM) $(VASMFLAGS) -depend=make -quiet -o $(program).bb $< >> $@

# Bootblock

dist: $(program).adf

rundist: $(program).adf
	$(FSUAE) $(UAEFLAGS) $<

$(program).bb: $(source)
	$(info Assembling bootblock for $<)
	$(VASM) $< $(VASMFLAGS) -Fbin -opt-size -nosym -pic -DBOOT=1 -o $@

$(program).adf: $(program).bb
	$(info Installing bootblock $<)
	$(MKADF) $< > $@

-include $(program).d

clean:
	$(info Cleaning...)
	$(RM) out/*.*

.PHONY: rundist dist run exe clean