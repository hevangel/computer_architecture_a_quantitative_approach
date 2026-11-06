// Signed 16x16 -> 32-bit multiplier using radix-4 Booth recoding (Appendix J).
// Recoding the multiplier two bits at a time halves the number of partial products:
// each step examines bits (b[2i+1], b[2i], b[2i-1]) and adds one of 0, +-M, +-2M, shifted by 2i.
// Latency: 8 clock cycles after `start`.  `done` is high while the product is valid.
module booth_multiplier (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,          // sample a and b, begin multiplying
    input  logic signed [15:0] a,              // multiplicand
    input  logic signed [15:0] b,              // multiplier
    output logic               busy,
    output logic               done,
    output logic signed [31:0] product
);
  logic signed [31:0] m;        // multiplicand, shifted left by 2 each step
  logic        [16:0] q;        // {multiplier, 0}, shifted right by 2 each step
  logic signed [31:0] acc;
  logic        [3:0]  steps;

  logic signed [31:0] term;
  always_comb begin
    case (q[2:0])
      3'b001, 3'b010: term = m;
      3'b011:         term = m <<< 1;
      3'b100:         term = -(m <<< 1);
      3'b101, 3'b110: term = -m;
      default:        term = 32'sd0;            // 000 and 111
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= 0; done <= 0; acc <= 0; m <= 0; q <= 0; steps <= 0;
    end else begin
      if (start && !busy) begin
        m <= 32'(a);  q <= {b, 1'b0};  acc <= 0;  steps <= 0;  busy <= 1;  done <= 0;
      end else if (busy) begin
        acc   <= acc + term;
        m     <= m <<< 2;
        q     <= q >> 2;
        steps <= steps + 1;
        if (steps == 4'd7) begin busy <= 0; done <= 1; end
      end
      if (done && start) done <= 0;
    end
  end
  assign product = acc;
endmodule
