`timescale 1ns/1ps
module tb_tournament_btb_ras;
    logic clk=0, reset=1, update=0, taken=0;
    logic [1:0] kind=0;
    logic [31:0] pc=0, target=0, random_state;
    wire local_p, global_p, tournament_p, btb_hit, ras_valid;
    wire [31:0] btb_target, ras_target;
    integer k, idx, phase, local_correct, global_correct, tournament_correct;
    always #5 clk=~clk;
    tournament_btb_ras dut(clk,reset,pc,update,kind,taken,target,local_p,global_p,tournament_p,
                           btb_hit,btb_target,ras_valid,ras_target);
    task automatic clear_state;
        begin reset=1; update=0; @(negedge clk); reset=0; end
    endtask
    task automatic control(input [1:0] op, input [31:0] address, input [31:0] destination);
        begin pc=address; kind=op; target=destination; update=1; @(negedge clk); update=0; #1; end
    endtask
    initial begin
        @(negedge clk); clear_state();
        local_correct=0; global_correct=0; tournament_correct=0; kind=0; update=1;
        for (k=0;k<2048;k=k+1) begin
            idx=k%4; phase=(k/4)%4; pc=idx*4;
            if ((idx%2)==0) taken=(phase==0 || phase==1); else taken=(phase==0 || phase==3);
            #1;
            if (k>=128) begin
                if (local_p==taken) local_correct=local_correct+1;
                if (global_p==taken) global_correct=global_correct+1;
                if (tournament_p==taken) tournament_correct=tournament_correct+1;
            end
            @(negedge clk);
        end
        update=0;
        if (local_correct!=1920 || global_correct!=1440 || tournament_correct!=1920)
            $fatal(1,"TEST FAILED: periodic trace %0d %0d %0d",local_correct,global_correct,tournament_correct);
        clear_state();
        local_correct=0; global_correct=0; tournament_correct=0; random_state=32'h12345678; kind=0; update=1;
        for (k=0;k<4096;k=k+1) begin
            pc=(k%2)*4;
            if ((k%2)==0) begin random_state=random_state*32'd1664525+32'd1013904223; taken=random_state[31]; end
            #1;
            if (k>=256) begin
                if (local_p==taken) local_correct=local_correct+1;
                if (global_p==taken) global_correct=global_correct+1;
                if (tournament_p==taken) tournament_correct=tournament_correct+1;
            end
            @(negedge clk);
        end
        update=0;
        if (local_correct!=1994 || global_correct!=2724 || tournament_correct!=2736)
            $fatal(1,"TEST FAILED: correlated trace %0d %0d %0d",local_correct,global_correct,tournament_correct);
        clear_state();
        for (k=0;k<4;k=k+1) control(1,32'h1000+k*4,32'h2000+k*4);
        pc=32'h100c; #1;
        if (!btb_hit || btb_target!==32'h200c) $fatal(1,"TEST FAILED: BTB hit");
        pc=32'h101c; #1;
        if (btb_hit) $fatal(1,"TEST FAILED: BTB tag collision");
        taken=1; control(0,32'h101c,32'h3030);
        if (!btb_hit || btb_target!==32'h3030) $fatal(1,"TEST FAILED: BTB replacement");
        pc=32'h100c; #1;
        if (btb_hit) $fatal(1,"TEST FAILED: old BTB entry");
        for (k=3;k>=0;k=k-1) begin
            if (!ras_valid || ras_target!==(32'h1000+k*4+4)) $fatal(1,"TEST FAILED: return stack %0d",k);
            control(2,0,0);
        end
        if (ras_valid) $fatal(1,"TEST FAILED: return stack empty");
        control(2,0,0);
        if (ras_valid) $fatal(1,"TEST FAILED: return stack underflow");
        for (k=0;k<5;k=k+1) control(1,32'h3000+k*4,0);
        for (k=4;k>=1;k=k-1) begin
            if (!ras_valid || ras_target!==(32'h3000+k*4+4)) $fatal(1,"TEST FAILED: overflow policy");
            control(2,0,0);
        end
        if (ras_valid) $fatal(1,"TEST FAILED: overflow depth");
        $display("TEST PASSED"); $finish;
    end
endmodule
