`timescale 1ns/1ps
// Torus 4x4 (ring distance = the shorter way round, ties go East / South), NVC = 2: class 0 = VC 0, class 1 = VC 1.
// Hand-derived expectations (see README):
//   routing and VC classes of single routers (router_rig): the output port is the shorter way round each ring, X before Y, a tie goes East / South;
//        the output VC is class 1 exactly when the hop crosses the dateline link (East from x = 3, West from x = 0, South from y = 3, North from y = 0) or when the packet
//        is already in class 1 and stays in the same ring; entering a new dimension (from the Local port or after a turn) restarts at class 0; ejection takes any VC (lowest free).
//   zero load: 3K + F - 1 with K = ring distance in X + ring distance in Y + 1 routers: (0,0)->(3,0) 5 flits = 3*2+4 = 10 (the mesh route would need 4 routers = 16),
//        (0,0)->(3,3) = 3*3+4 = 13 (mesh: 25), (1,1)->(3,3) = 3*5+4 = 19.
//   deadlock: on a ring of 4 every node sends a 20-flit packet two hops East.  With ONE virtual channel and no dateline every packet holds its first link and waits for the next one,
//        which is held by the next packet: the packets never arrive.  With the dateline classes (2 VCs) the same traffic is delivered.  The same holds for the 4x4 torus under the
//        "shift by (2,2)" pattern with 16-flit packets.
// Ejection checkers work per (node, virtual channel); injection obeys per-VC credits.

// one router of the 4x4 torus with its ports exposed, to check routing and the output virtual channel
module router_rig #(parameter int X = 0, parameter int Y = 0) ();
  import vc_pkg::*;
  int errors = 0;
  logic clk = 0, rst = 0;
  always #5 clk = ~clk;
  logic [4:0] in_v = 0, in_cr, out_v, out_cr = 0;  logic [5*FW-1:0] in_f = 0, out_f;  logic err;  logic [9:0] in_crvc, out_crvc = 0;
  torus_router #(.X(X), .Y(Y), .NX(4), .NY(4), .NVC(2), .DEPTH(4), .DATELINE(1'b1)) r (.clk, .rst_n(rst), .in_valid(in_v), .in_flit(in_f), .in_credit_v(in_cr), .in_credit_vc(in_crvc),
      .out_valid(out_v), .out_flit(out_f), .out_credit_v(out_cr), .out_credit_vc(out_crvc), .err_overflow(err));
  task automatic probe(input int in_port, input int in_vc, input int dx, input int dy, input int exp_port, input int exp_vc);
    logic [FW-1:0] f, e;
    f = '0;  f[FW-1:FW-2] = T_SINGLE;  f[33:32] = in_vc[1:0];  f[15:0] = 16'hABCD;  f[27:24] = dx[3:0];  f[31:28] = dy[3:0];
    e = f;  e[33:32] = exp_vc[1:0];
    @(negedge clk);  rst = 0;  @(negedge clk);  @(negedge clk);  rst = 1;
    @(negedge clk);  in_v = 5'(1 << in_port);  in_f[in_port*FW +: FW] = f;           // on the link during cycle c
    @(negedge clk);  in_v = 0;                                                        // c+1: VC allocation
    @(negedge clk);                                                                   // c+2: switch allocation
    @(negedge clk);                                                                   // c+3: on the output link
    if (out_v !== 5'(1 << exp_port)) begin errors++; $display("FAIL router (%0d,%0d): in %0d vc %0d dest (%0d,%0d): out_valid=%b, expected port %0d", X, Y, in_port, in_vc, dx, dy, out_v, exp_port); end
    else if (out_f[exp_port*FW +: FW] !== e) begin errors++; $display("FAIL router (%0d,%0d): in %0d vc %0d dest (%0d,%0d): output vc %0d, expected %0d", X, Y, in_port, in_vc, dx, dy, int'(out_f[exp_port*FW + 32 +: 2]), exp_vc); end
  endtask
endmodule

module torus_harness #(parameter int NX = 4, parameter int NY = 4, parameter int NVC = 2, parameter int DEPTH = 4, parameter bit DATELINE = 1'b1) ();
  import vc_pkg::*;
  localparam int NN = NX * NY, MAXF = 200, MAXP = 512;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic [NN-1:0] inj_valid = 0;  logic [NN*FW-1:0] inj_flit = 0;
  wire  [NN-1:0] inj_credit_v, ej_valid;  wire [NN*2-1:0] inj_credit_vc;  wire [NN*FW-1:0] ej_flit;  wire err_overflow;
  torus_net #(.NX(NX), .NY(NY), .NVC(NVC), .DEPTH(DEPTH), .DATELINE(DATELINE)) dut (.*);

  logic [FW-1:0] fl_data [0:NN*NVC*MAXF-1];
  int fl_ready [0:NN*NVC*MAXF-1];
  int fl_cnt [0:NN*NVC-1], fl_ptr [0:NN*NVC-1], inj_cred [0:NN*NVC-1], inj_rr [0:NN-1];
  int p_src [0:MAXP-1], p_dst [0:MAXP-1], p_len [0:MAXP-1], p_vc [0:MAXP-1];
  int inj_cyc [0:MAXP-1], ej_cyc [0:MAXP-1], p_done [0:MAXP-1], p_flits [0:MAXP-1], p_ready [0:MAXP-1];
  int cur_id [0:NN*NVC-1], nxt_seq [0:NN*NVC-1];
  int n_pkts = 0, delivered = 0, cyc = 0, errors = 0, ej_first = 1 << 30, ej_last = -1, node0_first = 1 << 30, node0_last = -1, t_start = 0;

  initial begin
    for (int i = 0; i < NN*NVC; i++) begin fl_cnt[i] = 0; fl_ptr[i] = 0; inj_cred[i] = DEPTH; cur_id[i] = -1; nxt_seq[i] = 0; end
    for (int n = 0; n < NN; n++) inj_rr[n] = NVC - 1;
    repeat (3) @(negedge clk);  rst_n = 1;
  end

  function automatic int ring(input int a, input int b, input int n);          // distance along the shorter way round a ring of n nodes
    int d;  d = ((a - b) % n + n) % n;
    return (d < n - d) ? d : n - d;
  endfunction
  function automatic int hops(input int s, input int d);   return ring(s % NX, d % NX, NX) + ring(s / NX, d / NX, NY); endfunction
  function automatic int mesh_hops(input int s, input int d);
    int dx, dy;  dx = (s % NX) - (d % NX);  dy = (s / NX) - (d / NX);
    return ((dx < 0) ? -dx : dx) + ((dy < 0) ? -dy : dy);
  endfunction
  function automatic int zero_load(input int id); return 3 * (hops(p_src[id], p_dst[id]) + 1) + p_len[id] - 1; endfunction
  function automatic int latency(input int id);   return ej_cyc[id] - inj_cyc[id]; endfunction
  function automatic int done_at(input int id);   return ej_cyc[id] - t_start;     endfunction     // completion time counted from the start of the run

  task automatic clear_all();
    n_pkts = 0;  delivered = 0;  ej_first = 1 << 30;  ej_last = -1;  node0_first = 1 << 30;  node0_last = -1;  t_start = cyc + 2;
    for (int i = 0; i < NN*NVC; i++) begin fl_cnt[i] = 0; fl_ptr[i] = 0; end
    for (int i = 0; i < MAXP; i++) begin p_done[i] = 0; p_flits[i] = 0; end
  endtask
  task automatic add_pkt(input int src, input int dst, input int len, input int t, input int vc);
    logic [FW-1:0] f;  logic [1:0] ty;  int id, base, q;
    id = n_pkts;  n_pkts++;  p_src[id] = src;  p_dst[id] = dst;  p_len[id] = len;  p_vc[id] = vc;  base = cyc + 2 + t;  p_ready[id] = base;
    q = src * NVC + vc;
    for (int i = 0; i < len; i++) begin
      ty = (len == 1) ? T_SINGLE : (i == 0) ? T_HEAD : (i == len - 1) ? T_TAIL : T_BODY;
      f = '0;  f[FW-1:FW-2] = ty;  f[33:32] = vc[1:0];  f[15:0] = id[15:0];  f[23:16] = i[7:0];
      if (i == 0) begin f[27:24] = (dst % NX); f[31:28] = (dst / NX); end
      fl_data[q*MAXF + fl_cnt[q]] = f;
      fl_ready[q*MAXF + fl_cnt[q]] = (i == 0) ? base : 0;
      fl_cnt[q]++;
    end
  endtask
  task automatic run(input int timeout, input string what);
    int t;  t = 0;
    while (delivered < n_pkts && t < timeout && errors == 0) begin @(negedge clk); t++; end
    if (delivered < n_pkts && errors == 0) begin errors++; $display("FAIL [%0dx%0d torus VC=%0d D=%0d] %s: only %0d of %0d packets delivered in %0d cycles (deadlock?)", NX, NY, NVC, DEPTH, what, delivered, n_pkts, timeout); end
    repeat (10) @(negedge clk);
  endtask

  // run without treating a timeout as an error (used to demonstrate a deadlock); returns the number of packets delivered
  task automatic run_quiet(input int timeout, output int got);
    int t;  t = 0;
    while (delivered < n_pkts && t < timeout && errors == 0) begin @(negedge clk); t++; end
    got = delivered;
  endtask

  // ---- injectors (one flit per node per cycle, any virtual channel with a flit and a credit, round-robin) and ejection checkers ----
  always @(negedge clk) if (rst_n) begin
    for (int n = 0; n < NN; n++) begin
      int k, q, v, sent;  logic [FW-1:0] f;
      inj_valid[n] = 1'b0;  sent = 0;
      for (int j = 1; j <= NVC; j++) begin
        v = (inj_rr[n] + j) % NVC;  q = n * NVC + v;  k = q * MAXF + fl_ptr[q];
        if (!sent && fl_ptr[q] < fl_cnt[q] && cyc >= fl_ready[k] && inj_cred[q] > 0) begin
          f = fl_data[k];
          inj_valid[n] = 1'b1;  inj_flit[n*FW +: FW] = f;  inj_cred[q]--;  sent = 1;  inj_rr[n] = v;
          if (f[FW-1:FW-2] == T_HEAD || f[FW-1:FW-2] == T_SINGLE) inj_cyc[int'(f[15:0])] = cyc;
          fl_ptr[q]++;
        end
      end
      if (inj_credit_v[n]) inj_cred[n*NVC + int'(inj_credit_vc[2*n +: 2])]++;       // usable from the next cycle
    end
    for (int n = 0; n < NN; n++) if (ej_valid[n]) begin
      logic [FW-1:0] f;  logic [1:0] ty;  int id, sq, q;
      f = ej_flit[n*FW +: FW];  ty = f[FW-1:FW-2];  id = int'(f[15:0]);  sq = int'(f[23:16]);  q = n * NVC + int'(f[33:32]);
      if (int'(f[33:32]) >= NVC) begin errors++; $display("FAIL node %0d: flit on nonexistent VC %0d", n, int'(f[33:32])); end
      else begin
      if (cyc < ej_first) ej_first = cyc;  ej_last = cyc;
      if (n == 0) begin if (cyc < node0_first) node0_first = cyc; node0_last = cyc; end
      if (cur_id[q] < 0) begin                                             // expecting a head
        if (ty != T_HEAD && ty != T_SINGLE) begin errors++; $display("FAIL node %0d: body/tail flit of packet %0d without a head", n, id); end
        else begin
          if (int'(f[27:24]) != (n % NX) || int'(f[31:28]) != (n / NX) || p_dst[id] != n) begin errors++; $display("FAIL packet %0d misrouted to node %0d", id, n); end
          if (sq != 0) begin errors++; $display("FAIL packet %0d head has index %0d", id, sq); end
          cur_id[q] = id;  nxt_seq[q] = 1;  p_flits[id] = 1;
          if (ty == T_SINGLE) cur_id[q] = -1;
        end
      end else begin                                                       // inside a packet of this virtual channel
        if (id != cur_id[q]) begin errors++; $display("FAIL node %0d: flit of packet %0d interleaved into packet %0d inside one virtual channel", n, id, cur_id[q]); end
        else if (ty == T_HEAD || ty == T_SINGLE) begin errors++; $display("FAIL node %0d: second head inside packet %0d", n, id); end
        else begin
          if (sq != nxt_seq[q]) begin errors++; $display("FAIL packet %0d flit order: got %0d expected %0d", id, sq, nxt_seq[q]); end
          nxt_seq[q]++;  p_flits[id]++;
          if (ty == T_TAIL) cur_id[q] = -1;
        end
      end
      if (cur_id[q] < 0 && (ty == T_TAIL || ty == T_SINGLE)) begin         // packet complete
        if (p_flits[id] != p_len[id]) begin errors++; $display("FAIL packet %0d delivered with %0d flits, expected %0d", id, p_flits[id], p_len[id]); end
        if (p_done[id] != 0) begin errors++; $display("FAIL packet %0d delivered twice", id); end
        p_done[id]++;  ej_cyc[id] = cyc;  delivered++;
      end
      end
    end
    cyc++;
  end
  bit ovf_seen = 0;
  always @(posedge clk) if (rst_n && err_overflow && !ovf_seen) begin ovf_seen = 1; errors++; $display("FAIL [%0dx%0d VC=%0d D=%0d]: input FIFO overflow (credit protocol violated)", NX, NY, NVC, DEPTH); end
endmodule


module tb_torus_dateline;
  import vc_pkg::*;
  int errors = 0;
  task automatic expect_i(input string what, input int got, input int exp_v);
    if (got != exp_v) begin errors++; $display("FAIL %s: got %0d expected %0d", what, got, exp_v); end
  endtask

  router_rig #(.X(0), .Y(0)) a00 ();
  router_rig #(.X(3), .Y(0)) a30 ();
  router_rig #(.X(1), .Y(0)) a10 ();
  router_rig #(.X(2), .Y(0)) a20 ();
  router_rig #(.X(0), .Y(3)) a03 ();

  torus_harness #(.NX(4), .NY(4), .NVC(2), .DEPTH(4), .DATELINE(1)) z ();          // zero load
  torus_harness #(.NX(4), .NY(1), .NVC(2), .DEPTH(4), .DATELINE(1)) ring2 ();      // ring, dateline classes
  torus_harness #(.NX(4), .NY(1), .NVC(1), .DEPTH(4), .DATELINE(0)) ring1 ();      // ring, one VC (deadlocks)
  torus_harness #(.NX(4), .NY(4), .NVC(2), .DEPTH(4), .DATELINE(1)) sh2 ();        // shift by (2,2), dateline classes
  torus_harness #(.NX(4), .NY(4), .NVC(1), .DEPTH(4), .DATELINE(0)) sh1 ();        // shift by (2,2), one VC (deadlocks)
  torus_harness #(.NX(4), .NY(4), .NVC(2), .DEPTH(4), .DATELINE(1)) rn2 ();        // random traffic
  torus_harness #(.NX(4), .NY(4), .NVC(4), .DEPTH(2), .DATELINE(1)) rn4 ();        // random traffic, 2 VCs per class

  logic [31:0] seed = 32'd1992;
  function automatic int rnd(input int n); seed = seed * 32'd1664525 + 32'd1013904223; return int'(seed[30:16]) % n; endfunction

  initial begin
    int got, t_ring, t_shift, sum2, sum4, zl2, th, mh, lat_sum_zl;
    repeat (6) @(negedge a00.clk);

    // ---- 1. routing and dateline classes of single routers ----
    //  router (0,0): from Local, VC 0
    a00.probe(P_L, 0, 1, 0, P_E, 0);  a00.probe(P_L, 0, 2, 0, P_E, 0);  a00.probe(P_L, 0, 3, 0, P_W, 1);          // 1 East, tie East, 3 = 1 West over the wrap-around (dateline) link -> class 1
    a00.probe(P_L, 0, 0, 1, P_S, 0);  a00.probe(P_L, 0, 0, 2, P_S, 0);  a00.probe(P_L, 0, 0, 3, P_N, 1);          // 1 South, tie South, 1 North over the wrap-around -> class 1
    a00.probe(P_L, 0, 3, 3, P_W, 1);  a00.probe(P_L, 0, 2, 3, P_E, 0);  a00.probe(P_L, 0, 0, 0, P_L, 0);          // X first; ejection takes the lowest free VC
    //  router (3,0): East is the wrap-around link
    a30.probe(P_L, 0, 0, 0, P_E, 1);  a30.probe(P_W, 0, 0, 0, P_E, 1);  a30.probe(P_W, 1, 1, 0, P_E, 1);           // crossing the dateline always ends in class 1
    a30.probe(P_W, 0, 3, 2, P_S, 0);  a30.probe(P_W, 1, 3, 2, P_S, 0);                                              // turning into the Y ring restarts at class 0 (even from class 1)
    //  router (1,0): no wrap-around link; the class is kept inside the ring
    a10.probe(P_W, 1, 3, 0, P_E, 1);  a10.probe(P_W, 0, 3, 0, P_E, 0);  a10.probe(P_W, 1, 1, 0, P_L, 0);
    //  router (2,0): East is not the wrap-around link (x = 2); a tie goes East
    a20.probe(P_L, 0, 3, 0, P_E, 0);  a20.probe(P_W, 1, 0, 0, P_E, 1);
    //  router (0,3): South is the wrap-around link of the Y ring
    a03.probe(P_L, 0, 0, 0, P_S, 1);  a03.probe(P_N, 0, 0, 1, P_S, 1);
    errors += a00.errors + a30.errors + a10.errors + a20.errors + a03.errors;
    if (errors != 0) begin $display("TEST FAILED: %0d errors in the routing/dateline-class checks", errors); $finish; end
    $display("routing: 22 router/input/destination combinations checked (shorter way round each ring, X first, dateline class on the output VC)");

    // ---- 2. zero-load latency 3K + F - 1 with ring distances ----
    z.clear_all();  z.add_pkt(0, 3, 5, 0, 0);    z.run(200, "wrap East");     expect_i("(0,0)->(3,0) 5 flits", z.latency(0), 3 * 2 + 4);
    z.clear_all();  z.add_pkt(0, 2, 5, 0, 0);    z.run(200, "tie");           expect_i("(0,0)->(2,0) 5 flits", z.latency(0), 3 * 3 + 4);
    z.clear_all();  z.add_pkt(0, 15, 5, 0, 1);   z.run(200, "corner");        expect_i("(0,0)->(3,3) 5 flits", z.latency(0), 3 * 3 + 4);
    z.clear_all();  z.add_pkt(5, 15, 5, 0, 0);   z.run(200, "diagonal");      expect_i("(1,1)->(3,3) 5 flits", z.latency(0), 3 * 5 + 4);
    z.clear_all();  z.add_pkt(12, 0, 5, 0, 0);   z.run(200, "wrap South");    expect_i("(0,3)->(0,0) 5 flits", z.latency(0), 3 * 2 + 4);
    z.clear_all();  z.add_pkt(5, 5, 3, 0, 0);    z.run(200, "self");          expect_i("(1,1)->(1,1) 3 flits", z.latency(0), 5);
    $display("zero-load: (0,0)->(3,0) = 10 cycles (mesh would take 16), (0,0)->(3,3) = 13 (mesh 25), (1,1)->(3,3) = 19");

    // ---- 3. deadlock on a ring: every node sends a 20-flit packet two hops East ----
    ring2.clear_all();  for (int s = 0; s < 4; s++) ring2.add_pkt(s, (s + 2) % 4, 20, 0, 0);
    ring2.run(3000, "ring with dateline");  expect_i("ring with dateline classes: packets delivered", ring2.delivered, 4);  t_ring = ring2.ej_last - ring2.t_start;
    ring1.clear_all();  for (int s = 0; s < 4; s++) ring1.add_pkt(s, (s + 2) % 4, 20, 0, 0);
    ring1.run_quiet(3000, got);
    if (got >= 4) begin errors++; $display("FAIL: the ring without virtual-channel classes should deadlock but delivered %0d packets", got); end
    $display("ring of 4, every node sends 20 flits two hops East: 1 VC delivers %0d of 4 packets in 3000 cycles (DEADLOCK); 2 VCs with the dateline deliver all 4 by cycle %0d", got, t_ring);

    // ---- 4. the same on the 4x4 torus: shift by (2,2), 16-flit packets ----
    sh2.clear_all();  for (int s = 0; s < 16; s++) sh2.add_pkt(s, ((s % 4 + 2) % 4) + 4 * ((s / 4 + 2) % 4), 16, 0, 0);
    sh2.run(5000, "shift with dateline");  expect_i("shift (2,2) with dateline classes: packets delivered", sh2.delivered, 16);  t_shift = sh2.ej_last - sh2.t_start;
    sh1.clear_all();  for (int s = 0; s < 16; s++) sh1.add_pkt(s, ((s % 4 + 2) % 4) + 4 * ((s / 4 + 2) % 4), 16, 0, 0);
    sh1.run_quiet(5000, got);
    if (got >= 16) begin errors++; $display("FAIL: the torus with one VC and no dateline should deadlock under shift (2,2) but delivered %0d packets", got); end
    $display("4x4 torus, shift by (2,2), 16-flit packets: 1 VC delivers %0d of 16 (DEADLOCK); 2 VCs with the dateline deliver all 16 by cycle %0d", got, t_shift);

    // ---- 5. random traffic: 16 nodes x 12 packets of 1..6 flits ----
    rn2.clear_all();  rn4.clear_all();
    for (int s = 0; s < 16; s++) for (int k = 0; k < 12; k++) begin
      int dst, len, tt, vc;
      dst = rnd(16);  len = 1 + rnd(6);  tt = rnd(40);  vc = rnd(4);              // explicit order: the VHDL testbench draws the same sequence
      rn2.add_pkt(s, dst, len, tt, vc % 2);  rn4.add_pkt(s, dst, len, tt, vc);
    end
    rn2.run(40000, "random 2 VC");  rn4.run(40000, "random 4 VC");
    expect_i("random 2 VC: packets delivered", rn2.delivered, 192);
    expect_i("random 4 VC: packets delivered", rn4.delivered, 192);
    sum2 = 0;  sum4 = 0;  th = 0;  mh = 0;  lat_sum_zl = 0;
    for (int i = 0; i < 192; i++) begin
      if (rn2.latency(i) < rn2.zero_load(i) || rn4.latency(i) < rn4.zero_load(i)) begin errors++; $display("FAIL packet %0d: latency below the zero-load bound", i); end
      sum2 += rn2.latency(i);  sum4 += rn4.latency(i);  th += rn2.hops(rn2.p_src[i], rn2.p_dst[i]);  mh += rn2.mesh_hops(rn2.p_src[i], rn2.p_dst[i]);  lat_sum_zl += rn2.zero_load(i);
    end
    if (!(th < mh)) begin errors++; $display("FAIL: the torus routes should be shorter than the mesh routes (%0d vs %0d hops)", th, mh); end
    $display("random traffic, 192 packets: %0d.%02d hops on average on the torus against %0d.%02d on a mesh;  average latency %0d.%02d (2 VC x 4, zero-load average %0d.%02d), %0d.%02d (4 VC x 2); all delivered by cycle %0d / %0d",
             th / 192, (th * 100 / 192) % 100, mh / 192, (mh * 100 / 192) % 100, sum2 / 192, (sum2 * 100 / 192) % 100, lat_sum_zl / 192, (lat_sum_zl * 100 / 192) % 100,
             sum4 / 192, (sum4 * 100 / 192) % 100, rn2.ej_last - rn2.t_start, rn4.ej_last - rn4.t_start);

    errors += z.errors + ring2.errors + ring1.errors + sh2.errors + sh1.errors + rn2.errors + rn4.errors;
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
