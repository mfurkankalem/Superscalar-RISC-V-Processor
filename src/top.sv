


module top import riscv_pkg::*;     
    #(
        parameter DMemInitFile = "dmem.mem", // data memory initialization file
        parameter IMemInitFile = "imem.mem" // instruction memory initialization file
    ) (
        input logic test_i, //test
        input logic clk,
        input logic rstn_i, // system reset //??
        input logic [XLEN-1:0] addr_i, // data memory report
        output logic update_o, // log update signal
        output logic [XLEN-1:0] pc_o, // log program counter
        output logic [XLEN-1:0] instr_o, // log instruction
        output logic [4:0] reg_addr_o, // log register address
        output logic [XLEN-1:0] reg_data_o, // log register data
        output logic [XLEN-1:0] mem_addr_o, // retired memory address
        output logic [7:0] data_o [0:XLEN-1], // data memory write
        output logic [XLEN-1:0] mem_data_o // retired memory data //imem için kullanılacak
        
    );

logic en_f;
logic en_d = 1;
logic flush_d = 0;

assign en_f = test_i; //test

// ====== Fetch Stage ==========================================================
logic startvalue;
logic [XLEN-1:0] pc_f, im_rd, pc_f_in;
logic [XLEN-1:0] instruction_cache [0:31]; // 32 instruction cache


instruction_memory instruction_memory_0(.im_a(pc_f), .im_rd(im_rd)); // read memory

always_ff @(negedge clk) begin
    if (im_rd != instruction_cache[pc_f[6:2]]) begin
        instruction_cache[pc_f[6:2]] <= im_rd;
    end
end

always_ff @(posedge clk) begin
    if (rstn_i) begin
    if (en_f) begin
    if(startvalue) begin
        
        if (pc_f_in >= INST_START) begin
        pc_f <= pc_f_in;
        pc_d <= pc_f;
        instr_d <= instruction_cache[pc_f[6:2]]; end
    end else begin
      pc_f <= INST_START;
      startvalue <= 1;
      end
    end end
    else
      pc_f <= 0;
end

// ====== Decode Stage =========================================================
logic [XLEN-1:0] pc_d, instr_d, imm_d, ALUr_rd1, ALUr_rd2, MEMr_rd1, MEMr_rd2;
logic [XLEN-1:0] register [0:XLEN-1];   //register file
logic [XLEN-1:0] register_busy;
instruct_t  decoded_d;
issue_t decode_result;

assign decoded_d = decode_function(instr_d);
assign imm_d =immediate_function(decoded_d.op, decoded_d.imm);

always_comb begin
    if(!register_busy[decoded_d.rd]) begin
        if(decoded_d.op == OP_LTYPE || decoded_d.op == OP_STYPE) begin
            decode_result.ALU = 1'b0;
            decode_result.MEM = 1'b1;
        end
        else begin
            decode_result.MEM = 1'b0;
            decode_result.ALU = 1'b1;
        end
    end 
    else begin
        decode_result.ALU = 1'b0;
        decode_result.MEM = 1'b0;
    end
    end
    

always_ff @(posedge clk) begin
    if (en_d) begin
        if(!flush_d) begin
            if(decode_result.ALU) begin
                ALUr_rd1 <= register[decoded_d.rs1];
                ALUr_rd2 <= register[decoded_d.rs2];
                pc_alu <= pc_d;
                instr_alu <= decoded_d;
                imm_alu <= imm_d;
            end
            else if(decode_result.MEM) begin
                MEMr_rd1 <= register[decoded_d.rs1];
                MEMr_rd2 <= register[decoded_d.rs2];
                pc_mem <= pc_d;
                instr_mem <= decoded_d;
                imm_mem <= imm_d;
            end
        end
    end
end

// later
always @(negedge clk) begin
    if(r_cd==1) begin
      if(decoded_w.rd==0)
        register[0] <= 0;
      else
      register[decoded_w.rd] <= r_wd3;
    end
end

// ====== ALU Issue Stage ======================================================
logic [XLEN-1:0] pc_alu, imm_alu, alu_in1, alu_in2, alu_out;
instruct_t instr_alu;
alu_op_t alu_op;
assign register_busy[instr_alu.rd] = 1'b1;
assign alu_op = alu_op_e(instr_alu.op, instr_alu.funct3, instr_alu.funct7);

always_comb begin
    if (instr_alu.op == OP_AUIPC)
        alu_in1 = pc_alu;
    else
        alu_in1 = ALUr_rd1;
    if ((instr_alu.op == OP_JAL) || (instr_alu.op == OP_RTYPE) || 
        (instr_alu.op == OP_BTYPE))
        alu_in2 = ALUr_rd2;
    else
        alu_in2 = imm_alu;
end

assign alu_out = alu_result(alu_in1, alu_in2, alu_op);




// ====== MEM Issue Stage ======================================================
logic [XLEN-1:0] pc_mem, imm_mem;
instruct_t instr_mem;
assign register_busy[instr_mem.rd] = 1'b1;




// ====== Writeback Stage =====================================================
logic [XLEN-1:0] pc_w;
instruct_t decoded_w;
assign decoded_w = decode_function(instr_d);


// ====== Commit Stage ========================================================
logic r_cd = 0;
logic [XLEN-1:0] r_wd3 = 0;


// ====== Fake Stage ==========================================================

always_comb begin
    if (en_f) 
    pc_f_in = prog_cnt(pc_f);
    else
    pc_f_in = 0;
end

// ====== Decode Functions =====================================================

function automatic instruct_t decode_function(input logic [XLEN-1:0] instr);
    decode_function.opname = opnames_t'(instr[16:0]);
    decode_function.op = instr[6:0];
    decode_function.rd = instr[11:7];
    decode_function.funct3 = instr[14:12];
    decode_function.rs1 = instr[19:15];
    decode_function.rs2 = instr[24:20];
    decode_function.funct7 = instr[31:25];
    decode_function.imm = instr[31:7];
endfunction

function automatic logic [XLEN-1:0] immediate_function(input logic [6:0] op, input logic [24:0] imm);
    case(op)
        OP_ITYPE: immediate_function = {{20{imm[24]}}, imm[24:13]};
        OP_STYPE: immediate_function = {{20{imm[24]}}, imm[24:18], imm[4:0]};
        OP_BTYPE: immediate_function = {{19{imm[24]}}, imm[24], imm[0], imm[23:18], imm[4:1], 1'b0};
        OP_LUI : immediate_function  = {imm[24:5], 12'b0};
        OP_AUIPC: immediate_function = {imm[24:5], 12'b0};
        OP_JAL : immediate_function  = {{11{imm[24]}}, imm[24], imm[12:5], imm[13], imm[23:14], 1'b0};
        OP_JALR: immediate_function  = {{11{imm[24]}}, imm[24], imm[12:5], imm[13], imm[23:14], 1'b0};
        default: immediate_function  = '0;
    endcase
endfunction

// ====== ALU Functions =======================================================

function automatic alu_op_t alu_op_e (input logic [6:0] op, input logic [2:0] funct3, 
input logic [6:0] funct7);
    case(op)
        OP_ITYPE: begin
            case(funct3)
                F3_ADD: begin
                    if(funct7 == F7_ADD)
                        alu_op_e = ALU_ADD;
                    else if(funct7 == F7_SUB)
                        alu_op_e = ALU_SUB;
                    else
                        alu_op_e = ALU_INVALID;
                end
                F3_SLL: alu_op_e = ALU_SLL;
                F3_SLT: alu_op_e = ALU_SLT;
                F3_SLTU: alu_op_e = ALU_SLTU;
                F3_XOR: alu_op_e = ALU_XOR;
                F3_OR: alu_op_e = ALU_OR;
                F3_AND: alu_op_e = ALU_AND;
                F3_SR: begin
                    if(funct7 == F7_SRL)
                        alu_op_e = ALU_SRL;
                    else if(funct7 == F7_SRA)
                        alu_op_e = ALU_SRA;
                    else
                        alu_op_e = ALU_INVALID;
                end
                default: alu_op_e = ALU_INVALID;
            endcase
        end
        OP_RTYPE: begin
            case(funct3)
                F3_ADD: begin
                    if(funct7 == F7_ADD)
                        alu_op_e = ALU_ADD;
                    else if(funct7 == F7_SUB)
                        alu_op_e = ALU_SUB;
                    else
                        alu_op_e = ALU_INVALID;
                end
                F3_SLL: alu_op_e = ALU_SLL;
                F3_SLT: alu_op_e = ALU_SLT;
                F3_SLTU: alu_op_e = ALU_SLTU;
                F3_XOR: alu_op_e = ALU_XOR;     
                F3_OR: alu_op_e = ALU_OR;
                F3_AND: alu_op_e = ALU_AND;
                F3_SR: begin
                    if(funct7 == F7_SRL)
                        alu_op_e = ALU_SRL;
                    else if(funct7 == F7_SRA)
                        alu_op_e = ALU_SRA;
                    else
                        alu_op_e = ALU_INVALID;
                end
            endcase
        end
        OP_LTYPE: alu_op_e = ALU_ADD;
        OP_STYPE: alu_op_e = ALU_ADD;
        OP_BTYPE: begin
            case(funct3)
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

function automatic logic [XLEN-1:0] alu_result(input logic [XLEN-1:0] alu_a, input logic [XLEN-1:0] alu_b, input alu_op_t alu_cd);
    case(alu_cd)
        ALU_ADD: alu_result = alu_a + alu_b;
        ALU_SUB: alu_result = alu_a - alu_b;
        ALU_AND: alu_result = alu_a & alu_b;
        ALU_OR:  alu_result = alu_a | alu_b;
        ALU_XOR: alu_result = alu_a ^ alu_b;
        ALU_SLL: alu_result = alu_a << alu_b[4:0];
        ALU_SRL: alu_result = alu_a >> alu_b[4:0];
        ALU_SRA: alu_result = $signed(alu_a) >>> alu_b[4:0];
        ALU_SLT: alu_result = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;
        ALU_SLTU:alu_result = (alu_a < alu_b) ? 32'd1 : 32'd0;
        default:alu_result = 'x;
    endcase

endfunction    
// ====== Others ==========================================================

function automatic logic [XLEN-1:0] prog_cnt(input logic [XLEN-1:0] pc_value);
    prog_cnt = pc_value + 4;
endfunction

assign update_o = 0;
assign pc_o = 0;
assign instr_o = 0;
assign reg_addr_o = 0;
assign reg_data_o = 0;
assign mem_addr_o = 0;
assign data_o [0] = 0;
assign mem_data_o = 0;

endmodule


