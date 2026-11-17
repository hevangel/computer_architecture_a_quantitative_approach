`timescale 1ns/1ps
module tb_tage_predictor;
 logic clk=0,reset=1,update_valid=0,actual_taken=0; logic [15:0] pc=0;
 wire prediction,gshare_prediction; wire [1:0] provider; wire [17:0] history;
 logic [7:0] expected; logic [15:0] vector_pc; logic [17:0] old_history;
 integer fd,rc,tage_errors=0,gshare_errors=0,long_provider=0;
 always #5 clk=~clk;
 tage_predictor dut(.*);
 initial begin
  fd=$fopen("../../../../ch03_ilp/tage_predictor/golden.txt","r"); if(!fd) $fatal(1,"missing vectors");
  repeat(2) @(negedge clk); reset=0;
  for(integer i=0;i<7024;i=i+1) begin
   rc=$fscanf(fd,"%h %h\n",vector_pc,expected); if(rc!=2) $fatal(1,"short vector file");
   pc=vector_pc; actual_taken=expected[0]; #1;
   if(prediction!==expected[1] || gshare_prediction!==expected[2] || provider!==expected[4:3])
     $fatal(1,"vector %0d pc=%h expected=%h got=%b%b%b",i,pc,expected,provider,gshare_prediction,prediction);
   if(i>=4000 && i<6000) begin tage_errors+=prediction!=actual_taken; gshare_errors+=gshare_prediction!=actual_taken; long_provider+=provider==3; end
   if(i%113==0) begin
    old_history=history; update_valid=0; @(negedge clk); #1;
    if(history!==old_history || prediction!==expected[1] || gshare_prediction!==expected[2] || provider!==expected[4:3]) $fatal(1,"disabled update");
   end
   update_valid=1; @(negedge clk); update_valid=0;
  end
  if(tage_errors!=0 || gshare_errors!=125 || long_provider!=250) $fatal(1,"long-history errors %0d %0d",tage_errors,gshare_errors);
  $fclose(fd); $display("TEST PASSED TAGE=%0d gshare=%0d",tage_errors,gshare_errors); $finish;
 end
 initial begin #150000; $fatal(1,"timeout"); end
endmodule
