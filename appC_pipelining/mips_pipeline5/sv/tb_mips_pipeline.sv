`timescale 1ns/1ps
// One harness per ISA flavor: the same logical program is assembled with DLX/MIPS32 encodings (XLEN=32)
// and with MIPS64 encodings (XLEN=64), run to BREAK, and checked against hand-derived results.
module mips_harness #(parameter int XLEN = 32) (input logic clk, input logic rst_n, output logic done, output integer errors);
  localparam bit IS64 = (XLEN == 64);
  localparam int WB   = XLEN / 8;                          // bytes per data word

  logic [31:0] imem_addr, imem_rdata;
  logic [XLEN-1:0] dmem_addr, dmem_wdata, dmem_rdata, dbg_rdata;
  logic dmem_we, halted;  logic [4:0] dbg_raddr = 0;
  logic [31:0] cycles, retired, lstalls, bstalls, flushes;

  mips_pipeline #(.XLEN(XLEN)) dut (.clk, .rst_n, .imem_addr, .imem_rdata, .dmem_addr, .dmem_wdata, .dmem_we, .dmem_rdata,
                                    .dbg_raddr, .dbg_rdata, .halted, .stat_cycles(cycles), .stat_retired(retired),
                                    .stat_load_stalls(lstalls), .stat_branch_stalls(bstalls), .stat_flushes(flushes));

  // ---- assembler (functions) --------------------------------------------------------------------
  function automatic [31:0] r_type(input [5:0] f, input [4:0] rs, rt, rd, sh); r_type = {6'h00, rs, rt, rd, sh, f}; endfunction
  function automatic [31:0] i_type(input [5:0] op, input [4:0] rs, rt, input [15:0] imm); i_type = {op, rs, rt, imm}; endfunction
  function automatic [31:0] add (input [4:0] rd, rs, rt);  add  = r_type(IS64 ? 6'h2D : 6'h20, rs, rt, rd, 0); endfunction   // DADDU / ADD
  function automatic [31:0] sub (input [4:0] rd, rs, rt);  sub  = r_type(IS64 ? 6'h2F : 6'h22, rs, rt, rd, 0); endfunction   // DSUBU / SUB
  function automatic [31:0] slt (input [4:0] rd, rs, rt);  slt  = r_type(6'h2A, rs, rt, rd, 0); endfunction
  function automatic [31:0] sll (input [4:0] rd, rt, input [4:0] sh); sll = r_type(IS64 ? 6'h38 : 6'h00, 0, rt, rd, sh); endfunction  // DSLL / SLL
  function automatic [31:0] jr  (input [4:0] rs);          jr   = r_type(6'h08, rs, 0, 0, 0); endfunction
  function automatic [31:0] brk ();                         brk  = r_type(6'h0D, 0, 0, 0, 0); endfunction
  function automatic [31:0] addi(input [4:0] rt, rs, input int imm); addi = i_type(IS64 ? 6'h19 : 6'h08, rs, rt, imm[15:0]); endfunction  // DADDIU / ADDI
  function automatic [31:0] ori (input [4:0] rt, rs, input [15:0] imm); ori = i_type(6'h0D, rs, rt, imm); endfunction
  function automatic [31:0] lui (input [4:0] rt, input [15:0] imm);     lui = i_type(6'h0F, 0, rt, imm); endfunction
  function automatic [31:0] lw  (input [4:0] rt, input int off, input [4:0] rs); lw = i_type(IS64 ? 6'h37 : 6'h23, rs, rt, off[15:0]); endfunction   // LD / LW
  function automatic [31:0] sw  (input [4:0] rt, input int off, input [4:0] rs); sw = i_type(IS64 ? 6'h3F : 6'h2B, rs, rt, off[15:0]); endfunction   // SD / SW
  function automatic [31:0] beq (input [4:0] rs, rt, input int off);  beq = i_type(6'h04, rs, rt, off[15:0]); endfunction   // off in words from PC+4
  function automatic [31:0] bne (input [4:0] rs, rt, input int off);  bne = i_type(6'h05, rs, rt, off[15:0]); endfunction
  function automatic [31:0] jal (input int word);           jal  = {6'h03, 26'(word)}; endfunction

  // ---- memories ---------------------------------------------------------------------------------
  logic [31:0] imem [0:63];
  logic [XLEN-1:0] dmem [0:63];
  assign imem_rdata = (imem_addr[31:8] == 0) ? imem[imem_addr[7:2]] : 32'd0;
  assign dmem_rdata = dmem[(dmem_addr >> $clog2(WB)) & 63];
  always_ff @(posedge clk) if (dmem_we) dmem[(dmem_addr >> $clog2(WB)) & 63] <= dmem_wdata;

  initial begin
    for (int i = 0; i < 64; i++) begin imem[i] = 0; dmem[i] = 0; end
    imem[0]  = addi(1, 0, 5);            // $1 = 5
    imem[1]  = addi(2, 0, 7);            // $2 = 7
    imem[2]  = add (3, 1, 2);            // $3 = 12            forward from MEM/WB and EX/MEM
    imem[3]  = sub (4, 3, 1);            // $4 = 7
    imem[4]  = sw  (3, 0, 0);            // mem[0] = 12
    imem[5]  = lw  (5, 0, 0);            // $5 = 12
    imem[6]  = add (6, 5, 5);            // $6 = 24            load-use stall (1)
    imem[7]  = beq (6, 6, 1);            // taken -> word 9    operand produced by the instruction just ahead: branch stall (1)
    imem[8]  = addi(7, 0, 99);           // wrong path
    imem[9]  = addi(8, 0, 1);            // $8 = 1
    imem[10] = addi(10, 0, 10);          // $10 = 10
    imem[11] = addi(11, 0, 0);           // $11 = 0
    imem[12] = add (11, 11, 10);         // loop: sum += i
    imem[13] = addi(10, 10, -1);         //       i--
    imem[14] = bne (10, 0, -3);          //       BNEZ: branch stall every iteration (operand from the addi ahead), taken 9 times
    imem[15] = sw  (11, WB, 0);          // mem[1] = 55
    imem[16] = jal (18);                 // $31 = 68, jump to word 18
    imem[17] = addi(13, 0, 77);          // wrong path
    imem[18] = slt (14, 0, 11);          // $14 = 1
    imem[19] = lui (15, 16'h1234);       // $15 = 0x12340000
    imem[20] = ori (16, 15, 16'h5678);   // $16 = 0x12345678
    imem[21] = sll (17, 14, 4);          // $17 = 16           (DSLL for MIPS64)
    imem[22] = lw  (20, 0, 0);           // $20 = 12
    imem[23] = addi(21, 0, 1);           // $21 = 1
    imem[24] = beq (20, 3, 1);           // taken -> word 26   operand is a load now in MEM: branch stall (1)
    imem[25] = addi(22, 0, 1);           // wrong path
    imem[26] = addi(18, 0, 116);         // $18 = byte address of word 29
    imem[27] = jr  (18);                 // JR: branch stall (1), taken
    imem[28] = addi(19, 0, 55);          // wrong path
    imem[29] = brk ();
  end

  integer e;
  task automatic check_reg(input int r, input logic [63:0] expect_v);
    dbg_raddr = r[4:0]; #1;
    if (dbg_rdata !== expect_v[XLEN-1:0]) begin e++; $display("FAIL [XLEN=%0d] $%0d = %h, expected %h", XLEN, r, dbg_rdata, expect_v[XLEN-1:0]); end
  endtask
  task automatic check_stat(input string name, input [31:0] got, input int expect_v);
    if (got !== expect_v) begin e++; $display("FAIL [XLEN=%0d] %s = %0d, expected %0d", XLEN, name, got, expect_v); end
  endtask

  initial begin
    int t;
    e = 0; done = 0; errors = 0;
    @(posedge rst_n);
    t = 0;
    while (!halted && t < 500) begin @(posedge clk); t++; end
    if (!halted) begin e++; $display("FAIL [XLEN=%0d] never halted", XLEN); end
    @(negedge clk);
    check_reg(1, 5);  check_reg(2, 7);  check_reg(3, 12);  check_reg(4, 7);  check_reg(5, 12);  check_reg(6, 24);
    check_reg(7, 0);                       // wrong-path writes must be squashed
    check_reg(8, 1);  check_reg(10, 0);  check_reg(11, 55);  check_reg(13, 0);  check_reg(14, 1);
    check_reg(15, 64'h1234_0000);  check_reg(16, 64'h1234_5678);  check_reg(17, 16);  check_reg(18, 116);  check_reg(19, 0);
    check_reg(20, 12);  check_reg(21, 1);  check_reg(22, 0);  check_reg(31, 68);
    if (dmem[0] !== 12 || dmem[1] !== 55) begin e++; $display("FAIL [XLEN=%0d] memory %0d %0d", XLEN, dmem[0], dmem[1]); end
    check_stat("retired", retired, 53);
    check_stat("load-use stalls", lstalls, 1);
    check_stat("branch-operand stalls", bstalls, 13);       // beq@7 (1) + bne x10 (10) + beq@24 load-in-MEM (1) + jr (1)
    check_stat("taken transfers", flushes, 13);             // beq@7 + bne x9 + jal + beq@24 + jr
    // cycles = instructions + 4 (fill) + load stalls + branch stalls + 1 per taken transfer
    check_stat("cycles", cycles, 53 + 4 + 1 + 13 + 13);
    $display("XLEN=%0d: cycles=%0d retired=%0d CPI=%f", XLEN, cycles, retired, cycles * 1.0 / retired);
    errors = e;  done = 1;
  end
endmodule

module tb_mips_pipeline;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic done32, done64;  integer err32, err64;
  mips_harness #(.XLEN(32)) dlx   (.clk, .rst_n, .done(done32), .errors(err32));
  mips_harness #(.XLEN(64)) mips64(.clk, .rst_n, .done(done64), .errors(err64));
  initial begin
    repeat (2) @(negedge clk);  rst_n = 1;
    wait (done32 && done64);
    #1;
    if (err32 + err64 == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", err32 + err64);
    $finish;
  end
endmodule
