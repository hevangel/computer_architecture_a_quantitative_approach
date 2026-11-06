`timescale 1ns/1ps
module tb_restoring_divider;
  logic clk = 0, rst_n = 0, start = 0;
  always #5 clk = ~clk;
  logic [15:0] n = 0, d = 0, q, r;  logic busy, done;
  restoring_divider dut (.clk, .rst_n, .start, .dividend(n), .divisor(d), .busy, .done, .quotient(q), .remainder(r));

  int errors = 0, tests = 0;
  logic [31:0] seed = 32'd4242;

  task automatic div(input [15:0] x, y);
    logic [15:0] eq, er;
    int cycles;
    if (y == 0) begin eq = 16'hFFFF; er = x; end else begin eq = x / y; er = x % y; end
    @(negedge clk); n = x; d = y; start = 1;
    @(negedge clk); start = 0;
    cycles = 0;
    while (!done && cycles < 30) begin @(negedge clk); cycles++; end
    tests++;
    if (!done || q !== eq || r !== er || cycles != 16) begin
      errors++; $display("FAIL %0d / %0d = %0d r %0d, expected %0d r %0d (%0d extra cycles)", x, y, q, r, eq, er, cycles);
    end
  endtask

  initial begin
    repeat (2) @(negedge clk); rst_n = 1;
    div(0, 1);  div(1, 1);  div(100, 7);  div(16'hFFFF, 1);  div(16'hFFFF, 16'hFFFF);  div(5, 9);
    div(16'h8000, 3);  div(1234, 0);  div(0, 0);  div(16'hFFFF, 2);
    for (int i = 0; i < 2000; i++) begin
      seed = seed * 32'd1664525 + 32'd1013904223;
      div(seed[31:16], (i % 4 == 0) ? {8'b0, seed[7:0]} : seed[15:0]);   // mix of small and large divisors
    end
    $display("%0d divisions checked", tests);
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
