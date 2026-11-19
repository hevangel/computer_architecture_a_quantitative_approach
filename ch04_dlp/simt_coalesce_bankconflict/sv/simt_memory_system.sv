// Data-bearing scratch memories behind the coalescer/replay engine.
module simt_memory_system (
 input logic clk,reset,start,shared_mode,write_op,allow_request,
 input logic [1023:0] lane_addresses,lane_wdata,
 input logic [31:0] lane_mask,
 input logic host_we,host_shared,input logic [7:0] host_addr,input logic [31:0] host_wdata,
 output logic [31:0] host_rdata,
 output logic busy,done,req_valid,
 output logic [31:0] req_lane_mask,req_line_address,
 output logic [5:0] accepted_requests,
 output logic [1023:0] lane_rdata
);
 logic [31:0] global_mem[0:255],shared_mem[0:255];
 logic [1023:0] addresses_latched,data_latched;
 logic shared_latched,write_latched;
 assign host_rdata=host_shared ? shared_mem[host_addr] : global_mem[host_addr];
 simt_memory_engine engine(.clk,.reset,.start,.shared_mode,.lane_addresses,.lane_mask,
   .busy,.done,.req_valid,.req_ready(allow_request),.req_lane_mask,.req_line_address,.accepted_requests);
 always_ff @(posedge clk) begin
  if(reset) begin addresses_latched<=0; data_latched<=0; shared_latched<=0; write_latched<=0; lane_rdata<=0; end
  else begin
   if(!busy && host_we) begin
    if(host_shared) shared_mem[host_addr]<=host_wdata; else global_mem[host_addr]<=host_wdata;
   end
   if(!busy && start) begin
    addresses_latched<=lane_addresses; data_latched<=lane_wdata; shared_latched<=shared_mode; write_latched<=write_op; lane_rdata<=0;
   end
   if(req_valid && allow_request) begin
    for(integer lane=0;lane<32;lane=lane+1) if(req_lane_mask[lane]) begin
      if(write_latched) begin
       if(shared_latched) shared_mem[addresses_latched[lane*32+2+:8]]<=data_latched[lane*32+:32];
       else global_mem[addresses_latched[lane*32+2+:8]]<=data_latched[lane*32+:32];
      end else begin
       if(shared_latched) lane_rdata[lane*32+:32]<=shared_mem[addresses_latched[lane*32+2+:8]];
       else lane_rdata[lane*32+:32]<=global_mem[addresses_latched[lane*32+2+:8]];
      end
    end
   end
  end
 end
endmodule
