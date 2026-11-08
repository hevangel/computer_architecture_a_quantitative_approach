`timescale 1ns/1ps
// Latencies: LD 6, ADD 4, MUL 7 (ST 1).  vl elements per vector, one element per cycle per unit.
//
// (1) DAXPY  LV V1,[X]; MULVS V2,V1,5; LV V3,[Y]; ADDV V4,V2,V3; SV V4,[Y]  with the cycle numbers derived BY HAND (first issue = cycle 0,
//     d = issue cycle, s = cycle the first element enters its unit, "idle" = first cycle with nothing in flight):
//       vl = 16 chained   : d 0 1 16 17 32   s 1 7 17 23 33   idle 49        (LV V3 must wait for the single memory pipe: 3 convoys of 16 cycles)
//       vl = 16 unchained : d 0 1 16 17 32   s 1 22 17 44 63  idle 79        (each consumer waits until the whole source vector has been written)
//       vl =  8 chained   : d 0 1 8 9 16     s 1 7 9 15 19    idle 27
//       vl =  8 unchained : d 0 1 8 9 16     s 1 14 9 28 39   idle 47
//       vl =  1           : d 0 1 2 3 4      s 1 7 3 14 18    idle 19        (chaining makes no difference for one element)
// (2) random programs: the start times are compared with a closed-form schedule (max() of the issue, unit, RAW, WAW and WAR constraints), and the final
//     register and memory contents with a sequential interpreter.
module vc_harness #(parameter bit CHAIN = 1'b1) (output bit done, output int errors, output int tot_daxpy16, output int tot_random);
  localparam int MAXI = 16, LD_L = 6, ADD_L = 4, MUL_L = 7;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic ld_we = 0, mem_we = 0, ins_valid = 0;
  logic [2:0] ld_reg = 0, rd_reg = 0, ins_op = 0, ins_vd = 0, ins_vs1 = 0, ins_vs2 = 0;
  logic [3:0] ld_idx = 0, rd_idx = 0;
  logic [31:0] ld_data = 0, mem_wdata = 0;  wire [31:0] rd_data, mem_rdata;
  logic [7:0] mem_addr = 0, mem_raddr = 0, ins_base = 0, ins_tag = 0;
  logic [4:0] vl = 1;
  logic signed [31:0] ins_scalar = 0;
  wire ins_ready, idle;  wire [2:0] st_valid;  wire [23:0] st_tag;

  vector_chain #(.CHAIN(CHAIN)) dut (.clk, .rst_n, .ld_we, .ld_reg, .ld_idx, .ld_data, .rd_reg, .rd_idx, .rd_data, .mem_we, .mem_addr, .mem_wdata,
      .mem_raddr, .mem_rdata, .vl, .ins_valid, .ins_op, .ins_vd, .ins_vs1, .ins_vs2, .ins_scalar, .ins_base, .ins_tag, .ins_ready, .st_valid, .st_tag, .idle);

  // ---- program and bookkeeping ----
  int p_op [0:MAXI-1], p_vd [0:MAXI-1], p_vs1 [0:MAXI-1], p_vs2 [0:MAXI-1], p_sc [0:MAXI-1], p_base [0:MAXI-1];
  int p_n, p_vl;
  int d_log [0:MAXI-1], s_log [0:MAXI-1], e_d [0:MAXI-1], e_s [0:MAXI-1];
  int h_d [0:MAXI-1], h_s [0:MAXI-1];  int h_idle;                  // hand-derived schedule of the directed test
  int e_idle, idle_cyc, acc, cyc;
  bit collecting;
  logic signed [31:0] sreg [0:127], smem [0:255];
  logic [31:0] dseed, seed;

  always @(posedge clk) begin
    if (collecting) begin
      if (idle && acc == p_n && idle_cyc < 0) idle_cyc = cyc;
      if (ins_valid && ins_ready) begin d_log[ins_tag] = cyc; acc++; end
      for (int u = 0; u < 3; u++) if (st_valid[u]) s_log[st_tag[8*u +: 8]] = cyc;
    end
    cyc++;
  end

  function automatic int unit_of(input int op);  return (op == 0 || op == 1) ? 0 : ((op == 2 || op == 3 || op == 6) ? 1 : 2);  endfunction
  function automatic int lat_of(input int op);   return op == 0 ? LD_L : (op == 1 ? 1 : (unit_of(op) == 1 ? ADD_L : MUL_L));  endfunction
  function automatic bit has_dst(input int op);  return op != 1;  endfunction
  function automatic bit reads(input int j, input int r);
    return (p_op[j] != 0 && p_vs1[j] == r) || ((p_op[j] == 2 || p_op[j] == 3 || p_op[j] == 4) && p_vs2[j] == r);
  endfunction
  function automatic int imax(input int a, input int b);  return a > b ? a : b;  endfunction

  // closed-form schedule
  task automatic model();
    int d, s, last;
    e_idle = 0;
    for (int k = 0; k < p_n; k++) begin
      d = (k == 0) ? 0 : e_d[k-1] + 1;
      for (int j = 0; j < k; j++) if (unit_of(p_op[j]) == unit_of(p_op[k])) d = imax(d, e_s[j] + p_vl - 1);                 // the unit is free
      if (has_dst(p_op[k]))
        for (int j = 0; j < k; j++) begin
          if (has_dst(p_op[j]) && p_vd[j] == p_vd[k]) d = imax(d, e_s[j] + p_vl - 1 + lat_of(p_op[j]));                     // WAW: earlier writer finished
          if (reads(j, p_vd[k])) d = imax(d, e_s[j] + p_vl);                                                                 // WAR: earlier readers finished
        end
      s = d + 1;
      for (int w = 0; w < 2; w++) begin                                                                                       // RAW on each source register
        int r, ok;
        ok = (w == 0) ? (p_op[k] != 0) : (p_op[k] == 2 || p_op[k] == 3 || p_op[k] == 4);
        r  = (w == 0) ? p_vs1[k] : p_vs2[k];
        if (ok) begin
          last = -1;
          for (int j = 0; j < k; j++) if (has_dst(p_op[j]) && p_vd[j] == r) last = j;
          if (last >= 0) s = imax(s, CHAIN ? e_s[last] + lat_of(p_op[last]) : e_s[last] + p_vl - 1 + lat_of(p_op[last]));
        end
      end
      e_d[k] = d;  e_s[k] = s;
      e_idle = imax(e_idle, has_dst(p_op[k]) ? s + p_vl - 1 + lat_of(p_op[k]) : s + p_vl);
    end
  endtask

  // sequential interpreter on the shadow copies
  task automatic interpret();
    logic signed [31:0] a, b, y;
    for (int k = 0; k < p_n; k++)
      for (int i = 0; i < p_vl; i++) begin
        a = sreg[p_vs1[k]*16 + i];  b = sreg[p_vs2[k]*16 + i];
        case (p_op[k])
          0: sreg[p_vd[k]*16 + i] = smem[(p_base[k] + i) & 255];
          1: smem[(p_base[k] + i) & 255] = a;
          2: begin y = a + b;  sreg[p_vd[k]*16 + i] = y; end
          3: begin y = a - b;  sreg[p_vd[k]*16 + i] = y; end
          4: begin y = a * b;  sreg[p_vd[k]*16 + i] = y; end
          5: begin b = p_sc[k];  y = a * b;  sreg[p_vd[k]*16 + i] = y; end
          default: begin b = p_sc[k];  y = a + b;  sreg[p_vd[k]*16 + i] = y; end
        endcase
      end
  endtask

  task automatic setup();           // random register and memory contents, loaded through the setup ports
    for (int r = 0; r < 8; r++)
      for (int i = 0; i < 16; i++) begin
        dseed = dseed * 32'd1664525 + 32'd1013904223;  sreg[r*16 + i] = dseed;
        @(negedge clk);  ld_we = 1;  ld_reg = r;  ld_idx = i;  ld_data = dseed;
      end
    for (int a = 0; a < 256; a++) begin
      dseed = dseed * 32'd1664525 + 32'd1013904223;  smem[a] = dseed;
      @(negedge clk);  mem_we = 1;  mem_addr = a;  mem_wdata = dseed;
    end
    @(negedge clk);  ld_we = 0;  mem_we = 0;
  endtask

  task automatic exec_prog(input string what);
    int timeout;
    acc = 0;  idle_cyc = -1;  collecting = 1;
    @(negedge clk);  vl = p_vl;
    for (int k = 0; k < p_n; k++) begin
      @(negedge clk);
      ins_valid = 1;  ins_op = p_op[k];  ins_vd = p_vd[k];  ins_vs1 = p_vs1[k];  ins_vs2 = p_vs2[k];  ins_scalar = p_sc[k];  ins_base = p_base[k];  ins_tag = k;
      #1;
      timeout = 0;
      while (!ins_ready && timeout < 3000) begin @(negedge clk); #1; timeout++; end
      if (timeout >= 3000) begin errors++; $display("FAIL [%s] instruction %0d was never accepted", what, k); end
    end
    @(negedge clk);  ins_valid = 0;
    timeout = 0;
    while (idle_cyc < 0 && timeout < 3000) begin @(negedge clk); timeout++; end
    collecting = 0;
    if (idle_cyc < 0) begin errors++; $display("FAIL [%s] machine never became idle", what); end
    @(negedge clk);
  endtask

  task automatic check(input string what, input bit use_hand);
    int t0, bad;
    t0 = d_log[0];  bad = 0;
    for (int k = 0; k < p_n; k++) begin
      if (d_log[k] - t0 != (use_hand ? h_d[k] : e_d[k])) begin bad++; $display("FAIL [%s] instr %0d issue cycle %0d expected %0d", what, k, d_log[k] - t0, use_hand ? h_d[k] : e_d[k]); end
      if (s_log[k] - t0 != (use_hand ? h_s[k] : e_s[k])) begin bad++; $display("FAIL [%s] instr %0d start cycle %0d expected %0d", what, k, s_log[k] - t0, use_hand ? h_s[k] : e_s[k]); end
    end
    if (idle_cyc - t0 != (use_hand ? h_idle : e_idle)) begin bad++; $display("FAIL [%s] idle at cycle %0d expected %0d", what, idle_cyc - t0, use_hand ? h_idle : e_idle); end
    // data
    for (int r = 0; r < 8; r++)
      for (int i = 0; i < 16; i++) begin
        rd_reg = r;  rd_idx = i;  #1;
        if (rd_data !== sreg[r*16 + i]) begin bad++; if (bad < 6) $display("FAIL [%s] V%0d[%0d] = %h expected %h", what, r, i, rd_data, sreg[r*16 + i]); end
      end
    for (int a = 0; a < 256; a++) begin
      mem_raddr = a;  #1;
      if (mem_rdata !== smem[a]) begin bad++; if (bad < 6) $display("FAIL [%s] mem[%0d] = %h expected %h", what, a, mem_rdata, smem[a]); end
    end
    errors += (bad > 0) ? 1 : 0;
  endtask

  task automatic daxpy(input int n);
    p_n = 5;  p_vl = n;
    p_op[0] = 0;  p_vd[0] = 1;  p_vs1[0] = 0;  p_vs2[0] = 0;  p_sc[0] = 0;  p_base[0] = 0;      // LV    V1,[0]       X
    p_op[1] = 5;  p_vd[1] = 2;  p_vs1[1] = 1;  p_vs2[1] = 0;  p_sc[1] = 5;  p_base[1] = 0;      // MULVS V2,V1,5
    p_op[2] = 0;  p_vd[2] = 3;  p_vs1[2] = 0;  p_vs2[2] = 0;  p_sc[2] = 0;  p_base[2] = 16;     // LV    V3,[16]      Y
    p_op[3] = 2;  p_vd[3] = 4;  p_vs1[3] = 2;  p_vs2[3] = 3;  p_sc[3] = 0;  p_base[3] = 0;      // ADDV  V4,V2,V3
    p_op[4] = 1;  p_vd[4] = 0;  p_vs1[4] = 4;  p_vs2[4] = 0;  p_sc[4] = 0;  p_base[4] = 16;     // SV    V4,[16]
    if (n == 16) begin
      h_d[0]=0; h_d[1]=1; h_d[2]=16; h_d[3]=17; h_d[4]=32;
      if (CHAIN) begin h_s[0]=1; h_s[1]=7;  h_s[2]=17; h_s[3]=23; h_s[4]=33; h_idle = 49; end
      else       begin h_s[0]=1; h_s[1]=22; h_s[2]=17; h_s[3]=44; h_s[4]=63; h_idle = 79; end
    end else if (n == 8) begin
      h_d[0]=0; h_d[1]=1; h_d[2]=8; h_d[3]=9; h_d[4]=16;
      if (CHAIN) begin h_s[0]=1; h_s[1]=7;  h_s[2]=9; h_s[3]=15; h_s[4]=19; h_idle = 27; end
      else       begin h_s[0]=1; h_s[1]=14; h_s[2]=9; h_s[3]=28; h_s[4]=39; h_idle = 47; end
    end else begin
      h_d[0]=0; h_d[1]=1; h_d[2]=2; h_d[3]=3; h_d[4]=4;
      h_s[0]=1; h_s[1]=7; h_s[2]=3; h_s[3]=14; h_s[4]=18; h_idle = 19;
    end
    setup();  interpret();  exec_prog("DAXPY");  model();
    check($sformatf("DAXPY vl=%0d", n), 1'b1);
    // the closed-form model must reproduce the hand-derived numbers too
    for (int k = 0; k < 5; k++) if (e_d[k] != h_d[k] || e_s[k] != h_s[k]) begin errors++; $display("FAIL: closed-form model disagrees with the hand schedule (instr %0d)", k); end
    if (e_idle != h_idle) begin errors++; $display("FAIL: closed-form idle %0d vs hand %0d", e_idle, h_idle); end
    if (n == 16) tot_daxpy16 = idle_cyc - d_log[0];
  endtask

  task automatic random_program();
    int op, vd, s1, s2, sc, base;
    p_n = 12;
    seed = seed * 32'd1664525 + 32'd1013904223;  p_vl = 1 + int'(seed[30:16]) % 16;
    for (int k = 0; k < p_n; k++) begin
      seed = seed * 32'd1664525 + 32'd1013904223;  op = int'(seed[30:16]) % 7;
      seed = seed * 32'd1664525 + 32'd1013904223;  vd = int'(seed[30:16]) % 6;
      seed = seed * 32'd1664525 + 32'd1013904223;  s1 = int'(seed[30:16]) % 6;
      seed = seed * 32'd1664525 + 32'd1013904223;  s2 = int'(seed[30:16]) % 6;
      seed = seed * 32'd1664525 + 32'd1013904223;  sc = int'(seed[30:16]) % 2001 - 1000;
      seed = seed * 32'd1664525 + 32'd1013904223;  base = int'(seed[30:16]) % 240;
      if (s1 == vd) s1 = (vd + 1) % 6;                       // the destination differs from the sources
      if (s2 == vd) s2 = (vd + 2) % 6;
      p_op[k] = op;  p_vd[k] = vd;  p_vs1[k] = s1;  p_vs2[k] = s2;  p_sc[k] = sc;  p_base[k] = base;
    end
  endtask

  initial begin
    done = 0;  errors = 0;  tot_daxpy16 = 0;  tot_random = 0;  cyc = 0;  collecting = 0;  dseed = 32'd99;  seed = 32'd2013;
    repeat (3) @(negedge clk);  rst_n = 1;  repeat (2) @(negedge clk);
    daxpy(16);  daxpy(8);  daxpy(1);
    for (int t = 0; t < 40; t++) begin
      random_program();  setup();  interpret();  exec_prog("random");  model();
      check($sformatf("random program %0d (vl=%0d)", t, p_vl), 1'b0);
      tot_random += e_idle;
    end
    done = 1;
  end
endmodule

module tb_vector_chain;
  wire dc, dn;  int ec, en, dax_c, dax_n, rnd_c, rnd_n, dummy1, dummy2;
  int errors;
  vc_harness #(.CHAIN(1)) hc (.done(dc), .errors(ec), .tot_daxpy16(dax_c), .tot_random(rnd_c));
  vc_harness #(.CHAIN(0)) hn (.done(dn), .errors(en), .tot_daxpy16(dax_n), .tot_random(rnd_n));
  initial begin
    wait (dc && dn);
    errors = ec + en;
    if (!(dax_c < dax_n)) begin errors++; $display("FAIL: chaining does not speed up DAXPY"); end
    if (!(rnd_c < rnd_n)) begin errors++; $display("FAIL: chaining does not speed up the random programs"); end
    $display("DAXPY vl=16: chained %0d cycles, unchained %0d cycles (%0d.%02dx);  40 random programs: %0d vs %0d cycles in total",
             dax_c, dax_n, dax_n / dax_c, (dax_n * 100 / dax_c) % 100, rnd_c, rnd_n);
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
