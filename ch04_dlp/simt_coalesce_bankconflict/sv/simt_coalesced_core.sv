// Integrates the existing 8-lane SIMT core and data-bearing coalesced memory.
module simt_coalesced_core #(
 parameter int NW=2, WS=8, QUEUE_DEPTH=4
)(
 input logic clk,rst_n,run,allow_request,
 output logic [7:0] imem_addr, input logic [31:0] imem_rdata,
 input logic host_we,host_shared,input logic [7:0] host_addr,input logic [31:0] host_wdata,
 output logic [31:0] host_rdata,
 output logic all_done,output logic [31:0] stat_cycles,stat_issued,stat_lane_ops,stat_idle,transactions
);
 logic [WS*16-1:0] core_addr; logic [WS*32-1:0] core_wdata; logic [WS-1:0] core_we;
 logic req_valid,req_ready,req_write,req_shared; logic [7:0] req_warp,resp_warp; logic [WS-1:0] req_mask; logic [2:0] req_rd,resp_rd;
 logic [1023:0] addresses,wdata,rdata; logic [31:0] mask;
 logic sys_busy,sys_done,sys_valid; logic [31:0] sys_req_mask,sys_line; logic [5:0] sys_count;
 // Requests queue independently of the single coalescer. The engine drains in FIFO order.
 logic [WS*16-1:0] q_addr[0:QUEUE_DEPTH-1];
 logic [WS*32-1:0] q_data[0:QUEUE_DEPTH-1];
 logic [WS-1:0] q_mask[0:QUEUE_DEPTH-1];
 logic [7:0] q_warp[0:QUEUE_DEPTH-1]; logic [2:0] q_rd[0:QUEUE_DEPTH-1];
 logic q_shared[0:QUEUE_DEPTH-1],q_write[0:QUEUE_DEPTH-1];
 integer head,tail,count;
 logic enqueue,dequeue;
 assign req_ready=run && count<QUEUE_DEPTH;
 assign enqueue=req_valid && req_ready;
 assign dequeue=(count!=0) && !sys_busy;
 simt_core #(.NW(NW),.WS(WS),.ASYNC_MEM(1)) core(.clk,.rst_n(rst_n && run),.imem_addr,.imem_rdata,
   .dmem_addr(core_addr),.dmem_wdata(core_wdata),.dmem_we(core_we),.dmem_rdata('0),
   .all_done,.stat_cycles,.stat_issued,.stat_lane_ops,.stat_idle,
   .mem_req_valid(req_valid),.mem_req_ready(req_ready),.mem_req_write(req_write),.mem_req_shared(req_shared),.mem_req_warp(req_warp),.mem_req_rd(req_rd),.mem_req_mask(req_mask),
   .mem_resp_valid(sys_done),.mem_resp_warp(resp_warp),.mem_resp_rd(resp_rd),.mem_resp_rdata(rdata[WS*32-1:0]));
 always_comb begin
  addresses=0; wdata=0; mask=0;
  for(integer i=0;i<WS;i=i+1) begin
   addresses[32*i+:32]={14'b0,q_addr[head][16*i+:16],2'b0};
   wdata[32*i+:32]=q_data[head][32*i+:32]; mask[i]=q_mask[head][i];
  end
 end
 simt_memory_system memory(.clk,.reset(!rst_n),.start(dequeue),.shared_mode(q_shared[head]),.write_op(q_write[head]),.allow_request,
   .lane_addresses(addresses),.lane_wdata(wdata),.lane_mask(mask),.host_we,.host_shared,.host_addr,.host_wdata,.host_rdata,
   .busy(sys_busy),.done(sys_done),.req_valid(sys_valid),.req_lane_mask(sys_req_mask),.req_line_address(sys_line),
   .accepted_requests(sys_count),.lane_rdata(rdata));
 always_ff @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin resp_warp<=0; resp_rd<=0; transactions<=0; head<=0; tail<=0; count<=0; end
  else begin
   if(enqueue) begin
    q_addr[tail]<=core_addr; q_data[tail]<=core_wdata; q_mask[tail]<=req_mask;
    q_warp[tail]<=req_warp; q_rd[tail]<=req_rd; q_shared[tail]<=req_shared; q_write[tail]<=req_write;
    tail<=(tail==QUEUE_DEPTH-1)?0:tail+1;
   end
   if(dequeue) begin
    resp_warp<=q_warp[head]; resp_rd<=q_rd[head]; head<=(head==QUEUE_DEPTH-1)?0:head+1;
   end
   case ({enqueue,dequeue})
    2'b10:count<=count+1;
    2'b01:count<=count-1;
    default:;
   endcase
   if(sys_valid && allow_request) transactions<=transactions+1;
  end
 end
endmodule
