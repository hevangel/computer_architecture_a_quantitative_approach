`timescale 1ns/1ps
// Directed sequence on block 0 (P = 4, initial memory 0xA0, directory U), hand-derived.  hops(t) = message hops of the transaction; the expected latency is hops*LAT + 1 for a miss
// and 1 for a hit; "msgs" = messages sent (request, invalidates, acknowledgements, fetch, data to home, reply).
//    # op                          directory before -> after        caches after (C0 C1 C2 C3)   hops  msgs   what happens
//    1 C0 read                     U -> S{0}                        S I I I                      2     2      request, data reply
//    2 C0 read                     S{0}                              S I I I                      hit   0
//    3 C1 read                     S{0} -> S{0,1}                    S S I I                      2     2
//    4 C2 read                     S{0,1} -> S{0,1,2}                S S S I                      2     2
//    5 C3 write 0xB1               S{0,1,2} -> M{3}                  I I I M                      4     8      request, 3 invalidates, 3 acks, reply (2k+2, k=3)
//    6 C3 write 0xB2               M{3}                              I I I M                      hit   0
//    7 C0 read  (-> 0xB2)          M{3} -> S{0,3}                    S I I S                      4     4      request, fetch, data to home (memory := 0xB2), reply
//    8 C0 write 0xC3               S{0,3} -> M{0}                    M I I I                      4     4      C0 already shares; request, 1 invalidate, 1 ack, reply (k=1)
//    9 C1 write 0xD4               M{0} -> M{1}                      I M I I                      4     4      request, fetch+invalidate, data to home (memory := 0xC3), reply
//   10 C1 read                     M{1}                              I M I I                      hit   0
//   11 C2 write 0xE5               M{1} -> M{2}                      I I M I                      4     4
//   12 C2 read blk 1               U -> S{2}                         (block 1) I I S I            2     2
//   13 C2 write blk 1 0xF6         S{2} -> M{2}                      (block 1) I I M I            2     2      the only sharer upgrades: no invalidates (k=0)
//   14 C3 write blk 2 0x17         U -> M{3}                         (block 2) I I I M            2     2
// The random phase compares every operation with a reference model of the same protocol (states, data, message counts, latency) and checks the invariants after each operation.
module dir_harness #(parameter int P = 4, parameter int NB = 4, parameter int LAT = 2, parameter bit SPARSE = 1'b0)
    (output bit done, output int errors, output int r_msgs, output int r_miss, output int r_ops);
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic req_valid = 0, req_write = 0;  logic [$clog2(P)-1:0] req_node = 0;  logic [$clog2(NB)-1:0] req_blk = 0;  logic [31:0] req_wdata = 0;
  wire req_ready, resp_valid;  wire [31:0] resp_data;
  wire [31:0] st_req, st_rep, st_inv, st_ack, st_fetch, st_wb, st_hits, st_miss;
  logic [$clog2(P)-1:0] dbg_node = 0;  logic [$clog2(NB)-1:0] dbg_blk = 0;
  wire [1:0] dbg_cstate, dbg_dstate;  wire [31:0] dbg_cdata, dbg_mem;  wire [P-1:0] dbg_dsharers;
  directory_msi #(.P(P), .NB(NB), .LAT(LAT)) dut (.clk, .rst_n, .req_valid, .req_node, .req_write, .req_blk, .req_wdata, .req_ready, .resp_valid, .resp_data,
      .stat_req(st_req), .stat_rep(st_rep), .stat_inv(st_inv), .stat_ack(st_ack), .stat_fetch(st_fetch), .stat_wb(st_wb), .stat_hits(st_hits), .stat_misses(st_miss),
      .dbg_node, .dbg_blk, .dbg_cstate, .dbg_cdata, .dbg_dstate, .dbg_dsharers, .dbg_mem);

  // reference model (written independently of the RTL: explicit per-node states and message bookkeeping)
  int          sst [0:P*NB-1];                  // 0 I, 1 S, 2 M
  int          sdir [0:NB-1];                   // 0 U, 1 S, 2 M
  logic [P-1:0] ssh [0:NB-1];
  logic [31:0] smem [0:NB-1], sdat [0:P*NB-1], gval [0:NB-1];
  int cyc = 0, resp_cyc = 0;  bit got = 0;  logic [31:0] got_data;
  always @(posedge clk) begin
    if (resp_valid) begin got = 1;  resp_cyc = cyc;  got_data = resp_data; end
    cyc++;
  end

  int e_hops, e_msgs, e_req, e_rep, e_inv, e_ack, e_fetch, e_wb;  bit e_hit;  logic [31:0] e_data;
  task automatic ref_op(input int c, input bit wr, input int b, input logic [31:0] wd);
    int sharers, owner;
    e_hit = 0; e_hops = 0; e_req = 0; e_rep = 0; e_inv = 0; e_ack = 0; e_fetch = 0; e_wb = 0;
    sharers = 0;  owner = -1;
    for (int j = 0; j < P; j++) if (ssh[b][j]) begin if (j != c) sharers++; if (sdir[b] == 2) owner = j; end
    if (!wr) begin
      if (sst[c*NB + b] != 0) begin e_hit = 1; e_data = sdat[c*NB + b]; end
      else begin
        e_req = 1; e_rep = 1; e_hops = 2;
        if (sdir[b] == 2) begin                                               // owner supplies the data through the home
          e_fetch = 1; e_wb = 1; e_hops = 4;
          smem[b] = sdat[owner*NB + b];  sst[owner*NB + b] = 1;
        end
        sdat[c*NB + b] = smem[b];  e_data = smem[b];
        sst[c*NB + b] = 1;  sdir[b] = 1;  ssh[b][c] = 1;
      end
    end else begin
      if (sst[c*NB + b] == 2) begin e_hit = 1; sdat[c*NB + b] = wd; end
      else begin
        e_req = 1; e_rep = 1; e_hops = 2;
        if (sdir[b] == 2) begin
          e_fetch = 1; e_wb = 1; e_hops = 4;
          smem[b] = sdat[owner*NB + b];  sst[owner*NB + b] = 0;
        end else if (sdir[b] == 1 && sharers > 0) begin
          e_inv = sharers; e_ack = sharers; e_hops = 4;
          for (int j = 0; j < P; j++) if (j != c && ssh[b][j]) sst[j*NB + b] = 0;
        end
        sst[c*NB + b] = 2;  sdat[c*NB + b] = wd;
        sdir[b] = 2;  ssh[b] = '0;  ssh[b][c] = 1;
      end
      e_data = wd;
    end
    if (wr) gval[b] = wd;
    e_msgs = e_req + e_rep + e_inv + e_ack + e_fetch + e_wb;
  endtask

  int tot_msgs = 0, tot_miss = 0;
  // drive one operation, wait for its response, compare everything
  task automatic do_op(input int c, input bit wr, input int b, input logic [31:0] wd, input int exp_hops, input int exp_msgs, input string what);
    int t0, s0, m0, exp_lat;  logic [31:0] before_msgs, after_msgs;
    int d_req, d_rep, d_inv, d_ack, d_fetch, d_wb;
    while (!req_ready) @(negedge clk);
    @(negedge clk);
    before_msgs = st_req + st_rep + st_inv + st_ack + st_fetch + st_wb;
    d_req = st_req; d_rep = st_rep; d_inv = st_inv; d_ack = st_ack; d_fetch = st_fetch; d_wb = st_wb;
    ref_op(c, wr, b, wd);
    got = 0;  req_valid = 1;  req_node = c[$clog2(P)-1:0];  req_write = wr;  req_blk = b[$clog2(NB)-1:0];  req_wdata = wd;  t0 = cyc;
    @(negedge clk);  req_valid = 0;
    while (!got) @(negedge clk);
    exp_lat = e_hit ? 1 : e_hops * LAT + 1;
    if (resp_cyc - t0 != exp_lat) begin errors++; $display("FAIL [%s] latency %0d expected %0d", what, resp_cyc - t0, exp_lat); end
    if (exp_hops >= 0 && !(e_hit ? exp_hops == 0 : exp_hops == e_hops)) begin errors++; $display("FAIL [%s] reference model has %0d hops, hand-derived %0d", what, e_hops, exp_hops); end
    if (exp_msgs >= 0 && e_msgs != exp_msgs) begin errors++; $display("FAIL [%s] reference model sends %0d messages, hand-derived %0d", what, e_msgs, exp_msgs); end
    repeat (2) @(negedge clk);
    after_msgs = st_req + st_rep + st_inv + st_ack + st_fetch + st_wb;
    if (after_msgs - before_msgs != e_msgs) begin errors++; $display("FAIL [%s] %0d messages sent, expected %0d", what, after_msgs - before_msgs, e_msgs); end
    if (int'(st_req) - d_req != e_req || int'(st_rep) - d_rep != e_rep || int'(st_inv) - d_inv != e_inv || int'(st_ack) - d_ack != e_ack ||
        int'(st_fetch) - d_fetch != e_fetch || int'(st_wb) - d_wb != e_wb) begin errors++; $display("FAIL [%s] message types differ", what); end
    if (!wr && got_data !== gval[b]) begin errors++; $display("FAIL [%s] read %h expected %h", what, got_data, gval[b]); end
    tot_msgs += e_msgs;  if (!e_hit) tot_miss++;
    check_state(b, what);
  endtask

  task automatic check_state(input int b, input string what);
    dbg_blk = b[$clog2(NB)-1:0];
    for (int j = 0; j < P; j++) begin
      dbg_node = j[$clog2(P)-1:0];  #1;
      if (int'(dbg_cstate) != sst[j*NB + b]) begin errors++; $display("FAIL [%s] node %0d block %0d state %0d expected %0d", what, j, b, dbg_cstate, sst[j*NB + b]); end
      if (sst[j*NB + b] != 0 && dbg_cdata !== sdat[j*NB + b]) begin errors++; $display("FAIL [%s] node %0d block %0d data %h expected %h", what, j, b, dbg_cdata, sdat[j*NB + b]); end
    end
    #1;
    if (int'(dbg_dstate) != sdir[b] || dbg_dsharers !== ssh[b]) begin errors++; $display("FAIL [%s] directory block %0d: state %0d sharers %b, expected %0d %b", what, b, dbg_dstate, dbg_dsharers, sdir[b], ssh[b]); end
    if (sdir[b] != 2 && dbg_mem !== smem[b]) begin errors++; $display("FAIL [%s] block %0d memory %h expected %h", what, b, dbg_mem, smem[b]); end
    // protocol invariants
    begin
      int owners = 0, shared = 0;
      for (int j = 0; j < P; j++) begin
        if (sst[j*NB + b] == 2) owners++;
        if (sst[j*NB + b] == 1) shared++;
        if ((sst[j*NB + b] != 0) != ssh[b][j]) begin errors++; $display("FAIL [%s] sharer bit %0d of block %0d disagrees with the cache", what, j, b); end
      end
      if (owners > 1 || (owners == 1 && shared > 0)) begin errors++; $display("FAIL [%s] invariant: block %0d has %0d owners and %0d sharers", what, b, owners, shared); end
      if (sdir[b] == 0 && (owners + shared) != 0) begin errors++; $display("FAIL [%s] invariant: uncached block %0d is cached", what, b); end
    end
  endtask

  logic [31:0] seed = 32'd5150;
  function automatic int rnd(input int n); seed = seed * 32'd1664525 + 32'd1013904223; return int'(seed[30:16]) % n; endfunction

  initial begin
    int blk, node, nops, wr_i, rn, rb, rw;  logic [31:0] wd;
    done = 0; errors = 0; r_msgs = 0; r_miss = 0; r_ops = 0;
    for (int i = 0; i < P*NB; i++) begin sst[i] = 0; sdat[i] = 0; end
    for (int i = 0; i < NB; i++) begin sdir[i] = 0; ssh[i] = '0; smem[i] = 32'hA0 + i; gval[i] = 32'hA0 + i; end
    repeat (2) @(negedge clk);  rst_n = 1;  repeat (2) @(negedge clk);

    if (P == 4 && NB >= 3) begin
      //        node wr blk data      hops msgs  what
      do_op(0, 0, 0, 0,          2, 2, "1: C0 read, dir U");
      do_op(0, 0, 0, 0,          0, 0, "2: C0 read hit");
      do_op(1, 0, 0, 0,          2, 2, "3: C1 read, dir S");
      do_op(2, 0, 0, 0,          2, 2, "4: C2 read, dir S");
      do_op(3, 1, 0, 32'hB1,     4, 8, "5: C3 write, 3 sharers: request + 3 inv + 3 ack + reply");
      do_op(3, 1, 0, 32'hB2,     0, 0, "6: C3 write hit in M");
      do_op(0, 0, 0, 0,          4, 4, "7: C0 read, dir M: fetch from C3");
      do_op(0, 1, 0, 32'hC3,     4, 4, "8: C0 write while sharing with C3: 1 inv + 1 ack");
      do_op(1, 1, 0, 32'hD4,     4, 4, "9: C1 write, dir M: fetch+invalidate C0");
      do_op(1, 0, 0, 0,          0, 0, "10: C1 read hit in M");
      do_op(2, 1, 0, 32'hE5,     4, 4, "11: C2 write, dir M");
      do_op(2, 0, 1, 0,          2, 2, "12: C2 read block 1");
      do_op(2, 1, 1, 32'hF6,     2, 2, "13: C2 write block 1: sole sharer upgrades, no invalidates");
      do_op(3, 1, 2, 32'h17,     2, 2, "14: C3 write block 2, dir U");
    end

    // random phase (sequential consistency per block): every node touches every block, or (SPARSE) block b is used only by three nodes
    tot_msgs = 0;  tot_miss = 0;  nops = (P == 4) ? 3000 : 4000;
    for (int i = 0; i < nops; i++) begin
      rb = rnd(NB);  rn = rnd(P);  rw = rnd(100);  wd = seed ^ 32'h5A5A5A5A;
      node = SPARSE ? ((rb * 3 + (rn % 3)) % P) : rn;
      do_op(node, rw < 35, rb, wd, -1, -1, $sformatf("random %0d", i));
    end
    r_msgs = tot_msgs;  r_miss = tot_miss;  r_ops = nops;
    done = 1;
  end
endmodule

module tb_directory_msi;
  wire d0, d1, d2, d3;  int e0, e1, e2, e3, m0, m1, m2, m3, x0, x1, x2, x3, o0, o1, o2, o3;
  dir_harness #(.P(4),  .NB(4), .LAT(2), .SPARSE(0)) h2  (.done(d0), .errors(e0), .r_msgs(m0), .r_miss(x0), .r_ops(o0));
  dir_harness #(.P(4),  .NB(4), .LAT(3), .SPARSE(0)) h3  (.done(d1), .errors(e1), .r_msgs(m1), .r_miss(x1), .r_ops(o1));
  dir_harness #(.P(4),  .NB(8), .LAT(2), .SPARSE(1)) s4  (.done(d2), .errors(e2), .r_msgs(m2), .r_miss(x2), .r_ops(o2));
  dir_harness #(.P(16), .NB(8), .LAT(2), .SPARSE(1)) s16 (.done(d3), .errors(e3), .r_msgs(m3), .r_miss(x3), .r_ops(o3));
  int errors;
  initial begin
    wait (d0 && d1 && d2 && d3);
    errors = e0 + e1 + e2 + e3;
    $display("random sharing, 4 nodes (every node touches every block): %0d misses in %0d operations, %0d messages = %0d.%02d per miss; a snooping bus would broadcast to 3 caches per miss",
             x0, o0, m0, m0 / x0, (m0 * 100 / x0) % 100);
    $display("sparse sharing, 16 nodes (each block shared by 3 nodes): %0d misses, %0d messages = %0d.%02d per miss, where a broadcast would reach 15 caches per miss",
             x3, m3, m3 / x3, (m3 * 100 / x3) % 100);
    if (!(m3 * 3 < x3 * 15)) begin errors++; $display("FAIL: directory traffic (%0d messages per miss) is not below a third of the broadcast traffic at 16 nodes", m3 / x3); end
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
