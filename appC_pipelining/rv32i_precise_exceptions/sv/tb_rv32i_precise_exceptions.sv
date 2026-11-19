`timescale 1ns/1ps
module tb_rv32i_precise_exceptions;
    logic clk=0, rst_n=0, irq=0;
    logic [31:0] imem_rdata;
    wire [31:0] imem_addr,dmem_addr,dmem_wdata,store_addr,mepc,mcause,dbg_rdata;
    wire dmem_we,halted,trap,fault_overlap;
    wire [31:0] stat_cycles,stat_retired,stat_load_stalls,stat_flushes;
    logic [4:0] dbg_raddr=0;
    logic [31:0] memory [0:1];
    integer test_mode=0;
    wire imem_fault=test_mode==2 && imem_addr==4;
    wire dmem_fault=test_mode==0 && dmem_addr==4;
    wire [31:0] dmem_rdata=memory[dmem_addr[2]];
    rv32i_precise_exceptions dut(.*);
    always #5 clk=~clk;
    always @(posedge clk) begin
        if (!rst_n) begin memory[0]<=0; memory[1]<=0; end
        else if (dmem_we) memory[store_addr[2]]<=dmem_wdata;
    end
    always @* begin
        imem_rdata=32'h00000013;
        case(imem_addr)
            0: imem_rdata=32'h00700093; // addi x1,x0,7
            4: imem_rdata=test_mode==1 ? 32'hffffffff : test_mode==4 ? 32'h00000073 : 32'h00102023;
            8: imem_rdata=test_mode==0 ? 32'h00102223 : 32'h00000013;
            12: imem_rdata=test_mode==0 ? 32'h00000073 : 32'h00000013;
            16: imem_rdata=32'h00900193;
            20: imem_rdata=32'h00100073;
            128: imem_rdata=32'h01000113;
            132: imem_rdata=32'h34111273; // CSRRW x4,mepc,x2
            136: imem_rdata=32'h342012f3; // CSRRW x5,mcause,x0
            140: imem_rdata=32'h30200073;
            144: imem_rdata=32'h06300313; // must be flushed by MRET
            default: ;
        endcase
    end
    task tick;
        @(posedge clk); #1;
    endtask
    task check_reg(input integer reg_id, input logic [31:0] expected);
        dbg_raddr=reg_id; #1;
        if (dbg_rdata!==expected) $fatal(1,"mode %0d x%0d was %h, expected %h",test_mode,reg_id,dbg_rdata,expected);
    endtask

    integer n, count;
    bit saw_overlap;
    logic [31:0] expected_pc,expected_cause;
    initial begin
        for(n=0;n<5;n=n+1) begin
            test_mode=n; rst_n=0; irq=0; tick; rst_n=1;
            expected_pc=(n==0) ? 8 : 4;
            case(n)
                0: expected_cause=7;
                1: expected_cause=2;
                2: expected_cause=1;
                3: expected_cause=32'h8000000b;
                4: expected_cause=11;
            endcase
            if (n==3) begin tick; irq=1; tick; irq=0; end
            count=0; saw_overlap=0;
            while (!trap && count<20) begin
                if (fault_overlap) saw_overlap=1;
                tick; count=count+1;
            end
            if (!trap || mepc!=expected_pc || mcause!=expected_cause || imem_addr!=128)
                $fatal(1,"trap mode %0d mepc=%h cause=%h pc=%h",n,mepc,mcause,imem_addr);
            if (n==0 && (!saw_overlap || memory[0]!=7 || memory[1]!=0 || stat_retired!=2))
                $fatal(1,"two faults did not preserve older effects");
            if (n!=0 && (memory[0]!=0 || memory[1]!=0 || stat_retired!=1))
                $fatal(1,"faulted or younger store committed");
            check_reg(1,7); check_reg(3,0);
            count=0;
            while (!halted && count<80) begin
                tick; count=count+1;
                if (trap) $fatal(1,"unexpected second trap");
            end
            if (!halted || memory[1]!=0) $fatal(1,"resume did not halt cleanly");
            check_reg(3,9); check_reg(4,expected_pc); check_reg(5,expected_cause); check_reg(6,0);
        end
        $display("TEST PASSED"); $finish;
    end
endmodule
