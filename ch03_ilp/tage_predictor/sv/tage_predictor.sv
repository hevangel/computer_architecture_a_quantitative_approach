// Small non-speculative tagged-history predictor with a bimodal base and gshare baseline.
module tage_predictor (
 input logic clk,reset,input logic [15:0] pc,input logic update_valid,actual_taken,
 output logic prediction,gshare_prediction,output logic [1:0] provider,
 output logic [17:0] history
);
 logic [1:0] base[0:15],gshare[0:15];
 logic valid[0:47]; logic [7:0] tags[0:47]; logic [2:0] counters[0:47]; logic [1:0] useful[0:47];
 logic [3:0] bi,gi,idx[0:2]; logic [7:0] tag[0:2]; logic alternate;
 function automatic [1:0] sat2(input [1:0] x,input logic up);
  if(up) sat2=(x==3)?x:x+1'b1; else sat2=(x==0)?x:x-1'b1;
 endfunction
 function automatic [2:0] sat3(input [2:0] x,input logic up);
  if(up) sat3=(x==7)?x:x+1'b1; else sat3=(x==0)?x:x-1'b1;
 endfunction
 always_comb begin : query
  logic [17:0] h;
  bi=pc[5:2]; gi=pc[5:2]^history[3:0];
  prediction=base[bi][1]; alternate=prediction; provider=0;
  for(integer b=0;b<3;b=b+1) begin
   case(b) 0:h=history & 18'h00003; 1:h=history & 18'h0003f; default:h=history; endcase
   idx[b]=pc[5:2]^h[3:0]; tag[b]=8'(pc>>2)^8'(h)^8'(h>>8)^8'(h>>16);
   if(valid[b*16+idx[b]] && tags[b*16+idx[b]]==tag[b]) begin
    alternate=prediction; prediction=counters[b*16+idx[b]][2]; provider=2'(b+1);
   end
  end
  gshare_prediction=gshare[gi][1];
 end
 always_ff @(posedge clk) begin : train
  integer slot,allocation;
  if(reset) begin
   history<=0;
   for(integer i=0;i<16;i=i+1) begin base[i]<=1; gshare[i]<=1; end
   for(integer i=0;i<48;i=i+1) begin valid[i]<=0; tags[i]<=0; counters[i]<=3; useful[i]<=0; end
  end else if(update_valid) begin
   base[bi]<=sat2(base[bi],actual_taken); gshare[gi]<=sat2(gshare[gi],actual_taken);
   if(provider!=0) begin
    slot=(int'(provider)-1)*16+int'(idx[int'(provider)-1]);
    counters[slot]<=sat3(counters[slot],actual_taken);
    if(prediction!=alternate) useful[slot]<=sat2(useful[slot],prediction==actual_taken);
   end
   if(prediction!=actual_taken) begin
    allocation=-1;
    for(integer b=0;b<3;b=b+1)
      if(b>=int'(provider) && allocation<0 && (!valid[b*16+idx[b]] || useful[b*16+idx[b]]==0)) allocation=b;
    if(allocation>=0) begin
      slot=allocation*16+int'(idx[allocation]); valid[slot]<=1; tags[slot]<=tag[allocation];
      counters[slot]<=actual_taken?3'd4:3'd3; useful[slot]<=0;
    end else begin
      for(integer b=0;b<3;b=b+1)
        if(b>=int'(provider) && valid[b*16+idx[b]] && useful[b*16+idx[b]]!=0)
          useful[b*16+idx[b]]<=useful[b*16+idx[b]]-1'b1;
    end
   end
   history<={history[16:0],actual_taken};
  end
 end
endmodule
