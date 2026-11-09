`timescale 1ns/1ps
// Single core (no contention): every access after the first iteration hits, so the totals follow from the operation costs (hit = 1 cycle, miss = BUS_LAT cycles, think NT between iterations):
//   TAS    : first iteration  xchg miss + load-counter miss + work + store-counter upgrade + release hit = 3 BUS_LAT + CS_LEN + 1;   later iterations 1 + 1 + CS_LEN + 1 + 1 = 4 + CS_LEN
//            => cycles = 3 BUS_LAT + CS_LEN + 1 + (N-1) (4 + CS_LEN + NT);   bus transactions: 1 BusRd + 2 BusRdX, independent of N
//   TTAS   : first iteration  load-L miss + xchg upgrade + load-counter miss + work + store-counter upgrade + release hit = 4 BUS_LAT + CS_LEN + 1;   later 5 + CS_LEN
//            => cycles = 4 BUS_LAT + CS_LEN + 1 + (N-1) (5 + CS_LEN + NT);   2 BusRd + 2 BusRdX
//   TICKET : first iteration  fetch-add miss + load-serving miss + load-counter miss + work + store-counter upgrade + release upgrade = 5 BUS_LAT + CS_LEN;   later 5 + CS_LEN
//            => cycles = 5 BUS_LAT + CS_LEN + (N-1) (5 + CS_LEN + NT);   2 BusRd + 3 BusRdX
// With several cores the testbench checks what any correct lock must give: the counter equals P*N (no lost update), never more than one core inside the critical section, every core finishes
// N iterations, and for the ticket lock the cores acquire in exactly the order they drew their tickets (FIFO).  The control without a lock must lose updates and overlap.
module lock_harness #(parameter int P = 4, parameter int N = 4, parameter int LOCK = 0, parameter int BUS_LAT = 4, parameter int CS_LEN = 2, parameter int NT = 3)
    (output bit fin, output int errors, output int cycles, output int rd, output int rdx, output int ctr, output int maxcs, output int total_acq);
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  wire done;  wire [31:0] stat_rd, stat_rdx, stat_cycles, counter, cs_count;  wire [P-1:0] acq_pulse, tick_pulse;
  spinlock_bench #(.P(P), .N(N), .LOCK(LOCK), .BUS_LAT(BUS_LAT), .CS_LEN(CS_LEN), .NT(NT)) dut (.clk, .rst_n, .done, .stat_rd, .stat_rdx, .stat_cycles, .counter, .cs_count, .acq_pulse, .tick_pulse);

  int acq_n [0:P-1];
  int tick_log [0:4095], acq_log [0:4095];  int n_tick = 0, n_acq = 0, mx = 0;
  always @(posedge clk) if (rst_n) begin
    if (cs_count > mx) mx = int'(cs_count);
    for (int k = 0; k < P; k++) begin
      if (tick_pulse[k]) begin tick_log[n_tick] = k; n_tick++; end
      if (acq_pulse[k])  begin acq_log[n_acq] = k;  n_acq++;  acq_n[k]++; end
    end
  end

  initial begin
    int t;
    fin = 0; errors = 0; cycles = 0; rd = 0; rdx = 0; ctr = 0; maxcs = 0; total_acq = 0;
    for (int k = 0; k < P; k++) acq_n[k] = 0;
    repeat (3) @(negedge clk);  rst_n = 1;
    t = 0;
    while (!done && t < 200000) begin @(negedge clk); t++; end
    repeat (3) @(negedge clk);
    if (!done) begin errors++; $display("FAIL [P=%0d lock=%0d] not finished after %0d cycles", P, LOCK, t); end
    cycles = int'(stat_cycles);  rd = int'(stat_rd);  rdx = int'(stat_rdx);  ctr = int'(counter);  maxcs = mx;  total_acq = n_acq;
    if (LOCK != 3) begin
      if (counter !== P * N) begin errors++; $display("FAIL [P=%0d lock=%0d] counter %0d, expected %0d (lost updates)", P, LOCK, counter, P * N); end
      if (mx > 1) begin errors++; $display("FAIL [P=%0d lock=%0d] %0d cores inside the critical section at once", P, LOCK, mx); end
      for (int k = 0; k < P; k++) if (acq_n[k] != N) begin errors++; $display("FAIL [P=%0d lock=%0d] core %0d acquired %0d times, expected %0d", P, LOCK, k, acq_n[k], N); end
      if (LOCK == 2) begin
        if (n_tick != P * N || n_acq != P * N) begin errors++; $display("FAIL ticket lock: %0d tickets, %0d acquisitions", n_tick, n_acq); end
        for (int i = 0; i < n_acq && i < n_tick; i++) if (acq_log[i] != tick_log[i]) begin errors++; $display("FAIL ticket lock not FIFO: acquisition %0d by core %0d, ticket %0d was drawn by core %0d", i, acq_log[i], i, tick_log[i]); i = n_acq; end
      end
    end
    fin = 1;
  end
endmodule

module tb_spinlock_bench;
  // uncontended runs with hand-derived totals
  wire f0, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14;
  int e0, e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11, e12, e13, e14;
  int cy0, cy1, cy2, cy3, cy4, cy5, cy6, cy7, cy8, cy9, cy10, cy11, cy12, cy13, cy14;
  int rd0, rd1, rd2, rd3, rd4, rd5, rd6, rd7, rd8, rd9, rd10, rd11, rd12, rd13, rd14;
  int rx0, rx1, rx2, rx3, rx4, rx5, rx6, rx7, rx8, rx9, rx10, rx11, rx12, rx13, rx14;
  int ct0, ct1, ct2, ct3, ct4, ct5, ct6, ct7, ct8, ct9, ct10, ct11, ct12, ct13, ct14;
  int mc0, mc1, mc2, mc3, mc4, mc5, mc6, mc7, mc8, mc9, mc10, mc11, mc12, mc13, mc14;
  int ta0, ta1, ta2, ta3, ta4, ta5, ta6, ta7, ta8, ta9, ta10, ta11, ta12, ta13, ta14;
  lock_harness #(.P(1), .N(5), .LOCK(0)) u_tas  (.fin(f0), .errors(e0), .cycles(cy0), .rd(rd0), .rdx(rx0), .ctr(ct0), .maxcs(mc0), .total_acq(ta0));
  lock_harness #(.P(1), .N(5), .LOCK(1)) u_ttas (.fin(f1), .errors(e1), .cycles(cy1), .rd(rd1), .rdx(rx1), .ctr(ct1), .maxcs(mc1), .total_acq(ta1));
  lock_harness #(.P(1), .N(5), .LOCK(2)) u_tkt  (.fin(f2), .errors(e2), .cycles(cy2), .rd(rd2), .rdx(rx2), .ctr(ct2), .maxcs(mc2), .total_acq(ta2));
  lock_harness #(.P(1), .N(3), .LOCK(0), .BUS_LAT(6), .CS_LEN(0), .NT(0)) u_tas0 (.fin(f3), .errors(e3), .cycles(cy3), .rd(rd3), .rdx(rx3), .ctr(ct3), .maxcs(mc3), .total_acq(ta3));
  // contended runs, 4 cores
  lock_harness #(.P(4), .N(6), .LOCK(0)) c_tas  (.fin(f4), .errors(e4), .cycles(cy4), .rd(rd4), .rdx(rx4), .ctr(ct4), .maxcs(mc4), .total_acq(ta4));
  lock_harness #(.P(4), .N(6), .LOCK(1)) c_ttas (.fin(f5), .errors(e5), .cycles(cy5), .rd(rd5), .rdx(rx5), .ctr(ct5), .maxcs(mc5), .total_acq(ta5));
  lock_harness #(.P(4), .N(6), .LOCK(2)) c_tkt  (.fin(f6), .errors(e6), .cycles(cy6), .rd(rd6), .rdx(rx6), .ctr(ct6), .maxcs(mc6), .total_acq(ta6));
  lock_harness #(.P(4), .N(6), .LOCK(3)) c_none (.fin(f7), .errors(e7), .cycles(cy7), .rd(rd7), .rdx(rx7), .ctr(ct7), .maxcs(mc7), .total_acq(ta7));
  // two cores, derived by hand
  lock_harness #(.P(2), .N(1), .LOCK(0), .CS_LEN(0), .NT(0)) h_tas2  (.fin(f13), .errors(e13), .cycles(cy13), .rd(rd13), .rdx(rx13), .ctr(ct13), .maxcs(mc13), .total_acq(ta13));
  lock_harness #(.P(2), .N(1), .LOCK(1), .CS_LEN(0), .NT(0)) h_ttas2 (.fin(f14), .errors(e14), .cycles(cy14), .rd(rd14), .rdx(rx14), .ctr(ct14), .maxcs(mc14), .total_acq(ta14));
  // scaling with the number of cores
  lock_harness #(.P(2), .N(6), .LOCK(0)) p2_tas  (.fin(f8),  .errors(e8),  .cycles(cy8),  .rd(rd8),  .rdx(rx8),  .ctr(ct8),  .maxcs(mc8),  .total_acq(ta8));
  lock_harness #(.P(2), .N(6), .LOCK(1)) p2_ttas (.fin(f9),  .errors(e9),  .cycles(cy9),  .rd(rd9),  .rdx(rx9),  .ctr(ct9),  .maxcs(mc9),  .total_acq(ta9));
  lock_harness #(.P(8), .N(6), .LOCK(0)) p8_tas  (.fin(f10), .errors(e10), .cycles(cy10), .rd(rd10), .rdx(rx10), .ctr(ct10), .maxcs(mc10), .total_acq(ta10));
  lock_harness #(.P(8), .N(6), .LOCK(1)) p8_ttas (.fin(f11), .errors(e11), .cycles(cy11), .rd(rd11), .rdx(rx11), .ctr(ct11), .maxcs(mc11), .total_acq(ta11));
  lock_harness #(.P(8), .N(6), .LOCK(2)) p8_tkt  (.fin(f12), .errors(e12), .cycles(cy12), .rd(rd12), .rdx(rx12), .ctr(ct12), .maxcs(mc12), .total_acq(ta12));

  int errors;
  task automatic expect_i(input string what, input int got, input int exp_v);
    if (got != exp_v) begin errors++; $display("FAIL %s: got %0d expected %0d", what, got, exp_v); end
  endtask
  initial begin
    errors = 0;
    wait (f0 && f1 && f2 && f3 && f4 && f5 && f6 && f7 && f8 && f9 && f10 && f11 && f12 && f13 && f14);
    #1;
    errors += e0 + e1 + e2 + e3 + e4 + e5 + e6 + e7 + e8 + e9 + e10 + e11 + e12 + e13 + e14;
    // hand-derived single-core totals (BUS_LAT 4, CS_LEN 2, NT 3, N 5)
    expect_i("TAS 1 core cycles",    cy0, 3*4 + 2 + 1 + 4*(4 + 2 + 3));   expect_i("TAS 1 core BusRd",  rd0, 1);  expect_i("TAS 1 core BusRdX",  rx0, 2);
    expect_i("TTAS 1 core cycles",   cy1, 4*4 + 2 + 1 + 4*(5 + 2 + 3));   expect_i("TTAS 1 core BusRd", rd1, 2);  expect_i("TTAS 1 core BusRdX", rx1, 2);
    expect_i("TICKET 1 core cycles", cy2, 5*4 + 2 + 0 + 4*(5 + 2 + 3));   expect_i("TICKET 1 core BusRd", rd2, 2); expect_i("TICKET 1 core BusRdX", rx2, 3);
    expect_i("TAS 1 core, BUS_LAT 6, no critical-section work, no think time", cy3, 3*6 + 0 + 1 + 2*(4 + 0 + 0));
    expect_i("TAS 2 cores cycles", cy13, 33);   expect_i("TAS 2 cores BusRd", rd13, 2);   expect_i("TAS 2 cores BusRdX", rx13, 6);
    expect_i("TTAS 2 cores cycles", cy14, 45);  expect_i("TTAS 2 cores BusRd", rd14, 5);  expect_i("TTAS 2 cores BusRdX", rx14, 6);
    // the control without a lock must show what the locks prevent
    if (!(mc7 > 1)) begin errors++; $display("FAIL: without a lock the critical sections should overlap (max %0d)", mc7); end
    if (!(ct7 < 4 * 6)) begin errors++; $display("FAIL: without a lock increments should be lost (counter %0d of %0d)", ct7, 4 * 6); end
    // traffic
    if (!(rx5 + rd5 < rx4 + rd4)) begin errors++; $display("FAIL: TTAS (%0d transactions) should need fewer bus transactions than TAS (%0d) with 4 cores", rx5 + rd5, rx4 + rd4); end
    if (!(rx11 + rd11 < rx10 + rd10)) begin errors++; $display("FAIL: TTAS should need fewer bus transactions than TAS with 8 cores"); end
    $display("4 cores x 6 critical sections (24 acquisitions): bus transactions / cycles   TAS %0d / %0d,  TTAS %0d / %0d,  ticket %0d / %0d   (no lock: counter %0d of 24, up to %0d cores inside at once)",
             rd4 + rx4, cy4, rd5 + rx5, cy5, rd6 + rx6, cy6, ct7, mc7);
    $display("transactions per acquisition, 2 / 4 / 8 cores:  TAS %0d.%02d / %0d.%02d / %0d.%02d   TTAS %0d.%02d / %0d.%02d / %0d.%02d   (8 cores ticket: %0d.%02d)",
             (rd8+rx8)/12, ((rd8+rx8)*100/12)%100, (rd4+rx4)/24, ((rd4+rx4)*100/24)%100, (rd10+rx10)/48, ((rd10+rx10)*100/48)%100,
             (rd9+rx9)/12, ((rd9+rx9)*100/12)%100, (rd5+rx5)/24, ((rd5+rx5)*100/24)%100, (rd11+rx11)/48, ((rd11+rx11)*100/48)%100,
             (rd12+rx12)/48, ((rd12+rx12)*100/48)%100);
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
