`timescale 1ns/1ps
module tb_spectre_transient_demo;
 logic clk=0,reset=1,host_we=0,flush=0,start=0,mitigation_en=0;
 logic [7:0] host_addr=0,host_data=0,index_value=0,probe_index=0;
 logic [8:0] bound=0; wire [7:0] probe_cycles,arch_value,short_cycles,short_arch;
 wire busy,done,transient_load,transient_touch,short_busy,short_done,short_load,short_touch;
 always #5 clk=~clk;
 spectre_transient_demo dut(.*);
 spectre_transient_demo #(.BRANCH_LATENCY(1)) short_path(.clk,.reset,.host_we,.host_addr,.host_data,.flush,.start,.index_value,.bound,.mitigation_en,.probe_index,
  .probe_cycles(short_cycles),.arch_value(short_arch),.busy(short_busy),.done(short_done),.transient_load(short_load),.transient_touch(short_touch));
 task automatic init(input [7:0] addr,input [7:0] data);
  begin @(negedge clk); host_we=1; host_addr=addr; host_data=data; @(negedge clk); host_we=0; end
 endtask
 task automatic run_case(input [7:0] idx,input logic protection);
  integer waited;
  begin
   @(negedge clk); flush=1; start=1; index_value=idx; bound=9'd16; mitigation_en=protection;
   @(negedge clk); flush=0; start=0; waited=0;
   while(!done && waited<30) begin @(negedge clk); waited=waited+1; end
   if(!done || busy) $fatal(1,"completion timeout");
  end
 endtask
 task automatic probe_all(input integer expected_hit);
  begin
   for(integer i=0;i<256;i=i+1) begin
    probe_index=8'(i); #1;
    if(probe_cycles!==(i==expected_hit?8'd1:8'd10)) $fatal(1,"probe mismatch %0d",i);
   end
  end
 endtask
 initial begin
  repeat(2) @(negedge clk); reset=0; init(3,8'h33); init(200,8'h5a);
  // Legal operation commits under either protection setting.
  run_case(3,0); if(arch_value!=8'h33 || !transient_load || !transient_touch) $fatal(1,"unprotected legal operation"); probe_all(8'h33);
  run_case(3,1); if(arch_value!=8'h33 || transient_load || transient_touch) $fatal(1,"protected legal operation"); probe_all(8'h33);
  // Wrong path changes only the cache; the architectural value stays 0x33.
  run_case(200,0); if(arch_value!=8'h33 || !transient_load || !transient_touch) $fatal(1,"unprotected wrong path"); probe_all(8'h5a);
  probe_index=8'h5a; #1; if(short_cycles!=10 || short_arch!=8'h33 || short_touch) $fatal(1,"short speculation window");
  run_case(200,1); if(arch_value!=8'h33 || transient_load || transient_touch) $fatal(1,"protected wrong path"); probe_all(-1);
  $display("TEST PASSED"); $finish;
 end
 initial begin #10000; $fatal(1,"timeout"); end
endmodule
