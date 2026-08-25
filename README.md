A superscalar RISC-V processor implemented in SystemVerilog, verified with Verilator. The i2oi name stands for in-order fetch/decode, out-of-order issue: instructions are fetched and decoded in program order, but issue one per cycle into one of two independent execution paths (ALU or MEM). Once issued, an ALU-path instruction and a MEM-path instruction can execute concurrently, so instructions may complete out of order — a reorder buffer (ROB) then retires them strictly in order. The design fetches instructions from a hex memory image, executes the RV32I instruction set, and logs its execution trace for verification against a reference model.

## Architecture

The processor is organized into six stages — Fetch, Decode, ALU Issue, MEM Issue, MEM Read, and Commit.

**Fetch / Decode** — Instructions are fetched and decoded strictly in order. Decode reads the register file, checks for data hazards, and routes each instruction into exactly one of two paths: ALU-type instructions (arithmetic/logic, branches, jumps, LUI/AUIPC) or MEM-type instructions (loads/stores). Each issued instruction also reserves a slot in the ROB, in program order.

**ALU Issue** — Executes arithmetic/logic operations, resolves branch and jump targets, and redirects fetch on a taken branch or jump, flushing the decode stage.

**MEM Issue / MEM Read** — Computes the effective address for a load/store, then accesses data memory. Because this path spans two stages, an ALU-path instruction issued around the same time can finish first — completion between the two paths is out of order.

**Commit** — The ROB retires instructions in order: it checks whether the oldest pending instruction's result is ready on either the ALU or MEM completion port, and only then writes it back to the register file and advances the ROB. This decouples out-of-order completion from the architectural (in-order) register and memory state.

Key modules:

| Module | Responsibility |
|---|---|
| `riscv_pkg` | Shared types, opcodes, and constants |
| `instruction_memory` | Loads program from a hex file into memory, combinationally serves fetch requests |
| `data_memory` | Load/store memory access |
| `top` | Fetch, decode, hazard/issue logic, ALU and MEM execution paths, ROB, and in-order commit |

## Repository Layout

```
src/
  pkg/            - riscv_pkg.sv (shared types/constants)
  data_memory.sv
  instruction_memory.sv
  top.sv
tb/
  tb.sv           - testbench, top-level simulation entry point
test/
  assembler.py    - assembles codes.txt into test.hex
  codes.txt       - test program source
  test.hex        - assembled instruction image
  test.log        - reference execution trace
  test.objdump    - disassembly of the test program
```

## Requirements

- [Verilator](https://www.veripool.org/verilator/)
- GTKWave (optional, for waveform viewing)

## Build & Run

```bash
make             # run lint through run (default target)
make lint        # static lint check
make build       # compile the design + testbench with Verilator
make run         # build and run the simulation
make wave        # run and open the waveform in GTKWave
make assembler   # assemble test/codes.txt into test/test.hex
make clean       # remove build artifacts and waveform dump
```

## Testing

`test/assembler.py` assembles `test/codes.txt` into `test/test.hex`, a plain list of hex-encoded instruction words with no stored addresses — addresses are derived by the memory model, starting at `INST_START` and incrementing by 4 per line.

During simulation, the processor's execution trace (retired PC, instruction, register writes, memory accesses) is written to `model.log`. This output is compared against the reference trace in `test/test.log`; an exact match confirms the processor executes the test program correctly.

## Status

Verified against the reference test program — `model.log` matches `test.log` exactly.
