.section .text
.globl _start
_start:
    addi x7, x0, 5
    addi x3, x7, 3
    addi x1, x3, -2
    addi x7, x3, 3
    addi x2, x0, 2
    add x5, x3, x1
    add x3, x7, x5
    