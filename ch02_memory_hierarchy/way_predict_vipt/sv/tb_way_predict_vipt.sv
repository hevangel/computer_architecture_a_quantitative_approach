`timescale 1ns/1ps
module tb_way_predict_vipt;
 reg clk=0,reset=1,req_valid=0,req_write=0; reg [15:0] va=0,pa=0,dbg_addr=0; reg [31:0] wd=0;
 wire ready,rv,fault,safe,busy; wire [31:0] rd,fast,slow,miss,probes,dbg; wire [1:0] word;
 reg bad_valid=0; wire bad_ready,bad_rv,bad_fault,bad_safe; wire [31:0] bad_data;
 always #5 clk=~clk;
 way_predict_vipt dut(.clk,.reset,.req_valid,.req_write,.req_vaddr(va),.req_paddr(pa),.req_wdata(wd),.req_ready(ready),.resp_valid(rv),.resp_fault(fault),.resp_data(rd),.config_safe(safe),.refill_busy(busy),.refill_word(word),.stat_fast(fast),.stat_slow(slow),.stat_miss(miss),.stat_way_reads(probes),.dbg_paddr(dbg_addr),.dbg_memory(dbg));
 way_predict_vipt #(.PAGE_BITS(5)) bad(.clk,.reset,.req_valid(bad_valid),.req_write(1'b0),.req_vaddr(16'h0),.req_paddr(16'h0),.req_wdata(32'h0),.req_ready(bad_ready),.resp_valid(bad_rv),.resp_fault(bad_fault),.resp_data(bad_data),.config_safe(bad_safe),.refill_busy(),.refill_word(),.stat_fast(),.stat_slow(),.stat_miss(),.stat_way_reads(),.dbg_paddr(16'h0),.dbg_memory());
 task automatic access(input bit w,input [15:0] v,input [15:0] p,input [31:0] data,input [31:0] expected,input integer latency,input bit is_fault);
  integer cycles,n; reg [1:0] first;
  begin
   @(negedge clk); while(!ready) @(negedge clk);
   va=v; pa=p; wd=data; req_write=w; req_valid=1; first=v[3:2]; n=0; cycles=0;
   @(negedge clk); req_valid=0; cycles=1; #1;
   while(!rv && cycles<20) begin
    if(busy) begin if(word!==((first+n)&3)) $fatal(1,"refill order"); n=n+1; end
    @(negedge clk); #1; cycles=cycles+1;
   end
   if(!rv || fault!==is_fault || (!is_fault && rd!==expected) || (latency!=0 && cycles!=latency))
    $fatal(1,"response v=%h latency %0d expected %0d data %h expected %h fault %b",v,cycles,latency,rd,expected,fault);
   if(latency==3 && (!busy || ready)) $fatal(1,"critical response not early");
   while(!ready) begin
    if(busy) begin if(word!==((first+n)&3)) $fatal(1,"refill order after response"); n=n+1; end
    @(negedge clk); #1;
   end
   if(n!=0 && n!=4) $fatal(1,"refill beat count %0d",n);
  end
 endtask
 reg [31:0] shadow[0:16383]; reg [31:0] seed=32'd947,rand_value; integer a; bit wr; reg [15:0] phys,virt;
 initial begin
  repeat(3) @(negedge clk); reset=0;
  if(!safe || bad_safe) $fatal(1,"VIPT safety");
  access(0,16'h000c,16'h000c,0,32'h10000003,3,0);
  access(0,16'h0000,16'h0000,0,32'h10000000,1,0);
  access(0,16'h0040,16'h0040,0,32'h10000010,3,0);
  access(0,16'h0000,16'h0000,0,32'h10000000,2,0);
  access(0,16'h0000,16'h0000,0,32'h10000000,1,0);
  access(1,16'h1000,16'h0000,32'habcdef01,32'habcdef01,1,0);
  access(0,16'h2000,16'h0000,0,32'habcdef01,1,0);
  access(0,16'h0080,16'h0080,0,32'h10000020,3,0);
  access(0,16'h0000,16'h0000,0,32'habcdef01,2,0);
  access(0,16'h0040,16'h0040,0,32'h10000010,3,0);
  if(fast!=4 || slow!=2 || miss!=4 || probes!=16) $fatal(1,"way counts %0d %0d %0d %0d",fast,slow,miss,probes);
  dbg_addr=0; #1; if(dbg!==32'habcdef01) $fatal(1,"write through");
  access(0,16'h1004,16'h0000,0,0,1,1);
  @(negedge clk); bad_valid=1; @(negedge clk); bad_valid=0; #1;
  if(!bad_ready || !bad_rv || !bad_fault) $fatal(1,"unsafe configuration accepted");
  for(integer i=0;i<16384;i=i+1) shadow[i]=32'h10000000+32'(i); shadow[0]=32'habcdef01;
  for(integer i=0;i<128;i=i+1) begin
   seed=seed*32'd1664525+32'd1013904223; a=int'(seed[23:10]); wr=seed[31];
   seed=seed*32'd1664525+32'd1013904223; rand_value=seed;
   phys=16'(a*4); virt={seed[31:28],phys[11:0]};
   if(wr) begin shadow[a]=rand_value; access(1,virt,phys,rand_value,rand_value,0,0); end
   else access(0,virt,phys,0,shadow[a],0,0);
  end
  for(integer i=0;i<16384;i=i+1) begin dbg_addr=16'(i*4); #1; if(dbg!==shadow[i]) $fatal(1,"memory mismatch %0d",i); end
  $display("TEST PASSED"); $finish;
 end
 initial begin #200000; $fatal(1,"timeout"); end
endmodule
