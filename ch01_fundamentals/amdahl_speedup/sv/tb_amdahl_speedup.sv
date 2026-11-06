`timescale 1ns/1ps
module tb_amdahl_speedup;
  logic [16:0] f;
  logic [15:0] s;
  logic [31:0] y;
  int errors = 0;

  amdahl_speedup dut (.f_q16(f), .s_q8_8(s), .speedup_q16(y));

  // expected values were computed with exact rationals (see README)
  task automatic check(input [16:0] f_i, input [15:0] s_i, input int expected_q16, input string name);
    int diff;
    f = f_i; s = s_i; #1;
    diff = int'(y) - expected_q16;
    if (diff < 0) diff = -diff;
    if (diff > 128) begin
      errors++;
      $display("FAIL %s: got %0d expected %0d (Q16.16)", name, y, expected_q16);
    end else
      $display("ok   %s: speedup = %f", name, y / 65536.0);
  endtask

  initial begin
    check(17'd52429, 16'd2560,  234057, "f=0.80 s=10   -> 3.5714");
    check(17'd32768, 16'd512,    87381, "f=0.50 s=2    -> 1.3333");
    check(17'd58982, 16'd25600, 601248, "f=0.90 s=100  -> 9.1743");
    check(17'd0,     16'd2048,   65536, "f=0    s=8    -> 1.0 (no enhancement used)");
    check(17'd65536, 16'd2048,  524288, "f=1    s=8    -> 8.0 (whole program enhanced)");
    check(17'd16384, 16'd384,    71494, "f=0.25 s=1.5  -> 1.0909");
    check(17'd62259, 16'd4096,  599186, "f=0.95 s=16   -> 9.1429");
    check(17'd32768, 16'd0,          0, "s=0 invalid  -> 0");
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
