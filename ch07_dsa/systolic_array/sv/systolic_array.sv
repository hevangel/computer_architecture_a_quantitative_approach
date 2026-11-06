// Weight-stationary N x N systolic matrix-multiply unit, the core of Google's TPU (Chapter 7).
//
//   C[m][n] = sum_k A[m][k] * W[k][n]        A: int8 activations   W: int8 weights   C: int32
//
// Each PE(k,n) holds weight W[k][n].  Activations flow left-to-right, partial sums top-to-bottom.
// One activation row A[m][*] is presented per cycle; row k is delayed by k cycles on the way in
// (the "skew") so that each wavefront meets the right partial sum, and column n is delayed by
// N-1-n cycles on the way out so a whole result row C[m][*] appears together.
// Latency: a row presented in cycle m is valid at c_out in cycle m + 2N - 1; throughput is one
// row per cycle -- N*N MACs per cycle once the pipeline is full.
module systolic_array #(
    parameter int N      = 4,
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
) (
    input  logic                       clk,
    input  logic                       rst_n,
    // weight load: write row w_row of W (N weights per write)
    input  logic                       w_we,
    input  logic [$clog2(N)-1:0]       w_row,
    input  logic [N*DATA_W-1:0]        w_data,
    // activation stream: one row of A per cycle
    input  logic                       in_valid,
    input  logic [N*DATA_W-1:0]        a_in,
    // result stream: one row of C per cycle, 2N-1 cycles later
    output logic                       out_valid,
    output logic [N*ACC_W-1:0]         c_out
);
  localparam int LAT = 2 * N - 1;

  logic signed [DATA_W-1:0] wt    [0:N*N-1];   // stationary weights, index k*N+n
  logic signed [DATA_W-1:0] a_reg [0:N*N-1];   // activation register in PE(k,n)
  logic signed [ACC_W-1:0]  p_reg [0:N*N-1];   // partial-sum register in PE(k,n)
  logic signed [DATA_W-1:0] dl    [0:N*N-1];   // input skew delay lines, row k uses dl[k*N + 0 .. k-1]
  logic signed [ACC_W-1:0]  od    [0:N*N-1];   // output de-skew delay lines, column n uses od[n*N + 0 .. N-2-n]
  logic [LAT-1:0]           vpipe;

  logic signed [DATA_W-1:0] a_w [0:N*N-1];     // activation entering PE(k,n)
  logic signed [ACC_W-1:0]  p_w [0:N*N-1];     // partial sum entering PE(k,n)
  logic signed [ACC_W-1:0]  col [0:N-1];       // de-skewed column outputs
  logic signed [ACC_W-1:0]  prod [0:N*N-1];    // a*w of each PE
  logic signed [ACC_W-1:0]  ax, wx;            // operands sign-extended to ACC_W before multiplying
                                               // (Icarus mis-extends narrow signed array elements otherwise)

  always_comb begin
    for (int k = 0; k < N; k++)
      for (int n = 0; n < N; n++) begin
        if (n == 0) a_w[k*N+n] = (k == 0) ? $signed(a_in[0 +: DATA_W]) : dl[k*N + k - 1];
        else        a_w[k*N+n] = a_reg[k*N + n - 1];
        p_w[k*N+n] = (k == 0) ? '0 : p_reg[(k-1)*N + n];
        ax = a_w[k*N+n];
        wx = wt[k*N+n];
        prod[k*N+n] = ax * wx;
      end
    for (int n = 0; n < N; n++)
      col[n] = (n == N - 1) ? p_reg[(N-1)*N + n] : od[n*N + (N - 2 - n)];
    for (int n = 0; n < N; n++) c_out[n*ACC_W +: ACC_W] = col[n];
    out_valid = vpipe[LAT-1];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      vpipe <= '0;
      for (int i = 0; i < N*N; i++) begin a_reg[i] <= '0; p_reg[i] <= '0; dl[i] <= '0; od[i] <= '0; end
    end else begin
      vpipe <= {vpipe[LAT-2:0], in_valid};
      for (int k = 0; k < N; k++)
        for (int n = 0; n < N; n++) begin
          a_reg[k*N+n] <= a_w[k*N+n];
          p_reg[k*N+n] <= p_w[k*N+n] + prod[k*N+n];                      // the MAC
        end
      for (int k = 1; k < N; k++) begin                               // input skew: row k delayed k cycles
        dl[k*N + 0] <= $signed(a_in[k*DATA_W +: DATA_W]);
        for (int j = 1; j < k; j++) dl[k*N + j] <= dl[k*N + j - 1];
      end
      for (int n = 0; n < N - 1; n++) begin                           // output de-skew: column n delayed N-1-n
        od[n*N + 0] <= p_reg[(N-1)*N + n];
        for (int j = 1; j < N - 1 - n; j++) od[n*N + j] <= od[n*N + j - 1];
      end
    end
  end

  always_ff @(posedge clk)
    if (w_we)
      for (int n = 0; n < N; n++) wt[w_row*N + n] <= $signed(w_data[n*DATA_W +: DATA_W]);
endmodule
