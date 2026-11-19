`timescale 1ns/1ps
module tb_smt_multithread_core;
    logic clk=0, reset=1, prog_we=0, prog_thread=0, mem_we=0, start=0, read_thread=0;
    logic [1:0] prog_op=0;
    logic [2:0] prog_dst=0, prog_src=0, read_reg=0;
    logic [31:0] prog_arg=0, mem_data=0;
    logic [7:0] mem_addr=0;
    wire [31:0] read_value [0:4];
    wire prog_ready [0:4];
    wire done [0:4];
    wire [31:0] cycles [0:4], issued [0:4], switches [0:4];
    integer i, t, k, j, timeout, op_rand, src_rand, dst_rand, arg_rand;
    logic [31:0] random_state;
    logic [31:0] golden [0:1][0:7];
    genvar m;
    generate for (m=0;m<5;m=m+1) begin: modes
        smt_multithread_core #(.MODE(m==4 ? 3 : m), .NPHYS(m==4 ? 9 : 20)) dut (
            .clk(clk), .reset(reset), .prog_we(prog_we), .prog_thread(prog_thread),
            .prog_op(prog_op), .prog_dst(prog_dst), .prog_src(prog_src), .prog_arg(prog_arg),
            .mem_we(mem_we), .mem_addr(mem_addr), .mem_data(mem_data), .start(start),
            .read_thread(read_thread), .read_reg(read_reg), .read_value(read_value[m]),
            .prog_ready(prog_ready[m]), .done(done[m]), .cycles(cycles[m]), .issued(issued[m]), .switches(switches[m]));
    end endgenerate
    always #5 clk=~clk;
    task add_instruction(input integer thread_id, input integer op, input integer dst, input integer src, input integer arg);
        begin
            @(negedge clk);
            prog_we=1; prog_thread=thread_id; prog_op=op; prog_dst=dst; prog_src=src; prog_arg=arg;
        end
    endtask
    initial begin
        repeat (2) @(negedge clk); reset=0;
        mem_we=1; mem_addr=0; mem_data=11;
        @(negedge clk); mem_addr=1; mem_data=17;
        @(negedge clk); mem_we=0;
        for (t=0;t<2;t=t+1) begin
            add_instruction(t,0,6,6,1);
            for (k=0;k<5;k=k+1) begin
                add_instruction(t,2,1,0,(k+t)%2);
                for (j=0;j<4;j=j+1) add_instruction(t,0,2+j,2+j,1);
                add_instruction(t,0,7,1,1);
                add_instruction(t,1,6,6,2);
            end
        end
        @(negedge clk); prog_we=0; start=1;
        @(negedge clk); start=0;
        timeout=0;
        while (!(done[0] && done[1] && done[2] && done[3] && done[4]) && timeout<200) begin
            @(negedge clk); timeout=timeout+1;
        end
        if (timeout>=200) $fatal(1,"timeout");
        $display("cycles %0d %0d %0d %0d",cycles[0],cycles[1],cycles[2],cycles[3]);
        if (cycles[0]!=87 || cycles[1]!=57 || cycles[2]!=54 || cycles[3]!=48 || cycles[4]!=83) $fatal(1,"cycle mismatch");
        for (i=0;i<5;i=i+1) if (issued[i]!=72) $fatal(1,"issue count");
        for (t=0;t<2;t=t+1) begin
            read_thread=t;
            for (j=0;j<8;j=j+1) begin
                read_reg=j; @(posedge clk); #1;
                for (i=0;i<5;i=i+1) begin
                    case(j)
                        0: if (read_value[i]!==0) $fatal(1,"r0");
                        1: if (read_value[i]!== (t==0 ? 11 : 17)) $fatal(1,"r1");
                        2,3,4,5: if (read_value[i]!==5) $fatal(1,"r2-r5");
                        6: if (read_value[i]!==32) $fatal(1,"r6");
                        7: if (read_value[i]!== (t==0 ? 12 : 18)) $fatal(1,"r7");
                    endcase
                end
            end
        end
        // Fill only thread 0's program memory. A rejected extra write must
        // not wrap, and thread 1 remains independently writable.
        @(negedge clk); reset=1;
        repeat (2) @(negedge clk); reset=0;
        for (j=0;j<64;j=j+1) add_instruction(0,0,1,1,1);
        @(negedge clk); prog_we=1; prog_thread=0; prog_arg=100; #1;
        for (i=0;i<5;i=i+1) if (prog_ready[i]!==0) $fatal(1,"full queue accepted write");
        @(negedge clk); prog_thread=1; prog_arg=7; #1;
        for (i=0;i<5;i=i+1) if (prog_ready[i]!==1) $fatal(1,"other queue unavailable");
        @(negedge clk); prog_we=0; start=1;
        @(negedge clk); start=0; #1;
        for (i=0;i<5;i=i+1) if (prog_ready[i]!==0) $fatal(1,"write enabled during execution");
        timeout=0;
        while (!(done[0] && done[1] && done[2] && done[3] && done[4]) && timeout<300) begin
            @(negedge clk); timeout=timeout+1;
        end
        if (timeout>=300) $fatal(1,"pressure timeout");
        for (i=0;i<5;i=i+1) if (issued[i]!=65) $fatal(1,"pressure issue count");
        read_thread=0; read_reg=1; @(posedge clk); #1;
        for (i=0;i<5;i=i+1) if (read_value[i]!==64) $fatal(1,"pressure thread 0");
        read_thread=1; @(posedge clk); #1;
        for (i=0;i<5;i=i+1) if (read_value[i]!==7) $fatal(1,"pressure thread 1");
        // Both threads request a load at once. A younger ADD overwrites a
        // multiply destination before the older multiply completes.
        @(negedge clk); reset=1;
        repeat (2) @(negedge clk); reset=0;
        mem_we=1; mem_addr=0; mem_data=11;
        @(negedge clk); mem_addr=1; mem_data=17;
        @(negedge clk); mem_we=0;
        add_instruction(0,2,1,0,0); add_instruction(0,1,2,1,3);
        add_instruction(0,0,2,0,5); add_instruction(0,0,3,2,1);
        add_instruction(1,2,1,0,1); add_instruction(1,0,2,1,3);
        @(negedge clk); prog_we=0; start=1;
        @(negedge clk); start=0;
        @(negedge clk);
        if (issued[3]!=1 || issued[4]!=1) $fatal(1,"two simultaneous loads started");
        timeout=0;
        while (!(done[0] && done[1] && done[2] && done[3] && done[4]) && timeout<100) begin
            @(negedge clk); timeout=timeout+1;
        end
        if (timeout>=100) $fatal(1,"dependency timeout");
        if (cycles[0]!=21 || cycles[1]!=14 || cycles[2]!=14 || cycles[3]!=13 || cycles[4]!=14)
            $fatal(1,"dependency timing");
        read_thread=0; read_reg=2; @(posedge clk); #1;
        for (i=0;i<5;i=i+1) if (read_value[i]!==5) $fatal(1,"WAW retirement");
        read_reg=3; @(posedge clk); #1;
        for (i=0;i<5;i=i+1) if (read_value[i]!==6) $fatal(1,"renamed source");
        read_thread=1; read_reg=2; @(posedge clk); #1;
        for (i=0;i<5;i=i+1) if (read_value[i]!==20) $fatal(1,"load dependency");
        // Deterministic arithmetic streams checked by a separate sequential interpreter.
        @(negedge clk); reset=1;
        repeat (2) @(negedge clk); reset=0;
        random_state=32'h12345678;
        for (t=0;t<2;t=t+1) for (j=0;j<8;j=j+1) golden[t][j]=0;
        for (t=0;t<2;t=t+1) begin
            for (k=0;k<64;k=k+1) begin
                random_state=random_state*32'd1664525+32'd1013904223;
                src_rand=(random_state>>8)&7; dst_rand=(random_state>>12)&7;
                arg_rand=((random_state>>16)&3)+1; op_rand=(random_state>>20)&1;
                if (op_rand==0) golden[t][dst_rand]=golden[t][src_rand]+arg_rand;
                else golden[t][dst_rand]=golden[t][src_rand]*arg_rand;
                add_instruction(t,op_rand,dst_rand,src_rand,arg_rand);
            end
        end
        @(negedge clk); prog_we=0; start=1;
        @(negedge clk); start=0;
        timeout=0;
        while (!(done[0] && done[1] && done[2] && done[3] && done[4]) && timeout<1000) begin
            @(negedge clk); timeout=timeout+1;
        end
        if (timeout>=1000) $fatal(1,"random timeout");
        for (i=0;i<5;i=i+1) if (issued[i]!=128) $fatal(1,"random issue count");
        for (t=0;t<2;t=t+1) begin
            read_thread=t;
            for (j=0;j<8;j=j+1) begin
                read_reg=j; @(posedge clk); #1;
                for (i=0;i<5;i=i+1) if (read_value[i]!==golden[t][j])
                    $fatal(1,"random register t=%0d r=%0d mode=%0d",t,j,i);
            end
        end
        $display("TEST PASSED"); $finish;
    end
endmodule
