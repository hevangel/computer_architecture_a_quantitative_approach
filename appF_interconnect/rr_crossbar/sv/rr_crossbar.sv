// N x N crossbar switch with a round-robin arbiter on every output (Appendix F).
// Each input presents (req, dst, data).  Every output independently picks one of the inputs
// that want it; the pointer moves just past the last winner, so under contention the winners
// rotate fairly and no input can be starved.  Inputs aimed at different outputs are all served
// in the same cycle (that is what a crossbar buys you over a shared bus).  An input whose
// request loses arbitration sees in_gnt = 0 and must retry (head-of-line blocking).
module rr_crossbar #(
    parameter int N = 4,
    parameter int W = 32
) (
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic [N-1:0]               in_req,
    input  logic [N*$clog2(N)-1:0]     in_dst,       // destination output of each input
    input  logic [N*W-1:0]             in_data,
    output logic [N-1:0]               in_gnt,       // input i's flit was accepted this cycle
    output logic [N-1:0]               out_valid,
    output logic [N*$clog2(N)-1:0]     out_src,      // which input won each output
    output logic [N*W-1:0]             out_data
);
  localparam int DW = $clog2(N);
  logic [DW-1:0] ptr [0:N-1];              // per-output: last winner (search starts after it)
  logic [DW-1:0] win [0:N-1];
  logic          found [0:N-1];
  int idx;

  always_comb begin
    in_gnt = '0;
    for (int j = 0; j < N; j++) begin
      found[j] = 1'b0;  win[j] = '0;
      for (int k = 1; k <= N; k++) begin
        idx = (int'(ptr[j]) + k) % N;
        if (!found[j] && in_req[idx] && int'(in_dst[idx*DW +: DW]) == j) begin
          found[j] = 1'b1;  win[j] = DW'(idx);
        end
      end
      out_valid[j]         = found[j];
      out_src[j*DW +: DW]  = win[j];
      out_data[j*W +: W]   = found[j] ? in_data[int'(win[j])*W +: W] : '0;
      if (found[j]) in_gnt[int'(win[j])] = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) for (int j = 0; j < N; j++) ptr[j] <= DW'(N - 1);     // first winner will be input 0
    else        for (int j = 0; j < N; j++) if (found[j]) ptr[j] <= win[j];
  end
endmodule
