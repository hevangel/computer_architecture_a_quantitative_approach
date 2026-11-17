`timescale 1ns/1ps
module tb_prf_rename_ooo;
 reg clk=0,reset=1,init_we=0,valid=0,pred=0; reg [2:0] init_reg=0,dst=0,src1=0,src2=0,dbg_reg=0; reg [31:0] init_data=0; reg [1:0] op=0;
 wire ready,recover,taken,idle; wire [7:0] recover_id,p_recover_id; wire [31:0] dbg_value,issued,committed,squashed,recoveries,ooo; wire [3:0] front,arch,count; wire [15:0] free_bits; wire [4:0] free_count;
 reg check_conservation=0; integer full_stalls=0; always #5 clk=~clk;
 reg p_reset=1,p_init=0,p_valid=0,p_done=0,p_pred=0; reg [1:0] p_op=2; wire p_ready,p_idle,p_recover; wire [15:0] p_free_bits; wire [31:0] p_squashed; wire [4:0] p_free; wire [3:0] p_count; wire [31:0] p_value,p_issued,p_committed;
 prf_rename_ooo #(.NPHYS(12)) pressure(.clk,.reset(p_reset),.init_we(p_init),.init_reg(3'd0),.init_data(32'd1),.issue_valid(p_valid),.issue_op(p_op),.issue_dst(3'd0),.issue_src1(3'd0),.issue_src2(3'd0),.issue_pred_taken(p_pred),.issue_branch_id(8'd7),.issue_ready(p_ready),.recover_valid(p_recover),.recover_taken(),.recover_branch_id(p_recover_id),.idle(p_idle),.dbg_reg(3'd0),.dbg_value(p_value),.dbg_front(),.dbg_arch(),.dbg_free(p_free_bits),.free_count(p_free),.rob_count(p_count),.stat_issued(p_issued),.stat_committed(p_committed),.stat_squashed(p_squashed),.stat_recoveries(),.stat_ooo());
 initial begin : pressure_test
  repeat(3) @(negedge clk); p_reset=0; @(negedge clk); p_init=1; @(negedge clk); p_init=0;
  for(integer k=0;k<4;k=k+1) begin @(negedge clk); p_valid=1; #1; if(!p_ready) $fatal(1,"unexpected early pressure"); @(posedge clk); #1; end
  @(negedge clk); p_valid=1; #1;
  if(p_ready || p_free!=0 || p_count!=4) $fatal(1,"free list did not independently block issue");
  p_op=3; p_pred=1; #1; if(!p_ready) $fatal(1,"branch should not need a physical destination");
  @(posedge clk); #1; @(negedge clk); p_op=2; p_pred=0; #1;
  while(!p_ready) begin @(negedge clk); #1; end
  @(posedge clk); #1; @(negedge clk); p_valid=0;
  while(!p_idle) begin @(negedge clk); #1; end
  if(p_free!=4 || p_count!=0 || p_value!=1 || p_issued!=6 || p_committed!=6) $fatal(1,"pressure recovery");
  for(integer k=0;k<3;k=k+1) begin @(negedge clk); p_op=(k==0)?3:2; p_valid=1; #1; if(!p_ready) $fatal(1,"pressure branch issue"); @(posedge clk); #1; end
  @(negedge clk); p_valid=0; while(!p_recover) begin @(negedge clk); #1; end
  if(p_recover_id!=7 || p_squashed!=2 || p_free!=4 || p_free_bits!==16'h0f00) $fatal(1,"restricted PRF recovery mask");
  while(!p_idle) begin @(negedge clk); #1; end
  if(p_free!=4 || p_issued!=9 || p_committed!=7 || p_value!=1) $fatal(1,"restricted PRF branch drain");
  p_done=1;
 end
 prf_rename_ooo dut(.clk,.reset,.init_we,.init_reg,.init_data,.issue_valid(valid),.issue_op(op),.issue_dst(dst),.issue_src1(src1),.issue_src2(src2),.issue_pred_taken(pred),.issue_branch_id({5'b0,dst}),.issue_ready(ready),.recover_valid(recover),.recover_taken(taken),.recover_branch_id(recover_id),.idle,.dbg_reg,.dbg_value,.dbg_front(front),.dbg_arch(arch),.dbg_free(free_bits),.free_count,.rob_count(count),.stat_issued(issued),.stat_committed(committed),.stat_squashed(squashed),.stat_recoveries(recoveries),.stat_ooo(ooo));
 always @(posedge clk) if(check_conservation && !reset) begin
  if(int'(free_count)+8+int'(count)!=16) $fatal(1,"free-list conservation free=%0d rob=%0d",free_count,count);
  if(valid && !ready && free_count==0) full_stalls=full_stalls+1;
 end
 task automatic setup(input bit random_values);
  begin
   @(negedge clk); reset=1; valid=0; init_we=0; check_conservation=0; repeat(2) @(negedge clk); reset=0;
   for(integer r=0;r<8;r=r+1) begin
    @(negedge clk); init_we=1; init_reg=3'(r);
    if(random_values) case(r) 0:init_data=3; 1:init_data=5; 2:init_data=7; 3:init_data=11; 4:init_data=13; 5:init_data=17; 6:init_data=19; default:init_data=23; endcase
    else case(r) 0:init_data=2; 1:init_data=1; 2:init_data=3; default:init_data=0; endcase
    @(negedge clk); init_we=0;
   end
  end
 endtask
 task automatic send(input [1:0] operation,input integer d,a,b,input bit predicted);
  begin
   @(negedge clk); valid=1; op=operation; dst=3'(d); src1=3'(a); src2=3'(b); pred=predicted; #1;
   while(!ready) begin @(negedge clk); #1; end
   @(posedge clk); #1;
  end
 endtask
 task automatic stop_sending; begin @(negedge clk); valid=0; end endtask
 task automatic wait_recovery; integer t; begin t=0; while(!recover && t<200) begin @(negedge clk); #1; t=t+1; end if(t==200) $fatal(1,"recovery timeout"); end endtask
 task automatic drain; integer t; begin t=0; while(!idle && t<2000) begin @(negedge clk); #1; t=t+1; end if(t==2000) $fatal(1,"drain timeout"); end endtask
 task automatic expect_reg(input integer r,input [31:0] value); begin dbg_reg=3'(r); #1; if(dbg_value!==value || front!==arch) $fatal(1,"r%0d value=%h expected=%h map=%0d/%0d",r,dbg_value,value,front,arch); end endtask
 reg [31:0] shadow[0:7],seed=32'd1949,a,b; integer kind,d,s1,s2; reg [3:0] expected_map;
 initial begin
  setup(0);
  send(2,0,0,2,0); send(3,0,1,0,0); send(0,0,0,1,0); send(1,2,2,1,0); stop_sending();
  wait_recovery(); dbg_reg=0; #1;
  if(!taken || squashed!=2 || recoveries!=1 || front!=8 || arch!=0 || free_bits!==16'hfe00 || count!=2) $fatal(1,"older uncommitted mapping recovery front=%0d arch=%0d squash=%0d",front,arch,squashed);
  for(integer r=1;r<8;r=r+1) begin dbg_reg=3'(r); #1; if(front!==4'(r) || arch!==4'(r)) $fatal(1,"surviving map %0d",r); end
  drain(); expect_reg(0,6); expect_reg(2,3); if(free_count!=8 || count!=0) $fatal(1,"first recovery leak");
  setup(0);
  send(2,0,0,2,0); send(3,0,0,0,0); send(0,0,0,1,0); send(1,2,2,1,0); stop_sending();
  wait_recovery(); dbg_reg=0; #1; expected_map=arch;
  if(!taken || squashed!=2 || front!=arch || arch!=8 || free_bits!==16'hfe01 || count!=1) $fatal(1,"older committed mapping lost");
  drain(); expect_reg(0,6); expect_reg(2,3); if(free_count!=8 || count!=0) $fatal(1,"second recovery leak");
  setup(0);
  send(3,0,3,0,1); send(0,2,1,1,0); stop_sending(); wait_recovery();
  if(taken || squashed!=1) $fatal(1,"not-taken recovery"); drain(); expect_reg(2,3);
  setup(0);
  send(3,0,1,0,1); send(0,2,1,1,0); stop_sending(); drain(); expect_reg(2,2);
  if(recoveries!=0 || squashed!=0 || free_count!=8) $fatal(1,"correct prediction discarded work");
  // A younger branch may recover first and then itself be squashed by an older branch.
  setup(0);
  send(2,0,0,2,0); send(3,1,0,0,0); send(3,2,1,0,0); send(0,2,1,1,0); stop_sending();
  wait_recovery(); if(recover_id!=2) $fatal(1,"younger branch identifier"); @(negedge clk); #1; while(!recover) begin @(negedge clk); #1; end
  if(recover_id!=1) $fatal(1,"older branch identifier");
  drain(); expect_reg(0,6); expect_reg(2,3);
  if(recoveries!=2 || committed!=2 || free_count!=8) $fatal(1,"nested branch recovery");
  // A held wrong-path request must not be accepted during the recovery notification.
  setup(0);
  send(2,0,0,2,0); send(3,0,1,0,0); send(0,0,0,1,0); send(1,2,2,1,0); send(0,5,1,1,0);
  wait_recovery(); if(ready || squashed!=3) $fatal(1,"issue accepted during recovery notification");
  @(negedge clk); valid=0; drain(); expect_reg(0,6); expect_reg(2,3); expect_reg(5,0);
  if(issued!=5 || committed!=2 || free_count!=8) $fatal(1,"wrong-path request leaked");
  setup(1); for(integer r=0;r<8;r=r+1) begin case(r) 0:shadow[r]=3; 1:shadow[r]=5; 2:shadow[r]=7; 3:shadow[r]=11; 4:shadow[r]=13; 5:shadow[r]=17; 6:shadow[r]=19; default:shadow[r]=23; endcase end
  check_conservation=1;
  for(integer i=0;i<120;i=i+1) begin
   seed=seed*32'd1664525+32'd1013904223; kind=int'(seed[30:16])%6; if(kind==0) kind=2; else if(kind%2==1) kind=0; else kind=1; d=2+(int'(seed[4:2])%6); s1=int'(seed[10:8]); s2=int'(seed[14:12]); a=shadow[s1]; b=shadow[s2];
   case(kind) 0:shadow[d]=a+b; 1:shadow[d]=a-b; default:shadow[d]=a*b; endcase
   send(2'(kind),d,s1,s2,0);
  end
  stop_sending(); drain(); check_conservation=0;
  if(shadow[0]!==32'h00000003 || shadow[1]!==32'h00000005 || shadow[2]!==32'hfcbe7adc || shadow[3]!==32'h7934b0a5 || shadow[4]!==32'h5819034d || shadow[5]!==32'h084b09f0 || shadow[6]!==32'h58190350 || shadow[7]!==32'hf7b4f615) $fatal(1,"reference stream mismatch");
  for(integer r=0;r<8;r=r+1) expect_reg(r,shadow[r]);
  if(free_count!=8 || count!=0 || committed!=120 || ooo==0 || full_stalls==0) $fatal(1,"final conservation or out-of-order execution");
  while(!p_done) @(negedge clk);
  $display("120 instructions, out-of-order completions=%0d, free-list stalls=%0d",ooo,full_stalls); $display("TEST PASSED"); $finish;
 end
 initial begin #200000; $fatal(1,"timeout"); end
endmodule
