SV_FILES = ${wildcard ./src/pkg/*.sv} ${wildcard ./src/*.sv} 
TB_FILES = ${wildcard ./tb/*.sv}
ALL_FILES = ${SV_FILES} ${TB_FILES}


VERILATOR_FLAGS = --binary ${ALL_FILES} --top tb \
                  -j 2 -O0 --trace --trace-max-array 256 \
                  -CFLAGS "-O0" \
                  -MAKEFLAGS "OPT_FAST=-O0 OPT_SLOW=-O0" \
                  -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN

all: lint run

assembler:
	riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -Ttext 0x00000000 ./test/test.S -o ./test/test.elf
	riscv64-unknown-elf-objcopy -O binary ./test/test.elf ./test/test.bin
	hexdump -v -e '1/4 "%08x\n"' ./test/test.bin > ./test/test.hex

lint:
	verilator --lint-only -Wall --timing -Wno-UNUSED -Wno-MULTIDRIVEN -Wno-CASEINCOMPLETE ${ALL_FILES}

build:
	verilator ${VERILATOR_FLAGS}

run: build 
	obj_dir/Vtb

wave: run
	gtkwave --dark dump.vcd

clean:
	rm -f dump.vcd
	rm -f ./test/test.elf ./test/test.bin ./test/test.hex
	rm -rf obj_dir/

.PHONY: all assembler lint build run wave clean