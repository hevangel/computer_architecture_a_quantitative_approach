`timescale 1ns/1ps
module tb_multicycle_microcode_baseline;
    logic clk=0, rst_n=0;
    logic [4:0] dbg_raddr=0;
    logic [31:0] program_rom [0:24];
    wire [31:0] ia [0:2], da [0:2], wd [0:2], dbg [0:2], cycles [0:2], retired [0:2];
    wire [2:0] halted, we;
    wire [31:0] memory0,memory1,memory2;
    logic [31:0] memory [0:2][0:63];
    integer stores [0:2];
    always #5 clk=~clk;
    for (genvar i=0;i<3;i=i+1) begin : cpu
        wire [31:0] inst=(ia[i]<100) ? program_rom[ia[i][6:2]] : 0;
        wire [31:0] data_word=memory[i][da[i][7:2]];
        if(i<2) begin : multicycle
            multicycle_microcode_baseline #(.MICROCODE(i==1)) core(
                clk,rst_n,ia[i],inst,da[i],wd[i],we[i],data_word,dbg_raddr,dbg[i],halted[i],cycles[i],retired[i]);
        end else begin : pipeline
            rv32i_pipeline core(clk,rst_n,ia[i],inst,da[i],wd[i],we[i],data_word,
                dbg_raddr,dbg[i],halted[i],cycles[i],retired[i],,);
        end
        always @(posedge clk) begin
            if (!rst_n) begin
                stores[i]<=0;
                for (integer a=0;a<64;a=a+1) memory[i][a]<=0;
            end else if (we[i]) begin
                memory[i][da[i][7:2]]<=wd[i]; stores[i]<=stores[i]+1;
            end
        end
    end
    initial $readmemh("../../../../appC_pipelining/multicycle_microcode_baseline/program.hex",program_rom);
    integer count;
    initial begin
        repeat(2) @(negedge clk);
        rst_n=1; count=0;
        while (halted!=3'b111 && count<250) begin
            @(negedge clk); count=count+1;
            if (cycles[0]!==cycles[1] || retired[0]!==retired[1] || ia[0]!==ia[1] || we[0]!==we[1] ||
                (we[0] && (da[0]!==da[1] || wd[0]!==wd[1])))
                $fatal(1,"hardwired and microcode cycle mismatch");
        end
        if (halted!=3'b111 || cycles[0]!=197 || cycles[2]!=78 || 2*cycles[0]<5*cycles[2])
            $fatal(1,"elapsed cycles baseline=%0d pipeline=%0d",cycles[0],cycles[2]);
        for(integer i=0;i<3;i=i+1)
            if(retired[i]!=49 || stores[i]!=2 || memory[i][0]!=12 || memory[i][1]!=55)
                $fatal(1,"retirement or memory state");
        for(integer addr=0;addr<64;addr=addr+1)
            if (memory[0][addr]!==memory[2][addr] || memory[1][addr]!==memory[2][addr]) $fatal(1,"memory parity");
        for(integer i=0;i<32;i=i+1) begin
            dbg_raddr=i; #1;
            if (dbg[0]!==dbg[2] || dbg[1]!==dbg[2]) $fatal(1,"register x%0d parity",i);
        end
        $display("197 vs 78 cycles, 49 instructions per core");
        $display("TEST PASSED"); $finish;
    end
endmodule
