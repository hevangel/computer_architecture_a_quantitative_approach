`timescale 1ns/1ps
module tb_r4000_superpipeline8;
    logic clk=0,rst_n=0,slot_dependency=0;
    logic [4:0] dbg_raddr=0;
    wire [2:0] halted, we;
    wire [31:0] ia [0:2], cycles [0:2], retired [0:2], load_stalls [0:2], flushes [0:2];
    wire [63:0] da [0:2], wd [0:2], dbg [0:2];
    logic [63:0] mem [0:2][0:1];
    always #5 clk=~clk;
    function automatic [31:0] program_word(input logic [31:0] a,input bit dependent);
        if(dependent) case(a)
            0: program_word=32'hdc010000;
            4: program_word=32'h10000002;
            8: program_word=32'h0021182d;
            12: program_word=32'h64040063;
            16: program_word=32'h0000000d;
            default: program_word=0;
        endcase else
        case(a)
            0: program_word=32'hdc010000;
            4: program_word=32'h0021102d;
            8: program_word=32'h10000002;
            12: program_word=32'h64030001;
            16: program_word=32'h64040063;
            20: program_word=32'hfc020008;
            24: program_word=32'h0000000d;
            default: program_word=0;
        endcase
    endfunction
    for(genvar i=0;i<3;i=i+1) begin : cpu
        wire [31:0] inst=program_word(ia[i],slot_dependency);
        wire [63:0] data_word=mem[i][da[i][3]];
        if(i==0) begin : baseline
            mips_pipeline #(.XLEN(64)) core(clk,rst_n,ia[i],inst,da[i],wd[i],we[i],data_word,
                dbg_raddr,dbg[i],halted[i],cycles[i],retired[i],load_stalls[i],,flushes[i]);
        end else begin : eight_stage
            r4000_superpipeline8 #(.XLEN(64),.DELAY_SLOT(i==2)) core(clk,rst_n,ia[i],inst,da[i],wd[i],we[i],data_word,
                dbg_raddr,dbg[i],halted[i],cycles[i],retired[i],load_stalls[i],,flushes[i]);
        end
        always @(posedge clk) begin
            if(!rst_n) begin mem[i][0]<=64'h100000003; mem[i][1]<=0; end
            else if(we[i]) mem[i][da[i][3]]<=wd[i];
        end
    end
    integer count;
    initial begin
        repeat(2) @(negedge clk); rst_n=1; count=0;
        while(halted!=3'b111 && count<70) begin @(negedge clk); count=count+1; end
        if(halted!=3'b111 || cycles[0]!=11 || cycles[1]!=17 || cycles[2]!=17 ||
           retired[0]!=5 || retired[1]!=5 || retired[2]!=6) $fatal(1,"timing/counter mismatch");
        if(load_stalls[0]!=1 || load_stalls[1]!=2 || load_stalls[2]!=2 ||
           flushes[0]!=1 || flushes[1]!=3 || flushes[2]!=2) $fatal(1,"hazard penalty mismatch");
        for(integer i=0;i<3;i=i+1)
            if(mem[i][0]!=64'h100000003 || mem[i][1]!=64'h200000006) $fatal(1,"memory mismatch");
        for(integer r=0;r<32;r=r+1) begin
            dbg_raddr=r; #1;
            if (dbg[0]!==dbg[1] || (r!=3 && dbg[2]!==dbg[0]) || (r==3 && dbg[2]!==64'd1))
                $fatal(1,"register parity at x%0d",r);
        end
        @(negedge clk); rst_n=0; slot_dependency=1;
        @(negedge clk); rst_n=1; count=0;
        while(halted!=3'b111 && count<70) begin @(negedge clk); count=count+1; end
        dbg_raddr=3; #1;
        if(halted!=3'b111 || dbg[0]!=0 || dbg[1]!=0 || dbg[2]!=64'h200000006 ||
           load_stalls[1]!=0 || load_stalls[2]!=1 || retired[2]!=4)
            $fatal(1,"redirect lost a stalled delay-slot instruction");
        $display("TEST PASSED"); $finish;
    end
endmodule
