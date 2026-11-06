// Vector functional unit with L parallel lanes (Chapter 4 / Appendix G).
// A register file of VREGS vector registers, each MVL elements of 32 bits.  One vector
// instruction occupies the unit for ceil(vl / L) cycles: every cycle the L lanes process the
// next L elements (lanes whose element index is >= vl are masked off).  Doubling the lanes
// halves the time for long vectors -- the central idea of vector machines.
//   op 0 VADD  vd = vs1 + vs2        op 3 VMULS vd = vs1 * scalar
//   op 1 VSUB  vd = vs1 - vs2        op 4 VADDS vd = vs1 + scalar
//   op 2 VMUL  vd = vs1 * vs2
// Elements >= vl of the destination register are left unchanged.  vl must be in 1..MVL.
module vector_unit #(
    parameter int L     = 4,
    parameter int MVL   = 16,
    parameter int VREGS = 8
) (
    input  logic                         clk,
    input  logic                         rst_n,
    // element-wise register access (use only while idle)
    input  logic                         ld_we,
    input  logic [$clog2(VREGS)-1:0]     ld_reg,
    input  logic [$clog2(MVL)-1:0]       ld_idx,
    input  logic [31:0]                  ld_data,
    input  logic [$clog2(VREGS)-1:0]     rd_reg,
    input  logic [$clog2(MVL)-1:0]       rd_idx,
    output logic [31:0]                  rd_data,
    // vector instruction issue
    input  logic                         start,
    input  logic [2:0]                   op,
    input  logic [$clog2(VREGS)-1:0]     vd, vs1, vs2,
    input  logic signed [31:0]           scalar,
    input  logic [$clog2(MVL):0]         vl,
    output logic                         busy
);
  logic signed [31:0] vrf [0:VREGS*MVL-1];
  assign rd_data = vrf[int'(rd_reg)*MVL + int'(rd_idx)];

  logic [2:0]                 op_q;
  logic [$clog2(VREGS)-1:0]   vd_q, vs1_q, vs2_q;
  logic signed [31:0]         sc_q;
  logic [$clog2(MVL):0]       vl_q;
  int                         pos;                         // first element of this cycle's chunk
  logic signed [31:0]         a, b, y;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= 1'b0;  pos <= 0;
      for (int i = 0; i < VREGS*MVL; i++) vrf[i] <= '0;
    end else if (!busy) begin
      if (ld_we) vrf[int'(ld_reg)*MVL + int'(ld_idx)] <= ld_data;
      if (start) begin
        op_q <= op; vd_q <= vd; vs1_q <= vs1; vs2_q <= vs2; sc_q <= scalar; vl_q <= vl;
        pos <= 0;  busy <= 1'b1;
      end
    end else begin
      for (int l = 0; l < L; l++) begin                    // the L lanes work in parallel
        if (pos + l < int'(vl_q)) begin
          a = vrf[int'(vs1_q)*MVL + pos + l];
          b = vrf[int'(vs2_q)*MVL + pos + l];
          case (op_q)
            3'd0:    y = a + b;
            3'd1:    y = a - b;
            3'd2:    y = a * b;
            3'd3:    y = a * sc_q;
            3'd4:    y = a + sc_q;
            default: y = 32'sd0;
          endcase
          vrf[int'(vd_q)*MVL + pos + l] <= y;
        end
      end
      pos <= pos + L;
      if (pos + L >= int'(vl_q)) busy <= 1'b0;
    end
  end
endmodule
