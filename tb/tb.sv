module tb ();
  logic [riscv_pkg::XLEN-1:0] addr, addr2;
  logic [31:0]                 data [0:31];  
  logic [riscv_pkg::XLEN-1:0] pc, pc2;
  logic [riscv_pkg::XLEN-1:0] instr, instr2;
  logic [                4:0] reg_addr, reg_addr2;
  logic [riscv_pkg::XLEN-1:0] reg_data, reg_data2;
  logic [riscv_pkg::XLEN-1:0] mem_addr;
  logic [riscv_pkg::XLEN-1:0] mem_data;
  logic                       update;
  logic                       update2;
  logic                       clk;
  logic                       rstn;

  top i_top (
      .clk(clk),
      .rstn_i(rstn),
      .addr_i(addr),
      .update_o(update),
      .update_o2(update2),
      .data_o(data),
      .pc_o(pc),
      .pc_o2(pc2),
      .instr_o(instr),
      .instr_o2(instr2),
      .reg_addr_o(reg_addr),
      .reg_addr_o2(reg_addr2),
      .reg_data_o(reg_data),
      .reg_data_o2(reg_data2),
      .mem_addr_o(mem_addr),  
      .mem_data_o(mem_data)

  );
  integer file_pointer;
  initial begin
    file_pointer = $fopen("model.log", "w");
    #1
    forever begin
      if (update) begin
        if (reg_addr == 0) begin
          $fdisplay(file_pointer, "0x%8h (0x%8h)", pc, instr);
        end else begin
          if (reg_addr > 9) begin
            $fdisplay(file_pointer, "0x%8h (0x%8h) x%0d 0x%8h", pc, instr, reg_addr, reg_data);
          end else begin
            $fdisplay(file_pointer, "0x%8h (0x%8h) x%0d  0x%8h", pc, instr, reg_addr, reg_data);
          end
        end
       end
       if(update2) begin
        if (reg_addr2 == 0) begin
          $fdisplay(file_pointer, "0x%8h (0x%8h)", pc2, instr2);
        end else begin
          if (reg_addr2 > 9) begin
            $fdisplay(file_pointer, "0x%8h (0x%8h) x%0d 0x%8h", pc2, instr2, reg_addr2, reg_data2);
          end else begin
            $fdisplay(file_pointer, "0x%8h (0x%8h) x%0d  0x%8h", pc2, instr2, reg_addr2, reg_data2);
          end
        end
       end
      #2;
    end
  end

  initial clk = 0;
  always #1 clk = ~clk;

  initial begin
    rstn = 0;
    #2;
    rstn = 1;
    #2
    #200;
    for (int i = 0; i < riscv_pkg::XLEN/4; i++) begin
      addr = i*4;
      $display("data @ mem[0x%8h] = %8h", addr, data[addr]);
    end
    $finish;
  end


  initial begin
    $dumpfile("dump.vcd");
    $dumpvars();
  end

endmodule
