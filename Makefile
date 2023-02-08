subdirs := $(wildcard */)
sources := $(wildcard *.asm) $(wildcard $(addsuffix *.asm, $(subdirs)))
objects := $(addprefix obj/, $(patsubst %.asm,%.o,$(notdir $(sources))))
deps := $(objects:.o=.d)

program = out/throwing-shapes
BINDIR = ~/projects/vscode-amiga-debug/bin/darwin

CC =  $(BINDIR)/opt/bin/m68k-amiga-elf-gcc
ELF2HUNK =  $(BINDIR)/elf2hunk
FSUAE = $(BINDIR)/fs-uae/fs-uae
VASM = $(BINDIR)/vasmm68k_mot
MKADF = ~/amiga/bin/mkadf

CCFLAGS = -g -MP -MMD -m68000 -Ofast -nostdlib -Wextra -Wno-unused-function -Wno-volatile-register-var -fomit-frame-pointer -fno-tree-loop-distribution -flto -fwhole-program -fno-exceptions
LDFLAGS = -Wl,--emit-relocs,-Ttext=0,-Map=$(program).map
VASMFLAGS = -m68000 -quiet -x -opt-size
UAEFLAGS = --amiga_model=A500 --floppy_drive_0_sounds=off

all: $(program).exe

dist: dist/a.adf

dist/a.adf: dist/bootblock
	$(MKADF) $< > $@

dist/bootblock: effect.asm
	$(VASM) $< $(VASMFLAGS) -Fbin -opt-size -nosym -pic -DBOOT=1 -o $@

out/dist.exe: effect.asm
	$(VASM) $< $(VASMFLAGS) -Fbin -opt-size -nosym -pic -Fhunkexe -o $@

run: all
	$(FSUAE) $(UAEFLAGS) --hard_drive_1=./out

rundist: dist/a.adf
	$(FSUAE) $(UAEFLAGS) $<

$(program).exe: $(program).elf
	$(info Elf2Hunk $(program).exe)
	$(ELF2HUNK) $(program).elf $(program).exe -s -v

$(program).elf: $(objects)
	$(info Linking $(program).elf)
	$(CC) $(CCFLAGS) $(LDFLAGS) $(objects) -o $@
#	m68k-amiga-elf-objdump --disassemble --no-show-raw-ins --visualize-jumps -S $@ >$(program).s

clean:
	$(info Cleaning...)
	$(RM) obj/* dist/* $(program).*

-include $(deps)

$(objects): obj/%.o : %.asm
	$(info Assembling $<)
	$(VASM) $(VASMFLAGS) -Felf -dwarf=3 -o $@ $(CURDIR)/$<

$(deps): obj/%.d : %.asm
	$(info Building dependencies for $<)
	$(VASM) $(VASMFLAGS) -depend=make -o $(patsubst %.d,%.o,$@) $(CURDIR)/$< > $@
