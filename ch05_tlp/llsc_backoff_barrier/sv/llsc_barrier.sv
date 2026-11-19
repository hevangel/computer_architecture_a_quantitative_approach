// Serialized four-core memory commands plus a reusable all-core sense barrier.
module llsc_barrier (
 input logic clk,reset,cmd_valid,input logic [1:0] cmd_core,cmd_op,input logic [3:0] cmd_addr,
 input logic [31:0] cmd_wdata,output logic rsp_valid,sc_success,output logic [31:0] rsp_data,invalidations,
 input logic arrive,input logic [1:0] arrive_core,
 output logic [3:0] waiting,local_sense,output logic global_sense,barrier_release
);
 logic [31:0] memory[0:15]; logic [3:0] reservations; logic [3:0] reserved_addr[0:3];
 always_ff @(posedge clk) begin : update
  integer killed; logic [3:0] arrivals;
  if(reset) begin
   rsp_valid<=0; sc_success<=0; rsp_data<=0; invalidations<=0; reservations<=0;
   waiting<=0; local_sense<=0; global_sense<=0; barrier_release<=0;
   for(integer i=0;i<16;i=i+1) memory[i]<=0;
   for(integer i=0;i<4;i=i+1) reserved_addr[i]<=0;
  end else begin
   rsp_valid<=0; sc_success<=0; barrier_release<=0;
   if(cmd_valid) begin
    rsp_valid<=1; rsp_data<=memory[cmd_addr]; killed=0;
    case(cmd_op)
     0: ; // ordinary load
     1: begin reservations[cmd_core]<=1; reserved_addr[cmd_core]<=cmd_addr; end
     2: begin // SC always consumes its own reservation
      reservations[cmd_core]<=0;
      if(reservations[cmd_core] && reserved_addr[cmd_core]==cmd_addr) begin
       sc_success<=1; memory[cmd_addr]<=cmd_wdata;
       for(integer i=0;i<4;i=i+1) if(reservations[i] && reserved_addr[i]==cmd_addr) begin
        reservations[i]<=0; if(i!=int'(cmd_core)) killed=killed+1;
       end
      end
     end
     3: begin // ordinary store broadcasts an invalidation
      memory[cmd_addr]<=cmd_wdata;
      for(integer i=0;i<4;i=i+1) if(reservations[i] && reserved_addr[i]==cmd_addr) begin
       reservations[i]<=0; if(i!=int'(cmd_core)) killed=killed+1;
      end
     end
    endcase
    invalidations<=invalidations+32'(killed);
   end
   if(arrive && !waiting[arrive_core]) begin
    local_sense[arrive_core]<=~local_sense[arrive_core]; arrivals=waiting | (4'b1<<arrive_core);
    if(arrivals==4'b1111) begin waiting<=0; global_sense<=~global_sense; barrier_release<=1; end
    else waiting<=arrivals;
   end
  end
 end
endmodule
