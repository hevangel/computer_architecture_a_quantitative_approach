`timescale 1ns/1ps
module tb_rv32i_pipeline;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata, dbg_rdata;
  logic dmem_we, halted;  logic [4:0] dbg_raddr = 0;
  logic [31:0] cycles, retired, stalls, flushes;

  rv32i_pipeline dut (.clk, .rst_n, .imem_addr, .imem_rdata, .dmem_addr, .dmem_wdata, .dmem_we, .dmem_rdata,
                      .dbg_raddr, .dbg_rdata, .halted,
                      .stat_cycles(cycles), .stat_retired(retired), .stat_load_stalls(stalls), .stat_flushes(flushes));

  // ---- tiny RV32I assembler (functions) -------------------------------------
  function automatic [31:0] r_type(input [6:0] f7, input [4:0] rs2, rs1, input [2:0] f3, input [4:0] rd);
    r_type = {f7, rs2, rs1, f3, rd, 7'b0110011}; endfunction
  function automatic [31:0] i_type(input [11:0] imm, input [4:0] rs1, input [2:0] f3, input [4:0] rd, input [6:0] op);
    i_type = {imm, rs1, f3, rd, op}; endfunction
  function automatic [31:0] s_type(input [11:0] imm, input [4:0] rs2, rs1);
    s_type = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011}; endfunction
  function automatic [31:0] b_type(input [12:0] imm, input [4:0] rs2, rs1, input [2:0] f3);
    b_type = {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], 7'b1100011}; endfunction
  function automatic [31:0] j_type(input [20:0] imm, input [4:0] rd);
    j_type = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111}; endfunction

  function automatic [31:0] addi(input [4:0] rd, rs1, input int imm); addi = i_type(imm[11:0], rs1, 3'b000, rd, 7'b0010011); endfunction
  function automatic [31:0] add (input [4:0] rd, rs1, rs2); add = r_type(7'b0000000, rs2, rs1, 3'b000, rd); endfunction
  function automatic [31:0] sub (input [4:0] rd, rs1, rs2); sub = r_type(7'b0100000, rs2, rs1, 3'b000, rd); endfunction
  function automatic [31:0] slt (input [4:0] rd, rs1, rs2); slt = r_type(7'b0000000, rs2, rs1, 3'b010, rd); endfunction
  function automatic [31:0] slli(input [4:0] rd, rs1, input int sh); slli = i_type(sh[11:0], rs1, 3'b001, rd, 7'b0010011); endfunction
  function automatic [31:0] lw  (input [4:0] rd, input int off, input [4:0] rs1); lw = i_type(off[11:0], rs1, 3'b010, rd, 7'b0000011); endfunction
  function automatic [31:0] sw  (input [4:0] rs2, input int off, input [4:0] rs1); sw = s_type(off[11:0], rs2, rs1); endfunction
  function automatic [31:0] beq (input [4:0] rs1, rs2, input int off); beq = b_type(off[12:0], rs2, rs1, 3'b000); endfunction
  function automatic [31:0] bne (input [4:0] rs1, rs2, input int off); bne = b_type(off[12:0], rs2, rs1, 3'b001); endfunction
  function automatic [31:0] jal (input [4:0] rd, input int off); jal = j_type(off[20:0], rd); endfunction
  function automatic [31:0] jalr(input [4:0] rd, rs1, input int off); jalr = i_type(off[11:0], rs1, 3'b000, rd, 7'b1100111); endfunction
  function automatic [31:0] lui (input [4:0] rd, input [19:0] imm); lui = {imm, rd, 7'b0110111}; endfunction
  localparam [31:0] EBREAK = 32'h0010_0073;

  // ---- memories -------------------------------------------------------------
  logic [31:0] imem [0:63];
  logic [31:0] dmem [0:63];
  assign imem_rdata = (imem_addr[31:8] == 0) ? imem[imem_addr[7:2]] : 32'd0;
  assign dmem_rdata = dmem[dmem_addr[7:2]];
  always_ff @(posedge clk) if (dmem_we) dmem[dmem_addr[7:2]] <= dmem_wdata;

  initial begin
    for (int i = 0; i < 64; i++) begin imem[i] = 0; dmem[i] = 0; end
    imem[0]  = addi(1, 0, 5);            // x1 = 5
    imem[1]  = addi(2, 0, 7);            // x2 = 7
    imem[2]  = add (3, 1, 2);            // x3 = 12            (forward from MEM/WB)
    imem[3]  = sub (4, 3, 1);            // x4 = 7             (forward from EX/MEM, distance 1)
    imem[4]  = sw  (3, 0, 0);            // mem[0] = 12
    imem[5]  = lw  (5, 0, 0);            // x5 = 12
    imem[6]  = add (6, 5, 5);            // x6 = 24            (load-use: 1 stall)
    imem[7]  = beq (6, 6, 8);            // taken -> word 9    (2 flushed instructions)
    imem[8]  = addi(7, 0, 99);           // wrong path: must not execute
    imem[9]  = addi(8, 0, 1);            // x8 = 1
    imem[10] = addi(10, 0, 10);          // x10 = 10 (loop counter)
    imem[11] = addi(11, 0, 0);           // x11 = 0  (sum)
    imem[12] = add (11, 11, 10);         // loop: sum += i
    imem[13] = addi(10, 10, -1);         //       i--
    imem[14] = bne (10, 0, -8);          //       until i == 0   (taken 9 times)
    imem[15] = sw  (11, 4, 0);           // mem[1] = 55
    imem[16] = jal (12, 8);              // x12 = 68, jump to word 18
    imem[17] = addi(13, 0, 77);          // wrong path
    imem[18] = slt (14, 0, 11);          // x14 = (0 < 55) = 1
    imem[19] = lui (15, 20'h12345);      // x15 = 0x12345000
    imem[20] = addi(16, 15, 12'h678);    // x16 = 0x12345678
    imem[21] = slli(17, 14, 4);          // x17 = 16
    imem[22] = jalr(18, 0, 96);          // x18 = 92, jump to byte 96 (word 24)
    imem[23] = addi(19, 0, 55);          // wrong path
    imem[24] = EBREAK;
  end

  int errors = 0;
  task automatic check_reg(input int r, input [31:0] expect_v);
    dbg_raddr = r[4:0]; #1;
    if (dbg_rdata !== expect_v) begin errors++; $display("FAIL x%0d = %h, expected %h", r, dbg_rdata, expect_v); end
  endtask
  task automatic check_stat(input string name, input [31:0] got, input [31:0] expect_v);
    if (got !== expect_v) begin errors++; $display("FAIL %s = %0d, expected %0d", name, got, expect_v); end
  endtask

  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1;
    begin : run
      int t;
      t = 0;
      while (!halted && t < 500) begin @(posedge clk); t++; end
      if (!halted) begin errors++; $display("FAIL: program never halted"); end
    end
    @(negedge clk);
    check_reg(1, 5);  check_reg(2, 7);  check_reg(3, 12); check_reg(4, 7);  check_reg(5, 12); check_reg(6, 24);
    check_reg(7, 0);   // wrong-path write must be squashed
    check_reg(8, 1);  check_reg(10, 0); check_reg(11, 55); check_reg(12, 68);
    check_reg(13, 0);  // wrong-path write must be squashed
    check_reg(14, 1); check_reg(15, 32'h12345000); check_reg(16, 32'h12345678); check_reg(17, 16);
    check_reg(18, 92); check_reg(19, 0);
    if (dmem[0] !== 12 || dmem[1] !== 55) begin errors++; $display("FAIL memory: %0d %0d", dmem[0], dmem[1]); end
    check_stat("retired", retired, 49);
    check_stat("load stalls", stalls, 1);
    check_stat("taken branches/jumps", flushes, 12);
    // pipeline CPI model: cycles = instructions + 4 (fill) + load-use stalls + 2 * taken transfers
    check_stat("cycles", cycles, 49 + 4 + 1 + 2*12);
    $display("cycles=%0d retired=%0d CPI=%f", cycles, retired, cycles * 1.0 / retired);
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
