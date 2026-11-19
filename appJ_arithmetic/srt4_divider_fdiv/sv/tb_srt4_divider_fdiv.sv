`timescale 1ns/1ps
module tb_srt4_divider_fdiv;
    logic clk=0, reset=1, start=0;
    logic [31:0] numerator=0, denominator=0;
    wire busy, done, divide_by_zero, fault_hit, buggy_busy, buggy_done, buggy_dz, buggy_fault;
    wire [31:0] quotient, remainder, buggy_q, buggy_r;
    wire signed [65:0] mantissa, buggy_m;
    wire signed [6:0] exponent, buggy_e;
    srt4_divider_fdiv good(.*);
    srt4_divider_fdiv #(.PENTIUM_FDIV_BUG(1)) bad(clk,reset,start,numerator,denominator,
        buggy_busy,buggy_done,buggy_dz,buggy_fault,buggy_q,buggy_r,buggy_m,buggy_e);
    always #5 clk=~clk;
    task tick;
        @(posedge clk); #1;
    endtask
    integer source, status, n, latency, expected_e;
    logic [31:0] expected_q, expected_r;
    logic [71:0] expected_m;
    initial begin
        source=$fopen("../../../../appJ_arithmetic/srt4_divider_fdiv/vectors.txt","r");
        if (!source) $fatal(1,"vector file");
        tick; reset=0; n=0;
        while (!$feof(source)) begin
            status=$fscanf(source,"%h %h %h %h %h %d\n",numerator,denominator,expected_q,expected_r,expected_m,expected_e);
            if (status==6) begin
                start=1; tick; start=0; latency=0;
                while (!done && latency<34) begin
                    if (!busy || !buggy_busy || buggy_done) $fatal(1,"busy mismatch");
                    tick; latency=latency+1;
                end
                if (!done || !buggy_done || busy || buggy_busy || (latency!=((numerator==0 || denominator==0) ? 0 : 33)))
                    $fatal(1,"radix-4 cadence");
                if (quotient!==expected_q || remainder!==expected_r || mantissa!==expected_m[65:0] ||
                    int'(exponent)!=expected_e || divide_by_zero!=(denominator==0) || fault_hit)
                    $fatal(1,"vector %0d expected %h/%h/%h got %h/%h/%h",n,expected_q,expected_r,expected_m,quotient,remainder,mantissa);
                if (n==0 && (!buggy_fault || buggy_m==mantissa)) $fatal(1,"missing FDIV precision loss");
                if (!buggy_fault && (buggy_q!=quotient || buggy_r!=remainder || buggy_m!=mantissa || buggy_e!=exponent || buggy_dz!=divide_by_zero))
                    $fatal(1,"fault changed an unaffected vector");
                n=n+1;
            end else if (status!=-1) $fatal(1,"invalid vector format");
        end
        if (n!=577) $fatal(1,"wrong vector count");
        tick;
        if (done || buggy_done) $fatal(1,"response not a pulse");
        $display("TEST PASSED (%0d vectors)",n);
        $finish;
    end
endmodule
