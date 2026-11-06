`timescale 1ns/1ps
module tb_raid5_parity;
  localparam int DISKS = 5, W = 32;
  logic [(DISKS-1)*W-1:0] data_blocks;  logic [W-1:0] parity_out;
  logic [DISKS*W-1:0] stripe;           logic [2:0] failed;
  logic [W-1:0] syndrome, rebuilt, old_data, new_data, old_parity, new_parity;

  raid5_parity #(.DISKS(DISKS), .W(W)) dut (.*);

  int errors = 0;
  logic [31:0] seed = 32'd2024;
  function automatic logic [31:0] rnd(); seed = seed * 32'd1664525 + 32'd1013904223; return seed; endfunction

  initial begin
    for (int t = 0; t < 200; t++) begin
      for (int i = 0; i < DISKS-1; i++) data_blocks[i*W +: W] = rnd();
      #1;
      stripe = {parity_out, data_blocks};                       // parity lives on the last disk
      for (int f = 0; f < DISKS; f++) begin
        failed = f[2:0]; #1;
        if (syndrome !== 0) begin errors++; $display("FAIL: healthy stripe has syndrome %h", syndrome); end
        if (rebuilt !== stripe[f*W +: W]) begin errors++; $display("FAIL: rebuild of disk %0d", f); end
      end
      // small write to data disk 2
      old_data = data_blocks[2*W +: W];  new_data = rnd();  old_parity = parity_out;  #1;
      data_blocks[2*W +: W] = new_data;  #1;
      if (new_parity !== parity_out) begin errors++; $display("FAIL: small-write parity"); end
    end
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
