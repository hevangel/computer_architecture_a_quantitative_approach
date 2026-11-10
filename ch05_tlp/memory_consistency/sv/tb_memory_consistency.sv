`timescale 1ns/1ps
// Exhaustive litmus tests.  For every program the testbench enumerates ALL schedules (depth-first over the enabled actions, re-running the machine from reset for each schedule) and
// collects the set of final outcomes (under SC the number of schedules is the multinomial coefficient of the program lengths: SB 4!/(2!2!) = 6, SB+fences 6!/(3!3!) = 20, MP 6, MP+fence 5!/(3!2!) = 10, LB 6, IRIW 6!/(1!1!2!2!) = 180, SBF 20, WRC 5!/(1!2!2!) = 30); it must equal the set derived by hand for the model -- no forbidden outcome may ever appear, every allowed outcome must appear.
// x = address 0, y = address 1, all initially 0, every store writes 1.   Outcome = the observed registers, written as a tuple.
//   SB   P0: x=1; r0=y    P1: y=1; r0=x       (P0.r0, P1.r0)    SC {01,10,11} (not 00: some store comes first);  TSO, PSO {00,01,10,11}: each store may still sit in its buffer while the other core loads
//   SB+F same with a FENCE between the store and the load in both cores: {01,10,11} in all three models
//   MP   P0: x=1; y=1     P1: r0=y; r1=x      (P1.r0, P1.r1)    SC, TSO {00,01,11} (not 10: stores drain in order, loads execute in order);  PSO all four (y may drain before x)
//   MP+F a FENCE between P0's two stores: {00,01,11} in all three models
//   LB   P0: r0=x; y=1    P1: r0=y; x=1       (P0.r0, P1.r0)    {00,01,10} in all three (loads execute in order before the later store: 11 needs load reordering, allowed on ARM/POWER)
//   IRIW P0: x=1  P1: y=1  P2: r0=x; r1=y  P3: r0=y; r1=x   (P2.r0,P2.r1,P3.r0,P3.r1)    every outcome except 1010 in all three models (two readers never disagree on the order of two independent
//        writes: memory is multi-copy atomic here)
//   SBF  P0: x=1; r0=x; r1=y   P1: y=1; r0=y; r1=x    (P0.r0,P0.r1,P1.r0,P1.r1)    SC {1011,1110,1111};  TSO, PSO add 1010: each core reads its own store FROM ITS BUFFER (r0 = 1) before it is visible to the other
//   WRC  P0: x=1   P1: r0=x; y=1   P2: r0=y; r1=x    (P1.r0, P2.r0, P2.r1)    every outcome except 110 in all three models (causality: if P1 saw x=1 before writing y, P2 seeing y=1 must see x=1)
module lit_harness #(parameter int MODEL = 0) (output bit done, output int errors, output int runs_total);
  localparam int P = 4, L = 3, NT = 8;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic local_rst = 0;
  wire dut_rst_n = rst_n && !local_rst;
  logic [P*L*8-1:0] prog = '0;
  logic act_valid = 0;  logic [7:0] act = 0;
  wire [P+P*3-1:0] enabled;  wire [P*2*4-1:0] regs;  wire [15:0] memv;
  consistency_model #(.MODEL(MODEL), .P(P), .L(L), .SBD(3)) dut (.clk, .rst_n(dut_rst_n), .prog, .act_valid, .act, .enabled, .regs, .memv);

  function automatic [7:0] I(input int op, input int ad, input int arg);  return {op[1:0], ad[1:0], 4'(arg)};  endfunction
  localparam int ST_ = 1, LD_ = 2, FN_ = 3;
  logic [7:0] pg [0:NT-1][0:P-1][0:L-1];
  int nobs [0:NT-1], obs_c [0:NT-1][0:3], obs_r [0:NT-1][0:3];
  logic [15:0] exp_sc [0:NT-1], exp_tso [0:NT-1], exp_pso [0:NT-1];
  int runs [0:NT-1], nout [0:NT-1];

  function automatic logic [15:0] mask(input int n, input int a, input int b, input int c, input int d);   // one outcome tuple -> its bit in the set
    int code;  code = (n == 2) ? (a*2 + b) : (n == 3) ? (a*4 + b*2 + c) : (a*8 + b*4 + c*2 + d);
    return 16'(1) << code;
  endfunction

  task automatic define_tests();
    for (int t = 0; t < NT; t++) for (int c = 0; c < P; c++) for (int k = 0; k < L; k++) pg[t][c][k] = 8'h00;
    // 0 SB
    pg[0][0][0] = I(ST_,0,1);  pg[0][0][1] = I(LD_,1,0);   pg[0][1][0] = I(ST_,1,1);  pg[0][1][1] = I(LD_,0,0);
    nobs[0] = 2;  obs_c[0][0] = 0; obs_r[0][0] = 0;  obs_c[0][1] = 1; obs_r[0][1] = 0;
    exp_sc[0] = mask(2,0,1,0,0) | mask(2,1,0,0,0) | mask(2,1,1,0,0);   exp_tso[0] = exp_sc[0] | mask(2,0,0,0,0);   exp_pso[0] = exp_tso[0];
    // 1 SB + fences
    pg[1][0][0] = I(ST_,0,1);  pg[1][0][1] = I(FN_,0,0);  pg[1][0][2] = I(LD_,1,0);   pg[1][1][0] = I(ST_,1,1);  pg[1][1][1] = I(FN_,0,0);  pg[1][1][2] = I(LD_,0,0);
    nobs[1] = 2;  obs_c[1][0] = 0; obs_r[1][0] = 0;  obs_c[1][1] = 1; obs_r[1][1] = 0;
    exp_sc[1] = exp_sc[0];  exp_tso[1] = exp_sc[0];  exp_pso[1] = exp_sc[0];
    // 2 MP
    pg[2][0][0] = I(ST_,0,1);  pg[2][0][1] = I(ST_,1,1);   pg[2][1][0] = I(LD_,1,0);  pg[2][1][1] = I(LD_,0,1);
    nobs[2] = 2;  obs_c[2][0] = 1; obs_r[2][0] = 0;  obs_c[2][1] = 1; obs_r[2][1] = 1;
    exp_sc[2] = mask(2,0,0,0,0) | mask(2,0,1,0,0) | mask(2,1,1,0,0);   exp_tso[2] = exp_sc[2];   exp_pso[2] = exp_sc[2] | mask(2,1,0,0,0);
    // 3 MP + fence between the stores
    pg[3][0][0] = I(ST_,0,1);  pg[3][0][1] = I(FN_,0,0);  pg[3][0][2] = I(ST_,1,1);   pg[3][1][0] = I(LD_,1,0);  pg[3][1][1] = I(LD_,0,1);
    nobs[3] = 2;  obs_c[3][0] = 1; obs_r[3][0] = 0;  obs_c[3][1] = 1; obs_r[3][1] = 1;
    exp_sc[3] = exp_sc[2];  exp_tso[3] = exp_sc[2];  exp_pso[3] = exp_sc[2];
    // 4 LB
    pg[4][0][0] = I(LD_,0,0);  pg[4][0][1] = I(ST_,1,1);   pg[4][1][0] = I(LD_,1,0);  pg[4][1][1] = I(ST_,0,1);
    nobs[4] = 2;  obs_c[4][0] = 0; obs_r[4][0] = 0;  obs_c[4][1] = 1; obs_r[4][1] = 0;
    exp_sc[4] = mask(2,0,0,0,0) | mask(2,0,1,0,0) | mask(2,1,0,0,0);   exp_tso[4] = exp_sc[4];   exp_pso[4] = exp_sc[4];
    // 5 IRIW
    pg[5][0][0] = I(ST_,0,1);  pg[5][1][0] = I(ST_,1,1);
    pg[5][2][0] = I(LD_,0,0);  pg[5][2][1] = I(LD_,1,1);   pg[5][3][0] = I(LD_,1,0);  pg[5][3][1] = I(LD_,0,1);
    nobs[5] = 4;  obs_c[5][0] = 2; obs_r[5][0] = 0;  obs_c[5][1] = 2; obs_r[5][1] = 1;  obs_c[5][2] = 3; obs_r[5][2] = 0;  obs_c[5][3] = 3; obs_r[5][3] = 1;
    exp_sc[5] = 16'hFFFF & ~mask(4,1,0,1,0);   exp_tso[5] = exp_sc[5];   exp_pso[5] = exp_sc[5];
    // 6 SB with forwarding
    pg[6][0][0] = I(ST_,0,1);  pg[6][0][1] = I(LD_,0,0);  pg[6][0][2] = I(LD_,1,1);   pg[6][1][0] = I(ST_,1,1);  pg[6][1][1] = I(LD_,1,0);  pg[6][1][2] = I(LD_,0,1);
    nobs[6] = 4;  obs_c[6][0] = 0; obs_r[6][0] = 0;  obs_c[6][1] = 0; obs_r[6][1] = 1;  obs_c[6][2] = 1; obs_r[6][2] = 0;  obs_c[6][3] = 1; obs_r[6][3] = 1;
    exp_sc[6] = mask(4,1,0,1,1) | mask(4,1,1,1,0) | mask(4,1,1,1,1);   exp_tso[6] = exp_sc[6] | mask(4,1,0,1,0);   exp_pso[6] = exp_tso[6];
    // 7 WRC
    pg[7][0][0] = I(ST_,0,1);   pg[7][1][0] = I(LD_,0,0);  pg[7][1][1] = I(ST_,1,1);   pg[7][2][0] = I(LD_,1,0);  pg[7][2][1] = I(LD_,0,1);
    nobs[7] = 3;  obs_c[7][0] = 1; obs_r[7][0] = 0;  obs_c[7][1] = 2; obs_r[7][1] = 0;  obs_c[7][2] = 2; obs_r[7][2] = 1;
    exp_sc[7] = 16'h00FF & ~mask(3,1,1,0,0);   exp_tso[7] = exp_sc[7];   exp_pso[7] = exp_sc[7];
  endtask

  int path [0:63], nch [0:63];
  int depth;
  logic [15:0] seen;
  task automatic one_run(input int t);          // run the machine once, following `path`; record the number of choices at each step and the final outcome
    int d, cnt, want, pick, code, val;  bit fin;
    @(negedge clk);  local_rst = 1;  act_valid = 0;  @(negedge clk);  @(negedge clk);  local_rst = 0;
    for (int c = 0; c < P; c++) for (int k = 0; k < L; k++) prog[(c*L + k)*8 +: 8] = pg[t][c][k];
    d = 0;  fin = 0;
    while (!fin) begin
      @(negedge clk);  act_valid = 0;  #1;
      cnt = 0;  for (int a = 0; a < P + P*3; a++) if (enabled[a]) cnt++;
      if (cnt == 0) fin = 1;
      else begin
        nch[d] = cnt;
        want = path[d];  pick = -1;  cnt = 0;
        for (int a = 0; a < P + P*3; a++) if (enabled[a]) begin if (cnt == want) pick = a; cnt++; end
        act_valid = 1;  act = 8'(pick);
        d++;
      end
    end
    depth = d;
    code = 0;
    for (int i = 0; i < nobs[t]; i++) begin
      val = int'(regs[(obs_c[t][i]*2 + obs_r[t][i])*4 +: 4]);
      if (val > 1) begin errors++; $display("FAIL [model %0d test %0d] register value %0d", MODEL, t, val); end
      code = code * 2 + (val & 1);
    end
    seen[code] = 1'b1;
  endtask

  initial begin
    int t, d, k;  bit more;  logic [15:0] want_mask;
    done = 0; errors = 0; runs_total = 0;
    define_tests();
    repeat (3) @(negedge clk);  rst_n = 1;  repeat (2) @(negedge clk);
    for (t = 0; t < NT; t++) begin
      for (int i = 0; i < 64; i++) begin path[i] = 0; nch[i] = 0; end
      seen = '0;  runs[t] = 0;  more = 1;
      while (more) begin
        one_run(t);
        runs[t]++;
        // next schedule: odometer over the choices (deepest position that still has an unused alternative)
        more = 0;
        for (k = depth - 1; k >= 0 && !more; k--) begin
          if (path[k] + 1 < nch[k]) begin
            path[k]++;  more = 1;
            for (int j = k + 1; j < 64; j++) path[j] = 0;
          end
        end
      end
      want_mask = (MODEL == 0) ? exp_sc[t] : (MODEL == 1) ? exp_tso[t] : exp_pso[t];
      nout[t] = 0;  for (int i = 0; i < 16; i++) if (seen[i]) nout[t]++;
      if (seen !== want_mask) begin errors++; $display("FAIL [model %0d test %0d] outcomes seen %b, expected %b (after %0d schedules)", MODEL, t, seen, want_mask, runs[t]); end
      if (MODEL == 0) begin                                    // under SC every schedule is an interleaving of the programs: a multinomial coefficient
        int sc_runs [0:NT-1];
        sc_runs[0] = 6;  sc_runs[1] = 20;  sc_runs[2] = 6;  sc_runs[3] = 10;  sc_runs[4] = 6;  sc_runs[5] = 180;  sc_runs[6] = 20;  sc_runs[7] = 30;
        if (runs[t] != sc_runs[t]) begin errors++; $display("FAIL [SC test %0d] %0d schedules, expected %0d (a multinomial coefficient)", t, runs[t], sc_runs[t]); end
      end
      runs_total += runs[t];
    end
    done = 1;
  end
endmodule

module tb_memory_consistency;
  wire d0, d1, d2;  int e0, e1, e2, n0, n1, n2;
  lit_harness #(.MODEL(0)) sc  (.done(d0), .errors(e0), .runs_total(n0));
  lit_harness #(.MODEL(1)) tso (.done(d1), .errors(e1), .runs_total(n1));
  lit_harness #(.MODEL(2)) pso (.done(d2), .errors(e2), .runs_total(n2));
  string names [0:7];
  int errors;
  initial begin
    names[0] = "SB";  names[1] = "SB+fences";  names[2] = "MP";  names[3] = "MP+fence";  names[4] = "LB";  names[5] = "IRIW";  names[6] = "SB+forwarding";  names[7] = "WRC";
    wait (d0 && d1 && d2);
    errors = e0 + e1 + e2;
    $display("schedules explored: SC %0d, TSO %0d, PSO %0d", n0, n1, n2);
    $display("test            schedules (SC/TSO/PSO)    distinct outcomes (SC/TSO/PSO)");
    for (int t = 0; t < 8; t++)
      $display("%-14s  %0d / %0d / %0d              %0d / %0d / %0d", names[t], sc.runs[t], tso.runs[t], pso.runs[t], sc.nout[t], tso.nout[t], pso.nout[t]);
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
