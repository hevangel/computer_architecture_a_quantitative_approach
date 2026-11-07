// A 64-bit packed-subword SIMD ALU (Chapter 4: SIMD instruction-set extensions such as MMX / SSE / AVX).
//
// One 64-bit register is treated as 8 x 8-bit, 4 x 16-bit or 2 x 32-bit lanes (esize = 0, 1, 2) and one instruction operates on every lane at once:
// "subword parallelism" -- the existing wide datapath does 8 byte operations instead of 1.
//
//   op  name     per lane                                                  op  name     per lane
//    0  PADD     a + b (wraps)                                             10  PAVGU    (a + b + 1) >> 1, unsigned (rounding average)
//    1  PSUB     a - b (wraps)                                             11  PCMPEQ   all ones if a == b else 0
//    2  PADDS    signed saturating add                                     12  PCMPGTS  all ones if a > b (signed) else 0
//    3  PSUBS    signed saturating subtract                                13  PMULLO   low half of a * b
//    4  PADDUS   unsigned saturating add                                   14  PMADD    (esize 1 only) y32[i] = a[2i]*b[2i] + a[2i+1]*b[2i+1], signed
//    5  PSUBUS   unsigned saturating subtract (floors at 0)                15  PSLL     a << imm  (0 when imm >= lane width)
//    6  PMINU    unsigned minimum                                          16  PSRL     a >> imm  logical
//    7  PMAXU    unsigned maximum                                          17  PSRA     a >> imm  arithmetic (sign fill when imm >= width)
//    8  PMINS    signed minimum                                            18  PSAD     (esize 0 only) y[15:0] = sum over 8 bytes of |a - b|, rest 0
//    9  PMAXS    signed maximum
//
// PADD and PSUB are implemented the way hardware does it: ONE 64-bit adder/subtractor whose carry (borrow) is killed at every lane boundary
// by handling the lane MSBs separately ("SWAR"):   sum = ((a & ~H) + (b & ~H)) ^ ((a ^ b) & H),   H = the lane MSB mask.
// Everything else is computed lane by lane.  Purely combinational.
module simd_alu (
    input  logic [1:0]  esize,           // 0: 8-bit lanes, 1: 16-bit, 2: 32-bit
    input  logic [4:0]  op,
    input  logic [63:0] a,
    input  logic [63:0] b,
    input  logic [5:0]  imm,             // shift count
    output logic [63:0] y
);
  logic [63:0] H, sum_swar, diff_swar;
  always_comb begin
    case (esize)
      2'd0:    H = 64'h8080_8080_8080_8080;
      2'd1:    H = 64'h8000_8000_8000_8000;
      default: H = 64'h8000_0000_8000_0000;
    endcase
    sum_swar  = ((a & ~H) + (b & ~H)) ^ ((a ^ b) & H);                       // one adder, carries cannot cross a lane boundary
    diff_swar = ((a | H) - (b & ~H)) ^ ((a ^ ~b) & H);                       // one subtractor, borrows cannot cross
  end

  int lw, nl;
  logic [63:0] lmask;
  logic signed [63:0] ua, ub, sa, sb, r, smax, smin, umax;
  logic signed [31:0] acc;                               // PMADD partial sum (declared here, defaulted below: no inferred latch)
  logic [15:0]        sad;                               // PSAD running sum
  always_comb begin
    lw = 8 << esize;  nl = 64 / lw;
    lmask = (lw == 64) ? '1 : ((64'd1 << lw) - 64'd1);
    smax = (64'sd1 << (lw - 1)) - 64'sd1;  smin = -(64'sd1 << (lw - 1));  umax = lmask;
    y = 64'd0;
    ua = 0; ub = 0; sa = 0; sb = 0; r = 0; acc = 0; sad = 0;
    if (op == 5'd0) y = sum_swar;
    else if (op == 5'd1) y = diff_swar;
    else if (op == 5'd14) begin                                              // PMADD: signed 16x16 products added in pairs -> 32-bit lanes
      for (int i = 0; i < 2; i++) begin
        acc = $signed(a[32*i +: 16]) * $signed(b[32*i +: 16]) + $signed(a[32*i + 16 +: 16]) * $signed(b[32*i + 16 +: 16]);
        y[32*i +: 32] = acc;
      end
    end else if (op == 5'd18) begin                                          // PSAD: sum of absolute differences of 8 unsigned bytes
      for (int i = 0; i < 8; i++) sad = sad + ((a[8*i +: 8] > b[8*i +: 8]) ? (a[8*i +: 8] - b[8*i +: 8]) : (b[8*i +: 8] - a[8*i +: 8]));
      y = {48'd0, sad};
    end else begin
      for (int l = 0; l < 8; l++) if (l < nl) begin
        ua = (a >> (l * lw)) & lmask;  ub = (b >> (l * lw)) & lmask;         // unsigned lane values (non-negative in 64 bits)
        sa = (ua << (64 - lw)) >>> (64 - lw);  sb = (ub << (64 - lw)) >>> (64 - lw);   // sign-extended lane values
        r = 0;
        case (op)
          5'd2:  begin r = sa + sb; if (r > smax) r = smax; if (r < smin) r = smin; end
          5'd3:  begin r = sa - sb; if (r > smax) r = smax; if (r < smin) r = smin; end
          5'd4:  begin r = ua + ub; if (r > umax) r = umax; end
          5'd5:  begin r = ua - ub; if (r < 0) r = 0; end
          5'd6:  r = (ua < ub) ? ua : ub;
          5'd7:  r = (ua > ub) ? ua : ub;
          5'd8:  r = (sa < sb) ? sa : sb;
          5'd9:  r = (sa > sb) ? sa : sb;
          5'd10: r = (ua + ub + 64'sd1) >>> 1;
          5'd11: r = (ua == ub) ? -64'sd1 : 64'sd0;
          5'd12: r = (sa > sb) ? -64'sd1 : 64'sd0;
          5'd13: r = ua * ub;
          5'd15: r = (int'(imm) >= lw) ? 64'sd0 : (ua << imm);
          5'd16: r = (int'(imm) >= lw) ? 64'sd0 : (ua >> imm);
          5'd17: r = (int'(imm) >= lw) ? (sa >>> 63) : (sa >>> imm);
          default: r = 0;
        endcase
        y = y | ((r & lmask) << (l * lw));
      end
    end
  end
endmodule
