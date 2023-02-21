subdirs := $(wildcard */)
sources := $(wildcard *.asm) $(wildcard $(addsuffix *.asm, $(subdirs)))
objects := $(addprefix obj/, $(patsubst %.asm,%.o,$(notdir $(sources))))
deps := $(objects:.o=.d)

program = throwing-shapes
BINDIR = ~/projects/vscode-amiga-debug/bin/darwin

CC =  $(BINDIR)/opt/bin/m68k-amiga-elf-gcc
ELF2HUNK =  $(BINDIR)/elf2hunk
FSUAE = $(BINDIR)/fs-uae/fs-uae
VASM = $(BINDIR)/vasmm68k_mot
MKADF = ~/amiga/bin/mkadf

CCFLAGS = -g -MP -MMD -m68000 -Ofast -nostdlib -Wextra -Wno-unused-function -Wno-volatile-register-var -fomit-frame-pointer -fno-tree-loop-distribution -flto -fwhole-program -fno-exceptions
LDFLAGS = -Wl,--emit-relocs,-Ttext=0,-Map=out/$(program).map
VASMFLAGS = -m68000 -x -opt-size
UAEFLAGS = --amiga_model=A500 --floppy_drive_0_sounds=off

exe: out/$(program).exe

run: exe
	$(FSUAE) $(UAEFLAGS) --hard_drive_1=./out

dist: dist/$(program).adf

rundist: dist/$(program).adf
	$(FSUAE) $(UAEFLAGS) $<

dist/$(program).adf: dist/bootblock
	$(MKADF) $< > $@

dist/bootblock: effect.asm
	$(VASM) $< $(VASMFLAGS) -Fbin -opt-size -nosym -pic -DBOOT=1 -o $@

out/$(program).exe: out/$(program).elf
	$(info Elf2Hunk $(program).exe)
	$(ELF2HUNK) out/$(program).elf out/$(program).exe -s -v

out/$(program).elf: $(objects)
	$(info Linking $(program).elf)
	$(CC) $(CCFLAGS) $(LDFLAGS) $(objects) -o $@
#	m68k-amiga-elf-objdump --disassemble --no-show-raw-ins --visualize-jumps -S $@ >$(program).s

-include $(deps)

$(objects): obj/%.o : %.asm
	$(info Assembling $<)
	$(VASM) $(VASMFLAGS) -Felf -dwarf=3 -o $@ $(CURDIR)/$<

$(deps): obj/%.d : %.asm
	$(info Building dependencies for $<)
	$(VASM) $(VASMFLAGS) -depend=make -quiet -o $(patsubst %.d,%.o,$@) $(CURDIR)/$< > $@

clean:
	$(info Cleaning...)
	$(RM) obj/* dist/* out/*.*

.PHONY: rundist dist run exe clean