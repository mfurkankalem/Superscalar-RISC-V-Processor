


module top import riscv_pkg::*;     
    #(
        parameter DMemInitFile = "dmem.mem", // data memory initialization file
        parameter IMemInitFile = "imem.mem" // instruction memory initialization file
    ) (
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

logic en_f = 1;

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
    if(startvalue) begin
        if (en_f) begin
        pc_f <= pc_f_in;
        pc_d <= pc_f;
        instr_d <= instruction_cache[pc_f[6:2]];
        end
    end else begin
      pc_f <= INST_START;
      startvalue <= 1;
      end
    end else
      pc_f <= 0;
end

// ====== Decode Stage =========================================================
logic [XLEN-1:0] pc_d, instr_d;



// ====== Fake Stage ==========================================================

always_comb begin
    pc_f_in = prog_cnt(pc_f);
end

// ====== Functions ==========================================================

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


