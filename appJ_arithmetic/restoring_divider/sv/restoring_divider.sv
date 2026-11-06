// Unsigned 16-bit restoring divider (Appendix J): one quotient bit per clock.
// Each step shifts the partial remainder left, brings down the next dividend bit and
// tries to subtract the divisor; if the result would be negative the subtraction is
// "restored" (not committed) and the quotient bit is 0.
// Division by zero follows the RISC-V convention: quotient = all ones, remainder = dividend.
// Latency: 16 cycles after `start`.
module restoring_divider (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [15:0] dividend,
    input  logic [15:0] divisor,
    output logic        busy,
    output logic        done,
    output logic [15:0] quotient,
    output logic [15:0] remainder
);
  logic [15:0] n, d, q;
  logic [16:0] r;
  logic [4:0]  bit_idx;

  logic [16:0] shifted, diff;
  always_comb begin
    shifted = {r[15:0], n[15]};
    diff    = shifted - {1'b0, d};
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= 0; done <= 0; n <= 0; d <= 0; q <= 0; r <= 0; bit_idx <= 0;
    end else begin
      if (start && !busy) begin
        n <= dividend; d <= divisor; q <= 0; r <= 0; bit_idx <= 0; busy <= 1; done <= 0;
      end else if (busy) begin
        n <= {n[14:0], 1'b0};
        if (!diff[16]) begin r <= diff;    q <= {q[14:0], 1'b1}; end   // fits: commit
        else           begin r <= shifted; q <= {q[14:0], 1'b0}; end   // restore
        bit_idx <= bit_idx + 1;
        if (bit_idx == 5'd15) begin busy <= 0; done <= 1; end
      end
      if (done && start) done <= 0;
    end
  end
  assign quotient  = q;
  assign remainder = r[15:0];
endmodule
