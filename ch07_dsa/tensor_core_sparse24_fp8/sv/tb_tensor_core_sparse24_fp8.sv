`timescale 1ns/1ps
module tb_tensor_core_sparse24_fp8;
    logic clk=0, reset=1, start=0, sparse=0;
    logic [1:0] format=0;
    logic signed [7:0] scale_a=0, scale_b=0;
    logic [255:0] a_tile=0, dense_weights=0;
    logic [511:0] c_tile=0;
    logic [15:0] indices=0;
    logic [127:0] sparse_weights=0;
    wire weight_read, busy, done, error;
    wire [1:0] weight_slot;
    wire [63:0] weights = sparse ? sparse_weights[64*weight_slot +: 64] :
                                   dense_weights[64*weight_slot +: 64];
    wire [2:0] compute_cycles;
    wire [4:0] weight_reads, flags;
    wire [511:0] d_tile;
    tensor_core_sparse24_fp8 dut(.*);
    always #5 clk=~clk;
    task tick;
        @(posedge clk); #1;
    endtask
    integer fd, rc, fmt, sa, sb, cases_run, mode, reads, beats;
    logic [7:0] expected_flags;
    logic [511:0] expected_d;
    initial begin
        fd=$fopen("../../../../ch07_dsa/tensor_core_sparse24_fp8/vectors.txt","r");
        if (!fd) $fatal(1,"missing vectors");
        tick; reset=0; cases_run=0;
        while (!$feof(fd)) begin
            rc=$fscanf(fd,"%d %d %d %h %h %h %h %h %h %h\n",fmt,sa,sb,a_tile,c_tile,
                       dense_weights,sparse_weights,indices,expected_d,expected_flags);
            if (rc==10) begin
                format=fmt; scale_a=sa; scale_b=sb;
                for (mode=0; mode<2; mode=mode+1) begin
                    sparse=mode; start=1; tick; start=0;
                    reads=0; beats=0;
                    while (busy && beats<5) begin
                        if (!weight_read || weight_slot!=beats) $fatal(1,"weight address");
                        reads=reads+4; beats=beats+1; tick;
                    end
                    if (!done || error || weight_read || d_tile!==expected_d || flags!==expected_flags[4:0])
                        $fatal(1,"tile mismatch case %0d sparse %0d",cases_run,mode);
                    if (beats!=(mode ? 2 : 4) || compute_cycles!=beats || weight_reads!=reads)
                        $fatal(1,"wrong compute or read count");
                end
                cases_run=cases_run+1;
            end else if (rc!=-1) $fatal(1,"bad vector data");
        end
        indices[3:0]=4'b0101; sparse=1; start=1; tick; start=0;
        if (!done || !error || busy || weight_read || weight_reads!=0 || d_tile!==c_tile)
            $fatal(1,"duplicate metadata accepted");
        indices[3:0]=4'b0110; start=1; tick; start=0;
        if (!done || !error || busy || weight_read || compute_cycles!=0) $fatal(1,"descending metadata accepted");
        sparse=0; format=0; start=1; tick; start=0;
        if (!done || !error || busy || weight_read) $fatal(1,"unsupported input format accepted");
        tick;
        if (done || cases_run!=30) $fatal(1,"done or case count");
        $display("TEST PASSED (%0d dense/sparse pairs)",cases_run);
        $finish;
    end
endmodule
