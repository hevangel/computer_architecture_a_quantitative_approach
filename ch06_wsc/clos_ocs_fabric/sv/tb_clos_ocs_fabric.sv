`timescale 1ns/1ps
module tb_clos_ocs_fabric;
    logic clk=0, reset=1, cfg_valid=0;
    logic [31:0] in_valid=0;
    wire [31:0] in_ready, out_valid;
    logic [95:0] in_destination=0;
    logic [511:0] in_id=0;
    wire [511:0] out_id;
    logic [7:0] out_ready=0;
    logic [3:0] cfg_cross=0;
    wire [3:0] active_cross;
    wire cfg_ready;
    clos_ocs_fabric dut(.*);
    always #5 clk=~clk;

    task tick;
        @(posedge clk); #1;
    endtask

    task traffic(input bit adaptive, input bit spread, output integer elapsed);
        integer sends [0:31];
        integer lane_count, quota, total, got, i, id, dest, cycle;
        logic [127:0] seen;
        logic [31:0] accepted;
        begin
            reset=1; in_valid=0; out_ready=0; tick; reset=0;
            cfg_valid=adaptive; cfg_cross=1; tick; cfg_valid=0;
            if (active_cross!=(adaptive ? 1 : 0)) $fatal(1,"initial mapping");
            lane_count=spread ? 32 : 4;
            quota=128/lane_count;
            total=lane_count*quota;
            got=0; seen=0; elapsed=0;
            for (i=0;i<32;i=i+1) sends[i]=0;
            while (got<total && elapsed<300) begin
                elapsed=elapsed+1;
                out_ready=8'hff;
                if (spread && elapsed%5==0) out_ready=8'h55;
                in_valid=0;
                for (i=0;i<lane_count;i=i+1) begin
                    if (sends[i]<quota) begin
                        in_valid[i]=1;
                        in_id[16*i +: 16]=i*quota+sends[i];
                        in_destination[3*i +: 3]=spread ? (i/4+1)%8 : 3;
                    end
                end
                #1;
                accepted=in_ready & in_valid;
                for (i=0;i<32;i=i+1) begin
                    if (accepted[i]) sends[i]=sends[i]+1;
                    if (out_valid[i] && out_ready[i/4]) begin
                        id=int'(out_id[16*i +: 16]);
                        dest=spread ? (id/quota/4+1)%8 : 3;
                        if (id>=total || seen[id] || i/4!=dest) $fatal(1,"bad id or route: %0d",id);
                        seen[id]=1; got=got+1;
                    end
                end
                tick;
            end
            if (got!=total || !(&seen)) $fatal(1,"loss or timeout");
            in_valid=0; tick;
            if (out_valid!=0) $fatal(1,"unexpected residual egress");
        end
    endtask

    integer static_cycles, adapted_cycles, uniform_cycles;
    initial begin
        traffic(0,0,static_cycles);
        traffic(1,0,adapted_cycles);
        traffic(0,1,uniform_cycles);
        if (2*static_cycles<3*adapted_cycles) $fatal(1,"hot-pair throughput threshold");
        $display("128 packets: fixed=%0d cycles adapted=%0d uniform=%0d",static_cycles,adapted_cycles,uniform_cycles);

        reset=1; out_ready=0; tick; reset=0;
        in_valid=1; in_destination[2:0]=3; in_id[15:0]=16'h1234; tick;
        in_valid=0; tick;
        if (!out_valid[12] || out_id[192 +: 16]!=16'h1234) $fatal(1,"in-flight setup");
        cfg_valid=1; cfg_cross=1; tick; cfg_valid=0;
        repeat(3) begin
            if (cfg_ready || active_cross!=0 || !out_valid[12] || out_id[192 +: 16]!=16'h1234)
                $fatal(1,"configuration changed under a blocked packet");
            tick;
        end
        out_ready=8'hff; tick;
        if (!cfg_ready || active_cross!=1 || out_valid!=0) $fatal(1,"configuration did not commit on drain");
        $display("TEST PASSED"); $finish;
    end
    initial begin #10000; $fatal(1,"timeout"); end
endmodule
