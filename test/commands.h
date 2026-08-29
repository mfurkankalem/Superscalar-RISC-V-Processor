#ifndef COMMANDS_H
#define COMMANDS_H

.macro ekle rd, rs1, rs2
.insn r 0x0b, 0x1, 0x01, \rd, \rs1, \rs2
.endm

.macro veya rd, rs1, rs2
.insn r 0x0b, 0x1, 0x02, \rd, \rs1, \rs2
.endm

#endif
