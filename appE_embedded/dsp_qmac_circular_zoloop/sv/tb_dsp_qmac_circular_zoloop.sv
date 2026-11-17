`timescale 1ns/1ps
module tb_dsp_qmac_circular_zoloop;
  logic clk=0,reset=1,mac_clear=0,mac_enable=0,pointer_load=0,pointer_step=0,repeat_load=0,repeat_step=0;
  logic signed [15:0] sample=0,coefficient=0,rounded_q15;
  logic signed [39:0] accumulator;
  logic [3:0] pointer_start=0,pointer,fft_index=0,bit_reversed;
  logic [4:0] pointer_modulus=16,repeat_count=0;
  logic repeat_active,repeat_last;
  logic [63:0] expected_reverse=64'hf7b3d591e6a2c480;
  always #5 clk=~clk;
  dsp_qmac_circular_zoloop dut(.*);
  task automatic clear_mac;
    begin @(negedge clk); mac_clear=1; mac_enable=0; @(negedge clk); mac_clear=0; end
  endtask
  task automatic one_product(input integer s,input integer c,input integer expected);
    begin
      clear_mac(); sample=16'(s); coefficient=16'(c); mac_enable=1;
      @(negedge clk); mac_enable=0;
      if (rounded_q15!==16'(expected)) $fatal(1,"rounding mismatch got %d",rounded_q15);
    end
  endtask
  initial begin
    repeat (2) @(negedge clk); reset=0;
    for (integer i=0;i<16;i=i+1) begin
      fft_index=4'(i); #1;
      if (bit_reversed!==expected_reverse[i*4+:4]) $fatal(1,"bit reverse mismatch");
    end
    @(negedge clk); pointer_start=13; pointer_load=1; repeat_count=16; repeat_load=1; mac_clear=1;
    @(negedge clk); pointer_load=0; repeat_load=0; mac_clear=0; pointer_step=1; repeat_step=1; mac_enable=1; coefficient=2048;
    for (integer i=0;i<16;i=i+1) begin
      if (!repeat_active || repeat_last!==(i==15)) $fatal(1,"repeat state mismatch");
      sample=16'(integer'(pointer)*2048);
      @(negedge clk);
    end
    mac_enable=0; pointer_step=0; repeat_step=0;
    if (repeat_active || pointer!=13 || accumulator!==40'sd503316480 || rounded_q15!==16'sd15360) $fatal(1,"FIR mismatch");
    one_product(1,16384,0); one_product(3,16384,2); one_product(-1,16384,0); one_product(-3,16384,-2);
    clear_mac(); sample=32767; coefficient=32767; mac_enable=1;
    repeat (520) @(negedge clk);
    mac_enable=0;
    if (accumulator!==40'sh7fffffffff || rounded_q15!==16'sh7fff) $fatal(1,"positive saturation mismatch");
    clear_mac(); sample=-32768; coefficient=32767; mac_enable=1;
    repeat (520) @(negedge clk);
    mac_enable=0;
    if (accumulator!==40'sh8000000000 || rounded_q15!==16'sh8000) $fatal(1,"negative saturation mismatch");
    $display("TEST PASSED"); $finish;
  end
  initial begin #30000; $fatal(1,"timeout"); end
endmodule
