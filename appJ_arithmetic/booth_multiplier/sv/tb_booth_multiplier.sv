`timescale 1ns/1ps
module tb_booth_multiplier;
  logic clk = 0, rst_n = 0, start = 0;
  always #5 clk = ~clk;
  logic signed [15:0] a = 0, b = 0;
  logic busy, done;  logic signed [31:0] product;
  booth_multiplier dut (.clk, .rst_n, .start, .a, .b, .busy, .done, .product);

  int errors = 0, tests = 0;
  logic [31:0] seed = 32'd777;

  task automatic mul(input logic signed [15:0] x, y);
    logic signed [31:0] expected;
    int cycles;
    expected = x * y;                    // golden model: the simulator's own multiplier
    @(negedge clk); a = x; b = y; start = 1;
    @(negedge clk); start = 0;
    cycles = 0;
    while (!done && cycles < 20) begin @(negedge clk); cycles++; end
    tests++;
    if (!done || product !== expected || cycles != 8) begin
      errors++; $display("FAIL %0d * %0d = %0d, expected %0d (done=%b, %0d extra cycles)", x, y, product, expected, done, cycles);
    end
  endtask

  initial begin
    repeat (2) @(negedge clk); rst_n = 1;
    mul(0, 0);  mul(1, 1);  mul(-1, -1);  mul(16'sh7FFF, 16'sh7FFF);  mul(16'sh8000, 16'sh8000);
    mul(16'sh8000, 16'sh7FFF);  mul(16'sh8000, -1);  mul(1234, -5678);  mul(-3, 7);  mul(16'sh5555, 16'shAAAA);
    for (int i = 0; i < 2000; i++) begin
      seed = seed * 32'd1664525 + 32'd1013904223;
      mul(seed[31:16], seed[15:0]);
    end
    $display("%0d multiplications checked", tests);
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
