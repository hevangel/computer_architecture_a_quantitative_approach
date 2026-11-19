`timescale 1ns/1ps
module tb_moesi_false_sharing;
    logic clk=0, reset=1, valid=0, write=0;
    logic [1:0] core=0;
    logic [3:0] address=0;
    logic [31:0] write_word=0;
    wire [31:0] read_word,memory_writes,peer_dirty_reads,false_misses;
    wire [2:0] miss_kind,requester_state;
    wire [23:0] cache_states;
    moesi_false_sharing dut(.*);
    always #5 clk=~clk;
    task access(input integer c,a, input bit w, input integer data_value, output integer result);
        core=c; address=a; write=w; write_word=data_value; valid=1;
        @(posedge clk); #1;
        result=read_word;
    endtask
    integer value,k;
    initial begin
        @(posedge clk); #1; reset=0;
        access(0,0,1,13,value);
        if (miss_kind!=1 || requester_state!=3) $fatal(1,"initial write");
        access(1,0,0,0,value);
        if (value!=13 || memory_writes!=0 || peer_dirty_reads!=1 || cache_states[2:0]!=4)
            $fatal(1,"owned read");
        access(2,0,0,0,value);
        if (value!=13 || memory_writes!=0 || peer_dirty_reads!=2) $fatal(1,"owned forwarding");
        access(0,4,0,0,value);
        if (memory_writes!=1) $fatal(1,"owner eviction");
        access(3,0,0,0,value);
        if (value!=13) $fatal(1,"backing stale");
        access(0,0,0,0,value);
        if (miss_kind!=3) $fatal(1,"conflict");
        access(0,2,0,0,value);
        access(0,6,0,0,value);
        access(0,0,0,0,value);
        // The direct mapped slot for line 0 survived until an even line displaced it.
        access(0,4,0,0,value);
        access(0,2,0,0,value);
        access(0,0,0,0,value);
        if (miss_kind!=2) $fatal(1,"capacity");
        access(1,0,1,99,value);
        access(2,0,0,0,value);
        if (miss_kind!=4 || value!=99) $fatal(1,"true sharing");

        reset=1; valid=0; @(posedge clk); #1; reset=0;
        for(k=0;k<6;k=k+1) begin
            access(0,0,1,k,value);
            access(1,1,1,k+10,value);
        end
        if (false_misses!=10) $fatal(1,"adjacent writes");
        access(2,0,0,0,value);
        if (value!=5) $fatal(1,"lost neighbor word");
        reset=1; valid=0; @(posedge clk); #1; reset=0;
        for(k=0;k<6;k=k+1) begin
            access(0,0,1,k,value);
            access(1,2,1,k+10,value);
        end
        if (false_misses!=0 || memory_writes!=0) $fatal(1,"padding");
        $display("TEST PASSED"); $finish;
    end
endmodule
