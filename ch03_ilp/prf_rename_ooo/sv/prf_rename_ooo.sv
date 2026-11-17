// Eight architectural and sixteen physical registers; an eight-entry pointer-only ROB.
// One issue/commit per cycle, independent add/branch and multiply units, one result bus.
module prf_rename_ooo #(parameter integer NPHYS=16) (
 input logic clk,reset,init_we,input logic [2:0] init_reg,input logic [31:0] init_data,
 input logic issue_valid,input logic [1:0] issue_op,input logic [2:0] issue_dst,issue_src1,issue_src2,input logic issue_pred_taken,input logic [7:0] issue_branch_id,
 output logic issue_ready,output logic recover_valid,recover_taken,output logic [7:0] recover_branch_id,output logic idle,
 input logic [2:0] dbg_reg,output logic [31:0] dbg_value,output logic [3:0] dbg_front,dbg_arch,
 output logic [15:0] dbg_free,output logic [4:0] free_count,output logic [3:0] rob_count,
 output logic [31:0] stat_issued,stat_committed,stat_squashed,stat_recoveries,stat_ooo
);
 initial if(NPHYS<9 || NPHYS>16) $fatal(1,"NPHYS must be between 9 and 16");
 localparam [1:0] ADD=0,SUB=1,MUL=2,BR=3;
 logic [31:0] prf[0:15]; logic [15:0] preg_ready,free_bits;
 logic [3:0] front[0:7],arch[0:7];
 logic rv[0:7],done[0:7],executing[0:7],pred[0:7];
 logic [1:0] op[0:7]; logic [2:0] adst[0:7]; logic [3:0] pdst[0:7],pold[0:7],ps1[0:7],ps2[0:7];
 logic [7:0] branch_id[0:7]; logic [2:0] head,tail; logic [3:0] count;
 logic ubusy[0:1],udone[0:1]; logic [2:0] utag[0:1],urem[0:1]; logic [31:0] uvalue[0:1];
 logic has_free,cdb_valid,cdb_unit,recover_now; logic [3:0] free_pick; logic [2:0] cdb_tag; logic [31:0] cdb_value;
 integer free_total;
 assign dbg_value=prf[arch[dbg_reg]]; assign dbg_front=front[dbg_reg]; assign dbg_arch=arch[dbg_reg]; assign dbg_free=free_bits; assign free_count=5'(free_total); assign rob_count=count;
 assign idle=(count==0 && !ubusy[0] && !ubusy[1]);
 always_comb begin
  has_free=0; free_pick=0; free_total=0;
  for(integer p=0;p<16;p=p+1) if(free_bits[p]) begin free_total=free_total+1; if(!has_free) begin has_free=1; free_pick=4'(p); end end
  cdb_valid=udone[0] || udone[1]; cdb_unit=!udone[0] && udone[1]; cdb_tag=utag[cdb_unit]; cdb_value=uvalue[cdb_unit];
  recover_now=cdb_valid && op[cdb_tag]==BR && ((cdb_value!=0)!=pred[cdb_tag]);
  issue_ready=(count<8) && ((issue_op==BR)||has_free) && !recover_now && !recover_valid && !reset && !init_we;
 end
 function automatic integer distance(input integer tag,input integer h); distance=(tag+8-h)%8; endfunction
 always_ff @(posedge clk) begin : machine
  integer pick,tagx,keep; logic [3:0] mapx; logic [15:0] new_free; logic [31:0] lhs,rhs;
  if(reset) begin
   head<=0; tail<=0; count<=0; free_bits<=(16'hffff >> (16-NPHYS)) & 16'hff00; preg_ready<=16'h00ff;
   recover_valid<=0; recover_taken<=0; recover_branch_id<=0; stat_issued<=0; stat_committed<=0; stat_squashed<=0; stat_recoveries<=0; stat_ooo<=0;
   for(integer i=0;i<16;i=i+1) prf[i]<=0;
   for(integer i=0;i<8;i=i+1) begin front[i]<=4'(i); arch[i]<=4'(i); rv[i]<=0; done[i]<=0; executing[i]<=0; pred[i]<=0; op[i]<=0; adst[i]<=0; pdst[i]<=0; pold[i]<=0; ps1[i]<=0; ps2[i]<=0; branch_id[i]<=0; end
   for(integer u=0;u<2;u=u+1) begin ubusy[u]<=0; udone[u]<=0; utag[u]<=0; urem[u]<=0; uvalue[u]<=0; end
  end else begin
   recover_valid<=0;
   if(init_we && idle) prf[arch[init_reg]]<=init_data;
   if(cdb_valid) begin
    done[cdb_tag]<=1; if(op[cdb_tag]!=BR) begin prf[pdst[cdb_tag]]<=cdb_value; preg_ready[pdst[cdb_tag]]<=1; end
    if(cdb_tag!=head) stat_ooo<=stat_ooo+1;
    ubusy[cdb_unit]<=0; udone[cdb_unit]<=0;
   end
   for(integer u=0;u<2;u=u+1) begin
    if(!ubusy[u]) begin
     if(!recover_now) begin
      pick=-1;
      for(integer j=0;j<8;j=j+1) if(rv[j] && !executing[j] && !done[j] && ((op[j]==MUL)==(u==1)) && preg_ready[ps1[j]] && (op[j]==BR || preg_ready[ps2[j]]))
       if(pick<0 || distance(j,int'(head))<distance(pick,int'(head))) pick=j;
      if(pick>=0) begin
       lhs=prf[ps1[pick]]; rhs=prf[ps2[pick]]; ubusy[u]<=1; udone[u]<=0; utag[u]<=3'(pick); executing[pick]<=1;
       urem[u]<=(u==0)?3'd2:3'd4;
       case(op[pick]) ADD:uvalue[u]<=lhs+rhs; SUB:uvalue[u]<=lhs-rhs; MUL:uvalue[u]<=lhs*rhs; default:uvalue[u]<=(lhs!=0); endcase
      end
     end
    end else if(!udone[u]) begin if(urem[u]==1) begin urem[u]<=0; udone[u]<=1; end else urem[u]<=urem[u]-1; end
   end
   if(count!=0 && done[head] && !recover_now) begin
    if(op[head]!=BR) begin arch[adst[head]]<=pdst[head]; free_bits[pold[head]]<=1; end
    rv[head]<=0; head<=head+1; stat_committed<=stat_committed+1;
   end
   if(issue_valid && issue_ready) begin
    rv[tail]<=1; done[tail]<=0; executing[tail]<=0; op[tail]<=issue_op; pred[tail]<=issue_pred_taken; branch_id[tail]<=issue_branch_id;
    ps1[tail]<=front[issue_src1]; ps2[tail]<=front[issue_src2]; adst[tail]<=issue_dst;
    if(issue_op!=BR) begin pdst[tail]<=free_pick; pold[tail]<=front[issue_dst]; front[issue_dst]<=free_pick; free_bits[free_pick]<=0; preg_ready[free_pick]<=0; end
    tail<=tail+1; stat_issued<=stat_issued+1;
   end
   count<=count + ((issue_valid && issue_ready)?1:0) - ((count!=0 && done[head] && !recover_now)?1:0);
   if(recover_now) begin
    keep=distance(int'(cdb_tag),int'(head))+1;
    recover_valid<=1; recover_taken<=(cdb_value!=0); recover_branch_id<=branch_id[cdb_tag]; stat_recoveries<=stat_recoveries+1; stat_squashed<=stat_squashed+32'(int'(count)-keep);
    tail<=3'((int'(head)+keep)%8); count<=4'(keep);
    new_free=16'hffff >> (16-NPHYS); for(integer r=0;r<8;r=r+1) new_free[arch[r]]=0;
    for(integer off=0;off<8;off=off+1) if(off<keep) begin
     tagx=(int'(head)+off)%8; if(rv[tagx] && op[tagx]!=BR) new_free[pdst[tagx]]=0;
    end
    free_bits<=new_free;
    for(integer r=0;r<8;r=r+1) begin
     mapx=arch[r]; for(integer off=0;off<8;off=off+1) if(off<keep) begin
      tagx=(int'(head)+off)%8; if(rv[tagx] && op[tagx]!=BR && adst[tagx]==3'(r)) mapx=pdst[tagx];
     end
     front[r]<=mapx;
    end
    for(integer j=0;j<8;j=j+1) if(rv[j] && distance(j,int'(head))>=keep && distance(j,int'(head))<int'(count)) begin rv[j]<=0; done[j]<=0; executing[j]<=0; end
    for(integer u=0;u<2;u=u+1) if(ubusy[u] && distance(int'(utag[u]),int'(head))>=keep) begin ubusy[u]<=0; udone[u]<=0; end
   end
  end
 end
endmodule
