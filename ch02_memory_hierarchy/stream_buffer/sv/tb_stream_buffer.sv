`timescale 1ns/1ps
module tb_stream_buffer;
    logic clk=0, reset=1, valid=0;
    logic [31:0] address=0;
    wire rb, rp;
    wire [31:0] db, dp, cb, hb, mb, demand_b, phb, prb, cp, hp, mp, demand_p, php, prp;
    integer i;
    logic [31:0] test_address;
    always #5 clk=~clk;
    stream_buffer baseline(clk,reset,valid,1'b0,address,rb,db,cb,hb,mb,demand_b,phb,prb);
    stream_buffer prefetched(clk,reset,valid,1'b1,address,rp,dp,cp,hp,mp,demand_p,php,prp);
    task automatic run_access(input logic [31:0] addr);
        begin
            address=addr; valid=1; @(negedge clk);
            if (!rb || !rp || db !== (addr ^ 32'ha5c39e71) || dp !== db)
                $fatal(1,"TEST FAILED: data at %h",addr);
        end
    endtask
    initial begin
        @(negedge clk); reset=0;
        for (i=0;i<32;i=i+1) run_access(i);
        if (cb!==32 || cp!==32 || mb!==32 || mp!==32 || demand_b!==32 || demand_p!==1 || php!==31 || prp!==35 ||
            demand_p*10 > demand_b*3)
            $fatal(1,"TEST FAILED: sequential demand reads");
        // The final line is in L1; no buffer access or memory read on repeat.
        run_access(31);
        if (hb!==1 || hp!==1 || demand_p!==1 || php!==31) $fatal(1,"TEST FAILED: L1 hit");
        valid=0; reset=1; @(negedge clk); reset=0;
        for (i=0;i<32;i=i+1) begin
            test_address = (i%2 == 0) ? (i/2) : (16+i/2);
            run_access(test_address);
        end
        if (cb!==32 || cp!==32 || demand_b!==32 || demand_p!==32 || php!==0 || prp!==128)
            $fatal(1,"TEST FAILED: interleaved streams");
        $display("TEST PASSED"); $finish;
    end
endmodule
