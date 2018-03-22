MARSDEV ?= ${HOME}/mars
MARSBIN  = $(MARSDEV)/m68k-elf/bin
TOOLSBIN = $(MARSDEV)/bin

CC   = $(MARSBIN)/m68k-elf-gcc
AS   = $(MARSBIN)/m68k-elf-as
LD   = $(MARSBIN)/m68k-elf-ld
NM   = $(MARSBIN)/m68k-elf-nm
OBJC = $(MARSBIN)/m68k-elf-objcopy

# Z80 Assembler to build XGM driver
ASMZ80   = $(TOOLSBIN)/sjasm
# SGDK Tools
BINTOS   = $(TOOLSBIN)/bintos
LZ4W     = java -jar $(TOOLSBIN)/lz4w.jar
RESCOMP  = $(TOOLSBIN)/rescomp
WAVTORAW = $(TOOLSBIN)/wavtoraw
XGMTOOL  = $(TOOLSBIN)/xgmtool
# Sik's Tools
MDTILER  = $(TOOLSBIN)/mdtiler
SLZ      = $(TOOLSBIN)/slz
UFTC     = $(TOOLSBIN)/uftc
ifeq ($(shell test -e $(MDTILER) || echo -n no),no)
    MDTILER = bin/mdtiler
endif

# Some files needed are in a versioned directory
GCC_VER := $(shell $(CC) -dumpversion)
PLUGIN   = $(MARSDEV)/m68k-elf/libexec/gcc/m68k-elf/$(GCC_VER)
LTO_SO   = liblto_plugin.so
ifeq ($(OS),Windows_NT)
	LTO_SO = liblto_plugin-0.dll
endif

INCS     = -Isrc -Ires -Iinc
LIBS     = -L$(MARSDEV)/m68k-elf/lib/gcc/m68k-elf/$(GCC_VER)
CCFLAGS  = -m68000 -Wall -Wextra -std=c99 -ffreestanding
OPTIONS  = 
ASFLAGS  = -m68000 --register-prefix-optional
LDFLAGS  = -T $(MARSDEV)/ldscripts/sgdk.ld -nostdlib
Z80FLAGS = -isrc/xgm

# Stage layout files to compress
PXMS  = $(wildcard res/Stage/*.pxm)
PXMS += $(wildcard res/Stage/*/*.pxm)
CPXMS = $(PXMS:.pxm=.cpxm)

# mdtiler scripts to generate tile patterns & mappings
MDTS  = $(wildcard res/*.mdt)
MDTS += $(wildcard res/*/*.mdt)
PATS  = $(MDTS:.mdt=.pat)
MAPS  = $(MDTS:.mdt=.map)

RESS  = res/resources.res
Z80S  = $(wildcard src/xgm/*.s80)
CS    = $(wildcard src/*.c)
CS   += $(wildcard src/ai/*.c)
CS   += $(wildcard src/db/*.c)
SS    = $(wildcard src/*.s)
SS   += $(wildcard src/xgm/*.s)
OBJS  = $(RESS:.res=.o)
OBJS += $(Z80S:.s80=.o)
OBJS += $(CS:.c=.o)
OBJS += $(SS:.s=.o)

ASMO  = $(CS:%.c=asmout/%.s)

.SECONDARY: doukutsu.elf

.PHONY: all pal release asm debug prereq main-build

all: release
pal: release

release: OPTIONS  = -Ofast -fno-web -fno-gcse -fno-unit-at-a-time -fomit-frame-pointer
release: OPTIONS += -frename-registers -fshort-enums
release: OPTIONS += -flto -fuse-linker-plugin
release: main-build symbol.txt

asm: OPTIONS  = -Ofast -fno-web -fno-gcse -fno-unit-at-a-time -fomit-frame-pointer
asm: OPTIONS += -frename-registers -fshort-enums
asm: head-gen asm-dir $(ASMO)

# Gens-KMod, BlastEm and UMDK support GDB tracing, enabled by this target
debug: OPTIONS = -g -Og -DDEBUG -DKDEBUG
debug: main-build symbol.txt

main-build: prereq head-gen doukutsu.bin

prereq: $(LIBPNG) $(MDTILER)

# Cross reference symbol.txt with the addresses displayed in the crash handler
symbol.txt: doukutsu.bin
	$(NM) --plugin=$(PLUGIN)/$(LTO_SO) -n doukutsu.elf > symbol.txt

boot.o:
	$(AS) $(ASFLAGS) boot.s -o $@

%.bin: %.elf
	@echo "Stripping ELF header..."
	@$(OBJC) -O binary $< temp.bin
	@dd if=temp.bin of=$@ bs=8K conv=sync
	@rm -f temp.bin

%.elf: boot.o $(PATS) $(OBJS)
	$(CC) -o $@ $(LDFLAGS) boot.o $(OBJS) $(LIBS)

%.o: %.c
	@echo "CC $<"
	@$(CC) $(CCFLAGS) $(OPTIONS) $(INCS) -c $< -o $@

%.o: %.s 
	@echo "AS $<"
	@$(AS) $(ASFLAGS) $< -o $@

%.s: %.res
	$(RESCOMP) $< $@

%.o80: %.s80
	$(ASMZ80) $(Z80FLAGS) $< $@ out.lst

%.s: %.o80
	$(BINTOS) $<

# For asm target
asm-dir:
	mkdir -p asmout/src/{ai,db,xgm}

asmout/%.s: %.c
	$(CC) $(CCFLAGS) $(OPTIONS) $(INCS) -S $< -o $@

# Compression of stage layouts
%.cpxm: %.pxm
	$(SLZ) -c "$<" "$@"

%.pat: %.mdt
	$(MDTILER) -b "$<"

.PHONY: head-gen clean

head-gen:
	rm -f inc/ai_gen.h
	python aigen.py

clean:
	rm -f $(CPXMS) $(PATS) $(MAPS) $(OBJS)
	rm -f doukutsu.bin doukutsu.elf symbol.txt boot.o
	rm -f src/xgm/z80_xgm.s src/xgm/z80_xgm.o80 src/xgm/z80_xgm.h out.lst
	rm -f res/resources.h res/resources.s inc/ai_gen.h
	rm -rf asmout
