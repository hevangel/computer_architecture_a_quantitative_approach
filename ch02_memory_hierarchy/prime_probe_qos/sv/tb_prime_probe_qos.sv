`timescale 1ns/1ps
module tb_prime_probe_qos;
    logic clk=0, reset=1, partition=0, valid=0, domain=0;
    logic [31:0] addr=0;
    wire ready, response, hit;
    wire [31:0] latency, hits, misses;
    integer i, elapsed;
    always #5 clk=~clk;
    prime_probe_qos dut(clk,reset,partition,valid,domain,addr,ready,response,hit,latency,hits,misses);
    task automatic begin_scenario(input logic use_partition);
        begin reset=1; valid=0; partition=use_partition; @(negedge clk); reset=0; end
    endtask
    task automatic access_line(input logic who, input logic [31:0] line, input logic expected_hit);
        begin
            if (!ready) $fatal(1,"TEST FAILED: not ready");
            valid=1; domain=who; addr=line; @(negedge clk); valid=0;
            elapsed=0;
            while (!response && elapsed<10) begin @(negedge clk); elapsed=elapsed+1; end
            if (!response || hit!==expected_hit || latency!==(expected_hit ? 32'd1 : 32'd5) || elapsed!==latency)
                $fatal(1,"TEST FAILED: hit or latency for %d",line);
        end
    endtask
    initial begin
        @(negedge clk);
        begin_scenario(0);
        for (i=0;i<4;i=i+1) access_line(1,i,0);
        access_line(1,0,1); // secret 0: no victim access
        if (hits!==1 || misses!==4) $fatal(1,"TEST FAILED: shared control");
        begin_scenario(0);
        for (i=0;i<4;i=i+1) access_line(1,i,0);
        access_line(0,100,0); // secret 1: victim evicts oldest spy line
        access_line(1,0,0);
        if (hits!==0 || misses!==5) $fatal(1,"TEST FAILED: shared leak");
        begin_scenario(1);
        for (i=0;i<2;i=i+1) access_line(1,i,0);
        access_line(1,0,1); // secret 0
        if (hits!==1 || misses!==2) $fatal(1,"TEST FAILED: partition control");
        begin_scenario(1);
        for (i=0;i<2;i=i+1) access_line(1,i,0);
        for (i=0;i<5;i=i+1) access_line(0,100+i,0);
        access_line(1,0,1); access_line(1,1,1);
        if (hits!==2 || misses!==2) $fatal(1,"TEST FAILED: partition isolation");
        $display("TEST PASSED"); $finish;
    end
endmodule
