`timescale 1ns/1ps
module tb_hamming_secded;
  logic [63:0] data, dec;
  logic [71:0] code, rx;
  logic        sec, ded;
  secded_encoder enc (.data, .code);
  secded_decoder dcd (.code(rx), .data(dec), .single_err(sec), .double_err(ded));

  int errors = 0, singles = 0, doubles = 0;
  logic [31:0] seed = 32'd99;

  initial begin
    for (int w = 0; w < 12; w++) begin
      seed = seed * 32'd1664525 + 32'd1013904223;  data[63:32] = seed;
      seed = seed * 32'd1664525 + 32'd1013904223;  data[31:0]  = seed;
      if (w == 0) data = 64'd0;
      if (w == 1) data = '1;
      #1;
      rx = code; #1;                                                  // no error
      if (dec !== data || sec || ded) begin errors++; $display("FAIL clean word %h", data); end
      for (int i = 0; i < 72; i++) begin                              // every single-bit error
        rx = code ^ (72'd1 << i); #1;
        singles++;
        if (dec !== data || !sec || ded) begin errors++; $display("FAIL single error at %0d", i); end
      end
      for (int i = 0; i < 72; i++)                                    // every double-bit error
        for (int j = i + 1; j < 72; j++) begin
          rx = code ^ (72'd1 << i) ^ (72'd1 << j); #1;
          doubles++;
          if (sec || !ded) begin errors++; $display("FAIL double error at %0d,%0d", i, j); end
        end
    end
    $display("%0d single-bit and %0d double-bit error patterns checked", singles, doubles);
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
