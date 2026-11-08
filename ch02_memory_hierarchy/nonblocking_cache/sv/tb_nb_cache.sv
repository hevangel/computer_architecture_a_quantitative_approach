`timescale 1ns/1ps
// Memory: MEM_LAT 10, a write occupies the memory port for 4 cycles (WR_OCC), a read for 1.  Cycle numbers are relative to the first accepted request (cycle 0).
// Hand-derived expectations ("acc" = cycle a request is accepted, "resp" = cycle its answer appears on the hit or fill port):
//   read hit : resp = acc + 1.        read miss on an idle cache: request to memory at acc+1, line back at acc+11, answered at acc+12.
//   hit under miss    : R0 miss @0, R1 hit @1      -> non-blocking: acc 1, resp 2;  blocking: R1 waits for the miss, acc 13, resp 14
//   miss under miss   : R0 miss @0, R1 miss @1     -> NM >= 2: resp 12, 13;  one MSHR (or blocking): R1 acc 13, resp 25
//   secondary misses  : words 0..3 of ONE line @0,1,2,3 -> one fetch, answers at 12,13,14,15 (blocking: later words hit: acc 13,14,15 resp 14,15,16);
//                       a fifth read of the line @4 hits as soon as the line is installed: acc 12, resp 13 (blocking: acc 16, resp 17)
//   write buffer vs read: W(A) @0, W(L) @1, R(L) @2 (same line L as the second write): the first write holds the memory port c1..c4, the second drains at c5..c8,
//                       so the line fetch may leave only at c9: resp 9 + 10 + 1 = 20, and the read returns the BUFFERED value
//   write to a line with a miss outstanding: R miss @0, W same line @1 -> W acc 13 (after the 12-cycle miss), a later read of it hits with the new value
//   eight writes to distinct words, presented every cycle, accepted at cycle:
//        WBD 0: 0 4 8 12 16 20 24 28     WBD 1: 0 2 6 10 14 18 22 26     WBD 2: 0 1 2 6 10 14 18 22     WBD 4: 0 1 2 3 4 6 10 14
//        (one memory write per 4 cycles in steady state; the buffer only absorbs the burst)
// Then three random request streams (hot region / wide / write heavy): every read must return the program-order value, and after the machine drains main
// memory must equal the shadow memory.
module nbc_harness #(parameter int NM = 4, parameter bit HUM = 1'b1, parameter int WBD = 4)
    (output bit done, output int errors, output int tot_a, output int tot_b, output int tot_c);
  localparam int MAXR = 512;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic req_valid = 0, req_write = 0;  logic [7:0] req_addr = 0;  logic [31:0] req_wdata = 0;  logic [5:0] req_id = 0;
  wire  req_ready, hit_valid, fill_valid, mem_valid, mem_write, mem_ready, mem_rvalid, violation;
  wire  [5:0] hit_id, fill_id;  wire [31:0] hit_data, fill_data, mem_wdata, dbg_data;  wire [7:0] mem_addr;  wire [1:0] mem_tag, mem_rtag;
  wire  [127:0] mem_rline;  wire [31:0] st_hit, st_pri, st_sec;
  logic [7:0] dbg_addr = 0;

  nb_cache #(.NM(NM), .HUM(HUM), .WBD(WBD)) dut (.clk, .rst_n, .req_valid, .req_write, .req_addr, .req_wdata, .req_id, .req_ready,
      .hit_valid, .hit_id, .hit_data, .fill_valid, .fill_id, .fill_data, .mem_valid, .mem_write, .mem_addr, .mem_wdata, .mem_tag, .mem_ready,
      .mem_rvalid, .mem_rtag, .mem_rline, .stat_hit(st_hit), .stat_pri(st_pri), .stat_sec(st_sec));
  nb_mem mem (.clk, .rst_n, .mem_valid, .mem_write, .mem_addr, .mem_wdata, .mem_tag, .mem_ready, .mem_rvalid, .mem_rtag, .mem_rline, .dbg_addr, .dbg_data, .violation);

  bit          r_write [0:MAXR-1];
  int          r_addr [0:MAXR-1], r_time [0:MAXR-1], acc_c [0:MAXR-1], resp_c [0:MAXR-1], id_req [0:63];
  logic [31:0] r_wdata [0:MAXR-1], r_exp [0:MAXR-1];
  logic [31:0] shadow [0:255];
  int n_req = 0, ptr = 0, completed = 0, cyc = 0;
  logic [31:0] wseed = 32'd77, seed = 32'd2013;

  function automatic int rnd(input int n);  seed = seed * 32'd1664525 + 32'd1013904223;  return int'(seed[30:16]) % n;  endfunction

  initial begin
    for (int a = 0; a < 256; a++) shadow[a] = 32'h5A000000 + 32'(a) * 32'd17;
    repeat (3) @(negedge clk);  rst_n = 1;
  end

  task automatic clear();  n_req = 0;  ptr = 0;  completed = 0;  endtask
  task automatic submit(input bit write, input int addr, input int t);
    wseed = wseed * 32'd1664525 + 32'd1013904223;
    r_write[n_req] = write;  r_addr[n_req] = addr;  r_time[n_req] = cyc + 3 + t;  r_wdata[n_req] = wseed;  r_exp[n_req] = shadow[addr];
    resp_c[n_req] = -1;  acc_c[n_req] = -1;
    if (write) shadow[addr] = wseed;
    n_req++;
  endtask
  task automatic run(input int timeout, input string what);
    int t;  t = 0;
    while (completed < n_req && t < timeout) begin @(negedge clk); t++; end
    if (completed < n_req) begin errors++; $display("FAIL [%s] %0d of %0d requests completed in %0d cycles", what, completed, n_req, timeout); end
    repeat (40) @(negedge clk);
  endtask
  task automatic idle(input int n);  repeat (n) @(negedge clk);  endtask
  task automatic expect_i(input string what, input int got, input int exp_v);
    if (got != exp_v) begin errors++; $display("FAIL [%0d,%0d,%0d] %s: got %0d expected %0d", NM, HUM, WBD, what, got, exp_v); end
  endtask
  function automatic int rel_acc(input int i);   return acc_c[i] - acc_c[0];   endfunction
  function automatic int rel_resp(input int i);  return resp_c[i] - acc_c[0];  endfunction

  // driver: present the next due request; it is accepted at the coming clock edge if req_ready is high
  always @(negedge clk) if (rst_n) begin
    req_valid = 1'b0;
    if (ptr < n_req && cyc >= r_time[ptr]) begin
      req_valid = 1'b1;  req_write = r_write[ptr];  req_addr = r_addr[ptr];  req_wdata = r_wdata[ptr];  req_id = ptr % 64;
      #1;
      if (req_ready) begin
        id_req[ptr % 64] = ptr;  acc_c[ptr] = cyc;
        if (r_write[ptr]) completed++;
        ptr++;
      end
    end
  end
  // monitor
  always @(posedge clk) begin
    int k;
    if (rst_n && hit_valid) begin
      k = id_req[hit_id];  resp_c[k] = cyc;  completed++;
      if (hit_data !== r_exp[k]) begin errors++; $display("FAIL read %0d (addr %0d) hit data %h expected %h", k, r_addr[k], hit_data, r_exp[k]); end
    end
    if (rst_n && fill_valid) begin
      k = id_req[fill_id];  resp_c[k] = cyc;  completed++;
      if (fill_data !== r_exp[k]) begin errors++; $display("FAIL read %0d (addr %0d) fill data %h expected %h", k, r_addr[k], fill_data, r_exp[k]); end
    end
    if (rst_n && violation && errors == 0) begin errors++; $display("FAIL: cache presented a request to a busy memory"); end
    cyc++;
  end

  task automatic stream(input int wr_pct, input int hot_pct, input int n, output int total);
    int rw, rh, a64, a256, gap, tc, last;
    clear();  tc = 0;
    for (int i = 0; i < n; i++) begin
      rw = rnd(100);  rh = rnd(100);  a64 = rnd(64);  a256 = rnd(256);  gap = rnd(3);
      tc += gap;
      submit(rw < wr_pct, (rh < hot_pct) ? a64 : a256, tc);
    end
    run(20000, "stream");
    last = 0;  for (int i = 0; i < n; i++) begin if (acc_c[i] > last) last = acc_c[i]; if (resp_c[i] > last) last = resp_c[i]; end
    total = last - acc_c[0];
    idle(100);
    for (int a = 0; a < 256; a++) begin
      dbg_addr = a;  #1;
      if (dbg_data !== shadow[a]) begin errors++; if (errors < 5) $display("FAIL main memory word %0d = %h expected %h", a, dbg_data, shadow[a]); end
    end
  endtask

  initial begin
    int p0, s0, h0, kk;
    bit nb, multi;
    int tab [0:7];
    done = 0;  errors = 0;  tot_a = 0;  tot_b = 0;  tot_c = 0;
    nb = HUM;  multi = HUM && NM >= 2;
    repeat (8) @(negedge clk);

    // ---- T1: hit and miss latencies, conflict miss ----
    clear();  submit(0, 36, 0);   run(100, "miss");     expect_i("read miss latency", rel_resp(0), 12);
    clear();  submit(0, 37, 0);   run(100, "hit");      expect_i("read hit latency", rel_resp(0), 1);
    clear();  submit(0, 100, 0);  run(100, "conflict"); expect_i("conflict miss latency", rel_resp(0), 12);
    clear();  submit(0, 36, 0);   run(100, "evicted");  expect_i("evicted line misses again", rel_resp(0), 12);

    // ---- T2: hit under miss ----
    clear();  submit(0, 8, 0);  run(100, "preload");
    clear();  submit(0, 68, 0);  submit(0, 9, 1);  run(200, "hit under miss");
    expect_i("T2 miss resp", rel_resp(0), 12);
    expect_i("T2 hit acc",  rel_acc(1),  nb ? 1 : 13);
    expect_i("T2 hit resp", rel_resp(1), nb ? 2 : 14);

    // ---- T3: miss under miss ----
    clear();  submit(0, 160, 0);  submit(0, 172, 1);  run(200, "miss under miss");
    expect_i("T3 first resp", rel_resp(0), 12);
    expect_i("T3 second acc",  rel_acc(1),  multi ? 1 : 13);
    expect_i("T3 second resp", rel_resp(1), multi ? 13 : 25);

    // ---- T4: secondary misses ----
    p0 = st_pri;  s0 = st_sec;  h0 = st_hit;
    clear();  submit(0, 192, 0);  submit(0, 193, 1);  submit(0, 194, 2);  submit(0, 195, 3);  submit(0, 192, 4);  run(200, "secondary misses");
    if (nb) begin
      tab[0] = 0; tab[1] = 1; tab[2] = 2; tab[3] = 3; tab[4] = 12;
      for (int i = 0; i < 5; i++) expect_i($sformatf("T4 acc %0d", i), rel_acc(i), tab[i]);
      tab[0] = 12; tab[1] = 13; tab[2] = 14; tab[3] = 15; tab[4] = 13;
      for (int i = 0; i < 5; i++) expect_i($sformatf("T4 resp %0d", i), rel_resp(i), tab[i]);
      expect_i("T4 primary misses", st_pri - p0, 1);  expect_i("T4 secondary misses", st_sec - s0, 3);  expect_i("T4 hits", st_hit - h0, 1);
    end else begin
      tab[0] = 0; tab[1] = 13; tab[2] = 14; tab[3] = 15; tab[4] = 16;
      for (int i = 0; i < 5; i++) expect_i($sformatf("T4 acc %0d", i), rel_acc(i), tab[i]);
      tab[0] = 12; tab[1] = 14; tab[2] = 15; tab[3] = 16; tab[4] = 17;
      for (int i = 0; i < 5; i++) expect_i($sformatf("T4 resp %0d", i), rel_resp(i), tab[i]);
      expect_i("T4 primary misses", st_pri - p0, 1);  expect_i("T4 secondary misses", st_sec - s0, 0);  expect_i("T4 hits", st_hit - h0, 4);
    end

    // ---- T5: a read miss must wait for buffered writes to its line ----
    if (WBD >= 2) begin
      clear();  submit(1, 230, 0);  submit(1, 21, 1);  submit(0, 21, 2);  run(200, "write buffer vs read");
      expect_i("T5 acc W0", rel_acc(0), 0);  expect_i("T5 acc W1", rel_acc(1), 1);  expect_i("T5 acc R", rel_acc(2), 2);
      expect_i("T5 read resp", rel_resp(2), 20);
    end

    // ---- T6: a write to a line with a miss outstanding waits ----
    clear();  submit(0, 40, 0);  submit(1, 41, 1);  submit(0, 41, 14);  run(200, "write vs miss");
    expect_i("T6 W acc", rel_acc(1), 13);  expect_i("T6 R acc", rel_acc(2), 14);  expect_i("T6 R resp", rel_resp(2), 15);

    // ---- T7: write burst ----
    if (WBD == 0 || WBD == 1 || WBD == 2 || WBD == 4) begin
      case (WBD)
        0: begin tab[0]=0; tab[1]=4; tab[2]=8;  tab[3]=12; tab[4]=16; tab[5]=20; tab[6]=24; tab[7]=28; end
        1: begin tab[0]=0; tab[1]=2; tab[2]=6;  tab[3]=10; tab[4]=14; tab[5]=18; tab[6]=22; tab[7]=26; end
        2: begin tab[0]=0; tab[1]=1; tab[2]=2;  tab[3]=6;  tab[4]=10; tab[5]=14; tab[6]=18; tab[7]=22; end
        default: begin tab[0]=0; tab[1]=1; tab[2]=2; tab[3]=3; tab[4]=4; tab[5]=6; tab[6]=10; tab[7]=14; end
      endcase
      clear();  for (int i = 0; i < 8; i++) submit(1, 224 + 4 * i, 0);  run(300, "write burst");
      for (int i = 0; i < 8; i++) expect_i($sformatf("T7 write %0d accepted", i), rel_acc(i), tab[i]);
    end

    // ---- T8: a second write to the address of the entry that is being sent to memory right now must not be lost (checked through the later read and the memory image) ----
    clear();  submit(1, 236, 0);  submit(1, 236, 1);  submit(0, 236, 40);  run(300, "write merge race");
    clear();  submit(1, 237, 0);  submit(1, 237, 1);  submit(1, 237, 2);  submit(0, 237, 40);  run(300, "write merge race 2");

    // ---- random streams ----
    stream(35, 70, 300, tot_a);
    stream(20, 10, 300, tot_b);
    stream(75, 50, 300, tot_c);
    done = 1;
  end
endmodule

module tb_nb_cache;
  wire d0, d1, d2, d3, d4, d5;  int e0, e1, e2, e3, e4, e5;
  int a0, b0, c0, a1, b1, c1, a2, b2, c2, a3, b3, c3, a4, b4, c4, a5, b5, c5;
  nbc_harness #(.NM(1), .HUM(0), .WBD(4)) hb (.done(d0), .errors(e0), .tot_a(a0), .tot_b(b0), .tot_c(c0));   // blocking
  nbc_harness #(.NM(1), .HUM(1), .WBD(4)) hh (.done(d1), .errors(e1), .tot_a(a1), .tot_b(b1), .tot_c(c1));   // hit under miss
  nbc_harness #(.NM(4), .HUM(1), .WBD(4)) hm (.done(d2), .errors(e2), .tot_a(a2), .tot_b(b2), .tot_c(c2));   // miss under miss, 4-entry write buffer
  nbc_harness #(.NM(4), .HUM(1), .WBD(0)) w0 (.done(d3), .errors(e3), .tot_a(a3), .tot_b(b3), .tot_c(c3));   // no write buffer
  nbc_harness #(.NM(4), .HUM(1), .WBD(1)) w1 (.done(d4), .errors(e4), .tot_a(a4), .tot_b(b4), .tot_c(c4));
  nbc_harness #(.NM(4), .HUM(1), .WBD(2)) w2 (.done(d5), .errors(e5), .tot_a(a5), .tot_b(b5), .tot_c(c5));
  int errors;
  initial begin
    wait (d0 && d1 && d2 && d3 && d4 && d5);
    errors = e0 + e1 + e2 + e3 + e4 + e5;
    if (!(a0 > a1 && a1 > a2)) begin errors++; $display("FAIL: hot stream totals not blocking > hit-under-miss > miss-under-miss: %0d %0d %0d", a0, a1, a2); end
    if (!(b0 > b1 && b1 >= b2)) begin errors++; $display("FAIL: wide stream totals: %0d %0d %0d", b0, b1, b2); end
    if (!(c3 > c4 && c4 >= c5 && c5 >= c2 && c3 > c2)) begin errors++; $display("FAIL: write-heavy totals not nonincreasing with buffer depth: %0d %0d %0d %0d", c3, c4, c5, c2); end
    $display("cycles for 300 requests, hot stream:        blocking %0d, hit-under-miss %0d, miss-under-miss %0d", a0, a1, a2);
    $display("cycles for 300 requests, wide stream:       blocking %0d, hit-under-miss %0d, miss-under-miss %0d", b0, b1, b2);
    $display("cycles for 300 requests, write-heavy stream: write buffer depth 0: %0d, 1: %0d, 2: %0d, 4: %0d", c3, c4, c5, c2);
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
