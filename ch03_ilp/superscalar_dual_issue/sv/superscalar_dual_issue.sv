// In-order two-wide RV32I teaching pipeline: ADD/SUB/ADDI/LUI, LW/SW,
// BEQ/BNE and EBREAK. Slot 0 is ALU/branch; slot 1 is ALU/memory.
module superscalar_dual_issue (
 input logic clk,rst_n,
 output logic [31:0] imem_addr,input logic [31:0] imem_lo,imem_hi,
 output logic [31:0] dmem_addr,dmem_wdata,output logic dmem_we,input logic [31:0] dmem_rdata,
 input logic [4:0] dbg_raddr,output logic [31:0] dbg_rdata,
 output logic halted,output logic [31:0] stat_cycles,stat_retired,stat_pairs,stat_load_stalls,stat_flushes
);
 localparam [6:0] OP_REG=7'h33,OP_IMM=7'h13,OP_LUI=7'h37,OP_LOAD=7'h03,OP_STORE=7'h23,OP_BRANCH=7'h63;
 localparam [31:0] EBREAK=32'h00100073;
 logic [31:0] regs[1:31]; logic [31:0] fetch_pc,id_pc,id0,id1; logic id_valid,stop_fetch;
 logic [31:0] ei[0:1],epc[0:1],ea[0:1],eb[0:1]; logic ev[0:1];
 logic [31:0] mi[0:1],mr[0:1],ms[0:1]; logic mv[0:1];
 logic [31:0] wi[0:1],wvdata[0:1]; logic wv[0:1];
 logic [31:0] ex_result[0:1],ex_store[0:1],branch_target; logic redirect;
 logic issue_two,load_hazard,first_mem,second_mem,can_pair; logic [4:0] e_load_rd;
 function automatic logic is_mem(input logic [31:0] ins); is_mem=ins[6:0]==OP_LOAD || ins[6:0]==OP_STORE; endfunction
 function automatic logic is_branch(input logic [31:0] ins); is_branch=ins[6:0]==OP_BRANCH; endfunction
 function automatic logic writes_reg(input logic [31:0] ins); writes_reg=(ins[6:0]==OP_REG || ins[6:0]==OP_IMM || ins[6:0]==OP_LUI || ins[6:0]==OP_LOAD) && ins[11:7]!=0; endfunction
 function automatic logic uses1(input logic [31:0] ins); uses1=ins[6:0]==OP_REG || ins[6:0]==OP_IMM || ins[6:0]==OP_LOAD || ins[6:0]==OP_STORE || ins[6:0]==OP_BRANCH; endfunction
 function automatic logic uses2(input logic [31:0] ins); uses2=ins[6:0]==OP_REG || ins[6:0]==OP_STORE || ins[6:0]==OP_BRANCH; endfunction
 function automatic logic depends(input logic [31:0] ins,input logic [4:0] r); depends=(r!=0) && ((uses1(ins) && ins[19:15]==r) || (uses2(ins) && ins[24:20]==r)); endfunction
 function automatic [31:0] read_id(input logic [4:0] r);
  begin
   if(r==0) read_id=0; else begin
    read_id=regs[r];
    for(integer i=0;i<2;i=i+1) if(wv[i] && writes_reg(wi[i]) && wi[i][11:7]==r) read_id=wvdata[i];
   end
  end
 endfunction
 function automatic [31:0] forward_ex(input logic [4:0] r,input logic [31:0] original);
  begin
   if(r==0) forward_ex=0; else begin
    forward_ex=original;
    for(integer i=0;i<2;i=i+1) if(wv[i] && writes_reg(wi[i]) && wi[i][11:7]==r) forward_ex=wvdata[i];
    for(integer i=0;i<2;i=i+1) if(mv[i] && writes_reg(mi[i]) && mi[i][6:0]!=OP_LOAD && mi[i][11:7]==r) forward_ex=mr[i];
   end
  end
 endfunction
 assign imem_addr=fetch_pc; assign dbg_rdata=dbg_raddr==0 ? 0 : regs[dbg_raddr];
 assign dmem_addr=mr[1]; assign dmem_wdata=ms[1]; assign dmem_we=mv[1] && mi[1][6:0]==OP_STORE && !halted;
 always_comb begin : decisions
  logic [4:0] dst0; logic a1,a2; logic [31:0] aa,bb,imm;
  first_mem=is_mem(id0); second_mem=is_mem(id1); dst0=id0[11:7];
  can_pair=!is_branch(id0) && id0!=EBREAK && !is_branch(id1) && id1!=EBREAK && !(first_mem && second_mem) &&
    !(writes_reg(id0) && (depends(id1,dst0) || (writes_reg(id1) && id1[11:7]==dst0)));
  issue_two=id_valid && can_pair;
  e_load_rd=(ev[1] && ei[1][6:0]==OP_LOAD) ? ei[1][11:7] : 0;
  load_hazard=id_valid && (depends(id0,e_load_rd) || (issue_two && depends(id1,e_load_rd)));
  redirect=0; branch_target=0;
  for(integer i=0;i<2;i=i+1) begin
   aa=forward_ex(ei[i][19:15],ea[i]); bb=forward_ex(ei[i][24:20],eb[i]); ex_store[i]=bb; ex_result[i]=0;
   case(ei[i][6:0])
    OP_REG: if(ei[i][30]) ex_result[i]=aa-bb; else ex_result[i]=aa+bb;
    OP_IMM,OP_LOAD: ex_result[i]=aa+{{20{ei[i][31]}},ei[i][31:20]};
    OP_STORE: ex_result[i]=aa+{{20{ei[i][31]}},ei[i][31:25],ei[i][11:7]};
    OP_LUI: ex_result[i]={ei[i][31:12],12'b0};
    default: ex_result[i]=0;
   endcase
   if(i==0 && ev[i] && is_branch(ei[i])) begin
    a1=(ei[i][14:12]==3'b000 && aa==bb); a2=(ei[i][14:12]==3'b001 && aa!=bb);
    if(a1 || a2) begin
     imm={{19{ei[i][31]}},ei[i][31],ei[i][7],ei[i][30:25],ei[i][11:8],1'b0};
     redirect=1; branch_target=epc[i]+imm;
    end
   end
  end
 end
 always_ff @(posedge clk) begin : pipeline
  logic [31:0] ins0,ins1; logic v0,v1;
  if(!rst_n) begin
   fetch_pc<=0; id_pc<=0; id0<=0; id1<=0; id_valid<=0; stop_fetch<=0; halted<=0;
   stat_cycles<=0; stat_retired<=0; stat_pairs<=0; stat_load_stalls<=0; stat_flushes<=0;
   for(integer i=1;i<32;i=i+1) regs[i]<=0;
   for(integer i=0;i<2;i=i+1) begin ev[i]<=0; mv[i]<=0; wv[i]<=0; ei[i]<=0; mi[i]<=0; wi[i]<=0; epc[i]<=0; ea[i]<=0; eb[i]<=0; mr[i]<=0; ms[i]<=0; wvdata[i]<=0; end
  end else if(!halted) begin
   stat_cycles<=stat_cycles+1; stat_retired<=stat_retired+32'(wv[0])+32'(wv[1]);
   for(integer i=0;i<2;i=i+1) begin
    if(wv[i] && writes_reg(wi[i])) regs[wi[i][11:7]]<=wvdata[i];
    wv[i]<=mv[i]; wi[i]<=mi[i]; wvdata[i]<=(mi[i][6:0]==OP_LOAD) ? dmem_rdata : mr[i];
    mv[i]<=ev[i]; mi[i]<=ei[i]; mr[i]<=ex_result[i]; ms[i]<=ex_store[i];
    ev[i]<=0;
   end
   if((wv[0] && wi[0]==EBREAK)||(wv[1] && wi[1]==EBREAK)) halted<=1;
   if(redirect) begin fetch_pc<=branch_target; id_valid<=0; stop_fetch<=0; stat_flushes<=stat_flushes+1; end
   else if(load_hazard && !stop_fetch) stat_load_stalls<=stat_load_stalls+1;
   else if(!stop_fetch) begin
    if(!id_valid) begin id0<=imem_lo; id1<=imem_hi; id_pc<=fetch_pc; fetch_pc<=fetch_pc+8; id_valid<=1; end
    else begin
     v0=0; v1=0; ins0=0; ins1=0;
     if(first_mem) begin v1=1; ins1=id0; if(issue_two) begin v0=1; ins0=id1; end end
     else begin v0=1; ins0=id0; if(issue_two) begin v1=1; ins1=id1; end end
     ev[0]<=v0; ev[1]<=v1; ei[0]<=ins0; ei[1]<=ins1;
     epc[0]<=first_mem && issue_two ? id_pc+4 : id_pc;
     epc[1]<=first_mem ? id_pc : id_pc+4;
     ea[0]<=read_id(ins0[19:15]); eb[0]<=read_id(ins0[24:20]);
     ea[1]<=read_id(ins1[19:15]); eb[1]<=read_id(ins1[24:20]);
     if(issue_two) begin stat_pairs<=stat_pairs+1; id0<=imem_lo; id1<=imem_hi; id_pc<=fetch_pc; fetch_pc<=fetch_pc+8; end
     else if(id0==EBREAK) begin id_valid<=0; stop_fetch<=1; end
     else begin id0<=id1; id1<=imem_lo; id_pc<=id_pc+4; fetch_pc<=fetch_pc+4; end
    end
   end
  end
 end
endmodule
