`timescale 1ns/1ps
// Timing parameters (cycles): tRCD 3, tCL 3, tCWL 2, tRP 3, tRAS 7, tWR 3, tRTP 2, tRRD 2, tCCD = BL = 4, tWTR 3, tRTW 6, tRFC 12.
// Hand-derived expectations, request accepted at cycle q on an otherwise idle system (see dram_ctrl):
//     row miss  (bank closed)   : 2 + tRCD + tCL + BL        = 12 cycles
//     row hit   (row open)      : 2 + tCL + BL               =  9
//     row conflict (other row)  : 2 + tRP + tRCD + tCL + BL  = 15
//   closed-page policy: the bank has always been precharged by the next access, so all three are 12.
//   FR-FCFS on A0 B0 A1 B1 A2 B2 A3 B3 (rows A and B of ONE bank, 4 bursts each): 2 activations; FCFS: 8.
//   64 sequential bursts, bank-interleaved: the data bus can be kept busy: (first RD at q+2+tRCD) + 63 x tCCD + tCL + BL = q + 264 cycles.
// Every run also demands: read data equals the program-order value, no request lost, and zero violations reported by the device's independent timing checker.
module dram_harness #(parameter bit FR_FCFS = 1'b1, parameter bit OPEN_PAGE = 1'b1, parameter int REFI = 400) ();
  localparam int MAXR = 1024;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic req_valid = 0, req_write = 0;  logic [7:0] req_addr = 0;  logic [127:0] req_wdata = 0;  logic [5:0] req_id = 0;
  wire  req_ready, rd_resp_valid, wr_resp_valid, cmd_valid, dev_rd_valid, violation;
  wire  [5:0] rd_resp_id, wr_resp_id;  wire [127:0] rd_resp_data, cmd_wdata, dev_rd_data;
  wire  [2:0] cmd;  wire [1:0] cmd_bank, cmd_col;  wire [3:0] cmd_row;
  wire  [31:0] st_act, st_pre, st_rd, st_wr, st_ref, dev_refs, max_gap;

  dram_ctrl #(.FR_FCFS(FR_FCFS), .OPEN_PAGE(OPEN_PAGE), .tREFI(REFI)) ctrl (.clk, .rst_n, .req_valid, .req_ready, .req_write, .req_addr, .req_wdata, .req_id,
      .rd_resp_valid, .rd_resp_id, .rd_resp_data, .wr_resp_valid, .wr_resp_id, .cmd_valid, .cmd, .cmd_bank, .cmd_row, .cmd_col, .cmd_wdata,
      .dev_rd_valid, .dev_rd_data, .stat_act(st_act), .stat_pre(st_pre), .stat_rd(st_rd), .stat_wr(st_wr), .stat_ref(st_ref));
  dram_device dev (.clk, .rst_n, .cmd_valid, .cmd, .cmd_bank, .cmd_row, .cmd_col, .cmd_wdata, .rd_valid(dev_rd_valid), .rd_data(dev_rd_data),
      .violation, .stat_refs(dev_refs), .max_ref_gap(max_gap));

  logic        r_write [0:MAXR-1];
  logic [7:0]  r_addr  [0:MAXR-1];
  logic [127:0] r_wdata [0:MAXR-1], r_exp [0:MAXR-1];
  int          r_time [0:MAXR-1], enq [0:MAXR-1], done_at [0:MAXR-1], id_req [0:63];
  logic [127:0] shadow [0:255];
  int n_req = 0, ptr = 0, completed = 0, cyc = 0, errors = 0;
  logic [31:0] wseed = 32'd77;

  function automatic logic [127:0] init_burst(input int a);
    for (int k = 0; k < 4; k++) init_burst[32*k +: 32] = 32'hD0000000 | (a << 8) | k;
  endfunction
  initial begin
    for (int a = 0; a < 256; a++) shadow[a] = init_burst(a);
    repeat (3) @(negedge clk);  rst_n = 1;
  end

  task automatic clear();  n_req = 0;  ptr = 0;  completed = 0;  endtask
  // queue a request `t` cycles from now; write data is pseudo-random; the expected read value is the program-order value
  task automatic submit(input bit write, input int addr, input int t);
    logic [127:0] w;
    for (int k = 0; k < 4; k++) begin wseed = wseed * 32'd1664525 + 32'd1013904223; w[32*k +: 32] = wseed; end
    r_write[n_req] = write;  r_addr[n_req] = addr[7:0];  r_time[n_req] = cyc + 2 + t;  r_wdata[n_req] = w;
    r_exp[n_req] = shadow[addr];
    if (write) shadow[addr] = w;
    n_req++;
  endtask
  task automatic run(input int timeout, input string what);
    int t;  t = 0;
    while (completed < n_req && t < timeout) begin @(negedge clk); t++; end
    if (completed < n_req) begin errors++; $display("FAIL [%s] %0d of %0d requests completed in %0d cycles", what, completed, n_req, timeout); end
    repeat (4) @(negedge clk);
  endtask
  task automatic idle(input int n);  repeat (n) @(negedge clk);  endtask
  function automatic int latency(input int i);  return done_at[i] - enq[i];  endfunction
  int last_avg100 = 0, last_total = 0;
  // replay the request stream that the top module generated (tb_dram_controller.s_*), then record average latency (x100) and the total time
  task automatic run_stream(input string what, input int n);
    int tc, sum, mx;
    clear();  tc = 0;
    for (int i = 0; i < n; i++) begin tc += tb_dram_controller.s_g[i]; submit(tb_dram_controller.s_w[i], tb_dram_controller.s_a[i], tc); end
    run(30000, what);
    sum = 0;  mx = 0;
    for (int i = 0; i < n; i++) begin sum += latency(i); if (done_at[i] > mx) mx = done_at[i]; end
    last_avg100 = sum * 100 / n;  last_total = mx - enq[0];
  endtask

  always @(negedge clk) if (rst_n) begin
    int k;
    req_valid = 1'b0;
    if (ptr < n_req && cyc >= r_time[ptr] && req_ready) begin
      req_valid = 1'b1;  req_write = r_write[ptr];  req_addr = r_addr[ptr];  req_wdata = r_wdata[ptr];  req_id = ptr % 64;
      id_req[ptr % 64] = ptr;  enq[ptr] = cyc;  ptr++;
    end
    if (rd_resp_valid) begin
      k = id_req[rd_resp_id];  done_at[k] = cyc;  completed++;
      if (rd_resp_data !== r_exp[k]) begin errors++; $display("FAIL read of request %0d (addr %0d): %h expected %h", k, r_addr[k], rd_resp_data, r_exp[k]); end
    end
    if (wr_resp_valid) begin k = id_req[wr_resp_id];  done_at[k] = cyc;  completed++; end
    cyc++;
  end
  always @(posedge clk) if (violation && rst_n && errors == 0) begin errors++; $display("FAIL: the DRAM device reported a timing/protocol violation"); end
endmodule

module tb_dram_controller;
  int errors = 0;
  task automatic expect_i(input string what, input int got, input int exp_v);
    if (got != exp_v) begin errors++; $display("FAIL %s: got %0d expected %0d", what, got, exp_v); end
  endtask

  dram_harness #(.FR_FCFS(1), .OPEN_PAGE(1), .REFI(400)) ho ();      // FR-FCFS, open page
  dram_harness #(.FR_FCFS(1), .OPEN_PAGE(0), .REFI(400)) hc ();      // FR-FCFS, closed page
  dram_harness #(.FR_FCFS(0), .OPEN_PAGE(1), .REFI(400)) hf ();      // FCFS, open page
  dram_harness #(.FR_FCFS(1), .OPEN_PAGE(1), .REFI(400)) hs ();      // streaming
  dram_harness #(.FR_FCFS(1), .OPEN_PAGE(1), .REFI(100)) hr ();      // refresh every 100 cycles

  logic [31:0] seed = 32'd2013;
  function automatic int rnd(input int n); seed = seed * 32'd1664525 + 32'd1013904223; return int'(seed[30:16]) % n; endfunction

  // the same request stream is replayed on several harnesses
  bit  s_w [0:299];  int s_a [0:299], s_g [0:299];
  task automatic make_stream(input int kind);          // 0: small hot set (many same-address hazards)   1: wide random   2: high row locality
    int prev;  prev = 0;
    for (int i = 0; i < 300; i++) begin
      s_w[i] = (rnd(10) < 4);
      s_g[i] = rnd(5);
      if (kind == 0) s_a[i] = rnd(24);
      else if (kind == 1) s_a[i] = rnd(256);
      else begin if (rnd(10) < 8) s_a[i] = (prev & 8'hFC) | rnd(4); else s_a[i] = rnd(256); end     // 80%: another burst of the same row
      prev = s_a[i];
    end
  endtask

  initial begin
    int a0, a1, tmax, t_fr, t_fcfs, act_fr, act_fcfs, avg_o, avg_c, avg_f, tot_o, tot_c, tot_f, nrefs, tstream, bw100, r0, c0;
    repeat (8) @(negedge ho.clk);

    // ---- 1. latencies on an idle system (addresses: {row 2, bank 1, col 0} = 36, same row col 1 = 37, {row 5, bank 1} = 84) -----------------------------------
    ho.clear();  ho.submit(0, 36, 0);  ho.run(100, "open miss");      expect_i("open page: row miss",     ho.latency(0), 12);  ho.idle(30);
    ho.clear();  ho.submit(0, 37, 0);  ho.run(100, "open hit");       expect_i("open page: row hit",      ho.latency(0), 9);   ho.idle(30);
    ho.clear();  ho.submit(0, 84, 0);  ho.run(100, "open conflict");  expect_i("open page: row conflict", ho.latency(0), 15);
    hf.clear();  hf.submit(0, 36, 0);  hf.run(100, "fcfs miss");      expect_i("FCFS: row miss",          hf.latency(0), 12);  hf.idle(30);
    hf.clear();  hf.submit(0, 37, 0);  hf.run(100, "fcfs hit");       expect_i("FCFS: row hit",           hf.latency(0), 9);   hf.idle(30);
    hf.clear();  hf.submit(0, 84, 0);  hf.run(100, "fcfs conflict");  expect_i("FCFS: row conflict",     hf.latency(0), 15);
    hc.clear();  hc.submit(0, 36, 0);  hc.run(100, "closed miss");    expect_i("closed page: first access",        hc.latency(0), 12);  hc.idle(30);
    hc.clear();  hc.submit(0, 37, 0);  hc.run(100, "closed 2");       expect_i("closed page: same row, later",     hc.latency(0), 12);  hc.idle(30);
    hc.clear();  hc.submit(0, 84, 0);  hc.run(100, "closed 3");       expect_i("closed page: different row",      hc.latency(0), 12);
    $display("latency: open page  miss 12 / hit 9 / conflict 15 cycles;   closed page  12 / 12 / 12");

    // ---- 2. FR-FCFS vs FCFS on A0 B0 A1 B1 A2 B2 A3 B3 (rows 3 and 9 of bank 0, 4 bursts each) -----------------------------------------------------
    a0 = ho.st_act;  ho.clear();
    for (int i = 0; i < 4; i++) begin ho.submit(0, 48 + i, 2 * i); ho.submit(0, 144 + i, 2 * i + 1); end
    ho.run(1000, "A/B FR-FCFS");
    act_fr = ho.st_act - a0;  tmax = 0;  for (int i = 0; i < 8; i++) if (ho.done_at[i] > tmax) tmax = ho.done_at[i];  t_fr = tmax - ho.enq[0];
    a1 = hf.st_act;  hf.clear();
    for (int i = 0; i < 4; i++) begin hf.submit(0, 48 + i, 2 * i); hf.submit(0, 144 + i, 2 * i + 1); end
    hf.run(1000, "A/B FCFS");
    act_fcfs = hf.st_act - a1;  tmax = 0;  for (int i = 0; i < 8; i++) if (hf.done_at[i] > tmax) tmax = hf.done_at[i];  t_fcfs = tmax - hf.enq[0];
    expect_i("FR-FCFS: row activations for A0 B0 A1 B1 ...", act_fr, 2);
    expect_i("FCFS: row activations for A0 B0 A1 B1 ...", act_fcfs, 8);
    if (!(t_fr < t_fcfs)) begin errors++; $display("FAIL: FR-FCFS (%0d cycles) is not faster than FCFS (%0d)", t_fr, t_fcfs); end
    $display("A/B pattern: FR-FCFS %0d activations in %0d cycles;  FCFS %0d activations in %0d cycles", act_fr, t_fr, act_fcfs, t_fcfs);

    // ---- 3. data integrity and policy comparison on random streams -------------------------------------------------------------------------------------
    make_stream(0);  ho.run_stream("hot set", 300);  hc.run_stream("hot set", 300);  hf.run_stream("hot set", 300);
    $display("hot set (many same-address read/write hazards): 300 requests; average latency  FR-FCFS open %0d.%02d  closed %0d.%02d  FCFS open %0d.%02d cycles",
             ho.last_avg100 / 100, ho.last_avg100 % 100, hc.last_avg100 / 100, hc.last_avg100 % 100, hf.last_avg100 / 100, hf.last_avg100 % 100);
    make_stream(1);  ho.run_stream("wide random", 300);  hc.run_stream("wide random", 300);  hf.run_stream("wide random", 300);
    $display("wide random: average latency (total cycles)  FR-FCFS open %0d.%02d (%0d)  closed %0d.%02d (%0d)  FCFS open %0d.%02d (%0d)",
             ho.last_avg100 / 100, ho.last_avg100 % 100, ho.last_total, hc.last_avg100 / 100, hc.last_avg100 % 100, hc.last_total, hf.last_avg100 / 100, hf.last_avg100 % 100, hf.last_total);
    make_stream(2);  ho.run_stream("row locality", 300);  hc.run_stream("row locality", 300);  hf.run_stream("row locality", 300);
    $display("row locality (80%% same row): average latency (total cycles)  FR-FCFS open %0d.%02d (%0d)  closed %0d.%02d (%0d)  FCFS open %0d.%02d (%0d)",
             ho.last_avg100 / 100, ho.last_avg100 % 100, ho.last_total, hc.last_avg100 / 100, hc.last_avg100 % 100, hc.last_total, hf.last_avg100 / 100, hf.last_avg100 % 100, hf.last_total);
    if (ho.last_total > hf.last_total) begin errors++; $display("FAIL: FR-FCFS is slower than FCFS on the row-locality stream"); end

    // ---- 4. streaming: 64 sequential bursts keep the data bus busy ------------------------------------------------------------------------------------------
    hs.clear();  for (int i = 0; i < 64; i++) hs.submit(0, i, 0);
    hs.run(2000, "streaming");
    tmax = 0;  for (int i = 0; i < 64; i++) if (hs.done_at[i] > tmax) tmax = hs.done_at[i];
    tstream = tmax - hs.enq[0];
    expect_i("streaming: 64 bursts finish exactly q + 264 cycles", tstream, 264);
    expect_i("streaming: activations (4 banks x 4 rows)", hs.st_act, 16);
    expect_i("streaming: reads", hs.st_rd, 64);
    bw100 = 64 * 4 * 100 / tstream;
    $display("streaming: 64 bursts in %0d cycles = %0d%% of peak data-bus bandwidth (%0d activations hidden behind other banks' bursts)", tstream, bw100, hs.st_act);

    // ---- 5. refresh every 100 cycles ---------------------------------------------------------------------------------------------------------------------
    r0 = hr.dev_refs;  c0 = hr.cyc;                                             // the harness has been running since reset: measure a 720-cycle window
    hr.clear();
    for (int i = 0; i < 50; i++) begin
      bit w;  int ad;
      w = (rnd(10) < 4);  ad = rnd(256);                                       // explicit draw order (the VHDL testbench draws the same stream)
      hr.submit(w, ad, 12 * i);
    end
    hr.run(2000, "refresh traffic");
    while (hr.cyc < c0 + 720) @(negedge hr.clk);
    nrefs = hr.dev_refs - r0;
    // a refresh is due every 100 cycles and may be delayed by at most 40 (draining + precharging) -> between floor(720/140) = 5 and ceil(720/100) = 8
    if (nrefs < 5 || nrefs > 8) begin errors++; $display("FAIL: %0d refreshes in a 720-cycle window with tREFI = 100 (expected 5..8)", nrefs); end
    expect_i("controller and device agree on the refresh count", hr.st_ref, hr.dev_refs);
    if (hr.max_gap > 140) begin errors++; $display("FAIL: refresh gap %0d cycles exceeds tREFI + 40", hr.max_gap); end
    $display("refresh: %0d REF commands in a 720-cycle window (tREFI = 100); over the whole run %0d refreshes, longest gap %0d cycles (limit 140)", nrefs, hr.dev_refs, hr.max_gap);

    errors += ho.errors + hc.errors + hf.errors + hs.errors + hr.errors;
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
