`timescale 1ns/1ps
module tb_nested_pt_walker;
 reg clk=0,reset=1,invalidate=0,valid=0,pwc=0,mem_ready=1; reg [31:0] va=0,gr=32'h10000,hr=32'h2000; reg [15:0] asid=0;
 wire ready,rv,fault,big,mv; wire [31:0] pa,ma,reads,hits,thits; reg mrv=0; reg [31:0] mrdata=0; integer mode=0,transactions=0; bit stall_next=1;
 always #5 clk=~clk;
 nested_pt_walker dut(.clk,.reset,.invalidate,.req_valid(valid),.pwc_enable(pwc),.req_vaddr(va),.req_guest_root(gr),.req_host_root(hr),.req_asid(asid),.req_ready(ready),.resp_valid(rv),.resp_fault(fault),.resp_super(big),.resp_paddr(pa),.mem_valid(mv),.mem_ready,.mem_addr(ma),.mem_rvalid(mrv),.mem_rdata(mrdata),.stat_mem_reads(reads),.stat_pwc_hits(hits),.stat_tlb_hits(thits));
 function automatic [31:0] memory(input [31:0] address,input integer choice);
  begin case(address)
   32'h2000: memory=32'h4001;
   32'h2004: if(choice==5) memory=32'h00401003; else if(choice==1) memory=32'h00400003; else memory=32'h6001;
   32'h4040: memory=32'h10001;
   32'h4048: memory=32'h12001;
   32'h4060: memory=32'h18001;
   32'h4068: memory=32'h1a001;
   32'h4080: if(choice==6) memory=32'h20003; else memory=32'h20001;
   32'h4084: memory=32'h21001;
   32'h4088: memory=32'h22001;
   32'h6048: memory=32'h00500001;
   32'h10000: memory=32'h12001;
   32'h12008: memory=32'h20001;
   32'h10008: if(choice==4) memory=32'h00201003; else if(choice==1 || choice==2 || choice==5) memory=32'h00200003; else if(choice==3) memory=0; else memory=32'h12001;
   32'h12048: memory=32'h20001;
   32'h1204c: memory=32'h21001;
   32'h18008: memory=32'h1a001;
   32'h1a048: memory=32'h21001;
   default: memory=0;
  endcase end
 endfunction
 always @(posedge clk) begin
  if(reset) begin mrv<=0; mrdata<=0; transactions<=0; end
  else begin mrv<=mv && mem_ready; if(mv && mem_ready) begin mrdata<=memory(ma,mode); transactions<=transactions+1; end end
 end
 task automatic clear_cache; begin @(negedge clk); while(!ready) @(negedge clk); invalidate=1; @(negedge clk); invalidate=0; end endtask
 task automatic translate(input [31:0] address,input [15:0] id,input [31:0] root,input bit use_pwc,input bit expected_fault,input [31:0] expected,input bit superpage,input integer read_count);
  integer before_count,elapsed; reg [31:0] held_address;
  begin
   @(negedge clk); while(!ready) @(negedge clk); va=address; asid=id; gr=root; pwc=use_pwc; valid=1; before_count=reads;
   @(negedge clk); valid=0; #1; elapsed=1;
   if(stall_next) begin
    while(!mv) begin @(negedge clk); #1; end
    held_address=ma; mem_ready=0;
    repeat(3) begin @(negedge clk); #1; if(!mv || ma!==held_address || reads!=before_count) $fatal(1,"memory backpressure"); end
    mem_ready=1; stall_next=0;
   end
   while(!rv && elapsed<300) begin @(negedge clk); #1; elapsed=elapsed+1; end
   if(!rv || fault!==expected_fault || (!expected_fault && (pa!==expected || big!==superpage)) || (read_count>=0 && reads-before_count!=read_count))
    $fatal(1,"translation va=%h asid=%0d fault=%b pa=%h super=%b reads=%0d expected %0d",address,id,fault,pa,big,reads-before_count,read_count);
  end
 endtask
 reg [31:0] seed=32'd2031, random_va, random_pa; integer random_asid;
 initial begin
  repeat(3) @(negedge clk); reset=0;
  translate(32'h00412034,1,32'h10000,0,0,32'h20034,0,8);
  translate(32'h00412038,1,32'h10000,0,0,32'h20038,0,0);
  if(thits!=1 || reads!=transactions) $fatal(1,"TLB counter");
  clear_cache();
  translate(32'h00412034,1,32'h10000,1,0,32'h20034,0,6);
  translate(32'h00413034,1,32'h10000,1,0,32'h21034,0,2);
  translate(32'h00412034,2,32'h18000,1,0,32'h21034,0,4);
  translate(32'h00412034,1,32'h10000,1,0,32'h20034,0,0);
  if(hits==0) $fatal(1,"PWC never hit");
  clear_cache(); mode=1;
  translate(32'h00412034,1,32'h10000,0,0,32'h00412034,1,4);
  translate(32'h00002034,1,32'h10000,0,0,32'h00020034,0,8);
  translate(32'h00414034,1,32'h10000,0,0,32'h00414034,1,0);
  translate(32'h00002038,1,32'h10000,0,0,32'h00020038,0,0);
  clear_cache(); mode=2;
  translate(32'h00412034,1,32'h10000,0,0,32'h00500034,0,5);
  translate(32'h00413034,1,32'h10000,0,1,0,0,5);
  clear_cache(); mode=3;
  translate(32'h00412034,1,32'h10000,0,1,0,0,3);
  translate(32'h00412034,1,32'h10001,0,1,0,0,0);
  clear_cache(); mode=4; translate(32'h00412034,1,32'h10000,0,1,0,0,3);
  clear_cache(); mode=5; translate(32'h00412034,1,32'h10000,0,1,0,0,4);
  clear_cache(); mode=6; translate(32'h00412034,1,32'h10000,0,1,0,0,8);
  clear_cache(); mode=0;
  translate(32'h00412034,1,32'h10000,0,0,32'h20034,0,8);
  translate(32'h00412034,2,32'h10000,0,0,32'h20034,0,8);
  translate(32'h00412034,3,32'h10000,0,0,32'h20034,0,8);
  translate(32'h00412034,4,32'h10000,0,0,32'h20034,0,8);
  translate(32'h00412034,1,32'h10000,0,0,32'h20034,0,0);
  translate(32'h00412034,5,32'h10000,0,0,32'h20034,0,8);
  translate(32'h00412034,1,32'h10000,0,0,32'h20034,0,0);
  translate(32'h00412034,2,32'h10000,0,0,32'h20034,0,8);
  clear_cache();
  for(integer i=0;i<128;i=i+1) begin
   seed=seed*32'd1664525+32'd1013904223;
   random_va=(seed[16] ? 32'h00413000 : 32'h00412000) | {20'b0,seed[11:0]};
   random_pa=(seed[16] ? 32'h00021000 : 32'h00020000) | {20'b0,seed[11:0]};
   random_asid=1+int'(seed[18:17]);
   translate(random_va,random_asid,32'h10000,0,0,random_pa,0,-1);
  end
  if(reads!=transactions) $fatal(1,"memory count");
  $display("TEST PASSED"); $finish;
 end
 initial begin #100000; $fatal(1,"timeout"); end
endmodule
