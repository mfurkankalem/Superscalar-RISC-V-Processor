.section .text
.globl _start
_start:
    addi x7, x0, 5
    addi x3, x7, 3
    addi x1, x0, 1
    sw x7, 0(x0)
    sb x3, 0(x1)
    lw x2, 0(x0)
    