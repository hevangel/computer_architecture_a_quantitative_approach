`timescale 1ns/1ps
module tb_alloy_dram_cache;
    logic clk=0, reset=1, valid=0;
    logic [31:0] address=0;
    logic [1:0] pc=0;
    wire rb,rp,vb,vp,hb,hp,pb,pp;
    wire [31:0] db,dp,lb,lp,hits_b,misses_b,ch_b,cm_b,fh_b,fm_b,reads_b;
    wire [31:0] hits_p,misses_p,ch_p,cm_p,fh_p,fm_p,reads_p;
    integer i,scenario,elapsed,total_b,total_p;
    logic seen_b,seen_p;
    always #5 clk=~clk;
    alloy_dram_cache #(.PREDICT_ENABLE(0)) baseline(clk,reset,valid,address,pc,rb,vb,hb,pb,db,lb,hits_b,misses_b,ch_b,cm_b,fh_b,fm_b,reads_b);
    alloy_dram_cache #(.PREDICT_ENABLE(1)) predicted(clk,reset,valid,address,pc,rp,vp,hp,pp,dp,lp,hits_p,misses_p,ch_p,cm_p,fh_p,fm_p,reads_p);
    initial begin
        @(negedge clk);
        for (scenario=0;scenario<2;scenario=scenario+1) begin
            reset=1; valid=0; @(negedge clk); reset=0; total_b=0; total_p=0;
            for (i=0;i<20;i=i+1) begin
                if (scenario==0) begin
                    if (i==0) begin address=0; pc=1; end
                    else if (i==1) begin address=0; pc=0; end
                    else if (i==2) begin address=0; pc=2; end
                    else if (i==19) begin address=4; pc=0; end
                    else begin address=0; pc=0; end
                end else begin
                    if (i<3) begin address=i; pc=1; end
                    else if (i==19) begin address=6; pc=0; end
                    else begin address=2; pc=0; end
                end
                if (!rb || !rp) $fatal(1,"TEST FAILED: not ready");
                valid=1; @(negedge clk); valid=0; elapsed=0; seen_b=0; seen_p=0;
                while ((!seen_b || !seen_p) && elapsed<160) begin
                    @(negedge clk); elapsed=elapsed+1;
                    if (vb) begin
                        seen_b=1; total_b=total_b+elapsed;
                        if (elapsed!=lb || db!==(address^32'hc39a57e1)) $fatal(1,"TEST FAILED: baseline response");
                    end
                    if (vp) begin
                        seen_p=1; total_p=total_p+elapsed;
                        if (elapsed!=lp || dp!==(address^32'hc39a57e1) || hp!==hb || pp!==pb)
                            $fatal(1,"TEST FAILED: predicted response");
                    end
                end
                if (!seen_b || !seen_p) $fatal(1,"TEST FAILED: timeout");
            end
            if (scenario==0) begin
                if (hits_p!=18 || misses_p!=2 || ch_p!=16 || cm_p!=1 || fh_p!=1 || fm_p!=2 ||
                    reads_b!=2 || reads_p!=4 || total_b!=872 || total_p!=843)
                    $fatal(1,"TEST FAILED: textbook-profile accounting");
            end else begin
                if (hits_p!=16 || misses_p!=4 || ch_p!=15 || cm_p!=3 || fh_p!=1 || fm_p!=1 ||
                    reads_b!=4 || reads_p!=5 || total_b!=1064 || total_p!=977)
                    $fatal(1,"TEST FAILED: 80/15/5 accounting");
            end
        end
        $display("TEST PASSED"); $finish;
    end
endmodule
