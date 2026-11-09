`timescale 1ns/1ps
// Hand-derived expectations (see README):
//   zero load: a packet crossing K = hops + 1 routers with F flits takes 3K + F - 1 cycles from the head on the injection link to the tail on the ejection link
//              (the head needs VC allocation + switch allocation = 3 cycles per router, the body/tail flits stream right behind it).
//   credit loop: one 40-flit packet over 4 routers takes 3*4 + 39 = 51 cycles at full rate (per-VC buffer depth >= the 4-cycle credit round trip); with depth D < 4 only D flits
//                can be sent per 4 cycles, so flit i leaves at floor(i/D)*4 + (i mod D): the 40th flit is late by floor(39/D)*4 + (39 mod D) - 39  -> 51 + 38 (D=2), 51 + 13 (D=3).
//   head-of-line blocking (4x1 mesh): C = node 1 -> 3, 60 flits holds router 1's East output; A = node 0 -> 3, 20 flits, queues behind C at router 1; B = node 0 -> 1,
//              4 flits, is injected right behind A.  With ONE virtual channel B sits in A's queue until C has passed (B completes after cycle 60); with TWO virtual channels
//              B overtakes A and completes within 3*2 + 4 - 1 plus at most 4 cycles of sharing the injection port with A.
// Ejection checkers work per (node, virtual channel): flits of one packet arrive in order, packets are never interleaved INSIDE a virtual channel, each is delivered exactly once.
module vc_harness #(parameter int NX = 4, parameter int NY = 4, parameter int NVC = 2, parameter int DEPTH = 4) ();
  import vc_pkg::*;
  localparam int NN = NX * NY, MAXF = 200, MAXP = 512;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic [NN-1:0] inj_valid = 0;  logic [NN*FW-1:0] inj_flit = 0;
  wire  [NN-1:0] inj_credit_v, ej_valid;  wire [NN*2-1:0] inj_credit_vc;  wire [NN*FW-1:0] ej_flit;  wire err_overflow;
  vc_net #(.NX(NX), .NY(NY), .NVC(NVC), .DEPTH(DEPTH)) dut (.*);

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

  function automatic int hops(input int s, input int d);
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
    if (delivered < n_pkts && errors == 0) begin errors++; $display("FAIL [%0dx%0d VC=%0d D=%0d] %s: only %0d of %0d packets delivered in %0d cycles (deadlock?)", NX, NY, NVC, DEPTH, what, delivered, n_pkts, timeout); end
    repeat (10) @(negedge clk);
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

module tb_vc_router;
  import vc_pkg::*;
  int errors = 0;
  task automatic expect_i(input string what, input int got, input int exp_v);
    if (got != exp_v) begin errors++; $display("FAIL %s: got %0d expected %0d", what, got, exp_v); end
  endtask

  // 1. routing table of a single router (1,1) of a 3x3 mesh, flits arriving on virtual channel 1
  logic clk = 0, ru_rst = 0;
  always #5 clk = ~clk;
  logic [4:0] ru_in_v = 0, ru_in_cr, ru_out_v, ru_out_cr = 0;  logic [5*FW-1:0] ru_in_f = 0, ru_out_f;  logic ru_err;  logic [9:0] ru_in_crvc, ru_out_crvc = 0;
  vc_router #(.X(1), .Y(1), .NX(3), .NY(3), .NVC(2), .DEPTH(4)) ru (.clk, .rst_n(ru_rst), .in_valid(ru_in_v), .in_flit(ru_in_f), .in_credit_v(ru_in_cr), .in_credit_vc(ru_in_crvc),
      .out_valid(ru_out_v), .out_flit(ru_out_f), .out_credit_v(ru_out_cr), .out_credit_vc(ru_out_crvc), .err_overflow(ru_err));
  task automatic route_case(input int in_port, input int dx, input int dy, input int exp_port);
    logic [FW-1:0] f;
    f = '0;  f[FW-1:FW-2] = T_SINGLE;  f[33:32] = 2'd1;  f[15:0] = 16'hABCD;  f[27:24] = dx[3:0];  f[31:28] = dy[3:0];
    @(negedge clk);  ru_rst = 0;  @(negedge clk);  @(negedge clk);  ru_rst = 1;
    @(negedge clk);  ru_in_v = 5'(1 << in_port);  ru_in_f[in_port*FW +: FW] = f;      // on the link during cycle c
    @(negedge clk);  ru_in_v = 0;                                                      // c+1: virtual-channel allocation
    @(negedge clk);                                                                    // c+2: switch allocation
    @(negedge clk);                                                                    // c+3: on the output link
    if (ru_out_v !== 5'(1 << exp_port)) begin errors++; $display("FAIL route: in %0d dest (%0d,%0d): out_valid=%b, expected port %0d", in_port, dx, dy, ru_out_v, exp_port); end
    else if (ru_out_f[exp_port*FW +: FW] !== (f & ~(36'd3 << 32) | (36'd0 << 32))) begin errors++; $display("FAIL route: flit corrupted (%h vs %h)", ru_out_f[exp_port*FW +: FW], f); end
  endtask

  vc_harness #(.NX(4), .NY(4), .NVC(2), .DEPTH(4)) z ();                         // zero-load, hot spot
  vc_harness #(.NX(4), .NY(1), .NVC(1), .DEPTH(2)) c2 ();
  vc_harness #(.NX(4), .NY(1), .NVC(1), .DEPTH(3)) c3 ();
  vc_harness #(.NX(4), .NY(1), .NVC(2), .DEPTH(4)) c4 ();
  vc_harness #(.NX(4), .NY(1), .NVC(1), .DEPTH(5)) c5 ();
  vc_harness #(.NX(4), .NY(1), .NVC(1), .DEPTH(4)) hol1 ();                      // head-of-line blocking, one VC
  vc_harness #(.NX(4), .NY(1), .NVC(2), .DEPTH(4)) hol2 ();                      // ... and two VCs
  vc_harness #(.NX(4), .NY(4), .NVC(1), .DEPTH(8)) r1 ();                        // random traffic, 8 flits of buffering per port in each case
  vc_harness #(.NX(4), .NY(4), .NVC(2), .DEPTH(4)) r2 ();
  vc_harness #(.NX(4), .NY(4), .NVC(4), .DEPTH(2)) r4 ();

  logic [31:0] seed = 32'd1992;
  function automatic int rnd(input int n); seed = seed * 32'd1664525 + 32'd1013904223; return int'(seed[30:16]) % n; endfunction


  initial begin
    int mx, lat2, lat3, lat4, lat5, bdone1, bdone2, adone1, adone2, sum1, sum2, sum4, tot1, tot2, tot4;
    int exp2, exp3;
    repeat (6) @(negedge clk);

    // ---- 1. routing ----
    route_case(P_L, 2, 1, P_E);  route_case(P_L, 0, 1, P_W);  route_case(P_L, 1, 0, P_N);  route_case(P_L, 1, 2, P_S);  route_case(P_L, 1, 1, P_L);
    route_case(P_L, 2, 0, P_E);  route_case(P_L, 0, 2, P_W);  route_case(P_L, 2, 2, P_E);  route_case(P_L, 0, 0, P_W);
    route_case(P_W, 2, 1, P_E);  route_case(P_W, 1, 2, P_S);  route_case(P_W, 1, 1, P_L);  route_case(P_N, 0, 2, P_W);  route_case(P_N, 1, 2, P_S);
    $display("routing: 14 destination/input combinations routed X-first (dimension order), in 3 cycles");

    // ---- 2. zero-load latency 3K + F - 1, on either virtual channel ----
    z.clear_all();  z.add_pkt(0, 15, 5, 0, 0);  z.run(200, "corner to corner");        expect_i("(0,0)->(3,3) 5 flits", z.latency(0), 3 * 7 + 4);
    z.clear_all();  z.add_pkt(0, 15, 5, 0, 1);  z.run(200, "corner to corner vc1");    expect_i("(0,0)->(3,3) 5 flits on VC 1", z.latency(0), 3 * 7 + 4);
    z.clear_all();  z.add_pkt(0, 1, 1, 0, 0);   z.run(200, "neighbour");               expect_i("(0,0)->(1,0) 1 flit", z.latency(0), 6);
    z.clear_all();  z.add_pkt(5, 5, 3, 0, 1);   z.run(200, "self");                    expect_i("(1,1)->(1,1) 3 flits", z.latency(0), 5);
    z.clear_all();  z.add_pkt(3, 8, 2, 0, 0);   z.run(200, "mixed");                   expect_i("(3,0)->(0,2) 2 flits", z.latency(0), 3 * 6 + 1);
    $display("zero-load: corner-to-corner 5-flit packet = %0d cycles (3 x 7 routers + 4), neighbour = 6, self = 5", 25);

    // ---- 3. credit loop per virtual channel ----
    c2.clear_all(); c2.add_pkt(0, 3, 40, 0, 0); c2.run(1000, "D=2");  lat2 = c2.latency(0);
    c3.clear_all(); c3.add_pkt(0, 3, 40, 0, 0); c3.run(1000, "D=3");  lat3 = c3.latency(0);
    c4.clear_all(); c4.add_pkt(0, 3, 40, 0, 1); c4.run(1000, "D=4 vc1");  lat4 = c4.latency(0);
    c5.clear_all(); c5.add_pkt(0, 3, 40, 0, 0); c5.run(1000, "D=5");  lat5 = c5.latency(0);
    exp2 = 51 + (39 / 2) * 4 + (39 % 2) - 39;  exp3 = 51 + (39 / 3) * 4 + (39 % 3) - 39;
    $display("credit loop, 40-flit packet over 4 routers: ideal 51 cycles; VC buffer depth 2 -> %0d (expected %0d), 3 -> %0d (expected %0d), 4 -> %0d, 5 -> %0d", lat2, exp2, lat3, exp3, lat4, lat5);
    expect_i("D=2 credit-limited", lat2, exp2);
    expect_i("D=3 credit-limited", lat3, exp3);
    expect_i("D=4 sustains one flit per cycle", lat4, 51);
    expect_i("D=5 sustains one flit per cycle", lat5, 51);

    // ---- 4. head-of-line blocking ----
    hol1.clear_all();  hol1.add_pkt(1, 3, 60, 0, 0);  hol1.add_pkt(0, 3, 20, 0, 0);  hol1.add_pkt(0, 1, 4, 0, 0);  hol1.run(2000, "HOL, 1 VC");
    hol2.clear_all();  hol2.add_pkt(1, 3, 60, 0, 0);  hol2.add_pkt(0, 3, 20, 0, 0);  hol2.add_pkt(0, 1, 4, 0, 1);  hol2.run(2000, "HOL, 2 VCs");
    bdone1 = hol1.done_at(2);  bdone2 = hol2.done_at(2);  adone1 = hol1.done_at(1);  adone2 = hol2.done_at(1);
    $display("head-of-line blocking: short packet B (4 flits, node 0 -> 1) completes at cycle %0d with 1 VC (stuck behind the blocked 20-flit packet A) and at cycle %0d with 2 VCs; A completes at %0d / %0d",
             bdone1, bdone2, adone1, adone2);
    if (!(bdone1 > 60)) begin errors++; $display("FAIL: with one VC, B (%0d) should wait for the 60-flit packet C", bdone1); end
    if (!(bdone2 <= 3 * 2 + 4 - 1 + 4 + 2 + 3)) begin errors++; $display("FAIL: with two VCs, B should overtake A: completes at %0d", bdone2); end
    if (hol1.errors + hol2.errors != 0) errors++;

    // ---- 5. hot spot ----
    z.clear_all();  for (int s = 1; s < 16; s++) z.add_pkt(s, 0, 4, 0, s % 2);  z.run(2000, "hot spot");
    expect_i("hot spot: packets delivered", z.delivered, 15);
    if (z.node0_last - z.node0_first < 15 * 4 - 1) begin errors++; $display("FAIL hot spot: 60 flits ejected in only %0d cycles", z.node0_last - z.node0_first + 1); end
    mx = 0;  for (int i = 0; i < 15; i++) if (z.latency(i) > mx) mx = z.latency(i);
    $display("hot spot: 60 flits through one ejection port in %0d cycles (minimum 60), worst packet latency %0d", z.node0_last - z.node0_first + 1, mx);

    // ---- 6. random traffic, equal buffering (8 flits per input port): 1 VC x 8, 2 VC x 4, 4 VC x 2 ----
    r1.clear_all();  r2.clear_all();  r4.clear_all();
    for (int s = 0; s < 16; s++) for (int k = 0; k < 12; k++) begin
      int dst, len, tt, vc;
      dst = rnd(16);  len = 1 + rnd(6);  tt = rnd(40);  vc = rnd(4);              // explicit order: the VHDL testbench draws the same sequence
      r1.add_pkt(s, dst, len, tt, 0);  r2.add_pkt(s, dst, len, tt, vc % 2);  r4.add_pkt(s, dst, len, tt, vc);
    end
    r1.run(40000, "random 1 VC");  r2.run(40000, "random 2 VC");  r4.run(40000, "random 4 VC");
    expect_i("random 1 VC: packets delivered", r1.delivered, 192);
    expect_i("random 2 VC: packets delivered", r2.delivered, 192);
    expect_i("random 4 VC: packets delivered", r4.delivered, 192);
    sum1 = 0; sum2 = 0; sum4 = 0;
    for (int i = 0; i < 192; i++) begin
      if (r1.latency(i) < r1.zero_load(i) || r2.latency(i) < r2.zero_load(i) || r4.latency(i) < r4.zero_load(i)) begin errors++; $display("FAIL packet %0d: latency below the zero-load bound", i); end
      sum1 += r1.latency(i);  sum2 += r2.latency(i);  sum4 += r4.latency(i);
    end
    tot1 = r1.ej_last - r1.t_start;  tot2 = r2.ej_last - r2.t_start;  tot4 = r4.ej_last - r4.t_start;
    $display("random traffic, 192 packets, 8 flits of buffering per port: 1 VC x 8: average latency %0d.%02d, done at %0d;  2 VC x 4: %0d.%02d, done at %0d;  4 VC x 2: %0d.%02d, done at %0d",
             sum1 / 192, (sum1 * 100 / 192) % 100, tot1, sum2 / 192, (sum2 * 100 / 192) % 100, tot2, sum4 / 192, (sum4 * 100 / 192) % 100, tot4);

    if (!(sum2 < sum1 && tot2 < tot1)) begin errors++; $display("FAIL: 2 VCs x 4 flits should beat 1 VC x 8 flits under load (latency %0d vs %0d, done %0d vs %0d)", sum2, sum1, tot2, tot1); end
    if (!(sum4 < sum1)) begin errors++; $display("FAIL: 4 VCs x 2 flits should beat 1 VC x 8 flits under load (latency %0d vs %0d)", sum4, sum1); end

    errors += z.errors + c2.errors + c3.errors + c4.errors + c5.errors + r1.errors + r2.errors + r4.errors;
    if (ru_err) errors++;
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
