`timescale 1ns/1ps
module tb_superscalar_dual_issue;
 logic clk=0,rst_n=0; always #5 clk=~clk;
 logic [31:0] ia0,lo,hi,da0,dw0,dr0,dbg0; logic we0,h0; logic [31:0] cyc0,ret0,pairs,stalls,flushes;
 logic [31:0] ia1,ins1,da1,dw1,dr1,dbg1; logic we1,h1; logic [31:0] cyc1,ret1,stall1,flush1; logic [4:0] dbg_addr=0;
 logic [31:0] rom[0:255],mem0[0:63],mem1[0:63];
 superscalar_dual_issue dut(.clk,.rst_n,.imem_addr(ia0),.imem_lo(lo),.imem_hi(hi),.dmem_addr(da0),.dmem_wdata(dw0),.dmem_we(we0),.dmem_rdata(dr0),.dbg_raddr(dbg_addr),.dbg_rdata(dbg0),.halted(h0),.stat_cycles(cyc0),.stat_retired(ret0),.stat_pairs(pairs),.stat_load_stalls(stalls),.stat_flushes(flushes));
 rv32i_pipeline scalar(.clk,.rst_n,.imem_addr(ia1),.imem_rdata(ins1),.dmem_addr(da1),.dmem_wdata(dw1),.dmem_we(we1),.dmem_rdata(dr1),.dbg_raddr(dbg_addr),.dbg_rdata(dbg1),.halted(h1),.stat_cycles(cyc1),.stat_retired(ret1),.stat_load_stalls(stall1),.stat_flushes(flush1));
 assign lo=(ia0<1024) ? rom[ia0[9:2]] : 32'h00100073;
 assign hi=(ia0<1020) ? rom[ia0[9:2]+1] : 32'h00100073;
 assign ins1=(ia1<1024) ? rom[ia1[9:2]] : 32'h00100073;
 assign dr0=mem0[da0[7:2]]; assign dr1=mem1[da1[7:2]];
 always @(posedge clk) begin if(we0) mem0[da0[7:2]]<=dw0; if(we1) mem1[da1[7:2]]<=dw1; end
 function automatic [31:0] addi(input integer rd,rs,imm); addi={12'(imm),5'(rs),3'b000,5'(rd),7'h13}; endfunction
 function automatic [31:0] add(input integer rd,rs1,rs2); add={7'b0,5'(rs2),5'(rs1),3'b000,5'(rd),7'h33}; endfunction
 function automatic [31:0] sub(input integer rd,rs1,rs2); sub={7'b0100000,5'(rs2),5'(rs1),3'b000,5'(rd),7'h33}; endfunction
 function automatic [31:0] lw(input integer rd,offset); lw={12'(offset),5'b0,3'b010,5'(rd),7'h03}; endfunction
 function automatic [31:0] sw(input integer rs,offset); logic [11:0] i; begin i=12'(offset); sw={i[11:5],5'(rs),5'b0,3'b010,i[4:0],7'h23}; end endfunction
 function automatic [31:0] beq(input integer r1,r2,offset); logic [12:0] i; begin i=13'(offset); beq={i[12],i[10:5],5'(r2),5'(r1),3'b000,i[4:1],i[11],7'h63}; end endfunction
 function automatic [31:0] bne(input integer r1,r2,offset); logic [12:0] i; begin i=13'(offset); bne={i[12],i[10:5],5'(r2),5'(r1),3'b001,i[4:1],i[11],7'h63}; end endfunction
 task automatic setup;
  begin rst_n=0; for(integer i=0;i<256;i=i+1) rom[i]=32'h00100073;
   for(integer i=0;i<64;i=i+1) begin mem0[i]=0; mem1[i]=0; end
   for(integer i=0;i<8;i=i+1) begin mem0[i]=32'((i+1)*(i+1)); mem1[i]=32'((i+1)*(i+1)); end
  end
 endtask
 task automatic execute_case(input bit expect_hazards);
  integer t;
  begin repeat(3) @(negedge clk); rst_n=1; t=0;
   while(!(h0 && h1) && t<3000) begin @(negedge clk); t=t+1; end
   if(t==3000) $fatal(1,"timeout");
   for(integer i=0;i<32;i=i+1) begin dbg_addr=5'(i); #1; if(dbg0!==dbg1) $fatal(1,"x%0d dual=%h scalar=%h",i,dbg0,dbg1); end
   for(integer i=0;i<64;i=i+1) if(mem0[i]!==mem1[i]) $fatal(1,"memory %0d dual=%h scalar=%h",i,mem0[i],mem1[i]);
   if(ret0!==ret1) $fatal(1,"retired mismatch %0d %0d",ret0,ret1);
   if(expect_hazards && (stalls==0 || flushes==0 || pairs==0)) $fatal(1,"missing hazard events");
  end
 endtask
 integer k,scheduled_cycles,unscheduled_cycles,op,rd,rs1,rs2,imm,addr; reg [31:0] seed,scheduled_regs[0:31],scheduled_mem[0:63];
 initial begin
  setup();
  rom[0]=addi(1,0,5); rom[1]=addi(2,0,7); rom[2]=add(3,1,2); rom[3]=addi(4,3,1);
  rom[4]=sw(4,64); rom[5]=lw(5,64); rom[6]=add(6,5,3); rom[7]=beq(6,6,16);
  rom[8]=addi(7,0,99); rom[9]=sw(4,76); rom[10]=32'h00100073;
  rom[11]=addi(8,0,3); rom[12]=addi(9,0,1); rom[13]=addi(9,9,2);
  rom[14]=addi(10,9,5); rom[15]=sw(10,68); rom[16]=addi(11,0,3); rom[17]=addi(12,0,0);
  rom[18]=addi(12,12,1); rom[19]=addi(11,11,-1); rom[20]=bne(11,0,-8); rom[21]=sw(12,72); rom[22]=32'h00100073;
  execute_case(1); dbg_addr=7; #1; if(dbg0!==0 || mem0[16]!==13 || mem0[17]!==8 || mem0[18]!==3 || mem0[19]!==0) $fatal(1,"directed outcome");
  @(negedge clk); setup(); k=0;
  for(integer i=0;i<23;i=i+1) begin
   rom[k]=lw(5,(i%8)*4); k=k+1; rom[k]=addi(1,1,1); k=k+1;
   rom[k]=addi(3,3,1); k=k+1; rom[k]=lw(6,((i+1)%8)*4); k=k+1;
   rom[k]=add(2,2,5); k=k+1; rom[k]=addi(4,4,1); k=k+1;
   rom[k]=sub(2,2,6); k=k+1; rom[k]=addi(7,7,1); k=k+1;
  end
  rom[k]=sw(2,64); rom[k+1]=32'h00100073;
  execute_case(0); scheduled_cycles=cyc0;
  if(mem0[16]!==32'hffffffc1 || ret0*2<=cyc0*3) $fatal(1,"scheduled dot product or IPC %0d/%0d result=%0d",ret0,cyc0,mem0[16]);
  for(integer i=0;i<32;i=i+1) begin dbg_addr=5'(i); #1; scheduled_regs[i]=dbg0; end
  for(integer i=0;i<64;i=i+1) scheduled_mem[i]=mem0[i];
  @(negedge clk); setup(); k=0;
  for(integer i=0;i<23;i=i+1) begin
   rom[k]=lw(5,(i%8)*4); k=k+1; rom[k]=add(2,2,5); k=k+1;
   rom[k]=addi(1,1,1); k=k+1; rom[k]=addi(3,3,1); k=k+1;
   rom[k]=lw(6,((i+1)%8)*4); k=k+1; rom[k]=sub(2,2,6); k=k+1;
   rom[k]=addi(4,4,1); k=k+1; rom[k]=addi(7,7,1); k=k+1;
  end
  rom[k]=sw(2,64); rom[k+1]=32'h00100073;
  execute_case(0); unscheduled_cycles=cyc0;
  if(mem0[16]!==32'hffffffc1 || scheduled_cycles>=unscheduled_cycles) $fatal(1,"scheduling %0d vs %0d",scheduled_cycles,unscheduled_cycles);
  for(integer i=0;i<32;i=i+1) begin dbg_addr=5'(i); #1; if(dbg0!==scheduled_regs[i]) $fatal(1,"schedule register %0d",i); end
  for(integer i=0;i<64;i=i+1) if(mem0[i]!==scheduled_mem[i]) $fatal(1,"schedule memory %0d",i);
  @(negedge clk); setup(); seed=32'd731;
  for(integer i=0;i<180;i=i+1) begin
   seed=seed*32'd1664525+32'd1013904223;
   op=int'(seed[31:30]); rd=1+int'(seed[7:4]); rs1=int'(seed[3:0]); rs2=int'(seed[11:8]); imm=int'(seed[20:16])-16; addr=(8+int'(seed[12:10]))*4;
   case(op)
    0: rom[i]=addi(rd,rs1,imm);
    1: if(seed[29]) rom[i]=sub(rd,rs1,rs2); else rom[i]=add(rd,rs1,rs2);
    2: rom[i]=lw(rd,addr);
    default: rom[i]=sw(rs2,addr);
   endcase
  end
  rom[180]=32'h00100073; execute_case(0);
  $display("scheduled %0d cycles; unscheduled %0d cycles",scheduled_cycles,unscheduled_cycles);
  $display("TEST PASSED"); $finish;
 end
 initial begin #100000; $fatal(1,"timeout"); end
endmodule
