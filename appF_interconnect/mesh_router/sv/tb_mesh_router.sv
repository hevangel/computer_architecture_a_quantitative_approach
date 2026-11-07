`timescale 1ns/1ps
// A reusable harness around mesh_net: per-node injectors that obey the credit protocol, per-node ejection checkers (right destination, flit order,
// no interleaving of packets, exactly-once delivery, packet length), and a per-packet latency log.  Latency = cycle the tail flit is on the ejection
// link minus the cycle the head flit was on the injection link.
module mesh_harness #(parameter int NX = 4, parameter int NY = 4, parameter int DEPTH = 4) ();
  import mesh_pkg::*;
  localparam int NN = NX * NY, MAXF = 160, MAXP = 512;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic [NN-1:0] inj_valid = 0;  logic [NN*FW-1:0] inj_flit = 0;
  wire  [NN-1:0] inj_credit, ej_valid;  wire [NN*FW-1:0] ej_flit;  wire err_overflow;
  mesh_net #(.NX(NX), .NY(NY), .DEPTH(DEPTH)) dut (.*);

  logic [FW-1:0] fl_data [0:NN*MAXF-1];
  int fl_ready [0:NN*MAXF-1];
  int fl_cnt [0:NN-1], fl_ptr [0:NN-1], inj_cred [0:NN-1];
  int p_src [0:MAXP-1], p_dst [0:MAXP-1], p_len [0:MAXP-1];
  int inj_cyc [0:MAXP-1], ej_cyc [0:MAXP-1], p_done [0:MAXP-1], p_flits [0:MAXP-1];
  int cur_id [0:NN-1], nxt_seq [0:NN-1];
  int n_pkts = 0, delivered = 0, cyc = 0, errors = 0, ej_first = 1 << 30, ej_last = -1, node0_first = 1 << 30, node0_last = -1;

  initial begin
    for (int n = 0; n < NN; n++) begin fl_cnt[n] = 0; fl_ptr[n] = 0; inj_cred[n] = DEPTH; cur_id[n] = -1; nxt_seq[n] = 0; end
    repeat (3) @(negedge clk);  rst_n = 1;
  end

  function automatic int hops(input int s, input int d);
    int dx, dy;  dx = (s % NX) - (d % NX);  dy = (s / NX) - (d / NX);
    return ((dx < 0) ? -dx : dx) + ((dy < 0) ? -dy : dy);
  endfunction
  function automatic int zero_load(input int id); return 2 * (hops(p_src[id], p_dst[id]) + 1) + p_len[id] - 1; endfunction
  function automatic int latency(input int id);   return ej_cyc[id] - inj_cyc[id]; endfunction

  task automatic clear_all();
    n_pkts = 0;  delivered = 0;  ej_first = 1 << 30;  ej_last = -1;  node0_first = 1 << 30;  node0_last = -1;
    for (int n = 0; n < NN; n++) begin fl_cnt[n] = 0; fl_ptr[n] = 0; end
    for (int i = 0; i < MAXP; i++) begin p_done[i] = 0; p_flits[i] = 0; end
  endtask
  task automatic add_pkt(input int src, input int dst, input int len, input int t);
    logic [FW-1:0] f;  logic [1:0] ty;  int id, base;
    id = n_pkts;  n_pkts++;  p_src[id] = src;  p_dst[id] = dst;  p_len[id] = len;  base = cyc + 2 + t;
    for (int i = 0; i < len; i++) begin
      ty = (len == 1) ? T_SINGLE : (i == 0) ? T_HEAD : (i == len - 1) ? T_TAIL : T_BODY;
      f = '0;  f[FW-1:FW-2] = ty;  f[15:0] = id[15:0];  f[23:16] = i[7:0];
      if (i == 0) begin f[27:24] = (dst % NX); f[31:28] = (dst / NX); end
      fl_data[src*MAXF + fl_cnt[src]] = f;
      fl_ready[src*MAXF + fl_cnt[src]] = (i == 0) ? base : 0;
      fl_cnt[src]++;
    end
  endtask
  // run until every packet is delivered (or the timeout expires), then let the network settle
  task automatic run(input int timeout, input string what);
    int t;  t = 0;
    while (delivered < n_pkts && t < timeout) begin @(negedge clk); t++; end
    if (delivered < n_pkts) begin errors++; $display("FAIL [%0dx%0d D=%0d] %s: only %0d of %0d packets delivered in %0d cycles (deadlock?)", NX, NY, DEPTH, what, delivered, n_pkts, timeout); end
    repeat (10) @(negedge clk);
  endtask

  // ---- injectors and ejection checkers (once per cycle, in the middle of the cycle) --------------------------------------
  always @(negedge clk) if (rst_n) begin
    for (int n = 0; n < NN; n++) begin
      int k;  logic [FW-1:0] f;
      inj_valid[n] = 1'b0;
      k = n * MAXF + fl_ptr[n];
      if (fl_ptr[n] < fl_cnt[n] && cyc >= fl_ready[k] && inj_cred[n] > 0) begin
        f = fl_data[k];
        inj_valid[n] = 1'b1;  inj_flit[n*FW +: FW] = f;  inj_cred[n]--;
        if (f[FW-1:FW-2] == T_HEAD || f[FW-1:FW-2] == T_SINGLE) inj_cyc[int'(f[15:0])] = cyc;
        fl_ptr[n]++;
      end
      if (inj_credit[n]) inj_cred[n]++;                                     // a credit pulse seen this cycle is usable from the next cycle
    end
    for (int n = 0; n < NN; n++) if (ej_valid[n]) begin
      logic [FW-1:0] f;  logic [1:0] ty;  int id, sq;
      f = ej_flit[n*FW +: FW];  ty = f[FW-1:FW-2];  id = int'(f[15:0]);  sq = int'(f[23:16]);
      if (cyc < ej_first) ej_first = cyc;  ej_last = cyc;
      if (n == 0) begin if (cyc < node0_first) node0_first = cyc; node0_last = cyc; end
      if (cur_id[n] < 0) begin                                             // expecting a head
        if (ty != T_HEAD && ty != T_SINGLE) begin errors++; $display("FAIL node %0d: body/tail flit of packet %0d without a head", n, id); end
        else begin
          if (int'(f[27:24]) != (n % NX) || int'(f[31:28]) != (n / NX) || p_dst[id] != n) begin errors++; $display("FAIL packet %0d misrouted to node %0d", id, n); end
          if (sq != 0) begin errors++; $display("FAIL packet %0d head has index %0d", id, sq); end
          cur_id[n] = id;  nxt_seq[n] = 1;  p_flits[id] = 1;
          if (ty == T_SINGLE) begin cur_id[n] = -1; end
        end
      end else begin                                                       // inside a packet
        if (id != cur_id[n]) begin errors++; $display("FAIL node %0d: flit of packet %0d interleaved into packet %0d", n, id, cur_id[n]); end
        else if (ty == T_HEAD || ty == T_SINGLE) begin errors++; $display("FAIL node %0d: second head inside packet %0d", n, id); end
        else begin
          if (sq != nxt_seq[n]) begin errors++; $display("FAIL packet %0d flit order: got %0d expected %0d", id, sq, nxt_seq[n]); end
          nxt_seq[n]++;  p_flits[id]++;
          if (ty == T_TAIL) cur_id[n] = -1;
        end
      end
      if (cur_id[n] < 0 && (ty == T_TAIL || ty == T_SINGLE)) begin         // packet complete
        if (p_flits[id] != p_len[id]) begin errors++; $display("FAIL packet %0d delivered with %0d flits, expected %0d", id, p_flits[id], p_len[id]); end
        if (p_done[id] != 0) begin errors++; $display("FAIL packet %0d delivered twice", id); end
        p_done[id]++;  ej_cyc[id] = cyc;  delivered++;
      end
    end
    cyc++;
  end
  always @(posedge clk) if (rst_n && err_overflow) begin errors++; $display("FAIL [%0dx%0d D=%0d]: input FIFO overflow (credit protocol violated)", NX, NY, DEPTH); end
endmodule

module tb_mesh_router;
  import mesh_pkg::*;
  int errors = 0;
  task automatic expect_i(input string what, input int got, input int exp_v);
    if (got != exp_v) begin errors++; $display("FAIL %s: got %0d expected %0d", what, got, exp_v); end
  endtask

  // ---------------------------------------------------------------------------------------------------------------
  // 1. Routing table of a single router at (1,1) in a 3x3 mesh: dimension-order (X first), a flit for the east column goes East even when it also has to
  //    move in Y.
  logic clk = 0, ru_rst = 0;
  always #5 clk = ~clk;
  logic [4:0] ru_in_v = 0, ru_in_cr, ru_out_v, ru_out_cr = 0;  logic [5*FW-1:0] ru_in_f = 0, ru_out_f;  logic ru_err;
  mesh_router #(.X(1), .Y(1), .NX(3), .NY(3), .DEPTH(4)) ru (.clk, .rst_n(ru_rst), .in_valid(ru_in_v), .in_flit(ru_in_f), .in_credit(ru_in_cr),
                                                              .out_valid(ru_out_v), .out_flit(ru_out_f), .out_credit(ru_out_cr), .err_overflow(ru_err));
  task automatic route_case(input int in_port, input int dx, input int dy, input int exp_port);
    logic [FW-1:0] f;
    f = '0;  f[FW-1:FW-2] = T_SINGLE;  f[15:0] = 16'hABCD;  f[27:24] = dx[3:0];  f[31:28] = dy[3:0];
    @(negedge clk);  ru_rst = 0;  @(negedge clk);  @(negedge clk);  ru_rst = 1;
    @(negedge clk);  ru_in_v = 5'(1 << in_port);  ru_in_f[in_port*FW +: FW] = f;      // on the link during this cycle (cycle c)
    @(negedge clk);  ru_in_v = 0;                                                      // cycle c+1: the router switches it
    @(negedge clk);                                                                    // cycle c+2: it is on the output link
    if (ru_out_v !== 5'(1 << exp_port)) begin errors++; $display("FAIL route: in %0d dest (%0d,%0d): out_valid=%b, expected port %0d", in_port, dx, dy, ru_out_v, exp_port); end
    else if (ru_out_f[exp_port*FW +: FW] !== f) begin errors++; $display("FAIL route: flit corrupted"); end
  endtask

  // ---------------------------------------------------------------------------------------------------------------
  mesh_harness #(.NX(4), .NY(4), .DEPTH(4)) m44 ();
  mesh_harness #(.NX(4), .NY(1), .DEPTH(2)) c2 ();
  mesh_harness #(.NX(4), .NY(1), .DEPTH(3)) c3 ();
  mesh_harness #(.NX(4), .NY(1), .DEPTH(4)) c4 ();
  mesh_harness #(.NX(4), .NY(1), .DEPTH(5)) c5 ();

  logic [31:0] seed = 32'd1992;
  function automatic int rnd(input int n); seed = seed * 32'd1664525 + 32'd1013904223; return int'(seed[30:16]) % n; endfunction

  initial begin
    int zl, sum_lat, sum_zl, mx, lat2, lat3, lat4, lat5;
    repeat (6) @(negedge clk);

    // ---- 1. routing ---------------------------------------------------------------------------------------------
    //  from Local:     dest (2,1) E   (0,1) W   (1,0) N   (1,2) S   (1,1) L   (2,0) E   (0,2) W   (2,2) E   (0,0) W
    route_case(P_L, 2, 1, P_E);  route_case(P_L, 0, 1, P_W);  route_case(P_L, 1, 0, P_N);  route_case(P_L, 1, 2, P_S);  route_case(P_L, 1, 1, P_L);
    route_case(P_L, 2, 0, P_E);  route_case(P_L, 0, 2, P_W);  route_case(P_L, 2, 2, P_E);  route_case(P_L, 0, 0, P_W);
    //  from other inputs (a packet arriving from the West keeps going East, turns South, or ejects; from the North it can turn East/West/South)
    route_case(P_W, 2, 1, P_E);  route_case(P_W, 1, 2, P_S);  route_case(P_W, 1, 1, P_L);  route_case(P_N, 0, 2, P_W);  route_case(P_N, 1, 2, P_S);
    $display("routing: 14 destination/input combinations routed X-first (dimension order)");

    // ---- 2. zero-load latency on the 4x4 mesh (D = 4): 2 (hops + 1) + flits - 1 -------------------------------------------
    m44.clear_all();  m44.add_pkt(0, 15, 5, 0);  m44.run(200, "corner to corner");
    expect_i("(0,0)->(3,3) 5 flits: hops", m44.hops(0, 15), 6);
    expect_i("(0,0)->(3,3) 5 flits: latency", m44.latency(0), 2 * 7 + 4);
    m44.clear_all();  m44.add_pkt(0, 1, 1, 0);   m44.run(200, "neighbour");   expect_i("(0,0)->(1,0) 1 flit latency", m44.latency(0), 4);
    m44.clear_all();  m44.add_pkt(5, 5, 3, 0);   m44.run(200, "self");        expect_i("(1,1)->(1,1) 3 flits latency", m44.latency(0), 4);
    m44.clear_all();  m44.add_pkt(3, 8, 2, 0);   m44.run(200, "mixed");       expect_i("(3,0)->(0,2) 2 flits latency", m44.latency(0), 2 * 6 + 1);
    $display("zero-load: corner-to-corner 5-flit packet = %0d cycles (2 x 7 routers + 4), neighbour = 4, self = 4", 18);

    // ---- 3. credit loop: one 40-flit packet over a 4-node chain (4 routers) ---------------------------------------------------
    //  full rate needs buffering >= the 4-cycle credit round trip -> latency = 2 x 4 + 39 = 47 for D >= 4; smaller buffers throttle the link
    c2.clear_all(); c2.add_pkt(0, 3, 40, 0); c2.run(1000, "D=2");  lat2 = c2.latency(0);
    c3.clear_all(); c3.add_pkt(0, 3, 40, 0); c3.run(1000, "D=3");  lat3 = c3.latency(0);
    c4.clear_all(); c4.add_pkt(0, 3, 40, 0); c4.run(1000, "D=4");  lat4 = c4.latency(0);
    c5.clear_all(); c5.add_pkt(0, 3, 40, 0); c5.run(1000, "D=5");  lat5 = c5.latency(0);
    $display("credit loop, 40-flit packet over 4 routers: ideal %0d cycles;  FIFO depth 2 -> %0d, 3 -> %0d, 4 -> %0d, 5 -> %0d", 2 * 4 + 39, lat2, lat3, lat4, lat5);
    expect_i("D=4 sustains one flit per cycle", lat4, 2 * 4 + 39);
    expect_i("D=5 sustains one flit per cycle", lat5, 2 * 4 + 39);
    if (!(lat3 > lat4)) begin errors++; $display("FAIL: depth 3 (%0d) should be slower than depth 4 (%0d)", lat3, lat4); end
    if (!(lat2 > lat3)) begin errors++; $display("FAIL: depth 2 (%0d) should be slower than depth 3 (%0d)", lat2, lat3); end

    // ---- 4. hot spot: all 15 other nodes send a 4-flit packet to node 0 at once ------------------------------------------------------
    m44.clear_all();
    for (int s = 1; s < 16; s++) m44.add_pkt(s, 0, 4, 0);
    m44.run(2000, "hot spot");
    expect_i("hot spot: packets delivered", m44.delivered, 15);
    if (m44.node0_last - m44.node0_first < 15 * 4 - 1) begin errors++; $display("FAIL hot spot: 60 flits ejected in only %0d cycles (the port moves one flit per cycle)", m44.node0_last - m44.node0_first + 1); end
    mx = 0;  for (int i = 0; i < 15; i++) if (m44.latency(i) > mx) mx = m44.latency(i);
    $display("hot spot: 60 flits through one ejection port: first ejection t=%0d, last t=%0d (%0d cycles for 60 flits), worst packet latency %0d",
             m44.node0_first, m44.node0_last, m44.node0_last - m44.node0_first + 1, mx);

    // ---- 5. random traffic: 16 nodes x 8 packets (1..6 flits), random destinations and start times ---------------------------------
    m44.clear_all();
    for (int s = 0; s < 16; s++) for (int k = 0; k < 8; k++) begin
      int dst, len, tt;
      dst = rnd(16);  len = 1 + rnd(6);  tt = rnd(200);                    // explicit order: the VHDL testbench draws the same sequence
      m44.add_pkt(s, dst, len, tt);
    end
    m44.run(20000, "random traffic");
    expect_i("random: packets delivered", m44.delivered, 128);
    sum_lat = 0;  sum_zl = 0;
    for (int i = 0; i < 128; i++) begin
      if (m44.latency(i) < m44.zero_load(i)) begin errors++; $display("FAIL packet %0d: latency %0d below the zero-load bound %0d", i, m44.latency(i), m44.zero_load(i)); end
      sum_lat += m44.latency(i);  sum_zl += m44.zero_load(i);
    end
    $display("random: 128 packets delivered, average latency %0d.%02d cycles vs %0d.%02d at zero load (contention factor %0d.%02d)",
             sum_lat / 128, (sum_lat * 100 / 128) % 100, sum_zl / 128, (sum_zl * 100 / 128) % 100, sum_lat / sum_zl, (sum_lat * 100 / sum_zl) % 100);

    errors += m44.errors + c2.errors + c3.errors + c4.errors + c5.errors;
    if (ru_err) errors++;
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
