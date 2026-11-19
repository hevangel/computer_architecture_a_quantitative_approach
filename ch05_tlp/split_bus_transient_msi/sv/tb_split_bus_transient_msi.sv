`timescale 1ns/1ps
module tb_split_bus_transient_msi;
    logic clk=0,reset=1,allow_data=1;
    logic [1:0] req_valid=0;
    logic [3:0] req_op=0;
    logic [63:0] req_data=0;
    wire [1:0] req_ready,rsp_valid;
    wire [63:0] rsp_data;
    wire [7:0] cache_state;
    wire [31:0] memory_word,upgrade_races;
    split_bus_transient_msi dut(.*);
    always #5 clk=~clk;
    task tick;
        @(posedge clk); #1;
        if (cache_state==8'h22) $fatal(1,"two modified copies");
    endtask
    task wait_response(input integer core, input logic [31:0] data_value, input bit check_data);
        integer waited;
        begin
            waited=0;
            while (!rsp_valid[core] && waited<24) begin tick; waited=waited+1; end
            if (!rsp_valid[core] || (check_data && rsp_data[32*core +: 32]!==data_value))
                $fatal(1,"response mismatch core %0d",core);
        end
    endtask
    initial begin
        tick; reset=0;
        // Install two shared copies and return the arbitration pointer to core 0.
        req_valid=1; tick; req_valid=0; wait_response(0,0,1);
        req_valid=2; tick; req_valid=0; wait_response(1,0,1);
        if (cache_state!=8'h11) $fatal(1,"failed to share");

        req_valid=3; req_op=4'b0101; req_data={32'd9,32'd7}; allow_data=0; tick;
        req_valid=0;
        if (cache_state!=8'h55) $fatal(1,"two SM_AD requests required");
        tick;
        if (cache_state!=8'h34 || upgrade_races!=1) $fatal(1,"loser must fall back to IM_AD");
        repeat(5) begin
            tick;
            if (rsp_valid!=0 || cache_state!=8'h34) $fatal(1,"response did not wait");
        end
        allow_data=1; wait_response(0,7,1);
        if (cache_state!=8'h32) $fatal(1,"first writer missing");
        wait_response(1,9,1);
        if (cache_state!=8'h20 || memory_word!=7) $fatal(1,"ordered retry or writeback failed");

        req_op=0; req_valid=1; tick; req_valid=0; wait_response(0,9,1);
        if (cache_state!=8'h11 || memory_word!=9) $fatal(1,"stale read");
        req_op=1; req_data=32'd14; req_valid=1; tick; req_valid=0; wait_response(0,14,1);
        req_op=2; req_valid=1; tick; req_valid=0;
        if (cache_state!=8'h06) $fatal(1,"missing MI_A on eviction");
        wait_response(0,0,0);
        if (cache_state!=0 || memory_word!=14) $fatal(1,"dirty eviction failed");
        $display("TEST PASSED"); $finish;
    end
    initial begin #2000; $fatal(1,"timeout"); end
endmodule
