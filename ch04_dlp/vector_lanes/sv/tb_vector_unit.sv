`timescale 1ns/1ps
// DAXPY (Y = a*X + Y) on a 4-lane and a 1-lane vector unit.  Results must be identical and each
// vector instruction must take exactly ceil(vl/L) cycles.
module tb_vector_unit;
  localparam int MVL = 16, VREGS = 8;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic ld_we = 0;  logic [2:0] ld_reg = 0, rd_reg = 0;  logic [3:0] ld_idx = 0, rd_idx = 0;  logic [31:0] ld_data = 0;
  logic start = 0;  logic [2:0] op = 0, vd = 0, vs1 = 0, vs2 = 0;  logic signed [31:0] scalar = 0;  logic [4:0] vl = 0;
  logic [31:0] rd4, rd1;  logic busy4, busy1;

  vector_unit #(.L(4)) u4 (.clk, .rst_n, .ld_we, .ld_reg, .ld_idx, .ld_data, .rd_reg, .rd_idx, .rd_data(rd4), .start, .op, .vd, .vs1, .vs2, .scalar, .vl, .busy(busy4));
  vector_unit #(.L(1)) u1 (.clk, .rst_n, .ld_we, .ld_reg, .ld_idx, .ld_data, .rd_reg, .rd_idx, .rd_data(rd1), .start, .op, .vd, .vs1, .vs2, .scalar, .vl, .busy(busy1));

  int cnt4, cnt1, errors = 0;
  always @(posedge clk) begin
    if (start) begin cnt4 <= 0; cnt1 <= 0; end
    else begin if (busy4) cnt4 <= cnt4 + 1; if (busy1) cnt1 <= cnt1 + 1; end
  end

  task automatic vload(input [2:0] r, input int i, input int v);
    @(negedge clk); ld_we = 1; ld_reg = r; ld_idx = i[3:0]; ld_data = v;
    @(negedge clk); ld_we = 0;
  endtask
  task automatic vexec(input [2:0] o, d, s1, s2, input int sc, input int n);
    @(negedge clk); start = 1; op = o; vd = d; vs1 = s1; vs2 = s2; scalar = sc; vl = n[4:0];
    @(negedge clk); start = 0;
    while (busy4 || busy1) @(negedge clk);
    @(negedge clk);
  endtask
  task automatic vread(input [2:0] r, input int i, output int v4, output int v1);
    rd_reg = r; rd_idx = i[3:0]; #1; v4 = rd4; v1 = rd1;
  endtask

  initial begin
    int a_scalar, X, Y, expected, cyc4_total, cyc1_total, g4, g1;
    int vls [4];
    vls[0] = 16; vls[1] = 13; vls[2] = 4; vls[3] = 1;
    a_scalar = 5;
    repeat (2) @(negedge clk); rst_n = 1;

    foreach (vls[t]) begin
      int n;  n = vls[t];
      for (int i = 0; i < MVL; i++) begin vload(1, i, i*3 - 7); vload(2, i, 100 - 2*i); end     // V1 = X, V2 = Y
      vexec(3'd3, 3, 1, 0, a_scalar, n);                                     // V3 = a * X
      if (cnt4 != (n + 3) / 4 || cnt1 != n) begin errors++; $display("FAIL cycles for VMULS vl=%0d: L4=%0d L1=%0d", n, cnt4, cnt1); end
      cyc4_total = cnt4; cyc1_total = cnt1;
      vexec(3'd0, 2, 3, 2, 0, n);                                            // V2 = V3 + V2   (DAXPY done)
      if (cnt4 != (n + 3) / 4 || cnt1 != n) begin errors++; $display("FAIL cycles for VADD vl=%0d: L4=%0d L1=%0d", n, cnt4, cnt1); end
      cyc4_total += cnt4; cyc1_total += cnt1;
      for (int i = 0; i < MVL; i++) begin
        X = i*3 - 7;  Y = 100 - 2*i;
        expected = (i < n) ? a_scalar * X + Y : Y;                           // masked elements untouched
        vread(2, i, g4, g1);
        if (g4 !== expected || g1 !== expected) begin
          errors++; $display("FAIL DAXPY vl=%0d element %0d: L4=%0d L1=%0d expected %0d", n, i, g4, g1, expected);
        end
      end
      $display("DAXPY vl=%2d: 4 lanes = %2d cycles, 1 lane = %2d cycles", n, cyc4_total, cyc1_total);
    end

    // other opcodes, spot-checked
    for (int i = 0; i < MVL; i++) begin vload(4, i, i + 1); vload(5, i, 10 * (i + 1)); end
    vexec(3'd1, 6, 5, 4, 0, 16);   // V6 = V5 - V4 = 9*(i+1)
    vexec(3'd2, 7, 4, 5, 0, 16);   // V7 = V4 * V5 = 10*(i+1)^2
    vexec(3'd4, 4, 4, 0, -100, 16);  // V4 = V4 + (-100)
    for (int i = 0; i < MVL; i++) begin
      vread(6, i, g4, g1);  if (g4 !== 9*(i+1) || g1 !== 9*(i+1)) begin errors++; $display("FAIL VSUB %0d", i); end
      vread(7, i, g4, g1);  if (g4 !== 10*(i+1)*(i+1) || g1 !== 10*(i+1)*(i+1)) begin errors++; $display("FAIL VMUL %0d", i); end
      vread(4, i, g4, g1);  if (g4 !== (i + 1 - 100) || g1 !== (i + 1 - 100)) begin errors++; $display("FAIL VADDS %0d", i); end
    end
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
