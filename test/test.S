.section .text
.globl _start
_start:
    lui x1, 0x10000
    add x1, x1, 0

    lui x2, 0x12345
    add x2, x2, 0x678

    add x3, x0, -1

    add x4, x0, 0xAA

    sw x2, 0(x1)
    sh x2, 4(x1)
    sb x4, 6(x1)
    sw x3, 8(x1)
    sb x2, 12(x1)

    lw x5, 0(x1)
    lh x6, 0(x1)
    lhu x7, 0(x1)
    lb x8, 0(x1)
    lbu x9, 0(x1)

    lb x10, 1(x1)
    lbu x11, 1(x1)
    lh x12, 4(x1)
    lb x13, 6(x1)
    lbu x14, 6(x1)

    lw x15, 8(x1)
    lb x16, 8(x1)
    lbu x17, 8(x1)
    lh x18, 12(x1)
    lb x19, 12(x1)
    