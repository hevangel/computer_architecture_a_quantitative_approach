`timescale 1ns/1ps
module tb_vector_bank_gather_strip;
  logic clk=0,reset=1,mem_we=0,vec_we=0,start=0,indexed=0,store=0;
  logic [8:0] mem_addr=0,vec_index=0,base=0,stride=0;
  logic [31:0] mem_wdata=0,mem_rdata,vec_wdata=0,vec_result;
  logic [5:0] vec_slot=0; logic [6:0] length=0;
  logic busy,done,error; logic [15:0] service_cycles,ideal_cycles,bank_stalls;
  logic [2:0] strips; logic [4:0] strip_length;
  always #5 clk=~clk;
  vector_bank_gather_strip dut(.*);
  task automatic run_vector(input integer n,input bit ind,input bit wr,input integer st);
    begin @(negedge clk); length=7'(n); indexed=ind; store=wr; base=0; stride=9'(st); start=1;
      @(negedge clk); start=0;
    end
  endtask
  task automatic finish_vector(input integer svc,input integer ideal,input integer stalls,input integer num);
    begin
      while (!done) @(negedge clk);
      if(error || busy || service_cycles!=svc || ideal_cycles!=ideal || bank_stalls!=stalls || strips!=num)
        $fatal(1,"stats: service=%0d ideal=%0d stalls=%0d strips=%0d",service_cycles,ideal_cycles,bank_stalls,strips);
    end
  endtask
  initial begin
    repeat(2) @(negedge clk); reset=0;
    for(integer i=0;i<128;i=i+1) begin mem_we=1; mem_addr=9'(i); mem_wdata=32'(i); @(negedge clk); end
    mem_we=0;
    run_vector(45,0,0,1);
    if(strip_length!=16) $fatal(1,"first strip");
    while(strips==1) @(negedge clk); if(strip_length!=16) $fatal(1,"second strip");
    while(strips==2) @(negedge clk); if(strip_length!=13) $fatal(1,"third strip");
    finish_vector(6,6,0,3);
    for(integer i=0;i<45;i=i+1) begin vec_slot=6'(i); #1; if(vec_result!==32'(i)) $fatal(1,"unit result"); end
    run_vector(16,0,0,8); finish_vector(16,2,14,1);
    for(integer i=0;i<16;i=i+1) begin vec_slot=6'(i); #1; if(vec_result!==32'(8*i)) $fatal(1,"stride result"); end
    for(integer i=0;i<45;i=i+1) begin @(negedge clk); vec_we=1; vec_slot=6'(i); vec_index=9'((5*i)%113); vec_wdata=32'(1000+i); end
    @(negedge clk); vec_we=0;
    run_vector(45,1,1,0); finish_vector(7,6,1,3);
    for(integer i=0;i<45;i=i+1) begin mem_addr=9'((5*i)%113); #1; if(mem_rdata!==32'(1000+i)) $fatal(1,"scatter result"); end
    run_vector(45,1,0,0); finish_vector(7,6,1,3);
    for(integer i=0;i<45;i=i+1) begin vec_slot=6'(i); #1; if(vec_result!==32'(1000+i)) $fatal(1,"gather result"); end
    // Duplicate scatter addresses serialize in lane order; last lane wins.
    for(integer i=0;i<2;i=i+1) begin @(negedge clk); vec_we=1; vec_slot=6'(i); vec_index=7; vec_wdata=32'(111+111*i); end
    @(negedge clk); vec_we=0;
    run_vector(2,1,1,0); finish_vector(2,1,1,1);
    mem_addr=7; #1; if(mem_rdata!==222) $fatal(1,"duplicate scatter order");
    run_vector(64,0,0,1); finish_vector(8,8,0,4);
    run_vector(0,0,0,1); if(!done || error || busy) $fatal(1,"empty vector");
    run_vector(65,0,0,1); if(!done || !error || busy) $fatal(1,"oversize vector");
    $display("TEST PASSED"); $finish;
  end
  initial begin #30000; $fatal(1,"timeout"); end
endmodule
