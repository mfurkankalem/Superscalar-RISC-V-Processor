


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
        
        pc_f <= pc_f_in;
        pc_d <= pc_f;
        instr_d <= instruction_cache[pc_f[6:2]];
    end else begin
      pc_f <= INST_START;
      pc_d <= pc_f;
      startvalue <= 1;
      end
    end end
    else
      pc_f <= 0;
end

// ====== Decode Stage =========================================================
logic [XLEN-1:0] pc_d, instr_d, ALUr_rd1, ALUr_rd2, MEMr_rd1, MEMr_rd2;
logic [XLEN-1:0] register [0:XLEN-1];   //register file
logic [XLEN-1:0] register_busy;
instruct_t  decoded_d;
issue_t decode_result;

assign decoded_d = decode_function(instr_d);

always_comb begin
    if(!register_busy[decoded_d.rd]) begin
        if(decoded_d.op == OP_RTYPE || decoded_d.op == OP_ITYPE
        || decoded_d.op == OP_BTYPE || decoded_d.op == OP_UTYPE
        || decoded_d.op == OP_JTYPE) begin
            decode_result.ALU = 1'b1;
            decode_result.MEM = 1'b0;
        end
        else begin
            decode_result.MEM = 1'b1;
            decode_result.ALU = 1'b0;
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
                instr_alu <= instr_d;
            end
            else if(decode_result.MEM) begin
                MEMr_rd1 <= register[decoded_d.rs1];
                MEMr_rd2 <= register[decoded_d.rs2];
                instr_mem <= instr_d;
                pc_mem <= pc_d;
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
logic [XLEN-1:0] pc_alu, instr_alu;
instruct_t decoded_alu;
assign decoded_alu = decode_function(instr_alu);
assign register_busy[decoded_alu.rd] = 1'b1;


// ====== MEM Issue Stage ======================================================
logic [XLEN-1:0] pc_mem, instr_mem;
instruct_t decoded_mem;
assign decoded_mem = decode_function(instr_mem);
assign register_busy[decoded_mem.rd] = 1'b1;




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

// ====== Functions ==========================================================

function automatic instruct_t decode_function(input logic [XLEN-1:0] instr);
    decode_function.op = instr[6:0];
    decode_function.rd = instr[11:7];
    decode_function.funct3 = instr[14:12];
    decode_function.rs1 = instr[19:15];
    decode_function.rs2 = instr[24:20];
    decode_function.funct7 = instr[31:25];
    decode_function.imm = instr[31:7];
endfunction

function automatic logic [XLEN-1:0] prog_cnt(input logic [XLEN-1:0] pc_value);
    prog_cnt = pc_value + 4;
endfunction

// ====== Others ==========================================================


assign update_o = 0;
assign pc_o = 0;
assign instr_o = 0;
assign reg_addr_o = 0;
assign reg_data_o = 0;
assign mem_addr_o = 0;
assign data_o [0] = 0;
assign mem_data_o = 0;

endmodule


