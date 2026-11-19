// One warp request at a time: coalesce by 64-byte line or replay by bank.
module simt_memory_engine (
 input logic clk,reset,start,shared_mode,
 input logic [1023:0] lane_addresses, input logic [31:0] lane_mask,
 output logic busy,done,req_valid,
 input logic req_ready,
 output logic [31:0] req_lane_mask,req_line_address,
 output logic [5:0] accepted_requests
);
 logic [1023:0] addresses;
 logic [31:0] pending,selected;
 logic shared_latched;
 logic [25:0] line_id;
 logic found;
 logic [31:0] banks;
 always_comb begin
   selected=0; line_id=0; found=0; banks=0;
   if(shared_latched) begin
     for(integer lane=0;lane<32;lane=lane+1) if(pending[lane]) begin
       if(!banks[addresses[lane*32+2+:5]]) begin
         banks[addresses[lane*32+2+:5]]=1; selected[lane]=1;
       end
     end
   end else begin
     for(integer lane=0;lane<32;lane=lane+1) if(pending[lane] && !found) begin
       line_id=addresses[lane*32+6+:26]; found=1;
     end
     for(integer lane=0;lane<32;lane=lane+1)
       if(pending[lane] && addresses[lane*32+6+:26]==line_id) selected[lane]=1;
   end
 end
 assign req_valid=busy; assign req_lane_mask=selected;
 assign req_line_address=shared_latched ? 32'b0 : {line_id,6'b0};
 always_ff @(posedge clk) begin
   if(reset) begin busy<=0; done<=0; pending<=0; addresses<=0; shared_latched<=0; accepted_requests<=0; end
   else begin
     done<=0;
     if(!busy && start) begin
       addresses<=lane_addresses; pending<=lane_mask; shared_latched<=shared_mode; accepted_requests<=0;
       if(lane_mask==0) begin busy<=0; done<=1; end else busy<=1;
     end else if(busy && req_ready) begin
       accepted_requests<=accepted_requests+1;
       pending<=pending & ~selected;
       if((pending & ~selected)==0) begin busy<=0; done<=1; end
     end
   end
 end
endmodule
