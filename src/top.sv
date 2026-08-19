


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


    // === Instruction Fetch ===================================================
logic [XLEN-1:0] pc, im_rd;
logic [XLEN-1:0] instruction_cache [0:31]; // 31 instruction cache
assign pc = INST_START;

instruction_memory instruction_memory_0(.im_a(pc), .im_rd(im_rd));


    // === Others ==============================================================


assign update_o = 0;
assign pc_o = 0;
assign instr_o = 0;
assign reg_addr_o = 0;
assign reg_data_o = 0;
assign mem_addr_o = 0;
assign data_o [0] = 0;
assign mem_data_o = 0;

endmodule


