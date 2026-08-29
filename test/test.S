.section .text
.globl _start
_start:
    addi x7, x0, 5
    addi x3, x0, 3
    sw x7, 0(x0)
    addi x1, x0, -2
    addi x4, x0, 3
    add x5, x3, x0
    add x6, x2, x0
    