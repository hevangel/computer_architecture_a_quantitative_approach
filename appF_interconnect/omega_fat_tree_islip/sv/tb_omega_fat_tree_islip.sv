`timescale 1ns/1ps
module tb_omega_fat_tree_islip;
    logic clk=0,reset=1,advance=0;
    logic [7:0] in_valid=0,in_tail=0,out_ready=0;
    logic [23:0] in_dest=0;
    logic [127:0] in_data=0;
    wire [7:0] in_ready,out_valid,out_tail;
    wire [127:0] out_data;
    logic [63:0] requests=0;
    wire [63:0] iterative, baseline;
    omega8 dut(.*);
    islip8 round4(clk,reset,advance,requests,iterative);
    islip8 #(.ITERATIONS(1)) round1(clk,reset,advance,requests,baseline);
    always #5 clk=~clk;
    task tick;
        @(posedge clk); #1;
    endtask

    function automatic integer destination(input integer src,input bit blocking);
        if (blocking) destination=((src&1)<<2)|(src&2)|((src&4)>>2);
        else destination=((src&1)<<2)|((src&4)>>1)|((src&2)>>1);
    endfunction

    task traffic(input bit blocking, output integer cycles);
        integer sent [0:7], received [0:7];
        integer i, tag, src, word_id, total;
        logic [7:0] accepted, was_stalled;
        logic [127:0] stalled_data;
        begin
            reset=1; in_valid=0; out_ready=0; tick; reset=0;
            for (i=0;i<8;i=i+1) begin sent[i]=0; received[i]=0; end
            total=0; cycles=0; was_stalled=0; stalled_data=0;
            while (total<24 && cycles<200) begin
                cycles=cycles+1;
                out_ready=(cycles%7==0) ? 8'h55 : 8'hff;
                in_valid=0; in_tail=0;
                for(i=0;i<8;i=i+1) begin
                    if (sent[i]<3) begin
                        in_valid[i]=1;
                        in_tail[i]=sent[i]==2;
                        in_dest[3*i +: 3]=destination(i,blocking);
                        in_data[16*i +: 16]=16*(i+1)+sent[i];
                    end
                end
                #1;
                accepted=in_valid & in_ready;
                for(i=0;i<8;i=i+1) begin
                    if (was_stalled[i] && (!out_valid[i] || out_data[16*i +: 16]!=stalled_data[16*i +: 16]))
                        $fatal(1,"unstable stalled packet");
                    if (accepted[i]) sent[i]=sent[i]+1;
                    if (out_valid[i] && out_ready[i]) begin
                        tag=out_data[16*i +: 16]; src=tag/16-1; word_id=tag%16;
                        if (src<0 || src>=8 || destination(src,blocking)!=i ||
                            received[src]!=word_id || word_id>=3 || out_tail[i]!=(word_id==2))
                            $fatal(1,"loss, misroute, or broken wormhole ordering");
                        received[src]=received[src]+1; total=total+1;
                    end
                end
                was_stalled=out_valid & ~out_ready; stalled_data=out_data;
                tick;
            end
            if (total!=24) $fatal(1,"drain timeout");
            in_valid=0; tick;
            if (out_valid!=0) $fatal(1,"unexpected output after drain");
        end
    endtask

    integer free_cycles, blocked_cycles, accepted_one, accepted_four, sample;
    initial begin
        traffic(0,free_cycles);
        traffic(1,blocked_cycles);
        if (blocked_cycles<=free_cycles) $fatal(1,"blocking was not observed");
        $display("24 flits: nonblocking=%0d cycles, transpose=%0d cycles",free_cycles,blocked_cycles);

        reset=1; tick; reset=0;
        requests=64'h0000000000000203;
        #1;
        if (baseline!=64'h1 || iterative!=64'h0201) $fatal(1,"additional iSLIP iteration did not fill idle port");
        advance=1; tick;
        if (baseline!=64'h2 || iterative!=baseline) $fatal(1,"first iteration pointers incorrect");
        requests=64'h0000000000000202; #1;
        if (baseline!=64'h2 || iterative!=baseline) $fatal(1,"later-round pointer update must be deferred");
        tick;
        if (baseline!=64'h0200 || iterative!=baseline) $fatal(1,"grant pointer fairness");
        reset=1; advance=0; tick; reset=0;
        accepted_one=0; accepted_four=0;
        for (sample=0;sample<32;sample=sample+1) begin
            case (sample%4)
                0: requests=64'h0000000000000203;
                1: requests=64'h0303020203030202;
                2: requests=64'h030f030f030f030f;
                3: requests=64'h0703030105030107;
            endcase
            #1;
            if ((iterative & ~requests)!=0 || (baseline & ~requests)!=0) $fatal(1,"unsolicited match");
            accepted_one=accepted_one+$countones(baseline);
            accepted_four=accepted_four+$countones(iterative);
            advance=1; tick;
        end
        if (accepted_one!=76 || accepted_four!=86) $fatal(1,"crossbar utilization");
        $display("32 crossbar samples: one round=%0d, four rounds=%0d",accepted_one,accepted_four);
        $display("TEST PASSED"); $finish;
    end
    initial begin #10000; $fatal(1,"timeout"); end
endmodule
