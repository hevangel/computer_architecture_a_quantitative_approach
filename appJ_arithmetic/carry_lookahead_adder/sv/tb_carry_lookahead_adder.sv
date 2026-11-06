`timescale 1ns/1ps
module tb_carry_lookahead_adder;
  logic [15:0] a, b, sum;  logic cin, cout;
  carry_lookahead_adder dut (.a, .b, .cin, .sum, .cout);
  int errors = 0, tests = 0;
  logic [31:0] seed = 32'd12345;

  task automatic check(input [15:0] ai, bi, input ci);
    logic [16:0] expected;
    a = ai; b = bi; cin = ci; #1;
    expected = {1'b0, ai} + {1'b0, bi} + ci;
    tests++;
    if ({cout, sum} !== expected) begin
      errors++; $display("FAIL %h + %h + %b = %h%h, expected %h", ai, bi, ci, cout, sum, expected);
    end
  endtask

  initial begin
    check(0, 0, 0);  check(16'hFFFF, 0, 1);  check(16'hFFFF, 16'hFFFF, 1);  check(16'h8000, 16'h8000, 0);
    check(16'h0001, 16'hFFFF, 0);  check(16'h5555, 16'hAAAA, 1);  check(16'h000F, 16'h0001, 0);
    for (int i = 0; i < 20000; i++) begin
      seed = seed * 32'd1664525 + 32'd1013904223;   // LCG, same stream in the VHDL testbench
      check(seed[31:16], seed[15:0], seed[7]);
    end
    $display("%0d additions checked", tests);
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
