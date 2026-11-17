`timescale 1ns/1ps
module tb_cpi_power_counters;
    logic clk=0, reset=1;
    logic [1:0] kind=0;
    logic [31:0] data_word=0;
    logic retire_base=0, stall_base=0, retire_fast=0, stall_fast=0, gate=0;
    wire [31:0] cycles_b, retired_b, stalls_b, toggles_b, cycles_f, retired_f, stalls_f, toggles_f;
    wire [127:0] retired_classes_b, stall_classes_b, retired_classes_f, stall_classes_f;
    wire [47:0] cpi_b, cpi_f;
    wire [63:0] dyn_b, stat_b, power_b, dyn_f, stat_f, power_f;
    integer i;
    always #5 clk = ~clk;
    cpi_power_counters baseline(clk,reset,retire_base,kind,stall_base,kind,1'b1,data_word,
        cycles_b,retired_b,stalls_b,toggles_b,retired_classes_b,stall_classes_b,cpi_b,dyn_b,stat_b,power_b);
    cpi_power_counters improved(clk,reset,retire_fast,kind,stall_fast,kind,gate,data_word,
        cycles_f,retired_f,stalls_f,toggles_f,retired_classes_f,stall_classes_f,cpi_f,dyn_f,stat_f,power_f);
    initial begin
        @(negedge clk); reset=0;
        for (i=0;i<10;i=i+1) begin
            kind = i % 4; data_word = (i%2 == 0) ? 32'hffffffff : 0;
            retire_base = i<6; stall_base = i>=6;
            retire_fast = i<8; stall_fast = i>=8;
            gate = (i%4)<2;
            @(negedge clk);
        end
        if (cycles_b !== 10 || retired_b !== 6 || stalls_b !== 4 || cpi_b !== 109226 ||
            cycles_f !== 10 || retired_f !== 8 || stalls_f !== 2 || cpi_f !== 81920)
            $fatal(1,"TEST FAILED: CPI counts");
        if (retired_classes_b !== {32'd1,32'd1,32'd2,32'd2} ||
            stall_classes_b !== {32'd1,32'd1,32'd1,32'd1} ||
            retired_classes_f !== {32'd2,32'd2,32'd2,32'd2} ||
            stall_classes_f !== {32'd0,32'd0,32'd1,32'd1})
            $fatal(1,"TEST FAILED: class counts");
        if (toggles_b !== 320 || toggles_f !== 192 || dyn_b !== 64'd20971520 || dyn_f !== 64'd12582912 ||
            stat_b !== 64'd163840 || stat_f !== 64'd163840 || power_b !== 64'd2113536 || power_f !== 64'd2113536 ||
            dyn_f * 10 > dyn_b * 7)
            $fatal(1,"TEST FAILED: energy counts");
        $display("TEST PASSED"); $finish;
    end
endmodule
