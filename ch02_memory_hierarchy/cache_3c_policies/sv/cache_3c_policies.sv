// Finite 8-bit block-address cache policy evaluator and fully-associative 3C shadow.
module cache_3c_policies #(parameter int SETS=4, ASSOC=1, POLICY=0) (
 input logic clk,reset,valid, input logic [7:0] block_addr,
 output logic hit, output logic [1:0] miss_kind,
 output logic [31:0] accesses,compulsory,capacity,conflict
);
 initial begin
  if(SETS<1 || ASSOC<1 || ASSOC>4 || POLICY<0 || POLICY>3) $fatal(1,"unsupported cache configuration");
 end
 localparam int LINES=SETS*ASSOC;
 logic cache_valid[0:LINES-1]; logic [7:0] cache_block[0:LINES-1]; logic [31:0] cache_age[0:LINES-1];
 logic shadow_valid[0:LINES-1]; logic [7:0] shadow_block[0:LINES-1]; logic [31:0] shadow_age[0:LINES-1];
 logic seen[0:255]; logic [2:0] tree[0:SETS-1]; logic [7:0] lfsr; logic [31:0] timestamp;
 integer set_idx,cache_way,cache_victim,shadow_way,shadow_victim; logic cache_found,shadow_found,cache_empty,shadow_empty;
 always_comb begin
  set_idx=int'(block_addr)%SETS; cache_found=0; cache_way=0; cache_victim=0; cache_empty=0;
  shadow_found=0; shadow_way=0; shadow_victim=0; shadow_empty=0;
  for(integer i=0;i<ASSOC;i=i+1) begin
   if(cache_valid[set_idx*ASSOC+i] && cache_block[set_idx*ASSOC+i]==block_addr) begin cache_found=1; cache_way=i; end
   if(!cache_valid[set_idx*ASSOC+i] && !cache_empty) begin cache_empty=1; cache_victim=i; end
  end
  if(!cache_empty) begin
   if(POLICY==2) cache_victim=int'(lfsr)%ASSOC;
   else if(POLICY==3) begin
    if(ASSOC==1) cache_victim=0;
    else if(ASSOC==2) cache_victim=tree[set_idx][1]?1:0;
    else if(!tree[set_idx][0]) cache_victim=tree[set_idx][1]?1:0;
    else if(ASSOC==3) cache_victim=2;
    else cache_victim=tree[set_idx][2]?3:2;
   end else begin
    for(integer i=1;i<ASSOC;i=i+1)
     if(cache_age[set_idx*ASSOC+i]<cache_age[set_idx*ASSOC+cache_victim]) cache_victim=i;
   end
  end
  for(integer i=0;i<LINES;i=i+1) begin
   if(shadow_valid[i] && shadow_block[i]==block_addr) begin shadow_found=1; shadow_way=i; end
   if(!shadow_valid[i] && !shadow_empty) begin shadow_empty=1; shadow_victim=i; end
  end
  if(!shadow_empty) for(integer i=1;i<LINES;i=i+1)
   if(shadow_age[i]<shadow_age[shadow_victim]) shadow_victim=i;
 end
 always_ff @(posedge clk) begin : update
  integer w, sw, idx;
  if(reset) begin
   hit<=0; miss_kind<=0; accesses<=0; compulsory<=0; capacity<=0; conflict<=0; timestamp<=0; lfsr<=1;
   for(integer i=0;i<256;i=i+1) seen[i]<=0;
   for(integer i=0;i<SETS;i=i+1) tree[i]<=0;
   for(integer i=0;i<LINES;i=i+1) begin
    cache_valid[i]<=0; cache_block[i]<=0; cache_age[i]<=0;
    shadow_valid[i]<=0; shadow_block[i]<=0; shadow_age[i]<=0;
   end
  end else if(valid) begin
   accesses<=accesses+1; timestamp<=timestamp+1; hit<=cache_found; miss_kind<=0;
   seen[block_addr]<=1;
   w=cache_found?cache_way:cache_victim; idx=set_idx*ASSOC+w;
   if(!cache_found) begin
    cache_valid[idx]<=1; cache_block[idx]<=block_addr; cache_age[idx]<=timestamp;
    if(!seen[block_addr]) begin compulsory<=compulsory+1; miss_kind<=1; end
    else if(!shadow_found) begin capacity<=capacity+1; miss_kind<=2; end
    else begin conflict<=conflict+1; miss_kind<=3; end
    if(POLICY==2) lfsr<={lfsr[6:0],lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
   end else if(POLICY==0) cache_age[idx]<=timestamp;
   if(w<2) begin tree[set_idx][0]<=1; tree[set_idx][1]<=1'(1-w); end
   else begin tree[set_idx][0]<=0; tree[set_idx][2]<=1'(3-w); end
   sw=shadow_found?shadow_way:shadow_victim;
   shadow_valid[sw]<=1; shadow_block[sw]<=block_addr; shadow_age[sw]<=timestamp;
  end
 end
endmodule
