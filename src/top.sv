

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
        output logic update_o2, // log update signal
        output logic [XLEN-1:0] pc_o, // log program counter
        output logic [XLEN-1:0] pc_o2, // log program counter
        output logic [XLEN-1:0] instr_o, // log instruction
        output logic [XLEN-1:0] instr_o2, // log instruction
        output logic [4:0] reg_addr_o, // log register address
        output logic [4:0] reg_addr_o2, // log register address
        output logic [XLEN-1:0] reg_data_o, // log register data
        output logic [XLEN-1:0] reg_data_o2, // log register data
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
    pc_d, instr_d, imm_d, ALUr_rd1, ALUr_rd2, ALU2r_rd1, ALU2r_rd2, MEMr_rd1, MEMr_rd2;
    logic [XLEN-1:0] register[0:XLEN-1]; //register file
    logic [XLEN-1:0] prf_register [0:PRF_SIZE-1];
    logic [6:0] rename_table [0:XLEN-1];
    logic [PRF_SIZE-1:0] busy_table;
    logic [PRF_SIZE-1:0] free_list;
    rob_t ROB [0:XLEN-1];
    iq_t IQ_ALU [0:XLEN-1];
    iq_t IQ_MEM [0:XLEN-1];
    logic [4:0] rob_stack_count;
    logic [4:0] iq_alu_stack_count;
    logic [4:0] iq_mem_stack_count;
    instruct_t decoded_d;

    assign decoded_d = decode_code(instr_d);

    always_ff @(negedge clk) begin
        if ((pc_d >= INST_START)&& ((instr_d != 0))&& (rob_stack_count < 5'(XLEN - 5))) begin
            if(decoded_d.issue == ALU) begin
                IQ_ALU[iq_alu_stack_count].issue <= decoded_d.issue;
                IQ_ALU[iq_alu_stack_count].prf_rs1 <= rename_table[decoded_d.rs1];
                IQ_ALU[iq_alu_stack_count].prf_rs2 <= rename_table[decoded_d.rs2];
                if (decoded_d.rd != 0) begin
                for (int i = 1; i < PRF_SIZE; i++) begin
                    if (free_list[i] == 1'b0) begin
                        free_list[i] <= 1'b1;
                        busy_table[i] <= 1'b1;
                        IQ_ALU[iq_alu_stack_count].prf_rd <= 7'(i);
                        rename_table[decoded_d.rd] <= 7'(i);
                        ROB[rob_stack_count].prf_rd <= 7'(i);
                        ROB[rob_stack_count].arf_rd <= decoded_d.rd;
                        ROB[rob_stack_count].prev_prf_rd <= rename_table[decoded_d.rd];
                        break;
                    end
                end
                end
                else begin
                    IQ_ALU[iq_alu_stack_count].prf_rd <= 7'(0);
                    ROB[rob_stack_count].prf_rd <= 7'(0);
                    ROB[rob_stack_count].arf_rd <= 5'(0);
                    ROB[rob_stack_count].prev_prf_rd <= 7'(0);
                end
                IQ_ALU[iq_alu_stack_count].instr <= decoded_d;
                IQ_ALU[iq_alu_stack_count].pc <= pc_d;
                iq_alu_stack_count <= iq_alu_stack_count + 1;
            end else if (decoded_d.issue == MEM) begin
                IQ_MEM[iq_mem_stack_count].issue <= decoded_d.issue;
                IQ_MEM[iq_mem_stack_count].prf_rs1 <= rename_table[decoded_d.rs1];
                IQ_MEM[iq_mem_stack_count].prf_rs2 <= rename_table[decoded_d.rs2];
                if (decoded_d.rd != 0) begin
                for (int i = 1; i < PRF_SIZE; i++) begin
                    if (free_list[i] == 1'b0) begin
                        free_list[i] <= 1'b1;
                        busy_table[i] <= 1'b1;
                        IQ_MEM[iq_mem_stack_count].prf_rd <= 7'(i);
                        rename_table[decoded_d.rd] <= 7'(i);
                        ROB[rob_stack_count].prf_rd <= 7'(i);
                        ROB[rob_stack_count].arf_rd <= decoded_d.rd;
                        ROB[rob_stack_count].prev_prf_rd <= rename_table[decoded_d.rd];
                        break;
                    end
                end
                end
                else begin
                    IQ_MEM[iq_mem_stack_count].prf_rd <= 7'(0);
                    ROB[rob_stack_count].prf_rd <= 7'(0);
                    ROB[rob_stack_count].arf_rd <= 5'(0);
                    ROB[rob_stack_count].prev_prf_rd <= 7'(0);
                end
                IQ_MEM[iq_mem_stack_count].instr <= decoded_d;
                IQ_MEM[iq_mem_stack_count].pc <= pc_d;
                iq_mem_stack_count <= iq_mem_stack_count + 1;
            end
            ROB[rob_stack_count].pc <= pc_d;
            ROB[rob_stack_count].state <= ROB_PENDING;
            ROB[rob_stack_count].instr <= instr_d;
            rob_stack_count <= rob_stack_count + 1;
        end
    end

    logic alu1_done, alu2_done, mem_done, mem_busy;
    int alu1_number, alu2_number;

    always_comb begin
        alu1_done = 1'b0;
        alu1_number = '0;
        alu2_done = 1'b0;
        alu2_number = '0;
        mem_done = 1'b0;
        if (pc_d >= INST_START) begin
            if(iq_alu_stack_count >0) begin
            for (int i = 0; i < XLEN; i++) begin
                if (i==32'(iq_alu_stack_count)) begin
                    break;
                end
                else if (!alu1_done && (busy_table[IQ_ALU[i].prf_rs1] == 1'b0) && (busy_table[IQ_ALU[i].prf_rs2] == 1'b0)) begin
                    alu1_number = i;
                    alu1_done = 1;
                end else if ((iq_alu_stack_count>1) && alu1_done && (busy_table[IQ_ALU[i].prf_rs1] == 1'b0) && (busy_table[IQ_ALU[i].prf_rs2] == 1'b0)) begin
                    alu2_number = i;
                    alu2_done = 1;
                    break;
                end 
            end
            end
            if(iq_mem_stack_count >0) begin
             if (!mem_busy && (busy_table[IQ_MEM[0].prf_rs1] == 1'b0) && (busy_table[IQ_MEM[0].prf_rs2] == 1'b0)) begin
                    mem_done = 1;
             end else begin
                    mem_done = 0;
             end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (alu1_done) begin
            ALUr_rd1 <= prf_register[IQ_ALU[alu1_number].prf_rs1];
            ALUr_rd2 <= prf_register[IQ_ALU[alu1_number].prf_rs2];
            ALUr_rd <= IQ_ALU[alu1_number].prf_rd;
            pc_alu <= IQ_ALU[alu1_number].pc;
            instr_alu <= IQ_ALU[alu1_number].instr;
            imm_alu <= IQ_ALU[alu1_number].instr.imm;
            if (busy_table[IQ_ALU[alu1_number].prf_rd] != 0) begin
                busy_table[IQ_ALU[alu1_number].prf_rd] <= 1'b1;
            end
        end
        else begin
            ALUr_rd1 <= 0;
            ALUr_rd2 <= 0;
            ALUr_rd <= 0;
            pc_alu <= 0;
            instr_alu <= 0;
            imm_alu <= 0;
        end
        if (alu2_done) begin
            ALU2r_rd1 <= prf_register[IQ_ALU[alu2_number].prf_rs1];
            ALU2r_rd2 <= prf_register[IQ_ALU[alu2_number].prf_rs2];
            ALU2r_rd <= IQ_ALU[alu2_number].prf_rd;
            pc_alu2 <= IQ_ALU[alu2_number].pc;
            instr_alu2 <= IQ_ALU[alu2_number].instr;
            imm_alu2 <= IQ_ALU[alu2_number].instr.imm;
            if (busy_table[IQ_ALU[alu2_number].prf_rd] != 0) begin
                busy_table[IQ_ALU[alu2_number].prf_rd] <= 1'b1;
            end
        end
        else begin
            ALU2r_rd1 <= 0;
            ALU2r_rd2 <= 0;
            ALU2r_rd <= 0;
            pc_alu2 <= 0;
            instr_alu2 <= 0;
            imm_alu2 <= 0;
        end
        if(mem_done) begin
            MEMr_rd1 <= prf_register[IQ_MEM[0].prf_rs1];
            MEMr_rd2 <= prf_register[IQ_MEM[0].prf_rs2];
            MEMr_rd <= IQ_MEM[0].prf_rd;
            pc_mem <= IQ_MEM[0].pc;
            instr_mem <= IQ_MEM[0].instr;
            imm_mem <= IQ_MEM[0].instr.imm;
            if (busy_table[IQ_MEM[0].prf_rd] != 0) begin
                busy_table[IQ_MEM[0].prf_rd] <= 1'b1;
            end
            mem_busy <= 1;
            for (int i = 0; i < 31; i++) begin
                IQ_MEM[i] <= IQ_MEM[i+1];
            end
            IQ_MEM[31] <= '0;
            iq_mem_stack_count <= iq_mem_stack_count - 1;
            en_m <= 1;
        end
        else begin
            MEMr_rd1 <= 0;
            MEMr_rd2 <= 0;
            MEMr_rd <= 0;
            pc_mem <= 0;
            instr_mem <= 0;
            imm_mem <= 0;
        end
        if (alu1_done && alu2_done) begin
            for (int i = alu1_number; i < 31-alu1_number; i++) begin
                if (i >= alu2_number-alu1_number-1) begin
                    IQ_ALU[i] <= IQ_ALU[i+2];
                end else begin
                    IQ_ALU[i] <= IQ_ALU[i+1];
                end
            end
            IQ_ALU[30] <= '0;
            IQ_ALU[31] <= '0;
            iq_alu_stack_count <= iq_alu_stack_count - 2;
        end else if (alu1_done && !alu2_done) begin
            for (int i = alu1_number; i < 31-alu1_number; i++) begin
                IQ_ALU[i] <= IQ_ALU[i+1];
            end
            IQ_ALU[31] <= '0;
            iq_alu_stack_count <= iq_alu_stack_count - 1;
        end else if (alu2_done && !alu1_done) begin
            for (int i = alu2_number; i < 31-alu2_number; i++) begin
                IQ_ALU[i] <= IQ_ALU[i+1];
            end
            IQ_ALU[31] <= '0;
            iq_alu_stack_count <= iq_alu_stack_count - 1;
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
        if (pc_redirect) begin
            prf_register[ALUr_rd] <= pc_alu + 4;
        end else if (ALUr_rd != 0) begin
            prf_register[ALUr_rd] <= alu_out;
        end else if (ALUr_rd == 0) begin
            prf_register[ALUr_rd] <= 0;
        end
    end



// ====== ALU2 Issue Stage ======================================================
    logic [XLEN-1:0] pc_alu2, imm_alu2, alu2_in1, alu2_in2, alu2_out;
    logic [6:0] ALU2r_rd;
    instruct_t instr_alu2;
    alu_op_t alu2_op;
    assign alu2_op = alu_op_e(instr_alu2.op, instr_alu2.funct3, instr_alu2.funct7);

    always_comb begin
        if (instr_alu2.op == OP_AUIPC) begin
            alu2_in1 = pc_alu2;
        end else begin
            alu2_in1 = ALU2r_rd1;
        end
        if ((instr_alu2.op == OP_JAL) || (instr_alu2.optype == OP_RTYPE) || (instr_alu2.optype == OP_BTYPE)) begin
            alu2_in2 = ALU2r_rd2;
        end else begin
            alu2_in2 = imm_alu2;
        end
    end

    assign alu2_out = alu_result(alu2_in1, alu2_in2, alu2_op);

    always_comb begin
        pc_redirect = 1'b0;
        if (instr_alu2.optype == OP_BTYPE) begin
            case (instr_alu2.funct3)
                F3_BEQ: pc_redirect = (alu2_out == 32'd0); // BEQ
                F3_BNE: pc_redirect = (alu2_out != 32'd0); // BNE
                F3_BLT: pc_redirect = (alu2_out == 32'd1); // BLT
                F3_BGE: pc_redirect = (alu2_out == 32'd0); // BGE
                F3_BLTU: pc_redirect = (alu2_out == 32'd1); // BLTU
                F3_BGEU: pc_redirect = (alu2_out == 32'd0); // BGEU
                default: pc_redirect = 1'b0;
            endcase
        end else if ((instr_alu2.op == OP_JAL) || (instr_alu2.op == OP_JALR)) begin
            pc_redirect = 1'b1;
        end

        if (pc_redirect) begin
            flush_d = 1;
            en_d = 0;
            en_f = 0;
            if (instr_alu2.op == OP_JALR) begin
                pc_src = alu2_out;
            end else begin
                if ($signed(imm_alu2) < 0) begin
                    pc_src = pc_alu2 + ($signed(imm_alu2));
                end else begin
                    pc_src = pc_alu2 + imm_alu2;
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
            if ((pc_alu2 == ROB[i].pc) || (pc_alu == ROB[i].pc))  begin
                ROB[i].state <= ROB_FINISHED;
            end
        end
    end


    always_ff @(negedge clk) begin
        if (pc_redirect) begin
            prf_register[ALU2r_rd] <= pc_alu2 + 4;
        end  else if (ALU2r_rd != 0) begin
            prf_register[ALU2r_rd] <= alu2_out;
        end else if (ALU2r_rd == 0) begin
            prf_register[ALU2r_rd] <= 0;
        end
    end


    // ====== MEM Issue Stage ======================================================
    logic [XLEN-1:0] pc_mem, imm_mem, mem_op_out;
    logic [6:0] MEMr_rd;
    instruct_t instr_mem;
    alu_op_t mem_op;
    assign mem_op = alu_op_e(instr_mem.op, instr_mem.funct3, instr_mem.funct7);

    assign mem_op_out = alu_result(MEMr_rd1, imm_mem, mem_op);

    always_ff @(posedge clk) begin
        mem_read_in <= MEMr_rd2;
        pc_mem_read <= pc_mem;
        instr_mem_read <= instr_mem;
        MEMr_read_rd <= MEMr_rd;
        data_word_address <= mem_op_out;
    end

    // ====== MEM Read Stage ======================================================
    logic [XLEN-1:0] pc_mem_read, mem_read_in, data_read_out, dm_a, dm_wd;
    logic [6:0] MEMr_read_rd;
    instruct_t instr_mem_read;
    data_byte_cache_t data_byte_cache [0:3]; // 32 byte data cache
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
        if (instr_mem_read.op == OP_LOAD) begin
            dm_a <= data_word_address;
        end 
    end

    always_comb begin
        if (instr_mem_read.op == OP_STORE) begin
            casez (instr_mem_read.funct3)
                F3_SB: begin
                    data_byte_cache[0].value = mem_read_in[7:0];
                    data_byte_cache[0].data_address = data_word_address;
                    data_byte_cache[0].pc = pc_mem_read;
                end
                F3_SH: begin
                    data_byte_cache[0].pc = pc_mem_read;
                    data_byte_cache[0].value = mem_read_in[7:0];
                    data_byte_cache[0].data_address = data_word_address;
                    data_byte_cache[1].value = mem_read_in[15:8];
                    data_byte_cache[1].data_address = data_word_address + 1;
                end
                F3_SW: begin
                    data_byte_cache[0].pc = pc_mem_read;
                    data_byte_cache[0].value = mem_read_in[7:0];
                    data_byte_cache[0].data_address = data_word_address;
                    data_byte_cache[1].value = mem_read_in[15:8];
                    data_byte_cache[1].data_address = data_word_address + 1;
                    data_byte_cache[2].value = mem_read_in[23:16];
                    data_byte_cache[2].data_address = data_word_address + 2;
                    data_byte_cache[3].value = mem_read_in[31:24];
                    data_byte_cache[3].data_address = data_word_address + 3;
                end
                default: begin data_byte_cache[0] = data_byte_cache[0];
                        data_byte_cache[1] = data_byte_cache[1];
                        data_byte_cache[2] = data_byte_cache[2];
                        data_byte_cache[3] =   data_byte_cache[3]; 
                end
                
            endcase
        end else if (instr_mem_read.op == OP_LOAD) begin
            casez (instr_mem_read.funct3)
                F3_LB:
                mem_out = {{(XLEN - 8) {data_read_out[7]}}, data_read_out[7:0]};
                F3_LH:
                mem_out = {
                    {(XLEN - 16) {data_read_out[15]}}, data_read_out [15:0]
                };
                F3_LW: mem_out = data_read_out;
                F3_LBU: mem_out = {{(XLEN - 8) {1'b0}}, data_read_out [7:0]};
                F3_LHU:
                mem_out = {
                    {(XLEN - 16) {1'b0}}, data_read_out [15:0]
                };
            endcase
        end else  begin 
            mem_out = 0;
            data_byte_cache[0] = data_byte_cache[0];
            data_byte_cache[1] = data_byte_cache[1];
            data_byte_cache[2] = data_byte_cache[2];
            data_byte_cache[3] = data_byte_cache[3];
        end
    end

    always_ff @(posedge clk) begin
        dm_a <= data_word_address;
        if(instr_mem_read.op == OP_LOAD) begin
            prf_register[MEMr_read_rd] <= mem_out;
        end
        for (int i = 0; i < rob_stack_count; i++) begin
            if (pc_mem_read == ROB[i].pc) begin
                ROB[i].state <= ROB_FINISHED;
            end
        end
    end

    // ====== Commit Stage ========================================================
    logic [XLEN-1:0] r_wd3, r_wd3_2, commit_mem_a, commit_mem_wd;
    logic commit_mem_cd;
    logic [4:0] commit_rd, commit_rd2;

    always_ff @(posedge clk) begin
        if (ROB[0].state == ROB_FINISHED) begin
            pc_o <= ROB[0].pc;
            instr_o <= ROB[0].instr;
            reg_data_o <= prf_register[ROB[0].prf_rd];
            reg_addr_o <= ROB[0].arf_rd;
            update_o <= 1;
            r_wd3 <= prf_register[ROB[0].prf_rd];
            commit_rd <= ROB[0].arf_rd;
            prf_register[ROB[0].prev_prf_rd] <= 0;
            free_list[ROB[0].prev_prf_rd] <= 1'b0;
            busy_table[ROB[0].prf_rd] <= 1'b0;
            if (ROB[0].instr[6:0] == 7'b0100011) begin
                dm_cd <= 1;
                dm_wd <= {data_byte_cache[3].value, data_byte_cache[2].value, 
                data_byte_cache[1].value, data_byte_cache[0].value};
                mem_busy <= 0;
                en_m <= 0;
            end
            if(ROB[1].state == ROB_FINISHED) begin
                pc_o2 <= ROB[1].pc;
                instr_o2 <= ROB[1].instr;
                reg_data_o2 <= prf_register[ROB[1].prf_rd];
                reg_addr_o2 <= ROB[1].arf_rd;
                update_o2 <= 1;
                r_wd3_2 <= prf_register[ROB[1].prf_rd];
                commit_rd2 <= ROB[1].arf_rd;
                prf_register[ROB[1].prev_prf_rd] <= 0;
                free_list[ROB[1].prev_prf_rd] <= 1'b0;
                busy_table[ROB[1].prf_rd] <= 1'b0;
                for (int i2 = 0; i2 < 30; i2++) begin
                ROB[i2] <= ROB[i2+2];
                end
                rob_stack_count <= rob_stack_count - 2;
                ROB[30] <= '0;
                ROB[31] <= '0;
            end else begin
                for (int i2 = 0; i2 < 31; i2++) begin
                ROB[i2] <= ROB[i2+1];
                end
                rob_stack_count <= rob_stack_count - 1;
                ROB[31] <= '0;
                update_o2 <= 0;
                commit_rd2 <= 0;
                r_wd3_2 <= 0;
            end
        
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
            dm_cd <= 0;
        end else begin
            register[commit_rd] <= r_wd3;
        end
        if (commit_rd2 == 0) begin
            register[0] <= 0;
            dm_cd <= 0;
        end else begin
            register[commit_rd2] <= r_wd3_2;
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
                decode_function.rd = 0;
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

