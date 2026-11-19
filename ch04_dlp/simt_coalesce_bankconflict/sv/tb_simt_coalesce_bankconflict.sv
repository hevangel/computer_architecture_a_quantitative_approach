`timescale 1ns/1ps
module tb_simt_coalesce_bankconflict;
 logic clk=0,reset=1; logic [1023:0] lane_addresses=0; logic [31:0] lane_mask=0;
 logic [5:0] global_transactions,shared_replay_cycles;
 logic [2:0] warp=0,wb_warp=0; logic [4:0] src_a=0,src_b=0,dst=0,wb_reg=0;
 logic use_a=0,use_b=0,write_dst=0,issue=0,can_issue,wb_valid=0,barrier_arrive=0,barrier_release;
 logic [7:0] barrier_target=0,barrier_waiting;
 logic engine_start=0,shared_mode=0,engine_busy,engine_done,req_valid,req_ready=0;
 logic [31:0] req_lane_mask,req_line_address; logic [5:0] accepted_requests;
 logic sys_start=0,sys_shared=0,sys_write=0,sys_allow=0,host_we=0,host_shared=0;
 logic [7:0] host_addr=0; logic [31:0] host_wdata=0,host_rdata,sys_req_mask,sys_line;
 logic [1023:0] sys_wdata=0,sys_rdata; logic sys_busy,sys_done,sys_valid; logic [5:0] sys_count;
 logic core_run=0,core_allow=0,core_host_we=0,core_done; logic [1:0] core_program=0;
 logic [7:0] core_imem_addr,core_host_addr=0; logic [31:0] core_imem_data,core_host_wdata=0,core_host_rdata;
 logic [31:0] core_cycles,core_issued,core_ops,core_idle,core_transactions;
 always #5 clk=~clk;
 simt_coalesce_bankconflict dut(.*);
 simt_memory_engine engine(.clk,.reset,.start(engine_start),.shared_mode,.lane_addresses,.lane_mask,
   .busy(engine_busy),.done(engine_done),.req_valid,.req_ready,.req_lane_mask,.req_line_address,.accepted_requests);
 simt_memory_system memsys(.clk,.reset,.start(sys_start),.shared_mode(sys_shared),.write_op(sys_write),.allow_request(sys_allow),
   .lane_addresses,.lane_wdata(sys_wdata),.lane_mask,.host_we,.host_shared,.host_addr,.host_wdata,.host_rdata,
   .busy(sys_busy),.done(sys_done),.req_valid(sys_valid),.req_lane_mask(sys_req_mask),.req_line_address(sys_line),
   .accepted_requests(sys_count),.lane_rdata(sys_rdata));
 function automatic [31:0] ins(input [4:0] op,input [3:0] rd,ra,rb,input integer imm);
  ins={op,rd,ra,rb,imm[14:0]};
 endfunction
 always_comb begin
  if(!core_program) begin
   case(core_imem_addr)
    0:core_imem_data=ins(7,1,0,0,0);
    1:core_imem_data=ins(8,2,1,0,0);
    2:core_imem_data=ins(6,3,2,0,7);
    3:core_imem_data=ins(9,0,1,3,64);
    default:core_imem_data=ins(14,0,0,0,0);
   endcase
  end else if(core_program==1) begin
   case(core_imem_addr)
    0:core_imem_data=ins(7,1,0,0,0);
    1:core_imem_data=ins(5,2,1,0,1);
    2:core_imem_data=ins(12,0,0,0,0);
    3:core_imem_data=ins(10,0,2,0,6);
    4:core_imem_data=ins(6,3,1,0,10);
    5:core_imem_data=ins(11,0,0,0,7);
    6:core_imem_data=ins(6,3,1,0,20);
    7:core_imem_data=ins(13,0,0,0,0);
    8:core_imem_data=ins(9,0,1,3,64);
    default:core_imem_data=ins(14,0,0,0,0);
   endcase
  end else if(core_program==2) begin
   case(core_imem_addr)
    0:core_imem_data=ins(7,1,0,0,0);   // tid
    1:core_imem_data=ins(6,5,0,0,8);
    2:core_imem_data=ins(3,2,1,5,0);   // tid * 8: two-way bank conflicts
    3:core_imem_data=ins(6,3,1,0,20);
    4:core_imem_data=ins(5,7,1,0,8);
    5:core_imem_data=ins(10,0,7,0,18); // warp 0 skips warp 1's delay
    18:core_imem_data=ins(16,0,2,3,0);
    19:core_imem_data=ins(17,0,0,0,0);
    20:core_imem_data=ins(6,6,1,0,8);
    21:core_imem_data=ins(5,6,6,0,15);
    22:core_imem_data=ins(3,6,6,5,0);
    23:core_imem_data=ins(15,4,6,0,0);
    24:core_imem_data=ins(9,0,1,4,64);
    25:core_imem_data=ins(17,0,0,0,0);
    26:core_imem_data=ins(14,0,0,0,0);
    6,7,8,9,10,11,12,13,14,15,16,17:core_imem_data=ins(0,0,0,0,0);
    default:core_imem_data=ins(14,0,0,0,0);
   endcase
  end else begin
   case(core_imem_addr)
    0:core_imem_data=ins(7,1,0,0,0);
    1:core_imem_data=ins(8,2,1,0,0);
    2:core_imem_data=ins(8,3,1,0,0);
    3:core_imem_data=ins(8,5,1,0,0);
    4:core_imem_data=ins(1,4,2,3,0);
    5:core_imem_data=ins(1,4,4,5,0);
    6:core_imem_data=ins(9,0,1,4,64);
    default:core_imem_data=ins(14,0,0,0,0);
   endcase
  end
 end
 simt_coalesced_core integrated(.clk,.rst_n(!reset),.run(core_run),.allow_request(core_allow),.imem_addr(core_imem_addr),.imem_rdata(core_imem_data),
   .host_we(core_host_we),.host_shared(1'b0),.host_addr(core_host_addr),.host_wdata(core_host_wdata),.host_rdata(core_host_rdata),.all_done(core_done),
   .stat_cycles(core_cycles),.stat_issued(core_issued),.stat_lane_ops(core_ops),.stat_idle(core_idle),.transactions(core_transactions));
 task automatic arrive(input integer w);
  begin @(negedge clk); warp=3'(w); barrier_arrive=1; @(negedge clk); barrier_arrive=0; end
 endtask
 initial begin
  repeat(2) @(negedge clk); reset=0;
  for(integer count=8;count<=32;count=count*2) begin
    lane_mask=32'hffffffff >> (32-count);
    for(integer i=0;i<32;i=i+1) lane_addresses[i*32+:32]=32'(i*4);
    #1; if(global_transactions!=((count+15)/16) || shared_replay_cycles!=1) $fatal(1,"contiguous count=%0d",count);
    for(integer i=0;i<32;i=i+1) lane_addresses[i*32+:32]=32'(i*64);
    #1; if(global_transactions!=count) $fatal(1,"stride count=%0d",count);
  end
  lane_mask='1;
  for(integer i=0;i<32;i=i+1) lane_addresses[i*32+:32]=32'((i%8)*4+(i/8)*128);
  #1; if(shared_replay_cycles!=4) $fatal(1,"bank conflicts");
  lane_mask=0; #1; if(global_transactions!=0 || shared_replay_cycles!=0) $fatal(1,"empty mask");
  @(negedge clk); warp=0; dst=5; write_dst=1; issue=1;
  @(negedge clk); issue=0; write_dst=0; src_a=5; use_a=1; #1;
  if(can_issue) $fatal(1,"RAW hazard not blocked");
  warp=1; #1; if(!can_issue) $fatal(1,"other warp blocked");
  warp=0; wb_warp=0; wb_reg=5; wb_valid=1;
  @(negedge clk); wb_valid=0; #1; if(!can_issue) $fatal(1,"writeback failed");
  use_a=0; barrier_target=8'h0f;
  for(integer phase=0;phase<2;phase=phase+1) begin
   arrive(0); if(barrier_waiting!=8'h01 || barrier_release) $fatal(1,"barrier first");
   #1; if(can_issue) $fatal(1,"barrier warp issued");
   arrive(1); arrive(2); if(barrier_waiting!=8'h07) $fatal(1,"barrier incomplete");
   arrive(3); if(!barrier_release || barrier_waiting!=0) $fatal(1,"barrier release");
  end
  // Two coalesced lines; first request must remain stable during stalls.
  lane_mask='1; for(integer i=0;i<32;i=i+1) lane_addresses[i*32+:32]=32'(i*4);
  @(negedge clk); engine_start=1; shared_mode=0; @(negedge clk); engine_start=0;
  if(!req_valid || req_line_address!=0 || req_lane_mask!=32'h0000ffff) $fatal(1,"first line");
  repeat(2) begin @(negedge clk); if(!req_valid || req_lane_mask!=32'h0000ffff || req_line_address!=0) $fatal(1,"stalled line"); end
  req_ready=1; @(negedge clk);
  if(!req_valid || req_line_address!=64 || req_lane_mask!=32'hffff0000) $fatal(1,"second line");
  @(negedge clk); req_ready=0;
  if(!engine_done || engine_busy || accepted_requests!=2) $fatal(1,"coalescer completion");
  // One address per line must emit 32 requests with exactly one lane each.
  for(integer i=0;i<32;i=i+1) lane_addresses[i*32+:32]=32'(i*64);
  @(negedge clk); engine_start=1; @(negedge clk); engine_start=0; req_ready=1;
  for(integer i=0;i<32;i=i+1) begin
    if(!req_valid || req_line_address!=32'(i*64) || req_lane_mask!=(32'b1<<i)) $fatal(1,"uncoalesced request");
    @(negedge clk);
  end
  req_ready=0; if(!engine_done || accepted_requests!=32) $fatal(1,"uncoalesced completion");
  // Four replay rounds for 32 lanes mapping to eight banks.
  for(integer i=0;i<32;i=i+1) lane_addresses[i*32+:32]=32'((i%8)*4+(i/8)*128);
  @(negedge clk); shared_mode=1; engine_start=1; @(negedge clk); engine_start=0; req_ready=1;
  for(integer round=0;round<4;round=round+1) begin
    if(!req_valid || req_lane_mask!==(32'hff<<(8*round))) $fatal(1,"shared replay");
    @(negedge clk);
  end
  req_ready=0; if(!engine_done || accepted_requests!=4) $fatal(1,"shared completion");
  lane_mask=0; @(negedge clk); engine_start=1; @(negedge clk); engine_start=0;
  if(!engine_done || engine_busy || accepted_requests!=0) $fatal(1,"empty request");
  // Preload global words and read through actual coalesced requests.
  for(integer i=0;i<32;i=i+1) begin @(negedge clk); host_we=1; host_shared=0; host_addr=8'(i); host_wdata=32'(500+i); end
  @(negedge clk); host_we=0; lane_mask='1;
  for(integer i=0;i<32;i=i+1) lane_addresses[i*32+:32]=32'(i*4);
  @(negedge clk); sys_start=1; sys_shared=0; sys_write=0; sys_allow=0;
  @(negedge clk); sys_start=0;
  repeat(2) begin @(negedge clk); if(!sys_valid || sys_line!=0 || sys_req_mask!=32'h0000ffff) $fatal(1,"system stall"); end
  sys_allow=1; while(!sys_done) @(negedge clk); sys_allow=0;
  if(sys_count!=2) $fatal(1,"system global count");
  for(integer i=0;i<32;i=i+1) if(sys_rdata[i*32+:32]!==32'(500+i)) $fatal(1,"global read lane %0d",i);
  // Four-bank replay rounds write and then read 32 distinct shared words.
  for(integer i=0;i<32;i=i+1) begin lane_addresses[i*32+:32]=32'((i%8)*4+(i/8)*128); sys_wdata[i*32+:32]=32'(1000+i); end
  @(negedge clk); sys_start=1; sys_shared=1; sys_write=1; sys_allow=1;
  @(negedge clk); sys_start=0; while(!sys_done) @(negedge clk); sys_allow=0;
  if(sys_count!=4) $fatal(1,"shared store count");
  @(negedge clk); sys_start=1; sys_write=0; sys_allow=1;
  @(negedge clk); sys_start=0; while(!sys_done) @(negedge clk); sys_allow=0;
  if(sys_count!=4) $fatal(1,"shared read count");
  for(integer i=0;i<32;i=i+1) if(sys_rdata[i*32+:32]!==32'(1000+i)) $fatal(1,"shared read lane %0d",i);
  // Masked global stores leave inactive words untouched.
  lane_mask=32'h55555555;
  for(integer i=0;i<32;i=i+1) begin lane_addresses[i*32+:32]=32'(i*4); sys_wdata[i*32+:32]=32'(2000+i); end
  @(negedge clk); sys_start=1; sys_shared=0; sys_write=1; sys_allow=1;
  @(negedge clk); sys_start=0; while(!sys_done) @(negedge clk); sys_allow=0;
  if(sys_count!=2) $fatal(1,"masked store count");
  host_shared=0;
  for(integer i=0;i<32;i=i+1) begin host_addr=8'(i); #1;
    if(host_rdata!==32'((i%2==0)?2000+i:500+i)) $fatal(1,"masked store data");
  end
  // Run two actual warps through coalesced memory under periodic backpressure.
  for(integer i=0;i<16;i=i+1) begin @(negedge clk); core_host_we=1; core_host_addr=8'(i); core_host_wdata=32'(i); end
  @(negedge clk); core_host_we=0; core_run=1;
  begin : wait_for_core
   integer cycles_waited; cycles_waited=0;
   while(!core_done && cycles_waited<200) begin
    core_allow=(cycles_waited%3 != 0); @(negedge clk); cycles_waited=cycles_waited+1;
   end
   if(!core_done || core_transactions!=4 || core_issued!=10 || core_ops!=80) $fatal(1,"integrated core statistics");
  end
  for(integer i=0;i<16;i=i+1) begin core_host_addr=8'(64+i); #1;
    if(core_host_rdata!==32'(i+7)) $fatal(1,"integrated result lane %0d got %h",i,core_host_rdata);
  end
  // Restart only the core; preserve memory and exercise divergent paths.
  @(negedge clk); core_run=0; core_program=1; @(negedge clk); core_run=1; core_allow=1;
  begin : wait_for_divergence
   integer waited; waited=0;
   while(!core_done && waited<200) begin @(negedge clk); waited=waited+1; end
   if(!core_done || core_transactions!=6 || core_issued!=22) $fatal(1,"divergent core statistics");
  end
  for(integer i=0;i<16;i=i+1) begin core_host_addr=8'(64+i); #1;
   if(core_host_rdata!==32'(i+((i%2==0)?20:10))) $fatal(1,"divergent result lane %0d",i);
  end
  // Both warps communicate through bank-conflicted shared memory and two barriers.
  @(negedge clk); core_run=0; core_program=2; @(negedge clk); core_run=1; core_allow=1;
  begin : wait_for_shared
   integer waited; waited=0;
   while(!core_done && waited<300) begin
    core_allow=(waited%4 != 0); @(negedge clk); waited=waited+1;
   end
   if(!core_done || core_transactions!=16 || core_issued!=42) $fatal(1,"shared/barrier statistics %0d %0d",core_transactions,core_issued);
  end
  for(integer i=0;i<16;i=i+1) begin core_host_addr=8'(64+i); #1;
   if(core_host_rdata!==32'(((i+8)%16)+20)) $fatal(1,"cross-warp shared result lane %0d got %h",i,core_host_rdata);
  end
  // Five loads fill the engine plus queue; the sixth must wait without being lost.
  @(negedge clk); core_run=0; core_program=3; core_allow=0;
  @(negedge clk); core_run=1;
  repeat(25) @(negedge clk);
  if(core_issued!=7 || core_transactions!=16 || core_done) $fatal(1,"queued loads did not overlap: issued=%0d",core_issued);
  core_allow=1;
  begin : wait_for_queued
   integer waited; waited=0;
   while(!core_done && waited<200) begin @(negedge clk); waited=waited+1; end
   if(!core_done || core_transactions!=24 || core_issued!=16 || core_ops!=128) $fatal(1,"queued program statistics");
  end
  for(integer i=0;i<16;i=i+1) begin core_host_addr=8'(64+i); #1;
   if(core_host_rdata!==32'(3*i)) $fatal(1,"queued result lane %0d",i);
  end
  $display("TEST PASSED"); $finish;
 end
 initial begin #10000; $fatal(1,"timeout"); end
endmodule
