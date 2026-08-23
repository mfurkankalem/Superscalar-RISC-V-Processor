


module top
  import riscv_pkg::*;
#(
    parameter DMemInitFile = "dmem.mem",  // data memory initialization file
    parameter IMemInitFile = "imem.mem"   // instruction memory initialization file
) (
    input logic test_i,  //test
    input logic clk,
    input logic rstn_i,  // system reset 
    input logic [XLEN-1:0] addr_i,  // data memory report
    output logic update_o,  // log update signal
    output logic [XLEN-1:0] pc_o,  // log program counter
    output logic [XLEN-1:0] instr_o,  // log instruction
    output logic [4:0] reg_addr_o,  // log register address
    output logic [XLEN-1:0] reg_data_o,  // log register data
    output logic [XLEN-1:0] mem_addr_o,  // retired memory address
    output logic [7:0] data_o[0:XLEN-1],  // data memory write
    output logic [XLEN-1:0] mem_data_o  // retired memory data 

);

  logic en_f;
  logic en_d;
  logic en_m;
  logic flush_d;



  // ====== Fetch Stage ==========================================================
  logic startvalue;
  logic [XLEN-1:0] pc_f, im_rd;
  logic [XLEN-1:0] instruction_cache[0:31];  // 32 instruction cache


  instruction_memory instruction_memory_0 (
      .im_a (pc_f),
      .im_rd(im_rd)
  );  // read memory

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
            pc_f    <= pc_src;
						pc_d <= 0;
						instr_d <= 0;
            end
          else  if (pc_f >= INST_START) begin
            pc_f <= pc_f + 4;
            pc_d <= pc_f;
            instr_d <= instruction_cache[pc_f[6:2]];
          end
        end 
        
        else begin
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
  logic [XLEN-1:0] pc_d, instr_d, imm_d, ALUr_rd1, ALUr_rd2, MEMr_rd1, MEMr_rd2;
  logic [XLEN-1:0] register[0:XLEN-1];  //register file
  logic [XLEN-1:0] register_busy, cache_busy;
  rob_t ROB[0:XLEN-1];
  logic [4:0] rob_stack_count;
  instruct_t decoded_d;
  issue_t decode_result;

  assign decoded_d = decode_function(instr_d);
  assign imm_d = immediate_function(decoded_d.op, decoded_d.imm);


  always_comb begin
    if (((!register_busy[decoded_d.rs1]) && (!register_busy[decoded_d.rs2]))
		|| ((!register_busy[decoded_d.rs1]) && ((decoded_d.op == OP_ITYPE)||
		(decoded_d.op == OP_LUI) || (decoded_d.op == OP_AUIPC) ||
		(decoded_d.op == OP_JAL) || (decoded_d.op == OP_JALR) ))) begin
      en_f = 1;
      en_d = 1;
      if (decoded_d.op == OP_STYPE) begin
        decode_result.ALU = 1'b0;
        decode_result.MEM = 1'b1;
      end else if (decoded_d.rd > 0) begin
        if (decoded_d.op == OP_LTYPE) begin
          decode_result.ALU = 1'b0;
          decode_result.MEM = 1'b1;
        end else begin
          decode_result.MEM = 1'b0;
          decode_result.ALU = 1'b1;
        end
      end else begin
        decode_result.ALU = 1'b0;
        decode_result.MEM = 1'b0;
      end
    end else begin
      en_f = 0;
      en_d = 0;
      decode_result.ALU = 1'b0;
      decode_result.MEM = 1'b0;
    end
  end


  always_ff @(posedge clk) begin
    if (en_d) begin
      if (!flush_d) begin
        if (decode_result.ALU) begin
          ALUr_rd1 <= register[decoded_d.rs1];
          ALUr_rd2 <= register[decoded_d.rs2];
          pc_alu <= pc_d;
          instr_alu <= decoded_d;
          imm_alu <= imm_d;
          if (decoded_d.rd > 0) register_busy[decoded_d.rd] <= 1'b1;
          rob_stack_count <= rob_stack_count + 1;
          ROB[rob_stack_count].pc <= pc_d;
          ROB[rob_stack_count].valid <= 1;
        end else if (decode_result.MEM) begin
          MEMr_rd1 <= register[decoded_d.rs1];
          MEMr_rd2 <= register[decoded_d.rs2];
          pc_mem <= pc_d;
          instr_mem <= decoded_d;
          imm_mem <= imm_d;
          if (instr_mem.op == OP_LTYPE) begin
            if (decoded_d.rd > 0) register_busy[decoded_d.rd] <= 1'b1;
          end else begin
            cache_busy[decoded_d.rs1] <= 1'b1;
          end
          rob_stack_count <= rob_stack_count + 1;
          ROB[rob_stack_count].pc <= pc_d;
          ROB[rob_stack_count].valid <= 1;
        end
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
  end


  // ====== ALU Issue Stage ======================================================
  logic [XLEN-1:0] pc_alu, imm_alu, alu_in1, alu_in2, alu_out, pc_src;
  logic pc_redirect;
  instruct_t instr_alu;
  alu_op_t alu_op;
  assign alu_op = alu_op_e(instr_alu.op, instr_alu.funct3, instr_alu.funct7);

  always_comb begin
    if (instr_alu.op == OP_AUIPC) alu_in1 = pc_alu;
    else alu_in1 = ALUr_rd1;
    if ((instr_alu.op == OP_JAL) || (instr_alu.op == OP_RTYPE) || (instr_alu.op == OP_BTYPE))
      alu_in2 = ALUr_rd2;
    else alu_in2 = imm_alu;
  end

  assign alu_out = alu_result(alu_in1, alu_in2, alu_op);

  always_comb begin
    pc_redirect = 1'b0;
    if (instr_alu.op == OP_BTYPE) begin
      case (instr_alu.funct3)
        F3_BEQ:  pc_redirect = (alu_out == 32'd0);  // BEQ
        F3_BNE:  pc_redirect = (alu_out != 32'd0);  // BNE
        F3_BLT:  pc_redirect = (alu_out == 32'd1);  // BLT
        F3_BGE:  pc_redirect = (alu_out == 32'd0);  // BGE
        F3_BLTU: pc_redirect = (alu_out == 32'd1);  // BLTU
        F3_BGEU: pc_redirect = (alu_out == 32'd0);  // BGEU
        default: pc_redirect = 1'b0;
      endcase
    end
    if (pc_redirect) begin
      if ($signed(imm_alu) < 0) pc_src = pc_alu + ($signed(imm_alu));
      else pc_src = pc_alu + imm_alu;
			flush_d = 1;
			en_d = 0;
			en_f = 0;
    end else begin
      pc_src = 0;
			en_d = 1;
			en_f = 1;
			flush_d = 0;
    end

  end


  always_ff @(posedge clk) begin
    alu_w       <= alu_out;
    instr_alu_w <= instr_alu;
    pc_alu_w    <= pc_alu;
  end


  // ====== MEM Issue Stage ======================================================
  logic [XLEN-1:0] pc_mem, imm_mem, mem_in1, mem_in2, mem_op_out;
  instruct_t instr_mem;
  alu_op_t   mem_op;
  assign mem_op = alu_op_e(instr_mem.op, instr_mem.funct3, instr_mem.funct7);

  assign mem_in1 = MEMr_rd1;
  assign mem_in2 = imm_mem;
  assign mem_op_out = alu_result(mem_in1, mem_in2, mem_op);

  always_comb begin
    if (cache_busy[decoded_d.rd]) begin
      en_m = 0;
      en_d = 0;
      en_f = 0;
    end else begin
      en_m = 1;
      en_d = 1;
      en_f = 1;
    end
  end
  always_ff @(posedge clk) begin
    if (en_m) begin
      mem_read_in1   <= mem_op_out;
      mem_read_in2   <= MEMr_rd2;
      pc_mem_read    <= pc_mem;
      instr_mem_read <= instr_mem;
    end
  end


  // ====== MEM Read Stage ======================================================
  logic [XLEN-1:0] pc_mem_read, mem_read_in1, mem_read_in2, data_read_out;
  instruct_t instr_mem_read;
  logic [7:0] data_byte_cache[0:XLEN-1];  // 32 byte data cache
  logic [XLEN-1:0] data_word_address;
  logic [XLEN-1:0] mem_out;
  logic dm_cd = 0;

  assign data_word_address = mem_read_in1 - (mem_read_in1 % 4);
  data_memory data_memory_0 (
      .clk  (clk),
      .dm_a (data_word_address),
      .dm_rd(data_read_out),
      .dm_wd(mem_read_in2),
      .dm_cd(dm_cd)
  );  // read memory

  always_ff @(negedge clk) begin
    if (instr_mem_read.op == OP_LTYPE) begin
      if (data_read_out[7:0] != data_byte_cache[data_word_address]) begin
        for (int i = 0; i < 4; i = i + 1) begin
          data_byte_cache[data_word_address+i] <= data_read_out[i*8+:8];
        end
      end
    end
  end


  always_comb begin
    if (instr_mem_read.op == OP_STYPE) begin
      casez (instr_mem_read.funct3)
        F3_SB:   data_byte_cache[mem_read_in1] = mem_read_in2[7:0];
        F3_SH: begin
          data_byte_cache[mem_read_in1]   = mem_read_in2[7:0];
          data_byte_cache[mem_read_in1+1] = mem_read_in2[15:8];
        end
        F3_SW: begin
          data_byte_cache[mem_read_in1]   = mem_read_in2[7:0];
          data_byte_cache[mem_read_in1+1] = mem_read_in2[15:8];
          data_byte_cache[mem_read_in1+2] = mem_read_in2[23:16];
          data_byte_cache[mem_read_in1+3] = mem_read_in2[31:24];
        end
        default: data_byte_cache[mem_read_in1] = data_byte_cache[mem_read_in1];
      endcase
    end else if (instr_mem_read.op == OP_LTYPE) begin
      casez (instr_mem_read.funct3)
        F3_LB:
        mem_out = {{(XLEN - 8) {data_byte_cache[mem_read_in1][7]}}, data_byte_cache[mem_read_in1]};
        F3_LH:
        mem_out = {
          {(XLEN - 16) {data_byte_cache[mem_read_in1+1][7]}},
          data_byte_cache[mem_read_in1],
          data_byte_cache[mem_read_in1+1]
        };
        F3_LW:
        mem_out = {
          data_byte_cache[mem_read_in1],
          data_byte_cache[mem_read_in1+1],
          data_byte_cache[mem_read_in1+2],
          data_byte_cache[mem_read_in1+3]
        };
        F3_LBU: mem_out = {{(XLEN - 8) {1'b0}}, data_byte_cache[mem_read_in1]};
        F3_LHU:
        mem_out = {
          {(XLEN - 16) {1'b0}}, data_byte_cache[mem_read_in1], data_byte_cache[mem_read_in1+1]
        };
      endcase
    end else data_byte_cache[mem_read_in1] = data_byte_cache[mem_read_in1];
  end

  always_ff @(posedge clk) begin
    mem_w       <= mem_out;  //değişicek
    instr_mem_w <= instr_mem_read;
    pc_mem_w    <= pc_mem_read;
    if (instr_mem_read.op == OP_STYPE) cache_busy[instr_mem_read.rs1] <= 1'b0;
  end

  // ====== Writeback Stage =====================================================
  logic [XLEN-1:0] alu_w, pc_alu_w, mem_w, pc_mem_w;
  instruct_t instr_alu_w, instr_mem_w;
  prf_t prf_alu, prf_mem;

  always_ff @(posedge clk) begin
    prf_alu.pc    <= pc_alu_w;
    prf_alu.rd    <= instr_alu_w.rd;
    prf_alu.value <= alu_w;
    prf_mem.pc    <= pc_mem_w;
    prf_mem.rd    <= instr_mem_w.rd;
    prf_mem.value <= mem_w;
  end





  // ====== Commit Stage ========================================================
  logic [XLEN-1:0] r_wd3;
  logic [4:0] commit_rd;


  always_ff @(negedge clk) begin
    if ((prf_alu.pc == ROB[0].pc) && ROB[0].valid) begin
      r_wd3     <= prf_alu.value;
      commit_rd <= prf_alu.rd;
      for (int i = 0; i < 31; i++) begin
        ROB[i] <= ROB[i+1];
      end
      rob_stack_count <= rob_stack_count - 1;
      ROB[31] <= '0;
    end else if ((prf_mem.pc == ROB[0].pc) && ROB[0].valid) begin
      r_wd3     <= prf_mem.value;
      commit_rd <= prf_mem.rd;
      for (int i = 0; i < 31; i++) begin
        ROB[i] <= ROB[i+1];
      end
      rob_stack_count <= rob_stack_count - 1;
      ROB[31] <= '0;
    end else begin
      r_wd3     <= 0;
      commit_rd <= 0;
    end
  end

  always_ff @(negedge clk) begin
    if (commit_rd == 0) register[0] <= 0;
    else register[commit_rd] <= r_wd3;
    register_busy[commit_rd] <= 1'b0;
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

  function automatic logic [XLEN-1:0] immediate_function(input logic [6:0] op,
                                                         input logic [24:0] imm);
    case (op)
      OP_ITYPE: immediate_function = {{20{imm[24]}}, imm[24:13]};
      OP_STYPE: immediate_function = {{20{imm[24]}}, imm[24:18], imm[4:0]};
      OP_BTYPE: immediate_function = {{19{imm[24]}}, imm[24], imm[0], imm[23:18], imm[4:1], 1'b0};
      OP_LUI:   immediate_function = {imm[24:5], 12'b0};
      OP_AUIPC: immediate_function = {imm[24:5], 12'b0};
      OP_JAL:   immediate_function = {{11{imm[24]}}, imm[24], imm[12:5], imm[13], imm[23:14], 1'b0};
      OP_JALR:  immediate_function = {{11{imm[24]}}, imm[24], imm[12:5], imm[13], imm[23:14], 1'b0};
      default:  immediate_function = '0;
    endcase
  endfunction

  // ====== ALU Functions =======================================================

  function automatic alu_op_t alu_op_e(input logic [6:0] op, input logic [2:0] funct3,
                                       input logic [6:0] funct7);
    case (op)
      OP_ITYPE: begin
        case (funct3)
          F3_ADD:  alu_op_e = ALU_ADD;
          F3_SLL:  alu_op_e = ALU_SLL;
          F3_SLT:  alu_op_e = ALU_SLT;
          F3_SLTU: alu_op_e = ALU_SLTU;
          F3_XOR:  alu_op_e = ALU_XOR;
          F3_OR:   alu_op_e = ALU_OR;
          F3_AND:  alu_op_e = ALU_AND;
          F3_SR: begin
            if (funct7 == F7_SRL) alu_op_e = ALU_SRL;
            else if (funct7 == F7_SRA) alu_op_e = ALU_SRA;
            else alu_op_e = ALU_INVALID;
          end
          default: alu_op_e = ALU_INVALID;
        endcase
      end
      OP_RTYPE: begin
        case (funct3)
          F3_ADD: begin
            if (funct7 == F7_ADD) alu_op_e = ALU_ADD;
            else if (funct7 == F7_SUB) alu_op_e = ALU_SUB;
            else alu_op_e = ALU_INVALID;
          end
          F3_SLL:  alu_op_e = ALU_SLL;
          F3_SLT:  alu_op_e = ALU_SLT;
          F3_SLTU: alu_op_e = ALU_SLTU;
          F3_XOR:  alu_op_e = ALU_XOR;
          F3_OR:   alu_op_e = ALU_OR;
          F3_AND:  alu_op_e = ALU_AND;
          F3_SR: begin
            if (funct7 == F7_SRL) alu_op_e = ALU_SRL;
            else if (funct7 == F7_SRA) alu_op_e = ALU_SRA;
            else alu_op_e = ALU_INVALID;
          end
        endcase
      end
      OP_LTYPE: alu_op_e = ALU_ADD;
      OP_STYPE: alu_op_e = ALU_ADD;
      OP_BTYPE: begin
        case (funct3)
          F3_BEQ:  alu_op_e = ALU_SUB;
          F3_BNE:  alu_op_e = ALU_SUB;
          F3_BLT:  alu_op_e = ALU_SLT;
          F3_BGE:  alu_op_e = ALU_SLT;
          F3_BLTU: alu_op_e = ALU_SLTU;
          F3_BGEU: alu_op_e = ALU_SLTU;
        endcase
      end
      OP_JAL:   alu_op_e = ALU_NONE;
      OP_JALR:  alu_op_e = ALU_ADD;
      OP_LUI:   alu_op_e = ALU_NONE;
      OP_AUIPC: alu_op_e = ALU_ADD;
      default:  alu_op_e = ALU_INVALID;
    endcase
  endfunction

  function automatic logic [XLEN-1:0] alu_result(
      input logic [XLEN-1:0] alu_a, input logic [XLEN-1:0] alu_b, input alu_op_t alu_cd);
    case (alu_cd)
      ALU_ADD:  alu_result = alu_a + alu_b;
      ALU_SUB:  alu_result = alu_a - alu_b;
      ALU_AND:  alu_result = alu_a & alu_b;
      ALU_OR:   alu_result = alu_a | alu_b;
      ALU_XOR:  alu_result = alu_a ^ alu_b;
      ALU_SLL:  alu_result = alu_a << alu_b[4:0];
      ALU_SRL:  alu_result = alu_a >> alu_b[4:0];
      ALU_SRA:  alu_result = $signed(alu_a) >>> alu_b[4:0];
      ALU_SLT:  alu_result = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;
      ALU_SLTU: alu_result = (alu_a < alu_b) ? 32'd1 : 32'd0;
      default:  alu_result = 'x;
    endcase

  endfunction
  // ====== Others ==========================================================

  assign update_o = 0;
  assign pc_o = 0;
  assign instr_o = 0;
  assign reg_addr_o = 0;
  assign reg_data_o = 0;
  assign mem_addr_o = 0;
  assign data_o[0] = 0;
  assign mem_data_o = 0;

endmodule


