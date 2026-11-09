// A TORUS router with DATELINE virtual-channel classes (Appendix F: topology, deadlock avoidance with virtual channels).
//
// A torus adds wrap-around links to the mesh: every row and every column is a RING.  Dimension-order routing now takes the SHORTER way round each ring (a tie goes in the positive
// direction: East / South).  The wrap-around links create a problem the mesh never had: the packets of one ring can wait for each other in a cycle -- with wormhole switching and ONE virtual
// channel the ring DEADLOCKS (every packet holds the link it is on and waits for the link ahead).
//
// DATELINE fix (Dally & Seitz): cut each ring at a "dateline" (the wrap-around link, router NX-1 -> 0 and 0 -> NX-1, likewise in Y) and split the virtual channels into two CLASSES.
//   * a packet starts every dimension in class 0 (the lower half of the VCs);
//   * a packet that crosses the dateline link moves to class 1 (the upper half) and stays there until it leaves that dimension (a packet never goes round more than half a ring, so it
//     crosses the dateline at most once);
//   * when a packet turns into the next dimension it starts again in class 0.
// Within a ring, class-0 channels only ever wait for class-0 channels further along, up to the dateline, and class-1 channels wait only for class-1 channels beyond it: the channel
// dependency graph has no cycle, so there is no deadlock.  (DATELINE = 0 disables the classes, to demonstrate the deadlock.)
// Everything else -- VC allocation, separable switch allocation, per-VC credits, 3 cycles per router for a head flit -- is as in vc_router.
module torus_router
  import vc_pkg::*;
#(
    parameter int X     = 0,
    parameter int Y     = 0,
    parameter int NX    = 4,
    parameter int NY    = 4,
    parameter int NVC   = 2,
    parameter int DEPTH = 4,
    parameter bit DATELINE = 1'b1       // 1: dateline VC classes (needs an even NVC >= 2)
) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic [4:0]          in_valid,
    input  logic [5*FW-1:0]     in_flit,
    output logic [4:0]          in_credit_v,     // pulse: a flit left an input FIFO of port p ...
    output logic [9:0]          in_credit_vc,    // ... of this virtual channel (2 bits per port)
    output logic [4:0]          out_valid,
    output logic [5*FW-1:0]     out_flit,
    input  logic [4:0]          out_credit_v,    // pulses from the downstream routers
    input  logic [9:0]          out_credit_vc,
    output logic                err_overflow     // sticky: an input FIFO was written while full (flow-control violation)
);
  localparam int IV = 5 * NVC;                                 // input virtual channels, index p*NVC + v
  localparam int PW = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  localparam int CW = $clog2(DEPTH + 1);

  logic [FW-1:0] fifo [0:IV*DEPTH-1];
  logic [PW-1:0] rd [0:IV-1], wr [0:IV-1];
  logic [CW-1:0] cnt [0:IV-1];
  logic          st_act [0:IV-1];                              // input VC has been allocated an output VC
  logic [2:0]    st_op [0:IV-1];
  logic [1:0]    st_ov [0:IV-1];
  logic          ovb [0:IV-1];                                 // output VC (index o*NVC + ov) is owned by a packet
  logic [CW-1:0] cred [0:IV-1];
  logic [4:0]    va_rr [0:4];                                  // last VA winner (input VC index) per output port
  logic [1:0]    sa_in_rr [0:4];                               // last SA winner (vc) per input port
  logic [2:0]    sa_out_rr [0:4];                              // last SA winner (input port) per output port

  // ---- head-of-FIFO decode and XY route --------------------------------------------------------------------------------
  logic [FW-1:0] hf [0:IV-1];
  logic          nonempty [0:IV-1], is_head [0:IV-1], is_tail [0:IV-1];
  logic [2:0]    route [0:IV-1];
  int            dxm, dym;
  always_comb begin
    for (int i = 0; i < IV; i++) begin
      hf[i]       = fifo[i*DEPTH + int'(rd[i])];
      nonempty[i] = (cnt[i] != '0);
      is_head[i]  = (hf[i][FW-1:FW-2] == T_HEAD) || (hf[i][FW-1:FW-2] == T_SINGLE);
      is_tail[i]  = (hf[i][FW-1:FW-2] == T_TAIL) || (hf[i][FW-1:FW-2] == T_SINGLE);
      dxm = (int'(hf[i][27:24]) + NX - X) % NX;
      dym = (int'(hf[i][31:28]) + NY - Y) % NY;
      if      (dxm != 0) route[i] = (dxm <= NX / 2) ? 3'(P_E) : 3'(P_W);       // shorter way round the X ring, ties go East
      else if (dym != 0) route[i] = (dym <= NY / 2) ? 3'(P_S) : 3'(P_N);       // then the Y ring, ties go South
      else               route[i] = 3'(P_L);
    end
  end

  // ---- VC allocation: one grant per output port per cycle ---------------------------------------------------------------
  logic       va_v [0:4];
  logic [4:0] va_iv [0:4];
  logic [1:0] va_ov [0:4];
  int         pk, pp, vv, lo, hi, dimi, dimo, ov_found;
  logic       wrp, cin, cout;
  always_comb begin
    pk = 0;
    for (int o = 0; o < 5; o++) begin
      va_v[o] = 1'b0;  va_iv[o] = '0;  va_ov[o] = '0;
      // dimension of the output port (1 = X ring, 2 = Y ring) and whether its link is the wrap-around (dateline) link
      dimo = (o == P_E || o == P_W) ? 1 : (o == P_N || o == P_S) ? 2 : 0;
      wrp  = (o == P_E && X == NX - 1) || (o == P_W && X == 0) || (o == P_S && Y == NY - 1) || (o == P_N && Y == 0);
      for (int k = 1; k <= IV; k++) begin
        pk = (int'(va_rr[o]) + k) % IV;
        pp = 0;  vv = 0;  dimi = 0;  cin = 1'b0;  cout = 1'b0;  lo = 0;  hi = 0;  ov_found = -1;       // scratch values (no latches)
        if (!va_v[o] && nonempty[pk] && !st_act[pk] && is_head[pk] && int'(route[pk]) == o) begin
          pp = pk / NVC;  vv = pk % NVC;
          dimi = (pp == P_E || pp == P_W) ? 1 : (pp == P_N || pp == P_S) ? 2 : 0;
          cin  = (vv >= NVC / 2);
          // class of the output VC: keep the class while going on in the same ring, set it when crossing the dateline, restart at 0 in a new dimension
          cout = wrp ? 1'b1 : ((dimi == dimo) ? cin : 1'b0);
          if (!DATELINE || o == P_L) begin lo = 0; hi = NVC - 1; end
          else begin lo = cout ? NVC / 2 : 0; hi = cout ? NVC - 1 : NVC / 2 - 1; end
          ov_found = -1;
          for (int ov = NVC - 1; ov >= 0; ov--) if (ov >= lo && ov <= hi && !ovb[o*NVC + ov]) ov_found = ov;
          if (ov_found >= 0) begin va_v[o] = 1'b1; va_iv[o] = 5'(pk); va_ov[o] = 2'(ov_found); end
        end
      end
    end
  end

  // ---- switch allocation: input stage (one VC per input port), output stage (one input port per output port) -------------------
  logic       cand_v [0:4];
  logic [4:0] cand_iv [0:4];
  logic       win_v [0:4];
  logic [4:0] win_iv [0:4];
  logic [2:0] win_p [0:4];
  logic [4:0] fwd_p;
  logic       fwd [0:IV-1];
  int         qv, qp;
  always_comb begin
    qv = 0;  qp = 0;
    for (int p = 0; p < 5; p++) begin
      cand_v[p] = 1'b0;  cand_iv[p] = '0;
      for (int k = 1; k <= NVC; k++) begin
        qv = (int'(sa_in_rr[p]) + k) % NVC;
        if (!cand_v[p] && st_act[p*NVC + qv] && nonempty[p*NVC + qv] &&
            (int'(st_op[p*NVC + qv]) == P_L || cred[int'(st_op[p*NVC + qv])*NVC + int'(st_ov[p*NVC + qv])] != '0)) begin
          cand_v[p] = 1'b1;  cand_iv[p] = 5'(p*NVC + qv);
        end
      end
    end
    for (int o = 0; o < 5; o++) begin
      win_v[o] = 1'b0;  win_iv[o] = '0;  win_p[o] = '0;
      for (int k = 1; k <= 5; k++) begin
        qp = (int'(sa_out_rr[o]) + k) % 5;
        if (!win_v[o] && cand_v[qp] && int'(st_op[cand_iv[qp]]) == o) begin win_v[o] = 1'b1; win_iv[o] = cand_iv[qp]; win_p[o] = 3'(qp); end
      end
    end
    fwd_p = '0;
    for (int i = 0; i < IV; i++) fwd[i] = 1'b0;
    for (int o = 0; o < 5; o++) if (win_v[o]) begin fwd[int'(win_iv[o])] = 1'b1; fwd_p[int'(win_p[o])] = 1'b1; end
  end

  // ---- state update ----------------------------------------------------------------------------------------------------
  logic [FW-1:0] sf;
  logic          dec_c, inc_c;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_valid <= '0;  out_flit <= '0;  in_credit_v <= '0;  in_credit_vc <= '0;  err_overflow <= 1'b0;
      for (int i = 0; i < IV; i++) begin
        rd[i] <= '0; wr[i] <= '0; cnt[i] <= '0; st_act[i] <= 1'b0; st_op[i] <= '0; st_ov[i] <= '0; ovb[i] <= 1'b0; cred[i] <= CW'(DEPTH);
      end
      for (int o = 0; o < 5; o++) begin va_rr[o] <= 5'(IV - 1); sa_in_rr[o] <= 2'(NVC - 1); sa_out_rr[o] <= 3'd4; end
      for (int i = 0; i < IV*DEPTH; i++) fifo[i] <= '0;
    end else begin
      // VC allocation results
      for (int o = 0; o < 5; o++) if (va_v[o]) begin
        st_act[int'(va_iv[o])] <= 1'b1;  st_op[int'(va_iv[o])] <= 3'(o);  st_ov[int'(va_iv[o])] <= va_ov[o];
        ovb[o*NVC + int'(va_ov[o])] <= 1'b1;  va_rr[o] <= va_iv[o];
      end
      // switch allocation results: the flit moves into the output register
      for (int o = 0; o < 5; o++) begin
        out_valid[o] <= win_v[o];
        if (win_v[o]) begin
          sf = hf[int'(win_iv[o])];  sf[33:32] = st_ov[int'(win_iv[o])];
          out_flit[o*FW +: FW] <= sf;
          sa_out_rr[o] <= win_p[o];
          sa_in_rr[int'(win_p[o])] <= 2'(int'(win_iv[o]) % NVC);
          if (is_tail[int'(win_iv[o])]) begin
            st_act[int'(win_iv[o])] <= 1'b0;  ovb[o*NVC + int'(st_ov[int'(win_iv[o])])] <= 1'b0;
          end
        end
      end
      // credit counters, one per output VC
      for (int o = 0; o < 5; o++)
        for (int ov = 0; ov < NVC; ov++) begin
          dec_c = (o != P_L) && win_v[o] && (int'(st_ov[int'(win_iv[o])]) == ov);
          inc_c = out_credit_v[o] && (int'(out_credit_vc[2*o +: 2]) == ov);
          if (dec_c && !inc_c)      cred[o*NVC + ov] <= cred[o*NVC + ov] - 1'b1;
          else if (!dec_c && inc_c) cred[o*NVC + ov] <= cred[o*NVC + ov] + 1'b1;
        end
      // input FIFOs
      for (int p = 0; p < 5; p++) begin
        in_credit_v[p] <= fwd_p[p];
        in_credit_vc[2*p +: 2] <= 2'd0;
      end
      for (int o = 0; o < 5; o++) if (win_v[o]) in_credit_vc[2*int'(win_p[o]) +: 2] <= 2'(int'(win_iv[o]) % NVC);
      for (int p = 0; p < 5; p++) if (in_valid[p]) begin
        int v;  v = int'(in_flit[p*FW + 32 +: 2]);
        fifo[(p*NVC + v)*DEPTH + int'(wr[p*NVC + v])] <= in_flit[p*FW +: FW];
      end
      for (int i = 0; i < IV; i++) begin
        logic wr_i;  wr_i = in_valid[i / NVC] && (int'(in_flit[(i / NVC)*FW + 32 +: 2]) == (i % NVC));
        if (wr_i) begin
          wr[i] <= (int'(wr[i]) == DEPTH - 1) ? '0 : wr[i] + 1'b1;
          if (cnt[i] == CW'(DEPTH)) err_overflow <= 1'b1;
        end
        if (fwd[i]) rd[i] <= (int'(rd[i]) == DEPTH - 1) ? '0 : rd[i] + 1'b1;
        if (wr_i && !fwd[i])      cnt[i] <= cnt[i] + 1'b1;
        else if (!wr_i && fwd[i]) cnt[i] <= cnt[i] - 1'b1;
      end
    end
  end
endmodule
