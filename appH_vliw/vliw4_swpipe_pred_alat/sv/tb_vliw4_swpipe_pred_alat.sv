`timescale 1ns/1ps
module tb_vliw4_swpipe_pred_alat;
    logic clk=0,rst_n=0;
    logic [3:0] dbg_raddr=0;
    logic [127:0] rom [0:95];
    logic [31:0] memory [0:63],base_memory [0:63];
    wire [31:0] imem_addr,dmem_addr,dmem_wdata,dbg_rdata,bundles,ops,alat_failures;
    wire [31:0] base_pc,base_addr,base_value,base_bundles,base_ops;
    wire dbg_nat,halted,dmem_we,base_we,base_halted;
    wire [2:0] trap_cause;
    integer program_id=1;
    wire [127:0] imem_rdata=rom[16*program_id+imem_addr[3:0]];
    wire [31:0] dmem_rdata=memory[dmem_addr[7:2]];
    wire dmem_fault=dmem_addr>=256;
    wire [127:0] base_instruction=rom[base_pc[3:0]];
    wire [31:0] base_data=base_memory[base_addr[7:2]];
    vliw4_swpipe_pred_alat dut(.*);
    vliw4 baseline(clk,rst_n,base_pc,base_instruction,base_addr,base_value,base_we,base_data,dbg_raddr,
                   ,base_halted,base_bundles,base_ops);
    always #5 clk=~clk;
    always @(posedge clk) begin
        if (!rst_n) begin
            for(integer i=0;i<64;i=i+1) begin memory[i]<=0; base_memory[i]<=0; end
            for(integer i=0;i<8;i=i+1) begin
                memory[i]<=i+1; base_memory[i]<=i+1;
                memory[16+i]<=100*i; base_memory[16+i]<=100*i;
            end
        end else begin
            if (dmem_we) memory[dmem_addr[7:2]]<=dmem_wdata;
            if (base_we) base_memory[base_addr[7:2]]<=base_value;
        end
    end
    task tick;
        @(posedge clk); #1;
    endtask
    task run_case(input integer id);
        integer elapsed;
        begin
            program_id=id; rst_n=0; tick; rst_n=1; elapsed=0;
            while ((!halted || !base_halted) && elapsed<80) begin tick; elapsed=elapsed+1; end
            if (!halted || !base_halted) $fatal(1,"timeout id %0d pc=%h base_pc=%h halt=%b/%b ops=%d reg5=%h",id,imem_addr,base_pc,halted,base_halted,ops,dut.regs[5]);
        end
    endtask
    initial begin
        $readmemh("../../../../appH_vliw/vliw4_swpipe_pred_alat/programs.hex",rom);
        run_case(1);
        if (base_bundles!=31 || base_ops!=60 || bundles!=29 || ops*base_bundles<=base_ops*bundles || trap_cause!=0)
            $fatal(1,"kernel schedule/IPC %0d/%0d vs %0d/%0d",ops,bundles,base_ops,base_bundles);
        for(integer i=0;i<8;i=i+1)
            if (memory[16+i]!=103*i+3 || base_memory[16+i]!=memory[16+i]) $fatal(1,"DAXPY result");
        $display("DAXPY ops/bundles: %0d/%0d versus %0d/%0d",ops,bundles,base_ops,base_bundles);
        run_case(2);
        if (memory[16]!=3 || memory[17]!=100 || trap_cause!=0) $fatal(1,"short prologue/epilogue");
        run_case(3); dbg_raddr=4; #1;
        if (trap_cause!=0 || !dbg_nat || memory[25]!=0) $fatal(1,"suppressed load/check/store");
        run_case(4); dbg_raddr=2; #1;
        if (trap_cause!=2 || dbg_rdata!=0 || memory[25]!=0) $fatal(1,"NaT must trap before same-bundle side effects");
        run_case(5); dbg_raddr=2; #1;
        if(trap_cause!=0 || alat_failures!=2 || dbg_rdata!=99 || memory[0]!=42 || memory[5]!=42)
            $fatal(1,"ALAT overlap/replacement");
        $display("TEST PASSED"); $finish;
    end
endmodule
