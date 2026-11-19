`timescale 1ns/1ps
module tb_nb_set_assoc_cache;
 import nb_reference_pkg::*;
 reg clk=0,rst_n=0,req_valid=0,req_write=0,flush=0,allow_mem=1;
 reg [7:0] req_addr=0,dbg_addr=0; reg [31:0] req_wdata=0; reg [5:0] req_id=0;
 wire ready,hv,fv,flush_done,mv,mw,mready,mrv,viol; wire [5:0] hid,fid; wire [31:0] hd,fd,debug,sh,sp,ss,sw,nlw;
 wire [7:0] ma; wire [127:0] mwd,mrl; wire [1:0] mt,mrt;
 always #5 clk=~clk;
 wb_cache #(.NM(4),.WBD(2),.WAYS(2),.FORWARD_WB(1)) dut(.clk,.rst_n,.req_valid,.req_write,.req_addr,.req_wdata,.req_id,.req_ready(ready),.hit_valid(hv),.hit_id(hid),.hit_data(hd),.fill_valid(fv),.fill_id(fid),.fill_data(fd),.flush,.flush_done,.mem_valid(mv),.mem_write(mw),.mem_addr(ma),.mem_wdata(mwd),.mem_tag(mt),.mem_ready(mready && allow_mem),.mem_rvalid(mrv),.mem_rtag(mrt),.mem_rline(mrl),.stat_hit(sh),.stat_pri(sp),.stat_sec(ss),.stat_wb(sw));
 wb_mem mem(.clk,.rst_n,.mem_valid(mv),.mem_write(mw),.mem_addr(ma),.mem_wdata(mwd),.mem_tag(mt),.mem_ready(mready),.mem_rvalid(mrv),.mem_rtag(mrt),.mem_rline(mrl),.dbg_addr,.dbg_data(debug),.violation(viol),.n_lwr(nlw));
 task automatic request(input bit wr,input int addr,input logic[31:0] data,input int id);
  begin @(negedge clk); req_valid=1; req_write=wr; req_addr=addr; req_wdata=data; req_id=id; #1;
   while (!ready) begin @(negedge clk); #1; end
   @(negedge clk); req_valid=0;
  end
 endtask
 task automatic answer(input int id,input logic[31:0] expected);
  integer t; begin t=0; #1;
   while (!((hv && hid==id)||(fv && fid==id)) && t<80) begin @(negedge clk); #1; t=t+1; end
   if(t==80 || (hv && hid==id && hd!==expected) || (fv && fid==id && fd!==expected)) $fatal(1,"response %0d",id);
  end
 endtask
 reg [TRACE_WIDTH-1:0] vector;
 reg ev,ew,eallow,er,ehv,efv,emv,emw; reg [7:0] ea,ema,ehc,epc,esc,ewc;
 reg [31:0] ed,ehd,efd; reg [5:0] ei,ehid,efid; reg [1:0] emt;
 integer pri_before,sec_before,hit_before,ra; reg [31:0] seed=32'd1481,rv; reg wr; reg [31:0] shadow[0:255];
 initial begin
  repeat(3) @(negedge clk); rst_n=1;
  request(1,0,32'h11112222,0); repeat(20) @(negedge clk);
  request(1,32,32'h33334444,1); repeat(20) @(negedge clk);
  request(0,0,0,2); answer(2,32'h11112222); if(sh!=1) $fatal(1,"LRU hit");
  request(0,64,0,3);
  while(!(mv && !mw && ma==64)) @(negedge clk);
  @(posedge clk); @(negedge clk); allow_mem=0;
  answer(3,32'h5a000440); repeat(3) @(negedge clk);
  request(0,32,0,4); answer(4,32'h33334444);
  if(nlw!=0 || viol) $fatal(1,"forwarding used memory");
  allow_mem=1; repeat(30) @(negedge clk);
  flush=1; while(!flush_done) @(negedge clk); @(negedge clk); flush=0;
  dbg_addr=0; #1; if(debug!==32'h11112222) $fatal(1,"flush line 0");
  dbg_addr=32; #1; if(debug!==32'h33334444) $fatal(1,"flush line 32");
  if(nlw!=2 || viol) $fatal(1,"writeback count");
  // Prime one line, then overlap two independent misses, a merged target,
  // and a hit on the primed line. Values are from the memory initialization.
  request(0,0,0,5); answer(5,32'h11112222); repeat(4) @(negedge clk);
  pri_before=sp; sec_before=ss; hit_before=sh;
  request(0,4,0,6); request(0,8,0,7); request(0,5,0,8);
  request(0,0,0,9); answer(9,32'h11112222);
  answer(6,32'h5a000044); answer(8,32'h5a000055); answer(7,32'h5a000088);
  if(sp-pri_before!=2 || ss-sec_before!=1 || sh-hit_before!=1 || viol)
    $fatal(1,"overlapping MSHRs and hit");
  for(integer i=0;i<256;i=i+1) shadow[i]=32'h5a000000+32'(i*17);
  shadow[0]=32'h11112222; shadow[32]=32'h33334444;
  for(integer i=0;i<200;i=i+1) begin
    seed=seed*32'd1664525+32'd1013904223; ra=seed[23:16]; wr=seed[31];
    seed=seed*32'd1664525+32'd1013904223; rv=seed;
    request(wr,ra,rv,10);
    if(wr) shadow[ra]=rv; else answer(10,shadow[ra]);
  end
  repeat(40) @(negedge clk); flush=1;
  while(!flush_done) @(negedge clk); @(negedge clk); flush=0;
  for(integer i=0;i<256;i=i+1) begin dbg_addr=i; #1; if(debug!==shadow[i]) $fatal(1,"random flush %0d",i); end
  if(viol) $fatal(1,"memory protocol");
  // Each reference frame is a pre-edge snapshot from the independent Python model.
  rst_n=0; repeat(3) @(negedge clk); rst_n=1;
  for(integer step=0;step<TRACE_LENGTH;step=step+1) begin
    @(negedge clk); vector=reference_frame(step);
    {ev,ew,ea,ed,ei,eallow,er,ehv,ehid,ehd,efv,efid,efd,emv,emw,ema,emt,ehc,epc,esc,ewc}=vector;
    req_valid=ev; req_write=ew; req_addr=ea; req_wdata=ed; req_id=ei; allow_mem=eallow; #1;
    if((ev && ready!==er) || hv!==ehv || (ehv && (hid!==ehid || hd!==ehd)) ||
       fv!==efv || (efv && (fid!==efid || fd!==efd)) || mv!==emv ||
       (emv && (mw!==emw || ma!==ema || (!emw && mt!==emt))) ||
       sh!=={24'b0,ehc} || sp!=={24'b0,epc} || ss!=={24'b0,esc} || sw!=={24'b0,ewc} || viol)
      $fatal(1,"reference mismatch at cycle %0d ready %b/%b hit %b/%b fill %b/%b mem %b/%b counters %0d,%0d,%0d,%0d expected %0d,%0d,%0d,%0d",step,ready,er,hv,ehv,fv,efv,mv,emv,sh,sp,ss,sw,ehc,epc,esc,ewc);
  end
  $display("TEST PASSED"); $finish;
 end
 initial begin #100000; $fatal(1,"timeout"); end
endmodule
