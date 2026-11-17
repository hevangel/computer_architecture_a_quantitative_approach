// Serialized MSI directory: eight nodes, four blocks, one cache line per node.
// MODE 0 full vector, 1 two pointers + broadcast overflow, 2 coarse pairs.
module directory_limited_evict #(parameter int MODE=0) (
 input logic clk,reset,req_valid,input logic [2:0] req_node,input logic req_write,
 input logic [1:0] req_block,input logic [31:0] req_data,
 output logic resp_valid,output logic [31:0] resp_data,stat_inv,stat_puts,stat_putm,stat_fetch,
 input logic [2:0] dbg_node,input logic [1:0] dbg_block,
 output logic [1:0] dbg_cache_state,dbg_directory_state,dbg_cached_block,
 output logic [31:0] dbg_cache_data,dbg_memory,output logic [7:0] dbg_targets
);
 localparam [1:0] I=0,S=1,M=2,U=0;
 logic [1:0] cs[0:7],cb[0:7],ds[0:3]; logic [31:0] cd[0:7],memory[0:3];
 logic [2:0] owner[0:3],ptr0[0:3],ptr1[0:3]; logic [1:0] pcount[0:3];
 logic overflow[0:3]; logic [7:0] full[0:3]; logic [3:0] coarse[0:3];
 initial if(MODE<0 || MODE>2) $fatal(1,"unsupported directory mode");
 function automatic [7:0] targets(input integer b);
  logic [7:0] m;
  begin
   m=0;
   if(MODE==0) m=full[b];
   else if(MODE==1) begin
    if(overflow[b]) m='1;
    else begin if(pcount[b]>0) m[ptr0[b]]=1; if(pcount[b]>1) m[ptr1[b]]=1; end
   end else for(integer k=0;k<8;k=k+1) if(coarse[b][k/2]) m[k]=1;
   targets=m;
  end
 endfunction
 assign dbg_cache_state=cs[dbg_node]; assign dbg_cached_block=cb[dbg_node]; assign dbg_cache_data=cd[dbg_node];
 assign dbg_directory_state=ds[dbg_block]; assign dbg_memory=memory[dbg_block];
 always_comb begin
  dbg_targets=0;
  if(MODE==0) dbg_targets=full[dbg_block];
  else if(MODE==1) begin
   if(overflow[dbg_block]) dbg_targets='1;
   else begin if(pcount[dbg_block]>0) dbg_targets[ptr0[dbg_block]]=1; if(pcount[dbg_block]>1) dbg_targets[ptr1[dbg_block]]=1; end
  end else for(integer k=0;k<8;k=k+1) if(coarse[dbg_block][k/2]) dbg_targets[k]=1;
 end
 always_ff @(posedge clk) begin : process_request
  integer n,b,v,oldowner,count; logic [7:0] mask;
  if(reset) begin
   resp_valid<=0; resp_data<=0; stat_inv<=0; stat_puts<=0; stat_putm<=0; stat_fetch<=0;
   for(integer i=0;i<8;i=i+1) begin cs[i]<=I; cb[i]<=0; cd[i]<=0; end
   for(integer i=0;i<4;i=i+1) begin
    ds[i]<=U; memory[i]<=32'hA0+32'(i); owner[i]<=0; ptr0[i]<=0; ptr1[i]<=0;
    pcount[i]<=0; overflow[i]<=0; full[i]<=0; coarse[i]<=0;
   end
  end else begin
   resp_valid<=0;
   if(req_valid) begin
    n=int'(req_node); b=int'(req_block); resp_valid<=1;
    if(cs[n]!=I && cb[n]==req_block && (!req_write || cs[n]==M)) begin
      if(req_write) begin cd[n]<=req_data; resp_data<=req_data; end else resp_data<=cd[n];
    end else begin
     // PutS / PutM when a different block displaces this node's sole line.
     if(cs[n]!=I && cb[n]!=req_block) begin
      v=int'(cb[n]);
      if(cs[n]==M) begin
       memory[v]<=cd[n]; ds[v]<=U; stat_putm<=stat_putm+1;
       full[v]<=0; pcount[v]<=0; overflow[v]<=0; coarse[v]<=0;
      end else begin
       stat_puts<=stat_puts+1;
       if(MODE==0) begin
        mask=full[v] & ~(8'b1<<n); full[v]<=mask; if(mask==0) ds[v]<=U;
       end else if(MODE==1 && !overflow[v]) begin
        if(pcount[v]==1 && ptr0[v]==req_node) begin pcount[v]<=0; ds[v]<=U; end
        else if(pcount[v]==2 && ptr0[v]==req_node) begin ptr0[v]<=ptr1[v]; pcount[v]<=1; end
        else if(pcount[v]==2 && ptr1[v]==req_node) pcount[v]<=1;
       end
       // Overflow and coarse entries stay conservative after PutS.
      end
     end
     if(!req_write) begin
      if(ds[b]==M) begin
       oldowner=int'(owner[b]); memory[b]<=cd[oldowner]; cd[n]<=cd[oldowner]; resp_data<=cd[oldowner];
       cs[oldowner]<=S; stat_fetch<=stat_fetch+1; ds[b]<=S;
       if(MODE==0) full[b]<=(8'b1<<oldowner)|(8'b1<<n);
       else if(MODE==1) begin ptr0[b]<=3'(oldowner); ptr1[b]<=req_node; pcount[b]<=2; overflow[b]<=0; end
       else coarse[b]<=(4'b1<<(oldowner/2))|(4'b1<<(n/2));
      end else begin
       cd[n]<=memory[b]; resp_data<=memory[b]; ds[b]<=S;
       if(MODE==0) full[b]<=full[b]|(8'b1<<n);
       else if(MODE==1 && !overflow[b]) begin
        if(pcount[b]==0) begin ptr0[b]<=req_node; pcount[b]<=1; end
        else if(ptr0[b]!=req_node && (pcount[b]==1 || ptr1[b]!=req_node)) begin
         if(pcount[b]==1) begin ptr1[b]<=req_node; pcount[b]<=2; end else overflow[b]<=1;
        end
       end else if(MODE==2) coarse[b]<=coarse[b]|(4'b1<<(n/2));
      end
      cs[n]<=S; cb[n]<=req_block;
     end else begin
      if(ds[b]==M) begin
       oldowner=int'(owner[b]); memory[b]<=cd[oldowner]; cs[oldowner]<=I; stat_fetch<=stat_fetch+1;
      end else if(ds[b]==S) begin
       mask=targets(b)&~(8'b1<<n); count=0;
       for(integer i=0;i<8;i=i+1) if(mask[i]) begin
        count=count+1; if(cs[i]!=I && cb[i]==req_block) cs[i]<=I;
       end
       stat_inv<=stat_inv+32'(count);
      end
      cs[n]<=M; cb[n]<=req_block; cd[n]<=req_data; resp_data<=req_data; ds[b]<=M; owner[b]<=req_node;
      full[b]<=0; pcount[b]<=0; overflow[b]<=0; coarse[b]<=0;
     end
    end
   end
  end
 end
endmodule
