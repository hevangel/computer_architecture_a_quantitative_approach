`timescale 1ns/1ps
module tb_consistency_litmus_tsosb;
    logic clk=0, reset=1, tso=0, valid=0, core=0, address=0;
    logic [1:0] op=0;
    logic [31:0] data=0;
    wire accepted, read_valid;
    wire [31:0] read_data, x, y;
    wire [1:0] pending0, pending1;
    integer mode, fenced, mask, steps, bit_count, j, c, pos0, pos1, r0, r1, cases;
    integer result;
    always #5 clk=~clk;
    consistency_litmus_tsosb dut(clk,reset,tso,valid,core,op,address,data,accepted,read_valid,read_data,x,y,pending0,pending1);
    task automatic init(input logic mode_tso);
        begin reset=1; tso=mode_tso; valid=0; @(negedge clk); reset=0; end
    endtask
    task automatic command(input logic which, input logic [1:0] opcode, input logic addr,
                           input logic [31:0] value, output integer read_result);
        integer attempts;
        begin
            core=which; op=opcode; address=addr; data=value; valid=1; attempts=0;
            @(negedge clk); attempts=attempts+1;
            while (!accepted && attempts<5) begin @(negedge clk); attempts=attempts+1; end
            if (!accepted) $fatal(1,"TEST FAILED: stalled command");
            if (opcode==1 && !read_valid) $fatal(1,"TEST FAILED: load response");
            read_result=read_data; valid=0;
        end
    endtask
    initial begin
        @(negedge clk); cases=0;
        for (mode=0;mode<2;mode=mode+1) begin
            for (fenced=0;fenced<2;fenced=fenced+1) begin
                steps=fenced ? 3 : 2;
                for (mask=0;mask<(1<<(steps*2));mask=mask+1) begin
                    bit_count=0; for (j=0;j<steps*2;j=j+1) bit_count=bit_count+((mask>>j)&1);
                    if (bit_count==steps) begin
                        init(mode); pos0=0; pos1=0; r0=-1; r1=-1;
                        for (j=0;j<steps*2;j=j+1) begin
                            c=(mask>>j)&1;
                            if (c==0) begin
                                if (pos0==0) command(0,0,0,1,result);
                                else if (fenced && pos0==1) command(0,3,0,0,result);
                                else begin command(0,1,1,0,result); r0=result; end
                                pos0=pos0+1;
                            end else begin
                                if (pos1==0) command(1,0,1,1,result);
                                else if (fenced && pos1==1) command(1,3,0,0,result);
                                else begin command(1,1,0,0,result); r1=result; end
                                pos1=pos1+1;
                            end
                        end
                        if (r0<0 || r1<0) $fatal(1,"TEST FAILED: missing read");
                        if ((!mode || fenced) && r0==0 && r1==0) $fatal(1,"TEST FAILED: forbidden SB outcome");
                        if (mode && !fenced && (r0!=0 || r1!=0)) $fatal(1,"TEST FAILED: TSO buffered SB");
                        cases=cases+1;
                    end
                end
            end
        end
        if (cases!=52) $fatal(1,"TEST FAILED: schedule count");
        // Same-address forwarding chooses the youngest pending store; a full
        // buffer rejects a third store, and explicit drains preserve FIFO order.
        init(1); command(0,0,0,11,result); command(0,0,0,22,result);
        command(0,1,0,0,result); if (result!=22 || x!=0) $fatal(1,"TEST FAILED: forwarding");
        core=0; op=0; address=1; data=33; valid=1; @(negedge clk); valid=0;
        if (accepted || pending0!=2) $fatal(1,"TEST FAILED: full buffer");
        command(0,2,0,0,result); if (x!=11 || pending0!=1) $fatal(1,"TEST FAILED: first drain");
        command(0,2,0,0,result); if (x!=22 || pending0!=0) $fatal(1,"TEST FAILED: second drain");
        // Message passing: FIFO drain prevents flag visibility before data.
        init(1); command(0,0,0,42,result); command(0,0,1,1,result);
        command(0,2,0,0,result); command(1,1,1,0,result); if (result!=0) $fatal(1,"TEST FAILED: early flag");
        command(0,2,0,0,result); command(1,1,1,0,result); if (result!=1) $fatal(1,"TEST FAILED: flag");
        command(1,1,0,0,result); if (result!=42) $fatal(1,"TEST FAILED: data after flag");
        $display("TEST PASSED"); $finish;
    end
endmodule
