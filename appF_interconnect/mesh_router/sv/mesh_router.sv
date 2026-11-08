// A wormhole-switched 5-port mesh router (Appendix F: routing, flow control, arbitration).
//
//   * Ports 0..4 = North, East, South, West, Local.  Router (X,Y) sits at column X, row Y of an NX x NY mesh (y grows southward).
//   * ROUTING: dimension-order (XY): correct X first (East/West) until dest_x == X, then Y (South/North), then eject on the Local port.
//     XY routing is minimal and deadlock-free on a mesh (no packet ever turns from the Y dimension back into X).
//   * WORMHOLE: a packet is a head flit (carries the destination), body flits and a tail.  The head claims an output port; the port stays
//     LOCKED to that input until the tail has passed, so the flits of different packets never interleave on a link.
//   * FLOW CONTROL is credit based.  Each output keeps a counter of free slots in the downstream input FIFO (initially DEPTH).  A flit may be
//     forwarded only if a credit is available; the counter is decremented when the flit is sent and incremented when the downstream router pops
//     it and returns a one-cycle credit pulse.  (The Local output ejects into the node and needs no credits.)  Input FIFOs therefore never overflow.
//   * ARBITRATION: an unlocked output picks, round-robin, among the inputs whose head flit is a packet head routed to it.
// Pipeline (zero load): a flit written to an input FIFO at the end of cycle c is forwarded (switched into the output register) at the end of
// cycle c+1 and is on the output link during cycle c+2, i.e. TWO cycles per router.  The credit round trip (decision -> pop -> pulse -> counter
// update -> next decision) is FOUR cycles, so a FIFO depth of 4 is exactly what is needed to sustain one flit per cycle per link.
module mesh_router
  import mesh_pkg::*;
#(
    parameter int X     = 0,
    parameter int Y     = 0,
    parameter int NX    = 4,
    parameter int NY    = 4,
    parameter int DEPTH = 4
) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic [4:0]          in_valid,
    input  logic [5*FW-1:0]     in_flit,
    output logic [4:0]          in_credit,       // pulse: a flit left input FIFO p -> credit for the upstream router
    output logic [4:0]          out_valid,
    output logic [5*FW-1:0]     out_flit,
    input  logic [4:0]          out_credit,      // pulse from the downstream router
    output logic                err_overflow     // sticky: an input FIFO was written while full (flow-control violation)
);
  localparam int PW = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  localparam int CW = $clog2(DEPTH + 1);

  logic [FW-1:0] fifo [0:5*DEPTH-1];
  logic [PW-1:0] rd [0:4];
  logic [PW-1:0] wr [0:4];
  logic [CW-1:0] cnt [0:4];
  logic          act [0:4];                          // input p holds an output (wormhole lock)
  logic [2:0]    lock_o [0:4];
  logic          busy [0:4];                         // output o is locked to some input
  logic [2:0]    owner [0:4];
  logic [CW-1:0] cred [0:4];
  logic [2:0]    rr [0:4];                           // last winner per output

  // ---- head-of-FIFO decode and XY route ------------------------------------------------------------------
  logic [FW-1:0] hf [0:4];
  logic          nonempty [0:4], is_head [0:4], is_tail [0:4];
  logic [2:0]    route [0:4];
  always_comb begin
    for (int p = 0; p < 5; p++) begin
      hf[p]       = fifo[p*DEPTH + int'(rd[p])];
      nonempty[p] = (cnt[p] != '0);
      is_head[p]  = (hf[p][FW-1:FW-2] == T_HEAD) || (hf[p][FW-1:FW-2] == T_SINGLE);
      is_tail[p]  = (hf[p][FW-1:FW-2] == T_TAIL) || (hf[p][FW-1:FW-2] == T_SINGLE);
      if      (int'(hf[p][27:24]) > X) route[p] = 3'(P_E);
      else if (int'(hf[p][27:24]) < X) route[p] = 3'(P_W);
      else if (int'(hf[p][31:28]) > Y) route[p] = 3'(P_S);
      else if (int'(hf[p][31:28]) < Y) route[p] = 3'(P_N);
      else                             route[p] = 3'(P_L);
    end
  end

  // ---- switch allocation ------------------------------------------------------------------------------------
  logic       win_v [0:4];                           // output o forwards a flit this cycle
  logic [2:0] win_p [0:4];                           // ... taken from this input
  logic       win_new [0:4];                         // ... and it is a head that just won arbitration
  logic [4:0] fwd;                                   // input p is popped this cycle
  int         pk;                                    // scratch: candidate input in the round-robin scan
  logic       credit_ok [0:4];
  always_comb begin
    pk = 0;
    for (int o = 0; o < 5; o++) credit_ok[o] = (o == P_L) || (cred[o] != '0);
    for (int o = 0; o < 5; o++) begin
      win_v[o] = 1'b0;  win_p[o] = 3'd0;  win_new[o] = 1'b0;
      if (busy[o]) begin
        if (nonempty[int'(owner[o])] && credit_ok[o]) begin win_v[o] = 1'b1; win_p[o] = owner[o]; end
      end else if (credit_ok[o]) begin
        for (int k = 1; k <= 5; k++) begin
          pk = (int'(rr[o]) + k) % 5;
          if (!win_v[o] && nonempty[pk] && !act[pk] && is_head[pk] && int'(route[pk]) == o) begin win_v[o] = 1'b1; win_p[o] = 3'(pk); win_new[o] = 1'b1; end
        end
      end
    end
    fwd = 5'b0;
    for (int o = 0; o < 5; o++) if (win_v[o]) fwd[int'(win_p[o])] = 1'b1;
  end

  // ---- state update --------------------------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_valid <= '0;  out_flit <= '0;  in_credit <= '0;  err_overflow <= 1'b0;
      for (int p = 0; p < 5; p++) begin
        rd[p] <= '0; wr[p] <= '0; cnt[p] <= '0; act[p] <= 1'b0; lock_o[p] <= '0; busy[p] <= 1'b0; owner[p] <= '0;
        cred[p] <= CW'(DEPTH); rr[p] <= 3'd4;
      end
      for (int i = 0; i < 5*DEPTH; i++) fifo[i] <= '0;
    end else begin
      // outputs: a flit moves from its input FIFO into the output register
      for (int o = 0; o < 5; o++) begin
        out_valid[o] <= win_v[o];
        if (win_v[o]) begin
          out_flit[o*FW +: FW] <= hf[int'(win_p[o])];
          if (win_new[o]) begin
            rr[o] <= win_p[o];
            if (!is_tail[int'(win_p[o])]) begin busy[o] <= 1'b1; owner[o] <= win_p[o]; act[int'(win_p[o])] <= 1'b1; lock_o[int'(win_p[o])] <= 3'(o); end
          end else if (is_tail[int'(win_p[o])]) begin           // tail of a locked packet: release the output
            busy[o] <= 1'b0;  act[int'(win_p[o])] <= 1'b0;
          end
        end
        // credit counter: -1 when a flit is sent, +1 when the downstream router returns a credit
        if (o != P_L) begin
          if (win_v[o] && !out_credit[o])      cred[o] <= cred[o] - 1'b1;
          else if (!win_v[o] && out_credit[o]) cred[o] <= cred[o] + 1'b1;
        end
      end
      // input FIFOs
      for (int p = 0; p < 5; p++) begin
        in_credit[p] <= fwd[p];
        if (in_valid[p]) begin
          fifo[p*DEPTH + int'(wr[p])] <= in_flit[p*FW +: FW];
          wr[p] <= (int'(wr[p]) == DEPTH - 1) ? '0 : wr[p] + 1'b1;
          if (cnt[p] == CW'(DEPTH)) err_overflow <= 1'b1;
        end
        if (fwd[p]) rd[p] <= (int'(rd[p]) == DEPTH - 1) ? '0 : rd[p] + 1'b1;
        if (in_valid[p] && !fwd[p])      cnt[p] <= cnt[p] + 1'b1;
        else if (!in_valid[p] && fwd[p]) cnt[p] <= cnt[p] - 1'b1;
      end
    end
  end
endmodule
