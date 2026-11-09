`timescale 1ns/1ps
// Memory: MEM_LAT 10; a line write keeps the port busy 4 cycles (WR_OCC), a read 1.  Cycle numbers are relative to the first accepted request (cycle 0).
// Hand-derived timeline of one miss on an idle cache (request accepted at cycle 0):
//   c1 fetch leaves for memory (the MSHR becomes visible at c1);  c11 the line returns;  c12 its first target is answered / patched;  one more target per cycle;
//   the cycle after the last target the line is INSTALLED (a dirty victim is pushed into the write-back buffer), the MSHR is free and the line is valid one cycle later.
//   So a read miss is answered at +12, and the MSHR is busy until the end of c13 for a single target.
// Directed expectations ("acc" = cycle a request is accepted, "resp" = cycle its answer appears):
//   hit: +1.  clean-victim conflict miss: +12.
//   hit under miss: R0 miss @0, R1 hit @1 -> non-blocking acc 1 / resp 2; blocking: acc 14, resp 15 (the MSHR is busy until the end of c13)
//   miss under miss: two lines @0, @1 -> NM >= 2 resp 12, 13; one MSHR or blocking: second accepted @14, answered @26
//   four reads of one line @0..3 -> answers 12 13 14 15 (blocking: later reads hit: acc 14 15 16, resp 15 16 17); a fifth read @4 stalls until the line is installed:
//       the install is at c16, so it is accepted @17 and answered @18 (blocking: acc 17, resp 18)
//   store miss (write-allocate): W @0, R of the same word @1 -> the load is answered @13 with the STORE's value (targets run in program order); blocking: R acc 14, resp 15
//   dirty eviction: read of a conflicting line @0 is answered @12 (the write-back is off the critical path); at c13 the dirty victim goes to the write-back buffer, at c14 the
//       memory port takes it (busy c15..c17), so a read of the evicted line accepted @14 can fetch only at c18: answered @29 (= 14 + 15), and it returns the stored value
//   two dirty evictions back to back (WBD >= 2, NM >= 2): R(Z1) @0 evicts X1, R(Z2) @1 evicts X2; X1 is written back at c14 (busy to c17), X2 sits in the buffer from c15;
//       R(X2) @15 must NOT fetch at c18 (X2 is still in the buffer, a fetch would read stale memory): X2 is written at c18, the fetch leaves at c22, answered @33
//   stores that hit cause no memory traffic; evicting the dirty line later costs exactly one line write.
// Then three random streams; every read must return the program-order value; after a FLUSH main memory must equal the shadow memory.
module wbc_harness #(parameter int NM = 4, parameter bit HUM = 1'b1, parameter int WBD = 2)
    (output bit done, output int errors, output int tot_a, output int tot_b, output int tot_c, output int lw_a, output int st_a);
  localparam int MAXR = 512;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic req_valid = 0, req_write = 0, flush = 0;  logic [7:0] req_addr = 0;  logic [31:0] req_wdata = 0;  logic [5:0] req_id = 0;
  wire  req_ready, hit_valid, fill_valid, mem_valid, mem_write, mem_ready, mem_rvalid, violation, flush_done;
  wire  [5:0] hit_id, fill_id;  wire [31:0] hit_data, fill_data, dbg_data;  wire [7:0] mem_addr;  wire [1:0] mem_tag, mem_rtag;
  wire  [127:0] mem_rline, mem_wdata;  wire [31:0] st_hit, st_pri, st_sec, st_wb, n_lwr;
  logic [7:0] dbg_addr = 0;

  wb_cache #(.NM(NM), .HUM(HUM), .WBD(WBD)) dut (.clk, .rst_n, .req_valid, .req_write, .req_addr, .req_wdata, .req_id, .req_ready,
      .hit_valid, .hit_id, .hit_data, .fill_valid, .fill_id, .fill_data, .flush, .flush_done, .mem_valid, .mem_write, .mem_addr, .mem_wdata, .mem_tag,
      .mem_ready, .mem_rvalid, .mem_rtag, .mem_rline, .stat_hit(st_hit), .stat_pri(st_pri), .stat_sec(st_sec), .stat_wb(st_wb));
  wb_mem mem (.clk, .rst_n, .mem_valid, .mem_write, .mem_addr, .mem_wdata, .mem_tag, .mem_ready, .mem_rvalid, .mem_rtag, .mem_rline, .dbg_addr, .dbg_data, .violation, .n_lwr);

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
    repeat (60) @(negedge clk);
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

  // flush the cache and compare main memory with the shadow memory
  task automatic flush_and_check(input string what);
    int t;
    flush = 1;  t = 0;
    while (!flush_done && t < 2000) begin @(negedge clk); t++; end
    if (!flush_done) begin errors++; $display("FAIL [%s] flush never finished", what); end
    @(negedge clk);  flush = 0;  idle(5);
    for (int a = 0; a < 256; a++) begin
      dbg_addr = a;  #1;
      if (dbg_data !== shadow[a]) begin errors++; if (errors < 5) $display("FAIL [%s] main memory word %0d = %h expected %h", what, a, dbg_data, shadow[a]); end
    end
  endtask

  task automatic stream(input int wr_pct, input int hot_pct, input int hot_size, input int n, output int total, output int stores);
    int rw, rh, ahot, awide, gap, tc, last;
    clear();  tc = 0;  stores = 0;
    for (int i = 0; i < n; i++) begin
      rw = rnd(100);  rh = rnd(100);  ahot = rnd(hot_size);  awide = rnd(256);  gap = rnd(3);
      tc += gap;
      submit(rw < wr_pct, (rh < hot_pct) ? ahot : awide, tc);
      if (rw < wr_pct) stores++;
    end
    run(20000, "stream");
    last = 0;  for (int i = 0; i < n; i++) begin if (acc_c[i] > last) last = acc_c[i]; if (resp_c[i] > last) last = resp_c[i]; end
    total = last - acc_c[0];
    idle(100);
    flush_and_check("stream");
  endtask

  initial begin
    int p0, s0, h0, w0, tab [0:7], dummy;
    bit nb, multi;
    done = 0;  errors = 0;  tot_a = 0;  tot_b = 0;  tot_c = 0;  lw_a = 0;  st_a = 0;
    nb = HUM;  multi = HUM && NM >= 2;
    repeat (8) @(negedge clk);

    // ---- T1 ----
    clear();  submit(0, 36, 0);   run(100, "miss");     expect_i("read miss latency", rel_resp(0), 12);
    clear();  submit(0, 37, 0);   run(100, "hit");      expect_i("read hit latency", rel_resp(0), 1);
    clear();  submit(0, 100, 0);  run(100, "conflict"); expect_i("clean conflict miss latency", rel_resp(0), 12);
    // ---- T2: hit under miss ----
    clear();  submit(0, 8, 0);  run(100, "preload");
    clear();  submit(0, 68, 0);  submit(0, 9, 1);  run(200, "hit under miss");
    expect_i("T2 miss resp", rel_resp(0), 12);
    expect_i("T2 hit acc",  rel_acc(1),  nb ? 1 : 14);
    expect_i("T2 hit resp", rel_resp(1), nb ? 2 : 15);
    // ---- T3: miss under miss ----
    clear();  submit(0, 160, 0);  submit(0, 172, 1);  run(200, "miss under miss");
    expect_i("T3 first resp", rel_resp(0), 12);
    expect_i("T3 second acc",  rel_acc(1),  multi ? 1 : 14);
    expect_i("T3 second resp", rel_resp(1), multi ? 13 : 26);
    // ---- T4: secondary misses ----
    p0 = st_pri;  s0 = st_sec;  h0 = st_hit;
    clear();  submit(0, 192, 0);  submit(0, 193, 1);  submit(0, 194, 2);  submit(0, 195, 3);  submit(0, 192, 4);  run(200, "secondary misses");
    if (nb) begin
      tab[0] = 0; tab[1] = 1; tab[2] = 2; tab[3] = 3; tab[4] = 17;
      for (int i = 0; i < 5; i++) expect_i($sformatf("T4 acc %0d", i), rel_acc(i), tab[i]);
      tab[0] = 12; tab[1] = 13; tab[2] = 14; tab[3] = 15; tab[4] = 18;
      for (int i = 0; i < 5; i++) expect_i($sformatf("T4 resp %0d", i), rel_resp(i), tab[i]);
      expect_i("T4 primary misses", st_pri - p0, 1);  expect_i("T4 secondary misses", st_sec - s0, 3);  expect_i("T4 hits", st_hit - h0, 1);
    end else begin
      tab[0] = 0; tab[1] = 14; tab[2] = 15; tab[3] = 16; tab[4] = 17;
      for (int i = 0; i < 5; i++) expect_i($sformatf("T4 acc %0d", i), rel_acc(i), tab[i]);
      tab[0] = 12; tab[1] = 15; tab[2] = 16; tab[3] = 17; tab[4] = 18;
      for (int i = 0; i < 5; i++) expect_i($sformatf("T4 resp %0d", i), rel_resp(i), tab[i]);
      expect_i("T4 primary misses", st_pri - p0, 1);  expect_i("T4 secondary misses", st_sec - s0, 0);  expect_i("T4 hits", st_hit - h0, 4);
    end
    // ---- T5: store miss = write-allocate; the load behind it sees the store ----
    clear();  submit(1, 200, 0);  submit(0, 200, 1);  run(200, "store miss");
    expect_i("T5 store acc", rel_acc(0), 0);
    expect_i("T5 load acc",  rel_acc(1), nb ? 1 : 14);
    expect_i("T5 load resp", rel_resp(1), nb ? 13 : 15);
    // ---- T6: dirty eviction is off the critical path; the evicted line comes back with the stored value ----
    w0 = n_lwr;
    clear();  submit(0, 8, 0);  submit(0, 200, 14);  run(300, "dirty eviction");
    expect_i("T6 evicting read resp", rel_resp(0), 12);
    expect_i("T6 re-read acc", rel_acc(1), 14);
    expect_i("T6 re-read resp", rel_resp(1), 29);
    expect_i("T6 line writes", n_lwr - w0, 1);
    // ---- T6b: two dirty evictions; the second victim is re-read while it is still in the write-back buffer ----
    if (multi && WBD >= 2) begin
      clear();  submit(1, 240, 0);  submit(1, 244, 0);  run(200, "dirty setup");
      clear();  submit(0, 16, 0);  submit(0, 20, 1);  submit(0, 244, 15);  run(300, "two dirty evictions");
      expect_i("T6b first resp", rel_resp(0), 12);
      expect_i("T6b second resp", rel_resp(1), 13);
      expect_i("T6b re-read acc", rel_acc(2), 15);
      expect_i("T6b re-read resp", rel_resp(2), 33);
    end
    // ---- T7: stores that hit cost no memory traffic; the dirty line is written back once, when evicted ----
    clear();  submit(0, 16, 0);  run(100, "make 16 resident");
    w0 = n_lwr;  h0 = st_hit;
    clear();  for (int i = 0; i < 4; i++) submit(1, 16 + i, i);  run(100, "store hits");
    for (int i = 0; i < 4; i++) expect_i($sformatf("T7 store %0d acc", i), rel_acc(i), i);
    expect_i("T7 store hits counted", st_hit - h0, 4);
    expect_i("T7 no line writes yet", n_lwr - w0, 0);
    clear();  submit(0, 240, 0);  run(200, "evict the dirty line");
    expect_i("T7 one line write for four stores", n_lwr - w0, 1);
    expect_i("T7 evicting read resp", rel_resp(0), 12);

    // ---- random streams ----
    flush_and_check("directed tests");
    w0 = n_lwr;  stream(40, 90, 24, 300, tot_a, st_a);  lw_a = n_lwr - w0;
    stream(20, 10, 64, 300, tot_b, dummy);
    stream(70, 50, 64, 300, tot_c, dummy);
    done = 1;
  end
endmodule

module tb_wb_cache;
  wire d0, d1, d2, d3, d4;  int e0, e1, e2, e3, e4;
  int a0, b0, c0, l0, s0, a1, b1, c1, l1, s1, a2, b2, c2, l2, s2, a3, b3, c3, l3, s3, a4, b4, c4, l4, s4;
  wbc_harness #(.NM(1), .HUM(0), .WBD(2)) hb (.done(d0), .errors(e0), .tot_a(a0), .tot_b(b0), .tot_c(c0), .lw_a(l0), .st_a(s0));   // blocking
  wbc_harness #(.NM(1), .HUM(1), .WBD(2)) hh (.done(d1), .errors(e1), .tot_a(a1), .tot_b(b1), .tot_c(c1), .lw_a(l1), .st_a(s1));   // hit under miss
  wbc_harness #(.NM(4), .HUM(1), .WBD(2)) hm (.done(d2), .errors(e2), .tot_a(a2), .tot_b(b2), .tot_c(c2), .lw_a(l2), .st_a(s2));   // miss under miss
  wbc_harness #(.NM(4), .HUM(1), .WBD(1)) w1 (.done(d3), .errors(e3), .tot_a(a3), .tot_b(b3), .tot_c(c3), .lw_a(l3), .st_a(s3));   // one write-back entry
  wbc_harness #(.NM(4), .HUM(1), .WBD(4)) w4 (.done(d4), .errors(e4), .tot_a(a4), .tot_b(b4), .tot_c(c4), .lw_a(l4), .st_a(s4));   // four write-back entries
  int errors;
  initial begin
    wait (d0 && d1 && d2 && d3 && d4);
    errors = e0 + e1 + e2 + e3 + e4;
    if (!(b0 > b1 && b1 > b2)) begin errors++; $display("FAIL: wide stream totals not blocking > hit-under-miss > miss-under-miss: %0d %0d %0d", b0, b1, b2); end
    if (!(c0 > c1 && c1 > c2)) begin errors++; $display("FAIL: write-heavy stream totals: %0d %0d %0d", c0, c1, c2); end
    if (!(c3 >= c2 && c2 >= c4)) begin errors++; $display("FAIL: totals not nonincreasing with write-back buffer depth: %0d %0d %0d", c3, c2, c4); end
    if (!(l2 * 3 < s2)) begin errors++; $display("FAIL: write-back did not cut memory writes: %0d line writes for %0d stores", l2, s2); end
    $display("wide stream, 300 requests:        blocking %0d, hit-under-miss %0d, miss-under-miss %0d cycles", b0, b1, b2);
    $display("write-heavy stream, 300 requests: blocking %0d, hit-under-miss %0d, miss-under-miss %0d cycles;  write-back buffer of 1/2/4 lines: %0d/%0d/%0d", c0, c1, c2, c3, c2, c4);
    $display("hot stream: %0d stores became %0d line writes in memory (write-through would need %0d word writes)", s2, l2, s2);
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
