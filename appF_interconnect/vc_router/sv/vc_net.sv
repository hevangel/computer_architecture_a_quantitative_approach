// An NX x NY 2-D mesh of vc_router instances.  Node n = y*NX + x.  Each node has a LOCAL port: flits are injected with inj_valid / inj_flit
// (the injector must respect the per-VC credits: inj_credit_v / inj_credit_vc return one credit per flit popped; start with DEPTH credits per VC; the vc field of an injected flit selects the VC) and ejected on ej_valid / ej_flit.
// Router (x,y) output East feeds router (x+1,y) input West (and credits flow back the opposite way); likewise for the other directions.  Mesh edges are tied off.
module vc_net
  import vc_pkg::*;
#(
    parameter int NX    = 4,
    parameter int NY    = 4,
    parameter int NVC   = 2,
    parameter int DEPTH = 4
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic [NX*NY-1:0]        inj_valid,
    input  logic [NX*NY*FW-1:0]     inj_flit,
    output logic [NX*NY-1:0]        inj_credit_v,
    output logic [NX*NY*2-1:0]      inj_credit_vc,
    output logic [NX*NY-1:0]        ej_valid,
    output logic [NX*NY*FW-1:0]     ej_flit,
    output logic                    err_overflow
);
  localparam int NN = NX * NY;
  logic [NN*5-1:0]    r_in_v, r_cr_in;
  logic [NN*10-1:0]   r_cr_in_vc;
  logic [NN*5*FW-1:0] r_in_f;
  wire  [NN*5-1:0]    r_out_v, r_cr_out;
  wire  [NN*10-1:0]   r_cr_out_vc;
  wire  [NN*5*FW-1:0] r_out_f;
  wire  [NN-1:0]      r_err;
  assign err_overflow = |r_err;

  genvar gx, gy;
  generate
    for (gy = 0; gy < NY; gy++) begin : row
      for (gx = 0; gx < NX; gx++) begin : col
        localparam int n = gy * NX + gx;
        // ---- inputs: neighbours' outputs (N input <- node above's S output, E <- right's W, S <- below's N, W <- left's E)
        if (gy > 0) begin : have_n
          assign r_in_v[n*5 + P_N] = r_out_v[(n - NX)*5 + P_S];
          assign r_in_f[(n*5 + P_N)*FW +: FW] = r_out_f[((n - NX)*5 + P_S)*FW +: FW];
          assign r_cr_in[n*5 + P_N] = r_cr_out[(n - NX)*5 + P_S];
          assign r_cr_in_vc[(n*5 + P_N)*2 +: 2] = r_cr_out_vc[((n - NX)*5 + P_S)*2 +: 2];
        end else begin : no_n
          assign r_in_v[n*5 + P_N] = 1'b0;  assign r_in_f[(n*5 + P_N)*FW +: FW] = '0;  assign r_cr_in[n*5 + P_N] = 1'b0;  assign r_cr_in_vc[(n*5 + P_N)*2 +: 2] = '0;
        end
        if (gx < NX - 1) begin : have_e
          assign r_in_v[n*5 + P_E] = r_out_v[(n + 1)*5 + P_W];
          assign r_in_f[(n*5 + P_E)*FW +: FW] = r_out_f[((n + 1)*5 + P_W)*FW +: FW];
          assign r_cr_in[n*5 + P_E] = r_cr_out[(n + 1)*5 + P_W];
          assign r_cr_in_vc[(n*5 + P_E)*2 +: 2] = r_cr_out_vc[((n + 1)*5 + P_W)*2 +: 2];
        end else begin : no_e
          assign r_in_v[n*5 + P_E] = 1'b0;  assign r_in_f[(n*5 + P_E)*FW +: FW] = '0;  assign r_cr_in[n*5 + P_E] = 1'b0;  assign r_cr_in_vc[(n*5 + P_E)*2 +: 2] = '0;
        end
        if (gy < NY - 1) begin : have_s
          assign r_in_v[n*5 + P_S] = r_out_v[(n + NX)*5 + P_N];
          assign r_in_f[(n*5 + P_S)*FW +: FW] = r_out_f[((n + NX)*5 + P_N)*FW +: FW];
          assign r_cr_in[n*5 + P_S] = r_cr_out[(n + NX)*5 + P_N];
          assign r_cr_in_vc[(n*5 + P_S)*2 +: 2] = r_cr_out_vc[((n + NX)*5 + P_N)*2 +: 2];
        end else begin : no_s
          assign r_in_v[n*5 + P_S] = 1'b0;  assign r_in_f[(n*5 + P_S)*FW +: FW] = '0;  assign r_cr_in[n*5 + P_S] = 1'b0;  assign r_cr_in_vc[(n*5 + P_S)*2 +: 2] = '0;
        end
        if (gx > 0) begin : have_w
          assign r_in_v[n*5 + P_W] = r_out_v[(n - 1)*5 + P_E];
          assign r_in_f[(n*5 + P_W)*FW +: FW] = r_out_f[((n - 1)*5 + P_E)*FW +: FW];
          assign r_cr_in[n*5 + P_W] = r_cr_out[(n - 1)*5 + P_E];
          assign r_cr_in_vc[(n*5 + P_W)*2 +: 2] = r_cr_out_vc[((n - 1)*5 + P_E)*2 +: 2];
        end else begin : no_w
          assign r_in_v[n*5 + P_W] = 1'b0;  assign r_in_f[(n*5 + P_W)*FW +: FW] = '0;  assign r_cr_in[n*5 + P_W] = 1'b0;  assign r_cr_in_vc[(n*5 + P_W)*2 +: 2] = '0;
        end
        // ---- local port
        assign r_in_v[n*5 + P_L] = inj_valid[n];
        assign r_in_f[(n*5 + P_L)*FW +: FW] = inj_flit[n*FW +: FW];
        assign r_cr_in[n*5 + P_L] = 1'b0;  assign r_cr_in_vc[(n*5 + P_L)*2 +: 2] = '0;
        assign inj_credit_v[n] = r_cr_out[n*5 + P_L];  assign inj_credit_vc[n*2 +: 2] = r_cr_out_vc[(n*5 + P_L)*2 +: 2];
        assign ej_valid[n] = r_out_v[n*5 + P_L];
        assign ej_flit[n*FW +: FW] = r_out_f[(n*5 + P_L)*FW +: FW];

        vc_router #(.X(gx), .Y(gy), .NX(NX), .NY(NY), .NVC(NVC), .DEPTH(DEPTH)) u_r (
            .clk, .rst_n,
            .in_valid(r_in_v[n*5 +: 5]), .in_flit(r_in_f[n*5*FW +: 5*FW]), .in_credit_v(r_cr_out[n*5 +: 5]), .in_credit_vc(r_cr_out_vc[n*10 +: 10]),
            .out_valid(r_out_v[n*5 +: 5]), .out_flit(r_out_f[n*5*FW +: 5*FW]), .out_credit_v(r_cr_in[n*5 +: 5]), .out_credit_vc(r_cr_in_vc[n*10 +: 10]),
            .err_overflow(r_err[n]));
      end
    end
  endgenerate
endmodule
