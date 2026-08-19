# assembler.py
import sys
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

def parse_mem_arg(arg):
    imm_str, reg_str = arg.split('(')
    imm = int(imm_str)
    reg = int(reg_str.replace('x', '').replace(')', ''))
    return imm, reg

def assemble_itype(args, funct3):
    rd = int(args[0].replace('x', ''))
    rs1 = int(args[1].replace('x', ''))
    imm = int(args[2], 0)
    if imm < 0: imm = (1 << 12) + imm
    opcode = "0010011"
    return f"{format(imm, '012b')}{format(rs1, '05b')}{funct3}{format(rd, '05b')}{opcode}"

def assemble_shifti(args, funct3, funct7):
    rd = int(args[0].replace('x', ''))
    rs1 = int(args[1].replace('x', ''))
    shamt = int(args[2], 0) & 0x1F # Sadece ilk 5 bit (RV32I için)
    opcode = "0010011"
    return f"{funct7}{format(shamt, '05b')}{format(rs1, '05b')}{funct3}{format(rd, '05b')}{opcode}"

def assemble_add(args):
    rd = int(args[0].replace('x', ''))
    rs1 = int(args[1].replace('x', ''))
    rs2 = int(args[2].replace('x', ''))
    opcode = "0110011"
    funct3 = "000"
    funct7 = "0000000"
    return f"{funct7}{format(rs2, '05b')}{format(rs1, '05b')}{funct3}{format(rd, '05b')}{opcode}"

def assemble_store(args, funct3):
    rs2 = int(args[0].replace('x', ''))
    imm, rs1 = parse_mem_arg(args[1])
    if imm < 0: imm = (1 << 12) + imm
    opcode = "0100011"
    imm_bin = format(imm, '012b')
    imm11_5 = imm_bin[0:7]
    imm4_0 = imm_bin[7:12]
    return f"{imm11_5}{format(rs2, '05b')}{format(rs1, '05b')}{funct3}{imm4_0}{opcode}"

def assemble_load(args, funct3):
    rd = int(args[0].replace('x', ''))
    imm, rs1 = parse_mem_arg(args[1])
    if imm < 0: imm = (1 << 12) + imm
    opcode = "0000011"
    return f"{format(imm, '012b')}{format(rs1, '05b')}{funct3}{format(rd, '05b')}{opcode}"

def assemble_rtype(args, funct3, funct7):
    rd = int(args[0].replace('x', ''))
    rs1 = int(args[1].replace('x', ''))
    rs2 = int(args[2].replace('x', ''))
    opcode = "0110011"
    return f"{funct7}{format(rs2, '05b')}{format(rs1, '05b')}{funct3}{format(rd, '05b')}{opcode}"

def assemble_jal(args):
    rd = int(args[0].replace('x', ''))
    imm = int(args[1])
    if imm % 2 != 0:
        raise ValueError(f"jal offset must be even: {imm}")
    if imm < 0: imm = (1 << 21) + imm
    b = format(imm, '021b')
    opcode = "1101111"
    return f"{b[0]}{b[10:20]}{b[9]}{b[1:9]}{format(rd, '05b')}{opcode}"

def assemble_jalr(args):
    rd = int(args[0].replace('x', ''))
    imm, rs1 = parse_mem_arg(args[1])
    if imm < 0: imm = (1 << 12) + imm
    opcode = "1100111"
    funct3 = "000"
    return f"{format(imm, '012b')}{format(rs1, '05b')}{funct3}{format(rd, '05b')}{opcode}"

def assemble_branch(args, funct3):
    rs1 = int(args[0].replace('x', ''))
    rs2 = int(args[1].replace('x', ''))
    imm = int(args[2])
    if imm % 2 != 0:
        raise ValueError(f"branch offset must be even: {imm}")
    if imm < 0: imm = (1 << 13) + imm
    b = format(imm, '013b')
    opcode = "1100011"
    return f"{b[0]}{b[2:8]}{format(rs2, '05b')}{format(rs1, '05b')}{funct3}{b[8:12]}{b[1]}{opcode}"

def assemble_utype(args, opcode):
    rd = int(args[0].replace('x', ''))
    imm = int(args[1], 0)
    if imm < 0: imm = (1 << 20) + imm
    return f"{format(imm, '020b')}{format(rd, '05b')}{opcode}"

def main():
    with open(os.path.join(SCRIPT_DIR, "codes.txt")) as cf:
        lines = [l.strip() for l in cf if l.strip()]

    with open(os.path.join(SCRIPT_DIR, "test.hex"), "w") as f:
        for line in lines:
            parts = line.replace(',', ' ').split()
            cmd = parts[0]
            args = parts[1:]

            if cmd in ["nop", "yok", "ecall", "ebreak", "fence"]:
                cmd, args = "addi", ["x0", "x0", "0"]
            elif cmd in ["mv", "taşı"]:
                cmd, args = "addi", [args[0], args[1], "0"]
            elif cmd in ["not", "değil"]:
                cmd, args = "xori", [args[0], args[1], "-1"]
            elif cmd in ["neg", "ters"]:
                cmd, args = "sub", [args[0], "x0", args[1]]
            elif cmd in ["ret", "dön"]:
                cmd, args = "jalr", ["x0", "0(x1)"]
            elif cmd in ["j", "atla"]:
                cmd, args = "jal", ["x0", args[0]]
            elif (cmd in ["jal", "atlab"]) and len(args) == 1:
                cmd, args = cmd, ["x1", args[0]]
            elif cmd == "jr":
                cmd, args = "jalr", ["x0", f"0({args[0]})"]
            elif (cmd in ["jalr", "atlas"]) and len(args) == 1:
                cmd, args = cmd, ["x1", f"0({args[0]})"]
            elif cmd == "seqz":
                cmd, args = "sltiu", [args[0], args[1], "1"]
            elif cmd == "snez":
                cmd, args = "sltu", [args[0], "x0", args[1]]
            elif cmd == "sltz":
                cmd, args = "slt", [args[0], args[1], "x0"]
            elif cmd == "sgtz":
                cmd, args = "slt", [args[0], "x0", args[1]]
            elif cmd == "beqz":
                cmd, args = "beq", [args[0], "x0", args[1]]
            elif cmd == "bnez":
                cmd, args = "bne", [args[0], "x0", args[1]]
            elif cmd == "blez":
                cmd, args = "bge", ["x0", args[0], args[1]]
            elif cmd == "bgez":
                cmd, args = "bge", [args[0], "x0", args[1]]
            elif cmd == "bltz":
                cmd, args = "blt", [args[0], "x0", args[1]]
            elif cmd == "bgtz":
                cmd, args = "blt", ["x0", args[0], args[1]]
            elif cmd == "bgt":
                cmd, args = "blt", [args[1], args[0], args[2]]
            elif cmd == "ble":
                cmd, args = "bge", [args[1], args[0], args[2]]
            elif cmd == "bgtu":
                cmd, args = "bltu", [args[1], args[0], args[2]]
            elif cmd == "bleu":
                cmd, args = "bgeu", [args[1], args[0], args[2]]
            elif cmd == "li":
                cmd, args = "addi", [args[0], "x0", args[1]]

            
            # I-Type
            if cmd in ["addi", "ekleh"]: bin_code = assemble_itype(args, "000")
            elif cmd in ["slti", "küçükseh"]: bin_code = assemble_itype(args, "010")
            elif cmd in ["sltiu", "küçüksehi"]: bin_code = assemble_itype(args, "011")
            elif cmd in ["xori", "xveyah"]: bin_code = assemble_itype(args, "100")
            elif cmd in ["ori", "veyah"]: bin_code = assemble_itype(args, "110")
            elif cmd in ["andi", "veh"]: bin_code = assemble_itype(args, "111")
            
            # Shift I-Type
            elif cmd == "slli": bin_code = assemble_shifti(args, "001", "0000000")
            elif cmd in ["srli", "sağh"]: bin_code = assemble_shifti(args, "101", "0000000")
            elif cmd in ["srai", "sağah"]: bin_code = assemble_shifti(args, "101", "0100000")

            # R-Type
            elif cmd in ["add", "ekle"]: bin_code = assemble_add(args)
            elif cmd in ["sub", "çıkar"]: bin_code = assemble_rtype(args, "000", "0100000")
            elif cmd in ["sll", "sol"]: bin_code = assemble_rtype(args, "001", "0000000")
            elif cmd in ["slt", "küçükse"]: bin_code = assemble_rtype(args, "010", "0000000")
            elif cmd in ["sltu", "küçüksei"]: bin_code = assemble_rtype(args, "011", "0000000")
            elif cmd in ["xor", "xveya"]: bin_code = assemble_rtype(args, "100", "0000000")
            elif cmd in ["srl", "sağ"]: bin_code = assemble_rtype(args, "101", "0000000")
            elif cmd in ["sra", "sağa"]: bin_code = assemble_rtype(args, "101", "0100000")
            elif cmd in ["or", "veya"]: bin_code = assemble_rtype(args, "110", "0000000")
            elif cmd in ["and", "ve"]: bin_code = assemble_rtype(args, "111", "0000000")

            # Load
            elif cmd == "lb": bin_code = assemble_load(args, "000")
            elif cmd == "lh": bin_code = assemble_load(args, "001")
            elif cmd in ["lw", "oku"]: bin_code = assemble_load(args, "010")
            elif cmd == "lbu": bin_code = assemble_load(args, "100")
            elif cmd == "lhu": bin_code = assemble_load(args, "101")

            # Store
            elif cmd == "sb": bin_code = assemble_store(args, "000")
            elif cmd == "sh": bin_code = assemble_store(args, "001")
            elif cmd in ["sw", "kaydet"]: bin_code = assemble_store(args, "010")

            # Jumps
            elif cmd in ["jal", "atlab"]: bin_code = assemble_jal(args)
            elif cmd in ["jalr", "atlas"]: bin_code = assemble_jalr(args)

            # Branches
            elif cmd in ["beq", "eşit"]: bin_code = assemble_branch(args, "000")
            elif cmd in ["bne", "eşitd"]: bin_code = assemble_branch(args, "001")
            elif cmd in ["blt", "küçük"]: bin_code = assemble_branch(args, "100")
            elif cmd in ["bge", "büyük"]: bin_code = assemble_branch(args, "101")
            elif cmd in ["bltu", "küçüki"]: bin_code = assemble_branch(args, "110")
            elif cmd in ["bgeu", "büyüki"]: bin_code = assemble_branch(args, "111")

            # U-Type
            elif cmd in ["lui", "yüksekh"]: bin_code = assemble_utype(args, "0110111")
            elif cmd in ["auipc", "yüksekpc"]: bin_code = assemble_utype(args, "0010111")

            else:
                print(f"Bilinmeyen komut: {cmd}")
                continue
                
            hex_code = format(int(bin_code, 2), '08X')
            f.write(hex_code + "\n")
            print(f"{line.ljust(20)} -> 0x{hex_code}")

if __name__ == "__main__":
    main()