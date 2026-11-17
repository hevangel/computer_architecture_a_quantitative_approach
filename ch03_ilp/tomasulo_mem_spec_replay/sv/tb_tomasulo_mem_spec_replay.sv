`timescale 1ns/1ps
module tb_tomasulo_mem_spec_replay;
 reg clk=0,rst_n=0,init_we=0,dinit_we=0,start=0; reg [2:0] init_reg=0,dbg_reg=0; reg [5:0] dinit_addr=0,dbg_addr=0; reg [31:0] init_data=0,dinit_data=0;
 wire [7:0] pc[0:2]; wire [31:0] code[0:2],cycles[0:2],commits[0:2],branches[0:2],flushes[0:2],squashed[0:2],loads[0:2],stores[0:2],fwds[0:2],replays[0:2],regs[0:2],mems[0:2]; wire [2:0] halted;
 reg [31:0] rom[0:63]; integer i; always #5 clk=~clk;
 genvar g; generate for(g=0;g<3;g=g+1) begin: core
  assign code[g]=rom[pc[g][5:0]];
  tomasulo_mem_spec_replay #(.MUL_LAT(8),.SPEC_MEM(g!=0),.RESOLVE_BRANCH(g!=0),.PREDICT_BTFN(g==2)) dut(
   .clk,.rst_n,.init_we,.init_reg,.init_data,.dinit_we,.dinit_addr,.dinit_data,.start,.imem_addr(pc[g]),.imem_rdata(code[g]),.halted(halted[g]),
   .stat_cycles(cycles[g]),.stat_committed(commits[g]),.stat_branches(branches[g]),.stat_flushes(flushes[g]),.stat_squashed(squashed[g]),
   .stat_loads(loads[g]),.stat_stores(stores[g]),.stat_fwd(fwds[g]),.stat_replays(replays[g]),.dbg_raddr(dbg_reg),.dbg_rdata(regs[g]),.dbg_maddr(dbg_addr),.dbg_mdata(mems[g]));
 end endgenerate
 function automatic [31:0] ins(input [3:0] op,rd,rs,rt,input integer imm); ins={op,rd,rs,rt,16'(imm)}; endfunction
 task automatic setup;
  begin
   @(negedge clk); rst_n=0; init_we=0; dinit_we=0; start=0; repeat(2) @(negedge clk); rst_n=1;
   for(integer r=0;r<8;r=r+1) begin @(negedge clk); init_we=1; init_reg=3'(r); case(r) 1:init_data=2; 2:init_data=3; 5:init_data=55; default:init_data=0; endcase @(negedge clk); init_we=0; end
   for(integer a=0;a<16;a=a+1) begin @(negedge clk); dinit_we=1; dinit_addr=6'(a); dinit_data=32'(1000+a); @(negedge clk); dinit_we=0; end
  end
 endtask
 task automatic run;
  integer t; begin @(negedge clk); start=1; @(negedge clk); start=0; t=0;
   while(halted!=3'b111 && t<1000) begin @(negedge clk); t=t+1; end
   if(t==1000) $fatal(1,"timeout");
  end
 endtask
 task automatic check_reg(input integer r,input [31:0] value); begin dbg_reg=3'(r); #1; if(regs[0]!==value || regs[1]!==value || regs[2]!==value) $fatal(1,"reg %0d got %h %h expected %h",r,regs[0],regs[1],value); end endtask
 task automatic check_mem(input integer a,input [31:0] value); begin dbg_addr=6'(a); #1; if(mems[0]!==value || mems[1]!==value || mems[2]!==value) $fatal(1,"memory %0d",a); end endtask
 reg [31:0] seed=32'd8941,gr[0:7],gm[0:63]; integer ty,rd,rs,rt,imm,op,steps,pcg,ncommit,nbranch,nstore,nload,ntaken,total_replays,addr;
 function automatic integer rnd(input integer limit); begin seed=seed*32'd1664525+32'd1013904223; rnd=int'(seed[30:16])%limit; end endfunction
 initial begin
  for(i=0;i<64;i=i+1) rom[i]=ins(4,0,0,0,0);
  // Independent load can bypass the unresolved store address.
  rom[0]=ins(2,3,1,2,0); rom[1]=ins(6,0,3,5,0); rom[2]=ins(5,4,0,0,9); rom[3]=ins(4,0,0,0,0);
  setup(); run(); check_reg(4,1009); check_mem(6,55);
  if(replays[1]!=0 || cycles[0]<cycles[1]+3) $fatal(1,"independent cycles %0d %0d replay %0d",cycles[0],cycles[1],replays[1]);
  $display("independent conservative=%0d speculative=%0d",cycles[0],cycles[1]);
  // A speculative load and its dependent must be replayed after alias discovery.
  rom[2]=ins(5,4,0,0,6); rom[3]=ins(0,6,4,4,0); rom[4]=ins(4,0,0,0,0);
  setup(); run(); check_reg(4,55); check_reg(6,110); check_mem(6,55);
  if(replays[1]!=1 || replays[0]!=0 || squashed[1]<2) $fatal(1,"alias recovery replays=%0d squashed=%0d",replays[1],squashed[1]);
  // Branch resolves while an older multiply is still executing; retain that work.
  rom[0]=ins(2,3,1,2,0); rom[1]=ins(3,0,1,0,5); rom[2]=ins(6,0,0,5,7); rom[3]=ins(5,6,0,0,7); rom[4]=ins(0,4,6,6,0); rom[5]=ins(5,7,0,0,8); rom[6]=ins(4,0,0,0,0);
  setup(); run(); check_reg(3,6); check_reg(7,1008); check_reg(6,0); check_mem(7,1007);
  if(flushes[1]!=1 || stores[1]!=0 || squashed[1]==0 || cycles[1]>=cycles[0]) $fatal(1,"branch recovery %0d/%0d",cycles[0],cycles[1]);
  $display("branch conservative=%0d resolve=%0d",cycles[0],cycles[1]);
  // Two late stores alias the same speculative load: the younger store wins.
  rom[0]=ins(2,3,1,2,0); rom[1]=ins(2,6,1,2,0); rom[2]=ins(6,0,3,5,0); rom[3]=ins(6,0,6,1,0);
  rom[4]=ins(5,4,0,0,6); rom[5]=ins(0,7,4,4,0); rom[6]=ins(4,0,0,0,0);
  setup(); run(); check_reg(4,2); check_reg(7,4); check_mem(6,2);
  if(replays[1]==0 || stores[1]!=2) $fatal(1,"multiple-store recovery");
  // Rename recovery must preserve the older multiply while discarding newer WAW chains.
  rom[0]=ins(2,3,1,2,0); rom[1]=ins(6,0,3,5,0); rom[2]=ins(5,4,0,0,6);
  rom[3]=ins(0,4,1,2,0); rom[4]=ins(0,6,4,4,0); rom[5]=ins(4,0,0,0,0);
  setup(); run(); check_reg(3,6); check_reg(4,5); check_reg(6,10); check_mem(6,55);
  if(replays[1]==0) $fatal(1,"WAW recovery");
  // A backward loop wraps the ROB and repeatedly squashes speculative HALT.
  rom[0]=ins(1,7,2,1,0); rom[1]=ins(0,6,6,1,0); rom[2]=ins(1,2,2,7,0);
  rom[3]=ins(3,0,2,0,1); rom[4]=ins(4,0,0,0,0);
  setup(); run(); check_reg(7,1); check_reg(2,0); check_reg(6,6);
  if(branches[1]!=3 || flushes[1]!=2 || commits[1]!=11 || branches[2]!=3 || flushes[2]!=1 || commits[2]!=11) $fatal(1,"ROB wrap branch recovery");
  total_replays=0;
  for(integer pidx=0;pidx<100;pidx=pidx+1) begin
   for(integer k=0;k<24;k=k+1) begin
    ty=rnd(10); rd=rnd(8); rs=rnd(8); rt=rnd(8); imm=rnd(8); op=rnd(3);
    if(ty<3) rom[k]=ins(4'(op),4'(rd),4'(rs),4'(rt),0);
    else if(ty<6) rom[k]=ins(5,4'(rd),4'(rs),0,imm);
    else if(ty<9) rom[k]=ins(6,0,4'(rs),4'(rt),imm);
    else if(k<22) rom[k]=ins(3,0,4'(rs),0,k+2+(imm%(23-k)));
    else rom[k]=ins(0,4'(rd),4'(rs),4'(rt),0);
   end
   rom[24]=ins(4,0,0,0,0);
   for(integer r=0;r<8;r=r+1) begin case(r) 1:gr[r]=2; 2:gr[r]=3; 5:gr[r]=55; default:gr[r]=0; endcase end
   for(integer a=0;a<64;a=a+1) gm[a]=(a<16)?32'(1000+a):0;
   pcg=0; steps=0; ncommit=0; nbranch=0; nstore=0; nload=0; ntaken=0;
   while(pcg<25 && steps<50) begin
    op=int'(rom[pcg][31:28]); rd=int'(rom[pcg][26:24]); rs=int'(rom[pcg][22:20]); rt=int'(rom[pcg][18:16]); imm=int'(rom[pcg][15:0]);
    ncommit=ncommit+1; steps=steps+1;
    case(op)
     0:gr[rd]=gr[rs]+gr[rt]; 1:gr[rd]=gr[rs]-gr[rt]; 2:gr[rd]=gr[rs]*gr[rt];
     3:begin nbranch=nbranch+1; if(gr[rs]!=0) begin ntaken=ntaken+1; pcg=imm-1; end end
     5:begin addr=(int'(gr[rs][5:0])+imm)%64; gr[rd]=gm[addr]; nload=nload+1; end
     6:begin addr=(int'(gr[rs][5:0])+imm)%64; gm[addr]=gr[rt]; nstore=nstore+1; end
     default:pcg=25;
    endcase
    pcg=pcg+1;
   end
   setup(); run();
   for(integer r=0;r<8;r=r+1) check_reg(r,gr[r]);
   for(integer a=0;a<64;a=a+1) check_mem(a,gm[a]);
   if(commits[0]!=ncommit || commits[1]!=ncommit || branches[0]!=nbranch || branches[1]!=nbranch || stores[0]!=nstore || stores[1]!=nstore || loads[0]!=nload || loads[1]!=nload || flushes[0]!=ntaken || flushes[1]<ntaken || commits[2]!=ncommit || branches[2]!=nbranch || stores[2]!=nstore || loads[2]!=nload || flushes[2]<ntaken) $fatal(1,"random %0d commits %0d/%0d/%0d exp %0d branches %0d/%0d/%0d exp %0d stores %0d/%0d/%0d exp %0d loads %0d/%0d/%0d exp %0d flush %0d/%0d/%0d exp %0d replays %0d",pidx,commits[0],commits[1],commits[2],ncommit,branches[0],branches[1],branches[2],nbranch,stores[0],stores[1],stores[2],nstore,loads[0],loads[1],loads[2],nload,flushes[0],flushes[1],flushes[2],ntaken,replays[1]);
   if(pidx==95 && (flushes[1]<=ntaken || flushes[2]<=ntaken)) $fatal(1,"wrong-path branch recovery accounting");
   total_replays=total_replays+int'(replays[1]);
  end
  $display("random programs=100 speculative replays=%0d",total_replays);
  $display("TEST PASSED"); $finish;
 end
 initial begin #400000; $fatal(1,"timeout"); end
endmodule
