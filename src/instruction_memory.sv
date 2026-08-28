module instruction_memory import riscv_pkg::*; #(
    parameter string InitFile = "test/test.hex"
) (
    input  logic [XLEN-1:0] im_a,
    output logic [XLEN-1:0] im_rd,
    output logic [XLEN-1:0] im_rd2
);

    logic [XLEN-1:0] memory [logic [XLEN-1:0]];

    initial begin
        integer fd;
        logic [XLEN-1:0] data;
        logic [XLEN-1:0] addr;

        fd = $fopen(InitFile, "r");
        if (fd == 0) begin
            $display("ERROR: %s not found", InitFile);
            $finish;
        end

        addr = INST_START;

        while (!$feof(fd)) begin
            if ($fscanf(fd, "%h\n", data) == 1) begin
                if (data != '0) begin
                    memory[addr] = data;
                end
                addr = addr + 4;
            end
        end
        $fclose(fd);
    end

    assign im_rd = memory.exists(im_a) ? memory[im_a] : '0;
    assign im_rd2 = memory.exists(im_a+4) ? memory[im_a+4] : '0;

endmodule
