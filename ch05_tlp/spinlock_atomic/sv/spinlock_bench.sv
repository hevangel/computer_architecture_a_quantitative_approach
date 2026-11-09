// Atomic read-modify-write and spin locks on a snooping bus (Chapter 5: synchronization).
//
// P cores share a write-invalidate (MSI) snooping bus.  Each core repeats N times:   acquire the lock; critical section = { load counter, CS_LEN cycles of work, store counter+1 };
// release; think NT cycles.  Three locks, selected by LOCK:
//   0 TAS     test-and-set: spin on an ATOMIC EXCHANGE (xchg L,1) until it returns 0.  Every attempt needs the line in M, so contending cores steal it from each other: bus traffic per spin.
//   1 TTAS    test-and-test-and-set: spin with plain LOADS (the line stays Shared in every spinner's cache: no bus traffic) and issue the atomic exchange only when the lock reads 0.
//   2 TICKET  ticket lock: FETCH-AND-ADD on the ticket counter gives each core a number; spin with loads on now_serving until it equals the number; release stores number+1 (FIFO order).
//   3 NONE    no lock (a control: the critical sections overlap and increments are lost).
// Memory system: 3 lines (0 = lock / next ticket, 1 = now serving, 2 = counter).  Coherence STATES (I/S/M) of every line in every cache decide the bus traffic; the VALUES live in one coherent
// memory image, and a memory operation performs atomically at the cycle it hits in the cache or completes on the bus.
//   * An operation that HITS (LD in S or M, ST / atomic in M) takes 1 cycle and no bus traffic.
//   * A miss (LD in I -> BusRd; ST / atomic in I or S -> BusRdX / upgrade) arbitrates for the bus (round robin).  A transaction takes BUS_LAT cycles: the coherence actions happen when it is
//     GRANTED (BusRd: owner M -> S, requester S; BusRdX: every other copy -> I, requester M) and the operation performs when it completes, BUS_LAT-1 cycles after the grant.
//   * An uncontended miss therefore takes BUS_LAT cycles in all.
// Statistics: stat_rd / stat_rdx (bus transactions by kind), stat_cycles (cycles until every core is done), counter value, the maximum number of cores inside the critical section at once,
// and per-core acquisition / ticket pulses for the FIFO check.
module spinlock_bench #(
    parameter int P       = 4,
    parameter int N       = 4,
    parameter int LOCK    = 0,
    parameter int BUS_LAT = 4,
    parameter int CS_LEN  = 2,
    parameter int NT      = 3
) (
    input  logic                clk,
    input  logic                rst_n,
    output logic                done,
    output logic [31:0]         stat_rd, stat_rdx, stat_cycles,
    output logic [31:0]         counter,
    output logic [31:0]         cs_count,                 // cores inside the critical section right now
    output logic [P-1:0]        acq_pulse,                // core k acquired the lock (one cycle)
    output logic [P-1:0]        tick_pulse                // core k drew a ticket (one cycle)
);
  localparam int NL = 3;
  localparam int S_THINK = 0, S_ACQ = 1, S_TT_RD = 2, S_TT_X = 3, S_TK_FAA = 4, S_TK_SPIN = 5, S_C_LD = 6, S_WORK = 7, S_C_ST = 8, S_REL = 9, S_DONE = 10;
  localparam int FIRST = (LOCK == 0) ? S_ACQ : (LOCK == 1) ? S_TT_RD : (LOCK == 2) ? S_TK_FAA : S_C_LD;
  localparam logic [1:0] M_I = 2'd0, M_S = 2'd1, M_M = 2'd2;

  logic [3:0]  fs   [0:P-1];
  int          cnt  [0:P-1];
  int          itn  [0:P-1];
  logic [31:0] my   [0:P-1];
  logic [31:0] tmp  [0:P-1];
  logic        in_cs [0:P-1];
  logic [1:0]  cst  [0:P*NL-1];
  logic [31:0] val  [0:NL-1];
  logic        busy;
  int          owner, rem, rr;

  // ---- the memory operation each core wants to perform this cycle ----
  logic        opv  [0:P-1];                 // the core is in a state that issues a memory operation
  logic [1:0]  opt  [0:P-1];                 // 0 load, 1 store, 2 atomic
  logic [1:0]  opl  [0:P-1];                 // line
  logic        hit  [0:P-1];
  logic        want [0:P-1];
  int          grant;
  always_comb begin
    for (int k = 0; k < P; k++) begin
      opv[k] = 1'b1;  opt[k] = 2'd0;  opl[k] = 2'd0;
      case (int'(fs[k]))
        S_ACQ:     begin opt[k] = 2'd2; opl[k] = 2'd0; end
        S_TT_RD:   begin opt[k] = 2'd0; opl[k] = 2'd0; end
        S_TT_X:    begin opt[k] = 2'd2; opl[k] = 2'd0; end
        S_TK_FAA:  begin opt[k] = 2'd2; opl[k] = 2'd0; end
        S_TK_SPIN: begin opt[k] = 2'd0; opl[k] = 2'd1; end
        S_C_LD:    begin opt[k] = 2'd0; opl[k] = 2'd2; end
        S_C_ST:    begin opt[k] = 2'd1; opl[k] = 2'd2; end
        S_REL:     begin opt[k] = 2'd1; opl[k] = (LOCK == 2) ? 2'd1 : 2'd0; end
        default:   opv[k] = 1'b0;
      endcase
      if (opt[k] == 2'd0) hit[k] = (cst[k*NL + int'(opl[k])] != M_I);
      else                hit[k] = (cst[k*NL + int'(opl[k])] == M_M);
      want[k] = opv[k] && !hit[k] && !(busy && owner == k);
    end
    grant = -1;
    if (!busy) for (int j = 1; j <= P; j++) if (grant < 0 && want[(rr + j) % P]) grant = (rr + j) % P;
    cs_count = '0;
    for (int k = 0; k < P; k++) if (in_cs[k]) cs_count = cs_count + 1;
    done = 1'b1;
    for (int k = 0; k < P; k++) if (int'(fs[k]) != S_DONE) done = 1'b0;
    counter = val[2];
  end

  // perform core k's operation (a hit, or the completion of its bus transaction); returns through nonblocking updates
  task automatic perform(input int k);
    logic [31:0] old;
    int ln;
    ln = int'(opl[k]);  old = val[ln];
    case (int'(fs[k]))
      S_ACQ: begin                                                      // xchg(L, 1)
        val[0] <= 32'd1;
        if (old == 0) begin fs[k] <= S_C_LD; in_cs[k] <= 1'b1; acq_pulse[k] <= 1'b1; end
      end
      S_TT_RD: if (old == 0) fs[k] <= S_TT_X;
      S_TT_X: begin
        val[0] <= 32'd1;
        if (old == 0) begin fs[k] <= S_C_LD; in_cs[k] <= 1'b1; acq_pulse[k] <= 1'b1; end
        else fs[k] <= S_TT_RD;
      end
      S_TK_FAA: begin val[0] <= old + 1; my[k] <= old; fs[k] <= S_TK_SPIN; tick_pulse[k] <= 1'b1; end
      S_TK_SPIN: if (old == my[k]) begin fs[k] <= S_C_LD; in_cs[k] <= 1'b1; acq_pulse[k] <= 1'b1; end
      S_C_LD: begin tmp[k] <= old; if (CS_LEN > 0) begin fs[k] <= S_WORK; cnt[k] <= CS_LEN; end else fs[k] <= S_C_ST; end
      S_C_ST: begin
        val[2] <= tmp[k] + 1;
        if (LOCK == 3) begin in_cs[k] <= 1'b0; next_iter(k); end else fs[k] <= S_REL;
      end
      S_REL: begin
        if (LOCK == 2) val[1] <= my[k] + 1; else val[0] <= 32'd0;
        in_cs[k] <= 1'b0;
        next_iter(k);
      end
      default: ;
    endcase
  endtask
  task automatic next_iter(input int k);
    itn[k] <= itn[k] + 1;
    if (itn[k] + 1 >= N) fs[k] <= S_DONE;
    else if (NT > 0) begin fs[k] <= S_THINK; cnt[k] <= NT; end
    else begin fs[k] <= FIRST; if (LOCK == 3) in_cs[k] <= 1'b1; end
  endtask

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= 1'b0;  owner <= 0;  rem <= 0;  rr <= P - 1;
      stat_rd <= '0;  stat_rdx <= '0;  stat_cycles <= '0;  acq_pulse <= '0;  tick_pulse <= '0;
      for (int k = 0; k < P; k++) begin fs[k] <= FIRST; cnt[k] <= 0; itn[k] <= 0; my[k] <= '0; tmp[k] <= '0; in_cs[k] <= (LOCK == 3); end
      for (int i = 0; i < P*NL; i++) cst[i] <= M_I;
      for (int l = 0; l < NL; l++) val[l] <= '0;
    end else begin
      acq_pulse <= '0;  tick_pulse <= '0;
      if (!done) stat_cycles <= stat_cycles + 1;
      // cores: think / work counters, and operations that hit
      for (int k = 0; k < P; k++) begin
        if (int'(fs[k]) == S_THINK) begin if (cnt[k] <= 1) begin fs[k] <= FIRST; if (LOCK == 3) in_cs[k] <= 1'b1; end else cnt[k] <= cnt[k] - 1; end
        else if (int'(fs[k]) == S_WORK) begin if (cnt[k] <= 1) fs[k] <= S_C_ST; else cnt[k] <= cnt[k] - 1; end
        else if (opv[k] && hit[k] && !(busy && owner == k)) perform(k);
      end
      // the bus: complete the transaction in flight, or grant a new one
      if (busy) begin
        if (rem == 1) begin busy <= 1'b0;  perform(owner); end
        else rem <= rem - 1;
      end else if (grant >= 0) begin
        busy <= 1'b1;  owner <= grant;  rem <= BUS_LAT - 1;  rr <= grant;
        if (opt[grant] == 2'd0) begin
          stat_rd <= stat_rd + 1;
          for (int j = 0; j < P; j++) if (j != grant && cst[j*NL + int'(opl[grant])] == M_M) cst[j*NL + int'(opl[grant])] <= M_S;
          cst[grant*NL + int'(opl[grant])] <= M_S;
        end else begin
          stat_rdx <= stat_rdx + 1;
          for (int j = 0; j < P; j++) if (j != grant) cst[j*NL + int'(opl[grant])] <= M_I;
          cst[grant*NL + int'(opl[grant])] <= M_M;
        end
      end
    end
  end
endmodule
