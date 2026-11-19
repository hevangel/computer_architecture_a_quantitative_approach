`timescale 1ns/1ps
module tb_west_first_adaptive_spec_vc;
    logic clk=0,reset=1,drive_serial=1;
    logic [15:0] in_valid=0,out_ready='1;
    wire [15:0] in_ready,out_valid,serial_ready,serial_valid;
    logic [63:0] destination=0,link_enable='1;
    logic [255:0] in_id=0;
    wire [255:0] out_id,serial_id;
    wire [31:0] link_hops,alternate_turns,serial_hops,serial_turns;
    west_first_adaptive_spec_vc dut(.*);
    west_first_adaptive_spec_vc #(.SPECULATIVE(0)) serial(
        clk,reset,drive_serial ? in_valid : 16'b0,out_ready,serial_ready,serial_valid,
        destination,link_enable,in_id,serial_id,serial_hops,serial_turns);
    always #5 clk=~clk;
    task tick;
        @(posedge clk); #1;
    endtask
    integer sent [0:15];
    integer cycles,i,tag,got;
    logic [79:0] seen;
    bit was_blocked;
    logic [15:0] blocked_id;
    initial begin
        tick; reset=0;
        in_valid=2; in_id[31:16]=16'h1234;
        tick; in_valid=0;
        if (out_valid!=0 || serial_valid!=0) $fatal(1,"early delivery");
        tick;
        if (out_valid!=1 || out_id[15:0]!=16'h1234 || serial_valid!=0)
            $fatal(1,"speculative hop latency");
        tick;
        if (out_valid!=0 || serial_valid!=1 || serial_id[15:0]!=16'h1234)
            $fatal(1,"serialized hop latency");

        reset=1; tick; reset=0; drive_serial=0;
        link_enable[1]=0; destination='1; // router 0 cannot go east; router 15 is reachable via south.
        got=0; cycles=0; seen=0; was_blocked=0;
        for(i=0;i<16;i=i+1) sent[i]=0;
        while(got<80 && cycles<500) begin
            cycles=cycles+1;
            out_ready[15]=(cycles%4!=0);
            for(i=0;i<16;i=i+1) begin
                in_valid[i]=sent[i]<5;
                in_id[16*i +: 16]=5*i+sent[i];
            end
            #1;
            if (out_valid[14:0]!=0) $fatal(1,"wrong destination");
            if (was_blocked && (!out_valid[15] || out_id[255:240]!==blocked_id))
                $fatal(1,"unstable blocked output");
            for(i=0;i<16;i=i+1) if(in_ready[i] && in_valid[i]) sent[i]=sent[i]+1;
            if (out_valid[15] && out_ready[15]) begin
                tag=out_id[255:240];
                if (tag>=80 || seen[tag]) $fatal(1,"duplicate or invalid packet");
                seen[tag]=1; got=got+1;
            end
            was_blocked=out_valid[15]&&!out_ready[15]; blocked_id=out_id[255:240];
            tick;
        end
        if (got!=80 || !(&seen) || link_hops!=240 || alternate_turns<5)
            $fatal(1,"mesh failed to drain or took nonminimal routes");
        in_valid=0; out_ready='1; tick;
        if (out_valid!=0) $fatal(1,"unexpected residual output");
        $display("80 packets, %0d minimal hops, %0d alternative turns, %0d cycles",link_hops,alternate_turns,cycles);
        $display("TEST PASSED"); $finish;
    end
endmodule
