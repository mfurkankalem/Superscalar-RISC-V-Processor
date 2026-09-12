

module data_memory import riscv_pkg::*; (
    input logic clk,
    input dm_t dm_cd,
    input logic [XLEN-1:0] dm_a,
    input logic [XLEN-1:0] dm_wd,
    output logic [7:0] data [0:XLEN-1], 
    output logic [XLEN-1:0] dm_rd 
);

               

assign dm_rd = {data[dm_a+3], data[dm_a+2], data[dm_a+1], data[dm_a]};

  always @(negedge clk) begin
  
    if(dm_cd==DM_WRITE_B) begin
      data[dm_a] <= dm_wd[7:0];
    end
    else if (dm_cd==DM_WRITE_H) begin
      data[dm_a] <= dm_wd[7:0];
      data[dm_a+1] <= dm_wd[15:8];
    end
    else if (dm_cd==DM_WRITE_W) begin
      data[dm_a] <= dm_wd[7:0];
      data[dm_a+1] <= dm_wd[15:8];
      data[dm_a+2] <= dm_wd[23:16];
      data[dm_a+3] <= dm_wd[31:24];
    end
  end

  final begin
    integer fd;
    integer i;
    fd = $fopen("data_memory.txt", "w");
    for (i = 0; i < XLEN; i = i + 1) begin
      $fwrite(fd, "data[%0d] = %0d (0x%08h)\n", i, data[i], data[i]);
    end
    $fclose(fd);
  end
    


endmodule
