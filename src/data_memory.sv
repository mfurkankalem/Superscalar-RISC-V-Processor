

module data_memory (
    input logic clk, dm_cd,
    input logic [31:0] dm_a,
    input logic [31:0] dm_wd,
    output logic [31:0] data [0:31],  
    output logic [31:0] dm_rd 
);

               

assign dm_rd = data[dm_a];

  always @(negedge clk) begin
  
    if(dm_cd==1) begin
      data[dm_a] <= dm_wd;
    end
  end

  final begin
    integer fd;
    integer i;
    fd = $fopen("data_memory.txt", "w");
    for (i = 0; i < 32; i = i + 1) begin
      $fwrite(fd, "data[%0d] = %0d (0x%08h)\n", i, data[i], data[i]);
    end
    $fclose(fd);
  end
    


endmodule
