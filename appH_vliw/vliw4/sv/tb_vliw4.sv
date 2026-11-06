`timescale 1ns/1ps
// The same kernel, y[i] = a*x[i] + y[i] for 8 elements (a = 3, x[i] = i+1, y[i] = 100 i), scheduled three ways:
//   PROG 0: one operation per bundle (what a scalar machine would do)               -> 75 bundles, 76 ops
//   PROG 1: operations packed into bundles within one iteration                      -> 43 bundles, 76 ops
//   PROG 2: loop unrolled x2 and re-scheduled to fill the slots                      -> 31 bundles, 60 ops
//   PROG 3: exposed-latency demonstration (reads a register before a load lands)     ->  6 bundles,  7 ops
// Expected y[i] = 103 i + 3.  Bundle and op counts are derived by hand from the schedules.
module vliw_harness #(parameter int PROG = 0) (input logic clk, input logic rst_n, output logic done, output integer errors);
  logic [31:0] imem_addr, dmem_addr, dmem_wdata, dmem_rdata, dbg_rdata, bundles, ops;
  logic [127:0] imem_rdata;  logic dmem_we, halted;  logic [3:0] dbg_raddr = 0;
  vliw4 dut (.clk, .rst_n, .imem_addr, .imem_rdata, .dmem_addr, .dmem_wdata, .dmem_we, .dmem_rdata,
             .dbg_raddr, .dbg_rdata, .halted, .stat_bundles(bundles), .stat_ops(ops));

  // ---- assembler (functions) ------------------------------------------------------------------
  function automatic [31:0] op(input [3:0] o, rd, ra, rb, input int imm); op = {o, rd, ra, rb, imm[15:0]}; endfunction
  localparam [31:0] NOP = 32'h0;
  function automatic [31:0] add (input [3:0] rd, ra, rb);         add  = op(4'd1, rd, ra, rb, 0); endfunction
  function automatic [31:0] mul (input [3:0] rd, ra, rb);         mul  = op(4'd3, rd, ra, rb, 0); endfunction
  function automatic [31:0] addi(input [3:0] rd, ra, input int i); addi = op(4'd4, rd, ra, 0, i); endfunction
  function automatic [31:0] ld  (input [3:0] rd, ra, input int i); ld   = op(4'd5, rd, ra, 0, i); endfunction
  function automatic [31:0] st  (input [3:0] ra, input int i, input [3:0] rb); st = op(4'd6, 0, ra, rb, i); endfunction
  function automatic [31:0] bnez(input [3:0] ra, input int target); bnez = op(4'd7, 0, ra, 0, target); endfunction
  function automatic [31:0] halt(); halt = op(4'd15, 0, 0, 0, 0); endfunction
  function automatic [127:0] bundle(input [31:0] s0, s1, s2, s3); bundle = {s3, s2, s1, s0}; endfunction

  logic [127:0] imem [0:63];
  logic [31:0]  dmem [0:63];
  assign imem_rdata = imem[imem_addr[5:0]];
  assign dmem_rdata = dmem[dmem_addr[7:2]];
  always_ff @(posedge clk) if (dmem_we) dmem[dmem_addr[7:2]] <= dmem_wdata;

  initial begin
    for (int i = 0; i < 64; i++) begin imem[i] = bundle(NOP, NOP, NOP, NOP); dmem[i] = 0; end
    for (int i = 0; i < 8; i++) begin dmem[i] = i + 1; dmem[16 + i] = 100 * i; end   // x at byte 0, y at byte 64
    if (PROG != 3) begin
      imem[0] = bundle(addi(2, 0, 64), addi(7, 0, 3), NOP, NOP);                      // r2 = &y, r7 = a
      imem[1] = bundle(addi(8, 0, (PROG == 2) ? 4 : 8), NOP, NOP, NOP);               // r8 = iteration count; r1 = &x = 0
    end
    if (PROG == 0) begin                                                              // one op per bundle
      imem[2]  = bundle(NOP, NOP, ld(3, 1, 0), NOP);
      imem[3]  = bundle(NOP, NOP, ld(4, 2, 0), NOP);
      imem[4]  = bundle(mul(5, 3, 7), NOP, NOP, NOP);                                 // r3 landed (load at 2, +2)
      imem[5]  = bundle(add(6, 5, 4), NOP, NOP, NOP);
      imem[6]  = bundle(NOP, NOP, st(2, 0, 6), NOP);
      imem[7]  = bundle(addi(1, 1, 4), NOP, NOP, NOP);
      imem[8]  = bundle(addi(2, 2, 4), NOP, NOP, NOP);
      imem[9]  = bundle(addi(8, 8, -1), NOP, NOP, NOP);
      imem[10] = bundle(NOP, NOP, NOP, bnez(8, 2));
      imem[11] = bundle(NOP, NOP, NOP, halt());
    end else if (PROG == 1) begin                                                     // packed within an iteration
      imem[2]  = bundle(addi(8, 8, -1), NOP, ld(3, 1, 0), NOP);
      imem[3]  = bundle(addi(1, 1, 4),  NOP, ld(4, 2, 0), NOP);
      imem[4]  = bundle(mul(5, 3, 7), NOP, NOP, NOP);
      imem[5]  = bundle(add(6, 5, 4), NOP, NOP, NOP);
      imem[6]  = bundle(addi(2, 2, 4), NOP, st(2, 0, 6), bnez(8, 2));                 // st reads the OLD r2
      imem[7]  = bundle(NOP, NOP, NOP, halt());
    end else if (PROG == 2) begin                                                     // unrolled x2, software scheduled
      imem[2]  = bundle(addi(8, 8, -1), NOP,         ld(3, 1, 0),  NOP);
      imem[3]  = bundle(NOP,            NOP,         ld(9, 1, 4),  NOP);
      imem[4]  = bundle(mul(5, 3, 7),   addi(1, 1, 8), ld(4, 2, 0), NOP);
      imem[5]  = bundle(mul(11, 9, 7),  NOP,         ld(10, 2, 4), NOP);
      imem[6]  = bundle(add(6, 5, 4),   NOP,         NOP,          NOP);
      imem[7]  = bundle(add(12, 11, 10), NOP,        st(2, 0, 6),  NOP);
      imem[8]  = bundle(addi(2, 2, 8),  NOP,         st(2, 4, 12), bnez(8, 2));
      imem[9]  = bundle(NOP, NOP, NOP, halt());
    end else begin                                                                    // exposed latency
      imem[0] = bundle(addi(3, 0, 77), NOP, NOP, NOP);                                // r3 = 77
      imem[1] = bundle(NOP, NOP, ld(3, 0, 0), NOP);                                   // r3 <- mem[0] = 1, lands 2 bundles later
      imem[2] = bundle(add(4, 3, 0), NOP, NOP, NOP);                                  // too early: still reads 77
      imem[3] = bundle(add(5, 3, 0), NOP, NOP, NOP);                                  // load has landed: reads 1
      imem[4] = bundle(add(6, 5, 0), add(5, 4, 0), NOP, NOP);                         // parallel read: r6 = old r5 (1), r5 = old r4 (77)
      imem[5] = bundle(NOP, NOP, NOP, halt());
    end
  end

  integer e;
  task automatic check_reg(input int r, input int expect_v);
    dbg_raddr = r[3:0]; #1;
    if (dbg_rdata !== expect_v) begin e++; $display("FAIL [PROG %0d] r%0d = %0d, expected %0d", PROG, r, dbg_rdata, expect_v); end
  endtask
  task automatic check_stat(input string name, input [31:0] got, input int expect_v);
    if (got !== expect_v) begin e++; $display("FAIL [PROG %0d] %s = %0d, expected %0d", PROG, name, got, expect_v); end
  endtask

  initial begin
    int t;
    e = 0; done = 0; errors = 0;
    @(posedge rst_n);
    t = 0;
    while (!halted && t < 400) begin @(posedge clk); t++; end
    if (!halted) begin e++; $display("FAIL [PROG %0d] never halted", PROG); end
    @(negedge clk);
    if (PROG != 3) begin
      for (int i = 0; i < 8; i++)
        if (dmem[16 + i] !== 103 * i + 3) begin e++; $display("FAIL [PROG %0d] y[%0d] = %0d, expected %0d", PROG, i, dmem[16 + i], 103 * i + 3); end
      check_stat("bundles", bundles, (PROG == 0) ? 75 : (PROG == 1) ? 43 : 31);
      check_stat("ops",     ops,     (PROG == 2) ? 60 : 76);
    end else begin
      check_reg(4, 77);  check_reg(5, 77);  check_reg(6, 1);  check_reg(3, 1);
      check_stat("bundles", bundles, 6);  check_stat("ops", ops, 7);
    end
    $display("PROG %0d: %0d bundles, %0d ops, IPC = %f", PROG, bundles, ops, ops * 1.0 / bundles);
    errors = e;  done = 1;
  end
endmodule

module tb_vliw4;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic [3:0] d;  integer er0, er1, er2, er3;
  vliw_harness #(.PROG(0)) p0 (.clk, .rst_n, .done(d[0]), .errors(er0));
  vliw_harness #(.PROG(1)) p1 (.clk, .rst_n, .done(d[1]), .errors(er1));
  vliw_harness #(.PROG(2)) p2 (.clk, .rst_n, .done(d[2]), .errors(er2));
  vliw_harness #(.PROG(3)) p3 (.clk, .rst_n, .done(d[3]), .errors(er3));
  initial begin
    repeat (2) @(negedge clk); rst_n = 1;
    wait (d == 4'hF);
    #1;
    if (er0 + er1 + er2 + er3 == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", er0 + er1 + er2 + er3);
    $finish;
  end
endmodule
