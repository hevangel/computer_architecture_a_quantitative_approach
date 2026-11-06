`timescale 1ns/1ps
module tb_rr_crossbar;
  localparam int N = 4, W = 32, DW = 2;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic [N-1:0] in_req = 0;  logic [N*DW-1:0] in_dst = 0;  logic [N*W-1:0] in_data = 0;
  logic [N-1:0] in_gnt, out_valid;  logic [N*DW-1:0] out_src;  logic [N*W-1:0] out_data;

  rr_crossbar #(.N(N), .W(W)) dut (.*);

  int errors = 0;
  logic [31:0] seed = 32'd808;

  task automatic drive(input [N-1:0] req, input int d0, d1, d2, d3);
    @(negedge clk);
    in_req = req;
    in_dst = {d3[1:0], d2[1:0], d1[1:0], d0[1:0]};
    for (int i = 0; i < N; i++) in_data[i*W +: W] = 32'hD0000000 + (i << 8) + $urandom_range(255, 0);
    #1;
  endtask

  initial begin
    repeat (2) @(negedge clk); rst_n = 1;

    // 1. hot spot: everyone wants output 2 -> winners must rotate 0,1,2,3,0,1,2,3
    for (int c = 0; c < 8; c++) begin
      drive(4'b1111, 2, 2, 2, 2);
      if (out_valid !== 4'b0100 || int'(out_src[2*DW +: DW]) !== c % 4 || in_gnt !== (4'b0001 << (c % 4))) begin
        errors++; $display("FAIL hotspot cycle %0d: valid=%b src=%0d gnt=%b", c, out_valid, out_src[2*DW +: DW], in_gnt);
      end
      if (out_data[2*W +: W] !== in_data[(c % 4)*W +: W]) begin errors++; $display("FAIL hotspot data"); end
    end

    // 2. input 1 idle, the rest hot-spot output 0 -> rotate 0,2,3,0,2,3 (idle input is skipped)
    for (int c = 0; c < 6; c++) begin
      drive(4'b1101, 0, 0, 0, 0);
      if (int'(out_src[0 +: DW]) !== ((c % 3 == 0) ? 0 : (c % 3 == 1) ? 2 : 3)) begin
        errors++; $display("FAIL skip-idle cycle %0d: src=%0d", c, out_src[0 +: DW]);
      end
    end

    // 3. permutation traffic i -> i+1: no conflicts, all four served every cycle
    for (int c = 0; c < 4; c++) begin
      drive(4'b1111, 1, 2, 3, 0);
      if (in_gnt !== 4'b1111 || out_valid !== 4'b1111) begin errors++; $display("FAIL permutation: gnt=%b valid=%b", in_gnt, out_valid); end
      for (int j = 0; j < N; j++)
        if (int'(out_src[j*DW +: DW]) !== (j + N - 1) % N || out_data[j*W +: W] !== in_data[((j + N - 1) % N)*W +: W]) begin
          errors++; $display("FAIL permutation routing at output %0d", j);
        end
    end

    // 4. random traffic: check arbiter invariants every cycle
    for (int c = 0; c < 3000; c++) begin
      logic [31:0] r;
      int exp_valid, ngnt;
      seed = seed * 32'd1664525 + 32'd1013904223;  r = seed;
      drive(r[3:0], r[5:4], r[7:6], r[9:8], r[11:10]);
      ngnt = 0;
      for (int j = 0; j < N; j++) begin
        exp_valid = 0;
        for (int i = 0; i < N; i++) if (in_req[i] && int'(in_dst[i*DW +: DW]) == j) exp_valid = 1;
        if (out_valid[j] !== exp_valid[0]) begin errors++; $display("FAIL output %0d valid=%b expected %0d", j, out_valid[j], exp_valid); end
        if (out_valid[j]) begin
          int s; s = int'(out_src[j*DW +: DW]);
          if (!in_req[s] || int'(in_dst[s*DW +: DW]) != j || !in_gnt[s]) begin errors++; $display("FAIL bad winner %0d for output %0d", s, j); end
          ngnt++;
        end
      end
      if ($countones(in_gnt) != ngnt) begin errors++; $display("FAIL grant count %b vs %0d outputs", in_gnt, ngnt); end
    end
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
