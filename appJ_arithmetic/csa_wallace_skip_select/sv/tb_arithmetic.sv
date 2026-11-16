`timescale 1ns/1ps
module tb_arithmetic;
    logic [15:0] a, b;
    logic cin;
    wire [15:0] skip_sum, select_sum, product;
    wire skip_cout, select_cout;
    logic [16:0] expected;
    integer x, y, k;
    logic [31:0] random_state;
    carry_skip16 skip_dut(a, b, cin, skip_sum, skip_cout);
    carry_select16 select_dut(a, b, cin, select_sum, select_cout);
    wallace8 multiply_dut(a[7:0], b[7:0], product);
    initial begin
        a = 0; b = 0; cin = 0;
        for (x = 0; x < 256; x = x + 1) begin
            for (y = 0; y < 256; y = y + 1) begin
                a = x; b = y; cin = (x + y) & 1;
                #1;
                expected = x + y + cin;
                if (product !== x*y || {skip_cout, skip_sum} !== expected ||
                    {select_cout, select_sum} !== expected) $fatal(1, "TEST FAILED: %0d %0d", x, y);
            end
        end
        random_state = 32'h12345678;
        for (k = 0; k < 10000; k = k + 1) begin
            random_state = random_state * 32'd1664525 + 32'd1013904223; a = random_state[15:0];
            random_state = random_state * 32'd1664525 + 32'd1013904223; b = random_state[31:16];
            cin = k & 1; #1;
            expected = {1'b0,a} + {1'b0,b} + cin;
            if ({skip_cout, skip_sum} !== expected || {select_cout, select_sum} !== expected)
                $fatal(1, "TEST FAILED: carry case %0d", k);
        end
        a = 16'hffff; b = 16'h0000; cin = 1; #1;
        if ({skip_cout,skip_sum} !== 17'h10000 || {select_cout,select_sum} !== 17'h10000)
            $fatal(1, "TEST FAILED: full carry chain");
        $display("TEST PASSED"); $finish;
    end
endmodule
