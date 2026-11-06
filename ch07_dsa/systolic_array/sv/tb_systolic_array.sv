`timescale 1ns/1ps
module tb_systolic_array;
  localparam int N = 4, M = 9, DW = 8, AW = 32;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic w_we = 0;  logic [1:0] w_row = 0;  logic [N*DW-1:0] w_data = 0;
  logic in_valid = 0;  logic [N*DW-1:0] a_in = 0;
  logic out_valid;  logic [N*AW-1:0] c_out;

  systolic_array #(.N(N), .DATA_W(DW), .ACC_W(AW)) dut (.*);

  logic signed [DW-1:0] W [N][N];
  logic signed [DW-1:0] A [M][N];
  logic signed [AW-1:0] C [M][N];            // golden result from plain nested loops
  logic [31:0] seed = 32'd31337;
  function automatic logic signed [DW-1:0] rnd8();
    seed = seed * 32'd1664525 + 32'd1013904223; return seed[23:16];
  endfunction

  logic signed [AW-1:0] ax, wx;
  int errors = 0, got = 0;
  int sent_cycle [M];
  int cycle = 0;
  always_ff @(posedge clk) cycle <= cycle + 1;

  // result checker: every valid output row must equal the next golden row, exactly 2N-1 cycles after it was sent
  always @(posedge clk) if (out_valid && rst_n) begin
    for (int n = 0; n < N; n++)
      if ($signed(c_out[n*AW +: AW]) !== C[got][n]) begin
        errors++; $display("FAIL C[%0d][%0d] = %0d, expected %0d", got, n, $signed(c_out[n*AW +: AW]), C[got][n]);
      end
    if (cycle - sent_cycle[got] != 2*N - 1) begin
      errors++; $display("FAIL latency of row %0d: %0d cycles", got, cycle - sent_cycle[got]);
    end
    got++;
  end

  initial begin
    for (int k = 0; k < N; k++) for (int n = 0; n < N; n++) W[k][n] = rnd8();
    for (int m = 0; m < M; m++) for (int k = 0; k < N; k++) A[m][k] = rnd8();
    W[0][0] = -128; A[0][0] = -128; A[1][1] = 127; W[1][1] = 127;           // extreme values
    for (int m = 0; m < M; m++) for (int n = 0; n < N; n++) begin
      C[m][n] = 0;
      for (int k = 0; k < N; k++) begin
        ax = A[m][k]; wx = W[k][n];                  // widen first: Icarus mis-extends narrow array elements
        C[m][n] = C[m][n] + ax * wx;
      end
    end

    repeat (3) @(negedge clk); rst_n = 1;
    for (int k = 0; k < N; k++) begin                                      // load weights, one row per cycle
      @(negedge clk); w_we = 1; w_row = k[1:0];
      for (int n = 0; n < N; n++) w_data[n*DW +: DW] = W[k][n];
    end
    @(negedge clk); w_we = 0;

    for (int m = 0; m < M; m++) begin                                      // stream A: 5 back-to-back rows, a gap, 4 more
      if (m == 5) begin @(negedge clk); in_valid = 0; repeat (3) @(negedge clk); end   // idle gap
      @(negedge clk);
      in_valid = 1;  sent_cycle[m] = cycle;
      for (int k = 0; k < N; k++) a_in[k*DW +: DW] = A[m][k];
    end
    @(negedge clk); in_valid = 0; a_in = '0;
    repeat (3*N) @(negedge clk);

    if (got != M) begin errors++; $display("FAIL: received %0d of %0d result rows", got, M); end
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
