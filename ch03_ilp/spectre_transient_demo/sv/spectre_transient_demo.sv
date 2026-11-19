// Abstract bounds-check speculation and cache footprint; no real CPU or timer.
module spectre_transient_demo #(parameter int BRANCH_LATENCY=5) (
 input logic clk,reset,
 input logic host_we,input logic [7:0] host_addr,host_data,
 input logic flush,input logic start,input logic [7:0] index_value,input logic [8:0] bound,
 input logic mitigation_en,input logic [7:0] probe_index,
 output logic [7:0] probe_cycles,arch_value,
 output logic busy,done,output logic transient_load,transient_touch
);
 logic [7:0] secret[0:255]; logic [255:0] cached;
 logic [7:0] held_index,loaded; logic allowed,mitigate,resolved;
 integer timer; logic [1:0] phase;
 assign probe_cycles=cached[probe_index]?8'd1:8'd10;
 initial if(BRANCH_LATENCY<1) $fatal(1,"branch latency must be positive");
 always_ff @(posedge clk) begin
  if(reset) begin
   cached<='0; arch_value<=0; busy<=0; done<=0; transient_load<=0; transient_touch<=0;
   held_index<=0; loaded<=0; allowed<=0; mitigate<=0; resolved<=0; timer<=0; phase<=0;
  end else begin
   done<=0;
   if(!busy) begin
    if(host_we) secret[host_addr]<=host_data;
    if(flush) cached<='0;
    if(start) begin
     held_index<=index_value; allowed<=({1'b0,index_value}<bound); mitigate<=mitigation_en;
     timer<=BRANCH_LATENCY; resolved<=0; phase<=0; busy<=1;
     transient_load<=0; transient_touch<=0;
    end
   end else begin
    if(timer>0) begin timer<=timer-1; if(timer==1) resolved<=1; end
    if(phase==0 && (!mitigate || resolved) && (!resolved || allowed)) begin
     loaded<=secret[held_index]; phase<=1; if(!resolved) transient_load<=1;
    end else if(phase==1 && (!resolved || allowed)) begin
     cached[loaded]<=1; phase<=2; if(!resolved) transient_touch<=1;
    end
    if(resolved && (!allowed || phase==2)) begin
     if(allowed) arch_value<=loaded;
     busy<=0; done<=1;
    end
   end
  end
 end
endmodule
