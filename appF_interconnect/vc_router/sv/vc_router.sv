// A VIRTUAL-CHANNEL wormhole router (Appendix F: virtual channels, VC allocation, switch allocation).
//
// Every input port has NVC virtual channels: NVC separate flit FIFOs (DEPTH flits each) that share the one physical link.  A packet occupies ONE virtual channel
// per hop from head to tail, but the flits of packets in different virtual channels are interleaved on the link, flit by flit.  Consequence: a packet that is blocked
// (its output is busy or has no credits) no longer blocks the packets queued behind it in OTHER virtual channels -- no head-of-line blocking.
//
//   * ROUTING: dimension-order (XY), as in mesh_router.
//   * VC ALLOCATION (VA): the head flit of a packet at the front of an idle input VC asks for an output port; each output port grants one request per cycle (round-robin) and
//     gives the winner the lowest FREE output VC (a VC is free from the head's grant until the tail has been sent).  A head therefore spends one extra cycle in the router.
//   * SWITCH ALLOCATION (SA): separable, two stages.  Each input port picks (round-robin) one of its VCs that has an allocated output VC, a flit and a CREDIT for the downstream
//     VC buffer; each output port then picks (round-robin) one of the input ports that chose it.  The winning flit is moved into the output register with its vc field rewritten
//     to the output VC.
//   * FLOW CONTROL: one credit counter per output VC (initially DEPTH); a credit pulse carries the VC number (in_credit_v / in_credit_vc: one pop per input port per cycle).
//     The Local (ejection) output needs no credits.
// Pipeline: a head flit written to an input FIFO at the end of cycle c wins VA in c+1, SA in c+2 and is on the output link during c+3: THREE cycles per router.  Body and tail
// flits need only SA: two cycles.  The credit round trip per VC is four cycles, as in mesh_router, so DEPTH = 4 per VC sustains one flit per cycle for a single stream.
module vc_router
  import vc_pkg::*;
#(
    parameter int X     = 0,
    parameter int Y     = 0,
    parameter int NX    = 4,
    parameter int NY    = 4,
    parameter int NVC   = 2,
    parameter int DEPTH = 4
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
  always_comb begin
    for (int i = 0; i < IV; i++) begin
      hf[i]       = fifo[i*DEPTH + int'(rd[i])];
      nonempty[i] = (cnt[i] != '0);
      is_head[i]  = (hf[i][FW-1:FW-2] == T_HEAD) || (hf[i][FW-1:FW-2] == T_SINGLE);
      is_tail[i]  = (hf[i][FW-1:FW-2] == T_TAIL) || (hf[i][FW-1:FW-2] == T_SINGLE);
      if      (int'(hf[i][27:24]) > X) route[i] = 3'(P_E);
      else if (int'(hf[i][27:24]) < X) route[i] = 3'(P_W);
      else if (int'(hf[i][31:28]) > Y) route[i] = 3'(P_S);
      else if (int'(hf[i][31:28]) < Y) route[i] = 3'(P_N);
      else                             route[i] = 3'(P_L);
    end
  end

  // ---- VC allocation: one grant per output port per cycle ---------------------------------------------------------------
  logic       va_v [0:4];
  logic [4:0] va_iv [0:4];
  logic [1:0] va_ov [0:4];
  int         pk;
  logic       fo_ok;  logic [1:0] fo;
  always_comb begin
    pk = 0;
    for (int o = 0; o < 5; o++) begin
      va_v[o] = 1'b0;  va_iv[o] = '0;  va_ov[o] = '0;
      fo_ok = 1'b0;  fo = '0;
      for (int ov = NVC - 1; ov >= 0; ov--) if (!ovb[o*NVC + ov]) begin fo_ok = 1'b1; fo = 2'(ov); end
      if (fo_ok)
        for (int k = 1; k <= IV; k++) begin
          pk = (int'(va_rr[o]) + k) % IV;
          if (!va_v[o] && nonempty[pk] && !st_act[pk] && is_head[pk] && int'(route[pk]) == o) begin va_v[o] = 1'b1; va_iv[o] = 5'(pk); va_ov[o] = fo; end
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
