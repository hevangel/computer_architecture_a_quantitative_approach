// Warp memory transaction estimator, register scoreboards and block barrier.
module simt_coalesce_bankconflict (
  input logic clk,reset,
  input logic [1023:0] lane_addresses, input logic [31:0] lane_mask,
  output logic [5:0] global_transactions,shared_replay_cycles,
  input logic [2:0] warp, input logic [4:0] src_a,src_b,dst,
  input logic use_a,use_b,write_dst,issue,
  output logic can_issue,
  input logic wb_valid, input logic [2:0] wb_warp, input logic [4:0] wb_reg,
  input logic barrier_arrive, input logic [7:0] barrier_target,
  output logic [7:0] barrier_waiting, output logic barrier_release
);
  logic [31:0] scoreboard[0:7];
  logic [7:0] arriving;
  always_comb begin : memory_counts
    integer unique_count,counts[0:31],max_count;
    logic seen;
    unique_count=0; max_count=0; seen=0;
    for(integer i=0;i<32;i=i+1) counts[i]=0;
    for(integer i=0;i<32;i=i+1) if(lane_mask[i]) begin
      seen=0;
      for(integer j=0;j<32;j=j+1)
        if(j<i && lane_mask[j] && lane_addresses[i*32+6+:26]==lane_addresses[j*32+6+:26]) seen=1;
      if(!seen) unique_count=unique_count+1;
      counts[lane_addresses[i*32+2+:5]]=counts[lane_addresses[i*32+2+:5]]+1;
    end
    for(integer i=0;i<32;i=i+1) if(counts[i]>max_count) max_count=counts[i];
    global_transactions=6'(unique_count); shared_replay_cycles=6'(max_count);
  end
  assign can_issue=!barrier_waiting[warp] && (!use_a || !scoreboard[warp][src_a]) &&
                   (!use_b || !scoreboard[warp][src_b]) && (!write_dst || !scoreboard[warp][dst]);
  assign arriving=8'b1<<warp;
  always_ff @(posedge clk) begin
    if(reset) begin
      for(integer i=0;i<8;i=i+1) scoreboard[i]<=0;
      barrier_waiting<=0; barrier_release<=0;
    end else begin
      barrier_release<=0;
      if(wb_valid) scoreboard[wb_warp][wb_reg]<=0;
      if(issue && can_issue && write_dst) scoreboard[warp][dst]<=1;
      if(barrier_arrive && barrier_target[warp] && barrier_target!=0) begin
        if(((barrier_waiting|arriving)&barrier_target)==barrier_target) begin
          barrier_waiting<=barrier_waiting & ~barrier_target;
          barrier_release<=1;
        end else barrier_waiting<=barrier_waiting|arriving;
      end
    end
  end
endmodule
