`timescale 1ns/1ps
module tb_conv2d_linebuffer;
    logic clk=0, reset=1, in_valid=0;
    logic signed [7:0] pixel=0;
    logic [71:0] kernel=0;
    wire out_valid;
    wire signed [31:0] result;
    integer pf, ef, rc, value, expected, frame, i, outputs;
    integer weights [0:8];
    always #5 clk=~clk;
    conv2d_linebuffer dut(clk,reset,in_valid,pixel,kernel,out_valid,result);
    initial begin
        weights[0]=-2; weights[1]=1; weights[2]=3; weights[3]=0; weights[4]=-1;
        weights[5]=2; weights[6]=1; weights[7]=-3; weights[8]=2;
        for (i=0;i<9;i=i+1) kernel[i*8 +: 8]=weights[i];
        @(negedge clk); reset=0;
        for (frame=0;frame<2;frame=frame+1) begin
            pf=$fopen("../../../../ch07_dsa/conv2d_linebuffer/pixels.txt","r");
            ef=$fopen("../../../../ch07_dsa/conv2d_linebuffer/expected.txt","r");
            if (!pf || !ef) $fatal(1,"TEST FAILED: missing vectors");
            outputs=0;
            for (i=0;i<256;i=i+1) begin
                rc=$fscanf(pf,"%d\n",value); if (rc!=1) $fatal(1,"TEST FAILED: input vector");
                in_valid=1; pixel=value; @(negedge clk);
                if (out_valid !== ((i/16>=2) && (i%16>=2))) $fatal(1,"TEST FAILED: valid at %0d",i);
                if (out_valid) begin
                    rc=$fscanf(ef,"%d\n",expected); if (rc!=1 || result!==expected) $fatal(1,"TEST FAILED: output %0d",outputs);
                    outputs=outputs+1;
                end
                if (i%17==0 && i!=255) begin
                    in_valid=0; @(negedge clk); if (out_valid) $fatal(1,"TEST FAILED: stalled valid");
                end
            end
            if (outputs!=196 || !$feof(ef)) begin
                // EOF only becomes visible after a read attempt in some simulators.
                rc=$fscanf(ef,"%d\n",expected);
                if (outputs!=196 || rc==1) $fatal(1,"TEST FAILED: output count");
            end
            $fclose(pf); $fclose(ef);
        end
        $display("TEST PASSED"); $finish;
    end
endmodule
