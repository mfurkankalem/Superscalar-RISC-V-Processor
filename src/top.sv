

module top
    import riscv_pkg::*;
    #(
        parameter DMemInitFile = "dmem.mem", // data memory initialization file
        parameter IMemInitFile = "imem.mem" // instruction memory initialization file
    ) (
        input logic clk,
        input logic rstn_i, // system reset
        input logic [XLEN-1:0] addr_i, // data memory report
        output logic update_o, // log update signal
        output logic [XLEN-1:0] pc_o, // log program counter
        output logic [XLEN-1:0] instr_o, // log instruction
        output logic [4:0] reg_addr_o, // log register address
        output logic [XLEN-1:0] reg_data_o, // log register data
        output logic [XLEN-1:0] mem_addr_o, // retired memory address
        output logic [31:0] data_o[0:XLEN-1], // data memory write
        output logic [XLEN-1:0] mem_data_o // retired memory data
    );

    logic en_f;
    logic en_d;
    logic en_m;
    logic flush_d;

    // ====== Fetch Stage ==========================================================
    logic startvalue;
    logic [XLEN-1:0] pc_f, im_rd;
    logic [XLEN-1:0] instruction_cache[0:XLEN-1]; // 32 instruction cache

    instruction_memory instruction_memory_0 (
        .im_a (pc_f),
        .im_rd (im_rd)
    ); // read memory

    always_ff @(negedge clk) begin
        if (im_rd != instruction_cache[pc_f[6:2]]) begin
            instruction_cache[pc_f[6:2]] <= im_rd;
        end
    end

    always_ff @(posedge clk) begin
        if (rstn_i) begin
            if (en_f) begin
                if (startvalue) begin
                    if (pc_src > 0) begin
                        pc_f <= pc_src;
                        pc_d <= 0;
                        instr_d <= 0;
                    end else if (pc_f >= INST_START && (rob_stack_count < 5'(XLEN - 5))) begin
                        pc_f <= pc_f + 4;
                        pc_d <= pc_f;
                        instr_d <= instruction_cache[pc_f[6:2]];
                    end else begin
                        pc_f <= pc_f;
                        pc_d <= 0;
                        instr_d <= 0;
                    end
                end else begin
                    pc_f <= INST_START;
                    startvalue <= 1;
                end
            end else begin
                pc_f <= pc_f;
                pc_d <= pc_d;
                instr_d <= instr_d;
            end
        end else pc_f <= 0;
    end

    // ====== Decode Stage =========================================================
    logic [XLEN-1:0]
    pc_d, instr_d, imm_d, ALUr_rd1, ALUr_rd2, MEMr_rd1, MEMr_rd2;
    logic [XLEN-1:0] register[0:XLEN-1]; //register file
    logic [XLEN-1:0] cache_busy;
    logic [XLEN-1:0] prf_register [0:PRF_SIZE-1];
    logic [6:0] rename_table [0:XLEN-1];
    logic [PRF_SIZE-1:0] busy_table;
    logic [PRF_SIZE-1:0] free_list;
    rob_t ROB [0:XLEN-1];
    iq_t IQ [0:XLEN-1];
    logic [4:0] rob_stack_count;
    logic [4:0] iq_stack_count;
    instruct_t decoded_d;

    assign decoded_d = decode_code(instr_d);

    always_ff @(negedge clk) begin
        if ((pc_d >= INST_START)&& ((instr_d != 0))&& (rob_stack_count < 5'(XLEN - 5))) begin
            IQ[iq_stack_count].issue <= decoded_d.issue;
            IQ[iq_stack_count].prf_rs1 <= rename_table[decoded_d.rs1];
            IQ[iq_stack_count].prf_rs2 <= rename_table[decoded_d.rs2];
            if (decoded_d.rd != 0) begin
            for (int i = 1; i < PRF_SIZE; i++) begin
                if (free_list[i] == 1'b0) begin
                    free_list[i] <= 1'b1;
                    busy_table[i] <= 1'b1;
                    IQ[iq_stack_count].prf_rd <= 7'(i);
                    rename_table[decoded_d.rd] <= 7'(i);
                    ROB[rob_stack_count].prf_rd <= 7'(i);
                    ROB[rob_stack_count].arf_rd <= decoded_d.rd;
                    ROB[rob_stack_count].prev_prf_rd <= rename_table[decoded_d.rd];
                    break;
                end
            end
            end
            else begin
                IQ[iq_stack_count].prf_rd <= 7'(0);
                ROB[rob_stack_count].prf_rd <= 7'(0);
                ROB[rob_stack_count].arf_rd <= 5'(0);
                ROB[rob_stack_count].prev_prf_rd <= 7'(0);
            end
            IQ[iq_stack_count].instr <= decoded_d;
            IQ[iq_stack_count].pc <= pc_d;
            iq_stack_count <= iq_stack_count + 1;
            ROB[rob_stack_count].pc <= pc_d;
            ROB[rob_stack_count].state <= ROB_PENDING;
            ROB[rob_stack_count].instr <= instr_d;
            rob_stack_count <= rob_stack_count + 1;
        end
    end

    logic alu_done, mem_done;
    int alu_number, mem_number;

    always_comb begin
        alu_done = 1'b0;
        alu_number = '0;
        mem_done = 1'b0;
        mem_number = '0;
        if (pc_d >= INST_START) begin
            for (int i = 0; i < XLEN; i++) begin
                if (!alu_done && (IQ[i].issue == ALU) && (busy_table[IQ[i].prf_rs1] == 1'b0) && (busy_table[IQ[i].prf_rs2] == 1'b0)) begin
                    alu_number = i;
                    alu_done = 1;
                    break;
                end
                if (!mem_done && (IQ[i].issue == MEM) && (busy_table[IQ[i].prf_rs1] == 1'b0) && (busy_table[IQ[i].prf_rs2] == 1'b0)) begin
                    mem_number = i;
                    mem_done = 1;
                    break;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (alu_done && !mem_done) begin
            ALUr_rd1 <= prf_register[IQ[alu_number].prf_rs1];
            ALUr_rd2 <= prf_register[IQ[alu_number].prf_rs2];
            ALUr_rd <= IQ[alu_number].prf_rd;
            pc_alu <= IQ[alu_number].pc;
            instr_alu <= IQ[alu_number].instr;
            imm_alu <= IQ[alu_number].instr.imm;
            if (IQ[alu_number].prf_rd != 0) begin
                busy_table[IQ[alu_number].prf_rd] <= 1'b1;
            end
            MEMr_rd1 <= 0;
            MEMr_rd2 <= 0;
            pc_mem <= 0;
            instr_mem <= 0;
            imm_mem <= 0;
            iq_stack_count <= iq_stack_count - 1;
            for (int i = alu_number; i < 31-alu_number; i++) begin
                IQ[i] <= IQ[i+1];
            end
            IQ[31] <= '0;
        end
        else if (!alu_done && mem_done) begin
            ALUr_rd1 <= 0;
            ALUr_rd2 <= 0;
            pc_alu <= 0;
            instr_alu <= 0;
            imm_alu <= 0;
            MEMr_rd1 <= prf_register[IQ[mem_number].prf_rs1];
            MEMr_rd2 <= prf_register[IQ[mem_number].prf_rs2];
            busy_table[IQ[mem_number].prf_rd] <= 1'b1;
            MEMr_rd <= IQ[mem_number].prf_rd;
            pc_mem <= IQ[mem_number].pc;
            instr_mem <= IQ[mem_number].instr;
            imm_mem <= IQ[mem_number].instr.imm;
            iq_stack_count <= iq_stack_count - 1;
            for (int i = mem_number; i < 31-mem_number; i++) begin
                IQ[i] <= IQ[i+1];
            end
            IQ[31] <= '0;
        end
        else begin
            ALUr_rd1 <= 0;
            ALUr_rd2 <= 0;
            pc_alu <= 0;
            instr_alu <= 0;
            imm_alu <= 0;
            MEMr_rd1 <= 0;
            MEMr_rd2 <= 0;
            pc_mem <= 0;
            instr_mem <= 0;
            imm_mem <= 0;
        end
    end

    // ====== ALU Issue Stage ======================================================
    logic [XLEN-1:0] pc_alu, imm_alu, alu_in1, alu_in2, alu_out, pc_src;
    logic [6:0] ALUr_rd;
    logic pc_redirect;
    instruct_t instr_alu;
    alu_op_t alu_op;
    assign alu_op = alu_op_e(instr_alu.op, instr_alu.funct3, instr_alu.funct7);

    always_comb begin
        if (instr_alu.op == OP_AUIPC) begin
            alu_in1 = pc_alu;
        end else begin
            alu_in1 = ALUr_rd1;
        end
        if ((instr_alu.op == OP_JAL) || (instr_alu.optype == OP_RTYPE) || (instr_alu.optype == OP_BTYPE)) begin
            alu_in2 = ALUr_rd2;
        end else begin
            alu_in2 = imm_alu;
        end
    end

    assign alu_out = alu_result(alu_in1, alu_in2, alu_op);

    always_comb begin
        pc_redirect = 1'b0;
        if (instr_alu.optype == OP_BTYPE) begin
            case (instr_alu.funct3)
                F3_BEQ: pc_redirect = (alu_out == 32'd0); // BEQ
                F3_BNE: pc_redirect = (alu_out != 32'd0); // BNE
                F3_BLT: pc_redirect = (alu_out == 32'd1); // BLT
                F3_BGE: pc_redirect = (alu_out == 32'd0); // BGE
                F3_BLTU: pc_redirect = (alu_out == 32'd1); // BLTU
                F3_BGEU: pc_redirect = (alu_out == 32'd0); // BGEU
                default: pc_redirect = 1'b0;
            endcase
        end else if ((instr_alu.op == OP_JAL) || (instr_alu.op == OP_JALR)) begin
            pc_redirect = 1'b1;
        end

        if (pc_redirect) begin
            flush_d = 1;
            en_d = 0;
            en_f = 0;
            if (instr_alu.op == OP_JALR) begin
                pc_src = alu_out;
            end else begin
                if ($signed(imm_alu) < 0) begin
                    pc_src = pc_alu + ($signed(imm_alu));
                end else begin
                    pc_src = pc_alu + imm_alu;
                end
            end
        end else begin
            pc_src = 0;
            en_d = 1;
            en_f = 1;
            flush_d = 0;
        end
    end

    always_ff @(negedge clk) begin
        for (int i = 0; i < rob_stack_count; i++) begin
            if (pc_alu == ROB[i].pc) begin
                ROB[i].state <= ROB_FINISHED;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (pc_redirect) begin
            prf_register[ALUr_rd] <= pc_alu + 4;
        end else if (instr_alu.optype == OP_BTYPE) begin
            prf_register[ALUr_rd] <= 0;
        end else begin
            prf_register[ALUr_rd] <= alu_out;
        end
    end

    // ====== MEM Issue Stage ======================================================
    logic [XLEN-1:0] pc_mem, imm_mem, mem_in1, mem_in2, mem_op_out, data_word_address_mem;
    logic [6:0] MEMr_rd;
    instruct_t instr_mem;
    alu_op_t mem_op;
    assign mem_op = alu_op_e(instr_mem.op, instr_mem.funct3, instr_mem.funct7);

    assign mem_in1 = MEMr_rd1;
    assign mem_in2 = imm_mem;
    assign mem_op_out = alu_result(mem_in1, mem_in2, mem_op);
    assign data_word_address_mem = mem_op_out - (mem_op_out % 4);

    always_comb begin
        if (cache_busy[data_word_address_mem]) begin
            en_m = 0;
        end else begin
            en_m = 1;
        end
    end
    always_ff @(posedge clk) begin
        if (en_m) begin
            cache_busy[data_word_address_mem] <= 1'b1;
            mem_read_in1 <= mem_op_out;
            mem_read_in2 <= MEMr_rd2;
            pc_mem_read <= pc_mem;
            instr_mem_read <= instr_mem;
            MEMr_read_rd <= MEMr_rd;
            data_word_address <= data_word_address_mem;
        end
    end

    // ====== MEM Read Stage ======================================================
    logic [XLEN-1:0] pc_mem_read, mem_read_in1, mem_read_in2, data_read_out, dm_a, dm_wd;
    logic [6:0] MEMr_read_rd;
    instruct_t instr_mem_read;
    logic [7:0] data_byte_cache[0:XLEN-1]; // 32 byte data cache
    logic [XLEN-1:0] data_word_address;
    logic [XLEN-1:0] mem_out;
    logic dm_cd;

    data_memory data_memory_0 (
        .clk (clk),
        .dm_a (dm_a),
        .data (data_o),
        .dm_rd(data_read_out),
        .dm_wd(dm_wd),
        .dm_cd(dm_cd)
    ); // read memory

    always_ff @(negedge clk) begin
        if (instr_mem_read.op == OP_STORE) begin
            for (int i = 0; i < 4; i = i + 1) begin
                dm_wd[i*8+:8] <= data_byte_cache[data_word_address+i];
            end
            dm_a <= data_word_address;
            dm_cd <= 1;
        end else dm_cd <= 0;
    end

    always_comb begin
        if (instr_mem_read.op == OP_STORE) begin
            casez (instr_mem_read.funct3)
                F3_SB: data_byte_cache[mem_read_in1] = mem_read_in2[7:0];
                F3_SH: begin
                    data_byte_cache[mem_read_in1] = mem_read_in2[7:0];
                    data_byte_cache[mem_read_in1+1] = mem_read_in2[15:8];
                end
                F3_SW: begin
                    data_byte_cache[mem_read_in1] = mem_read_in2[7:0];
                    data_byte_cache[mem_read_in1+1] = mem_read_in2[15:8];
                    data_byte_cache[mem_read_in1+2] = mem_read_in2[23:16];
                    data_byte_cache[mem_read_in1+3] = mem_read_in2[31:24];
                end
                default: data_byte_cache[mem_read_in1] = data_byte_cache[mem_read_in1];
            endcase
        end else if (instr_mem_read.op == OP_LOAD) begin
            casez (instr_mem_read.funct3)
                F3_LB:
                mem_out = {{(XLEN - 8) {data_byte_cache[mem_read_in1][7]}}, data_byte_cache[mem_read_in1]};
                F3_LH:
                mem_out = {
                    {(XLEN - 16) {data_byte_cache[mem_read_in1+1][7]}},
                    data_byte_cache[mem_read_in1+1],
                    data_byte_cache[mem_read_in1]
                };
                F3_LW:
                mem_out = {
                    data_byte_cache[mem_read_in1+3],
                    data_byte_cache[mem_read_in1+2],
                    data_byte_cache[mem_read_in1+1],
                    data_byte_cache[mem_read_in1]
                };
                F3_LBU: mem_out = {{(XLEN - 8) {1'b0}}, data_byte_cache[mem_read_in1]};
                F3_LHU:
                mem_out = {
                    {(XLEN - 16) {1'b0}}, data_byte_cache[mem_read_in1], data_byte_cache[mem_read_in1+1]
                };
            endcase
        end else mem_out = 0;
    end

    always_ff @(posedge clk) begin
        cache_busy[data_word_address] <= 1'b0;

        prf_register[MEMr_read_rd] <= mem_out;
        for (int i = 0; i < rob_stack_count; i++) begin
            if (pc_mem_read == ROB[i].pc) begin
                ROB[i].state <= ROB_FINISHED;
            end
        end
    end

    // ====== Commit Stage ========================================================
    logic [XLEN-1:0] r_wd3;
    logic [4:0] commit_rd;

    always_ff @(posedge clk) begin
        if (ROB[0].state == ROB_FINISHED) begin
            pc_o <= ROB[0].pc;
            instr_o <= ROB[0].instr;
            reg_data_o <= prf_register[ROB[0].prf_rd];
            reg_addr_o <= ROB[0].arf_rd;
            update_o <= 1;
            r_wd3 <= prf_register[ROB[0].prf_rd];
            commit_rd <= ROB[0].arf_rd;
            for (int i2 = 0; i2 < 31; i2++) begin
                ROB[i2] <= ROB[i2+1];
            end
            rob_stack_count <= rob_stack_count - 1;
            ROB[31] <= '0;
            prf_register[ROB[0].prev_prf_rd] <= 0;
            free_list[ROB[0].prev_prf_rd] <= 1'b0;
            busy_table[ROB[0].prf_rd] <= 1'b0;
        end
        else begin
            update_o <= 0;
            r_wd3 <= 0;
            commit_rd <= 0;
        end
    end
    always_ff @(negedge clk) begin
        if (commit_rd == 0) begin
            register[0] <= 0;
        end else begin
            register[commit_rd] <= r_wd3;
        end
    end

    // ====== Decode Functions =====================================================

    function automatic instruct_t decode_code(input logic [XLEN-1:0] instr);
        instruct_t decode_function;
        decode_function.op = opcode_e'(instr[6:0]);
        decode_function.optype = opcode_to_optype(decode_function.op);
        casez (decode_function.optype)
            OP_RTYPE: begin
                decode_function.funct7 = instr[31:25];
                decode_function.rs2 = instr[24:20];
                decode_function.rs1 = instr[19:15];
                decode_function.funct3 = instr[14:12];
                decode_function.rd = instr[11:7];
                decode_function.issue = ALU;
            end
            OP_ITYPE: begin
                decode_function.imm = {{20{instr[31]}}, instr[31:20]};
                decode_function.rs1 = instr[19:15];
                decode_function.rs2 = 0;
                decode_function.funct3 = instr[14:12];
                decode_function.rd = instr[11:7];
                if(decode_function.op == OP_LOAD) begin
                    decode_function.issue = MEM;
                end else begin
                    decode_function.issue = ALU;
                end
            end
            OP_STYPE: begin
                decode_function.imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
                decode_function.rs2 = instr[24:20];
                decode_function.rs1 = instr[19:15];
                decode_function.funct3 = instr[14:12];
                decode_function.rd = 0;
                decode_function.issue = MEM;
            end
            OP_BTYPE: begin
                decode_function.imm = {
                    {19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0
                };
                decode_function.rs2 = instr[24:20];
                decode_function.rs1 = instr[19:15];
                decode_function.funct3 = instr[14:12];
                decode_function.issue = ALU;
            end
            OP_UTYPE: begin
                decode_function.imm = {instr[31:12], 12'b0};
                decode_function.rd = instr[11:7];
                decode_function.issue = ALU;
            end
            OP_JTYPE: begin
                decode_function.imm = {
                    {11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0
                };
                decode_function.rd = instr[11:7];
                decode_function.issue = ALU;
            end
            default: begin
                decode_function.imm = 0;
                decode_function.rs1 = 0;
                decode_function.rs2 = 0;
                decode_function.rd = 0;
                decode_function.funct3 = 0;
                decode_function.funct7 = 0;
                decode_function.issue = INV;
            end
        endcase
        return decode_function;
    endfunction

    function automatic optype_e opcode_to_optype(opcode_e op);
        case (op)
            OP_REGISTER: return OP_RTYPE;
            OP_IMMEDIATE, OP_JALR, OP_LOAD: return OP_ITYPE;
            OP_STORE: return OP_STYPE;
            OP_BRANCH: return OP_BTYPE;
            OP_LUI, OP_AUIPC: return OP_UTYPE;
            OP_JAL: return OP_JTYPE;
            default: return INVALID_TYPE;
        endcase
    endfunction

    // ====== ALU Functions =======================================================

    function automatic alu_op_t alu_op_e(input logic [6:0] op, input logic [2:0] funct3,
        input logic [6:0] funct7);
        case (op)
            OP_IMMEDIATE: begin
                case (funct3)
                    F3_ADD: alu_op_e = ALU_ADD;
                    F3_SLL: alu_op_e = ALU_SLL;
                    F3_SLT: alu_op_e = ALU_SLT;
                    F3_SLTU: alu_op_e = ALU_SLTU;
                    F3_XOR: alu_op_e = ALU_XOR;
                    F3_OR: alu_op_e = ALU_OR;
                    F3_AND: alu_op_e = ALU_AND;
                    F3_SR: begin
                        if (funct7 == F7_SRL) begin
                            alu_op_e = ALU_SRL;
                        end else if (funct7 == F7_SRA) begin
                            alu_op_e = ALU_SRA;
                        end else begin
                            alu_op_e = ALU_INVALID;
                        end
                    end
                    default: alu_op_e = ALU_INVALID;
                endcase
            end
            OP_REGISTER: begin
                case (funct3)
                    F3_ADD: begin
                        if (funct7 == F7_ADD) begin
                            alu_op_e = ALU_ADD;
                        end else if (funct7 == F7_SUB) begin
                            alu_op_e = ALU_SUB;
                        end else begin
                            alu_op_e = ALU_INVALID;
                        end
                    end
                    F3_SLL: alu_op_e = ALU_SLL;
                    F3_SLT: alu_op_e = ALU_SLT;
                    F3_SLTU: alu_op_e = ALU_SLTU;
                    F3_XOR: alu_op_e = ALU_XOR;
                    F3_OR: alu_op_e = ALU_OR;
                    F3_AND: alu_op_e = ALU_AND;
                    F3_SR: begin
                        if (funct7 == F7_SRL) begin
                            alu_op_e = ALU_SRL;
                        end else if (funct7 == F7_SRA) begin
                            alu_op_e = ALU_SRA;
                        end else begin
                            alu_op_e = ALU_INVALID;
                        end
                    end
                endcase
            end
            OP_LOAD: alu_op_e = ALU_ADD;
            OP_STORE: alu_op_e = ALU_ADD;
            OP_BRANCH: begin
                case (funct3)
                    F3_BEQ: alu_op_e = ALU_SUB;
                    F3_BNE: alu_op_e = ALU_SUB;
                    F3_BLT: alu_op_e = ALU_SLT;
                    F3_BGE: alu_op_e = ALU_SLT;
                    F3_BLTU: alu_op_e = ALU_SLTU;
                    F3_BGEU: alu_op_e = ALU_SLTU;
                endcase
            end
            OP_JAL: alu_op_e = ALU_NONE;
            OP_JALR: alu_op_e = ALU_ADD;
            OP_LUI: alu_op_e = ALU_NONE;
            OP_AUIPC: alu_op_e = ALU_ADD;
            default: alu_op_e = ALU_INVALID;
        endcase
    endfunction

    function automatic logic [XLEN-1:0] alu_result(
        input logic [XLEN-1:0] alu_a, input logic [XLEN-1:0] alu_b, input alu_op_t alu_cd);
        case (alu_cd)
            ALU_ADD: alu_result = alu_a + alu_b;
            ALU_SUB: alu_result = alu_a - alu_b;
            ALU_AND: alu_result = alu_a & alu_b;
            ALU_OR: alu_result = alu_a | alu_b;
            ALU_XOR: alu_result = alu_a ^ alu_b;
            ALU_SLL: alu_result = alu_a << alu_b[4:0];
            ALU_SRL: alu_result = alu_a >> alu_b[4:0];
            ALU_SRA: alu_result = $signed(alu_a) >>> alu_b[4:0];
            ALU_SLT: alu_result = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;
            ALU_SLTU: alu_result = (alu_a < alu_b) ? 32'd1 : 32'd0;
            default: alu_result = 'x;
        endcase
    endfunction
    // ====== Others ==========================================================

    assign mem_addr_o = 0;
    assign data_o[0] = 0;
    assign mem_data_o = 0;
endmodule

