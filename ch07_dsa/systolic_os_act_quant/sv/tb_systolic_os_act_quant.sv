`timescale 1ns/1ps
module tb_systolic_os_act_quant;
    logic clk=0, reset=1, start=0;
    logic [127:0] a=0,b=0;
    logic [511:0] bias=0;
    logic [1:0] activation=0;
    logic [4:0] shift=0;
    wire busy, done;
    wire [511:0] accumulators;
    wire [127:0] quantized;
    integer fd, rc, case_id, mode, sh, i, cycle, av,bv,bias_v,acc_v,q_v;
    integer expected_acc [0:15], expected_q [0:15];
    always #5 clk=~clk;
    systolic_os_act_quant dut(clk,reset,start,a,b,bias,activation,shift,busy,done,accumulators,quantized);
    initial begin
        fd=$fopen("../../../../ch07_dsa/systolic_os_act_quant/golden.txt","r");
        if (!fd) $fatal(1,"TEST FAILED: missing vectors");
        @(negedge clk); reset=0;
        for (case_id=0;case_id<3;case_id=case_id+1) begin
            rc=$fscanf(fd,"%d %d\n",mode,sh); if (rc!=2) $fatal(1,"TEST FAILED: header");
            activation=mode; shift=sh;
            for (i=0;i<16;i=i+1) begin
                rc=$fscanf(fd,"%d %d %d %d %d\n",av,bv,bias_v,acc_v,q_v);
                if (rc!=5) $fatal(1,"TEST FAILED: vector");
                a[i*8 +: 8]=av; b[i*8 +: 8]=bv; bias[i*32 +: 32]=bias_v;
                expected_acc[i]=acc_v; expected_q[i]=q_v;
            end
            start=1; @(negedge clk); start=0;
            if (!busy || done) $fatal(1,"TEST FAILED: start");
            // Inputs may change after acceptance; the engine must use latched values.
            a=0; b=0; bias=0; activation=0; shift=0;
            for (cycle=0;cycle<10;cycle=cycle+1) begin
                @(negedge clk);
                if (cycle<9 && (!busy || done)) $fatal(1,"TEST FAILED: early completion");
            end
            if (busy || !done) $fatal(1,"TEST FAILED: completion latency");
            for (i=0;i<16;i=i+1)
                if (accumulators[i*32 +: 32]!==expected_acc[i] || quantized[i*8 +: 8]!==expected_q[i][7:0])
                    $fatal(1,"TEST FAILED: case %0d lane %0d",case_id,i);
        end
        $fclose(fd); $display("TEST PASSED"); $finish;
    end
endmodule
