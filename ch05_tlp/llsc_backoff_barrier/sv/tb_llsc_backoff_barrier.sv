`timescale 1ns/1ps
module tb_llsc_backoff_barrier;
 logic clk=0,reset=1,cmd_valid=0,arrive=0; logic [1:0] cmd_core=0,cmd_op=0,arrive_core=0;
 logic [3:0] cmd_addr=0; logic [31:0] cmd_wdata=0;
 wire rsp_valid,sc_success; wire [31:0] rsp_data,invalidations; wire [3:0] waiting,local_sense; wire global_sense,barrier_release;
 wire [3:0] done; wire [31:0] rd[0:3],rdx[0:3],cycles[0:3],counter[0:3],cs[0:3];
 always #5 clk=~clk;
 llsc_barrier dut(.*);
 for(genvar g=0;g<4;g=g+1) begin : locks
  localparam int L=(g==0)?0:((g==1)?1:((g==2)?5:4));
  spinlock_bench #(.P(4),.N(8),.LOCK(L),.CS_LEN(12),.NT(0)) lockbench(.clk,.rst_n(!reset),.done(done[g]),.stat_rd(rd[g]),.stat_rdx(rdx[g]),.stat_cycles(cycles[g]),.counter(counter[g]),.cs_count(cs[g]),.acq_pulse(),.tick_pulse());
  always @(posedge clk) if(!reset && cs[g]>1) $fatal(1,"mutual exclusion lock %0d",L);
 end
 task automatic command(input int core,op,addr,input [31:0] data,input logic expect_sc,input [31:0] expect_read);
  begin
   @(negedge clk); cmd_valid=1; cmd_core=2'(core); cmd_op=2'(op); cmd_addr=4'(addr); cmd_wdata=data;
   @(negedge clk); cmd_valid=0;
   if(!rsp_valid || sc_success!==expect_sc || rsp_data!==expect_read) $fatal(1,"response core=%0d op=%0d data=%h sc=%b",core,op,rsp_data,sc_success);
  end
 endtask
 task automatic arrival(input int core);
  begin @(negedge clk); arrive=1; arrive_core=2'(core); @(negedge clk); arrive=0; end
 endtask
 initial begin
  repeat(2) @(negedge clk); reset=0;
  command(0,1,1,0,0,0); command(1,3,1,32'd9,0,0);
  if(invalidations!=1) $fatal(1,"remote reservation invalidation");
  command(0,2,1,32'd7,0,32'd9); command(0,0,1,0,0,32'd9);
  command(0,1,1,0,0,32'd9); command(1,3,2,32'd11,0,0);
  command(0,2,1,32'd7,1,32'd9); command(0,0,1,0,0,32'd7);
  command(0,2,1,32'd8,0,32'd7); // successful SC consumes reservation
  command(0,1,1,0,0,32'd7); command(2,1,1,0,0,32'd7);
  command(3,3,1,32'd12,0,32'd7);
  if(invalidations!=3) $fatal(1,"multi-reservation invalidation count");
  command(2,2,1,32'd4,0,32'd12);
  command(0,1,1,0,0,32'd12); command(0,2,2,32'd8,0,32'd11); command(0,2,1,32'd8,0,32'd12);
  command(3,1,1,0,0,32'd12); command(3,3,1,32'd15,0,32'd12); command(3,2,1,32'd8,0,32'd15);
  command(0,1,1,0,0,32'd15); command(2,1,1,0,0,32'd15); command(0,2,1,32'd21,1,32'd15);
  command(2,2,1,32'd8,0,32'd21); if(invalidations!=4) $fatal(1,"successful SC must invalidate remote reservation");
  arrival(0); if(waiting!=1 || global_sense || barrier_release) $fatal(1,"first barrier arrival");
  arrival(0); if(waiting!=1 || local_sense!=1) $fatal(1,"duplicate arrival");
  arrival(2); arrival(1); if(waiting!=7 || barrier_release) $fatal(1,"early barrier release");
  arrival(3); if(waiting!=0 || !global_sense || !barrier_release || local_sense!=15) $fatal(1,"first barrier release");
  arrival(3); arrival(1); arrival(0); if(waiting!=11 || !global_sense || barrier_release) $fatal(1,"second barrier incomplete");
  arrival(2); if(waiting!=0 || global_sense || !barrier_release || local_sense!=0) $fatal(1,"second barrier release");
  wait(done==4'b1111); @(negedge clk);
  for(integer i=0;i<4;i=i+1) if(counter[i]!=32) $fatal(1,"lost increment");
  if(cycles[0]!=738 || cycles[1]!=964 || cycles[2]!=930 || cycles[3]!=841) $fatal(1,"lock cycle counts");
  if(!(rdx[3]<rdx[0] && rdx[3]<rdx[1] && rdx[3]<rdx[2])) $fatal(1,"backoff traffic %0d %0d %0d %0d",rdx[0],rdx[1],rdx[2],rdx[3]);
  $display("lock BusRdX TAS=%0d TTAS=%0d LRSC=%0d backoff=%0d; cycles=%0d/%0d/%0d/%0d",rdx[0],rdx[1],rdx[2],rdx[3],cycles[0],cycles[1],cycles[2],cycles[3]);
  $display("TEST PASSED"); $finish;
 end
 initial begin #300000; $fatal(1,"timeout"); end
endmodule
