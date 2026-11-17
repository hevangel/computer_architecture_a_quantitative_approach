// Serialized two-stage page walker. PTEs use bit 0 valid, bit 1 root superpage,
// and bits 31:12 as a page base. Root tables have 2048 entries, leaves 512.
module nested_pt_walker (
 input logic clk,reset,invalidate,req_valid,pwc_enable,
 input logic [31:0] req_vaddr,req_guest_root,req_host_root,
 input logic [15:0] req_asid,
 output logic req_ready,resp_valid,resp_fault,resp_super,
 output logic [31:0] resp_paddr,
 output logic mem_valid, input logic mem_ready,
 output logic [31:0] mem_addr, input logic mem_rvalid, input logic [31:0] mem_rdata,
 output logic [31:0] stat_mem_reads,stat_pwc_hits,stat_tlb_hits
);
 localparam [3:0] IDLE=0,HOST_START=1,LOOKUP=2,SEND=3,WAIT_DATA=4,HOST_ROOT=5,HOST_LEAF=6,GUEST_ENTRY=7;
 localparam [1:0] GROOT=0,GLEAF=1,DATA=2;
 logic [3:0] state,return_state; logic [1:0] ctx;
 logic [31:0] va_q,groot_q,hroot_q,gpa_q,pte_addr,pte_word; logic [15:0] asid_q;
 logic guest_super,pwc_q;
 logic pv[0:15]; logic [31:0] paddr[0:15],pdata[0:15]; logic [3:0] pnext;
 logic tv[0:3],tsuper[0:3]; logic [15:0] tasid[0:3]; logic [31:0] tvpn[0:3],tppn[0:3],tgr[0:3],thr[0:3]; logic [1:0] tage[0:3];
 logic tlb_hit,pwc_hit; integer thit,phit;
 assign req_ready=(state==IDLE && !invalidate);
 assign mem_valid=(state==SEND); assign mem_addr=pte_addr;
 always_comb begin
  tlb_hit=0; thit=0; pwc_hit=0; phit=0;
  for(integer i=0;i<4;i=i+1) begin
   if(tv[i] && tasid[i]==req_asid && tgr[i]==req_guest_root && thr[i]==req_host_root &&
      ((tsuper[i] && tvpn[i]==(req_vaddr>>21)) || (!tsuper[i] && tvpn[i]==(req_vaddr>>12)))) begin tlb_hit=1; thit=i; end
  end
  for(integer i=0;i<16;i=i+1) if(pv[i] && paddr[i]==pte_addr) begin pwc_hit=1; phit=i; end
 end
 task automatic finish_host(input logic [31:0] phys,input logic host_super);
  integer victim; logic [1:0] oldest; logic big;
  begin
   if(ctx==DATA) begin
    big=guest_super && host_super; resp_valid<=1; resp_fault<=0; resp_paddr<=phys; resp_super<=big;
    victim=0; oldest=tage[0];
    for(integer i=0;i<4;i=i+1) if(!tv[i]) victim=i;
    if(tv[0] && tv[1] && tv[2] && tv[3]) begin
     victim=0; oldest=tage[0]; for(integer i=1;i<4;i=i+1) if(tage[i]>oldest) begin oldest=tage[i]; victim=i; end
    end
    for(integer i=0;i<4;i=i+1) if(i!=victim && tv[i] && tage[i]!=3) tage[i]<=tage[i]+1;
    tv[victim]<=1; tsuper[victim]<=big; tasid[victim]<=asid_q; tgr[victim]<=groot_q; thr[victim]<=hroot_q;
    tvpn[victim]<=big ? va_q>>21 : va_q>>12; tppn[victim]<=big ? phys>>21 : phys>>12; tage[victim]<=0; state<=IDLE;
   end else begin pte_addr<=phys; return_state<=GUEST_ENTRY; state<=LOOKUP; end
  end
 endtask
 always_ff @(posedge clk) begin
  if(reset) begin
   state<=IDLE; resp_valid<=0; resp_fault<=0; resp_super<=0; resp_paddr<=0;
   stat_mem_reads<=0; stat_pwc_hits<=0; stat_tlb_hits<=0; pnext<=0;
   for(integer i=0;i<16;i=i+1) begin pv[i]<=0; paddr[i]<=0; pdata[i]<=0; end
   for(integer i=0;i<4;i=i+1) begin tv[i]<=0; tage[i]<=0; tsuper[i]<=0; tasid[i]<=0; tvpn[i]<=0; tppn[i]<=0; tgr[i]<=0; thr[i]<=0; end
  end else begin
   resp_valid<=0; resp_fault<=0;
   if(state==IDLE && invalidate) begin for(integer i=0;i<16;i=i+1) pv[i]<=0; for(integer i=0;i<4;i=i+1) tv[i]<=0; pnext<=0; end
   else case(state)
    IDLE: if(req_valid) begin
     if(req_guest_root[12:0]!=0 || req_host_root[12:0]!=0) begin resp_valid<=1; resp_fault<=1; resp_paddr<=0; resp_super<=0; end
     else if(tlb_hit) begin
      resp_valid<=1; resp_super<=tsuper[thit]; stat_tlb_hits<=stat_tlb_hits+1;
      resp_paddr<=tsuper[thit] ? {tppn[thit][10:0],req_vaddr[20:0]} : {tppn[thit][19:0],req_vaddr[11:0]};
      for(integer i=0;i<4;i=i+1) if(tv[i] && tage[i]<tage[thit]) tage[i]<=tage[i]+1;
      tage[thit]<=0;
     end else begin
      va_q<=req_vaddr; asid_q<=req_asid; groot_q<=req_guest_root; hroot_q<=req_host_root; pwc_q<=pwc_enable;
      gpa_q<=req_guest_root+{19'b0,req_vaddr[31:21],2'b0}; guest_super<=0; ctx<=GROOT; state<=HOST_START;
     end
    end
    HOST_START: begin pte_addr<=hroot_q+{19'b0,gpa_q[31:21],2'b0}; return_state<=HOST_ROOT; state<=LOOKUP; end
    LOOKUP: if(pwc_q && pwc_hit) begin pte_word<=pdata[phit]; stat_pwc_hits<=stat_pwc_hits+1; state<=return_state; end else state<=SEND;
    SEND: if(mem_ready) begin stat_mem_reads<=stat_mem_reads+1; state<=WAIT_DATA; end
    WAIT_DATA: if(mem_rvalid) begin
     pte_word<=mem_rdata; if(pwc_q) begin pv[pnext]<=1; paddr[pnext]<=pte_addr; pdata[pnext]<=mem_rdata; pnext<=pnext+1; end
     state<=return_state;
    end
    HOST_ROOT: if(!pte_word[0] || (pte_word[1] && |pte_word[20:12])) begin resp_valid<=1; resp_fault<=1; resp_paddr<=0; resp_super<=0; state<=IDLE; end
     else if(pte_word[1]) finish_host({pte_word[31:21],gpa_q[20:0]},1);
     else begin pte_addr<={pte_word[31:12],12'b0}+{21'b0,gpa_q[20:12],2'b0}; return_state<=HOST_LEAF; state<=LOOKUP; end
    HOST_LEAF: if(!pte_word[0] || pte_word[1]) begin resp_valid<=1; resp_fault<=1; resp_paddr<=0; resp_super<=0; state<=IDLE; end
     else finish_host({pte_word[31:12],gpa_q[11:0]},0);
    GUEST_ENTRY: if(!pte_word[0] || (ctx==GLEAF && pte_word[1]) || (ctx==GROOT && pte_word[1] && |pte_word[20:12])) begin
      resp_valid<=1; resp_fault<=1; resp_paddr<=0; resp_super<=0; state<=IDLE;
     end else if(ctx==GROOT && !pte_word[1]) begin
      gpa_q<={pte_word[31:12],12'b0}+{21'b0,va_q[20:12],2'b0}; ctx<=GLEAF; state<=HOST_START;
     end else begin
      if(ctx==GROOT) begin gpa_q<={pte_word[31:21],va_q[20:0]}; guest_super<=1; end
      else begin gpa_q<={pte_word[31:12],va_q[11:0]}; guest_super<=0; end
      ctx<=DATA; state<=HOST_START;
     end
    default: state<=IDLE;
   endcase
  end
 end
endmodule
