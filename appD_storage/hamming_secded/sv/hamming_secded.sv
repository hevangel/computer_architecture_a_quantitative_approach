// SECDED (72,64) extended Hamming code: corrects any single-bit error, detects any double-bit
// error.  This is the code used on ECC DRAM DIMMs (8 check bits per 64 data bits).
//
// Codeword layout (index 0 is the LSB):
//   [0]            overall even-parity bit (turns Hamming distance 3 into 4)
//   [1..71]        Hamming positions; check bits sit at the powers of two 1,2,4,...,64
//                  and the 64 data bits fill the remaining positions in ascending order.
// Check bit 2^k covers every position whose index has bit k set.  On decode the syndrome
// *is* the index of the flipped bit.
module secded_encoder (
    input  logic [63:0] data,
    output logic [71:0] code
);
  always_comb begin
    int d;
    code = '0;
    d = 0;
    for (int i = 1; i < 72; i++)
      if ((i & (i - 1)) != 0) begin code[i] = data[d]; d++; end      // not a power of two
    for (int k = 0; k < 7; k++) begin
      logic p;
      p = 1'b0;
      for (int i = 1; i < 72; i++)
        if (((i >> k) & 1) != 0) p ^= code[i];                       // code[2^k] is still 0 here
      code[1 << k] = p;
    end
    code[0] = ^code[71:1];
  end
endmodule

module secded_decoder (
    input  logic [71:0] code,
    output logic [63:0] data,         // corrected data
    output logic        single_err,   // a single-bit error was found and corrected
    output logic        double_err    // uncorrectable (double-bit) error detected
);
  logic [6:0]  syn;
  logic        overall;
  logic [71:0] cw;
  always_comb begin
    int d;
    for (int k = 0; k < 7; k++) begin
      syn[k] = 1'b0;
      for (int i = 1; i < 72; i++)
        if (((i >> k) & 1) != 0) syn[k] ^= code[i];
    end
    overall    = ^code;
    cw         = code;
    single_err = 1'b0;
    double_err = 1'b0;
    if (overall) begin                       // odd number of errors: assume one
      if (syn == 7'd0)      begin single_err = 1'b1; cw[0] ^= 1'b1; end          // the parity bit itself
      else if (syn < 7'd72) begin single_err = 1'b1; cw[syn] ^= 1'b1; end
      else                  double_err = 1'b1;                                   // impossible syndrome
    end else if (syn != 7'd0) begin
      double_err = 1'b1;                     // even number of errors, but nonzero syndrome
    end
    data = '0;
    d = 0;
    for (int i = 1; i < 72; i++)
      if ((i & (i - 1)) != 0) begin data[d] = cw[i]; d++; end
  end
endmodule
