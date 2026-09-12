package riscv_pkg;
    localparam INST_START = 32'h80000000;
    localparam XLEN = 32'd32;
    localparam PRF_SIZE = 32'd128;

    //====================================================================
    // Core structs
    //====================================================================

    typedef enum logic [1:0] {
        ALU = 2'b01,
        MEM = 2'b10,
        INV = 2'b11
    } issue_t;

    typedef enum logic [1:0] {
        ROB_ZERO = 2'b00,
        ROB_PENDING = 2'b01,
        ROB_SPECULATIVE = 2'b10,
        ROB_FINISHED = 2'b11
    } state;

    typedef enum logic [1:0] {
        DM_READ = 2'b00,
        DM_WRITE_B = 2'b01,
        DM_WRITE_H = 2'b10,
        DM_WRITE_W = 2'b11
    } dm_t;

    typedef struct packed {
        state state; // [84:83] (2 bit)
        logic [6:0] prf_rd; // [82:76] (7 bit)
        logic [4:0] arf_rd; // [75:71] (5 bit)
        logic [6:0] prev_prf_rd; // [70:64] (7 bit)
        logic [31:0] instr; // [63:32] (32 bit - XLEN=32)
        logic [31:0] pc; // [31:0] (32 bit - XLEN=32)
    } rob_t;

    typedef struct packed {
        logic [7:0]      value;
        logic [XLEN-1:0] data_address;
        logic [XLEN-1:0] pc; // [31:0] (32 bit - XLEN=32)
    } data_byte_cache_t;

    //====================================================================
    // Opcodes
    //====================================================================
    typedef enum logic [6:0] {
        OP_REGISTER = 7'b0110011,
        OP_IMMEDIATE = 7'b0010011,
        OP_BRANCH = 7'b1100011,
        OP_LUI = 7'b0110111,
        OP_AUIPC = 7'b0010111,
        OP_JAL = 7'b1101111,
        OP_JALR = 7'b1100111,
        OP_STORE = 7'b0100011,
        OP_LOAD = 7'b0000011
    } opcode_e;

    typedef enum logic [2:0] {
        OP_RTYPE = 3'b000,
        OP_ITYPE = 3'b001,
        OP_STYPE = 3'b010,
        OP_BTYPE = 3'b011,
        OP_UTYPE = 3'b100,
        OP_JTYPE = 3'b101,
        INVALID_TYPE = 3'b111
    } optype_e;

    typedef struct packed {
        issue_t issue; // [68:67] (2 bit)
        optype_e optype; // [66:64] (3 bit)
        logic [31:0] imm; // [63:32] (32 bit - XLEN=32)
        logic [6:0] funct7;// [31:25] (7 bit)
        logic [4:0] rs2; // [24:20] (5 bit)
        logic [4:0] rs1; // [19:15] (5 bit)
        logic [2:0] funct3;// [14:12] (3 bit)
        logic [4:0] rd; // [11:7] (5 bit)
        opcode_e op; // [6:0] (7 bit)
    } instruct_t;

    typedef struct packed {
        issue_t          issue;   // [123:122] (2 bit)
        logic [6:0]      prf_rs1; // [121:115] (7 bit)
        logic [6:0]      prf_rs2; // [114:108] (7 bit)
        logic [6:0]      prf_rd;  // [107:101] (7 bit)
        instruct_t       instr;   // [100:32]  (68 bit)
        logic [31:0]     pc;      // [31:0]    (32 bit)
    } iq_t;

    

    //====================================================================
    // funct3 groups
    //====================================================================
    typedef enum logic [2:0] {
        F3_ADD = 3'b000,
        F3_SLL = 3'b001,
        F3_SLT = 3'b010,
        F3_SLTU = 3'b011,
        F3_XOR = 3'b100,
        F3_SR = 3'b101,
        F3_OR = 3'b110,
        F3_AND = 3'b111
    } r_funct3;

    typedef enum logic [2:0] {
        F3_BEQ = 3'b000,
        F3_BNE = 3'b001,
        F3_BLT = 3'b100,
        F3_BGE = 3'b101,
        F3_BLTU = 3'b110,
        F3_BGEU = 3'b111
    } b_funct3;

    typedef enum logic [2:0] {
        F3_LB = 3'b000,
        F3_LH = 3'b001,
        F3_LW = 3'b010,
        F3_LBU = 3'b100,
        F3_LHU = 3'b101
    } l_funct3;

    typedef enum logic [2:0] {
        F3_SB = 3'b000,
        F3_SH = 3'b001,
        F3_SW = 3'b010
    } s_funct3;

    //====================================================================
    // funct7 values
    //====================================================================
    localparam F7_ADD = 7'b0000000;
    localparam F7_SUB = 7'b0100000;
    localparam F7_SLL = 7'b0000000;
    localparam F7_SLT = 7'b0000000;
    localparam F7_SLTU = 7'b0000000;
    localparam F7_XOR = 7'b0000000;
    localparam F7_SRL = 7'b0000000;
    localparam F7_SRA = 7'b0100000;
    localparam F7_OR = 7'b0000000;
    localparam F7_AND = 7'b0000000;

    localparam F7_SLLI = 7'b0000000;
    localparam F7_SRLI = 7'b0000000;
    localparam F7_SRAI = 7'b0100000;

    //====================================================================
    // ALU control
    //====================================================================
    typedef enum logic [3:0] {
        ALU_ADD = 4'b0000,
        ALU_SUB = 4'b0001,
        ALU_AND = 4'b0010,
        ALU_OR = 4'b0011,
        ALU_XOR = 4'b0100,
        ALU_SLL = 4'b0101,
        ALU_SRL = 4'b0110,
        ALU_SRA = 4'b0111,
        ALU_SLT = 4'b1000,
        ALU_SLTU = 4'b1001,
        ALU_CLZ = 4'b1010,
        ALU_CTZ = 4'b1011,
        ALU_CPOP = 4'b1100,
        ALU_INVALID = 4'b1101,
        ALU_NONE = 4'b1111
    } alu_op_t;
endpackage
