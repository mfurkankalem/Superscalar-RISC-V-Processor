SV_FILES = ${wildcard ./src/pkg/*.sv} ${wildcard ./src/*.sv} 
TB_FILES = ${wildcard ./tb/*.sv}
ALL_FILES = ${SV_FILES} ${TB_FILES}

CC      = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy
HEXDUMP = hexdump

all: lint run

assembler:
	$(CC) -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -Ttext 0x00000000 ./test/test.S -o ./test/test.elf
	$(OBJCOPY) -O binary ./test/test.elf ./test/test.bin
	$(HEXDUMP) -v -e '1/4 "%08x\n"' ./test/test.bin > ./test/test.hex

lint:
	verilator --lint-only -Wall --timing -Wno-UNUSED -Wno-MULTIDRIVEN -Wno-CASEINCOMPLETE ${ALL_FILES}

build:
	verilator --binary ${SV_FILES} ${TB_FILES} --top tb -j 0 --trace -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN

run: build assembler
	obj_dir/Vtb

wave: run
	gtkwave --dark dump.vcd

clean:
	rm -f dump.vcd
	rm -f ./test/test.elf ./test/test.bin ./test/test.hex
	rm -rf obj_dir/

.PHONY: all assembler lint build run wave clean